/*
 * NPIPX.COM: IPX for DOS games, on top of a packet driver (SPEC.md 15.5).
 *
 * It offers the Novell IPX programming interface that DOS network games use
 * (the far call entry from INT 2Fh AX=7A00h, and INT 7Ah): sockets, send,
 * listen, cancel, the timed events (AES), ESR call-backs, the local address.
 * No SPX. Frames go out as Ethernet II type 8137; Ethernet II, raw 802.3 and
 * 802.2 IPX frames are taken in. Everyone is on network 0, so the immediate
 * address of a node is its node address.
 *
 * Written for the MiSTer ao486 core's NE2000 card with the Crynwr packet
 * driver, where Intel's PDIPX passes no received packet on to the programs.
 *
 *   NPIPX          load (once; refuses when an IPX is already there)
 *
 * Licence: GNU GPL version 2 or later.
 *
 * Open Watcom, tiny model (.COM), compiled with -zu: the code runs on the
 * caller's stack (API calls, the INT 21h hook) or on its own (packet driver
 * receive, timer), so it never takes the address of a local.
 */
#include <dos.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#pragma pack(push, 1)
typedef struct {
    void __far    *addr;
    unsigned short size;
} Frag;

typedef struct Ecb {
    struct Ecb __far *link;
    void __far    *esr;
    unsigned char  inuse, ccode;
    unsigned short socket;              /* network order */
    unsigned short ticks, ipxwork2;     /* IPX workspace: AES countdown */
    unsigned short owner;               /* driver workspace: owner PSP (AES) */
    unsigned char  drvwork[10];
    unsigned char  immaddr[6];
    unsigned short fragcount;
    Frag           frag[1];
} Ecb;

typedef struct {
    unsigned short checksum, length;    /* network order */
    unsigned char  tc, type;
    unsigned char  dnet[4], dnode[6];
    unsigned short dsock;
    unsigned char  snet[4], snode[6];
    unsigned short ssock;
} IpxHdr;
#pragma pack(pop)

#define MAXSOCK  32
#define FRAMEMAX 1514
#define IPXMAX   (FRAMEMAX - 14)

/* ---------------------------------------------------------- resident data */

static unsigned short sock_num[MAXSOCK];        /* network order, 0 = free */
static unsigned short sock_owner[MAXSOCK];      /* PSP of a short-lived socket, 0 = long-lived */
static Ecb __far     *sock_head[MAXSOCK];
static Ecb __far     *aes_head;
static unsigned short next_dyn = 0x4000;

static unsigned char  my_mac[6];
static void __far    *pkt_entry;                /* the packet driver's interrupt handler */
static unsigned short __far *cur_psp;           /* DOS swappable data area: current PSP */

static unsigned char  txbuf[FRAMEMAX + 46];
static unsigned char  rxbuf[FRAMEMAX];
static unsigned short rx_len;
static unsigned char  rx_busy, in_timer;

static void __far *old2f;
static void __far *old7a;
static void __far *old1c;
static void __far *old21;

/* registers of the API call being served (the glue keeps outer ones safe) */
static unsigned short r_ax, r_bx, r_cx, r_dx, r_si, r_di, r_es;

static unsigned char rx_stack[1024];
static unsigned char tm_stack[1024];
static unsigned short save_ss, save_sp, tsave_ss, tsave_sp;

/* ----------------------------------------------------------------- helpers */

static unsigned short swap16(unsigned short v)
{
    return (unsigned short)((v << 8) | (v >> 8));
}

static int mac_eq(const unsigned char __far *a, const unsigned char __far *b)
{
    return _fmemcmp(a, b, 6) == 0;
}

static int all_ff(const unsigned char __far *a)
{
    int i;
    for (i = 0; i < 6; i++)
        if (a[i] != 0xFF) return 0;
    return 1;
}

