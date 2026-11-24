/*
 * f18a.c -- on an F18A (or a PICO9918) the field has the VGA build's look
 * (src/msdos/vga/video.c): the sky a ramp from its top's colour to the
 * horizon's, the dirt in 8 strata each darker than the one above with a
 * grain in it, the fire's 16 colours cycling down it.
 *
 * The screen stays the stock one (Graphics II, src/tms9918/): what changes
 * is four of the palette's entries, set again every scanline by a program
 * on the F18A's GPU (the copper: tools/nabu/mkcopper.py). The field's
 * lines draw the sky in entry 4, the dirt in 6 with its grain in 2, the
 * fire in 5 (st_line, st_fire: f18a_look rewrites what field.asm's styles
 * made), the copper giving those entries line y's colours; on the HUD's
 * rows, and while the field isn't shown, they are the TMS9918A's again.
 * Nothing else on a field line uses them (the seats' colours, black and
 * white), so the talk and the tanks look as they do on a stock VDP.
 *
 * The F18A shows more than four sprites on a line once unlocked (VR30):
 * no tank is drawn in the bitmap (field.asm's ao_lim).
 *
 * The tiles draw from the palette's second 16 (VR24 = 1), a copy of the
 * TMS9918A's colours that the copper changes: the first 16 are never
 * written, so a reset (no quitting on the NABU) leaves whatever runs next
 * its colours (the F18A's palette outlives a reset; VR24 doesn't).
 *
 * The title (menus.c) has the VGA build's colours too (f18a_title): the
 * copper's second part, tools/mkgfx_tms.py's table of them.
 *
 * The F18A is unlocked once (f18a_detect) and not locked again till we
 * quit (f18a_quit: a write to VR57 then would turn things off).
 */
#include <stdint.h>
#include <string.h>
#include "nabu.h"
#include "tms.h"
#include "plat.h"
#include "copper.h"

uint8_t f18a;                   /* there is one: the field's VGA look */
uint8_t st_grain[256];          /* the dirt's grain (render.asm: a line's seed + its column's) */

extern uint8_t st_line[];       /* render.asm: a field line's styles, 5 bytes */
extern uint8_t st_fire[8];
extern uint8_t st_stars, fire_ph;
extern uint8_t ao_lim;          /* field.asm: tanks on a line the sprites take */
uint8_t plat_rand(void);

#define FIELD_H 168
#define E_GRAIN 2               /* the palette's entries the copper sets */
#define E_SKY   4
#define E_FIRE  5
#define E_DIRT  6

/* the copper's tables (3F00h: mkcopper.py) */
static struct {
    uint8_t sky[FIELD_H];       /* 84 words, a word every 2 lines */
    uint8_t dirt[32];           /* 8 strata: the dirt's colour, its grain's */
    uint8_t fire[32];
    uint8_t std[8];             /* entries 2, 4, 5, 6 as the TMS9918A has them */
    uint8_t phase, on;
} cp;
#define CP_ON (FIELD_H + 32 + 32 + 8 + 1)    /* (3FF1h: on) */

/* the VGA build's: the skies' top and horizon, the dirts' top stratum, the
 * fire's 16 (6-bit RGB) */
static const uint8_t skies[8][6] = {
    { 18, 34, 58, 30, 46, 63 }, { 4, 10, 40, 40, 52, 63 }, { 0, 0, 4, 6, 4, 16 },
    { 10, 10, 14, 30, 30, 34 }, { 16, 4, 28, 63, 36, 8 }, { 10, 6, 3, 3, 2, 1 },
    { 0, 0, 0, 0, 0, 0 }, { 4, 10, 40, 40, 52, 63 } };
static const uint8_t dirts[8][3] = {
    { 44, 26, 10 }, { 18, 38, 12 }, { 34, 34, 34 }, { 50, 20, 8 },
    { 54, 42, 12 }, { 16, 22, 42 }, { 34, 16, 38 }, { 58, 38, 8 } };
static const uint8_t fires[16][3] = {
    { 63, 63, 40 }, { 63, 58, 20 }, { 63, 50, 8 }, { 63, 40, 4 }, { 63, 30, 0 }, { 60, 20, 0 },
    { 54, 12, 0 }, { 48, 6, 0 }, { 54, 12, 0 }, { 60, 20, 0 }, { 63, 30, 0 }, { 63, 40, 4 },
    { 63, 50, 8 }, { 63, 58, 20 }, { 63, 63, 40 }, { 63, 63, 52 } };

/* The TMS9918A's 16 colours as the F18A has them at power-on. */
static const uint16_t tms_pal[16] = {
    0x000, 0x000, 0x2C3, 0x5D6, 0x54F, 0x76F, 0xD54, 0x4EF,
    0xF54, 0xF76, 0xDC3, 0xED6, 0x2B2, 0xC5C, 0xCCC, 0xFFF,
};

static void vram_put(uint16_t a, const void *s, uint16_t n)
{
    va_addr = a;
    va_src = (const uint8_t *)s;
    va_len = n;
    va_write();
}

