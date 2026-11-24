/*
 * appkey.c -- the NABU has no FujiNet, so no lobby appkeys (src/appkey.c on
 * the others), and the menu and the game are one program (main.c's
 * ONE_PROGRAM): the name and the room stay in these variables.
 *
 * The name is the player name set in the Internet Adapter (an adapter new
 * enough to have one: nstrans.c nst_player_name), letters and digits only,
 * else the menu asks; the rooms listed are the default server's
 * (gen/config.h, DEFAULT_SERVER "host:port": tools/nabu/build.py SERVER=,
 * default fujinet.online:9913).
 */
#include <string.h>
#include "game.h"
#include "config.h"
#include "nstrans.h"

char my_name[NAME_LEN + 1];
char srv_host[61];
uint16_t srv_port;
char srv_table[ROOM_LEN + 1];

void nst_player_name(char *out);        /* nstrans.c */

void appkey_load(void)
{
    static char a[17];
    const char *p = DEFAULT_SERVER;
    uint8_t n = 0, i, c;
    while (*p && *p != ':' && n < 60)
        srv_host[n++] = *p++;
    srv_host[n] = 0;
    srv_port = 0;
    if (*p == ':')
        while (*++p >= '0' && *p <= '9')
            srv_port = srv_port * 10 + (*p - '0');
    if (!srv_port)
        srv_port = STREAM_PORT;
    srv_table[0] = 0;
    nst_player_name(a);
    n = 0;
    for (i = 0; a[i] && n < NAME_LEN; ++i) {
        c = (uint8_t)a[i];
        if (c >= 'a' && c <= 'z')
            c -= 32;
        if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
            my_name[n++] = c;
    }
    my_name[n] = 0;
}

void appkey_save_name(void)
{
}

void appkey_save_room(void)
{
}

void appkey_clear_room(void)
{
    srv_table[0] = 0;
}
