; render.asm -- the field's dirty cells into the VRAM (fld.asm keeps the
; store and marks them). A cell is 8 runs of 8 pixels, a line each; a
; run's pattern byte and colour byte come from its D and F bytes and its
; line's style (field.asm builds st_line, a record a line (style.inc),
; for the round's sky and dirt):
;
;   all sky         the line's sky pattern (none, or stars), its sky pair
;   all dirt        the line's dirt pattern (none), its dirt pair
;   sky and dirt    D; the line's dirt colour on its sky colour (st_mixc)
;   any fire        F; the fire's colour (by row, its phase cycling) on
;                   whichever of sky and dirt has more of the other pixels
;
; A cell drawn with fire gets flag bit 3 (CF_FIRE): while the fire burns,
; field.asm's field_frame moves its colours on and draws those again.
; A cell under a talk balloon (flag bit 1) is the balloon's: skipped. A
; cell under a tank drawn in the bitmap (bit 2: one the sprites couldn't
; take) goes through field.c's ovl_cell before it is written.
;
; The writes: flat out (OTIR) while the display is blanked or in the
; frame's blank (rnd_fast, set by tms_frame), else a byte every 38
; T-states (the VDP's 8 us while it draws). The NMI is held off (vdp_busy)
; for a cell, and caught up after.

        SECTION code_user

        PUBLIC  _fld_flush1, _fld_flushn, _fld_budget, _rnd_fast
        PUBLIC  _st_line, _st_fire, _st_stars
        PUBLIC  _fire_ph, _rc_pat, _rc_col, _rc_cell, _rc_y
        EXTERN  _fld_dirty, _fld_rowd, _fld_nd, _fld_shadow, _st_starb
        EXTERN  _vdp_busy, _vdp_pend, _vdp_catch_up, _tms_blanked, _ovl_cell
IFDEF F18A_HOOK
        EXTERN  _st_grain
ENDIF

IFNDEF SHADOW_ORG
        defc    SHADOW_ORG = $A700      ; (fld.asm's)
ENDIF
        defc    SH_HI   = SHADOW_ORG / 256
        INCLUDE "tms9918/style.inc"
        defc    FROWS   = 21
        INCLUDE "vdpio.inc"     ; VDP_DATA, VDP_CTRL (the platform's)

; bits set in a nibble
pop4:   defb    0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4

; uint8_t fld_flush1(void): a dirty cell drawn; 0 if there was none
_fld_flush1:
        ld      hl,(_fld_nd)
        ld      a,h
        or      l
        ld      l,a
        ret     z
        push    ix
        push    iy
        call    next
        pop     iy
        pop     ix
        ld      l,1
        ret

; void fld_flushn(void): up to fld_budget dirty cells drawn
_fld_flushn:
        ld      a,(_fld_budget)
fn_l:   or      a
        ret     z
        push    af
        call    _fld_flush1
        pop     af
        dec     a
        inc     l
        dec     l
        jr      nz,fn_l
        ret

; next: the first dirty cell, top down: drawn (or skipped), its flag off
next:   ld      hl,_fld_rowd
        ld      b,0
nx_r:   ld      a,(hl)
        or      a
        jr      nz,nx_row
        inc     hl
        inc     b
        ld      a,b
        cp      FROWS
        jr      c,nx_r
        ld      hl,0            ; (the count was wrong: it is 0)
        ld      (_fld_nd),hl
        ret
nx_row: dec     (hl)
        ld      hl,(_fld_nd)
        dec     hl
        ld      (_fld_nd),hl
        ld      a,b
        ld      (rc_r),a
        ld      l,b             ; the row's flags: dirty + r * 32
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,_fld_dirty
        add     hl,de
        ld      c,0
nx_c:   bit     0,(hl)
        jr      nz,nx_cell
        inc     hl
        inc     c
        ld      a,c
        cp      32
        jr      c,nx_c
        ret                     ; (none: the count was wrong)
nx_cell:
        res     0,(hl)
        ld      a,c
        ld      (rc_c),a
        bit     1,(hl)
        ret     nz              ; under the balloon
        ld      a,(hl)
        ld      (rc_flag),a
        ld      (rc_fp),hl
        jp      cell

; cell: draw row rc_r's column rc_c
cell:   ld      a,(rc_r)
        ld      h,a
        ld      a,(rc_c)
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      (_rc_cell),hl   ; (H r, L c * 8: the VRAM offset)
        ld      a,(rc_c)        ; c * 37 (the stars' hash)
        ld      b,a
        add     a,a
        add     a,a
        ld      c,a             ; 4c
        add     a,a
        add     a,a
        add     a,a             ; 32c
        add     a,c
        add     a,b
        ld      (rc_c37),a
        ld      a,(rc_r)        ; its first line, and that line's styles (IY)
        add     a,a
        add     a,a
        add     a,a
        ld      (_rc_y),a
        ld      e,a
        ld      d,0
        ld      l,a
        ld      h,d
        add     hl,hl
        add     hl,hl
        add     hl,de
        ld      de,_st_line
        add     hl,de
        push    hl
        pop     iy
        ld      a,(rc_r)        ; the D byte of the first run (its F: the page up)
        add     a,a
        add     a,SH_HI
        ld      h,a
        ld      a,(rc_c)
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      ix,_rc_pat
        xor     a
        ld      (rc_fire),a
        ld      b,8
cl_run: ld      d,(hl)          ; D
        inc     h
        ld      a,(hl)          ; F
        dec     h
        or      a
        jr      nz,cl_fire
        ld      a,d
        or      a
        jr      z,cl_sky
        inc     a
        jr      z,cl_dirt
        ld      (ix+0),d        ; sky and dirt: D, dirt on sky
        ld      a,(iy+L_MIXC)
        ld      (ix+8),a
        jp      cl_next
cl_sky: ld      a,(_st_stars)
        or      a
        jr      nz,cl_star
        ld      a,(iy+L_SKYP)
        ld      (ix+0),a
cl_skyc:
        ld      a,(iy+L_SKYC)
        ld      (ix+8),a
        jr      cl_next
cl_star:
        push    hl
        ld      a,(iy+L_SKYP)   ; the line's seed, plus the column's
        ld      hl,rc_c37
        add     a,(hl)
        ld      e,a
        ld      d,0
        ld      hl,_st_starb
        add     hl,de
        ld      a,(hl)
        ld      (ix+0),a
        pop     hl
        jr      cl_skyc
cl_dirt:
        ld      a,(iy+L_DIRTP)
IFDEF F18A_HOOK
        or      a               ; (an F18A's grain: the line's seed and the column's)
        jr      z,cl_dg
        push    hl
        ld      hl,rc_c37
        add     a,(hl)
        ld      e,a
        ld      d,0
        ld      hl,_st_grain
        add     hl,de
        ld      a,(hl)
        pop     hl
cl_dg:
ENDIF
        ld      (ix+0),a
        ld      a,(iy+L_DIRTC)
        ld      (ix+8),a
        jr      cl_next
cl_fire:
        push    hl
        push    bc
        ld      (ix+0),a        ; F, the fire's colour on the most of the rest
        ld      e,a
        ld      a,1
        ld      (rc_fire),a
        ld      a,e
        cpl
        and     d               ; dirt: D and not F
        call    popc
        ld      c,a
        ld      a,e
        or      d
        cpl                     ; sky: neither
        call    popc
        cp      c
        ld      a,(iy+L_MIXC)   ; (flags kept)
        jr      nc,cl_fsky      ; sky as many or more
        rrca
        rrca
        rrca
        rrca                    ; the dirt's (the high nibble)
cl_fsky:
        and     $0F
        ld      c,a
        pop     de              ; (D: the runs left)
        push    de
        ld      a,(_rc_y)       ; the line: the cell's first + 8 - left
        add     a,8
        sub     d
        rrca                    ; the fire's colour: its band and phase
        rrca
        rrca
        ld      hl,_fire_ph
        add     a,(hl)
        and     7
        ld      e,a
        ld      d,0
        ld      hl,_st_fire
        add     hl,de
        ld      a,(hl)
        or      c
        ld      (ix+8),a
        pop     bc
        pop     hl
cl_next:
        inc     ix
        ld      de,L_SIZE
        add     iy,de
        inc     l
        dec     b
        jp      nz,cl_run
        ld      hl,(rc_fp)      ; (CF_FIRE: drawn with fire, so its colours cycle)
        res     3,(hl)
        ld      a,(rc_fire)
        or      a
        jr      z,cl_nf
        set     3,(hl)
cl_nf:  ld      a,(rc_flag)
        bit     2,a
        call    nz,_ovl_cell    ; a tank in the bitmap here
        jp      write

; popc: A = the bits set in A (keeps C, D, E)
popc:   push    de
        ld      e,a
        and     $0F
        ld      hl,pop4
        add     a,l
        ld      l,a
        jr      nc,pc_1
        inc     h
pc_1:   ld      d,(hl)
        ld      a,e
        rrca
        rrca
        rrca
        rrca
        and     $0F
        ld      hl,pop4
        add     a,l
        ld      l,a
        jr      nc,pc_2
        inc     h
pc_2:   ld      a,(hl)
        add     a,d
        pop     de
        ret

; write: rc_pat and rc_col to the cell rc_cell (patterns, then colours)
write:  ld      a,1
        ld      (_vdp_busy),a
        ld      hl,(_rc_cell)
        ld      a,l
        out     (VDP_CTRL),a
        ld      a,h
        or      $40
        out     (VDP_CTRL),a
        ld      hl,_rc_pat
        call    out8
        ld      hl,(_rc_cell)
        ld      a,l
        out     (VDP_CTRL),a
        ld      a,h
        or      $60             ; (2000h on: the colours)
        out     (VDP_CTRL),a
        ld      hl,_rc_col
        call    out8
        xor     a
        ld      (_vdp_busy),a
        ld      a,(_vdp_pend)
        or      a
        ret     z
        jp      _vdp_catch_up

; out8: 8 bytes from HL to the VDP: flat out when that's safe
out8:   ld      bc,8 * 256 + VDP_DATA
        ld      a,(_rnd_fast)
        ld      e,a
        ld      a,(_tms_blanked)
        or      e
        jr      z,o8_slow
        otir
        ret
o8_slow:
        ld      a,(hl)          ; 38 T-states a byte
        out     (c),a
        inc     hl
        djnz    o8_slow
        ret

        SECTION bss_user
_fld_budget:    defs    1
_rnd_fast:      defs    1
_st_stars:      defs    1
_fire_ph:       defs    1
_st_fire:       defs    8
_st_line:       defs    168 * L_SIZE
_rc_pat:        defs    8
_rc_col:        defs    8
_rc_cell:       defs    2
_rc_y:          defs    1
rc_r:           defs    1
rc_c:           defs    1
rc_c37:         defs    1
rc_flag:        defs    1
rc_fp:          defs    2
rc_fire:        defs    1
