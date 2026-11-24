/*
 * tms.h -- the TMS9918A as FujiBarrage uses it: Graphics II with an
 * identity name table (each of the 768 cells has its own pattern and
 * colours), 8x8 sprites. Shared by the Adam and, later, the MSX; the
 * platform says how the VDP is reached (src/adam/vdpio.inc, adam.h; the
 * NABU's src/nabu/vdpio.inc, nabu.h).
 *
 * VRAM:
 *   0000-17FF  patterns (three thirds of 256 cells, 8 bytes each)
 *   1800-1AFF  names, 0..255 in each third (the identity)
 *   1B00-1B7F  the sprite attribute table
 *   1B80-1BFF  free
 *   1C00-1EFF  names, the field rows a cell left (the shake: R2 07h)
 *   1F00-1FFF  free
 *   2000-37FF  colours, laid out as the patterns
 *   3800-3BFF  sprite patterns: 128 of 8 bytes
 *   3C00-3EFF  names, the field rows a cell right (the shake: R2 0Fh)
 *   3F00-3FFF  free
 *
 * In Graphics II the CPU may touch the VDP only every 8 us while the
 * screen is drawn (29 T-states): the safe writers take longer than that;
 * the fast ones (OTIR) are for the blank and a blanked display.
 */
#ifndef TMS_H
#define TMS_H

#include <stdint.h>

#define VR_PAT    0x0000
#define VR_NAME   0x1800
#define VR_SAT    0x1B00
#define VR_NAMEL  0x1C00
#define VR_COL    0x2000
#define VR_SPAT   0x3800
#define VR_NAMER  0x3C00
#define VR_FONT   0x3A00        /* the font's glyphs, read back (sprite names 64-127) */

#define R1_ON   0xE0            /* 16K, display on, IE, 8x8 sprites */
#define R1_OFF  0xA0            /* the same, blanked */

/* colours */
enum { C_CLEAR, C_BLACK, C_MGREEN, C_LGREEN, C_DBLUE, C_LBLUE, C_DRED, C_CYAN,
       C_MRED, C_LRED, C_DYELLOW, C_LYELLOW, C_DGREEN, C_MAGENTA, C_GREY, C_WHITE };

#ifdef __ADAM__
#include "adam.h"
#endif
#ifdef __NABU__
#include "nabu.h"
#endif

/* vdp.asm: the arguments are these variables */
extern uint16_t va_addr, va_len;
extern const uint8_t *va_src;
extern uint8_t va_val;
void va_write(void);            /* va_len bytes from va_src to VRAM va_addr */
void va_writef(void);           /* the same, flat out: blank or blanked display only */
void va_fill(void);             /* va_len bytes of va_val */
void va_read(void);             /* va_len bytes from VRAM va_addr to va_src */
void vdp_reg(uint8_t r, uint8_t v);

extern uint8_t vdp_seen;        /* status bits seen by the frame clock */
extern uint8_t vdp_r1;          /* R1 as the game wants it (the NMI's flash puts it back) */
extern uint8_t vdp_r7;          /* the backdrop */
extern uint8_t vdp_r2;          /* the name table (the shake puts it back) */
extern uint8_t gfx_fast;        /* this pass came as the frame did: the blank is ours */

#endif
