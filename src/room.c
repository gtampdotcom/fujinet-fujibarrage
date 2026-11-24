/*
 * room.c -- the waiting room (who's here, the host starts), the shop and
 * the results, on text screens.
 */
#include <string.h>
#include "game.h"
#include "layout.h"
#include "scr.h"
#include "input.h"
#include "plat.h"
#include "sound.h"

static char b[20];
static char ln[41];
static uint8_t rep_prev;
static uint16_t rep_next;               /* the frame a held stick moves again */

/* the stick's moves: a press, then every 4 frames once held 16 */
static uint8_t rep(void)
{
    uint8_t d = inp_dir, mv = d & ~rep_prev;
    if (d && (int16_t)(frame_count - rep_next) >= 0 && !mv)
        mv = d;
    if (mv)
        rep_next = frame_count + (d & ~rep_prev ? 16 : 4);
    rep_prev = d;
    return mv;
}

static void at(uint8_t col, const char *t)
{
    while (*t && col < SCR_COLS)
        ln[col++] = *t++;
}

static void seat_line(uint8_t row, uint8_t s)
{
    uint8_t k = KIND(s);
    scr_clear_row(row);
    if (k == KIND_EMPTY) {
        scr_row(row, PAL_DIM);
        scr_text(row, SEAT_NAME_C, "- OPEN -");
        return;
    }
    scr_row(row, PAL_SEAT + s);
    memset(b, 0, sizeof(b));
    memcpy(b, NAME(s), NAME_LEN);
    scr_text(row, SEAT_NAME_C, b);
    if (k == KIND_BOT) {
        cat_name(cat_tier(PL(s, P_TIER)), b, SEAT_TIER_N);
        scr_text(row, SEAT_KIND_C, "BOT");
        scr_text(row, SEAT_TIER_C, b);
    } else
        scr_text(row, SEAT_KIND_C, PL(s, P_FLAGS) & PF_CONN ? "" : "(LINK DOWN)");
    if (s == st[OFF_HOST])
        scr_text(row, SEAT_HOST_C, "HOST");
    numstr(b, PL(s, P_WINS));
    if (st[OFF_PHASE] != PH_WAIT) {
        scr_text(row, SEAT_HOST_C, "WINS");
        scr_text(row, SEAT_WN_C, b);
    }
}

/* ---- the waiting room: the seats, or the settings (S): the host changes
 * them, everyone can look ---- */

static uint8_t set_on, set_page, set_sel, set_n;
static uint8_t set_ks[16];               /* the settings on this page */

static uint8_t hosting(void)
{
    return my_seat == st[OFF_HOST];
}

static void set_line(uint8_t i)
{
    uint8_t k = set_ks[i];
    memset(ln, ' ', SCR_COLS);
    cat_name(cat_setting(k) + 2, b, SET_NAME_N);
    at(SET_NAME_C, b);
    cat_value(k, SET(k), b);
    at(SET_VAL_C, b);
    scr_row(3 + i, hosting() && i == set_sel ? PAL_HILITE : PAL_TEXT);
    scr_text(3 + i, 0, ln);
}

static void wait_hint(void)
{
    scr_clear_row(23);
    scr_text(23, 1, set_on ? (hosting() ? TXT_W_HOSTSET : TXT_W_SET)
                           : !hosting() ? TXT_W_WAIT
                           : st[OFF_ROOM_FLAGS] & ROOM_PEOPLE ? TXT_W_PEOPLE
                           : TXT_W_BOTS);
}

static void wait_draw(void)
{
    uint8_t r, k;
    for (r = 1; r < 23; ++r) {
        scr_clear_row(r);
        scr_row(r, PAL_TEXT);
    }
    if (set_on) {
        set_n = 0;
        if (cat_ok)
            for (k = 0; k < N_SETTINGS && set_n < sizeof(set_ks); ++k)
                if (cat_setting(k)[0] == set_page)
                    set_ks[set_n++] = k;
        if (set_sel >= set_n)
            set_sel = 0;
        scr_row(1, PAL_HEAD);
        scr_text(1, 1, "SETTINGS:");
        cat_name(cat_page(set_page), b, 16);
        scr_text(1, 11, b);
    }
    wait_hint();
    wait_state();
}

void wait_enter(void)
{
    scr_begin();
    scr_row(0, PAL_HEAD);
    scr_text(0, 1, "WAITING ROOM:");
    scr_text(0, 15, srv_table);
    set_on = 0;
    wait_draw();
    scr_show();
}

