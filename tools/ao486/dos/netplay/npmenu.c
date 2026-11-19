/*
 * NPMENU.EXE: the network game menu for the MiSTer ao486 netplay core
 * (SPEC.md 15.5). 16-bit DOS, Open Watcom C, large model.
 *
 *   NPMENU /CHECK      looks for the NE2000 card at 0x300 and the drivers,
 *                      finds the card's IRQ, writes NPLOAD.BAT (the loads
 *                      still needed) and NPIRQ.TXT; exit code 1 = a card
 *   NPMENU             the menu; exit code 0 = go on booting, 2 = run RUN.BAT
 *                      and come back, 3 = stop at the DOS prompt
 *   NPMENU /INSTALL    copies the kit from its own folder to C:\NETPLAY and
 *                      hooks C:\AUTOEXEC.BAT (backup AUTOEXEC.NPB)
 *   NPMENU /BOOT       from AUTOEXEC.BAT: with the card on, online or single
 *                      player (single after 10 s); exit code 1 = online
 *                      (load NPLOAD.BAT, then the menu), 0 = boot on as usual
 *   NPMENU /UNINSTALL  takes the hook out of C:\AUTOEXEC.BAT and deletes
 *                      C:\NETPLAY, C:\NP.BAT and the backup
 *
 * The menu finds the network games of GAMES.INI on the hard disks, starts the
 * chosen one (through RUN.BAT, so the menu is out of memory while it runs),
 * and shows the other players in the room: every menu broadcasts a small IPX
 * packet once a second on socket 0x4E50, so when the room is linked you see
 * your friend, and what they start.
 *
 * Licence: GNU GPL version 2 or later.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <conio.h>
#include <dos.h>
#include <direct.h>
#include <signal.h>
#include <malloc.h>

#define NE_BASE   0x300
#define KIT_DIR   "C:\\NETPLAY"

/* ------------------------------------------------------------------ util */

static char kitdir[80];                 /* where NPMENU.EXE is */

static void kit_path(char *out, const char *name)
{
    sprintf(out, "%s\\%s", kitdir, name);
}

static void trim(char *s)
{
    char *p = s;
    size_t n;
    while (*p == ' ' || *p == '\t') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    n = strlen(s);
    while (n && (s[n - 1] == ' ' || s[n - 1] == '\t' || s[n - 1] == '\r' || s[n - 1] == '\n'))
        s[--n] = 0;
}

static unsigned long ticks(void)        /* BIOS tick counter, 18.2 Hz */
{
    return *(unsigned long __far *)MK_FP(0x40, 0x6C);
}

static void wait_ticks(unsigned n)
{
    unsigned long t = ticks();
    while (ticks() - t < n) ;
}

static int file_exists(const char *path)
{
    struct find_t f;
    return _dos_findfirst(path, _A_NORMAL | _A_RDONLY | _A_HIDDEN | _A_SYSTEM, &f) == 0;
}

static int dir_exists(const char *path)
{
    struct find_t f;
    return _dos_findfirst(path, _A_SUBDIR, &f) == 0 && (f.attrib & _A_SUBDIR);
}

/* ------------------------------------------------------- card and drivers */

/* A packet driver: "PKT DRVR" 3 bytes into its interrupt handler. */
static int find_packet_driver(void)
{
    int v;
    for (v = 0x60; v <= 0x80; v++) {
        char __far *h = (char __far *)_dos_getvect(v);
        if (h && _fmemcmp(h + 3, "PKT DRVR", 8) == 0) return v;
    }
    return 0;
}

static int ipx_installed(void)
{
    union REGS r;
    r.x.ax = 0x7A00;
    int86(0x2F, &r, &r);
    return r.h.al == 0xFF;
}

/* The card is there: a reset sets ISR.RST, and CR reads back what we wrote.
 * Only called when no driver owns the card (a reset would stop it). */
static int card_present(void)
{
    unsigned long t;
    if (inp(NE_BASE) == 0xFF) return 0;
    outp(NE_BASE + 0x1F, inp(NE_BASE + 0x1F));          /* reset */
    t = ticks();
    while (!(inp(NE_BASE + 7) & 0x80))
        if (ticks() - t > 2) return 0;
    outp(NE_BASE + 7, 0xFF);                            /* clear ISR */
    outp(NE_BASE, 0x21);                                /* page 0, stop, no DMA */
    return inp(NE_BASE) == 0x21;
}

static unsigned pic_irr(void)
{
    unsigned lo, hi;
    outp(0x20, 0x0A); lo = inp(0x20);
    outp(0xA0, 0x0A); hi = inp(0xA0);
    return lo | (hi << 8);
}

/* Which line the card interrupts on (OSD: 11, 10, 5 or 3): a remote DMA of
 * zero bytes sets ISR.RDC at once (the Linux ne driver probes the same way);
 * with only IMR.RDC on, the card's line goes high and shows in the PIC's
 * request register while the line is masked. */
static int card_irq(void)
{
    static const int cand[4] = { 11, 10, 5, 3 };
    unsigned m1 = inp(0x21), m2 = inp(0xA1);
    unsigned before, after, i, found = 0;

    _disable();
    outp(0x21, m1 | (1 << 3) | (1 << 5));
    outp(0xA1, m2 | (1 << 2) | (1 << 3));
    _enable();
    outp(NE_BASE + 7, 0xFF);
    outp(NE_BASE + 0x0F, 0x00);
    before = pic_irr();
    outp(NE_BASE + 0x0F, 0x40);                         /* IMR: RDC only */
    outp(NE_BASE + 0x0A, 0);
    outp(NE_BASE + 0x0B, 0);
    outp(NE_BASE, 0x0A);                                /* remote read, start */
    wait_ticks(1);
    after = pic_irr();
    outp(NE_BASE + 0x0F, 0x00);
    outp(NE_BASE + 7, 0xFF);
    outp(NE_BASE, 0x21);
    for (i = 0; i < 4; i++) {
        unsigned bit = 1u << cand[i];
        if ((after & bit) && !(before & bit)) { found = cand[i]; break; }
    }
    wait_ticks(1);
    _disable();
    outp(0x21, m1);
    outp(0xA1, m2);
    _enable();
    return found;
}

/* NPSTATE: NOCARD, CARD (no driver yet), PKT (packet driver, no IPX), IPX */
static const char *net_state(int *irq)
{
    *irq = 0;
    if (find_packet_driver()) return ipx_installed() ? "IPX" : "PKT";
    if (!card_present()) return "NOCARD";
    *irq = card_irq();
    return "CARD";
}

/* Writes NPLOAD.BAT (the driver loads this boot still needs) and NPIRQ.TXT.
 * Nothing goes through the environment: the ready-made disks have no room
 * left in it (SET fails quietly). */
