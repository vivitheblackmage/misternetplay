; ---------------------------------------------------------------------------
; NetPong - a small two-player paddle game for testing NES netplay.
;
; NROM-128 (mapper 0), NTSC. Port 1 moves the left paddle, port 2 the right
; one (Up/Down). Start on either pad starts a game; first to 9 wins.
;
; "SYNC xxxx" at the bottom is a checksum of the game state, updated every
; frame. In a netplay session both screens must show the same value at all
; times; the netplay core checks the same thing with its frame CRCs.
;
; Everything is deterministic: all RAM is cleared at reset, the only
; "randomness" (serve angle) comes from the frame counter, which counts
; logic frames from power-on.
; ---------------------------------------------------------------------------

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
OAMADDR   = $2003
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
SQ1_VOL   = $4000
SQ1_SWEEP = $4001
SQ1_LO    = $4002
SQ1_HI    = $4003
DMC_FREQ  = $4010
OAMDMA    = $4014
APUSTATUS = $4015
JOY1      = $4016
JOY2      = $4017            ; read: pad 2, write: APU frame counter

OAM       = $0200

BTN_START = $10
BTN_UP    = $08
BTN_DOWN  = $04

TOP       = 32               ; playfield, ball and paddles stay inside
BOTTOM    = 208
PADDLE_H  = 32
BALL      = 4
P1_X      = 16
P2_X      = 236
SPEED_PAD = 3
WIN_SCORE = 9

ST_TITLE  = 0
ST_SERVE  = 1
ST_PLAY   = 2
ST_OVER   = 3

MSG_CLEAR = 0
MSG_TITLE = 1
MSG_P1WIN = 2
MSG_P2WIN = 3
MSG_NONE  = $FF

; ---------------------------------------------------------------------------
.segment "HEADER"
        .byte "NES", $1A
        .byte 1                 ; 16 KB PRG
        .byte 1                 ; 8 KB CHR
        .byte $01               ; mapper 0, vertical mirroring
        .byte $00
        .res 8, 0

.segment "CHARS"
        .incbin "netpong.chr"

; ---------------------------------------------------------------------------
.segment "ZEROPAGE"
nmi_flag:   .res 1
upd_ready:  .res 1           ; main -> NMI: disp_* and msg_req are ready
frame_lo:   .res 1
frame_hi:   .res 1
pad1:       .res 1
pad2:       .res 1
pad1_prev:  .res 1
pad2_prev:  .res 1
state:      .res 1
timer:      .res 1
p1y:        .res 1
p2y:        .res 1
bx:         .res 1
by:         .res 1
bdx:        .res 1           ; signed
bdy:        .res 1           ; signed
speed:      .res 1
hits:       .res 1
score1:     .res 1
score2:     .res 1
serve_dx:   .res 1           ; signed: next serve goes this way
msg_req:    .res 1
tmp:        .res 1
cnt:        .res 1           ; main-thread loop counter (NMI uses ptr)
ptr:        .res 2
disp_s1:    .res 1
disp_s2:    .res 1
disp_h:     .res 4

; ---------------------------------------------------------------------------
.segment "CODE"

reset:
        sei
        cld
        ldx #$40
        stx JOY2                ; APU frame IRQ off
        ldx #$FF
        txs
        inx
        stx PPUCTRL
        stx PPUMASK
        stx DMC_FREQ
        bit PPUSTATUS
@vb1:   bit PPUSTATUS
        bpl @vb1

        lda #0
@clr:   sta $0000,x
        sta $0100,x
        sta $0300,x
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne @clr
        lda #$FF                ; all sprites off screen
@oam:   sta OAM,x
        inx
        bne @oam

@vb2:   bit PPUSTATUS
        bpl @vb2

        jsr init_ppu
        lda #$0F
        sta APUSTATUS

        lda #ST_TITLE
        sta state
        lda #MSG_TITLE
        sta msg_req
        lda #(TOP + BOTTOM - PADDLE_H) / 2
        sta p1y
        sta p2y
        jsr prepare_display
        lda #1
        sta upd_ready

        lda #$80                ; NMI on
        sta PPUCTRL

main_loop:
        lda #0
        sta nmi_flag
@wait:  lda nmi_flag
        beq @wait

        jsr read_pads
        jsr update
        inc frame_lo
        bne :+
        inc frame_hi