void wait_state(void)
{
    uint8_t i;
    if (set_on)
        for (i = 0; i < set_n; ++i)
            set_line(i);
    else
        for (i = 0; i < SEATS; ++i)
            seat_line(2 + i * 2, i);
}

void wait_frame(void)
{
    uint8_t mv = rep(), old = set_sel, a[2], n;
    if (ev_key == 'S') {
        set_on ^= 1;
        snd_cue(UI_TICK, 0);
        wait_draw();
        return;
    }
    if (set_on && set_n) {
        if (ev_key == 9) {                  /* TAB: the next page */
            set_page = set_page < 2 ? set_page + 1 : 0;
            set_sel = 0;
            wait_draw();
            return;
        }
        if ((mv & IN_UP) && set_sel)
            --set_sel;
        if ((mv & IN_DOWN) && set_sel + 1 < set_n)
            ++set_sel;
        if (set_sel != old) {
            snd_cue(UI_TICK, 0);
            set_line(old);
            set_line(set_sel);
        }
        if (hosting() && (mv & (IN_LEFT | IN_RIGHT))) {
            a[0] = set_ks[set_sel];
            a[1] = SET(a[0]);
            n = cat_count(a[0]);
            if (mv & IN_LEFT)
                a[1] = a[1] ? a[1] - 1 : n - 1;
            else
                a[1] = a[1] + 1 < n ? a[1] + 1 : 0;
            net_act(ACT_SET, a, 2);
            snd_cue(UI_TICK, 0);
        }
    }
    if (ev_btn && hosting()) {
        net_act(ACT_START, 0, 0);
        snd_cue(UI_GO, 0);
    }
}

/* ---- the shop: what the arms level allows, bought and sold one at a time
 * (the STATE's cash and stock answer each) ---- */

#define SHOP_TOP  2
#define SHOP_ROWS 19

#ifdef __CC65__
#pragma bss-name (push, "BSS2")
#endif
static uint8_t shop_ids[N_ITEMS], shop_own[N_ITEMS];    /* shown, and the stock shown */
#ifdef __CC65__
#pragma bss-name (pop)
#endif
static uint8_t shop_n, shop_sel, shop_top;

static uint32_t cash(void)
{
    return LE32(st + OFF_CASH);
}

static uint16_t price(uint8_t it)
{
    const uint8_t *r = cat_item(it);
    return LE16(r + 3);
}

/* list entry i on its row (if it is shown), in one go: no flicker */
static void shop_line(uint8_t i)
{
    uint8_t it;
    const uint8_t *r;
    if (i < shop_top || i >= shop_top + SHOP_ROWS)
        return;
    memset(ln, ' ', SCR_COLS);
    if (i < shop_n) {
        it = shop_ids[i];
        r = cat_item(it);
        cat_name(r + 6, b, SHOP_NAME_N);
        at(1, b);
        numstr(b, price(it));
        at(SHOP_PRICE_C, b);
        b[0] = 'X';
        numstr(b + 1, r[2]);
        at(SHOP_BUNDLE_C, b);
        if ((shop_own[it] = INV(it)) != 0) {
            numstr(b, INV(it));
            at(SHOP_OWN_C, b);
        }
    }
    scr_row(SHOP_TOP + i - shop_top, i == shop_sel ? PAL_HILITE : PAL_TEXT);
    scr_text(SHOP_TOP + i - shop_top, 0, ln);
}

/* the cash, the clock; a row whose stock changed */
void shop_state(void)
{
    uint8_t i;
    memset(ln, ' ', SCR_COLS);
    at(1, SHOP_ROUND_L);
    numstr(b, st[OFF_ROUND] + 1);
    at(SHOP_ROUND_C, b);
    at(SHOP_CASH_L, "CASH");
    num32(b, cash());
    at(SHOP_CASH_C, b);
    scr_text(0, 0, ln);
    for (i = shop_top; i < shop_top + SHOP_ROWS && i < shop_n; ++i)
        if (shop_own[shop_ids[i]] != INV(shop_ids[i]))
            shop_line(i);
    memset(ln, ' ', SCR_COLS);
    if (my_seat < SEATS && (PL(my_seat, P_FLAGS) & PF_DONE))
        at(1, "DONE: WAITING FOR THE OTHERS");
    numstr(b, st[OFF_TIMER]);
    at(SHOP_TIMER_C, b);
    scr_text(23, 0, ln);
}