static int write_load(const char *st, int irq)
{
    char path[96];
    FILE *f;
    kit_path(path, "NPLOAD.BAT");
    f = fopen(path, "wb");
    if (!f) { printf("Netplay: cannot write %s\n", path); return 0; }
    fprintf(f, "@ECHO OFF\r\n");
    if (!strcmp(st, "CARD"))
        fprintf(f, "LH %s\\NE2000.COM 0x60 %d 0x300 >NUL\r\n", kitdir, irq ? irq : 11);
    if (!strcmp(st, "CARD") || !strcmp(st, "PKT"))
        fprintf(f, "LH %s\\NPIPX.COM >NUL\r\n", kitdir);
    fclose(f);
    if (irq) {
        kit_path(path, "NPIRQ.TXT");
        if ((f = fopen(path, "wb")) != 0) { fprintf(f, "%d\r\n", irq); fclose(f); }
    }
    return 1;
}

static void announce(const char *st, int irq)
{
    if (!strcmp(st, "NOCARD"))
        printf("Netplay: no network card (ao486 OSD: Hardware, Network On).\n");
    else if (!strcmp(st, "CARD")) {
        if (irq) printf("Netplay: network card at 0x300, IRQ %d: loading the drivers.\n", irq);
        else     printf("Netplay: network card at 0x300, no IRQ seen (trying 11): loading the drivers.\n");
    } else
        printf("Netplay: network drivers already loaded.\n");
}

/* exit code 0 = no card, 1 = card (load NPLOAD.BAT) */
static int do_check(void)
{
    int irq;
    const char *st = net_state(&irq);
    if (!write_load(st, irq)) return 0;
    announce(st, irq);
    return strcmp(st, "NOCARD") != 0;
}

static int do_boot(void);               /* the boot choice, with the screen code */

/* -------------------------------------------------------------- the games */

#define MAXGAMES  64
#define MAXHINT   4
#define MAXFOUND  48

typedef struct {
    char name[40];
    char find[60];
    char need[80];
    char type;                          /* 'i' ipx, 'p' program, 'f' fpu */
    char run[48];
    char args[48];
    char modes[96];
    int  players;
    char hint[MAXHINT][76];
    int  nhint;
} Game;

typedef struct {
    int  game;
    char dir[80];
    char missing[64];                   /* need= files not there */
} Found;

static Game  __far *games;
static int   ngames;
static Found __far *found;
static int   nfound;

static int load_games(void)
{
    char path[96], line[200];
    FILE *f;
    Game __far *g = 0;

    kit_path(path, "GAMES.INI");
    f = fopen(path, "r");
    if (!f) return 0;
    while (fgets(line, sizeof line, f)) {
        char *eq;
        trim(line);
        if (!line[0] || line[0] == ';') continue;
        if (line[0] == '[') {
            char *e = strchr(line, ']');
            if (ngames >= MAXGAMES) break;
            g = &games[ngames++];
            _fmemset(g, 0, sizeof *g);
            if (e) *e = 0;
            _fstrncpy(g->name, line + 1, sizeof g->name - 1);
            g->type = 'p';
            g->players = 2;
            continue;
        }
        if (!g || !(eq = strchr(line, '='))) continue;
        *eq++ = 0;
        trim(line);
        strupr(line);
        if (!strcmp(line, "FIND"))         { strupr(eq); _fstrncpy(g->find, eq, sizeof g->find - 1); }
        else if (!strcmp(line, "NEED"))    { strupr(eq); _fstrncpy(g->need, eq, sizeof g->need - 1); }
        else if (!strcmp(line, "RUN"))     { strupr(eq); _fstrncpy(g->run, eq, sizeof g->run - 1); }
        else if (!strcmp(line, "ARGS"))    _fstrncpy(g->args, eq, sizeof g->args - 1);
        else if (!strcmp(line, "MODES"))   _fstrncpy(g->modes, eq, sizeof g->modes - 1);
        else if (!strcmp(line, "PLAYERS")) { g->players = atoi(eq); if (g->players < 2) g->players = 2; if (g->players > 8) g->players = 8; }
        else if (!strcmp(line, "TYPE"))    g->type = (char)tolower(eq[0]);
        else if (!strcmp(line, "HINT") && g->nhint < MAXHINT)
            _fstrncpy(g->hint[g->nhint++], eq, sizeof g->hint[0] - 1);
    }
    fclose(f);
    return ngames;
}

/* the names in one folder, upper case */
#define MAXNAMES 400
static char (__far *names)[13];
static int nnames;

static int have(const char *n)
{
    int i;
    for (i = 0; i < nnames; i++)
        if (!_fstrcmp(names[i], n)) return 1;
    return 0;
}

/* "A|B" is there when A or B is */
static int have_alt(const char *alts)
{
    char buf[48], *p;
    strncpy(buf, alts, sizeof buf - 1); buf[sizeof buf - 1] = 0;
    for (p = strtok(buf, "|"); p; p = strtok(0, "|"))
        if (have(p)) return 1;
    return 0;
}

static void check_folder(const char *dir)
{
    int gi;
    for (gi = 0; gi < ngames && nfound < MAXFOUND; gi++) {
        char list[80], *p, *save;
        Found __far *fo;
        int ok = 1;
        _fstrcpy(list, games[gi].find);
        if (!list[0]) continue;
        for (p = strtok(list, " "); p; p = strtok(0, " "))
            if (!have(p)) { ok = 0; break; }
        if (!ok) continue;
        fo = &found[nfound++];
        fo->game = gi;
        _fstrncpy(fo->dir, dir, sizeof fo->dir - 1);
        fo->dir[sizeof fo->dir - 1] = 0;
        fo->missing[0] = 0;
        _fstrcpy(list, games[gi].need);
        for (p = list; *p; ) {
            char word[48];
            int n = 0;
            while (*p == ' ') p++;
            while (*p && *p != ' ' && n < 47) word[n++] = *p++;
            word[n] = 0;
            if (n && !have_alt(word)) {
                save = strchr(word, '|');
                if (save) *save = 0;            /* name the first choice */
                if (_fstrlen(fo->missing) + strlen(word) + 2 < sizeof fo->missing) {
                    if (fo->missing[0]) _fstrcat(fo->missing, " ");
                    _fstrcat(fo->missing, word);
                }
            }
        }
    }
}

static int is_skipped(const char *name)
{
    static const char *skip[] = { "WINDOWS", "NETPLAY", "DOS", "MISTER", "DRIVERS", "UTIL", 0 };
    int i;
    for (i = 0; skip[i]; i++)
        if (!strcmp(name, skip[i])) return 1;
    return 0;
}