static int find_sock(unsigned short s)
{
    int i;
    if (!s) return -1;
    for (i = 0; i < MAXSOCK; i++)
        if (sock_num[i] == s) return i;
    return -1;
}

/* the ESR: ES:SI = ECB, AL = FFh from IPX, 00h from AES; interrupts off */
static void call_esr(Ecb __far *e, unsigned char from)
{
    unsigned short sseg, soff, eseg, eoff;
    if (!e->esr) return;
    sseg = FP_SEG(e->esr); soff = FP_OFF(e->esr);
    eseg = FP_SEG(e);      eoff = FP_OFF(e);
    _asm {
        push ds
        push bp
        push si
        push di
        push es
        mov  ax, sseg
        push ax
        mov  ax, soff
        push ax
        mov  cx, eseg
        mov  dx, eoff
        mov  al, from
        mov  es, cx
        mov  si, dx
        mov  bp, sp
        cli
        call dword ptr [bp]
        cli
        add  sp, 4
        pop  es
        pop  di
        pop  si
        pop  bp
        pop  ds
    }
}

/* unlink e from a list; 1 when it was there */
static int unlink_ecb(Ecb __far * __far *head, Ecb __far *e)
{
    Ecb __far * __far *p = head;
    while (*p) {
        if (*p == e) { *p = e->link; e->link = 0; return 1; }
        p = &(*p)->link;
    }
    return 0;
}

static void append_ecb(Ecb __far * __far *head, Ecb __far *e)
{
    Ecb __far * __far *p = head;
    e->link = 0;
    while (*p) p = &(*p)->link;
    *p = e;
}

static void close_slot(int i)
{
    while (sock_head[i]) {                      /* cancelled, no ESR */
        Ecb __far *e = sock_head[i];
        sock_head[i] = e->link;
        e->link = 0;
        e->inuse = 0;
        e->ccode = 0xFC;
    }
    sock_num[i] = 0;
    sock_owner[i] = 0;
}

/* --------------------------------------------------------------- receiving */

/* hand a received IPX packet to the first listener on its socket */
static void deliver(unsigned char __far *ipx, unsigned short len, unsigned char __far *from)
{
    IpxHdr __far *h = (IpxHdr __far *)ipx;
    unsigned short n, left, k;
    int i;
    Ecb __far *e;

    if (len < sizeof(IpxHdr)) return;
    n = swap16(h->length);
    if (n < sizeof(IpxHdr)) return;
    if (n > len) n = len;
    if (!all_ff(h->dnode) && !mac_eq(h->dnode, my_mac)) return;
    i = find_sock(h->dsock);
    if (i < 0 || !(e = sock_head[i])) return;   /* nobody listening: dropped */
    sock_head[i] = e->link;
    e->link = 0;

    left = n;
    for (k = 0; k < e->fragcount && left; k++) {
        unsigned short c = e->frag[k].size < left ? e->frag[k].size : left;
        _fmemcpy(e->frag[k].addr, ipx, c);
        ipx += c;
        left -= c;
    }
    _fmemcpy(e->immaddr, from, 6);
    e->ccode = left ? 0xFD : 0x00;              /* FD: did not fit */
    e->inuse = 0;
    call_esr(e, 0xFF);
}

static void rx_frame(void)
{
    unsigned char *f = rxbuf;
    unsigned short type = (unsigned short)((f[12] << 8) | f[13]);
    if (rx_len < 14 + sizeof(IpxHdr) || mac_eq(f + 6, my_mac)) return;
    if (type == 0x8137)
        deliver(f + 14, rx_len - 14, f + 6);
    else if (type <= 1500 && f[14] == 0xFF && f[15] == 0xFF)      /* raw 802.3 */
        deliver(f + 14, rx_len - 14, f + 6);
    else if (type <= 1500 && f[14] == 0xE0 && f[15] == 0xE0)      /* 802.2 */
        deliver(f + 17, rx_len - 17, f + 6);
}