:       jsr build_oam
        jsr prepare_display
        lda #1
        sta upd_ready
        jmp main_loop

; ---------------------------------------------------------------------------
nmi:
        pha
        txa
        pha
        tya
        pha

        lda #0
        sta OAMADDR
        lda #>OAM
        sta OAMDMA

        lda upd_ready
        beq @skip
        bit PPUSTATUS
        lda #$20                ; P1 score, row 2 col 8
        sta PPUADDR
        lda #$48
        sta PPUADDR
        lda disp_s1
        sta PPUDATA
        lda #$20                ; P2 score, row 2 col 23
        sta PPUADDR
        lda #$57
        sta PPUADDR
        lda disp_s2
        sta PPUDATA
        lda #$23                ; sync value, row 28 col 18
        sta PPUADDR
        lda #$92
        sta PPUADDR
        ldx #0
@h:     lda disp_h,x
        sta PPUDATA
        inx
        cpx #4
        bne @h
        lda msg_req
        bmi @nomsg
        jsr draw_msg
        lda #MSG_NONE
        sta msg_req
@nomsg: lda #0
        sta upd_ready
@skip:
        lda #0
        sta PPUSCROLL
        sta PPUSCROLL
        lda #$80
        sta PPUCTRL
        lda #$1E                ; background + sprites, left column too
        sta PPUMASK
        inc nmi_flag

        pla
        tay
        pla
        tax
        pla
irq:    rti

; A = message number. Two 14-tile rows: row 12 and row 14, from column 9.
draw_msg:
        asl a
        tax
        lda msg_ptrs,x
        sta ptr
        lda msg_ptrs+1,x
        sta ptr+1
        lda #$21
        sta PPUADDR
        lda #$89
        sta PPUADDR
        ldy #0
@a:     lda (ptr),y
        sta PPUDATA
        iny
        cpy #14
        bne @a
        lda #$21
        sta PPUADDR
        lda #$C9
        sta PPUADDR
@b:     lda (ptr),y
        sta PPUDATA
        iny
        cpy #28
        bne @b
        rts

; ---------------------------------------------------------------------------
; Rendering is off here.
init_ppu:
        bit PPUSTATUS
        lda #$3F
        sta PPUADDR
        lda #$00
        sta PPUADDR
        ldx #0
@pal:   lda palette,x
        sta PPUDATA
        inx
        cpx #32
        bne @pal

        lda #$20                ; nametable 0: spaces, then zero attributes
        sta PPUADDR
        lda #$00
        sta PPUADDR
        lda #$20
        ldy #4
@o:     ldx #240
@i:     sta PPUDATA
        dex
        bne @i
        dey
        bne @o
        lda #0
        ldx #64
@at:    sta PPUDATA
        dex
        bne @at

        lda #$20                ; top wall, row 3
        sta PPUADDR
        lda #$60
        sta PPUADDR
        lda #$05
        ldx #32
@tw:    sta PPUDATA
        dex
        bne @tw
        lda #$23                ; bottom wall, row 26
        sta PPUADDR
        lda #$40
        sta PPUADDR
        lda #$06
        ldx #32
@bw:    sta PPUDATA
        dex
        bne @bw

        lda #$04                ; net: column 16, rows 4-25, step 32
        sta PPUCTRL
        lda #$20
        sta PPUADDR
        lda #$90
        sta PPUADDR
        lda #$02
        ldx #22
@net:   sta PPUDATA
        dex
        bne @net
        lda #$00
        sta PPUCTRL

        ldx #0                  ; fixed text
@txt:   lda texts,x
        beq @done
        sta PPUADDR
        inx
        lda texts,x
        sta PPUADDR
        inx
@ch:    lda texts,x
        inx
        cmp #0
        beq @txt
        sta PPUDATA
        jmp @ch
@done:  rts

; ---------------------------------------------------------------------------
read_pads:
        lda pad1
        sta pad1_prev
        lda pad2
        sta pad2_prev
        lda #1
        sta JOY1
        lda #0
        sta JOY1
        ldx #8
@l:     lda JOY1
        lsr a
        rol pad1
        lda JOY2
        lsr a
        rol pad2
        dex
        bne @l
        rts