static void scan_dir(const char *dir, int depth)
{
    static char subs[4][64][13];
    char pat[96], (*sub)[13] = subs[depth];
    struct find_t f;
    int nsub = 0, i;

    sprintf(pat, "%s\\*.*", dir);
    nnames = 0;
    if (_dos_findfirst(pat, _A_NORMAL | _A_RDONLY | _A_HIDDEN | _A_SYSTEM | _A_SUBDIR, &f) == 0) {
        do {
            if (f.name[0] == '.') continue;
            strupr(f.name);
            if (f.attrib & _A_SUBDIR) {
                if (depth < 3 && nsub < 64 && !is_skipped(f.name)) strcpy(sub[nsub++], f.name);
            } else if (nnames < MAXNAMES) {
                _fstrcpy(names[nnames++], f.name);
            }
        } while (_dos_findnext(&f) == 0);
    }
    check_folder(dir);
    for (i = 0; i < nsub; i++) {
        char d[96];
        if (strlen(dir) + strlen(sub[i]) + 2 > 79) continue;
        sprintf(d, "%s\\%s", dir, sub[i]);
        scan_dir(d, depth + 1);
    }
}

/* fixed disks only: no floppies, no CD-ROM (MSCDEX), no network drives */
static int hard_disk(int drive)                 /* 3 = C: */
{
    union REGS r;
    r.x.ax = 0x4408; r.h.bl = (unsigned char)drive;
    intdos(&r, &r);
    if (r.x.cflag || r.x.ax != 1) return 0;
    r.x.ax = 0x4409; r.h.bl = (unsigned char)drive;
    intdos(&r, &r);
    if (r.x.cflag || (r.x.dx & 0x1000)) return 0;
    r.x.ax = 0x150B; r.x.bx = 0; r.x.cx = drive - 1;
    int86(0x2F, &r, &r);
    if (r.x.bx == 0xADAD && r.x.ax) return 0;
    return 1;
}

static void scan_all(void)
{
    int d;
    nfound = 0;
    for (d = 3; d <= 26; d++) {
        char root[3];
        if (!hard_disk(d)) continue;
        root[0] = (char)('A' + d - 1); root[1] = ':'; root[2] = 0;
        scan_dir(root, 0);
    }
}

/* -------------------------------------------------------------------- IPX */

#pragma pack(push, 1)
typedef struct {
    unsigned short checksum, length;
    unsigned char  tc, type;
    unsigned char  dnet[4], dnode[6];
    unsigned short dsock;
    unsigned char  snet[4], snode[6];
    unsigned short ssock;
} IpxHdr;

typedef struct {
    char           magic[4];            /* "NPLB" */
    unsigned char  version, state;      /* state: 0 in the menu, 1 starting a game */
    char           name[16];
    char           game[40];
    char           args[48];
    unsigned short seq;
} Lobby;

typedef struct {
    IpxHdr h;
    Lobby  l;
} Packet;

typedef struct {
    void __far    *link;
    void __far    *esr;
    unsigned char  inuse, ccode;
    unsigned short socket;
    unsigned char  ipxwork[4], drvwork[12];
    unsigned char  immaddr[6];
    unsigned short fragcount;
    void __far    *fragaddr;
    unsigned short fragsize;
} Ecb;
#pragma pack(pop)

#define LOBBY_SOCKET 0x504E             /* 0x4E50 in network order */
#define NRX 4

static unsigned ipx_dx_out;
static int ipx_ok;
static unsigned char my_net[4], my_node[6];
static Ecb rx_ecb[NRX], tx_ecb;
static Packet rx_pkt[NRX], tx_pkt;
static char my_name[16];

/* IPX through INT 7Ah (NPIPX has it; same functions as the far entry) */
static unsigned ipx_call(unsigned fn, unsigned axv, unsigned dxv, void __far *p)
{
    union REGS r;
    struct SREGS sr;
    segread(&sr);
    r.x.bx = fn;
    r.x.ax = axv;
    r.x.dx = dxv;
    sr.es = FP_SEG(p);
    r.x.si = FP_OFF(p);
    int86x(0x7A, &r, &r, &sr);
    ipx_dx_out = r.x.dx;
    return r.x.ax;
}

static void ipx_listen(int i)
{
    Ecb *e = &rx_ecb[i];
    memset(e, 0, sizeof *e);
    e->socket = LOBBY_SOCKET;
    e->fragcount = 1;
    e->fragaddr = &rx_pkt[i];
    e->fragsize = sizeof rx_pkt[i];
    ipx_call(4, 0, 0, e);
}

static void ipx_close(void)
{
    int i;
    unsigned long t = ticks();
    if (!ipx_ok) return;
    while (tx_ecb.inuse && ticks() - t < 9) ipx_call(10, 0, 0, 0);
    for (i = 0; i < NRX; i++)
        if (rx_ecb[i].inuse) ipx_call(6, 0, 0, &rx_ecb[i]);
    if (tx_ecb.inuse) ipx_call(6, 0, 0, &tx_ecb);
    ipx_call(1, 0, LOBBY_SOCKET, 0);
    ipx_ok = 0;
}

static void ipx_open(void)
{
    union REGS r;
    struct SREGS sr;
    unsigned char addr[10];
    int i;

    r.x.ax = 0x7A00;
    int86x(0x2F, &r, &r, &sr);
    if (r.h.al != 0xFF) return;
    {   /* open, short-lived; 0xFF = still open from an earlier menu */
        unsigned rc = ipx_call(0, 0x00, LOBBY_SOCKET, 0) & 0xFF;
        if (rc != 0 && rc != 0xFF) return;
    }
    ipx_call(9, 0, 0, (void __far *)addr);
    memcpy(my_net, addr, 4);
    memcpy(my_node, addr + 4, 6);
    ipx_ok = 1;
    for (i = 0; i < NRX; i++) ipx_listen(i);
}

static unsigned short tx_seq;

static void lobby_send(int state, const char *game, const char *args)
{
    unsigned long t = ticks();
    if (!ipx_ok) return;
    while (tx_ecb.inuse && ticks() - t < 9) ipx_call(10, 0, 0, 0);
    if (tx_ecb.inuse) return;
    memset(&tx_ecb, 0, sizeof tx_ecb);
    memset(&tx_pkt, 0, sizeof tx_pkt);
    tx_ecb.socket = LOBBY_SOCKET;
    memset(tx_ecb.immaddr, 0xFF, 6);
    tx_ecb.fragcount = 1;
    tx_ecb.fragaddr = &tx_pkt;
    tx_ecb.fragsize = sizeof tx_pkt;
    tx_pkt.h.type = 4;
    memcpy(tx_pkt.h.dnet, my_net, 4);
    memset(tx_pkt.h.dnode, 0xFF, 6);
    tx_pkt.h.dsock = LOBBY_SOCKET;
    memcpy(tx_pkt.l.magic, "NPLB", 4);
    tx_pkt.l.version = 1;
    tx_pkt.l.state = (unsigned char)state;
    strncpy(tx_pkt.l.name, my_name, sizeof tx_pkt.l.name - 1);
    if (game) strncpy(tx_pkt.l.game, game, sizeof tx_pkt.l.game - 1);
    if (args) strncpy(tx_pkt.l.args, args, sizeof tx_pkt.l.args - 1);
    tx_pkt.l.seq = ++tx_seq;
    ipx_call(3, 0, 0, &tx_ecb);
}

