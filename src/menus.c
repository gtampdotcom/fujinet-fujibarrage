/*
 * menus.c -- the title, the name and the room list (text screens), and the
 * little things every screen uses: a frame's tick, messages.
 */
#include <string.h>
#include "game.h"
#include "layout.h"
#include "scr.h"
#include "input.h"
#include "plat.h"
#include "sound.h"

static uint8_t prev_dir;

void tick(void)
{
    frame_wait();
    input_poll();
    input_take();
}

uint8_t pressed(uint8_t bit)
{
    uint8_t p = (inp_dir & bit) && !(prev_dir & bit);
    return p;
}

#if defined(MENU) || defined(ONE_PROGRAM)
static void tick_dir(void)
{
    prev_dir = inp_dir;
}
#endif

static void centre(uint8_t row, const char *s)
{
    uint8_t n = strlen(s);
    scr_text(row, n < SCR_COLS ? (SCR_COLS - n) / 2 : 0, s);
}

void message(const char *a, const char *b, uint8_t frames)
{
    scr_begin();
    scr_row(10, PAL_HEAD);
    scr_row(11, PAL_HEAD);
    scr_row(12, PAL_HEAD);
    centre(10, a);
    centre(12, b);
    scr_show();
    if (!frames) {
        do {
            tick();
        } while (!ev_btn && ev_key == KEY_NONE);
        return;
    }
    while (frames--)
        tick();
}

#if defined(MENU) || defined(ONE_PROGRAM)
/* ---- the menu program's (MENU.COM): the title, the name, the room ---- */

void title(void)
{
#ifdef SCR_PICTURE
    scr_picture();
#ifdef __NABU__
    scr_row(0, PAL_TEXT);               /* (the picture's top row, the border's blue: the hint) */
    centre(0, QUIT_HINT);
#endif
#else
    uint8_t r;
    scr_begin();
    for (r = 3; r < 8; ++r)
        scr_row(r, PAL_TITLE);
    centre(4, "F U J I B A R R A G E");
    centre(6, TXT_TAGLINE);
    centre(12, "AIM, FIRE, TALK TRASH.");
    centre(14, TXT_GALORE);
    scr_row(20, PAL_HILITE);
    centre(20, "PRESS FIRE");
    scr_show();
#endif
    snd_tune(t_title1, t_title2);       /* (it plays on through the menus) */
    do {
        tick();
#ifdef QUIT_HINT                         /* (a platform that can quit: its title says so) */
        if (ev_key == KEY_ESC)
            plat_quit();
#endif
    } while (!ev_btn && ev_key == KEY_NONE);
    snd_cue(UI_GO, 0);
}

#ifdef NAME_WHEEL
/* no keyboard: a letter wheel. The stick's up and down turn it, right or
   the button takes the letter, left takes one back; the keypad's digits
   type themselves; START (RETURN) is done. */
