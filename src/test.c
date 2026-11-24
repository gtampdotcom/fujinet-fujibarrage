/*
 * test.c -- offline test scenes for the emulator rigs (tools/atarisim): the
 * screens on canned states and a real shot's bytes (gen/fixture.h, from
 * the server's refview -fixture), no network: a TEST=1 build (make atari
 * TEST=1) only. At start-up we mark
 * test_hook[1] $C3 and wait a third of a second for a rig to poke $5A into
 * test_hook[0], the scene into [2] and its argument into [3]:
 *   1  the field: the fixture's ground, ten tanks, its shot played every
 *      5 seconds with the held link's sound ([3] bit 0: stream sound only)
 *   2  the waiting room       3  a round's end       4  the game's end
 *   5  the field, ten tanks, no shot: aim with the stick (seat 0's turn;
 *      [3] bit 7: the sky, SKY_* in bits 0-2, in place of the fixture's)
 *   6  a tune (ARG 0 a round's end, 1 the game's end, 2 the shop)
 *   7  every effect, 3 seconds apart: SND_* 0-15 (a boom small), the
 *      boom's sizes 1-3, then the UI_* cues (the sound's WAVs)
 *   8  (the CoCo, the Adam, the PC) scene 5 for the art: [3] bits 0-2
 *      the sky, 3-5 the dirt palette, 6 a balloon, 7 a ball of fire (its
 *      colours cycling)
 *   9  (the CoCo, the Adam, the PC) the whistle held at 442.9, 885.8 and
 *      1771.7 Hz, 1.5 s each with 0.5 s between (the engines' tuning)
 */
#ifndef TEST_SCENES
#include "game.h"
uint8_t test_hook[4];
void test_check(void)
{
}
#else
#include <string.h>
#include "game.h"
#include "scr.h"
#include "input.h"
#include "plat.h"
#include "sound.h"
#include "field.h"
#ifdef __APPLE2__
#include "apple2/test/fixture.h"    /* (its own shape: make fixture-apple2) */
#elif defined(_COCO_BASIC_) && defined(COCO3)
#include "coco3/test/fixture.h"     /* (refview -fixture-all: every segment) */
#elif defined(_COCO_BASIC_)
#include "coco2/test/fixture.h"
#elif defined(__ADAM__)
#include "adam/test/fixext.h"       /* (the rig's: tools/adamsim/fixture.py) */
#elif defined(__MSDOS__)
#include "msdos/test/fixext.h"      /* (files on the disk: tools/dossim/fixture.py) */
#else
#include "fixture.h"
#endif

#ifndef FIX_NSEG
/* a fixture bigger than the script buffer can't be played: make it with
 * refview -buf SCRIPT_BUF */
typedef char fixture_fits[sizeof(fix_script) <= SCRIPT_BUF ? 1 : -1];
#endif

uint8_t test_hook[4];
uint16_t test_t0, test_t1;
#ifdef FIX_EXTERN
uint8_t fix_ram[FIX_RAM];
#endif              /* the shot's start and end, in jiffies: the lag */
#ifdef __ATARI__                        /* (the OS's clock: frame_count stands still in a script) */
#define TEST_NOW() ((uint16_t)(*(volatile uint8_t *)0x13 << 8 | *(volatile uint8_t *)0x14))
#elif defined(__ATARI5200__)            /* (the crt0's) */
#define TEST_NOW() ((uint16_t)(*(volatile uint8_t *)0x01 << 8 | *(volatile uint8_t *)0x02))
#else
#define TEST_NOW() frame_count
#endif

static const char names[SEATS][NAME_LEN] = {
    "ANN", "BOB", "CAT", "DOT", "EVE", "FAY", "GUS", "HAL", "IVY", "JOE" };