/* Packet driver receive call-back. AX=0: give a buffer for CX bytes in
 * ES:DI (0:0 = no thanks); AX=1: the frame is in it. */
void __declspec(naked) receiver(void)
{
    _asm {
        or   ax, ax
        jnz  copied
        cmp  cx, FRAMEMAX
        ja   refuse
        cmp  byte ptr cs:rx_busy, 0
        jne  refuse
        mov  byte ptr cs:rx_busy, 1
        mov  word ptr cs:rx_len, cx
        push cs
        pop  es
        mov  di, offset rxbuf
        retf
    refuse:
        xor  di, di
        mov  es, di
        retf
    copied:
        pushf
        cli
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        push cs
        pop  ds
        mov  save_ss, ss
        mov  save_sp, sp
        push cs
        pop  ss
        mov  sp, offset rx_stack + 1024
        call rx_frame
        mov  ss, save_ss
        mov  sp, save_sp
        mov  byte ptr rx_busy, 0
        pop  es
        pop  ds
        pop  bp
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        popf
        retf
    }
}

/* ----------------------------------------------------------------- sending */

static int pkt_send(unsigned short len)
{
    unsigned short failed = 0;
    unsigned short pseg = FP_SEG(pkt_entry), poff = FP_OFF(pkt_entry);
    _asm {
        push ds
        push si
        push di
        push bp
        push es
        mov  cx, len
        mov  ax, pseg
        push ax
        mov  ax, poff
        push ax
        mov  bp, sp
        mov  si, offset txbuf
        mov  ah, 4
        pushf
        call dword ptr [bp]         ; INT to the packet driver: send_pkt
        cli
        mov  ax, 0
        adc  ax, 0
        add  sp, 4
        pop  es
        pop  bp
        pop  di
        pop  si
        pop  ds
        mov  failed, ax
    }
    return !failed;
}

static void send_packet(Ecb __far *e)
{
    unsigned short len = 0, k;
    IpxHdr *h = (IpxHdr *)(txbuf + 14);
    unsigned char *p = txbuf + 14;
    int ok = 1;

    e->inuse = 0xFF;
    for (k = 0; k < e->fragcount; k++) {
        unsigned short c = e->frag[k].size;
        if (len + c > IPXMAX) { ok = 0; break; }
        _fmemcpy(p, e->frag[k].addr, c);
        p += c;
        len += c;
    }
    if (!ok || len < sizeof(IpxHdr)) {
        e->inuse = 0;
        e->ccode = 0xFD;                        /* malformed */
        call_esr(e, 0xFF);
        return;
    }
    h->checksum = 0xFFFF;
    h->length = swap16(len);
    h->tc = 0;
    memset(h->snet, 0, 4);
    memcpy(h->snode, my_mac, 6);
    h->ssock = e->socket;
    if (e->fragcount && e->frag[0].size >= sizeof(IpxHdr))   /* as IPX does */
        _fmemcpy(e->frag[0].addr, h, sizeof(IpxHdr));

    if (mac_eq(e->immaddr, my_mac)) {           /* to ourselves */
        deliver(txbuf + 14, len, my_mac);
    } else {
        _fmemcpy(txbuf, e->immaddr, 6);
        memcpy(txbuf + 6, my_mac, 6);
        txbuf[12] = 0x81;
        txbuf[13] = 0x37;
        len += 14;
        if (len < 60) { memset(txbuf + len, 0, 60 - len); len = 60; }
        ok = pkt_send(len);
    }
    e->inuse = 0;
    e->ccode = ok ? 0x00 : 0xFF;
    call_esr(e, 0xFF);
}

/* --------------------------------------------------------------- the API */