static const char wheel[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
#endif

void name_entry(void)
{
    uint8_t n = 0;
#ifdef NAME_WHEEL
    uint8_t w = 0;
    char c[2];
    c[1] = 0;
#endif
#ifdef __NABU__
again:                                  /* (back from the title) */
    n = (uint8_t)strlen(my_name);       /* the name we have, to keep or rub out */
#endif
    scr_begin();
    scr_row(8, PAL_HEAD);
    centre(8, "WHAT'S YOUR NAME?");
    scr_row(12, PAL_HILITE);
#ifdef NAME_WHEEL
    centre(16, "UP/DOWN: LETTER  FIRE: TAKE IT");
    centre(18, "LEFT: BACK  START: DONE");
#endif
#ifdef __NABU__
    centre(16, "RETURN: DONE  ESC: BACK");
#endif
    scr_show();
    for (;;) {
        scr_clear_row(12);
        scr_text(12, (SCR_COLS - NAME_LEN) / 2, my_name);
#ifdef NAME_WHEEL
        if (n < NAME_LEN) {
            c[0] = wheel[w];
            scr_text(12, (SCR_COLS - NAME_LEN) / 2 + n, c);
        }
#endif
        scr_inverse(12, (SCR_COLS - NAME_LEN) / 2 + n, 1);
        tick();
        if (ev_key == KEY_RETURN && n)
            break;
#ifdef __NABU__
        if (ev_key == KEY_ESC) {        /* back to the title (whose ESC quits) */
            title();
            goto again;
        }
#endif
#ifdef NAME_WHEEL
        if (pressed(IN_UP))
            w = w ? w - 1 : sizeof(wheel) - 2;
        else if (pressed(IN_DOWN))
            w = w < sizeof(wheel) - 2 ? w + 1 : 0;
        else if ((pressed(IN_RIGHT) || ev_btn) && n < NAME_LEN)
            ev_key = wheel[w];
        else if (pressed(IN_LEFT))
            ev_key = KEY_BACK;
        tick_dir();
#endif
        if (ev_key == KEY_BACK && n)
            my_name[--n] = 0;
        else if (n < NAME_LEN && ((ev_key >= 'A' && ev_key <= 'Z') || (ev_key >= '0' && ev_key <= '9'))) {
            my_name[n++] = ev_key;
            my_name[n] = 0;
            snd_cue(UI_TICK, 0);
        }
    }
}
uint8_t room_list(void)
{
    uint8_t n, i, sel = 0;
    char b[8], nm[13];
    message("LOOKING FOR ROOMS", srv_host, 1);
    n = net_rooms();
#ifdef __NABU__
again:                                  /* (REFRESH: the list asked for again) */
    /* the link closed while the list is up: the server answers nothing
       (no pings) till we're in a room, and drops a quiet link; REFRESH and
       the room open their own */
    net_close();
#endif
    if (!n) {
        message("NO ROOMS FROM", srv_host, 0);
        return 0;
    }
#ifdef __NABU__
    if (sel > n)
        sel = n;
#endif
    scr_begin();
    scr_row(1, PAL_HEAD);
    centre(1, "PICK A ROOM");
    scr_text(3, 2, "ROOM          PEOPLE  PLAYING");
    for (i = 0; i < n; ++i) {
        memcpy(nm, rooms[i] + 8, 12);    /* (12 letters fill it: no 0 after) */
        nm[12] = 0;
        scr_text(5 + i * 2, 2, nm);
        numstr(b, rooms[i][20]);
        scr_text(5 + i * 2, 16, b);
        scr_text(5 + i * 2, 18, "/10");
        scr_text(5 + i * 2, 24, rooms[i][22] ? "ROUND" : "WAITING");
        if (rooms[i][22]) {
            numstr(b, rooms[i][23]);
            scr_text(5 + i * 2, 30, b);
        }
    }
#ifdef __NABU__
    /* a REFRESH line under the rooms (the server sends the list only when
       asked), and ESC back to the name */
    scr_text(5 + n * 2, 2, "REFRESH");
    centre(21, "UP/DOWN, FIRE TO PICK");
    centre(23, "ESC: CHANGE NAME");
    ++n;                                /* (the line is one more to choose) */
#else
    centre(22, "UP/DOWN, FIRE TO JOIN");
#endif
    scr_show();
    for (;;) {
        for (i = 0; i < n; ++i)
            scr_row(5 + i * 2, i == sel ? PAL_HILITE : PAL_TEXT);
        tick();
#ifdef __NABU__
        if (ev_key == KEY_ESC) {
            snd_cue(UI_TICK, 0);
            return 2;
        }
        if ((ev_btn || ev_key == KEY_RETURN) && sel == n - 1) {
            snd_cue(UI_TICK, 0);
            message("REFRESHING", srv_host, 1);
            n = net_rooms();
            goto again;
        }
        if (ev_key == KEY_RETURN)
            ev_btn = 1;
#endif
        if (pressed(IN_UP) && sel) {
            --sel;
            snd_cue(UI_TICK, 0);
        }
        if (pressed(IN_DOWN) && sel + 1 < n) {
            ++sel;
            snd_cue(UI_TICK, 0);
        }
        tick_dir();
        if (ev_btn) {
            memset(srv_table, 0, sizeof(srv_table));
            memcpy(srv_table, rooms[sel], ROOM_LEN);
            snd_cue(UI_GO, 0);
            return 1;
        }
    }
}
#endif