/* entries n.. as the TMS9918A's 16 colours (VR47: the data port, auto increment) */
static void f_palette_from(uint8_t n, const uint16_t *p, uint8_t k)
{
    uint8_t i;
    VDP_LOCK();
    VDP_CTRL = 0xC0 | n;
    VDP_CTRL = 0x80 | 47;
    for (i = 0; i < k; ++i) {
        VDP_DATA = (uint8_t)(p[i] >> 8);
        VDP_DATA = (uint8_t)p[i];
    }
    VDP_CTRL = 0;
    VDP_CTRL = 0x80 | 47;
    VDP_UNLOCK();
}

static void f_palette(uint8_t n)
{
    f_palette_from(n, tms_pal, 16);
}

/* The F18A's other 48 at power-on (its palettes 1-3: ECM1's TMS9918A, CGA,
 * ECM1's CGA): put back on quitting, the first 16 being tms_pal. */
static const uint16_t pal_rest[48] = {
    0x000, 0x2C3, 0x000, 0x54F, 0x000, 0xD54, 0x000, 0x4EF,
    0x000, 0xCCC, 0x000, 0xDC3, 0x000, 0xC5C, 0x000, 0xFFF,
    0x000, 0x00A, 0x0A0, 0x0AA, 0xA00, 0xA0A, 0xA50, 0xAAA,
    0x555, 0x55F, 0x5F5, 0x5FF, 0xF55, 0xF5F, 0xFF5, 0xFFF,
    0x000, 0x555, 0x000, 0x00A, 0x000, 0x0A0, 0x000, 0x0AA,
    0x000, 0xA00, 0x000, 0xA0A, 0x000, 0xA50, 0x000, 0xFFF,
};

/* 6-bit RGB to the F18A's 0RGB word, as two bytes (high first) */
static void rgb(uint8_t *d, uint8_t r, uint8_t g, uint8_t b)
{
    d[0] = (uint8_t)((r * 15 + 31) / 63);
    d[1] = (uint8_t)(((g * 15 + 31) / 63) << 4 | (b * 15 + 31) / 63);
}

/* An F18A or a PICO9918: unlocked (VR57 = 1Ch twice), it says so in status
 * register 1's top bits (VR15 picks it). A TMS9918A takes the writes as
 * registers 1 and 7: tms_init sets them after. */
void f18a_detect(void)
{
    uint8_t id;
    VDP_LOCK();
    id = VDP_CTRL;
    VDP_CTRL = 0x1C;
    VDP_CTRL = 0x80 | 57;
    VDP_CTRL = 0x1C;
    VDP_CTRL = 0x80 | 57;
    VDP_CTRL = 1;
    VDP_CTRL = 0x80 | 15;
    id = VDP_CTRL;              /* (the first may be stale) */
    id = VDP_CTRL;
    VDP_CTRL = 0;
    VDP_CTRL = 0x80 | 15;
    VDP_UNLOCK();
    f18a = (id & 0xE0) == 0xE0;
}

/* After tms_init: the copper into the VRAM (started by f18a_look). */
void f18a_start(void)
{
    uint8_t i;
    uint16_t h = 0x5A17;
    if (!f18a)
        return;
    for (i = 0; i < 4; ++i) {
        static const uint8_t e[4] = { E_GRAIN, E_SKY, E_FIRE, E_DIRT };
        cp.std[i * 2] = (uint8_t)(tms_pal[e[i]] >> 8);
        cp.std[i * 2 + 1] = (uint8_t)tms_pal[e[i]];
    }
    for (i = 0; i < 16; ++i)
        rgb(cp.fire + i * 2, fires[i][0], fires[i][1], fires[i][2]);
    i = 0;
    do {                        /* the grain: a pixel in four or so */
        h = h * 75 + 74;
        st_grain[i] = (uint8_t)(h >> 8);
        h = h * 75 + 74;
        st_grain[i] &= (uint8_t)(h >> 8);
    } while (++i);
    cp.phase = cp.on = 0;
    vram_put(COPPER_TAB, &cp, sizeof(cp));
    vram_put(COPPER_ORG, copper, sizeof(copper));
    vram_put(COPPER_TITLE_ORG, copper_title, sizeof(copper_title));
    f_palette(16);              /* the tiles' 16: the TMS9918A's, copied */
    vdp_reg(24, 0x01);          /* (VR24: tiles from entries 16-31) */
    ao_lim = 11;                /* (ten tanks: never one in the bitmap) */
    vdp_reg(30, 31);            /* sprites a line: 31 */
    /* (the copper runs only while the field is shown: f18a_look starts it) */
}