static void canned(void)
{
    uint8_t s;
    memset(st, 0, sizeof(st));
    st[OFF_PHASE] = PH_AIM;
    st[OFF_ROUND] = 2;
    st[OFF_ROUNDS] = 10;
    st[OFF_HOST] = 0;
    st[OFF_TURN] = 3;
    st[OFF_TIMER] = 27;
    st[OFF_TANKS] = 10;
    st[OFF_WIND] = 0xF4;
    st[OFF_WIND + 1] = 0xFF;
    st[OFF_SKY] = FIX_SKY;
    st[OFF_PALETTE] = FIX_PAL;
    st[OFF_RESULT] = 3;
    st[OFF_MY_SEAT] = 0;
    for (s = 0; s < SEATS; ++s) {
        memcpy((char *)st + OFF_SEATS + seat_off[s] + P_NAME, names[s], NAME_LEN);
        PL(s, P_KIND) = s < 3 ? KIND_HUMAN : KIND_BOT;
        PL(s, P_TIER) = s % N_TIERS;
        PL(s, P_ENERGY) = 100 - s * 7;
        PL(s, P_FLAGS) = PF_ALIVE | PF_CONN;
        PL16_SET(s, P_X, fix_tx[s]);
        PL(s, P_Y) = fix_ty[s];
        PL(s, P_ANGLE) = fix_ta[s];
        PL16_SET(s, P_POWER, 400);
        PL(s, P_WINS) = s & 3;
    }
    INV(I_MINI_MISSILE) = 99;
    my_seat = 0;
}

static void ground(void)
{
#ifdef FIELD_COLUMNS
    field_columns(0, fix_terrain, FIELD_W);
#else
    uint16_t x, at = 0;
    for (x = 0; x < FIELD_W; ++x) {
        field_column(x, fix_terrain + at);
        at += entry_len(fix_terrain + at);
    }
#endif
}

#if defined(_COCO_BASIC_) || defined(__ADAM__) || defined(__MSDOS__) || defined(__NABU__)
static uint8_t show;                    /* scene 8's extras */
#endif

static void field_scene(uint8_t shots, uint8_t stream_only)
{
    uint16_t t;
    ground();
    play_enter();
#if defined(_COCO_BASIC_) || defined(__ADAM__) || defined(__MSDOS__) || defined(__NABU__)
    if (show & 0x40)
        field_balloon(0, "NICE SHOT. NOW WATCH THIS ONE!", 30);
    if (show & 0x80) {
        field_ellipse(tk[4].x, tk[4].y - 40, 14, 12, PX_FX, 0);
        field_fire(1);
    }
#endif
    for (;;) {
        for (t = 0; t < 300; ++t) {
            tick();
            play_frame();
        }
        if (!shots)
            continue;
#ifdef FIX_EXTERN
        if (!stream_only)
            snd_full(1);
        {                               /* every segment in turn, from the rig */
            uint16_t played = 0, t0;
            for (seg_no = 0; seg_no < FIX_NSEG; ++seg_no) {
#ifdef FIX_FILES
                fix_seg(seg_no);        /* (the platform's: SEGn.BIN) */
#else
                test_hook[0] = (uint8_t)(0x80 | seg_no);
                while (test_hook[0] & 0x80)
                    frame_wait();
#endif
                seg_flags = S_LAST_FRAME | (seg_no == FIX_NSEG - 1 ? S_LAST_SEG : 0);
                t0 = TEST_NOW();
                play_segment();
                played += (uint16_t)(TEST_NOW() - t0);
            }
            test_t0 = 0;
            test_t1 = played;           /* (the time played, the asking left out) */
            test_hook[0] = 0xDD;
        }
#elif defined(FIX_NSEG)
        if (!stream_only)
            snd_full(1);
        {                               /* every segment in turn */
            uint16_t at = 0;
            test_t0 = TEST_NOW();
            for (seg_no = 0; seg_no < FIX_NSEG; ++seg_no) {
                seg_len = fix_seglen[seg_no];
                memcpy(script, fix_seg + at, seg_len);
                at += seg_len;
                seg_flags = S_LAST_FRAME | (seg_no == FIX_NSEG - 1 ? S_LAST_SEG : 0);
                play_segment();
            }
            test_t1 = TEST_NOW();
        }
#else
        memcpy(script, fix_script, sizeof(fix_script));
        seg_len = sizeof(fix_script);
        seg_no = 0;
        seg_flags = S_LAST_FRAME | S_LAST_SEG;
        if (!stream_only)
            snd_full(1);
        test_t0 = TEST_NOW();
        play_segment();
        test_t1 = TEST_NOW();
#endif
        for (t = 0; t < 40 && snd_busy(); ++t)
            frame_wait();
        snd_full(0);
        if (test_hook[3] & 2)           /* stop here: the field after the shot */
            for (;;)
                tick();
        for (t = 0; t < 120; ++t)
            tick();
        ground();                       /* the field as it was: again */
        canned();
        net_terrain = 1;
        play_state();
    }
}