static void api_open(unsigned short in_ax)
{
    unsigned short s = r_dx;
    int i, free = -1;
    if (!s) {                                   /* a dynamic socket */
        for (;;) {
            s = swap16(next_dyn);
            if (++next_dyn > 0x7FFF) next_dyn = 0x4000;
            if (find_sock(s) < 0) break;
        }
    }
    if (find_sock(s) >= 0) { r_ax |= 0xFF; return; }
    for (i = 0; i < MAXSOCK; i++)
        if (!sock_num[i]) { free = i; break; }
    if (free < 0) { r_ax |= 0xFE; return; }
    sock_num[free] = s;
    sock_head[free] = 0;
    if ((in_ax & 0xFF) == 0xFF) sock_owner[free] = 0;          /* long-lived */
    else sock_owner[free] = cur_psp && *cur_psp ? *cur_psp : 1;
    r_dx = s;
}

static void api_cancel(Ecb __far *e)
{
    int i;
    if (!e->inuse) { r_ax |= 0xFF; return; }
    for (i = 0; i < MAXSOCK; i++)
        if (sock_num[i] && unlink_ecb(&sock_head[i], e)) goto done;
    if (unlink_ecb(&aes_head, e)) goto done;
    r_ax |= 0xF9;                               /* cannot be cancelled */
    return;
done:
    e->inuse = 0;
    e->ccode = 0xFC;
}

static void api(void)
{
    Ecb __far *e = (Ecb __far *)MK_FP(r_es, r_si);
    unsigned short in_ax = r_ax;
    int i;

    r_ax &= 0xFF00;                             /* AL = 0: done (Doom checks it after a send) */
    switch (r_bx & 0xFF) {
    case 0x00:                                  /* open socket */
        api_open(in_ax);
        break;
    case 0x01:                                  /* close socket */
        if ((i = find_sock(r_dx)) >= 0) close_slot(i);
        break;
    case 0x02: {                                /* get local target */
        unsigned char __far *addr = (unsigned char __far *)MK_FP(r_es, r_si);
        unsigned char __far *imm = (unsigned char __far *)MK_FP(r_es, r_di);
        _fmemcpy(imm, addr + 4, 6);
        r_cx = 1;
        break;
    }
    case 0x03:                                  /* send packet */
        send_packet(e);
        break;
    case 0x04:                                  /* listen for packet */
        if ((i = find_sock(e->socket)) < 0) {
            e->inuse = 0;
            e->ccode = 0xFF;
            r_ax |= 0xFF;
            break;
        }
        e->inuse = 0xFE;
        e->ccode = 0;
        append_ecb(&sock_head[i], e);
        break;
    case 0x05:                                  /* schedule IPX event */
    case 0x07:                                  /* schedule special event */
        unlink_ecb(&aes_head, e);
        e->inuse = 0xFD;
        e->ccode = 0;
        e->ticks = in_ax ? in_ax : 1;
        e->owner = cur_psp ? *cur_psp : 0;
        append_ecb(&aes_head, e);
        break;
    case 0x06:                                  /* cancel event */
        api_cancel(e);
        break;
    case 0x08:                                  /* interval marker */
        r_ax = *(unsigned short __far *)MK_FP(0x40, 0x6C);
        break;
    case 0x09: {                                /* internetwork address */
        unsigned char __far *a = (unsigned char __far *)MK_FP(r_es, r_si);
        _fmemset(a, 0, 4);
        _fmemcpy(a + 4, my_mac, 6);
        break;
    }
    case 0x0A:                                  /* relinquish control */
    case 0x0B:                                  /* disconnect from target */
        break;
    case 0x0D:                                  /* packet size */
    case 0x1A:                                  /* maximum packet size */
        r_ax = IPXMAX;
        r_cx = 0;
        break;
    case 0x10:                                  /* SPX installed? no (AL = 0) */
        break;
    default:
        break;
    }
}

/* The API glue: registers in and out through r_*, the outer call's r_* kept
 * on the stack (an ESR may call IPX from inside IPX). Interrupts stay off. */
