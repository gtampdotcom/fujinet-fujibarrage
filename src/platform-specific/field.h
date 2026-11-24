/* field.h -- the playfield: a bitmap at the client's own resolution
 * (FIELD_W x FIELD_H), four pixel values, the tanks drawn into it; and the
 * status rows above it. play.c draws the server's TERRAIN and SCRIPT
 * through these; each platform implements them (src/atari/field.c). */
#ifndef FIELD_H_
#define FIELD_H_

#include <stdint.h>

#ifndef __CC65__
#define __fastcall__
#endif

#define PX_TANK 0
#define PX_SKY  1
#define PX_DIRT 2
#define PX_FX   3

#if defined(__ATARI__) || defined(__ATARI5200__)
/* (the 5200: the Atari's display in 16K of RAM, src/atari5200) */
#define FIELD_W 160
#define FIELD_H 168
#define TANK_W  7
#define TANK_H  5
#define PAR     109             /* pixel aspect, 64ths */
#ifdef __ATARI5200__
#define SCRIPT_BUF 1024
#define PLAT_ID   PLAT_ATARI5200
#define TXT_ITEMS "#: ITEMS"
#else
#ifndef SCRIPT_BUF                  /* (a rig's build may make it smaller) */
#define SCRIPT_BUF 1536
#endif
#define PLAT_ID   PLAT_ATARI    /* HELLO's platform and capabilities (proto.h) */
#define TXT_ITEMS "OPTION/I: ITEMS"   /* (the defence window, the items line shut) */
#endif
#define BANDS   4
#define PLAT_CAPS CAP_HOLD
#define ITEMS_ROW 2             /* the items line: the HUD's third row */
#define PLY_CATCHUP 4           /* script steps a pass, at most, when behind */
#define MARK_UP (TANK_H + 7)     /* the turn's arrow, its top: over the barrel */
#endif

#ifdef __APPLE2__
/* HGR page 1 is the field: 140 colour pixels (two dots each) by 160 lines,
 * mixed mode's four text rows the HUD (src/apple2/) */
#define FIELD_W 140
#define FIELD_H 160
#define TANK_W  5
#define TANK_H  5
#define PAR     117             /* pixel aspect, 64ths */
#ifndef SCRIPT_BUF
#define SCRIPT_BUF 1536
#endif
#define BANDS   0               /* the tanks are in the bitmap: no colour objects */
#define PLAT_ID   PLAT_APPLE2
#define PLAT_CAPS CAP_HOLD
#define ITEMS_ROW 3             /* the items line: the HUD's fourth row (talk's, in a script) */
#define PLY_CATCHUP 8
#define MARK_UP (TANK_H + 9)     /* the turn's arrow, its top: over the barrel and pennant */
#define TXT_ITEMS "I: ITEMS"
#endif

#if defined(_COCO_BASIC_) && defined(COCO3)
/* GIME 320x200x16: the field over a 3-row HUD (lines 176-199); each value
 * is a set of palette indices (src/coco3/fld3.asm) */
#define FIELD_W 320
#define FIELD_H 176
#define TANK_W  12
#define TANK_H  6
#define PAR     55              /* pixel aspect, 64ths (measured: M0) */
#define PLAT_ID   PLAT_COCO3
#define MARK_UP (TANK_H + 8)
#elif defined(_COCO_BASIC_)
/* PMODE 4 artifact colour: 128 colour pixels (two dots each) by 168 lines,
 * the bit pair the value, a 3-row HUD under it (src/coco2/fld2.asm) */
#define FIELD_W 128
#define FIELD_H 168
#define TANK_W  5
#define TANK_H  5
#define PAR     109             /* pixel aspect, 64ths (measured: M0) */
#define PLAT_ID   PLAT_COCO
#define MARK_UP (TANK_H + 9)
#endif
#ifdef _COCO_BASIC_
#ifndef SCRIPT_BUF
#define SCRIPT_BUF 1536
#endif
#define BANDS   0               /* the tanks are in the bitmap */
#define PLAT_CAPS CAP_HOLD
#define ITEMS_ROW 2
#define PLY_CATCHUP 8
#define TXT_ITEMS "I: ITEMS"
#endif

