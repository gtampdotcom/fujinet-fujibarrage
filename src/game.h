/*
 * game.h -- FujiBarrage's client, platform neutral: the STATE the server
 * pushes (proto.h's layout), the documents it sends (net.c), the tanks as
 * drawn, the screens.
 */
#ifndef GAME_H
#define GAME_H

#include <stdint.h>
#include "proto.h"
#include "field.h"

#define NONE 0xFF
#ifdef TEST_SCENES
#define CAT_MAX 64              /* the scenes have no catalog: room for the fixture */
#else
#define CAT_MAX 1664
#endif

/* the last whole STATE */
extern uint8_t st[STATE_SIZE];
/* (by table, not s * SEAT_SIZE: cc65 multiplies in 16 bits, slowly) */
extern const uint8_t seat_off[SEATS];
#ifdef __CC65__
#define PL(s, f)   st[OFF_SEATS + seat_off[s] + (f)]
#else
/* (CMOC: OFF_SEATS + seat_off[s] would be a byte: seats 7-9 wrapped) */
#define SEAT_AT(s) (OFF_SEATS + (uint16_t)seat_off[s])
#define PL(s, f)   st[SEAT_AT(s) + (f)]
#endif
/* little-endian fields: cc65 reads them in place; CMOC (the CoCo: big-endian,
 * and byte op byte is a byte there) builds them a byte at a time */
#ifdef __CC65__
#define PL16(s, f) (*(uint16_t *)&st[OFF_SEATS + seat_off[s] + (f)])
#define PL16_SET(s, f, v) (PL16(s, f) = (v))
#define LE16(p)    ((p)[0] | (p)[1] << 8)
#define LE16A(a, i) ((a)[i] | (a)[(i) + 1] << 8)    /* (array a at index i) */
#define LE32(p)    (*(uint32_t *)(p))
#define SEATKIND(s, k) ((s) | (k) << 8)
#define I16(x)     (x)          /* (cc65 promotes; CMOC needs it said) */
#define U16(x)     (x)
#else
#define LE16(p)    ((uint16_t)(p)[0] | (uint16_t)(p)[1] << 8)
#define LE16A(a, i) ((uint16_t)(a)[i] | (uint16_t)(a)[(i) + 1] << 8)
#define LE32(p)    ((uint32_t)LE16(p) | (uint32_t)LE16((p) + 2) << 16)
#define PL16(s, f) LE16(&st[SEAT_AT(s) + (f)])
#define PL16_SET(s, f, v) (st[SEAT_AT(s) + (f)] = (uint8_t)(v), \
                           st[SEAT_AT(s) + (f) + 1] = (uint8_t)((uint16_t)(v) >> 8))
#define SEATKIND(s, k) ((uint16_t)(s) | (uint16_t)(k) << 8)
#define I16(x)     ((int16_t)(x))  /* a byte in signed 16-bit arithmetic (CMOC keeps byte op byte a byte) */
#define U16(x)     ((uint16_t)(x))  /* the same, unsigned (energy * 10u was a byte: power stopped at 232) */
#endif
#ifdef __CC65__
#define NAME(s)    ((const char *)st + OFF_SEATS + seat_off[s] + P_NAME)
#else
#define NAME(s)    ((const char *)st + SEAT_AT(s) + P_NAME)
#endif
#define KIND(s)    PL(s, P_KIND)
#define ALIVE(s)   (PL(s, P_FLAGS) & PF_ALIVE)
#define INV(i)     st[OFF_INV + (i)]
#define SET(k)     st[OFF_SETTINGS + (k)]

/* a tank as drawn */
typedef struct {
    uint8_t on;
    int16_t x;
    uint8_t y;
    uint8_t angle;
} tank_t;
extern tank_t tk[SEATS];

extern char my_name[NAME_LEN + 1];
extern char srv_host[61];
extern uint16_t srv_port;
extern char srv_table[ROOM_LEN + 1];
extern uint8_t my_seat;             /* NONE: watching */

/* net.c */
enum { NET_NONE, NET_STATE, NET_ERROR, NET_LOST, NET_SCRIPT, NET_HELD };
#define MAX_ROOMS 8
extern uint8_t rooms[MAX_ROOMS][ROOM_REC];
extern uint8_t net_err, net_heard;
extern uint8_t net_tv;              /* the field's terrain version (0xFF: none) */
extern uint8_t net_terrain;         /* columns came since play looked */
#ifdef CAT_ROM
#include "catalog.h"                /* CAT_LEN, CAT_S1, CAT_S2 */
extern const uint8_t catalog[];      /* in ROM (gen/<platform>/catalog.s), not sent */
extern uint8_t cat_stale;           /* the server's isn't it: UPDATE FUJIBARRAGE */
#else
extern uint8_t catalog[CAT_MAX];
#endif
extern uint16_t cat_len;
extern uint8_t script[SCRIPT_BUF];
extern uint16_t seg_len;
extern uint8_t seg_ready, seg_sid, seg_no, seg_flags;
uint8_t net_open(void);
void net_hello(void);
uint8_t net_poll(void);
uint8_t net_rooms(void);            /* count, 0: none or no answer */
uint8_t net_act(uint8_t act, const uint8_t *args, uint8_t n);
void net_hold(void);                /* a segment with S_HOLD is whole: go quiet */
void net_done(void);                /* the segment is played: say so (wakes a held link) */
void net_unhold(void);              /* a hold we asked for is over */
void net_want(uint8_t reason, uint8_t secs);
void net_leave(void);
void net_close(void);

/* cat.c: the CATALOG */
extern uint8_t cat_ok;
uint8_t cat_check(void);            /* parse it once whole; 1 when usable */
const uint8_t *cat_item(uint8_t i); /* kind, arms, bundle, price24, name (at +6) */
const uint8_t *cat_setting(uint8_t k);
const uint8_t *cat_tier(uint8_t t);
const uint8_t *cat_page(uint8_t p);
void cat_name(const uint8_t *lstr, char *out, uint8_t max);  /* length-prefixed to C */
void cat_value(uint8_t k, uint8_t v, char *out);     /* setting k at value v, as shown */
uint8_t cat_count(uint8_t k);                        /* its values */
void num32(char *out, uint32_t v);

/* play.c: the field */
void play_enter(void);
void play_state(void);              /* a new STATE came */
void play_frame(void);
uint8_t play_esc(void);             /* ESC on the field: 1 if it closed something */
void play_script(void);             /* a segment is ready: play it */
void play_segment(void);            /* (the same, no link: test scenes) */
uint8_t play_skip(void);            /* our shot left behind: its script ends (1) */
uint16_t entry_len(const uint8_t *e);

/* menus.c */
void title(void);
void name_entry(void);
uint8_t room_list(void);            /* 1: srv_table picked (the NABU: 2, ESC: the name again) */

/* room.c: the waiting room, the shop, the results */
void wait_enter(void);
void wait_state(void);
void wait_frame(void);
void shop_enter(void);
void shop_state(void);
void shop_frame(void);
void results_enter(uint8_t final);
void results_frame(void);

/* screens */
void tick(void);                    /* a frame: wait, input */
uint8_t pressed(uint8_t bit);       /* the stick pushed this frame */
void message(const char *a, const char *b, uint8_t frames);
void numstr(char *out, uint16_t v);

/* appkey.c */
void appkey_load(void);
void appkey_save_name(void);
void appkey_save_room(void);
void appkey_clear_room(void);

#endif