void test_check(void)
{
    uint8_t n;
    uint16_t t;
    test_hook[1] = 0xC3;
#ifdef TEST_SCENE                        /* a rig that can't poke memory: built in */
    test_hook[0] = 0x5A;
    test_hook[2] = TEST_SCENE;
#ifdef TEST_ARG
    test_hook[3] = TEST_ARG;
#else
    test_hook[3] = 0;
#endif
#endif
    for (n = 0; n < 20 && test_hook[0] != 0x5A; ++n)
        frame_wait();
    if (test_hook[0] != 0x5A)
        return;
    test_hook[0] = 0xA5;
#ifdef FIX_FILES
    fix_load();                         /* (the platform's: FIX.BIN) */
#endif
    field_init();
    canned();
    strcpy(my_name, "ANN");
    strcpy(srv_table, "room1");
    inp_hook = 1;
    cat_ok = 0;
    switch (test_hook[2]) {
    case 1:
        field_scene(1, test_hook[3] & 1);
    case 5:
        st[OFF_TURN] = 0;
        if (test_hook[3] & 0x80)
            st[OFF_SKY] = test_hook[3] & 7;
        field_scene(0, 0);
#if defined(_COCO_BASIC_) || defined(__ADAM__) || defined(__MSDOS__) || defined(__NABU__)
    case 8:
        st[OFF_TURN] = 0;
        st[OFF_SKY] = test_hook[3] & 7;
        st[OFF_PALETTE] = (test_hook[3] >> 3) & 7;
        show = test_hook[3];
        field_scene(0, 0);
    case 9:
        for (;;) {
            static const uint8_t pit[3] = { 71, 35, 17 };
            for (n = 0; n < 3; ++n) {
                snd_whistle(1, pit[n]);
                for (t = 0; t < 90; ++t)
                    tick();
                snd_whistle(0, 0);
                for (t = 0; t < 30; ++t)
                    tick();
            }
        }
#endif
    case 6:                             /* a tune: 0 the round's, 1 the game's end, 2 the shop */
        snd_tune(test_hook[3] == 1 ? t_over1 : test_hook[3] == 2 ? t_shop1 : t_win1,
                 test_hook[3] == 1 ? t_over2 : test_hook[3] == 2 ? t_shop2 : t_win2);
        for (;;)
            tick();
    case 7:
        for (n = 0; n < 24; ++n) {
            snd_cue(n < 16 ? n : n < 19 ? SND_BOOM : UI_TICK + n - 19, n < 16 ? 0 : n < 19 ? n - 15 : 0);
            for (t = 0; t < 180; ++t)
                tick();
        }
        for (;;)
            tick();
    case 2:
        st[OFF_PHASE] = PH_WAIT;
        wait_enter();
        break;
    case 3:
    case 4:
        st[OFF_PHASE] = test_hook[2] == 3 ? PH_ROUNDEND : PH_GAMEOVER;
        results_enter(test_hook[2] == 4);
        break;
    }
    for (;;)
        tick();
}
#endif