#if defined(__ADAM__) || defined(__NABU__)
/* TMS9918 Graphics II: the field 256x168 (character rows 0-20) over a
 * 3-row HUD; the tanks are sprites (src/tms9918/) */
#define FIELD_W 256
#define FIELD_H 168
#define TANK_W  7
#define TANK_H  5
#define PAR     73              /* pixel aspect, 64ths (5.37 MHz pixels) */
#ifndef SCRIPT_BUF
#define SCRIPT_BUF 1536
#endif
#define BANDS   4               /* sprites on a line (the rest go in the bitmap) */
#define FIELD_COLUMNS           /* field_columns: a frame's columns at once */
#define PLAT_ID   PLAT_ADAM
#define PLAT_CAPS CAP_HOLD
#define ITEMS_ROW 2
#define PLY_CATCHUP 8
#define MARK_UP (TANK_H + 7)     /* the turn's arrow, its top: over the barrel */
#define TXT_ITEMS "I: ITEMS"
#endif

#ifdef __MSDOS__
/* an IBM PC: CGA's 320x200 in 4 colours (src/msdos/cga) or VGA's and
 * MCGA's 256 (DOS_VGA: src/msdos/vga), the field 320x176 over a 3-row HUD;
 * the screen is the field, the tanks in it */
#define FIELD_W 320
#define FIELD_H 176
#define TANK_W  12
#define TANK_H  6
#define PAR     55              /* pixel aspect, 64ths (the CoCo 3's 7.16 MHz pixel) */
#ifndef SCRIPT_BUF
#define SCRIPT_BUF 4096
#endif
#define BANDS   0               /* the tanks are in the bitmap */
#ifdef DOS_VGA
#define PLAT_ID   PLAT_MSDOS_VGA
#else
#define PLAT_ID   PLAT_MSDOS
#endif
#define PLAT_CAPS CAP_HOLD
#define ITEMS_ROW 2
#define PLY_CATCHUP 8
#define MARK_UP (TANK_H + 8)
#define TXT_ITEMS "I: ITEMS"
#endif

void field_init(void);                      /* at start-up: all sky */
void field_loading(void);                   /* a whole field is coming */
void field_open(uint8_t sky, uint8_t pal);  /* the field screen on */
void field_column(uint16_t x, const uint8_t *entry);
#ifdef FIELD_COLUMNS
void field_columns(uint16_t x, const uint8_t *entry, uint16_t n);  /* n columns, entries in a row */
#endif
void field_plot(int16_t x, int16_t y, uint8_t v);
uint8_t field_get(int16_t x, int16_t y);
void field_swap(int16_t x, int16_t y, uint8_t from, uint8_t to);
void field_span(int16_t y, int16_t x0, int16_t x1, uint8_t v);
void field_tank(uint8_t seat, uint8_t draw);    /* tk[seat] drawn (1) or erased (0) */
void field_colours(void);                       /* the tanks moved: their colours follow */
void field_balloon(uint8_t seat, const char *s, uint8_t n);  /* n 0: take it away */
/* sparks from a tank: seat in the low byte, the kind in the high (0-7 a
 * death's DEATH_* effect, 8 + a shield's SH_* event). Only ever on sky, and
 * gone by the segment's end. */
void __fastcall__ field_sparks(uint16_t seat_kind);
void field_status(uint8_t row, uint8_t col, const char *s);
void field_status_hi(uint8_t row, uint8_t col, const char *s);  /* the same, to stand out (inverse) */
void field_status_clear(void);
void field_flash(uint8_t frames);
void field_fire(uint8_t on);                    /* the fire colours cycle */
/* an ellipse: mode 0 all of it v, 1 its sky v, 2 its colour 3 sky */
void field_ellipse(int16_t x, int16_t y, uint8_t rx, uint8_t ry, uint8_t v, uint8_t mode);

/* the script's tracks (OP_ARC): sixteen moving heads, drawn as they go */
void trk_reset(void);
void __fastcall__ trk_load(const uint8_t *args);    /* an OP_ARC's arguments */
void trk_step(void);                                /* all of them, a step */
void __fastcall__ trk_stop(uint8_t slot);
uint8_t trk_fall(void);                             /* the lowest falling one's line | 1, or 0 */

#endif