#define MAXPEERS 8
typedef struct {
    unsigned char node[6];
    char name[16], game[40], args[48];
    int state;
    unsigned long seen, started;        /* ticks */
} Peer;
static Peer peers[MAXPEERS];
static int npeers;

/* returns 1 when something changed */
static int lobby_poll(void)
{
    int i, changed = 0;
    unsigned long now = ticks();
    if (!ipx_ok) return 0;
    ipx_call(10, 0, 0, 0);                              /* relinquish control */
    for (i = 0; i < NRX; i++) {
        Packet *p = &rx_pkt[i];
        if (rx_ecb[i].inuse) continue;
        if (rx_ecb[i].ccode == 0 && !memcmp(p->l.magic, "NPLB", 4) && p->l.version == 1 &&
            memcmp(p->h.snode, my_node, 6)) {
            int k;
            for (k = 0; k < npeers; k++)
                if (!memcmp(peers[k].node, p->h.snode, 6)) break;
            if (k == npeers && npeers < MAXPEERS) { npeers++; memset(&peers[k], 0, sizeof peers[k]); changed = 1; }
            if (k < npeers) {
                Peer *q = &peers[k];
                p->l.name[15] = p->l.game[39] = p->l.args[47] = 0;
                if (strcmp(q->name, p->l.name) || q->state != p->l.state) changed = 1;
                memcpy(q->node, p->h.snode, 6);
                strcpy(q->name, p->l.name);
                q->state = p->l.state;
                if (p->l.state == 0 && q->started) { q->started = 0; changed = 1; }
                if (p->l.state == 1) {
                    if (strcmp(q->game, p->l.game) || strcmp(q->args, p->l.args) || now - q->started > 18 * 5) changed = 1;
                    strcpy(q->game, p->l.game);
                    strcpy(q->args, p->l.args);
                    q->started = now;
                }
                q->seen = now;
            }
        }
        ipx_listen(i);
    }
    for (i = 0; i < npeers; ) {                         /* gone after 5 s, a starter after 60 s */
        unsigned long keep = peers[i].started ? 18UL * 60 : 18UL * 5;
        if (now - peers[i].seen > keep) {
            peers[i] = peers[--npeers];
            changed = 1;
        } else i++;
    }
    return changed;
}

/* ----------------------------------------------------------------- screen */

static unsigned short __far *scr;
enum { C_TITLE = 0x1F, C_TEXT = 0x07, C_DIM = 0x08, C_SEL = 0x70, C_OK = 0x0A,
       C_WARN = 0x0E, C_BAD = 0x0C, C_HEAD = 0x0B, C_KEY = 0x30 };

static void put(int row, int col, int attr, const char *s)
{
    while (*s && col < 80) scr[row * 80 + col++] = (unsigned short)((attr << 8) | (unsigned char)*s++);
}

static void fill(int row, int col, int n, int attr)
{
    while (n-- > 0 && col < 80) scr[row * 80 + col++] = (unsigned short)((attr << 8) | ' ');
}

static void putn(int row, int col, int width, int attr, const char *s)
{
    fill(row, col, width, attr);
    while (*s && width-- > 0 && col < 80) scr[row * 80 + col++] = (unsigned short)((attr << 8) | (unsigned char)*s++);
}

static void cls(void)
{
    int i;
    for (i = 0; i < 80 * 25; i++) scr[i] = (C_TEXT << 8) | ' ';
}

static void cursor(int on)
{
    union REGS r;
    r.h.ah = 1;
    r.x.cx = on ? 0x0607 : 0x2000;
    int86(0x10, &r, &r);
}

static void restore_screen(void)
{
    union REGS r;
    cls();
    r.h.ah = 2; r.h.bh = 0; r.x.dx = 0;
    int86(0x10, &r, &r);
    cursor(1);
}

static int key_ready(void)
{
    unsigned char z = 0;
    _asm {
        mov ah, 1
        int 16h
        mov al, 0
        jnz has
        mov al, 1
    has:
        mov z, al
    }
    return !z;
}

static int read_key(void)
{
    union REGS r;
    r.h.ah = 0;
    int86(0x16, &r, &r);
    return r.h.al ? r.h.al : 0x100 + r.h.ah;
}

#define K_UP    0x148
#define K_DOWN  0x150
#define K_LEFT  0x14B
#define K_RIGHT 0x14D
#define K_PGUP  0x149
#define K_PGDN  0x151
#define K_HOME  0x147
#define K_END   0x14F
#define K_F2    0x13C
#define K_F5    0x13F
#define K_F10   0x144

/* -------------------------------------------------------------- boot choice */

#define BOOT_WAIT 10                    /* seconds until single player starts */

static void draw_boot(int choice, int left)
{
    char line[80];
    cls();
    fill(0, 0, 80, C_TITLE);
    put(0, 1, C_TITLE, "MiSTer ao486: the network card is on");
    put(6, 18, C_HEAD, "How do you want to play?");
    putn(9, 18, 46, choice == 0 ? C_SEL : C_TEXT, "  1  Online         the network game menu");
    putn(11, 18, 46, choice == 1 ? C_SEL : C_TEXT, "  2  Single player  start this disk as usual");
    if (left >= 0) sprintf(line, "Single player starts in %2d s.", left);
    else           strcpy(line, "Up/Down and Enter.");
    put(15, 18, left >= 0 ? C_WARN : C_TEXT, line);
    put(17, 18, C_DIM, "Keys: 1 or O online, 2 or S single player.");
}

/* NPMENU /BOOT, from AUTOEXEC.BAT: with the card on, the player picks online
 * (exit code 1: load the drivers, then the menu) or single player (0: the
 * boot goes on as before, nothing loaded). Without a key single player starts
 * after BOOT_WAIT seconds, so a disk never waits here. No card: 0 at once. */
static int do_boot(void)
{
    int irq, choice = 1, left = BOOT_WAIT, counting = 1, k;
    unsigned long t0, now, e;
    const char *st = net_state(&irq);

    if (!write_load(st, irq)) return 0;
    if (!strcmp(st, "NOCARD")) { announce(st, irq); return 0; }
    while (key_ready()) read_key();     /* keys pressed during the boot */
    scr = (unsigned short __far *)MK_FP(0xB800, 0);
    cursor(0);
    draw_boot(choice, left);
    t0 = ticks();
    for (;;) {
        while (!key_ready()) {
            if (!counting) continue;
            now = ticks();
            if (now < t0) t0 = now;     /* the tick counter wraps at midnight */
            e = (now - t0) * 10 / 182;
            if (e >= BOOT_WAIT) { choice = 1; goto done; }
            if (BOOT_WAIT - (int)e != left) { left = BOOT_WAIT - (int)e; draw_boot(choice, left); }
        }
        k = read_key();
        counting = 0;
        if (k == K_UP || k == K_DOWN || k == 9) choice = !choice;
        else if (k == '1' || k == 'o' || k == 'O') { choice = 0; break; }
        else if (k == '2' || k == 's' || k == 'S' || k == 27) { choice = 1; break; }
        else if (k == 13) break;
        draw_boot(choice, -1);
    }
done:
    restore_screen();
    if (choice) { printf("Netplay: single player (no network drivers loaded).\n"); return 0; }
    announce(st, irq);
    return 1;
}

