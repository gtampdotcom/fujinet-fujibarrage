/*
 * nabu.h -- the NABU PC: the TMS9918A at ports A0h (data) and A1h
 * (control), the frame interrupt, and the routines written in assembler
 * (irq.asm, vdp.asm, nabu_hw.asm, ay.asm, art.asm). The Adam's adam.h, with the
 * NABU's clock and its keyboard, network and sound in place of EOS's.
 *
 * The VDP's interrupt reaches the Z80 through the AY's interrupt mask (IM 2:
 * irq.asm's vdp_isr). Reading the VDP's status also resets its address
 * latch, so it must not land between the two bytes of an address or inside
 * a burst of data: while the game is at the VDP (vdp_busy) the handler takes
 * the VDP out of the mask and says so in vdp_pend, and the unlock
 * (vdp_catch_up) puts it back, when the frame comes at once.
 */
#ifndef NABU_H
#define NABU_H

#include <stdint.h>

__sfr __at 0xA0 VDP_DATA;
__sfr __at 0xA1 VDP_CTRL;
extern volatile uint8_t vdp_busy, vdp_pend;
void vdp_catch_up(void);
#define VDP_LOCK()   (vdp_busy = 1)
#define VDP_UNLOCK() do { vdp_busy = 0; if (vdp_pend) vdp_catch_up(); } while (0)

/* irq.asm: display frames (the script's clock), the effects the frame
 * writes to the VDP (the flash: R1 blanked and R7 white for flash_n
 * frames; the shake: R2 through shake_seq) */
extern volatile uint8_t vbi_ticks;
extern volatile uint8_t flash_n, shake_n;
extern uint8_t nmi_pal;         /* a 50 Hz machine: every fifth frame counts twice */
void vdp_install(void);         /* the frame's handler in the IM 2 table */

/* nabu_hw.asm */
void kb_install(void);          /* the keyboard's handler in the IM 2 table */
uint8_t kb_get(void);           /* the next keyboard code, 0 if none */

/* art.asm: the Adam's art block (gen/nabu/art.bin) into the VRAM's 3800h */
void art_load(void);

/* f18a.c: an F18A or a PICO9918 (f18a): the field's VGA look */
extern uint8_t f18a;
void f18a_detect(void);
void f18a_start(void);
void f18a_quit(void);
void f18a_title(void);          /* menus.c title(): its VGA colours, and after */
void f18a_title_end(void);

/* the sound's frame (irq.asm calls it; src/sound/) */
void snd_nmi(void);

#endif
