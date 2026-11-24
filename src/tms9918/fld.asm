; fld.asm -- the field on a TMS9918 machine (the Adam; the MSX to come):
; the store and the primitives the player (src/z80) and field.c draw with.
; The CoCo's src/coco2/fld2.asm in Z80, its ellipse the same steps, so the
; same pixels (tools/adamsim/refcheck.py).
;
; The store (SHADOW_ORG, 2A00h bytes: the Adam's A700h-D0FFh, under the
; stack; the NABU's D000h-F9FFh) is the field as two planes of a bit a pixel, laid out as the
; VDP's pattern table: D (dirt) and F (fire, the value 3), 256 x 168.
; Character row r (lines 8r..8r+7) is two pages: D at SH_HI + 2r, F the
; page after; in a page, the byte for pixels x..x+7 (x a multiple of 8) of
; line y is at (x & F8h) | (y & 7), its bit 7 the leftmost. So a run's D
; and F bytes are at HL and HL + 100h, and its VRAM pattern and colour
; bytes at r * 100h + L and 2000h more.
;
;   sky  D 0 F 0      dirt  D 1 F 0      fire  D 0 F 1      (tank: never)
;
; While the field is shown (fld_live), a primitive that changes a byte
; marks its 8x8 cell dirty (fld_dirty: a flag byte a cell, bit 0; per row
; the count, fld_rowd); render.asm draws dirty cells into the VRAM.
;
; The arguments are variables (fld.h; the player's names are the same):
; fx, fy, fx1 signed words, fv, fold, emode bytes, fent a pointer, ex, ey
; words, erx, ery bytes. A result is in A and L. No routine here touches
; IX or IY (zsdcc's, and the player's).

        SECTION code_user

        PUBLIC  _fld_clear, _fld_plot, _fld_get, _fld_swap, _fld_hspan, _fld_vrun
        PUBLIC  _fld_col, _fld_cols, _fld_ellipse, _fld_mark_all
        PUBLIC  _fx, _fy, _fx1, _fv, _fold, _fent, _ex, _ey, _erx, _ery, _emode
        PUBLIC  _fld_live, _fld_dirty, _fld_rowd, _fld_nd, _fld_ncols
        PUBLIC  fld_w, fld_h, fld_mid, fld_espan
        PUBLIC  _fld_shadow

IFNDEF SHADOW_ORG                       ; (a page: the platform's build may say, -DSHADOW_ORG)
        defc    SHADOW_ORG = $A700      ; (tools/adam/mkimage.py's SHADOW_ORG)
ENDIF
        defc    _fld_shadow = SHADOW_ORG
        defc    SH_HI   = SHADOW_ORG / 256
        defc    FLINES  = 168
        defc    FROWS   = 21
        defc    PX_SKY  = 1
        defc    PX_DIRT = 2
        defc    PX_FX   = 3

; the field's size, a tank's middle over its foot (the sparks: src/z80/pt.asm)
fld_w:  defw    256
fld_h:  defb    FLINES
fld_mid: defb   2

; a pixel's bit, x & 7
bit8:   defb    $80, $40, $20, $10, $08, $04, $02, $01
; a span's first byte: from pixel n on; its last: up to pixel n
lmask:  defb    $FF, $7F, $3F, $1F, $0F, $07, $03, $01
rmask:  defb    $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF
; a quarter circle: q32[i] = 64 sqrt(1 - (i/32)^2) (src/atari/fld.s's)
q32:    defb    64,64,64,63,63,62,62,61,60,59,57,56,54,53,51,49
        defb    46,44,41,38,35,32,28,24,20,15,10,5,0,0,0,0,0

; ---- dirty cells -----------------------------------------------------------

; mark: the cell of HL (a D page's byte) dirty, if the field is shown
; (keeps BC, DE, HL)
mark:   ld      a,(_fld_live)
        or      a
        ret     z
        push    hl
        push    de
        ld      a,l
        rrca
        rrca
        rrca
        and     31
        ld      e,a             ; the cell's column
        ld      a,h
        sub     SH_HI           ; 2r
        ld      d,a
        rrca                    ; r
        push    af
        ld      a,d
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl           ; 2r * 16 = r * 32
        ld      d,0
        add     hl,de
        ld      de,_fld_dirty
        add     hl,de
        pop     af
        bit     0,(hl)
        jr      nz,mk_x
        set     0,(hl)
        ld      e,a
        ld      d,0
        ld      hl,_fld_rowd
        add     hl,de
        inc     (hl)
        ld      hl,(_fld_nd)
        inc     hl
        ld      (_fld_nd),hl
mk_x:   pop     de
        pop     hl
        ret

; void fld_mark_all(void): every cell dirty (the field is drawn again)
_fld_mark_all:
        ld      hl,_fld_dirty
        ld      b,FROWS * 32 / 8
ma_l:   ld      c,8
ma_c:   set     0,(hl)
        inc     hl
        dec     c
        jr      nz,ma_c
        djnz    ma_l
        ld      hl,_fld_rowd
        ld      b,FROWS
ma_r:   ld      (hl),32
        inc     hl
        djnz    ma_r
        ld      hl,FROWS * 32
        ld      (_fld_nd),hl
        ret

; ---- the whole field ---------------------------------------------------------

; void fld_clear(void): all sky (drawn again, if shown)
_fld_clear:
        ld      hl,_fld_shadow
        ld      de,_fld_shadow+1
        ld      bc,FROWS * 512 - 1
        ld      (hl),0
        ldir
        ld      a,(_fld_live)
        or      a
        ret     z
        jr      _fld_mark_all

; ---- a pixel -----------------------------------------------------------------

; at: (fx, fy) on the field? NC: HL its D byte, B its bit; C: off it
at:     ld      a,(_fx+1)
        or      a
        jr      nz,at_off
        ld      a,(_fy+1)
        or      a
        jr      nz,at_off
        ld      a,(_fy)
        cp      FLINES
        jr      nc,at_off
        ld      c,a
        and     7
        ld      l,a
        ld      a,(_fx)
        ld      b,a
        and     $F8
        or      l
        ld      l,a             ; (x & F8h) | (y & 7)
        ld      a,c
        rrca
        rrca
        and     $3E             ; (y >> 3) * 2
        add     a,SH_HI
        ld      h,a
        ld      a,b
        and     7
        ld      de,bit8
        add     a,e
        ld      e,a
        jr      nc,at_b
        inc     d
at_b:   ld      a,(de)
        ld      b,a
        or      a               ; (NC)
        ret
at_off: scf
        ret

; void fld_plot(void): pixel (fx, fy) = fv
_fld_plot:
        call    at
        ret     c
; plot_at: HL's bit B = fv
plot_at:
        ld      a,(_fv)
        ld      c,(hl)
        cp      PX_DIRT
        ld      a,c
        jr      z,pl_ds
        ld      a,b
        cpl
        and     c
        jr      pl_d
pl_ds:  or      b
pl_d:   ld      (hl),a
        xor     c
        ld      e,a             ; D's bits changed
        inc     h
        ld      a,(_fv)
        ld      c,(hl)
        cp      PX_FX
        ld      a,c
        jr      z,pl_fs
        ld      a,b
        cpl
        and     c
        jr      pl_f
pl_fs:  or      b
pl_f:   ld      (hl),a
        dec     h
        xor     c
        or      e
        ret     z
        jp      mark

; value: HL's bit B as a value, in C
value:  inc     h
        ld      a,(hl)
        dec     h
        and     b
        ld      c,PX_FX
        ret     nz
        ld      a,(hl)
        and     b
        ld      c,PX_DIRT
        ret     nz
        ld      c,PX_SKY
        ret

; uint8_t fld_get(void): pixel (fx, fy); sky off the field
_fld_get:
        call    at
        ld      a,PX_SKY
        jr      c,gt_x
        call    value
        ld      a,c
gt_x:   ld      l,a
        ret

; void fld_swap(void): pixel (fx, fy) = fv if it is fold
_fld_swap:
        call    at
        ret     c
        call    value
        ld      a,(_fold)
        cp      c
        ret     nz
        jr      plot_at

; ---- a line's span -----------------------------------------------------------

; clip: line fy, fx..fx1 clipped to the field: NC with E x0, D x1, H the
; row's D page, C the line's low bits; C (carry) when nothing is left
clip:   ld      a,(_fy+1)
        or      a
        jr      nz,cl_no
        ld      a,(_fy)
        cp      FLINES
        jr      nc,cl_no
        ld      hl,(_fx)
        bit     7,h
        jr      z,cl_a
        ld      hl,0
cl_a:   ld      a,h
        or      a
        jr      nz,cl_no        ; x0 past the right
        ld      e,l
        ld      hl,(_fx1)
        bit     7,h
        jr      nz,cl_no        ; x1 left of the field
        ld      a,h
        or      a
        jr      z,cl_b
        ld      l,255
cl_b:   ld      d,l
        ld      a,d
        cp      e
        jr      c,cl_no         ; x1 < x0
        ld      a,(_fy)
        ld      c,a
        rrca
        rrca
        and     $3E
        add     a,SH_HI
        ld      h,a
        ld      a,c
        and     7
        ld      c,a
        or      a
        ret
cl_no:  scf
        ret

; void fld_hspan(void): line fy, fx to fx1 (both in) = fv, clipped
_fld_hspan:
        call    clip
        ret     c
        ld      a,(_fv)
        ld      b,0
        cp      PX_DIRT
        jr      nz,hs_1
        dec     b
hs_1:   ld      a,b
        ld      (sp_d),a        ; D's bits for the value: 00 or FF
        ld      a,(_fv)
        ld      b,0
        cp      PX_FX
        jr      nz,hs_2
        dec     b
hs_2:   ld      a,b
        ld      (sp_f),a
        xor     a
        ld      (sp_eq),a       ; (all the span's pixels)
; span: E x0, D x1, H the D page, C the line's low bits: the pixels the
; mode takes (sp_eq 0: all; else those equal to sp_eq's value) = sp_d, sp_f
span:   ld      a,d
        and     7
        push    de
        ld      de,rmask
        add     a,e
        ld      e,a
        jr      nc,sn_1
        inc     d
sn_1:   ld      a,(de)
        ld      (sp_rm),a
        pop     de
        ld      a,e
        and     7
        push    de
        ld      de,lmask
        add     a,e
        ld      e,a
        jr      nc,sn_2
        inc     d
sn_2:   ld      a,(de)
        pop     de
        ld      b,a             ; B: this byte's mask
        ld      a,d
        and     $F8
        ld      (sp_last),a
        ld      a,e
        and     $F8
        or      c
        ld      l,a             ; the first byte
sn_byte:
        ld      a,l
        and     $F8
        push    hl
        ld      hl,sp_last
        cp      (hl)
        pop     hl
        jr      nz,sn_m
        ld      a,(sp_rm)       ; the last byte: up to x1 too
        and     b
        ld      b,a
sn_m:   ld      a,(sp_eq)
        or      a
        jr      z,sn_put
        ; only the pixels that are the old value
        cp      PX_SKY
        jr      nz,sn_e2
        inc     h
        ld      a,(hl)
        dec     h
        or      (hl)
        cpl                     ; sky: neither
        jr      sn_e
sn_e2:  cp      PX_FX
        jr      nz,sn_e3
        inc     h
        ld      a,(hl)          ; fire: F
        dec     h
        jr      sn_e
sn_e3:  inc     h               ; dirt: D, not F
        ld      a,(hl)
        dec     h
        cpl
        and     (hl)
sn_e:   and     b
        jr      z,sn_next
        ld      b,a
sn_put: ld      a,(sp_d)        ; D = D ^ ((D ^ d) & m)
        xor     (hl)
        and     b
        jr      z,sn_f
        xor     (hl)
        ld      (hl),a
        call    mark
sn_f:   inc     h
        ld      a,(sp_f)
        xor     (hl)
        and     b
        jr      z,sn_fx
        xor     (hl)
        ld      (hl),a
        dec     h
        call    mark
        inc     h
sn_fx:  dec     h
sn_next:
        ld      a,l
        and     $F8
        push    hl
        ld      hl,sp_last
        cp      (hl)
        pop     hl
        ret     z
        ld      a,l
        add     a,8
        ld      l,a
        ld      b,$FF
        jr      sn_byte

; fld_espan: line fy, fx to fx1 (clipped): its pixels that are fold become
; fv, a byte at a time (fld_swap's, pixel for pixel)
fld_espan:
        call    clip
        ret     c
        ld      a,(_fv)
        ld      b,0
        cp      PX_DIRT
        jr      nz,es_1
        dec     b
es_1:   ld      a,b
        ld      (sp_d),a
        ld      a,(_fv)
        ld      b,0
        cp      PX_FX
        jr      nz,es_2
        dec     b
es_2:   ld      a,b
        ld      (sp_f),a
        ld      a,(_fold)
        ld      (sp_eq),a
        jp      span

; ---- a column ------------------------------------------------------------------

; colset: column fx's byte, bit B, D and F bits for value A (sp_d, sp_f)
colset: ld      c,a
        ld      b,0
        cp      PX_DIRT
        jr      nz,cs_1
        dec     b
cs_1:   ld      a,b
        ld      (sp_d),a
        ld      a,c
        ld      b,0
        cp      PX_FX
        jr      nz,cs_2
        dec     b
cs_2:   ld      a,b
        ld      (sp_f),a
        ld      a,(_fx)
        and     7
        ld      de,bit8
        add     a,e
        ld      e,a
        jr      nc,cs_3
        inc     d
cs_3:   ld      a,(de)
        ld      (sp_bit),a
        ret

; rows: rows cur..cnt-1 of column fx get (sp_d, sp_f) in bit sp_bit
rows:   ld      a,(r_cnt)
        ld      b,a
        ld      a,(r_cur)
        cp      b
        ret     nc
        ld      c,a             ; y
        rrca
        rrca
        and     $3E
        add     a,SH_HI
        ld      h,a
        ld      a,(_fx)
        and     $F8
        ld      l,a
        ld      a,c
        and     7
        or      l
        ld      l,a
        ld      a,b
        sub     c
        ld      b,a             ; the count
        xor     a
        ld      (sp_chg),a
        ld      a,(sp_d)        ; (the loop's: D's bits, F's, the mask)
        ld      d,a
        ld      a,(sp_f)
        ld      c,a
        ld      a,(sp_bit)
        ld      e,a
rw_l:   ld      a,(hl)          ; D = D ^ ((D ^ d) & m)
        xor     d
        and     e
        jr      z,rw_f
        xor     (hl)
        ld      (hl),a
        ld      a,1
        ld      (sp_chg),a
rw_f:   inc     h
        ld      a,(hl)          ; F the same
        xor     c
        and     e
        jr      z,rw_fx
        xor     (hl)
        ld      (hl),a
        ld      a,1
        ld      (sp_chg),a
rw_fx:  dec     h
        inc     l
        ld      a,l
        and     7
        jr      nz,rw_n         ; still in the cell
        ld      a,(sp_chg)      ; the cell's end: mark it if it changed
        or      a
        jr      z,rw_c
        dec     l
        call    mark
        inc     l
        xor     a
        ld      (sp_chg),a
rw_c:   ld      a,l
        sub     8
        ld      l,a
        inc     h
        inc     h
rw_n:   djnz    rw_l
        ld      a,(sp_chg)
        or      a
        ret     z
        dec     l
        jp      mark

; void fld_vrun(void): column fx, rows fy to fx1-1 = fv (all on the field)
_fld_vrun:
        ld      a,(_fx+1)
        or      a
        ret     nz
        ld      a,(_fy)
        ld      (r_cur),a
        ld      a,(_fx1)
        ld      (r_cnt),a
        ld      a,(_fv)
        call    colset
        jp      rows

; run: rows cur..cnt-1 (cnt at most the field's lines) of column fx = A;
; cur = cnt after
run:    push    af
        ld      a,(r_cnt)
        cp      FLINES + 1
        jr      c,rn_1
        ld      a,FLINES
        ld      (r_cnt),a
rn_1:   pop     af
        call    colset
        call    rows
        ld      a,(r_cnt)
        ld      (r_cur),a
        ret

; uint8_t fld_col(void): column fx becomes the TERRAIN entry at fent
; (sky, dirt); A and L its length
_fld_col:
        xor     a
        ld      (r_cur),a
        ld      hl,(_fent)
        ld      a,(hl)
        cp      $F0
        jr      z,co_empty
        jr      nc,co_spans
        ld      (r_cnt),a       ; one plain column: sky to its top,
        push    af
        ld      a,PX_SKY
        call    run
        pop     af
        ld      (r_cur),a
        ld      a,FLINES        ;  dirt from there
        ld      (r_cnt),a
        ld      a,PX_DIRT
        call    run
        ld      a,1
        ld      l,a
        ret
co_empty:
        ld      a,FLINES
        ld      (r_cnt),a
        ld      a,PX_SKY
        call    run
        ld      a,1
        ld      l,a
        ret
co_spans:
        and     $0F
        ld      (co_n),a        ; the spans
        inc     hl
        ld      (co_p),hl
co_sp:  ld      hl,(co_p)
        ld      a,(hl)          ; top: sky till there
        ld      (r_cnt),a
        ld      a,PX_SKY
        call    run
        ld      hl,(co_p)
        ld      a,(hl)
        inc     hl
        ld      (r_cur),a
        ld      a,(hl)          ; end: dirt till there
        inc     hl
        ld      (co_p),hl
        ld      (r_cnt),a
        ld      a,PX_DIRT
        call    run
        ld      hl,co_n
        dec     (hl)
        jr      nz,co_sp
        ld      a,FLINES
        ld      (r_cnt),a
        ld      a,PX_SKY
        call    run
        ld      hl,(_fent)
        ld      a,(hl)
        and     $0F
        add     a,a
        inc     a               ; 1 + 2n
        ld      l,a
        ret

; void fld_cols(void): fld_ncols columns from fx on become the TERRAIN
; entries from fent on (fx, fent past them after): the columns that share a
; byte at once (a settle's: the CoCo's fld_cols), each column's entry read
; as its runs, top down: sky to the first end, then dirt and sky by turns
; (plain: its top, then the bottom; spans: top, end, top ..., then the
; bottom). Between two ends of any of them the byte's bits are the same all
; the way down: rows writes them a byte a line.
        defc    I_P = 0                 ; 2: the entry's next end
        defc    I_K = 2                 ; ends left
        defc    I_V = 3                 ; the run's value: 0 sky, 1 dirt
        defc    I_E = 4                 ; its end (the field's lines at most)
        defc    I_M = 5                 ; its column's bit in the byte
        defc    I_SIZE = 6
_fld_cols:
        ld      a,(_fld_ncols)
        or      a
        ret     z
cs_next:
        ld      a,(_fx)         ; the byte's columns from fx on
        and     7
        ld      b,a
        ld      a,8
        sub     b
        ld      hl,_fld_ncols
        cp      (hl)
        jr      c,cs_k
        ld      a,(hl)
cs_k:   ld      (g_k),a
        cp      1
        jr      nz,cs_grp
        call    _fld_col        ; (alone)
        ld      e,a
        ld      d,0
        ld      hl,(_fent)
        add     hl,de
        ld      (_fent),hl
        jr      cs_adv
cs_grp: call    group
cs_adv: ld      a,(g_k)
        ld      e,a
        ld      d,0
        ld      hl,(_fx)
        add     hl,de
        ld      (_fx),hl
        ld      a,(_fld_ncols)
        sub     e
        ld      (_fld_ncols),a
        jr      nz,cs_next
        ret

; group: the g_k columns from fx on, in one byte
group:  ld      a,(_fx)         ; the first column's bit
        and     7
        ld      hl,bit8
        call    add_hl_a8
        ld      a,(hl)
        ld      (g_bit),a
        xor     a
        ld      (g_mask),a
        ld      hl,its
        ld      a,(g_k)
        ld      b,a
gi_l:   push    bc
        push    hl
        ld      a,(g_bit)       ; its bit
        push    hl
        ld      de,I_M
        add     hl,de
        ld      (hl),a
        pop     hl
        ld      c,a
        ld      a,(g_mask)
        or      c
        ld      (g_mask),a
        ld      a,c
        srl     a
        ld      (g_bit),a
        call    iinit           ; (A: the entry's length)
        ld      e,a
        ld      d,0
        ld      hl,(_fent)
        add     hl,de
        ld      (_fent),hl
        pop     hl
        ld      de,I_SIZE
        add     hl,de
        pop     bc
        djnz    gi_l
        xor     a
        ld      (g_cur),a
gl_m:   ld      hl,its          ; the nearest end, and the byte till then
        ld      a,(g_k)
        ld      b,a
        ld      c,FLINES        ; cnt
        ld      e,0             ; the dirt's bits
gl_e:   push    hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)          ; V
        inc     hl
        ld      d,(hl)          ; E
        inc     hl
        or      a
        jr      z,gl_s
        ld      a,(hl)          ; M
        or      e
        ld      e,a
gl_s:   ld      a,d
        cp      c
        jr      nc,gl_n
        ld      c,a
gl_n:   pop     hl
        push    de
        ld      de,I_SIZE
        add     hl,de
        pop     de
        djnz    gl_e
        ld      a,(g_cur)       ; rows cur .. cnt-1: the byte's bits
        cp      c
        jr      nc,gl_adv
        ld      (r_cur),a
        ld      a,c
        ld      (r_cnt),a
        ld      a,e
        ld      (sp_d),a
        xor     a
        ld      (sp_f),a
        ld      a,(g_mask)
        ld      (sp_bit),a
        push    bc
        call    rows
        pop     bc
gl_adv: ld      a,c
        ld      (g_cur),a
        cp      FLINES
        ret     nc
        ld      hl,its          ; the runs that end here: their next
        ld      a,(g_k)
        ld      b,a
ga_l:   push    hl
        ld      de,I_E
        add     hl,de
        ld      a,(g_cur)
        cp      (hl)
        pop     hl
        jr      c,ga_n
        call    inext
ga_n:   ld      de,I_SIZE
        add     hl,de
        djnz    ga_l
        jr      gl_m

; iinit: iterator HL reads the entry at fent; A its length (keeps HL, B)
iinit:  push    hl
        ld      de,(_fent)
        inc     hl
        inc     hl
        ld      (hl),0          ; K
        inc     hl
        ld      (hl),0          ; V: sky
        dec     hl
        dec     hl
        dec     hl
        ld      a,(de)
        cp      $F0
        jr      z,ii_e          ; no dirt
        jr      c,ii_p          ; plain: its top, then the bottom
        and     $0F             ; spans: 2n ends from the next byte
        add     a,a
        ld      c,a
        inc     de
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (hl),c
        dec     hl
        dec     hl
        call    iload
        ld      a,c
        inc     a               ; 1 + 2n
        pop     hl
        ret
ii_p:   ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (hl),1
        dec     hl
        dec     hl
ii_e:   call    iload
        ld      a,1
        pop     hl
        ret

; inext: iterator HL's next run; iload: its run's end (keeps HL, BC)
inext:  push    hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        xor     1
        ld      (hl),a
        pop     hl
iload:  push    hl
        push    bc
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)          ; ends left?
        ld      c,FLINES
        or      a
        jr      z,il_s
        dec     (hl)
        ld      a,(de)
        inc     de
        dec     hl
        ld      (hl),d
        dec     hl
        ld      (hl),e
        inc     hl
        inc     hl
        cp      FLINES+1
        jr      nc,il_s
        ld      c,a
il_s:   inc     hl
        inc     hl              ; (I_E)
        ld      (hl),c
        pop     bc
        pop     hl
        ret

add_hl_a8:
        add     a,l
        ld      l,a
        ret     nc
        inc     h
        ret

; ---- the ellipse -------------------------------------------------------------

; void fld_ellipse(void): the ellipse at (ex, ey), radii erx, ery. Its row
; dy is half as wide as erx * sqrt(1 - (dy/ery)^2): q32[i], i = dy*32/ery
; stepped without dividing (fld.s's steps, to the pixel)
_fld_ellipse:
        ld      a,(_ery)
        or      a
        jr      nz,el_r
        inc     a
        ld      (_ery),a
el_r:   srl     a
        ld      (el_rem),a      ; ery / 2: the rounding
        xor     a
        ld      (el_dy),a
        ld      (el_i),a
el_row: ld      a,(el_i)        ; hw = (erx * q32[i] + 32) >> 6
        ld      e,a
        ld      d,0
        ld      hl,q32
        add     hl,de
        ld      e,(hl)
        ld      a,(_erx)
        call    mul8            ; HL = A * E
        ld      de,32
        add     hl,de
        add     hl,hl
        add     hl,hl           ; << 2, then >> 8: >> 6
        ld      l,h
        ld      h,0
        jr      nc,el_h
        inc     h               ; (the bit shifted out of HL's top)
el_h:   ld      (el_hw),hl
        ld      a,(el_dy)       ; the row above: ey - dy
        ld      e,a
        ld      d,0
        ld      hl,(_ey)
        or      a
        sbc     hl,de
        ld      (_fy),hl
        call    erow
        ld      a,(el_dy)
        or      a
        jr      z,el_nx
        ld      e,a             ; and below: ey + dy
        ld      d,0
        ld      hl,(_ey)
        add     hl,de
        ld      (_fy),hl
        call    erow
el_nx:  ld      a,(_ery)
        ld      b,a
        ld      a,(el_dy)
        cp      b
        ret     nc
        inc     a
        ld      (el_dy),a
        ld      a,(el_rem)
        add     a,32
        ld      (el_rem),a
el_i2:  ld      a,(_ery)
        ld      b,a
        ld      a,(el_rem)
        cp      b
        jr      c,el_row
        sub     b
        ld      (el_rem),a
        ld      a,(el_i)
        cp      32
        jr      nc,el_i2
        inc     a
        ld      (el_i),a
        jr      el_i2

; erow: one row of the ellipse: line fy, ex - hw to ex + hw
erow:   ld      hl,(_ex)
        ld      de,(el_hw)
        or      a
        sbc     hl,de
        ld      (_fx),hl
        ld      hl,(_ex)
        add     hl,de
        ld      (_fx1),hl
        ld      a,(_emode)
        or      a
        jp      z,_fld_hspan
        cp      1               ; only the right value changes: sky becomes fv,
        jr      nz,er_2
        ld      a,PX_SKY
        ld      (_fold),a
        jp      fld_espan
er_2:   ld      a,PX_FX         ;  or fire becomes sky
        ld      (_fold),a
        ld      a,PX_SKY
        ld      (_fv),a
        jp      fld_espan

; mul8: HL = A * E (unsigned)
mul8:   ld      hl,0
        ld      d,0
        ld      b,8
m8_l:   add     hl,hl
        rlca
        jr      nc,m8_n
        add     hl,de
m8_n:   djnz    m8_l
        ret

        SECTION bss_user
_fx:    defs    2
_fy:    defs    2
_fx1:   defs    2
_fv:    defs    1
_fold:  defs    1
_fent:  defs    2
_ex:    defs    2
_ey:    defs    2
_erx:   defs    1
_ery:   defs    1
_emode: defs    1
_fld_live:      defs    1
_fld_ncols:     defs    1
_fld_nd:        defs    2
_fld_rowd:      defs    FROWS
_fld_dirty:     defs    FROWS * 32
sp_d:   defs    1
sp_f:   defs    1
sp_eq:  defs    1
sp_rm:  defs    1
sp_last: defs   1
sp_bit: defs    1
sp_chg: defs    1
r_cur:  defs    1
r_cnt:  defs    1
co_n:   defs    1
co_p:   defs    2
g_k:    defs    1
g_bit:  defs    1
g_mask: defs    1
g_cur:  defs    1
its:    defs    8 * I_SIZE
el_rem: defs    1
el_dy:  defs    1
el_i:   defs    1
el_hw:  defs    2