/* ------------------------------------------------------------------- menu */

typedef struct { int found; int game; } Row;     /* found < 0: not on these disks */
static Row rows[MAXGAMES + MAXFOUND];
static int nrows, sel, top, show_all = 1;
static char state_text[80];
static int state_attr;

static int ready(int fi)
{
    return found[fi].missing[0] == 0 && games[found[fi].game].type != 'f';
}

static void build_rows(void)
{
    int i, gi, pass;
    nrows = 0;
    for (pass = 0; pass < 3; pass++)            /* ready, then missing files / FPU */
        for (i = 0; i < nfound; i++) {
            int r = ready(i);
            if ((pass == 0 && r) || (pass == 1 && !r)) {
                rows[nrows].found = i; rows[nrows].game = found[i].game; nrows++;
            }
        }
    if (show_all)
        for (gi = 0; gi < ngames; gi++) {
            for (i = 0; i < nfound; i++) if (found[i].game == gi) break;
            if (i < nfound) continue;
            rows[nrows].found = -1; rows[nrows].game = gi; nrows++;
        }
    if (sel >= nrows) sel = nrows ? nrows - 1 : 0;
}

static void load_name(void)
{
    char path[96], line[80];
    FILE *f;
    sprintf(my_name, "PLAYER-%02X%02X", my_node[4], my_node[5]);
    kit_path(path, "NETPLAY.CFG");
    f = fopen(path, "r");
    if (!f) return;
    while (fgets(line, sizeof line, f)) {
        trim(line);
        if (!strnicmp(line, "name=", 5) && line[5]) {
            strncpy(my_name, line + 5, sizeof my_name - 1);
            my_name[sizeof my_name - 1] = 0;
        }
    }
    fclose(f);
}

static void save_name(void)
{
    char path[96];
    FILE *f;
    kit_path(path, "NETPLAY.CFG");
    f = fopen(path, "wb");
    if (!f) return;
    fprintf(f, "name=%s\r\n", my_name);
    fclose(f);
}

static void set_state_text(void)
{
    int irq = 0;
    const char *st;
    char path[96], line[16];
    FILE *f;
    kit_path(path, "NPIRQ.TXT");
    if ((f = fopen(path, "r")) != 0) {
        if (fgets(line, sizeof line, f)) irq = atoi(line);
        fclose(f);
    }
    if (find_packet_driver()) {
        if (ipx_installed()) {
            if (irq) sprintf(state_text, "Network card ready (packet driver and IPX loaded, IRQ %d).", irq);
            else     strcpy(state_text, "Network card ready (packet driver and IPX loaded).");
            state_attr = C_OK;
        } else {
            strcpy(state_text, "Packet driver loaded, but no IPX: run C:\\NETPLAY\\NPIPX.COM");
            state_attr = C_WARN;
        }
        return;
    }
    st = net_state(&irq);
    if (!strcmp(st, "NOCARD"))
        strcpy(state_text, "No network card: ao486 OSD, Hardware page, Network On. Then reboot.");
    else
        strcpy(state_text, "Network card found but no driver: type NP at the DOS prompt.");
    state_attr = C_BAD;
}

static void draw_list(void)
{
    int r;
    for (r = 0; r < 14; r++) {
        int idx = top + r, row = 4 + r;
        fill(row, 0, 52, C_TEXT);
        if (idx >= nrows) continue;
        {
            Row *w = &rows[idx];
            Game __far *g = &games[w->game];
            char name[40], where[40];
            int attr;
            _fstrcpy(name, g->name);
            if (w->found < 0) { strcpy(where, "-"); attr = C_DIM; }
            else {
                _fstrncpy(where, found[w->found].dir, 22); where[22] = 0;
                attr = g->type == 'f' ? C_BAD : ready(w->found) ? C_OK : C_WARN;
            }
            if (idx == sel) attr = C_SEL;
            putn(row, 1, 50, attr, "");
            putn(row, 2, 30, attr, name);
            putn(row, 33, 18, attr, where);
        }
    }
    put(3, 51, C_DIM, top > 0 ? "\x1E" : " ");
    put(17, 51, C_DIM, top + 14 < nrows ? "\x1F" : " ");
}

static void draw_room(void)
{
    int i, row = 4;
    char buf[40];
    for (i = 4; i < 18; i++) fill(i, 53, 27, C_TEXT);
    put(3, 53, C_HEAD, "In the room");
    if (!ipx_ok) { put(row, 54, C_DIM, "(no IPX: nobody seen)"); return; }
    sprintf(buf, "%s (you)", my_name);
    putn(row++, 54, 26, C_OK, buf);
    for (i = 0; i < npeers && row < 17; i++) {
        putn(row++, 54, 26, C_TEXT, peers[i].name);
        if (peers[i].started) {
            sprintf(buf, " started %.20s", peers[i].game);
            putn(row++, 54, 26, C_WARN, buf);
        }
    }
    if (!npeers) {
        put(row + 1, 54, C_DIM, "Nobody else yet. OSD");
        put(row + 2, 54, C_DIM, "Netplay: Host on one");
        put(row + 3, 54, C_DIM, "MiSTer, Join on the");
        put(row + 4, 54, C_DIM, "others (up to eight);");
        put(row + 5, 54, C_DIM, "wait for \"network");
        put(row + 6, 54, C_DIM, "linked\".");
    }
}

static int invite_peer(void);

static void draw_detail(void)
{
    int i;
    for (i = 18; i < 24; i++) fill(i, 0, 80, C_TEXT);
    for (i = 0; i < 80; i++) scr[18 * 80 + i] = (C_DIM << 8) | 0xC4;
    if (nrows) {
        Row *w = &rows[sel];
        Game __far *g = &games[w->game];
        char line[100];
        if (w->found < 0) {
            put(19, 1, C_DIM, "Not on these disks. Supported when its files are there:");
            _fstrcpy(line, g->find);
            put(20, 3, C_TEXT, line);
            if (g->need[0]) { char n[80]; _fstrcpy(n, g->need); sprintf(line, "and for network play: %s", n); put(21, 3, C_TEXT, line); }
        } else if (g->type == 'f') {
            char h[80];
            _fstrcpy(h, g->hint[0]);
            put(19, 1, C_BAD, h);
        } else if (!ready(w->found)) {
            char m[64];
            _fstrcpy(m, found[w->found].missing);
            sprintf(line, "Found in %s, but network play needs: %s", found[w->found].dir, m);
            put(19, 1, C_WARN, line);
            for (i = 0; i < g->nhint && i < 4; i++) { char h[80]; _fstrcpy(h, g->hint[i]); put(20 + i, 3, C_TEXT, h); }
        } else {
            sprintf(line, "In %s. Enter: set up and start.", found[w->found].dir);
            put(19, 1, C_OK, line);
            for (i = 0; i < g->nhint && i < 4; i++) { char h[80]; _fstrcpy(h, g->hint[i]); put(20 + i, 3, C_TEXT, h); }
        }
    }
    i = invite_peer();
    fill(23, 0, 80, C_TEXT);
    if (i >= 0) {
        char line[100];
        sprintf(line, " %s started %s. Press J to join with the same settings. ", peers[i].name, peers[i].game);
        put(23, 1, 0x1E, line);
    }
}