; A = Start pressed this frame on either pad (nonzero) or 0
start_pressed:
        lda pad1_prev
        eor #$FF
        and pad1
        sta tmp
        lda pad2_prev
        eor #$FF
        and pad2
        ora tmp
        and #BTN_START
        rts

; ---------------------------------------------------------------------------
update:
        lda pad1
        ldx p1y
        jsr move_paddle
        stx p1y
        lda pad2
        ldx p2y
        jsr move_paddle
        stx p2y

        lda state
        cmp #ST_SERVE
        beq do_serve
        cmp #ST_PLAY
        beq do_play
        jsr start_pressed       ; title or game over
        beq @r
        jmp new_game
@r:     rts

do_serve:
        jsr center_ball
        dec timer
        bne @r
        lda #ST_PLAY
        sta state
        lda serve_dx
        sta bdx
        lda frame_lo
        and #3
        tax
        lda serve_dy,x
        sta bdy
@r:     rts

do_play:
        clc
        lda bx
        adc bdx
        sta bx
        clc
        lda by
        adc bdy
        sta by

        lda bdy                 ; walls
        bmi @up
        lda by
        cmp #BOTTOM - BALL + 1
        bcc @walls_ok
        lda #BOTTOM - BALL
        sta by
        jmp @bounce
@up:    lda by
        cmp #TOP
        bcs @walls_ok
        lda #TOP
        sta by
@bounce:
        lda #0
        sec
        sbc bdy
        sta bdy
        lda #$53
        ldx #$00
        jsr sfx
@walls_ok:

        lda bdx
        bmi @left

        lda bx                  ; moving right
        cmp #P2_X - BALL
        bcc @r
        cmp #P2_X + BALL
        bcs @score_r
        lda p2y
        jsr overlap
        bcc @r
        lda #P2_X - BALL
        sta bx
        jsr bump_speed
        lda #0
        sec
        sbc speed
        sta bdx
        lda p2y
        jmp hit
@score_r:
        cmp #244
        bcc @r
        inc score1
        lda #$02                ; serve to the side that lost the point
        sta serve_dx
        lda score1
        ldx #MSG_P1WIN
        jmp point

@left:  lda bx
        cmp #P1_X + BALL + 1
        bcs @r
        cmp #P1_X - BALL + 1
        bcc @score_l
        lda p1y
        jsr overlap
        bcc @r
        lda #P1_X + BALL
        sta bx
        jsr bump_speed
        lda speed
        sta bdx
        lda p1y
        jmp hit
@score_l:
        cmp #6
        bcs @r
        inc score2
        lda #$FE
        sta serve_dx
        lda score2
        ldx #MSG_P2WIN
        jmp point
@r:     rts

; A = paddle top. Carry set if the ball overlaps it vertically.
overlap:
        sta tmp
        lda by
        clc
        adc #BALL
        cmp tmp
        bcc @no
        beq @no
        lda tmp
        clc
        adc #PADDLE_H
        cmp by
        bcc @no
        beq @no
        sec
        rts
@no:    clc
        rts

; A = paddle top: the ball's angle depends on where it hit the paddle.
hit:
        sta tmp
        lda by
        clc
        adc #BALL / 2
        sec
        sbc tmp
        bpl :+
        lda #0
:       lsr a
        lsr a
        lsr a
        cmp #5
        bcc :+
        lda #4
:       tax
        lda hit_dy,x
        sta bdy
        lda #$A9
        ldx #$00
        jmp sfx

bump_speed:
        inc hits
        ldx #2
        lda hits
        cmp #4
        bcc :+
        inx
        cmp #10
        bcc :+
        inx
:       stx speed
        rts

; A = scorer's new score, X = win message
point:
        cmp #WIN_SCORE
        bcc @next
        stx msg_req
        lda #ST_OVER
        sta state
        lda #$FF
        sta by
        lda #$00
        ldx #$22
        jmp sfx
@next:  lda #ST_SERVE
        sta state
        lda #60
        sta timer
        lda #0
        sta hits
        lda #2
        sta speed
        lda #$00
        ldx #$22
        jmp sfx

new_game:
        lda #0
        sta score1
        sta score2
        sta hits
        lda #2
        sta speed
        sta serve_dx
        lda #MSG_CLEAR
        sta msg_req
        lda #90
        sta timer
        lda #ST_SERVE
        sta state
        rts

