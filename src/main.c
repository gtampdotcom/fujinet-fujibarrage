/*
 * main.c -- FujiBarrage: an artillery game for up to ten on FujiNet.
 *
 * Two programs on the disk, from the same sources:
 *
 *   BARRAGE.COM (it boots)  the game. The appkeys (the lobby's, or the
 *       menu's) say who we are and which room; without them it loads
 *       MENU.COM. In the room the server's STATE says which screen to
 *       show: the waiting room, the shop, the field, the results. Leaving
 *       the room clears it from the appkeys and boots the disk again.
 *   MENU.COM (-DMENU)       the title, the name, the room list: it writes
 *       the choice to the appkeys and boots the disk again.
 *
 * Or one program (-DONE_PROGRAM: the NABU, which has room for both and no
 * disk to boot again): the menu, then the room, then the menu.
 */
#include <string.h>
#include "game.h"
#include "scr.h"
#include "input.h"
#include "plat.h"
#include "sound.h"
#include "field.h"

#define JOIN_WAIT 900           /* frames for the first STATE before giving up */

enum { S_NONE, S_WAIT, S_SHOP, S_FIELD, S_RESULTS, S_OVER };

#if !defined(MENU) || defined(ONE_PROGRAM)
static uint8_t screen_for(void)
{
    switch (st[OFF_PHASE]) {
    case PH_SHOP:
        return S_SHOP;
    case PH_DEFENSE:
    case PH_AIM:
    case PH_SHOT:
        return S_FIELD;
    case PH_ROUNDEND:
        return S_RESULTS;
    case PH_GAMEOVER:                   /* (its own: it follows a round's end) */
        return S_OVER;
    }
    return S_WAIT;
}

/* Play in srv_table. 1: come back to it (the link dropped); 0: we left, or
 * it would not have us. */
static uint8_t play_room(void)
{
    uint8_t r, shown = S_NONE, shown_seq = 0, want;
    uint16_t t = 0;

    message("JOINING", srv_table, 1);
    if (!net_open()) {
        message("NO ANSWER FROM", srv_host, 0);
        return 0;
    }
    net_hello();
    for (;;) {
        tick();
        r = net_poll();
        if (r == NET_ERROR) {
            net_close();
            message("THE SERVER SAID NO", net_err == ERR_VERSION ? "UPDATE FUJIBARRAGE" :
                    net_err == ERR_CAPS ? "THIS MACHINE ISN'T SERVED" : "NO SUCH ROOM", 0);
            return 0;
        }
        if (r == NET_LOST) {
            message("CONNECTION LOST", "TRYING AGAIN", 120);
            return 1;
        }
        if (ev_key == KEY_ESC && !(shown == S_FIELD && play_esc())) {
            net_leave();
            net_close();
            return 0;
        }
        if (!net_heard) {
            if (++t > JOIN_WAIT) {
                net_close();
                message("NO ANSWER FROM", srv_host, 0);
                return 0;
            }
            continue;
        }
        if (r == NET_STATE) {
            my_seat = st[OFF_MY_SEAT];
            cat_check();
#ifdef CAT_ROM
            if (cat_stale) {            /* our catalog in ROM isn't the server's */
                net_leave();
                net_close();
                message("THE SERVER SAID NO", "UPDATE FUJIBARRAGE", 0);
                return 0;
            }
#endif
        }
        want = screen_for();
        if (r == NET_SCRIPT || want != shown || (want == S_FIELD && st[OFF_SEQ] != shown_seq)) {
            if (want != shown || (want == S_FIELD && st[OFF_SEQ] != shown_seq) ||
                (r == NET_SCRIPT && shown != S_FIELD)) {
                if (r == NET_SCRIPT)
                    want = S_FIELD;
                shown = want;
                shown_seq = st[OFF_SEQ];
                switch (want) {
                case S_WAIT:
                    wait_enter();
                    break;
                case S_SHOP:
                    shop_enter();
                    break;
                case S_FIELD:
                    play_enter();
                    break;
                default:
                    results_enter(want == S_OVER);
                }
            }
            if (r == NET_SCRIPT) {
                play_script();
                continue;
            }
        } else if (r == NET_STATE) {
            if (shown == S_WAIT)
                wait_state();
            else if (shown == S_SHOP)
                shop_state();
            else if (shown == S_FIELD)
                play_state();
        }
        switch (shown) {
        case S_WAIT:
            wait_frame();
            break;
        case S_SHOP:
            shop_frame();
            break;
        case S_FIELD:
            play_frame();
            break;
        default:
            results_frame();
        }
    }
}

void test_check(void);
uint8_t xload(void);
#endif

#ifdef ONE_PROGRAM

int main(void)
{
    plat_init();
    test_check();
    appkey_load();
    title();
    if (!my_name[0]) {
        name_entry();
        appkey_save_name();
    }
    for (;;) {
        uint8_t r = room_list();
        if (r == 2) {                   /* ESC (the NABU): the name again, its ESC the title */
            name_entry();
            appkey_save_name();
        } else if (r) {
            net_close();
            appkey_save_room();
            field_init();
            while (play_room())         /* (the link dropped: again) */
                ;
            message("BACK TO THE ROOMS", "", 1);
            appkey_clear_room();
        }
    }
}

#elif !defined(MENU)

int main(void)
{
    plat_init();
    test_check();
    appkey_load();
    if (!my_name[0] || !srv_table[0]) {
        xload();                        /* the menu: it doesn't come back */
        message("MENU.COM ISN'T ON THIS DISK", "", 0);
        for (;;)
            ;
    }
    field_init();                       /* (the boot code at $A400 goes) */
    for (;;)
        if (!play_room()) {             /* left, or not let in */
            message("BACK TO THE ROOMS", "", 1);
            appkey_clear_room();
            plat_reboot();
        }
}

#else

int main(void)
{
    plat_init();
    appkey_load();
    title();
    if (!my_name[0]) {
        name_entry();
        appkey_save_name();
    }
    for (;;)
        if (room_list()) {
            net_close();
            message("JOINING", srv_table, 1);
            appkey_save_room();
            plat_reboot();              /* the game, with the room set */
        }
}
#endif