#ifdef __NABU__
/* the rows still to draw again after a scroll (0xFF: none): a few a pass, so
   the loop (and the link) never stops for the whole list (~29 frames) */
static uint8_t shop_redo = 0xFF;
#define REDO_ROWS 3
#endif

static void shop_all(void)
{
    uint8_t i;
#ifdef __NABU__
    shop_redo = 0xFF;                   /* (all of them now) */
#endif
    for (i = shop_top; i < shop_top + SHOP_ROWS; ++i)
        shop_line(i);
}

void shop_enter(void)
{
    uint8_t i;
    scr_begin();
    scr_row(0, PAL_HEAD);
    scr_text(1, 1, TXT_SHOP_HEAD);
    scr_text(22, 1, TXT_SHOP_HINT);
    shop_n = shop_sel = shop_top = 0;
    if (cat_ok)
        for (i = 0; i < N_ITEMS; ++i)
            if (i != I_MINI_MISSILE && cat_item(i)[1] <= SET(SET_ARMS))
                shop_ids[shop_n++] = i;
    shop_all();
    shop_state();
    scr_show();
    snd_tune(t_shop1, t_shop2);
}

void shop_frame(void)
{
    uint8_t fresh = inp_dir & ~rep_prev, mv, it, args[2], old = shop_sel;
#ifdef __NABU__
    if (shop_redo != 0xFF) {
        for (mv = 0; mv < REDO_ROWS && shop_redo < shop_top + SHOP_ROWS; ++mv, ++shop_redo)
            if (shop_redo != shop_sel)  /* (drawn at once) */
                shop_line(shop_redo);
        if (shop_redo >= shop_top + SHOP_ROWS)
            shop_redo = 0xFF;
    }
#endif
    if (my_seat >= SEATS || (PL(my_seat, P_FLAGS) & PF_DONE) || !shop_n)
        return;
    mv = rep();
    if ((mv & IN_UP) && shop_sel)
        --shop_sel;
    if ((mv & IN_DOWN) && shop_sel + 1 < shop_n)
        ++shop_sel;
    if (shop_sel != old) {
        snd_cue(UI_TICK, 0);
        if (shop_sel < shop_top || shop_sel >= shop_top + SHOP_ROWS) {
            /* a row on: the text moves, the new row is drawn */
            it = shop_sel < shop_top;
            shop_top = it ? shop_sel : shop_sel - SHOP_ROWS + 1;
#ifdef __NABU__
            /* every row drawn again, a few a pass (shop_redo): only writes (a
               scroll reads the VRAM back, ~9K, and the PICO9918 v1.2 slips
               bytes reading) */
            shop_line(shop_sel);        /* the one we're on now, the rest after */
            shop_redo = shop_top;
#else
            scr_scroll(SHOP_TOP, SHOP_ROWS, !it);
            shop_line(old);
            shop_line(shop_sel);
#endif
        } else {
            shop_line(old);
            shop_line(shop_sel);
        }
    }
    args[0] = it = shop_ids[shop_sel];
    args[1] = 1;
    if (ev_btn) {
        if (cash() < price(it)) {
            snd_cue(UI_ERROR, 0);
            scr_text(23, 1, "NOT ENOUGH CASH");
        } else {
            net_act(ACT_BUY, args, 2);
            snd_cue(UI_SELECT, 0);
        }
    }
    if ((fresh & IN_LEFT) && INV(it)) {   /* (a press each: no selling by holding) */
        net_act(ACT_SELL, args, 2);
        snd_cue(UI_TICK, 0);
    }
    if (ev_key == KEY_RETURN) {
        net_act(ACT_DONE, 0, 0);
        snd_cue(UI_GO, 0);
    }
}

void results_enter(uint8_t final)
{
    uint8_t s, r = st[OFF_RESULT];
    if (final)
        snd_tune(t_over1, t_over2);
    else
        snd_tune(t_win1, t_win2);
    scr_begin();
    scr_row(0, PAL_HEAD);
    scr_text(0, 1, final ? "GAME OVER" : "ROUND OVER");
    if (r < SEATS) {
        memset(b, 0, sizeof(b));
        memcpy(b, NAME(r), NAME_LEN);
        scr_row(2, PAL_SEAT + r);
        scr_text(2, 2, b);
        scr_text(2, 12, final ? "WINS THE GAME!" : "WINS THE ROUND");
    }
    for (s = 0; s < SEATS; ++s)
        if (KIND(s) != KIND_EMPTY)
            seat_line(5 + s * 2, s);
    scr_show();
}

void results_frame(void)
{
}
