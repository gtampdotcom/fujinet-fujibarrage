/* plat.h -- start-up, the 60 Hz jiffy clock, randomness and quitting. */
#ifndef PLAT_H
#define PLAT_H

#include <stdint.h>

void plat_init(void);
void plat_quit(void);
void plat_reboot(void);         /* boot the disk again */

/* Jiffies since boot (60 a second; a 50 Hz machine counts every fifth twice). */
extern uint16_t frame_count;

/* Wait for the next frame. */
void frame_wait(void);

uint8_t plat_rand(void);
uint8_t plat_hz(void);          /* 50 or 60: the display's frames a second */
#ifdef __ATARI5200__
#define NAME_WHEEL              /* no keyboard: the name from a letter wheel (menus.c) */
#endif
#ifdef __APPLE2__
/* Nothing interrupts an Apple II: the clock counts when it is asked
 * (src/apple2/lowlevel.s), so the script's clock is a call that asks. */
void frame_tick(void);
uint8_t vbi_now(void);
#define vbi_count (vbi_now())
#elif defined(_COCO_BASIC_) || defined(__ADAM__) || defined(__MSDOS__) || defined(__NABU__)
/* The CoCo counts frames in its interrupt. Asking is also where the CoCo
 * 1/2 (no timer) plays a slice of sound while a script waits, where the
 * Adam draws the field's changed cells (src/tms9918/render.asm), and where
 * the PC's flash, shake and fire step (src/msdos/plat.c). */
uint8_t vbi_now(void);
#define vbi_count (vbi_now())
#else
extern volatile uint8_t vbi_count;  /* +1 each display frame (the script's clock) */
#endif

#endif