static void draw_all(void)
{
    char title[80];
    cls();
    fill(0, 0, 80, C_TITLE);
    put(0, 2, C_TITLE, "MiSTer ao486 netplay: network games");
    sprintf(title, "you: %s", my_name);
    put(0, 78 - (int)strlen(title), C_TITLE, title);
    put(1, 1, state_attr, state_text);
    put(3, 2, C_HEAD, "Game");
    put(3, 33, C_HEAD, "Where");
    draw_list();
    draw_room();
    draw_detail();
    fill(24, 0, 80, C_KEY);
    put(24, 1, C_KEY, show_all
        ? "Enter play  Tab only found  F2 name  F5 rescan  Esc boot on  F10 DOS"
        : "Enter play  Tab all games   F2 name  F5 rescan  Esc boot on  F10 DOS");
}

/* the peer whose game start we can follow (same game found and ready here) */
static int invite_peer(void)
{
    int i, k;
    for (i = 0; i < npeers; i++) {
        if (!peers[i].started) continue;
        for (k = 0; k < nfound; k++) {
            char n[40];
            _fstrcpy(n, games[found[k].game].name);
            if (!strcmp(n, peers[i].game) && ready(k)) return i;
        }
    }
    return -1;
}

static void edit_name(void)
{
    char buf[16];
    int n, k;
    strcpy(buf, my_name);
    n = (int)strlen(buf);
    for (;;) {
        fill(23, 0, 80, 0x1F);
        put(23, 1, 0x1F, "Your name in the room:");
        put(23, 24, 0x1F, buf);
        put(23, 24 + n, 0x9F, "_");
        put(23, 45, 0x1F, "Enter: keep  Esc: cancel");
        k = read_key();
        if (k == 27) return;
        if (k == 13) break;
        if (k == 8 && n) buf[--n] = 0;
        else if (k >= 32 && k < 127 && n < 15) { buf[n++] = (char)k; buf[n] = 0; }
    }
    if (n) { strcpy(my_name, buf); save_name(); }
}

/* ---------------------------------------------------------------- startup */

static void make_args(Game __far *g, int players, int mode, int skill, char *out)
{
    char tmpl[48], modes[96], sw[48] = "", *p, *o = out;
    int i;
    _fstrcpy(tmpl, g->args);
    _fstrcpy(modes, g->modes);
    p = strtok(modes, "|");
    for (i = 0; p && i < mode; i++) p = strtok(0, "|");
    if (p && (p = strchr(p, '=')) != 0) strcpy(sw, p + 1);
    for (p = tmpl; *p; p++) {
        if (*p == '%' && p[1]) {
            p++;
            if (*p == 'N') o += sprintf(o, "%d", players);
            else if (*p == 'S') o += sprintf(o, "%d", skill);
            else if (*p == 'M') o += sprintf(o, "%s", sw);
            else *o++ = *p;
        } else *o++ = *p;
    }
    *o = 0;
    /* tidy double spaces from an empty mode */
    for (p = out; (p = strstr(p, "  ")) != 0; ) memmove(p, p + 1, strlen(p));
    trim(out);
}

static int nmodes(Game __far *g)
{
    char modes[96], *p;
    int n = 0;
    _fstrcpy(modes, g->modes);
    for (p = strtok(modes, "|"); p; p = strtok(0, "|")) n++;
    return n;
}

static void mode_name(Game __far *g, int mode, char *out)
{
    char modes[96], *p;
    int i;
    _fstrcpy(modes, g->modes);
    p = strtok(modes, "|");
    for (i = 0; p && i < mode; i++) p = strtok(0, "|");
    strcpy(out, p ? p : "");
    if ((p = strchr(out, '=')) != 0) *p = 0;
}

/* The program to start: the first of run= that is in the folder. */
static int pick_run(Found __far *fo, Game __far *g, char *prog)
{
    char alts[48], dir[80], path[140], *p;
    _fstrcpy(alts, g->run);
    _fstrcpy(dir, fo->dir);
    for (p = strtok(alts, "|"); p; p = strtok(0, "|")) {
        sprintf(path, "%s\\%s", dir, p);
        if (file_exists(path)) { strcpy(prog, p); return 1; }
    }
    return 0;
}

static int write_run(Found __far *fo, const char *prog, const char *args)
{
    char path[96], dir[80];
    FILE *f;
    const char *ext = strrchr(prog, '.');
    kit_path(path, "RUN.BAT");
    _fstrcpy(dir, fo->dir);
    f = fopen(path, "wb");
    if (!f) return 0;
    fprintf(f, "@ECHO OFF\r\n%c:\r\nCD %s\r\n", dir[0], dir[2] ? dir + 2 : "\\");
    if (ext && !stricmp(ext, ".BAT")) fprintf(f, "CALL %s %s\r\n", prog, args);
    else                              fprintf(f, "%s %s\r\n", prog, args);
    fprintf(f, "C:\r\nCD \\\r\n");
    fclose(f);
    return 1;
}

