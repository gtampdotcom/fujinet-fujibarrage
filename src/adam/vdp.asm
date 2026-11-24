; vdp.asm -- the VDP's writers (tms.h), from FujiBlast's. Arguments are
; variables, not the stack (whatever zsdcc's calling convention). Each
; locks the NMI out (vdp_busy) and unlocks at the end, taking a frame the
; NMI held back (vdp_catch_up, nmi.asm). A zero count does nothing (a count
; that counts down from zero would spray 64K of RAM over the VRAM).

        SECTION code_user

        PUBLIC  _va_addr, _va_len, _va_src, _va_val
        PUBLIC  _va_write, _va_writef, _va_fill, _va_read
        EXTERN  _vdp_busy, _vdp_pend, _vdp_catch_up

        INCLUDE "vdpio.inc"     ; VDP_DATA, VDP_CTRL (the platform's)

; lock; the address va_addr (A's bit 6 set: a write); DE the count, HL the source
setup:
        ld      c,a
        ld      a,1
        ld      (_vdp_busy),a
        ld      hl,(_va_addr)
        ld      a,l
        out     (VDP_CTRL),a
        ld      a,h
        and     $3F
        or      c
        out     (VDP_CTRL),a
        ld      de,(_va_len)
        ld      hl,(_va_src)
        ret

unlock:
        xor     a
        ld      (_vdp_busy),a
        ld      a,(_vdp_pend)
        or      a
        ret     z
        jp      _vdp_catch_up

; 50 T-states a byte
_va_write:
        ld      de,(_va_len)
        ld      a,d
        or      e
        ret     z
        ld      a,$40
        call    setup
wl:     ld      a,(hl)
        out     (VDP_DATA),a
        inc     hl
        dec     de
        ld      a,d
        or      e
        jr      nz,wl
        jr      unlock

; OTIR, 21 T-states a byte
_va_writef:
        ld      de,(_va_len)
        ld      a,d
        or      e
        ret     z
        ld      a,$40
        call    setup
fl:     ld      a,d
        or      a
        jr      z,ftail
        ld      bc,VDP_DATA     ; b = 0 is 256
        otir
        dec     d
        jr      fl
ftail:  ld      a,e
        or      a
        jr      z,unlock
        ld      b,a
        ld      c,VDP_DATA
        otir
        jr      unlock

; 41 T-states a byte
_va_fill:
        ld      de,(_va_len)
        ld      a,d
        or      e
        ret     z
        ld      a,$40
        call    setup
        ld      a,(_va_val)
        ld      h,a
fi:     ld      a,h
        out     (VDP_DATA),a
        dec     de
        ld      a,d
        or      e
        jr      nz,fi
        jr      unlock

; va_len bytes of VRAM va_addr to va_src, 50 T-states a byte
_va_read:
        ld      de,(_va_len)
        ld      a,d
        or      e
        ret     z
        xor     a
        call    setup
rl:     in      a,(VDP_DATA)
        ld      (hl),a
        inc     hl
        dec     de
        ld      a,d
        or      e
        jr      nz,rl
        jr      unlock

        SECTION bss_user
_va_addr:       defs    2
_va_len:        defs    2
_va_src:        defs    2
_va_val:        defs    1
