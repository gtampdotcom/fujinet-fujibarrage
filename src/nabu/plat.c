/*
 * plat.c -- the NABU PC: start-up, the 60 Hz clock and quitting (the
 * Adam's src/adam/plat.c; the interrupts FujiBlast's NABU src/nabu/plat.c's).
 * The menu and the game are one program here (main.c's ONE_PROGRAM): there
 * is room for both, so nothing is loaded again.
 *
 * The clock is the VDP's frame interrupt (irq.asm, IM 2 through the AY's
 * mask): it counts frame_count (the game's 60ths) and vbi_ticks (the
 * scripts' clock, display frames), and steps the sound. The HCCA's replies
 * come by interrupt too (nabu_hw.asm), so a network call loses no time.
 *
 * The game's loop is one pass a jiffy (src/main.c). When it is behind,
 * frame_wait returns at once and the pass is logic only, a few at most.
 * While it waits, the field's changed cells are drawn (src/tms9918/).
 */
#include <string.h>
#include "nabu.h"
#include "tms.h"
#include "game.h"
#include "input.h"
#include "plat.h"
#include "sound.h"
#include "scr.h"
#include "nstrans.h"
#include "tmsgfx.h"
#include "hcca.h"
#include "dbg.h"

#define CATCH_UP 30             /* jiffies behind: past this (a stall), let them go */
#define MAX_SKIP 4              /* passes in a row with no drawing, at most */

uint8_t gfx_fast;
static uint16_t seed = 0x1234;
static uint8_t hz = 60;
uint16_t hz_n;                  /* (for the rig: the loop's count over a frame) */
uint16_t nabu_passes;           /* frame_wait's passes (nstrans.c: once a pass at most) */
uint8_t plat_will_draw = 1;     /* 0: a pass made up to catch up (nstrans.c leaves the wire) */

#define FC (*(volatile uint16_t *)&frame_count)

void vdp_reg(uint8_t r, uint8_t v)
{
    VDP_LOCK();
    VDP_CTRL = v;
    VDP_CTRL = 0x80 | r;
    VDP_UNLOCK();
}

/* The field rate, 60 or 50: a loop counted from one frame to the next
 * (3.58 MHz, as the Adam: a frame is 59,736 T-states at 60, the loop 26). */
static void hz_measure(void)
{
    __asm
        ld      hl,_frame_count
        ld      a,(hl)
    hz_a:
        cp      (hl)            ; (a frame first)
        jr      z,hz_a
        ld      a,(hl)
        ld      bc,0
    hz_b:
        inc     bc              ; 6
        cp      (hl)            ; 7
        jr      z,hz_b          ; 12 (26 a turn)
        ld      (_hz_n),bc
    __endasm;
    hz = hz_n > 2600 ? 50 : 60;
    nmi_pal = hz == 50;
}

void plat_init(void)
{
    snd_hush();                 /* whatever the boot ROM left sounding */
    inp_hook = inp_hook_dir = inp_hook_btn = inp_hook_key = 0;
    hcca_init();                /* the replies' handler */
    kb_install();
    vdp_install();              /* the frame's */
    (void)ay_vdp_int_on();      /* and the three in the AY's mask */
    f18a_detect();              /* (an F18A: the field's VGA look, f18a.c) */
    tms_init();                 /* the VDP's tables; its interrupt on */
    art_load();                 /* the tanks and the font into the VRAM */
    f18a_start();
    hz_measure();
    snd_init();
    input_init();
    dbg("start");
#ifdef VIDEO_CARD
    tms_card();                 /* M0: the test card, the clock running */
#endif
}

/* The title's ESC: back to the boot ROM (the Internet Adapter's menu), as
 * after a reset: the link closed, the sound silent, the VDP blanked with
 * its interrupt off, an F18A as at power-on (f18a_quit), the ROM in and
 * its start. */
void plat_quit(void)
{
    nst_close();
    snd_stop();
    snd_hush();
    vdp_reg(1, 0x80);           /* 16K, blanked, no interrupt */
    f18a_quit();
    __asm
        di
        in      a,(0xA1)        ; (a pending frame interrupt: gone)
        ld      a,2             ; the boot ROM back in
        out     (0),a
        rst     0
    __endasm;
}

/* The server's round timer says what real time did: each second it ticks,
 * the jiffies counted since are set against 60, and what is missing goes
 * back on the clock, one a pass (the Adam's: an HCCA reply or a long VDP
 * burst holds a frame back). */
static uint8_t tm_last = 0xFF;
static uint16_t tm_at;
static int8_t drift;

static void clock_check(void)
{
    uint8_t t = st[OFF_TIMER];
    int16_t d;
    if (t != tm_last) {
        if ((uint8_t)(tm_last - t) == 1) {
            d = drift + 60 - (int16_t)(frame_count - tm_at);
            drift = d > 90 ? 90 : d < -90 ? -90 : (int8_t)d;
        }
        tm_last = t;
        tm_at = frame_count;
    }
    if (drift > 0) {
        __asm__("di");          /* (the interrupt changes it too) */
        ++frame_count;
        __asm__("ei");
        --drift;
    }
}

static uint16_t tf_seen;        /* the frame tms_frame last had */

void frame_wait(void)
{
    static uint16_t seen;
    static uint8_t skipped;     /* passes since the last drawn */
    uint16_t d;
    ++nabu_passes;
    clock_check();
    d = FC - seen;
    if (d > CATCH_UP) {         /* a stall: let it go */
        seen = FC - 1;
        d = 1;
    }
    seed += frame_count;
    if (d >= 2 && skipped < MAX_SKIP) {
        ++skipped;
        ++seen;                 /* behind: a pass with no drawing */
        plat_will_draw = 0;
        return;
    }
    plat_will_draw = 1;
    skipped = 0;
    while (FC == seen)
        tms_idle();             /* the field's changed cells, meanwhile */
    gfx_fast = d == 0;          /* we waited: the blank is ours */
    ++seen;
    tf_seen = FC;
    tms_frame();
}

/* the scripts' clock (play_segment waits on it): the field drawn meanwhile,
   and each frame's tms_frame (the sprites, the shake, the fire's colours) */
uint8_t vbi_now(void)
{
    if (FC != tf_seen) {
        tf_seen = FC;
        gfx_fast = 0;           /* (how far into the frame: not known) */
        tms_frame();
    } else
        tms_idle();
    return vbi_ticks;
}

uint8_t plat_rand(void)
{
    /* xorshift, stirred by the frame count */
    seed ^= seed << 7;
    seed ^= seed >> 9;
    seed ^= seed << 8;
    return (uint8_t)seed;
}

uint8_t plat_hz(void)
{
    return hz;
}