/* The setup screen before a start. Returns 1 to start (args filled in). */
static int setup_screen(Found __far *fo, Game __far *g, char *args, const char *follow)
{
    int players = 2, mode = 0, skill = 3, field = 0, i, k;
    int has_n, has_m, has_s, nf;
    char tmpl[48], line[100], nm[40];
    _fstrcpy(tmpl, g->args);
    has_n = g->type == 'i' && strstr(tmpl, "%N") != 0;
    has_m = g->type == 'i' && strstr(tmpl, "%M") != 0 && nmodes(g) > 0;
    has_s = g->type == 'i' && strstr(tmpl, "%S") != 0;
    nf = has_n + has_m + has_s;
    for (;;) {
        int row = 6, f = 0;
        cls();
        fill(0, 0, 80, C_TITLE);
        _fstrcpy(nm, g->name);
        sprintf(line, "Start %s", nm);
        put(0, 2, C_TITLE, line);
        _fstrcpy(line, fo->dir);
        put(2, 2, C_TEXT, "Folder:");
        put(2, 12, C_TEXT, line);
        if (follow) {
            sprintf(line, "Same settings as the other player: %s", follow);
            put(4, 2, C_WARN, line);
            strcpy(args, follow);
        } else if (g->type == 'i') {
            if (has_n) {
                sprintf(line, "Players:  < %d >", players);
                put(row++, 2, field == f++ ? C_SEL : C_TEXT, line);
            }
            if (has_m) {
                char mn[40];
                mode_name(g, mode, mn);
                sprintf(line, "Mode:     < %s >", mn);
                put(row++, 2, field == f++ ? C_SEL : C_TEXT, line);
            }
            if (has_s) {
                sprintf(line, "Skill:    < %d >", skill);
                put(row++, 2, field == f++ ? C_SEL : C_TEXT, line);
            }
            make_args(g, players, mode, skill, args);
            sprintf(line, "Command line: %s", args);
            put(row + 1, 2, C_DIM, line);
        } else args[0] = 0;
        row = 12;
        for (i = 0; i < g->nhint; i++) { char h[80]; _fstrcpy(h, g->hint[i]); put(row++, 2, C_TEXT, h); }
        put(row + 1, 2, C_DIM, "Everyone in the room starts the game from this menu; the others");
        put(row + 2, 2, C_DIM, "can press J in theirs to follow you with the same settings.");
        fill(24, 0, 80, C_KEY);
        put(24, 1, C_KEY, nf ? "Up/Down field  Left/Right change  Enter start  Esc back"
                             : "Enter start  Esc back");
        k = read_key();
        if (k == 27) return 0;
        if (k == 13) return 1;
        if (!nf || follow) continue;
        if (k == K_UP)   field = (field + nf - 1) % nf;
        if (k == K_DOWN) field = (field + 1) % nf;
        if (k == K_LEFT || k == K_RIGHT) {
            int d = k == K_RIGHT ? 1 : -1, which = 0, j;
            int order[3], n = 0;
            if (has_n) order[n++] = 0;
            if (has_m) order[n++] = 1;
            if (has_s) order[n++] = 2;
            which = order[field];
            if (which == 0) { players += d; if (players < 2) players = g->players; if (players > g->players) players = 2; }
            if (which == 1) { j = nmodes(g); mode = (mode + j + d) % j; }
            if (which == 2) { skill += d; if (skill < 1) skill = 5; if (skill > 5) skill = 1; }
        }
    }
}

static int start_game(int fi, const char *follow)
{
    Found __far *fo = &found[fi];
    Game __far *g = &games[fo->game];
    char prog[48], args[64], nm[40];
    int i;
    if (!pick_run(fo, g, prog)) return 0;
    if (!setup_screen(fo, g, args, follow)) return 0;
    if (!write_run(fo, prog, args)) return 0;
    _fstrcpy(nm, g->name);
    for (i = 0; i < 3; i++) { lobby_send(1, nm, args); wait_ticks(2); }
    return 1;
}

static int menu(void)
{
    int k, redraw = 1;
    unsigned long last_tx = 0;

    names = _fmalloc(sizeof(*names) * MAXNAMES);
    games = _fmalloc(sizeof(Game) * MAXGAMES);
    found = _fmalloc(sizeof(Found) * MAXFOUND);
    if (!names || !games || !found) { printf("Netplay: out of memory\n"); return 0; }
    if (!load_games()) { printf("Netplay: no %s\\GAMES.INI\n", kitdir); return 0; }

    ipx_open();
    atexit(ipx_close);
    load_name();
    set_state_text();
    scr = (unsigned short __far *)MK_FP(0xB800, 0);
    cursor(0);
    cls();
    put(12, 30, C_TEXT, "Looking for games...");
    scan_all();
    build_rows();

    for (;;) {
        if (ticks() - last_tx >= 18) { lobby_send(0, 0, 0); last_tx = ticks(); }
        if (lobby_poll()) redraw = 1;
        if (redraw) { draw_all(); redraw = 0; }
        if (!key_ready()) continue;
        k = read_key();
        redraw = 1;
        if (k == K_UP && sel > 0) sel--;
        else if (k == K_DOWN && sel + 1 < nrows) sel++;
        else if (k == K_PGUP) sel = sel > 13 ? sel - 13 : 0;
        else if (k == K_PGDN) sel = sel + 13 < nrows ? sel + 13 : (nrows ? nrows - 1 : 0);
        else if (k == K_HOME) sel = 0;
        else if (k == K_END) sel = nrows ? nrows - 1 : 0;
        else if (k == 9) { show_all = !show_all; build_rows(); }
        else if (k == K_F2) edit_name();
        else if (k == K_F5) { cls(); put(12, 30, C_TEXT, "Looking for games..."); scan_all(); build_rows(); }
        else if (k == 27) { restore_screen(); return 0; }
        else if (k == K_F10) { restore_screen(); return 3; }
        else if (k == 13 && nrows && rows[sel].found >= 0 && ready(rows[sel].found)) {
            if (start_game(rows[sel].found, 0)) { restore_screen(); return 2; }
        } else if (k == 'j' || k == 'J') {
            int p = invite_peer(), i;
            if (p >= 0)
                for (i = 0; i < nfound; i++) {
                    char n[40];
                    _fstrcpy(n, games[found[i].game].name);
                    if (!strcmp(n, peers[p].game) && ready(i)) {
                        if (start_game(i, peers[p].args)) { restore_screen(); return 2; }
                        break;
                    }
                }
        }
        if (sel < top) top = sel;
        if (sel >= top + 14) top = sel - 13;
    }
}

/* ---------------------------------------------------------------- install */

static int copy_file(const char *from, const char *to)
{
    FILE *a = fopen(from, "rb"), *b;
    static char buf[4096];
    size_t n;
    if (!a) return 0;
    b = fopen(to, "wb");
    if (!b) { fclose(a); return 0; }
    while ((n = fread(buf, 1, sizeof buf, a)) > 0) fwrite(buf, 1, n, b);
    fclose(a);
    return fclose(b) == 0;
}

static const char *kit_files[] = {
    "NPMENU.EXE", "GAMES.INI", "NETBOOT.BAT", "NE2000.COM", "NPIPX.COM", "README.TXT", 0
};

/* the line where the hook goes: before the first CD or RUNGAME line, the
 * way the ready-made ao486 disks start their game; else at the end */
static int hook_line(char lines[][128], int n)
{
    int i;
    for (i = 0; i < n; i++) {
        char u[128];
        strcpy(u, lines[i]);
        trim(u);
        strupr(u);
        if (!strncmp(u, "CD ", 3) || !strncmp(u, "CD\\", 3) || strstr(u, "RUNGAME")) return i;
    }
    return n;
}

static char lines[200][128];            /* AUTOEXEC.BAT, for install and uninstall */

/* the lines /INSTALL adds to AUTOEXEC.BAT */
static int is_hook(const char *line)
{
    char u[128];
    strncpy(u, line, sizeof u - 1);
    u[sizeof u - 1] = 0;
    trim(u);
    strupr(u);
    return !strcmp(u, "CALL C:\\NETPLAY\\NETBOOT.BAT BOOT")
        || !strcmp(u, "IF EXIST C:\\NETPLAY\\NPSKIP.FLG GOTO NPEND")
        || !strcmp(u, ":NPEND");
}

