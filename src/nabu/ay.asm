; ay.asm -- the sound's back end on the NABU's AY-3-8910 (latch 41h, data
; 40h): src/sound/snd.asm's three voices onto its three channels, each
; register written only when it changes. The engine's voices are the AY's
; own already (a period of 111861 / Hz is the AY's 1.79 MHz / 16; a volume
; of 0-15 its 3 dB steps), so this is the SN76489's back end
; (src/sn76489/sn.asm) without its tricks:
;
;   A  channel A     B  channel B     C  channel C
;
; A tone is the channel's tone (12 bits: down to 27 Hz, the bass where it
; is written). A noise is the channel's noise: the AY has one noise period,
; the first noise's of A, C, B (sn.asm's order); its period, the effects'
; bits' period, is the AY's (the SN's noise clocked by tone 3 shifts at
; 3.58 MHz / 32n, the AY's at 1.79 MHz / 16n), 1-31.
;
; Register 7's bit 6 is port A's direction (out: the interrupt mask), bit 7
; port B's (in): the mixer keeps them. Every other AY access runs with
; interrupts off (hcca.c, nabu_hw.asm); this runs in the frame's interrupt,
; so those can't come between its latch and its data. The latch is left at
; 14, as the rest of the port expects.
;
; snd_hush (nabu_hw.asm: a reply kept the interrupts off) zeroed the
; volumes: the next frame writes them again.

        SECTION code_user

        PUBLIC  sn_update, sn_quiet, _snd_hushed
        EXTERN  snd_va, snd_vb, snd_vc

        defc    AY_LATCH = $41
        defc    AY_DATA = $40
        defc    MIX_OFF = $7F           ; every tone and noise off; port A out, B in

; ays: register A = E unless the shadow (HL) has it; keeps A, BC, DE, HL
ays:    push    af
        ld      a,(hl)
        cp      e
        jr      z,ays_x
        ld      (hl),e
        pop     af
        push    af
        out     (AY_LATCH),a
        ld      a,e
        out     (AY_DATA),a
ays_x:  pop     af
        ret

; void sn_quiet(void): everything off, the shadows forgotten (from C)
sn_quiet:
        di
        ld      hl,shadow
        ld      b,shadow_end-shadow
sq_l:   ld      (hl),$FF
        inc     hl
        djnz    sq_l
        ld      e,0
        ld      a,8
        ld      hl,s_vol
        call    ays
        inc     a
        inc     hl
        call    ays
        inc     a
        inc     hl
        call    ays
        ld      e,MIX_OFF
        ld      a,7
        ld      hl,s_mix
        call    ays
        ld      a,14
        out     (AY_LATCH),a
        ei
        ret

; sn_update: the voices to the chip (the frame's interrupt, snd.asm's last)
sn_update:
        ld      a,(_snd_hushed)
        or      a
        jr      z,su_go
        xor     a
        ld      (_snd_hushed),a
        dec     a
        ld      (s_vol),a       ; (FF: written again)
        ld      (s_vol+1),a
        ld      (s_vol+2),a
su_go:  ; the noise's period: the first noise of A, C, B
        ld      hl,snd_va
        ld      a,(hl)
        cp      2
        jr      z,su_np
        ld      hl,snd_vc
        ld      a,(hl)
        cp      2
        jr      z,su_np
        ld      hl,snd_vb
        ld      a,(hl)
        cp      2
        jr      nz,su_ch
su_np:  inc     hl
        ld      e,(hl)
        inc     hl
        ld      a,(hl)
        or      a
        jr      nz,su_n31
        ld      a,e
        cp      32
        jr      c,su_nlo
su_n31: ld      e,31
        jr      su_nset
su_nlo: or      a
        jr      nz,su_nset
        ld      e,1
su_nset:
        ld      hl,s_np
        ld      a,6
        call    ays
su_ch:  ld      c,MIX_OFF
        ld      hl,snd_va
        ld      b,0
        call    chan
        ld      hl,snd_vb
        ld      b,1
        call    chan
        ld      hl,snd_vc
        ld      b,2
        call    chan
        ld      e,c
        ld      hl,s_mix
        ld      a,7
        call    ays
        ld      a,14
        out     (AY_LATCH),a
        ret

; chan: channel B (0-2) sounds voice HL (kind, period, volume); C the
; mixer, its bits cleared for what sounds
chan:   ld      a,(hl)
        inc     hl
        cp      1
        jr      z,ch_tone
        cp      2
        jr      z,ch_noise
        ld      e,0             ; off
        jr      ch_vol
ch_noise:
        ld      a,8
        call    bitb
        cpl
        and     c
        ld      c,a
        inc     hl
        inc     hl
        ld      a,(hl)
        and     15
        ld      e,a
        jr      ch_vol
ch_tone:
        ld      a,1
        call    bitb
        cpl
        and     c
        ld      c,a
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,d
        cp      $10
        jr      c,ct_ok
        ld      de,$0FFF        ; (under 27 Hz: the lowest)
ct_ok:  push    hl              ; (the volume's)
        ld      a,b
        add     a,a
        ld      hl,s_per
        add     a,l
        ld      l,a
        jr      nc,ct_1
        inc     h
ct_1:   ld      a,b
        add     a,a             ; register 2b: the period's low byte
        call    ays
        inc     hl
        inc     a
        ld      e,d             ; 2b + 1: its high 4 bits
        call    ays
        pop     hl
        ld      a,(hl)
        and     15
        ld      e,a
ch_vol: ld      a,b
        ld      hl,s_vol
        add     a,l
        ld      l,a
        jr      nc,cv_1
        inc     h
cv_1:   ld      a,8
        add     a,b
        jp      ays

; bitb: A << B (keeps BC)
bitb:   push    bc
        inc     b
        jr      bb_t
bb_l:   add     a,a
bb_t:   djnz    bb_l
        pop     bc
        ret

        SECTION bss_user
_snd_hushed:    defs    1
shadow:
s_per:  defs    6               ; the channels' periods, low and high
s_vol:  defs    3
s_np:   defs    1
s_mix:  defs    1
shadow_end:
