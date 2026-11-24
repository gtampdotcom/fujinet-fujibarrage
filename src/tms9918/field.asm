; field.asm -- the field (field.h) on a TMS9918: the store and its renderer
; (fld.asm, render.asm), the tanks as sprites, the HUD and the talk on the
; text's cells. (It was field.c: in assembler it is a third the size.)
;
; The round's look is a style a line (render.asm's tables), solid colours,
; no dither (it muddies the tanks): the sky in bands of its colours down
; the field (a gradient, a sunset), or black with stars; the dirt in
; strata of its bright and its dark colour, never the sky's colour on the
; same line; the fire in bands.
;
; The tanks are 8x8 sprites in their seats' colours, the foot at the
; sprite's bottom. The VDP shows only four on a line: yours, the turn's and
; the rest in that order take them while a line has room; a tank that would
; be a fifth is drawn in the bitmap instead (its cells marked: render.asm
; calls ovl_cell), in its colour over whichever of the run's colours it
; covers more of.
;
; The HUD is the text's last three rows, white on black (row 0's name in
; its seat's colour), only the cells that change written. A tank's talk is
; a balloon of whole cells over it: the cells it covers are the balloon's
; till it goes, then drawn from the store again.
;
; C's arguments are on the stack (zsdcc: right to left, a byte as a byte);
; IX and IY are kept.

        SECTION code_user

        INCLUDE "proto.inc"

        PUBLIC  _field_init, _field_loading, _field_open, _field_off, _field_column, _field_columns
        PUBLIC  _field_plot, _field_get, _field_swap, _field_span, _field_ellipse
        PUBLIC  _field_tank, _field_colours, _ovl_cell, _field_frame
        PUBLIC  _field_status, _field_status_hi, _field_status_clear, _field_balloon
        PUBLIC  _field_flash, _field_fire, _tms_idle, _tms_frame

        EXTERN  _fx, _fy, _fx1, _fv, _fold, _fent, _ex, _ey, _erx, _ery, _emode
        EXTERN  _fld_cols, _fld_ncols
        EXTERN  _fld_col, _fld_plot, _fld_get, _fld_swap, _fld_hspan, _fld_ellipse
        EXTERN  _fld_clear, _fld_mark_all, _fld_flush1, _fld_flushn
        EXTERN  _fld_budget, _rnd_fast, _fld_live, _fld_dirty, _fld_rowd, _fld_nd
        EXTERN  _st_line, _st_fire, _st_stars, _fire_ph
        EXTERN  _rc_pat, _rc_col, _rc_cell
        EXTERN  _seat_col, glyph8, vram8, _st, _my_seat, _tk
        EXTERN  _plat_rand, _frame_wait, _tms_blank, _tms_blanked, _vdp_reg
        EXTERN  _va_addr, _va_src, _va_len, _va_write, _va_writef
        EXTERN  _vdp_r7, _vdp_busy, _vdp_pend, _vdp_catch_up, _gfx_fast, _shake_dx, _flash_n

        INCLUDE "tms9918/style.inc"
        PUBLIC  _ao_lim
        defc    _ao_lim = ao_lim + 1
IFDEF F18A_HOOK
        EXTERN  _f18a, _f18a_look, _f18a_off, _f18a_fire
