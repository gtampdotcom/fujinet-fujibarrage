; scr.asm -- the TMS9918's set-up (tms.h, tmsgfx.h) and the text screens
; (scr.h): 32 columns by 24 rows of 8x8 cells, the Namco font
; (gen/adam/font.asm). (It was tms.c and scr.c: in assembler it is a third
; the size.)
;
; Graphics II, each third's names 0..255 in order (the identity): every
; cell has its own 8 pattern bytes and 8 colour bytes, so the field, the
; text, the HUD and the balloons are all written as cells, with no mode
; change and no character set to manage. Two more name tables hold the
; field's rows a cell to the left and to the right, for the shake (the
; NMI flips R2: nmi.asm).
;
; A row's palette is eight ink/ground pairs, a byte a pixel row, so a
; title's letters can run from one colour down to another. The VRAM is the
; only copy of the text: a row's palette changes by rewriting its colours
; (its letters stay), inverse swaps a cell's ink and ground in place, and a
; scroll copies rows through VRAM reads. Each row keeps a bit a cell for
; the cells with letters on them and those inverse, so a row is cleared a
; cell at a time: what is written over it at once doesn't flicker.
;
; C's arguments are on the stack (zsdcc); IX and IY are kept.

        SECTION code_user

        PUBLIC  _tms_init, _tms_blank, _tms_cell, _tms_cell_fill, _tms_blanked
        PUBLIC  _scr_init, _scr_begin, _scr_row, _scr_text, _scr_inverse
        PUBLIC  _scr_clear_row, _scr_scroll, _scr_show, _seat_col
        PUBLIC  scr_rpal
        EXTERN  _va_addr, _va_src, _va_len, _va_val, _va_write, _va_writef, _va_fill, _va_read
        EXTERN  _vdp_busy, _vdp_pend, _vdp_catch_up, _vdp_r1, _vdp_r2, _vdp_r7
        EXTERN  _frame_wait, _field_off
        PUBLIC  glyph8, vram8

        INCLUDE "vdpio.inc"     ; VDP_DATA, VDP_CTRL (the platform's)
        defc    VR_NAME = $1800
        defc    VR_SAT = $1B00
        defc    VR_NAMEL = $1C00
        defc    VR_COL = $2000
        defc    VR_NAMER = $3C00
        defc    R1_ON = $E0
        defc    R1_OFF = $A0
        defc    PAL_TEXT = 0
        defc    PAL_SEAT = 5
        defc    ROWS = 24

; ---- the VDP --------------------------------------------------------------------

; lock: the NMI held off; unlock: let it in again (a frame it held back now)
lock:   ld      a,1
        ld      (_vdp_busy),a
        ret
unlock: xor     a
        ld      (_vdp_busy),a
        ld      a,(_vdp_pend)
        or      a
        ret     z
        jp      _vdp_catch_up

; waddr: the VDP's write address HL (locked); raddr: its read address
waddr:  ld      a,$40
        jr      ad
raddr:  xor     a
ad:     push    af
        call    lock
        pop     af
        or      h
        ld      c,a
        ld      a,l
        out     (VDP_CTRL),a
        ld      a,c
        out     (VDP_CTRL),a
        ret

; out8: B bytes from DE (37 T-states a byte: safe while the VDP draws)
out8:   ld      a,(de)
        out     (VDP_DATA),a
        inc     de
        djnz    out8
        ret

; outa: B bytes of C
outa:   ld      a,c
        out     (VDP_DATA),a
        nop
        nop
        djnz    outa
        ret

; reg: VDP register C = A
reg:    push    af
        call    lock
        pop     af
        out     (VDP_CTRL),a
        ld      a,c
        or      $80
        out     (VDP_CTRL),a
        jp      unlock

; void tms_blank(uint8_t on): the display blanked (1) or shown
_tms_blank:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
blank:  ld      (_tms_blanked),a
        or      a
        ld      a,R1_ON
        jr      z,bk_1
        ld      a,R1_OFF
bk_1:   ld      (_vdp_r1),a
        ld      c,1
        jr      reg

; void tms_init(void): registers, tables, the identity names; IE on
_tms_init:
        ld      a,1
        ld      (_tms_blanked),a
        ld      a,R1_OFF
        ld      (_vdp_r1),a
        ld      a,6
        ld      (_vdp_r2),a
        ld      a,1
        ld      (_vdp_r7),a
        ld      hl,regs
        ld      c,0
ti_r:   ld      a,(hl)
        push    hl
        push    bc
        call    reg
        pop     bc
        pop     hl
        inc     hl
        inc     c
        ld      a,c
        cp      8
        jr      c,ti_r
        ld      hl,0
        ld      de,$4000
        xor     a
        call    fill
        ld      hl,VR_NAME
        ld      e,0
        call    names
        ld      hl,VR_NAMEL
        ld      e,1
        call    names
        ld      hl,VR_NAMER
        ld      e,-1
        call    names
        ld      hl,VR_SAT
        call    waddr
        ld      a,$D0
        out     (VDP_DATA),a
        jp      unlock
regs:   defb    $02, R1_OFF, $06, $FF, $03, $36, $07, $01

; fill: DE bytes of A from VRAM HL
fill:   ld      (_va_addr),hl
        ld      (_va_len),de
        ld      (_va_val),a
        jp      _va_fill

; names: a name table at HL: the identity, the field's rows (0-20) shifted by E cells
names:  call    waddr
        ld      d,0             ; the row
nm_r:   ld      a,d
        and     7
        rrca
        rrca
        rrca                    ; (r & 7) * 32
        ld      h,a
        ld      a,d
        cp      21
        ld      l,e
        jr      c,nm_s
        ld      l,0             ; (the HUD's rows: not shifted)
nm_s:   ld      b,32
        ld      c,0
nm_c:   ld      a,c
        add     a,l
        and     31
        or      h
        out     (VDP_DATA),a
        inc     c
        djnz    nm_c
        inc     d
        ld      a,d
        cp      24
        jr      c,nm_r
        jp      unlock

; void tms_cell(uint16_t cell, const uint8_t *pat, const uint8_t *col)
_tms_cell:
        ld      hl,2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        pop     hl              ; HL the cell, DE the pattern, BC the colours
; cell: cell HL's pattern from DE, its colours from BC
cell:   push    bc
        add     hl,hl
        add     hl,hl
        add     hl,hl
        push    hl
        call    waddr
        ld      b,8
        call    out8
        call    unlock
        pop     hl
        ld      a,h
        or      $20
        ld      h,a
        call    waddr
        pop     de
        ld      b,8
        call    out8
        jp      unlock

; void tms_cell_fill(uint16_t first, uint16_t n, uint8_t pat, uint8_t col)
_tms_cell_fill:
        ld      hl,2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ex      de,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl           ; n * 8
        ex      de,hl
        ld      a,(hl)          ; pat
        inc     hl
        ld      c,(hl)          ; col
        pop     hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        push    hl
        push    de
        push    bc
        call    fill
        pop     bc
        pop     de
        pop     hl
        ld      a,h
        or      $20
        ld      h,a
        ld      a,c
        jp      fill

; ---- the text ----------------------------------------------------------------------

; glyph8: DE = glyph A's 8 bytes (A 0-63: ' ' to '_'), read from the font in
; the VRAM (3A00h: src/adam/chain.asm's art_load put it there) (keeps BC, HL)
glyph8: push    hl
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,$3A00
        add     hl,de
        call    vram8
        pop     hl
        ret

; vram8: DE = the 8 bytes at VRAM HL (a buffer's: copy them before the next
; call) (keeps BC, HL). ART_RAM (the platform's build): the art block's are
; read from its copy in RAM (_art_ram: 3800h-3BFFh as loaded): the NABU's
; PICO9918 slips a byte on sequential VRAM reads.
vram8:
IFDEF ART_RAM
        EXTERN  _art_ram
        ld      a,h
        sub     $38
        cp      4
        jr      nc,v8_vram
        push    hl
        ld      h,a
        ld      de,_art_ram
        add     hl,de
        ex      de,hl
        pop     hl
        ret
v8_vram:
ENDIF
        push    hl
        push    bc
        call    raddr
        ld      de,gbuf
        ld      b,8
g8_l:   in      a,(VDP_DATA)    ; (37 T-states a byte)
        ld      (de),a
        inc     de
        djnz    g8_l
        call    unlock
        ld      de,gbuf
        pop     bc
        pop     hl
        ret

; TEXT, TITLE, HEAD, HILITE, DIM: a byte each pixel row (ink << 4 | ground)
pals:   defb    $F4, $F4, $F4, $F4, $F4, $F4, $F4, $F4
        defb    $F6, $B6, $B6, $A6, $A6, $96, $96, $96
        defb    $17, $17, $17, $17, $17, $17, $17, $17
        defb    $4F, $4F, $4F, $4F, $4F, $4F, $4F, $4F
        defb    $E4, $E4, $E4, $E4, $E4, $E4, $E4, $E4
; the seats' colours (the tanks' too) and the ink that reads on each
_seat_col:
        defb    8, 11, 15, 3, 13, 9, 7, 10, 14, 12
seat_ink:
        defb    15, 1, 1, 1, 15, 1, 1, 1, 1, 15

; pal_of: HL = palette A's 8 bytes
pal_of: cp      PAL_SEAT
        jr      nc,po_seat
        add     a,a
        add     a,a
        add     a,a
        ld      hl,pals
        jp      add_hl_a
po_seat:
        sub     PAL_SEAT
        ld      hl,_seat_col
        call    add_hl_a
        ld      c,(hl)          ; ground: the seat's colour
        ld      de,seat_ink-_seat_col
        add     hl,de
        ld      a,(hl)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      c
        ld      hl,col8
        ld      b,7
po_l:   ld      (hl),a
        inc     hl
        djnz    po_l
        ld      a,$10           ; (a shadow line under the letters: black ink)
        or      c
        ld      (hl),a
        ld      hl,col8
        ret

add_hl_a:
        add     a,l
        ld      l,a
        ret     nc
        inc     h
        ret

; rowbits: HL = row A's 4 bytes in the table at DE
rowbits:
        add     a,a
        add     a,a
        ld      l,a
        ld      h,0
        add     hl,de
        ret

; bitof: HL += col C >> 3, A = its bit
bitof:  ld      a,c
        rrca
        rrca
        rrca
        and     3
        call    add_hl_a
        ld      a,c
        and     7
        ld      b,a
        ld      a,1
        ret     z
bo_s:   add     a,a
        djnz    bo_s
        ret

; row_colours: row A's 32 cells' colours, its palette over and over
row_colours:
        push    af
        ld      hl,scr_rpal
        call    add_hl_a
        ld      a,(hl)
        call    pal_of
        ld      de,buf
        ld      b,32
rc_l:   push    bc
        push    hl
        ld      bc,8
        ldir
        pop     hl
        pop     bc
        djnz    rc_l
        pop     af
        add     a,$20           ; VR_COL + row * 256
        ld      h,a
        ld      l,0
        ld      de,256
        ld      bc,buf
; vput: DE bytes from BC to VRAM HL: flat out while blanked
vput:   ld      (_va_addr),hl
        ld      (_va_len),de
        ld      (_va_src),bc
        ld      a,(_tms_blanked)
        or      a
        jp      nz,_va_writef
        jp      _va_write

; void scr_init(void)
_scr_init:
; void scr_begin(void): clear, every row TEXT; off
_scr_begin:
        call    _frame_wait
        ld      a,1
        call    blank
        call    _field_off
        ld      hl,VR_SAT       ; no sprites
        call    waddr
        ld      a,$D0
        out     (VDP_DATA),a
        call    unlock
        ld      a,4             ; the border: the text's ground (dark blue)
        ld      (_vdp_r7),a
        ld      c,7
        call    reg
        ld      hl,0
        ld      de,$1800
        xor     a
        call    fill
        ld      hl,VR_COL
        ld      de,$1800
        ld      a,$F4
        call    fill
        ld      hl,scr_rpal
        ld      b,ROWS
sb_r:   ld      (hl),PAL_TEXT
        inc     hl
        djnz    sb_r
        ld      hl,wrote        ; (and inv after it)
        ld      de,wrote+1
        ld      bc,ROWS*8-1
        ld      (hl),0
        ldir
        ret

; void scr_row(uint8_t row, uint8_t pal)
_scr_row:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        inc     hl
        ld      c,(hl)
        ld      e,a
        ld      hl,scr_rpal
        call    add_hl_a
        ld      a,c
        cp      (hl)
        ret     z
        ld      (hl),a
        ld      a,e
        push    af
        call    row_colours
        pop     af
        ld      de,inv
        call    rowbits
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ret

; void scr_text(uint8_t row, uint8_t col, const char *s)
_scr_text:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        ld      (t_row),a
        inc     hl
        ld      a,(hl)
        ld      (t_col),a
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (t_s),de
        ld      a,(t_row)
        ld      hl,scr_rpal
        call    add_hl_a
        ld      a,(hl)
        call    pal_of
        ld      (t_pal),hl
st_ch:  ld      a,(t_col)
        cp      32
        ret     nc
        ld      hl,(t_s)
        ld      a,(hl)
        or      a
        ret     z
        inc     hl
        ld      (t_s),hl
        cp      'a'             ; upper case; past '_': '?'
        jr      c,st_u
        cp      'z'+1
        jr      nc,st_u
        sub     32
st_u:   cp      32
        jr      c,st_q
        cp      96
        jr      c,st_g
st_q:   ld      a,'?'
st_g:   sub     32
        call    glyph8          ; DE the glyph
        ld      a,(t_row)       ; the cell: row * 32 + col
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,(t_col)
        call    add_hl_a
        ld      bc,(t_pal)
        call    cell
        ld      a,(t_row)       ; written; not inverse
        ld      de,wrote
        call    rowbits
        ld      a,(t_col)
        ld      c,a
        call    bitof
        or      (hl)
        ld      (hl),a
        ld      de,inv-wrote
        add     hl,de
        ld      a,(t_col)
        ld      c,a
        and     7
        ld      b,a
        ld      a,$FE
        jr      z,st_m
st_ms:  rlca
        djnz    st_ms
st_m:   and     (hl)
        ld      (hl),a
        ld      hl,t_col
        inc     (hl)
        jr      st_ch

; void scr_inverse(uint8_t row, uint8_t col, uint8_t n): n cells highlighted
_scr_inverse:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        ld      (t_row),a
        inc     hl
        ld      a,(hl)
        ld      (t_col),a
        inc     hl
        ld      b,(hl)          ; n, at most to the row's end
        ld      a,(t_col)
        add     a,b
        cp      33
        jr      c,si_n
        ld      a,(t_col)
        neg
        add     a,32
        ld      b,a
si_n:   ld      a,b
        or      a
        ret     z
        ld      (t_n),a
        ld      a,(t_row)       ; VR_COL + row * 256 + col * 8
        add     a,$20
        ld      h,a
        ld      a,(t_col)
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        push    hl
        ld      (_va_addr),hl
        ld      a,(t_n)
        add     a,a
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        ld      (_va_len),de
        ld      hl,buf
        ld      (_va_src),hl
        call    _va_read
        ld      hl,buf          ; ink and ground swapped
        ld      a,(_va_len)
        ld      b,a
si_s:   ld      a,(hl)
        rrca
        rrca
        rrca
        rrca
        ld      (hl),a
        inc     hl
        djnz    si_s
        pop     hl
        ld      de,(_va_len)
        ld      bc,buf
        call    vput
si_b:   ld      a,(t_row)       ; their bits
        ld      de,inv
        call    rowbits
        ld      a,(t_col)
        ld      c,a
        call    bitof
        xor     (hl)
        ld      (hl),a
        ld      hl,t_col
        inc     (hl)
        ld      hl,t_n
        dec     (hl)
        jr      nz,si_b
        ret

; void scr_clear_row(uint8_t row): the cells with letters or inverse, cleared
_scr_clear_row:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        ld      (t_row),a
        ld      hl,scr_rpal
        call    add_hl_a
        ld      a,(hl)
        call    pal_of
        ld      (t_pal),hl
        xor     a
        ld      (t_col),a
cr_c:   ld      a,(t_row)
        ld      de,wrote
        call    rowbits
        ld      a,(t_col)
        ld      c,a
        call    bitof
        ld      c,a
        and     (hl)
        ld      (t_w),a
        ld      de,inv-wrote
        add     hl,de
        ld      a,c
        and     (hl)
        ld      (t_v),a
        ld      a,(t_row)       ; the cell's VRAM: row * 256 + col * 8
        ld      h,a
        ld      a,(t_col)
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      a,(t_w)
        or      a
        jr      z,cr_v
        push    hl
        call    waddr
        ld      b,8
        ld      c,0
        call    outa
        call    unlock
        pop     hl
cr_v:   ld      a,(t_v)
        or      a
        jr      z,cr_n
        ld      a,h
        or      $20
        ld      h,a
        call    waddr
        ld      de,(t_pal)
        ld      b,8
        call    out8
        call    unlock
cr_n:   ld      hl,t_col
        inc     (hl)
        ld      a,(hl)
        cp      32
        jr      c,cr_c
        ld      a,(t_row)
        ld      de,wrote
        call    rowbits
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ld      a,(t_row)
        ld      de,inv
        call    rowbits
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ret

; void scr_scroll(uint8_t row, uint8_t n, uint8_t up): rows row..row+n-1
; move a row (up: each takes the one under it); the one left over keeps
; what it had (its caller writes it again)
_scr_scroll:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        ld      (t_row),a
        inc     hl
        ld      a,(hl)
        ld      (t_n),a
        inc     hl
        ld      a,(hl)
        ld      (t_w),a         ; up
        ld      a,(t_n)
        cp      2
        ret     c
        dec     a
        ld      (t_n),a         ; n - 1 moves
        xor     a
        ld      (t_col),a       ; i
ss_l:   ld      a,(t_w)         ; to, from
        or      a
        ld      a,(t_row)
        ld      hl,t_col
        jr      z,ss_dn
        add     a,(hl)          ; up: to = row + i, from = to + 1
        ld      d,a
        inc     a
        ld      e,a
        jr      ss_go
ss_dn:  ld      b,a             ; down: to = row + n - 1 - i (n-1 here: + 1), from = to - 1
        ld      a,(t_n)
        add     a,b
        sub     (hl)
        ld      d,a
        dec     a
        ld      e,a
ss_go:  ld      a,e             ; rpal[to] = rpal[from]
        ld      hl,scr_rpal
        call    add_hl_a
        ld      a,(hl)
        push    af
        ld      a,d
        ld      hl,scr_rpal
        call    add_hl_a
        pop     af
        ld      (hl),a
        push    de              ; the masks
        ld      a,e
        ld      de,wrote
        call    rowbits
        push    hl
        pop     bc
        pop     de
        push    de
        ld      a,d
        push    bc
        ld      de,wrote
        call    rowbits
        pop     de
        ex      de,hl           ; HL from, DE to
        ld      bc,4
        push    hl
        push    de
        ldir
        pop     de
        pop     hl
        ld      bc,inv-wrote
        add     hl,bc
        ex      de,hl
        add     hl,bc
        ex      de,hl
        ld      bc,4
        ldir
        pop     de
        ld      h,e             ; the patterns' row, then the colours'
        ld      l,0
        ld      b,d
        push    de
        call    copy_row
        pop     de
        ld      a,e
        add     a,$20
        ld      h,a
        ld      l,0
        ld      a,d
        add     a,$20
        ld      b,a
        call    copy_row
        ld      hl,t_col
        inc     (hl)
        ld      a,(t_n)
        cp      (hl)
        jr      nz,ss_l
        ret

; copy_row: VRAM HL's 256 bytes to VRAM B * 256
copy_row:
        push    bc
        ld      (_va_addr),hl
        ld      hl,256
        ld      (_va_len),hl
        ld      hl,buf
        ld      (_va_src),hl
        call    _va_read
        pop     bc
        ld      h,b
        ld      l,0
        ld      de,256
        ld      bc,buf
        jp      vput

; void scr_show(void): on, from the next frame
_scr_show:
        call    _frame_wait
        xor     a
        jp      blank

        SECTION bss_user
_tms_blanked:   defs    1
scr_rpal:       defs    ROWS
wrote:          defs    ROWS*4
inv:            defs    ROWS*4
col8:           defs    8
gbuf:           defs    8
buf:            defs    256
t_row:          defs    1
t_col:          defs    1
t_s:            defs    2
t_pal:          defs    2
t_n:            defs    1
t_w:            defs    1
t_v:            defs    1
