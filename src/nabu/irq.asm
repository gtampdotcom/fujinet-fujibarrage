; irq.asm -- the NABU's frame clock: the VDP's interrupt, IM 2 (its entry
; in z88dk's table at I * 256 + 6), through the AY's interrupt mask (bit
; 10h). The Adam's nmi.asm, the frame the same:
;
; Reading the VDP's status lets the interrupt go, but also resets its
; address latch, which would spoil an address being set or a burst of data
; under way. While the game is at the VDP (vdp_busy, nabu.h) the handler
; leaves the status alone: it takes the VDP out of the mask and sets
; vdp_pend; the unlock (vdp_catch_up) puts it back, and the interrupt (the
; VDP still holds it) comes at once.
;
; The handler has interrupts on again once it has read the status, as
; FujiBlast's: the HCCA's receive interrupt (nabu_hw.asm) can't wait a
; frame's work. (MAME can take this interrupt again right after the read:
; the status, bit 7 clear then, says it isn't a frame.)
;
; A frame: vbi_ticks +1 (the script's clock: display frames), frame_count
; +1 (60ths: a 50 Hz machine counts every fifth frame twice), the flash and
; the shake (VDP registers, written here between frames, where nothing else
; is at the VDP), then the sound's frame.

        SECTION code_user

        PUBLIC  _vdp_install, _vdp_catch_up
        PUBLIC  _vdp_busy, _vdp_pend, _vdp_seen, _vbi_ticks, _frame_count
        PUBLIC  _flash_n, _shake_n, _shake_dx, _nmi_pal, _vdp_r1, _vdp_r7, _vdp_r2
        EXTERN  _snd_nmi, _int_mask

        INCLUDE "vdpio.inc"

_vdp_install:
        di
        ld      a,i
        ld      h,a
        ld      l,6
        ld      de,vdp_isr
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ei
        ret

vdp_isr:
        push    af
        ld      a,(_vdp_busy)
        or      a
        jr      nz,vi_defer
        in      a,(VDP_CTRL)    ; the status: lets the interrupt go
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        ei
        bit     7,a
        call    nz,frame
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
vi_defer:
        ld      a,1
        ld      (_vdp_pend),a
        ld      a,14            ; (every other AY access runs with interrupts off)
        out     ($41),a
        ld      a,(_int_mask)
        and     $EF             ; the VDP out of the mask
        out     ($40),a
        pop     af
        ei
        ret

; void vdp_catch_up(void): the VDP back in the mask; the frame held back
; comes at once
_vdp_catch_up:
        di
        xor     a
        ld      (_vdp_pend),a
        ld      a,14
        out     ($41),a
        ld      a,(_int_mask)
        out     ($40),a
        ei
        ret

; a frame, the status in A
frame:
        ld      hl,_vdp_seen
        or      (hl)
        ld      (hl),a
        ld      hl,_vbi_ticks
        inc     (hl)
        ld      hl,(_frame_count)
        inc     hl
        ld      a,(_nmi_pal)
        or      a
        jr      z,fr_count
        ld      a,(pal5)
        dec     a
        jr      nz,fr_pal
        inc     hl              ; every fifth: one more
        ld      a,5
fr_pal: ld      (pal5),a
fr_count:
        ld      (_frame_count),hl
        ; the flash: blanked on white while flash_n counts down
        ld      a,(_flash_n)
        or      a
        jr      z,fr_shake
        dec     a
        ld      (_flash_n),a
        jr      z,fr_unflash
        ld      a,(_vdp_r1)
        and     $BF             ; (blank)
        ld      c,1
        call    reg
        ld      a,$0F           ; white
        ld      c,7
        call    reg
        jr      fr_shake
fr_unflash:
        ld      a,(_vdp_r1)
        ld      c,1
        call    reg
        ld      a,(_vdp_r7)
        ld      c,7
        call    reg
        ; the shake: the name table through 06h 07h 06h 0Fh (the field a
        ; cell left, then right), the sprites with it (shake_dx)
fr_shake:
        ld      a,(_shake_n)
        or      a
        jr      z,fr_sound
        dec     a
        ld      (_shake_n),a
        ld      b,0
        jr      z,fr_still      ; the last: back to the middle
        and     3
        ld      e,a
        ld      d,0
        ld      hl,shake_r2
        add     hl,de
        ld      a,(hl)
        ld      hl,shake_x
        add     hl,de
        ld      b,(hl)
        jr      fr_r2
fr_still:
        ld      a,(_vdp_r2)
fr_r2:  ld      c,2
        push    bc
        call    reg
        pop     bc
        ld      a,b
        ld      (_shake_dx),a
fr_sound:
        jp      _snd_nmi

; VDP register C = A
reg:    out     (VDP_CTRL),a
        ld      a,c
        or      $80
        out     (VDP_CTRL),a
        ret

shake_r2:
        defb    $06, $07, $06, $0F
shake_x:
        defb    0, -8, 0, 8

        SECTION data_user
_vdp_r1:        defb    $A0     ; (blanked, IE: plat_init sets it)
_vdp_r2:        defb    $06
_vdp_r7:        defb    $01
pal5:           defb    5

        SECTION bss_user
_vdp_busy:      defs    1
_vdp_pend:      defs    1
_vdp_seen:      defs    1
_vbi_ticks:     defs    1
_frame_count:   defs    2
_flash_n:       defs    1
_shake_n:       defs    1
_shake_dx:      defs    1
_nmi_pal:       defs    1