ENDIF
        defc    FIELD_H = 168
        defc    HUD_ROW = 21
        defc    CF_DIRTY = 1
        defc    CF_COVER = 2
        defc    CF_TANK = 4
        defc    CF_FIRE = 8             ; (render.asm's: drawn with fire)
        defc    FIRE_EVERY = 8          ; frames a step of the fire's colours
        defc    FROWS = 21
        defc    VR_SPAT = $3800
        defc    VR_SAT = $1B00
        defc    C_BLACK = 1
        defc    C_DYELLOW = 10
        defc    C_GREY = 14
        defc    C_WHITE = 15
        defc    TD_SIZE = 6             ; td: x (2), y, angle, on, me
        defc    OV_SIZE = 12            ; ovl: x (2), y, colour, its pattern's 8 rows
        defc    LMAX = 30               ; the balloon's line
        INCLUDE "vdpio.inc"     ; VDP_DATA, VDP_CTRL (the platform's)

; ---- the round's look ---------------------------------------------------------

; SKY_*: the colours down the sky (the count first); stars: black
skies:  defb    2, 5, 5, 0, 0, 0                ; plain: light blue
        defb    3, 4, 5, 7, 0, 0                ; gradient: dark blue, light blue, cyan
        defb    2, 1, 1, 0, 0, 0                ; stars: black
        defb    3, 1, 4, 14, 0, 0               ; storm: black, dark blue, grey
        defb    5, 4, 13, 8, 9, 10              ; sunset: dark blue, magenta, red, light red, gold
        defb    2, 1, 6, 0, 0, 0                ; cavern: black, dark red
        defb    2, 1, 1, 0, 0, 0                ; black
        defb    3, 4, 5, 7, 0, 0                ; random: as gradient
; the dirt palettes: bright (near the top), dark (deep)
dirts:  defb    10, 6, 2, 12, 14, 1, 8, 6, 11, 10, 5, 4, 13, 4, 11, 8
; the fire's bands (ink nibbles)
fires:  defb    $F0, $B0, $B0, $A0, $90, $80, $90, $A0

; styles: the line tables for sky A, dirt palette B
styles: ld      a,b
        and     7
        add     a,a
        ld      hl,dirts
        call    add_hl_a
        ld      a,(hl)
        ld      (sy_d0),a
        inc     hl
        ld      a,(hl)
        ld      (sy_d1),a
        ld      a,c
        and     7
        ld      (sy_sky),a
        ld      b,a
        add     a,a
        add     a,b
        add     a,a             ; * 6
        ld      hl,skies
        call    add_hl_a
        ld      (sy_s),hl
        ld      a,(hl)
        dec     a
        add     a,a
        ld      (sy_m),a        ; m = 2 (n - 1): bands of half a stop
        ld      a,(sy_sky)
        cp      SKY_STARS
        ld      a,0
        jr      nz,sy_ns
        inc     a
sy_ns:  ld      (_st_stars),a
        xor     a
        ld      (sy_y),a
        ld      (sy_q),a
        ld      (sy_acc),a
        ld      (sy_l),a
        ld      (sy_acc2),a
        ld      (sy_c9),a
        ld      (sy_band),a
sy_line:
        ; the sky
        ld      a,(_st_stars)
        or      a
        jr      z,sy_bands
        call    _plat_rand      ; (the line's stars: render.asm hashes it)
        ld      a,l
        call    sy_put_skyp
        ld      a,(sy_y)        ; white, a grey line in three
        ld      b,3
sy_mod: sub     b
        jr      nc,sy_mod
        add     a,b
        ld      a,C_WHITE * 16 + C_BLACK
        jr      nz,sy_w
        ld      a,C_GREY * 16 + C_BLACK
sy_w:   ld      hl,_st_line+L_SKYC
        call    sy_store
        ld      a,C_BLACK
        ld      (sy_smain),a
        jr      sy_dirt
sy_bands:
        ld      a,(sy_q)        ; the band: s[1 + (q + 1) / 2]
        inc     a
        srl     a
        inc     a
        ld      hl,(sy_s)
        call    add_hl_a
        ld      a,(hl)
        ld      (sy_smain),a
        ld      b,a
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      b
        ld      hl,_st_line+L_SKYC
        call    sy_store
        xor     a
        call    sy_put_skyp
        ld      a,(sy_m)        ; q = y * m / 168, stepped
        ld      b,a
        ld      a,(sy_acc)
        add     a,b
        cp      FIELD_H
        jr      c,sy_q1
        sub     FIELD_H
        ld      hl,sy_q
        inc     (hl)
sy_q1:  ld      (sy_acc),a
sy_dirt:
        ; the dirt: level y * 12 / 168, +4 in every third 9-line band
        ld      a,(sy_band)
        cp      1
        ld      a,(sy_l)
        jr      nz,sy_d1x
        add     a,4
sy_d1x: cp      8
        ld      a,(sy_d0)
        jr      c,sy_dm
        ld      a,(sy_d1)
sy_dm:  ld      b,a
        ld      a,(sy_smain)
        cp      b
        jr      nz,sy_dok
        ld      a,(sy_d0)       ; (the sky's colour: the other one)
        cp      b
        jr      nz,sy_dset
        ld      a,(sy_d1)
sy_dset:
        ld      b,a
        ld      a,(sy_smain)
        cp      b
        jr      nz,sy_dok
        ld      b,C_GREY        ; (both the sky's: grey, or gold on grey)
        cp      C_GREY
        jr      nz,sy_dok
        ld      b,C_DYELLOW
sy_dok: ld      a,b
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      c,a             ; dmain << 4
        or      b
        ld      hl,_st_line+L_DIRTC
        call    sy_store
        xor     a
        ld      hl,_st_line+L_DIRTP
        call    sy_store
        ld      a,(sy_smain)
        or      c
        ld      hl,_st_line+L_MIXC
        call    sy_store
        ld      a,(sy_acc2)     ; l = y * 12 / 168, stepped
        add     a,12
        cp      FIELD_H
        jr      c,sy_l1
        sub     FIELD_H
        ld      hl,sy_l
        inc     (hl)
sy_l1:  ld      (sy_acc2),a
        ld      a,(sy_c9)       ; the 9-line bands
        inc     a
        cp      9
        jr      c,sy_c9x
        ld      a,(sy_band)
        inc     a
        cp      3
        jr      c,sy_b3
        xor     a
sy_b3:  ld      (sy_band),a
        xor     a
sy_c9x: ld      (sy_c9),a
        ld      hl,sy_y
        inc     (hl)
        ld      a,(hl)
        cp      FIELD_H
        jp      c,sy_line
        ld      hl,fires
        ld      de,_st_fire
        ld      bc,8
        ldir
        xor     a
        ld      (_fire_ph),a
        ret

sy_put_skyp:
        ld      hl,_st_line+L_SKYP
; sy_store: line sy_y's record, field HL (st_line + L_x) = A (keeps BC, DE)
sy_store:
        push    de
        push    af
        ex      de,hl
        ld      a,(sy_y)
        call    rec5
        add     hl,de
        pop     af
        pop     de
        ld      (hl),a
        ret

; rec5: HL = A * 5 (a line's record's offset; keeps BC, DE)
rec5:   ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        jp      add_hl_a

; HL += A
add_hl_a:
        add     a,l
        ld      l,a
        ret     nc
        inc     h
        ret

; ---- the field ------------------------------------------------------------------

; void field_init(void)
_field_init:                    ; (the sprites' patterns: art_load's)
        xor     a
        ld      (_fld_live),a
        call    _fld_clear
        ld      bc,SKY_GRADIENT
        jp      styles

; void field_loading(void): (the store isn't the screen: a field that comes
; over a text screen fills it, and field_open draws it)
_field_loading:
        ret

; void field_open(uint8_t sky, uint8_t pal)
_field_open:
        ld      hl,2
        add     hl,sp
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        push    bc
        ld      a,(_tms_blanked)
        or      a
        jr      nz,fo_bl
        call    _frame_wait
        ld      a,1
        call    blank
fo_bl:  pop     bc
IFDEF F18A_HOOK
        push    bc
        call    styles
        pop     hl              ; (L sky, H pal: f18a_look(sky, pal), as zsdcc pushes them)
        push    hl
        call    _f18a_look      ; (an F18A: the VGA build's look, src/nabu/f18a.c)
        pop     hl
ELSE
        call    styles
ENDIF
        ld      a,C_BLACK
        ld      (_vdp_r7),a
        ld      h,a
        ld      l,7
        push    hl
        call    _vdp_reg        ; (vdp_reg(7, black): r the lower byte, as zsdcc pushes them)
        pop     hl
        ld      hl,_fld_dirty
        ld      de,_fld_dirty+1
        ld      bc,21 * 32 - 1
        ld      (hl),0
        ldir
        xor     a
        ld      (b_on),a
        ld      (ovl_n),a
        inc     a
        ld      (_fld_live),a
        call    _fld_mark_all
fo_draw:
        call    _fld_flush1     ; (blanked: flat out)
        ld      a,l
        or      a
        jr      nz,fo_draw
        call    hud_reset
        ld      a,1
        ld      (tanks_dirty),a
        xor     a
        ld      (fire_on),a
        call    _frame_wait
        xor     a
; blank: the display blanked (A 1) or shown (A 0)
blank:  push    af
        inc     sp
        call    _tms_blank
        inc     sp
        ret

; void field_off(void): a text screen comes up
_field_off:
        xor     a
        ld      (_fld_live),a
        ld      (b_on),a
        ld      (ovl_n),a
IFDEF F18A_HOOK
        jp      _f18a_off
ELSE
        ret
ENDIF

; void field_column(uint16_t x, const uint8_t *entry)
_field_column:
        ld      hl,2
        add     hl,sp
        call    word
        ld      (_fx),de
        call    word
        ld      (_fent),de
        jp      _fld_col

; void field_columns(uint16_t x, const uint8_t *entry, uint16_t n): n
; columns from x, their entries one after another (fld_cols: the columns
; of a byte written together, 128 at a time)
_field_columns:
        ld      hl,2
        add     hl,sp
        call    word
        ld      (_fx),de
        call    word
        ld      (_fent),de
        call    word            ; DE n
fcs_l:  ld      a,d
        or      e
        ret     z
        ld      hl,128
        ex      de,hl
        or      a
        sbc     hl,de           ; n - 128
        jr      nc,fcs_k        ; (128 of them, n - 128 left)
        add     hl,de
        ld      e,l             ; (all n)
        ld      hl,0
fcs_k:  push    hl
        ld      a,e
        ld      (_fld_ncols),a
        call    _fld_cols       ; (fx, fent past them)
        pop     de
        jr      fcs_l

; word: DE = (HL), HL past it
word:   ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ret

; xy: fx, fy from the stack at HL
xy:     call    word
        ld      (_fx),de
        call    word
        ld      (_fy),de
        ret

; void field_plot(int16_t x, int16_t y, uint8_t v)
_field_plot:
        ld      hl,2
        add     hl,sp
        call    xy
        ld      a,(hl)
        ld      (_fv),a
        jp      _fld_plot

; uint8_t field_get(int16_t x, int16_t y)
_field_get:
        ld      hl,2
        add     hl,sp
        call    xy
        jp      _fld_get

; void field_swap(int16_t x, int16_t y, uint8_t from, uint8_t to)
_field_swap:
        ld      hl,2
        add     hl,sp
        call    xy
        ld      a,(hl)
        ld      (_fold),a
        inc     hl
        ld      a,(hl)
        ld      (_fv),a
        jp      _fld_swap

; void field_span(int16_t y, int16_t x0, int16_t x1, uint8_t v)
_field_span:
        ld      hl,2
        add     hl,sp
        call    word
        ld      (_fy),de
        call    word
        ld      (_fx),de
        call    word
        ld      (_fx1),de
        ld      a,(hl)
        ld      (_fv),a
        jp      _fld_hspan

; void field_ellipse(int16_t x, int16_t y, uint8_t rx, uint8_t ry, uint8_t v, uint8_t mode)
_field_ellipse:
        ld      hl,2
        add     hl,sp
        call    word
        ld      (_ex),de
        call    word
        ld      (_ey),de
        ld      a,(hl)          ; rx: 0 is 1
        or      a
        jr      nz,fe_rx
        inc     a
fe_rx:  ld      (_erx),a
        inc     hl
        ld      a,(hl)          ; ry: 1-200
        or      a
        jr      nz,fe_ry
        inc     a
fe_ry:  cp      201
        jr      c,fe_ry2
        ld      a,200
fe_ry2: ld      (_ery),a
        inc     hl
        ld      a,(hl)
        ld      (_fv),a
        inc     hl
        ld      a,(hl)
        ld      (_emode),a
        jp      _fld_ellipse

; ---- cells -------------------------------------------------------------------

; cell_dirty: cell HL dirty (keeps BC, DE)
cell_dirty:
        push    de
        ld      de,_fld_dirty
        add     hl,de
        bit     0,(hl)
        jr      nz,cd_x
        set     0,(hl)
        or      a
        sbc     hl,de           ; (the cell again)
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,h             ; its row: cell >> 5
        ld      hl,_fld_rowd
        call    add_hl_a
        inc     (hl)
        ld      hl,(_fld_nd)
        inc     hl
        ld      (_fld_nd),hl
cd_x:   pop     de
        ret

; text_cell: character A at cell HL, colour C (both ink and ground's byte)
; (keeps IX, IY)
text_cell:
        cp      'a'
        jr      c,tc_u
        cp      'z' + 1
        jr      nc,tc_u
        sub     32
tc_u:   cp      32
        jr      c,tc_sp
        cp      96
        jr      c,tc_ok
tc_sp:  ld      a,' '
tc_ok:  sub     32
        call    glyph8          ; DE the glyph
        add     hl,hl
        add     hl,hl
        add     hl,hl           ; HL the cell's VRAM offset
        ld      a,1
        ld      (_vdp_busy),a
        ld      a,l
        out     (VDP_CTRL),a
        ld      a,h
        or      $40
        out     (VDP_CTRL),a
        ld      b,8
tc_p:   ld      a,(de)          ; (38 T-states a byte: the VDP's 8 us)
        out     (VDP_DATA),a
        inc     de
        djnz    tc_p
        ld      a,l
        out     (VDP_CTRL),a
        ld      a,h
        or      $60
        out     (VDP_CTRL),a
        ld      b,8
tc_c:   ld      a,c
        out     (VDP_DATA),a
        nop
        nop
        djnz    tc_c
        xor     a
        ld      (_vdp_busy),a
        ld      a,(_vdp_pend)
        or      a
        ret     z
        jp      _vdp_catch_up

; ---- the tanks ------------------------------------------------------------------

; void field_tank(uint8_t s, uint8_t draw): tk[s] as it is drawn (or off)
_field_tank:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        ld      (ft_s),a
        ld      c,a
        inc     hl
        ld      a,(hl)          ; draw
        or      a
        jr      z,ft_o
        call    tk_at
        ld      a,(hl)          ; tk[s].on
        or      a
        jr      z,ft_o
        ld      a,1
ft_o:   ld      (ft_new+4),a
        ld      hl,ft_new       ; x, y, angle: tk's, or 0s when off
        ld      b,4
ft_z:   ld      (hl),0
        inc     hl
        djnz    ft_z
        inc     hl
        ld      (hl),0          ; (me)
        or      a
        jr      z,ft_cmp
        call    tk_at
        inc     hl
        ld      de,ft_new
        ld      bc,4
        ldir
        ld      a,(ft_s)
        ld      c,a
        ld      a,(_my_seat)
        cp      c
        jr      nz,ft_cmp
        ld      a,1
        ld      (ft_new+5),a
ft_cmp: ld      a,(ft_s)        ; the same as drawn: nothing
        ld      c,a
        call    td_at
        ld      de,ft_new
        ld      b,TD_SIZE
ft_c:   ld      a,(de)
        cp      (hl)
        jr      nz,ft_cp
        inc     de
        inc     hl
        djnz    ft_c
        ret
ft_cp:  call    td_at
        ex      de,hl
        ld      hl,ft_new
        ld      bc,TD_SIZE
        ldir
; void field_colours(void): the tanks moved: their sprites again
_field_colours:
        ld      a,1
        ld      (tanks_dirty),a
        ret

; tk_at: HL = &tk[C] (5 bytes each: on, x (2), y, angle)
tk_at:  ld      a,c
        add     a,a
        add     a,a
        add     a,c
        ld      hl,_tk
        jp      add_hl_a

; td_at: HL = &td[C]
td_at:  ld      a,c
        add     a,a
        add     a,c
        add     a,a
        ld      hl,td
        jp      add_hl_a

; tank_col: A = seat al_s's colour, or black (white on a dark sky) where
; its sky (al_y - 4's) is that colour: a tank never vanishes into its sky
tank_col:
        push    hl
        ld      a,(al_s)
        ld      hl,_seat_col
        call    add_hl_a
        ld      c,(hl)
        ld      a,(al_y)
        sub     4
        jr      nc,tcl_y
        xor     a
tcl_y:  push    de
        call    rec5
        ld      de,_st_line+L_SKYC
        add     hl,de
        pop     de
        ld      a,(_st_stars)
        or      a
        ld      a,(hl)
        jr      z,tcl_s
        ld      a,C_BLACK       ; (the stars' sky is black)
tcl_s:  and     $0F
        cp      c
        ld      a,c
        jr      nz,tcl_x
        ld      a,(hl)
        and     $0F
        cp      C_BLACK
        ld      a,C_WHITE
        jr      z,tcl_x
        ld      a,(hl)
        and     $0F
        cp      4               ; (dark blue)
        ld      a,C_WHITE
        jr      z,tcl_x
        ld      a,C_BLACK
tcl_x:  pop     hl
        ret

; pattern: A the sprite name for td record HL (its angle, yours or not)
pattern:
        push    hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)          ; angle
        cp      181
        jr      c,pt_a
        ld      a,180
pt_a:   add     a,5
        ld      b,-1
pt_d:   inc     b               ; / 10
        sub     10
        jr      nc,pt_d
        inc     hl
        inc     hl
        ld      a,(hl)          ; me: 19 on
        or      a
        ld      a,b
        jr      z,pt_x
        add     a,19
pt_x:   pop     hl
        ret

; ovl_cells: the cells of a tank at x DE, foot y A: CF_TANK set (C 1) or
; cleared (C 0), each drawn again
ovl_cells:
        ld      (oc_set),bc
        ld      (oc_y),a
        ld      hl,-3
        add     hl,de           ; x0
        bit     7,h
        ld      a,0
        jr      nz,oc_c0
        ld      a,l
        srl     h
        rra
        srl     h
        rra
        srl     h
        rra
oc_c0:  ld      (oc_cx0),a
        ld      hl,4
        add     hl,de           ; x0 + 7
        ld      a,l
        srl     h
        rra
        srl     h
        rra
        srl     h
        rra
        cp      32
        jr      c,oc_c1
        ld      a,31
oc_c1:  ld      (oc_cx1),a
        ld      a,(oc_y)        ; y0 = y - 8; rows (y0 < 0 ? 0 : y0 / 8) .. (y - 1) / 8
        or      a
        ret     z
        sub     8
        jr      nc,oc_r0
        xor     a
oc_r0:  rrca
        rrca
        rrca
        and     31
        ld      (oc_r),a
        ld      a,(oc_y)
        dec     a
        rrca
        rrca
        rrca
        and     31
        cp      21
        jr      c,oc_r1
        ld      a,20
oc_r1:  ld      (oc_r1v),a
oc_row: ld      a,(oc_cx0)
        ld      (oc_c),a
oc_col: ld      a,(oc_r)        ; the cell: r * 32 + c
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,(oc_c)
        call    add_hl_a
        push    hl
        ld      de,_fld_dirty
        add     hl,de
        ld      a,(oc_set)
        or      a
        jr      z,oc_clr
        set     2,(hl)
        jr      oc_d
oc_clr: res     2,(hl)
oc_d:   pop     hl
        call    cell_dirty
        ld      hl,oc_c         ; (the column it was: the last?)
        ld      a,(hl)
        inc     (hl)
        ld      hl,oc_cx1
        cp      (hl)
        jr      nz,oc_col
        ld      hl,oc_r
        ld      a,(hl)
        inc     (hl)
        ld      hl,oc_r1v
        cp      (hl)
        jr      nz,oc_row
        ret

; allocate: which tanks get sprites; the rest into the bitmap
allocate:
        ld      a,(ovl_n)       ; the old ones' cells as they were
        or      a
        jr      z,al_new
        ld      b,a
        ld      hl,ovl
al_old: push    bc
        push    hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      c,0
        call    ovl_cells
        pop     hl
        ld      de,OV_SIZE
        add     hl,de
        pop     bc
        djnz    al_old
al_new: xor     a
        ld      (ovl_n),a
        ld      hl,lines
        ld      de,lines+1
        ld      bc,FIELD_H + 8 - 1
        ld      (hl),a
        ldir
        ld      hl,sat
        ld      (al_p),hl
        ; the order: yours, the turn's, the rest
        ld      a,(_my_seat)
        cp      SEATS
        call    c,al_one
        ld      a,(_st+OFF_TURN)
        cp      SEATS
        jr      nc,al_rest
        ld      hl,_my_seat
        cp      (hl)
        call    nz,al_one
al_rest:
        xor     a
al_r:   push    af
        ld      hl,_my_seat
        cp      (hl)
        jr      z,al_skip
        ld      hl,_st+OFF_TURN
        cp      (hl)
        call    nz,al_one
al_skip:
        pop     af
        inc     a
        cp      SEATS
        jr      c,al_r
        ld      hl,(al_p)
        ld      (hl),$D0
        ld      de,sat
        or      a
        sbc     hl,de
        ld      a,l
        ld      (sat_n),a
        ld      a,1
        ld      (sat_dirty),a
        xor     a
        ld      (tanks_dirty),a
        ret

; al_one: tank A: a sprite if its lines have room, else the bitmap
al_one: ld      c,a
        ld      (al_s),a
        call    td_at
        ld      (al_td),hl
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)          ; on
        or      a
        ret     z
        dec     hl
        dec     hl
        ld      a,(hl)          ; y (at most the field's lines)
        cp      FIELD_H + 1
        jr      c,ao_y
        ld      a,FIELD_H
ao_y:   ld      (al_y),a
        ld      hl,lines        ; its lines: y-8 .. y-1, lines[y .. y+7]
        call    add_hl_a
        ld      (al_l),hl
        ld      b,8
        xor     a
ao_m:   cp      (hl)
        jr      nc,ao_m1
        ld      a,(hl)
ao_m1:  inc     hl
        djnz    ao_m
ao_lim: cp      4               ; (the VDP's four a line: an F18A's more, ao_lim)
        jr      nc,ao_ovl
        ld      hl,(al_l)
        ld      b,8
ao_i:   inc     (hl)
        inc     hl
        djnz    ao_i
        ld      hl,(al_td)
        call    pattern
        ld      (al_n),a
        ld      hl,(al_td)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,-3
        add     hl,de           ; x - 3
        ld      de,(al_p)
        ld      a,(al_y)
        sub     9
        ld      (de),a          ; Y
        inc     de
        call    tank_col
        ld      c,a
        bit     7,h
        ld      a,l
        jr      z,ao_x
        add     a,32            ; off the left: EC, 32 pixels
        set     7,c
ao_x:   ld      (de),a
        inc     de
        ld      a,(al_n)
        ld      (de),a
        inc     de
        ld      a,c
        ld      (de),a
        inc     de
        ld      (al_p),de
        ret
ao_ovl: ld      a,(ovl_n)       ; into the bitmap
        ld      b,a
        add     a,a
        add     a,b
        add     a,a
        add     a,a             ; (* 12)
        ld      hl,ovl
        call    add_hl_a
        push    hl
        ld      hl,(al_td)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        pop     hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,(al_y)
        ld      (hl),a
        inc     hl
        push    bc
        call    tank_col
        pop     bc
        ld      (hl),a
        inc     hl
        push    hl
        push    de
        ld      hl,(al_td)
        call    pattern
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      bc,VR_SPAT
        add     hl,bc
        call    vram8           ; DE its rows (the sprite's, in the VRAM)
        pop     bc              ; (x)
        pop     hl
        ex      de,hl
        push    bc
        ld      bc,8
        ldir                    ; into the record
        pop     de              ; (x)
        ld      a,(al_y)
        ld      c,1
        call    ovl_cells
        ld      hl,ovl_n
        inc     (hl)
        ret

; void ovl_cell(void): render.asm's cell (rc_cell, rc_pat, rc_col) with the
; tanks drawn in the bitmap over it
_ovl_cell:
        ld      a,(_rc_cell)
        ld      (oc_px),a       ; its x (column * 8)
        ld      a,(_rc_cell+1)
        add     a,a
        add     a,a
        add     a,a
        ld      (oc_py),a       ; its first line
        ld      c,0             ; k
oo_run: ld      a,(oc_py)
        add     a,c
        ld      (oc_ln),a
        ld      b,0             ; t: the tanks' bits in this run
        ld      a,(ovl_n)
        or      a
        ret     z
        ld      (oc_i),a
        ld      hl,ovl
        ld      (oc_rp),hl
oo_t:   ld      hl,(oc_rp)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)          ; x
        inc     hl
        ld      a,(oc_ln)       ; its lines: y-8 .. y-1
        add     a,8
        sub     (hl)
        jr      c,oo_n          ; line < y - 8
        cp      8
        jr      nc,oo_n         ; line >= y
        push    af              ; the pattern's row
        inc     hl
        ld      a,(hl)
        ld      (oc_tc),a       ; (its colour)
        inc     hl              ; (its rows)
        pop     af
        call    add_hl_a
        ld      a,(hl)          ; the row's bits
        ld      (oc_bits),a
        ld      hl,-3           ; dx = x - 3 - px
        add     hl,de
        ld      a,(oc_px)
        ld      e,a
        ld      d,0
        or      a
        sbc     hl,de
        ld      a,(oc_bits)
        bit     7,h
        jr      nz,oo_neg
        ld      d,a
        ld      a,h
        or      a
        jr      nz,oo_n         ; (8 or more right)
        ld      a,l
        cp      8
        jr      nc,oo_n
        or      a
        ld      a,d
        jr      z,oo_or
oo_r:   srl     a
        dec     l
        jr      nz,oo_r
        jr      oo_or
oo_neg: ld      d,a             ; dx < 0: left by -dx
        ld      a,l
        neg
        cp      8
        jr      nc,oo_n
        ld      l,a
        ld      a,d
oo_l:   add     a,a
        dec     l
        jr      nz,oo_l
oo_or:  or      a
        jr      z,oo_n          ; (nothing of it in this run)
        or      b
        ld      b,a
        ld      a,(oc_tc)
        ld      (oc_fg),a
oo_n:   ld      hl,(oc_rp)
        ld      de,OV_SIZE
        add     hl,de
        ld      (oc_rp),hl
        ld      hl,oc_i
        dec     (hl)
        jr      nz,oo_t
oo_done:
        ld      a,b
        or      a
        jr      z,oo_next
        ; the rest of the run: its more common colour behind the tank
        ld      hl,_rc_pat
        ld      a,c
        call    add_hl_a
        ld      a,b
        cpl
        ld      d,a             ; ~t
        and     (hl)            ; the ink's pixels left
        call    pop8
        ld      e,a
        ld      a,(hl)
        cpl
        and     d               ; the ground's
        call    pop8
        cp      e
        ld      (hl),b          ; the pattern: the tanks
        push    af
        ld      hl,_rc_col
        ld      a,c
        call    add_hl_a
        pop     af
        ld      a,(hl)
        jr      nc,oo_bg        ; ground as many or more
        rrca
        rrca
        rrca
        rrca
oo_bg:  and     $0F
        ld      e,a
        ld      a,(oc_fg)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      e
        ld      (hl),a
oo_next:
        inc     c
        ld      a,c
        cp      8
        jp      c,oo_run
        ret

; pop8: A = the bits set in A (keeps BC, DE, HL)
pop8:   push    bc
        ld      b,8
        ld      c,0
p8_l:   rlca
        jr      nc,p8_n
        inc     c
p8_n:   djnz    p8_l
        ld      a,c
        pop     bc
        ret

; ---- the frame: the sprites, then a burst of cells while it's blank -----------

; void tms_idle(void): waiting for a frame: a changed cell of the field drawn
_tms_idle:
        ld      a,(_fld_live)
        or      a
        ret     z
        jp      _fld_flush1

; void tms_frame(void): a frame came: the field's sprites and a burst of its cells
_tms_frame:

; void field_frame(void)
_field_frame:
        ld      a,(_fld_live)
        or      a
        ret     z
        ld      a,(fire_on)     ; the fire's colours: a step up a band
        or      a
        call    nz,fire_step
        ld      a,(tanks_dirty)
        or      a
        call    nz,allocate
        ld      a,(_shake_dx)
        ld      hl,sat_dx
        cp      (hl)
        jr      nz,ff_sat
        ld      a,(sat_dirty)
        or      a
        jr      z,ff_burst
ff_sat: ld      a,(_shake_dx)
        ld      (sat_dx),a
        ld      hl,sat          ; a copy, the shake's x on each sprite
        ld      de,satout
        ld      a,(sat_n)
        inc     a
        ld      c,a
        ld      b,0
        ldir
        ld      a,(sat_n)
        or      a
        jr      z,ff_w
        rrca
        rrca
        and     $3F
        ld      b,a             ; the sprites
        ld      hl,satout+1
        ld      a,(sat_dx)
        ld      c,a
ff_dx:  ld      a,(hl)
        add     a,c
        ld      (hl),a
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        djnz    ff_dx
ff_w:   ld      hl,VR_SAT
        ld      (_va_addr),hl
        ld      hl,satout
        ld      (_va_src),hl
        ld      a,(sat_n)
        inc     a
        ld      l,a
        ld      h,0
        ld      (_va_len),hl
        ld      a,(_gfx_fast)
        or      a
        jr      z,ff_slow
        call    _va_writef
        jr      ff_sd
ff_slow:
        call    _va_write
ff_sd:  xor     a
        ld      (sat_dirty),a
ff_burst:
        ld      a,(_gfx_fast)
        or      a
        ret     z
        ld      hl,(_fld_nd)
        ld      a,h
        or      l
        ret     z
        ld      a,1
        ld      (_rnd_fast),a
        ld      a,6
        ld      (_fld_budget),a
        call    _fld_flushn
        xor     a
        ld      (_rnd_fast),a
        ret

; ---- the HUD: the text's last three rows ------------------------------------------

hud_reset:
        ld      hl,HUD_ROW * 32
        ld      b,96
hr_l:   push    bc
        push    hl
        ld      a,' '
        ld      c,C_WHITE * 16 + C_BLACK
        call    text_cell
        pop     hl
        inc     hl
        pop     bc
        djnz    hr_l
        ld      hl,hud_ch
        ld      de,hud_ch+1
        ld      bc,95
        ld      (hl),' '
        ldir
        ld      hl,hud_at
        ld      de,hud_at+1
        ld      bc,95
        ld      (hl),0
        ldir
        ret

; void field_status(uint8_t row, uint8_t col, const char *s)
_field_status:
        xor     a
        jr      hud_text
; void field_status_hi(...): the same, inverse
_field_status_hi:
        ld      a,1
hud_text:
        ld      (ht_hi),a
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        ld      (ht_row),a
        inc     hl
        ld      a,(hl)
        ld      (ht_col),a
        inc     hl
        call    word
        ld      (ht_s),de
; hud_go: ht_row, ht_col, ht_s, ht_hi
hud_go: xor     a
        ld      (ht_name),a
        ld      a,(ht_row)      ; row 0 from column 0: its name in the seat's colour
        ld      b,a
        ld      a,(ht_col)
        or      b
        jr      nz,ht_go
        ld      a,(_st+OFF_TURN)
        cp      SEATS
        jr      c,ht_s1
        ld      a,(_my_seat)
        cp      SEATS
        jr      c,ht_s1
        xor     a
ht_s1:  ld      (ht_seat),a
        ld      c,a             ; its name: st + OFF_SEATS + seat * 25
        add     a,a
        add     a,a
        add     a,a
        ld      b,a             ; 8s
        add     a,a             ; 16s
        add     a,b
        add     a,c             ; 25s
        ld      l,a
        ld      h,0
        ld      de,_st+OFF_SEATS+P_NAME
        add     hl,de
        ld      b,NAME_LEN
        ld      c,0
ht_nl:  ld      a,(hl)
        or      a
        jr      z,ht_nx
        inc     hl
        inc     c
        djnz    ht_nl
ht_nx:  ld      a,c
        ld      (ht_name),a
ht_go:  ld      a,(ht_row)      ; hud_ch + row * 32
        rrca
        rrca
        rrca
        ld      e,a
        ld      d,0
        ld      hl,hud_ch
        add     hl,de
        ld      (ht_p),hl
ht_ch:  ld      hl,(ht_s)
        ld      a,(hl)
        or      a
        ret     z
        ld      a,(ht_col)
        cp      32
        ret     nc
        ; its attribute: 1 inverse, 2 + seat the name, 0 plain
        ld      a,(ht_hi)
        or      a
        jr      nz,ht_at
        ld      a,(ht_name)
        ld      b,a
        ld      a,(ht_col)
        cp      b
        ld      a,0
        jr      nc,ht_at
        ld      a,(ht_seat)
        add     a,2
ht_at:  ld      b,a
        ld      hl,(ht_p)
        ld      a,(ht_col)
        call    add_hl_a
        ld      de,(ht_s)
        ld      a,(de)
        cp      (hl)
        jr      nz,ht_put
        push    hl
        ld      de,96
        add     hl,de           ; (hud_at: 96 on)
        ld      a,b
        cp      (hl)
        pop     hl
        jr      z,ht_next
ht_put: ld      de,(ht_s)
        ld      a,(de)
        ld      (hl),a
        ld      de,96
        add     hl,de
        ld      (hl),b
        ld      a,b             ; the colours
        ld      c,C_BLACK * 16 + C_WHITE
        dec     a
        jr      z,ht_c
        ld      c,C_WHITE * 16 + C_BLACK
        inc     a
        jr      z,ht_c
        sub     2
        ld      hl,_seat_col
        call    add_hl_a
        ld      a,(hl)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      C_BLACK
        ld      c,a
ht_c:   ld      a,(ht_row)      ; the cell: (21 + row) * 32 + col
        add     a,HUD_ROW
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,(ht_col)
        call    add_hl_a
        ld      de,(ht_s)
        ld      a,(de)
        call    text_cell
ht_next:
        ld      hl,(ht_s)
        inc     hl
        ld      (ht_s),hl
        ld      hl,ht_col
        inc     (hl)
        jp      ht_ch

; void field_status_clear(void)
_field_status_clear:
        xor     a
        ld      (ht_hi),a
        ld      (ht_col),a
        ld      b,3
fc_l:   push    bc
        ld      a,3
        sub     b
        ld      (ht_row),a
        xor     a
        ld      (ht_col),a
        ld      hl,blank32
        ld      (ht_s),hl
        call    hud_go
        pop     bc
        djnz    fc_l
        ret
blank32:
        defm    "                                "
        defb    0

; ---- the balloon -------------------------------------------------------------

; balloon_off: its cells back to the store's
balloon_off:
        ld      a,(b_on)
        or      a
        ret     z
        xor     a
        ld      (b_on),a
        ld      a,(b_r0)
        ld      (oc_r),a
        ld      a,(b_h)
        ld      b,a
bo_r:   push    bc
        ld      a,(b_w)
        ld      b,a
        ld      a,(b_c0)
        ld      c,a
bo_c:   push    bc
        ld      a,(oc_r)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,c
        call    add_hl_a
        push    hl
        ld      de,_fld_dirty
        add     hl,de
        res     1,(hl)
        pop     hl
        call    cell_dirty
        pop     bc
        inc     c
        djnz    bo_c
        ld      hl,oc_r
        inc     (hl)
        pop     bc
        djnz    bo_r
        ret

; void field_balloon(uint8_t s, const char *t, uint8_t n)
_field_balloon:
        call    balloon_off
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        ld      (bl_s),a
        inc     hl
        call    word
        ld      (bl_t),de
        ld      a,(hl)          ; n
        or      a
        ret     z
        cp      MAX_TALK + 1
        jr      c,bl_n
        ld      a,MAX_TALK
bl_n:   ld      (bl_n_),a
        ld      a,(bl_s)
        cp      SEATS
        ret     nc
        ld      a,(_fld_live)
        or      a
        ret     z
        ld      a,(bl_n_)       ; lines, and their length
        ld      b,1
        cp      LMAX + 1
        jr      c,bl_1
        inc     b
        inc     a
        srl     a
bl_1:   ld      (bl_len),a
        ld      a,b
        ld      (b_h),a
        ld      a,(bl_len)
        add     a,2
        ld      (b_w),a
        ld      a,(bl_s)        ; its column: the tank's x / 8 - w / 2
        ld      c,a
        call    tk_at
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      (bl_y),a
        ex      de,hl
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      a,(b_w)
        srl     a
        ld      e,a
        ld      d,0
        or      a
        sbc     hl,de
        bit     7,h
        jr      z,bl_c1
        ld      hl,0
bl_c1:  ld      a,(b_w)
        add     a,l
        cp      33
        ld      a,l
        jr      c,bl_c2
        ld      a,(b_w)
        neg
        add     a,32
bl_c2:  ld      (b_c0),a
        ld      a,(bl_y)        ; its row: the one over the tank's box
        sub     16
        jr      nc,bl_r1
        xor     a
bl_r1:  rrca
        rrca
        rrca
        and     31
        ld      b,a
        ld      a,(b_h)
        dec     a
        ld      c,a
        ld      a,b
        sub     c
        jr      nc,bl_r2
        xor     a
bl_r2:  ld      (b_r0),a
        ld      a,(bl_s)
        ld      hl,_seat_col
        call    add_hl_a
        ld      a,(hl)
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      C_BLACK
        ld      (bl_col),a
        ld      a,1
        ld      (b_on),a
        xor     a
        ld      (bl_i),a
        ld      (oc_r),a
bl_row: xor     a
        ld      (oc_c),a
bl_cell:
        ld      a,(b_r0)        ; the cell
        ld      hl,oc_r
        add     a,(hl)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,(b_c0)
        call    add_hl_a
        ld      a,(oc_c)
        call    add_hl_a
        push    hl
        ld      de,_fld_dirty
        add     hl,de
        set     1,(hl)          ; the balloon's
        ld      a,(oc_c)        ; a character: columns 1 .. len, while any are left
        ld      e,' '
        or      a
        jr      z,bl_ch
        ld      b,a
        ld      a,(bl_len)
        cp      b
        jr      c,bl_ch
        ld      a,(bl_i)
        ld      b,a
        ld      a,(bl_n_)
        cp      b
        jr      z,bl_ch
        jr      c,bl_ch
        ld      hl,(bl_t)
        ld      a,b
        call    add_hl_a
        ld      e,(hl)
        ld      hl,bl_i
        inc     (hl)
bl_ch:  pop     hl
        ld      a,(bl_col)
        ld      c,a
        ld      a,e
        call    text_cell
        ld      hl,oc_c
        inc     (hl)
        ld      a,(b_w)
        cp      (hl)
        jr      nz,bl_cell
        ld      hl,oc_r
        inc     (hl)
        ld      a,(b_h)
        cp      (hl)
        jr      nz,bl_row
        ret

; ---- flash, fire --------------------------------------------------------------

; void field_flash(uint8_t frames): (the NMI blanks the frames after it's set)
_field_flash:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        inc     a
        ld      (_flash_n),a
        ret

; fire_step: every FIRE_EVERY frames, the fire's colours a band on and the
; cells drawn with fire (CF_FIRE) dirty again
fire_step:
        ld      hl,fire_t
        inc     (hl)
        ld      a,(hl)
        cp      FIRE_EVERY
        ret     c
        ld      (hl),0
        ld      hl,_fire_ph
        inc     (hl)
IFDEF F18A_HOOK
        ld      a,(_f18a)       ; (an F18A: the copper cycles them)
        or      a
        jp      nz,_f18a_fire
ENDIF
        ld      hl,_fld_dirty
        ld      c,FROWS
fs_r:   ld      b,32
fs_c:   bit     3,(hl)
        call    nz,fs_hit
        inc     hl
        djnz    fs_c
        dec     c
        jr      nz,fs_r
        ret
fs_hit: push    hl
        ld      de,_fld_dirty
        or      a
        sbc     hl,de           ; (the cell)
        call    cell_dirty
        pop     hl
        ret

; void field_fire(uint8_t on)
_field_fire:
        ld      hl,2
        add     hl,sp
        ld      a,(hl)
        ld      (fire_on),a
        ret

        SECTION bss_user
sy_d0:  defs    1
sy_d1:  defs    1
sy_sky: defs    1
sy_s:   defs    2
sy_m:   defs    1
sy_y:   defs    1
sy_q:   defs    1
sy_acc: defs    1
sy_l:   defs    1
sy_acc2: defs   1
sy_c9:  defs    1
sy_band: defs   1
sy_smain: defs  1
tanks_dirty: defs 1
sat_dirty: defs 1
sat_n:  defs    1
sat_dx: defs    1
fire_on: defs   1
fire_t: defs    1
sat:    defs    4 * SEATS + 1
satout: defs    4 * SEATS + 1
td:     defs    TD_SIZE * SEATS
ovl:    defs    OV_SIZE * SEATS
ovl_n:  defs    1
lines:  defs    FIELD_H + 8
al_p:   defs    2
al_s:   defs    1
al_td:  defs    2
al_y:   defs    1
al_l:   defs    2
al_n:   defs    1
oc_set: defs    2
oc_y:   defs    1
oc_cx0: defs    1
oc_cx1: defs    1
oc_r:   defs    1
oc_r1v: defs    1
oc_c:   defs    1
oc_px:  defs    1
oc_py:  defs    1
oc_ln:  defs    1
oc_i:   defs    1
oc_fg:  defs    1
oc_bits: defs   1
oc_tc:  defs    1
oc_rp:  defs    2
ft_s:   defs    1
ft_new: defs    TD_SIZE
hud_ch: defs    96
hud_at: defs    96
ht_hi:  defs    1
ht_row: defs    1
ht_col: defs    1
ht_s:   defs    2
ht_p:   defs    2
ht_name: defs   1
ht_seat: defs   1
b_on:   defs    1
b_r0:   defs    1
b_c0:   defs    1
b_w:    defs    1
b_h:    defs    1
bl_s:   defs    1
bl_t:   defs    2
bl_n_:  defs    1
bl_len: defs    1
bl_y:   defs    1
bl_col: defs    1
bl_i:   defs    1