static int read_lines(const char *path, char buf[][128], int max)
{
    FILE *f = fopen(path, "r");
    int n = 0;
    if (!f) return -1;
    while (n < max && fgets(buf[n], 128, f)) {
        size_t l = strlen(buf[n]);
        while (l && (buf[n][l - 1] == '\n' || buf[n][l - 1] == '\r')) buf[n][--l] = 0;
        n++;
    }
    if (!feof(f)) n = -2;               /* too long */
    fclose(f);
    return n;
}


static int do_install(void)
{
    char from[96], to[96];
    FILE *f;
    int n = 0, i, at;

    mkdir(KIT_DIR);
    for (i = 0; kit_files[i]; i++) {
        sprintf(from, "%s\\%s", kitdir, kit_files[i]);
        sprintf(to, "%s\\%s", KIT_DIR, kit_files[i]);
        if (!stricmp(from, to)) continue;
        if (!copy_file(from, to)) { printf("Could not copy %s to %s\n", from, to); return 1; }
    }
    f = fopen("C:\\NP.BAT", "wb");
    if (f) { fputs("@ECHO OFF\r\nCALL C:\\NETPLAY\\NETBOOT.BAT\r\n", f); fclose(f); }

    n = read_lines("C:\\AUTOEXEC.BAT", lines, 200);
    if (n == -2) { printf("C:\\AUTOEXEC.BAT is too long; add CALL C:\\NETPLAY\\NETBOOT.BAT BOOT yourself.\n"); return 1; }
    if (n < 0) n = 0;
    for (i = 0; i < n; i++) {
        char u[128];
        strcpy(u, lines[i]); strupr(u);
        if (strstr(u, "NETPLAY\\NETBOOT")) {
            printf("Netplay updated in C:\\NETPLAY (AUTOEXEC.BAT already starts it).\n");
            return 0;
        }
    }
    if (n && !file_exists("C:\\AUTOEXEC.NPB") && !copy_file("C:\\AUTOEXEC.BAT", "C:\\AUTOEXEC.NPB")) {
        printf("Could not back up C:\\AUTOEXEC.BAT\n");
        return 1;
    }
    at = hook_line(lines, n);
    f = fopen("C:\\AUTOEXEC.BAT", "wb");
    if (!f) { printf("Could not write C:\\AUTOEXEC.BAT\n"); return 1; }
    for (i = 0; i <= n; i++) {
        if (i == at) {
            if (!n) fputs("@ECHO OFF\r\n", f);
            fputs("CALL C:\\NETPLAY\\NETBOOT.BAT BOOT\r\n", f);
            fputs("IF EXIST C:\\NETPLAY\\NPSKIP.FLG GOTO NPEND\r\n", f);
        }
        if (i < n) fprintf(f, "%s\r\n", lines[i]);
    }
    fputs(":NPEND\r\n", f);
    fclose(f);
    printf("Netplay installed in C:\\NETPLAY. With the network card on, the PC asks at\n"
           "boot: online or single player (single after 10 s). Type NP for the menu.\n"
           "A:\\UNINSTAL takes it away again (the old AUTOEXEC.BAT is C:\\AUTOEXEC.NPB).\n");
    return 0;
}

/* NPMENU /UNINSTALL: takes the hook out of C:\AUTOEXEC.BAT (the backup goes
 * back when nothing else changed since; else only the netplay lines go, so
 * later changes stay), then deletes AUTOEXEC.NPB, C:\NP.BAT and C:\NETPLAY. */
static int do_uninstall(void)
{
    struct find_t ff;
    char path[96], old[128];
    FILE *f;
    int n, i, hooks = 0, same, left = 0;

    n = read_lines("C:\\AUTOEXEC.BAT", lines, 200);
    if (n == -2) { printf("C:\\AUTOEXEC.BAT is too long: take the netplay lines out yourself.\n"); return 1; }
    for (i = 0; i < n; i++) if (is_hook(lines[i])) hooks++;
    if (hooks) {
        /* the backup is the same as AUTOEXEC.BAT without the hook? */
        f = fopen("C:\\AUTOEXEC.NPB", "r");
        same = f != 0;
        for (i = 0; same && i < n; i++) {
            size_t l;
            if (is_hook(lines[i])) continue;
            if (!fgets(old, sizeof old, f)) { same = 0; break; }
            l = strlen(old);
            while (l && (old[l - 1] == '\n' || old[l - 1] == '\r')) old[--l] = 0;
            same = !strcmp(lines[i], old);
        }
        if (same && fgets(old, sizeof old, f)) same = 0;
        if (f) fclose(f);
        if (same) {
            if (!copy_file("C:\\AUTOEXEC.NPB", "C:\\AUTOEXEC.BAT")) { printf("Could not write C:\\AUTOEXEC.BAT\n"); return 1; }
        } else {
            f = fopen("C:\\AUTOEXEC.BAT", "wb");
            if (!f) { printf("Could not write C:\\AUTOEXEC.BAT\n"); return 1; }
            for (i = 0; i < n; i++) if (!is_hook(lines[i])) fprintf(f, "%s\r\n", lines[i]);
            fclose(f);
        }
    }
    remove("C:\\AUTOEXEC.NPB");
    remove("C:\\NP.BAT");

    chdir("\\");                       /* not inside the folder that goes */
    if (_dos_findfirst(KIT_DIR "\\*.*", _A_NORMAL | _A_RDONLY | _A_HIDDEN | _A_SYSTEM | _A_ARCH, &ff) == 0) {
        do {
            sprintf(path, "%s\\%s", KIT_DIR, ff.name);
            _dos_setfileattr(path, _A_NORMAL);
            if (remove(path)) left++;
        } while (_dos_findnext(&ff) == 0);
    }
    if (rmdir(KIT_DIR) == 0 || !dir_exists(KIT_DIR))
        printf("Netplay removed: C:\\AUTOEXEC.BAT is %s, C:\\NETPLAY is gone.\n",
               hooks ? "as before" : "unchanged (it had no netplay lines)");
    else
        printf("Netplay removed from C:\\AUTOEXEC.BAT; C:\\NETPLAY could not be deleted (%d files left).\n", left);
    return 0;
}

/* ------------------------------------------------------------------- main */

int main(int argc, char **argv)
{
    char *p;
    signal(SIGINT, SIG_IGN);
    strncpy(kitdir, argv[0], sizeof kitdir - 1);
    p = strrchr(kitdir, '\\');
    if (p) *p = 0; else strcpy(kitdir, KIT_DIR);

    if (argc > 1) {
        if (!stricmp(argv[1], "/CHECK"))     return do_check();
        if (!stricmp(argv[1], "/BOOT"))      return do_boot();
        if (!stricmp(argv[1], "/INSTALL"))   return do_install();
        if (!stricmp(argv[1], "/UNINSTALL")) return do_uninstall();
        printf("NPMENU [/CHECK | /BOOT | /INSTALL | /UNINSTALL]\n");
        return 1;
    }
    return menu();
}