void __declspec(naked) api_glue(void)
{
    _asm {
        cli
        push ds
        push cs
        pop  ds
        push r_ax
        push r_bx
        push r_cx
        push r_dx
        push r_si
        push r_di
        push r_es
        mov  r_ax, ax
        mov  r_bx, bx
        mov  r_cx, cx
        mov  r_dx, dx
        mov  r_si, si
        mov  r_di, di
        mov  r_es, es
        push bp
        call api
        pop  bp
        mov  ax, r_ax
        mov  bx, r_bx
        mov  cx, r_cx
        mov  dx, r_dx
        mov  si, r_si
        mov  di, r_di
        mov  es, r_es
        pop  r_es
        pop  r_di
        pop  r_si
        pop  r_dx
        pop  r_cx
        pop  r_bx
        pop  r_ax
        pop  ds
        ret
    }
}

/* the far call entry (INT 2Fh AX=7A00h gives it) */
void __declspec(naked) ipx_far(void)
{
    _asm {
        pushf
        call api_glue
        popf
        retf
    }
}

/* INT 7Ah: the same functions */
void __declspec(naked) int7a(void)
{
    _asm {
        call api_glue
        iret
    }
}

/* INT 2Fh AX=7A00h: IPX installed, ES:DI = entry */
void __declspec(naked) int2f(void)
{
    _asm {
        cmp  ax, 7A00h
        jne  chain
        mov  al, 0FFh
        push cs
        pop  es
        mov  di, offset ipx_far
        iret
    chain:
        jmp  dword ptr cs:old2f
    }
}

/* ------------------------------------------------------- timed events (AES) */

static void timer_tick(void)
{
    Ecb __far * __far *p = &aes_head;
    while (*p) {
        Ecb __far *e = *p;
        if (e->ticks > 1) { e->ticks--; p = &e->link; continue; }
        *p = e->link;                           /* due: off the list, then the ESR */
        e->link = 0;
        e->inuse = 0;
        e->ccode = 0;
        call_esr(e, 0x00);
        p = &aes_head;                          /* the ESR may have changed the list */
    }
}

void __declspec(naked) int1c(void)
{
    _asm {
        pushf
        call dword ptr cs:old1c
        cli
        cmp  byte ptr cs:in_timer, 0
        jne  tdone
        mov  byte ptr cs:in_timer, 1
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        push cs
        pop  ds
        mov  tsave_ss, ss
        mov  tsave_sp, sp
        push cs
        pop  ss
        mov  sp, offset tm_stack + 1024
        call timer_tick
        mov  ss, tsave_ss
        mov  sp, tsave_sp
        pop  es
        pop  ds
        pop  bp
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        mov  byte ptr cs:in_timer, 0
    tdone:
        iret
    }
}

/* ---------------------------------------------- a program ends: its sockets */

static void program_ends(void)
{
    unsigned short psp = cur_psp ? *cur_psp : 0;
    Ecb __far * __far *p = &aes_head;
    int i;
    for (i = 0; i < MAXSOCK; i++)
        if (sock_num[i] && sock_owner[i] && (sock_owner[i] == psp || !psp)) close_slot(i);
    while (*p) {                                /* its timed events too */
        Ecb __far *e = *p;
        if (e->owner == psp || !psp) { *p = e->link; e->link = 0; e->inuse = 0; e->ccode = 0xFC; }
        else p = &e->link;
    }
}

void __declspec(naked) int21(void)
{
    _asm {
        cmp  ah, 4Ch
        je   prgend
        cmp  ah, 0
        je   prgend
        jmp  dword ptr cs:old21
    prgend:
        pushf
        cli
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        push cs
        pop  ds
        call program_ends
        pop  es
        pop  ds
        pop  bp
        pop  di
        pop  si
        pop  dx
        pop  cx
        pop  bx
        pop  ax
        popf
        jmp  dword ptr cs:old21
    }
}

/* ------------------------------------------------------------- installing */

