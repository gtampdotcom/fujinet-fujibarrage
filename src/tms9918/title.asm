; title.asm -- the menu's title picture (scr.h SCR_PICTURE; tools/mkgfx_tms.py
; title): its pattern and colour tables, packed, unpacked here (lzd.asm)
; and written while the screen is blanked.

        SECTION code_user

        INCLUDE "vdpio.inc"

        PUBLIC  _scr_picture
        EXTERN  _title_pat, _title_col, _lz_unpack, _lz_src, _lz_dst
        EXTERN  _va_addr, _va_src, _va_len, _va_writef
        EXTERN  _scr_begin, _scr_show, scr_rpal, _vdp_r7, _vdp_busy, _vdp_pend, _vdp_catch_up

; void scr_picture(void)
_scr_picture:
        call    _scr_begin
        ld      hl,_title_pat
        ld      de,$0000
        call    table
        ld      hl,_title_col
        ld      de,$2000
        call    table
        ld      hl,scr_rpal     ; (no row the text's: a row changes it all)
        ld      b,24
sp_r:   ld      (hl),$FF
        inc     hl
        djnz    sp_r
        ld      a,1             ; R7: the border dark blue
        ld      (_vdp_busy),a
        ld      a,4
        ld      (_vdp_r7),a
        out     (VDP_CTRL),a
        ld      a,$87
        out     (VDP_CTRL),a
        xor     a
        ld      (_vdp_busy),a
        ld      a,(_vdp_pend)
        or      a
        call    nz,_vdp_catch_up
        jp      _scr_show

; table: the stream at HL unpacked to VRAM DE
table:  ld      (_lz_src),hl
        ld      (_va_addr),de
        ld      hl,big
        ld      (_lz_dst),hl
        call    _lz_unpack
        ld      hl,big
        ld      (_va_src),hl
        ld      hl,$1800
        ld      (_va_len),hl
        jp      _va_writef

IFDEF TITLE_BUF                         ; (the platform's build may lend it memory: the
        defc    big = TITLE_BUF         ; NABU's field store, free until a room)
ELSE
        SECTION bss_user
big:    defs    $1800
ENDIF