center_ball:
        lda #(256 - BALL) / 2
        sta bx
        lda #(TOP + BOTTOM - BALL) / 2
        sta by
        rts

; A = pad, X = paddle top -> X = new top
move_paddle:
        sta tmp
        and #BTN_UP
        beq @down
        txa
        sec
        sbc #SPEED_PAD
        cmp #TOP
        bcs :+
        lda #TOP
:       tax
@down:  lda tmp
        and #BTN_DOWN
        beq @r
        txa
        clc
        adc #SPEED_PAD
        cmp #BOTTOM - PADDLE_H + 1
        bcc :+
        lda #BOTTOM - PADDLE_H
:       tax
@r:     rts

; A = period low, X = $4003 (length index << 3 | period high)
sfx:
        pha
        lda #$9F                ; duty 50 %, constant volume 15
        sta SQ1_VOL
        lda #$08                ; sweep off
        sta SQ1_SWEEP
        pla
        sta SQ1_LO
        stx SQ1_HI
        rts

; ---------------------------------------------------------------------------
build_oam:
        ldx #0
        lda p1y
        ldy #P1_X
        jsr paddle_sprites
        lda p2y
        ldy #P2_X
        jsr paddle_sprites
        lda state               ; ball only while serving or playing
        cmp #ST_SERVE
        beq @ball
        cmp #ST_PLAY
        beq @ball
        lda #$FF
        sta OAM,x
        rts
@ball:  ldy by
        dey
        tya
        sta OAM,x
        lda #$03
        sta OAM+1,x
        lda #0
        sta OAM+2,x
        lda bx
        sta OAM+3,x
        rts

; A = top, Y = x; four 8x8 sprites from OAM+X, X advances by 16
paddle_sprites:
        sec
        sbc #1                  ; sprites are drawn one line lower
        sta tmp
        lda #4
        sta cnt
@s:     lda tmp
        sta OAM,x
        lda #$04
        sta OAM+1,x
        lda #0
        sta OAM+2,x
        tya
        sta OAM+3,x
        lda tmp
        clc
        adc #8
        sta tmp
        inx
        inx
        inx
        inx
        dec cnt
        bne @s
        rts

; ---------------------------------------------------------------------------
prepare_display:
        lda score1
        clc
        adc #'0'
        sta disp_s1
        lda score2
        clc
        adc #'0'
        sta disp_s2

        lda bx                  ; sync value: a mix of the whole game state
        eor p1y
        eor score1
        eor frame_lo
        eor state
        eor bdy
        tax
        lda by
        eor p2y
        eor score2
        eor frame_hi
        eor bdx
        eor timer
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda hex,y
        sta disp_h
        pla
        and #$0F
        tay
        lda hex,y
        sta disp_h+1
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda hex,y
        sta disp_h+2
        txa
        and #$0F
        tay
        lda hex,y
        sta disp_h+3
        rts

; ---------------------------------------------------------------------------
.segment "RODATA"

palette:
        .byte $0F, $30, $10, $00,  $0F, $30, $10, $00
        .byte $0F, $30, $10, $00,  $0F, $30, $10, $00
        .byte $0F, $30, $10, $00,  $0F, $30, $10, $00
        .byte $0F, $30, $10, $00,  $0F, $30, $10, $00

hex:    .byte "0123456789ABCDEF"
serve_dy: .byte $FE, $FF, $01, $02
hit_dy:   .byte $FE, $FF, $00, $01, $02

; address hi, lo, text, 0 ... 0
texts:
        .byte $20, $44, "P1", 0
        .byte $20, $5A, "P2", 0
        .byte $20, $48, "0", 0
        .byte $20, $57, "0", 0
        .byte $23, $8D, "SYNC", 0
        .byte 0

msg_ptrs:
        .word msg_clear, msg_title, msg_p1win, msg_p2win
msg_clear:
        .byte "       ", $02, "      "
        .byte "       ", $02, "      "
msg_title:
        .byte "   NETPONG    "
        .byte " PRESS START  "
msg_p1win:
        .byte "PLAYER 1 WINS "
        .byte " PRESS START  "
msg_p2win:
        .byte "PLAYER 2 WINS "
        .byte " PRESS START  "

.segment "VECTORS"
        .word nmi, reset, irq