/* field.asm's field_open, its styles made: the round's look, the copper on */
void f18a_look(uint8_t sky, uint8_t pal)
{
    uint8_t y, i, *p;
    const uint8_t *a, *b, *c;
    if (!f18a)
        return;
    sky &= 7;
    pal &= 7;
    a = skies[sky];
    b = a + 3;
    for (y = 0; y < FIELD_H / 2; ++y)
        rgb(cp.sky + y * 2,
            (uint8_t)(a[0] + ((int16_t)b[0] - a[0]) * y / (FIELD_H / 2 - 1)),
            (uint8_t)(a[1] + ((int16_t)b[1] - a[1]) * y / (FIELD_H / 2 - 1)),
            (uint8_t)(a[2] + ((int16_t)b[2] - a[2]) * y / (FIELD_H / 2 - 1)));
    c = dirts[pal];
    for (i = 0; i < 8; ++i) {   /* darker down; the grain darker still */
        uint8_t r = (uint8_t)(c[0] * (16 - i) / 16), g = (uint8_t)(c[1] * (16 - i) / 16),
                bl = (uint8_t)(c[2] * (16 - i) / 16);
        rgb(cp.dirt + i * 4, r, g, bl);
        rgb(cp.dirt + i * 4 + 2, (uint8_t)(r * 5 / 8), (uint8_t)(g * 5 / 8), (uint8_t)(bl * 5 / 8));
    }
    p = st_line;
    for (y = 0; y < FIELD_H; ++y, p += 5) {
        if (st_stars)
            p[0] = (uint8_t)((p[0] & 0xF0) | E_SKY);    /* the stars on the sky */
        else {
            p[0] = E_SKY << 4 | E_SKY;
            p[1] = 0;
        }
        p[2] = E_GRAIN << 4 | E_DIRT;
        p[3] = plat_rand() | 1; /* (render.asm: not 0, so grained) */
        p[4] = E_DIRT << 4 | E_SKY;
    }
    memset(st_fire, E_FIRE << 4, 8);
    cp.phase = fire_ph = 0;
    cp.on = 1;
    vram_put(COPPER_TAB, &cp, sizeof(cp));
    vdp_reg(54, COPPER_ORG >> 8);
    vdp_reg(55, COPPER_ORG & 0xFF);     /* the copper (re)started */
}

/* menus.c's title, drawn (scr_picture): the VGA build's colours on it, the
 * copper setting the tiles' entries a pair of lines at a time from its
 * table (gen/nabu/title.asm: tools/mkgfx_tms.py f18a_table, packed), put
 * where the shake's names are (VRAM 1C00h: f18a_title_end puts them back).
 * The table is unpacked into the field's store (free till a room, as
 * title.asm has it). */
extern const uint8_t title_f18a[];
extern const uint8_t *lz_src;
extern uint8_t *lz_dst;
void lz_unpack(void);
#define T_BUF ((uint8_t *)0xD000)       /* (tools/nabu/build.py SHADOW_ORG) */
#define T_LEN 768

void f18a_title(void)
{
    if (!f18a)
        return;
    lz_src = title_f18a;
    lz_dst = T_BUF;
    lz_unpack();
    vram_put(COPPER_TITLE_TAB, T_BUF, T_LEN);
    vdp_r7 = C_BLACK;                   /* the border black (entry 4's the sky's here: the */
    vdp_reg(7, C_BLACK);                /* next screen's scr_begin sets its own) */
    cp.on = 2;
    vram_put(COPPER_TAB + CP_ON, &cp.on, 1);
    vdp_reg(54, COPPER_ORG >> 8);
    vdp_reg(55, COPPER_ORG & 0xFF);     /* the copper (re)started */
}

/* the title left: the copper stopped, the TMS9918A's colours, the shake's
 * names (scr.asm's: the field's rows a cell left, the HUD's not) */
void f18a_title_end(void)
{
    uint8_t r, c, *p = T_BUF;
    if (!f18a)
        return;
    f18a_off();
    for (r = 0; r < 24; ++r)
        for (c = 0; c < 32; ++c)
            *p++ = (uint8_t)(((c + (r < 21)) & 31) | (r & 7) << 5);
    vram_put(0x1C00, T_BUF, T_LEN);
}

/* field.asm's field_off: a text screen comes */
void f18a_off(void)
{
    if (!f18a)
        return;
    cp.on = 0;
    vram_put(COPPER_TAB + CP_ON, &cp.on, 1);
    /* the GPU stopped off the field: it busy-waits on the scanline, and a
       PICO9918 serves the Z80's reads meanwhile (the menus read the VRAM);
       the tiles' 16 the TMS9918A's again */
    vdp_reg(56, 0);
    f_palette(16);
}

/* field.asm's fire_step: the fire's colours a step on (the copper's) */
void f18a_fire(void)
{
    cp.phase = fire_ph;
    vram_put(COPPER_TAB + CP_ON - 1, &cp.phase, 1);
}

/* Quitting: the F18A as it comes up at power-on, for the NABU's ROM and
 * whatever runs next (not every F18A or PICO9918 is reset by the reset
 * button): the copper stopped, the 64 colours of power-on, then VR50's
 * reset (every register as at power-on, VR24 and VR30 too, and locked
 * again: safe now, nothing of ours draws after). */
void f18a_quit(void)
{
    if (!f18a)
        return;
    f18a_off();                 /* (the copper's stock colours, should it run on) */
    vdp_reg(56, 0);             /* the GPU stopped */
    vdp_reg(1, 0xA0);           /* (blanked meanwhile) */
    f_palette(0);
    f_palette_from(16, pal_rest, 48);
    vdp_reg(50, 0x80);          /* the registers reset, the F18A locked */
}