static unsigned char ip_type[2] = { 0x81, 0x37 };
static unsigned char raw_type[2] = { 0xFF, 0xFF };
static union REGS rg;
static struct SREGS sr;
static unsigned short myseg;                    /* CS = DS in a .COM */

static int find_packet_driver(void)
{
    int v;
    for (v = 0x60; v <= 0x80; v++) {
        char __far *h = (char __far *)_dos_getvect(v);
        if (h && _fmemcmp(h + 3, "PKT DRVR", 8) == 0) return v;
    }
    return 0;
}

static int access_type(int vec, int cls, unsigned char *type)
{
    segread(&sr);
    rg.h.ah = 2;
    rg.h.al = (unsigned char)cls;
    rg.x.bx = 0xFFFF;
    rg.h.dl = 0;
    rg.x.cx = 2;
    sr.ds = myseg;
    rg.x.si = (unsigned short)type;
    sr.es = myseg;
    rg.x.di = (unsigned short)receiver;
    int86x(vec, &rg, &rg, &sr);
    return !rg.x.cflag;
}

int main(int argc, char **argv)
{
    int vec, i;
    unsigned short paras, sp_now = 0;

    (void)argv;
    segread(&sr);
    myseg = sr.cs;

    printf("NPIPX: IPX for DOS games on a packet driver (MiSTer ao486 netplay)\n");
    if (argc > 1) {
        printf("usage: NPIPX     (loads once; needs a packet driver)\n");
        return 1;
    }
    rg.x.ax = 0x7A00;
    int86(0x2F, &rg, &rg);
    if (rg.h.al == 0xFF) { printf("An IPX driver is already loaded.\n"); return 1; }
    if (!(vec = find_packet_driver())) { printf("No packet driver found (load NE2000.COM first).\n"); return 1; }
    pkt_entry = _dos_getvect(vec);

    if (!access_type(vec, 1, ip_type)) { printf("The packet driver refused IPX frames (type 8137).\n"); return 1; }
    rg.x.bx = rg.x.ax;                          /* our Ethernet address */
    rg.h.ah = 6;
    rg.x.cx = 6;
    segread(&sr);
    sr.es = myseg;
    rg.x.di = (unsigned short)my_mac;
    int86x(vec, &rg, &rg, &sr);
    access_type(vec, 11, raw_type);             /* raw 802.3 IPX too, where offered */

    rg.x.ax = 0x5D06;                           /* DOS swappable data: current PSP */
    int86x(0x21, &rg, &rg, &sr);
    if (!rg.x.cflag) cur_psp = (unsigned short __far *)MK_FP(sr.ds, rg.x.si + 0x10);

    old2f = _dos_getvect(0x2F);
    old7a = _dos_getvect(0x7A);
    old1c = _dos_getvect(0x1C);
    old21 = _dos_getvect(0x21);
    _dos_setvect(0x2F, (void (__interrupt __far *)())MK_FP(myseg, (unsigned short)int2f));
    _dos_setvect(0x7A, (void (__interrupt __far *)())MK_FP(myseg, (unsigned short)int7a));
    _dos_setvect(0x1C, (void (__interrupt __far *)())MK_FP(myseg, (unsigned short)int1c));
    _dos_setvect(0x21, (void (__interrupt __far *)())MK_FP(myseg, (unsigned short)int21));

    printf("Packet driver at 0x%02X, node ", vec);
    for (i = 0; i < 6; i++) printf("%02X%s", my_mac[i], i < 5 ? ":" : "\n");

    _dos_freemem(*(unsigned short __far *)MK_FP(_psp, 0x2C));   /* the environment */
    *(unsigned short __far *)MK_FP(_psp, 0x2C) = 0;
    _asm { mov sp_now, sp }                     /* code, data and stack end below SP */
    paras = sp_now / 16 + 2;
    _dos_keep(0, paras);
    return 0;
}
