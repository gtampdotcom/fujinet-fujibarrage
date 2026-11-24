/*
 * net.c -- the stream protocol (docs/PROTOCOL.md) over the link (nstrans.h).
 *
 * The server keeps four documents for us at our resolution: the CATALOG
 * (once), the STATE (patches to a staged copy, then a commit), the TERRAIN
 * (columns, written straight into the field) and the SCRIPT of each shot
 * (segments into script[], played by play.c). We report what we took from
 * the ring (credit) so it never sends more than the ring holds. From
 * FujiBlast's (itself from M.U.L.E.'s).
 *
 * The hold: a segment's last frame says S_HOLD and the server sends nothing
 * more; we credit what we took, stop the link (all of POKEY is the sound's
 * then), play, start the link again with a 0, and say D(sid, seg, taken),
 * again every second until something comes.
 */
#include <string.h>
#include "game.h"
#include "nstrans.h"
#include "plat.h"

#define PING_EVERY 300          /* frames between keepalives (each is answered) */
#define DEAD_AFTER 900          /* frames without a frame: the link is gone */
#define ASK_AGAIN  60           /* HELLO unanswered: again */
#define RESYNC_GAP 30           /* frames between RESYNCs */

uint8_t st[STATE_SIZE];
#ifdef __CC65__
#pragma bss-name (push, "BSS2")
#endif
static uint8_t stage[STATE_SIZE];
#ifdef __CC65__
#pragma bss-name (pop)
#endif
#if defined(MENU) || defined(ONE_PROGRAM)
uint8_t rooms[MAX_ROOMS][ROOM_REC];
#endif
uint8_t net_err, net_heard, net_tv = 0xFF, net_terrain;
#ifndef CAT_ROM
uint8_t catalog[CAT_MAX];
#endif
uint16_t cat_len;
uint8_t script[SCRIPT_BUF];
uint16_t seg_len;
uint8_t seg_ready, seg_sid, seg_no, seg_flags;

const uint8_t seat_off[SEATS] = { 0, 25, 50, 75, 100, 125, 150, 175, 200, 225 };

#ifdef TEST_SCENES
/* the offline scenes (test.c) have no link: room for their fixture */
uint8_t net_open(void) { return 0; }
void net_hello(void) {}
uint8_t net_poll(void) { return 0; }
void net_hold(void) {}
void net_done(void) {}
void net_unhold(void) {}
void net_want(uint8_t reason, uint8_t secs) { (void)reason; (void)secs; }
uint8_t net_act(uint8_t act, const uint8_t *args, uint8_t n) { (void)act; (void)args; (void)n; return 1; }
void net_leave(void) {}
void net_close(void) {}
#else
static uint8_t link, joined, seq, credited, resync_hold, resync_owed, held, d_owed, d_sid, d_seg;
#if defined(MENU) || defined(ONE_PROGRAM)
static uint8_t room_n, room_have;
#endif
static uint16_t quiet, q_ping;
static uint8_t q_ask, q_d;

static void send_d(void);
#ifdef __CC65__
#pragma bss-name (push, "PMGFREE")
#endif
static uint8_t raw[40];
#ifdef __CC65__
#pragma bss-name (pop)
#endif

/* a + b, mod 255, with no division (256 is 1, mod 255) */
static uint8_t add255(uint8_t a, uint8_t b)
{
    a += b;
    if (a < b)
        ++a;
    return a == 255 ? 0 : a;
}

/* A frame: COBS of type, payload, Fletcher-16; then 0. */
static void send(uint8_t type, const uint8_t *p, uint8_t n)
{
    uint8_t s1 = 0, s2 = 0, i, from = 0;
    raw[0] = type;
    memcpy(raw + 1, p, n);
    ++n;
    for (i = 0; i < n; ++i) {
        s1 = add255(s1, raw[i]);
        s2 = add255(s2, s1);
    }
    raw[n++] = s1;
    raw[n++] = s2;
    for (i = 0; i <= n; ++i) {
        if (i == n || raw[i] == 0) {
            nst_put(i - from + 1);
            for (; from < i; ++from)
                nst_put(raw[from]);
            ++from;
        }
    }
    nst_put(0);
}

static void send_credit(void)
{
    credited = nst_taken;
    send(SC_CREDIT, &credited, 1);
}

static void resync(void)
{
    uint8_t r[8];
    resync_owed = 1;
    if (resync_hold)
        return;
    r[0] = nst_taken;
    r[1] = net_tv;
    r[2] = seg_sid;
    r[3] = seg_no;
    r[4] = 0;
    r[5] = 0;
    r[6] = (uint8_t)cat_len;
    r[7] = cat_len >> 8;
    credited = nst_taken;
    send(SC_RESYNC, r, 8);
    seg_len = 0;
    resync_hold = RESYNC_GAP;
    resync_owed = 0;
}

uint8_t net_open(void)
{
    if (link)
        return 1;
    joined = 0;
    credited = 0;
    quiet = q_ping = q_ask = 0;
    link = nst_open(srv_host, srv_port);
    return link;
}

static void hello_frame(void)
{
    static uint8_t h[HELLO_LEN];
    memset(h, 0, sizeof(h));
    h[0] = PROTO_VERSION;
    strncpy((char *)h + 2, srv_table, ROOM_LEN);
    strncpy((char *)h + 10, my_name, NAME_LEN);
    h[18] = (uint8_t)FIELD_W;
    h[19] = FIELD_W >> 8;
    h[20] = FIELD_H;
    h[21] = PAR;
    h[22] = plat_hz();
    h[23] = TANK_W;
    h[24] = TANK_H;
    h[25] = (uint8_t)SCRIPT_BUF;
    h[26] = SCRIPT_BUF >> 8;
    h[27] = BANDS;
    h[28] = PLAT_CAPS;
    h[29] = PLAT_ID;
    send(SC_HELLO, h, sizeof(h));
}

void net_hello(void)
{
    joined = 1;
    net_heard = 0;
    net_err = 0;
    quiet = q_ping = q_ask = 0;
    resync_owed = 0;
#ifdef CAT_ROM
    cat_len = CAT_LEN;                  /* (a RESYNC says we have it all) */
#else
    cat_len = 0;
#endif
    cat_ok = 0;
    net_tv = 0xFF;
    seg_len = seg_ready = 0;
    seg_sid = 0;
    memset(stage, 0, sizeof(stage));
    hello_frame();
}

static void drop(void)
{
    nst_close();
    link = joined = held = 0;
}

/* one frame, in nst_buf (n bytes: type, payload) */
static uint8_t frame(uint8_t n)
{
    uint8_t *p = nst_buf + 1;
#if !defined(MENU) || defined(ONE_PROGRAM)
    uint16_t off, x, i;
    uint8_t len;
#endif
    switch (nst_buf[0]) {
#if !defined(MENU) || defined(ONE_PROGRAM)
    case CS_PATCH:
        for (i = 1; i + 3 <= n; i += len) {
            off = LE16A(nst_buf, i);
            len = nst_buf[i + 2];
            i += 3;
            if (i + len > n || off + len > STATE_SIZE)
                break;
            memcpy(stage + off, nst_buf + i, len);
        }
        break;
    case CS_COMMIT:
        if (joined) {
            memcpy(st, stage, STATE_SIZE);
            net_heard = 1;
            return NET_STATE;
        }
        break;
#endif
#if defined(MENU) || defined(ONE_PROGRAM)
    case CS_ROOM:
        if (n >= 3 + ROOM_REC && p[0] < MAX_ROOMS) {
            memcpy(rooms[p[0]], p + 2, ROOM_REC);
            room_have |= 1 << p[0];
        }
        if (n >= 3)
            room_n = p[1] > MAX_ROOMS ? MAX_ROOMS : p[1];
        break;
#endif
    case CS_ERROR:
        net_err = p[0];
        return NET_ERROR;
#if !defined(MENU) || defined(ONE_PROGRAM)
    case CS_CATALOG:
#ifndef CAT_ROM                         /* (ours is in ROM: cat_check compares) */
        off = LE16(p);
        if (off == cat_len && cat_len + n - 3 <= CAT_MAX) {
            memcpy(catalog + cat_len, p + 2, n - 3);
            cat_len += n - 3;
        }
#endif
        break;
    case CS_TERRAIN:
        /* terrain while a script plays: the server left our shot behind
           (play_skip ends it). Its diff runs from the shot's start and our
           field is part-way through it: ours no longer (as the INTV's). */
        if (play_skip())
            net_tv = 0xFF;
        if (p[0] != 0xFF && p[0] != net_tv) {
            net_tv = 0xFF;              /* not what we have: all of it again */
            resync();
            break;
        }
        if (p[0] == 0xFF) {
            net_tv = 0xFE;              /* being built */
            field_loading();            /* (over a text screen: blank it) */
        }
        x = LE16(p + 3);
#ifdef FIELD_COLUMNS
        {   /* the frame's columns at once: a byte's columns written together */
            uint16_t x0 = x;
            for (i = 6; i < n && x < FIELD_W; ++x)
                i += entry_len(nst_buf + i);
            field_columns(x0, nst_buf + 6, x - x0);
        }
#else
        for (i = 6; i < n && x < FIELD_W; ++x) {
            field_column(x, nst_buf + i);
            i += entry_len(nst_buf + i);
        }
#endif
        if (p[2] & G_LAST)
            net_tv = p[1];
        net_terrain = 1;
        break;
    case CS_SCRIPT:
        off = LE16(p + 3);
        if (off == 0) {
            seg_len = 0;
            seg_sid = p[0];
            seg_no = p[1];
            seg_ready = 0;
        }
        if (p[0] != seg_sid || p[1] != seg_no || off != seg_len || seg_len + n - 6 > SCRIPT_BUF) {
            resync();                   /* a frame of it missing */
            break;
        }
        memcpy(script + seg_len, p + 5, n - 6);
        seg_len += n - 6;
        if (p[2] & S_LAST_FRAME) {
            seg_ready = 1;
            seg_flags = p[2];
            return NET_SCRIPT;
        }
        break;
    case CS_HOLD:
        return NET_HELD;
#endif
    }
    return NET_NONE;
}

uint8_t net_poll(void)
{
    uint8_t n, r = NET_NONE, f;
    if (!link)
        return NET_LOST;
    if (held)
        return NET_NONE;                /* quiet until net_done */
    if (nst_lost()) {
        drop();
        return NET_LOST;
    }
    if (resync_hold)
        --resync_hold;
    else if (resync_owed)
        resync();
    while ((n = nst_frame()) != 0) {
        quiet = q_ping = q_ask = 0;
        d_owed = 0;
        if (n == 255) {
            net_tv = 0xFF;
            resync();
            continue;
        }
        f = frame(n);
        if (f == NET_STATE)
            r = NET_STATE;
        else if (f == NET_ERROR || f == NET_SCRIPT || f == NET_HELD) {
            r = f;
            break;                      /* a script or a hold: nothing comes after it */
        }
    }
    if ((uint8_t)(nst_taken - credited) >= 48)
        send_credit();
    if (nst_garbled()) {
        net_tv = 0xFF;
        resync();
    }
    ++quiet;
    if (++q_ping == PING_EVERY) {
        q_ping = 0;
        send_credit();
        send(SC_PING, 0, 0);
    }
    if (++q_ask == ASK_AGAIN) {
        q_ask = 0;
        if (joined && !net_heard)
            hello_frame();
    }
    if (d_owed && ++q_d == ASK_AGAIN) { /* our D may have been lost */
        q_d = 0;
        send_d();
    }
    if (quiet > DEAD_AFTER) {
        drop();
        return NET_LOST;
    }
    return r;
}

/* the link quiet (the server sends nothing until our D) */
void net_hold(void)
{
    send_credit();
    nst_hold();
    held = 1;
}

static void send_d(void)
{
    uint8_t d[3];
    d[0] = d_sid;
    d[1] = d_seg;
    d[2] = nst_taken;
    credited = nst_taken;
    send(SC_DONE, d, 3);
    d_owed = 1;
    q_d = 0;
    quiet = 0;
}

static void wake(void)
{
    if (held) {
        nst_wake();
        held = 0;
    }
}

/* the segment is played */
void net_done(void)
{
    wake();
    d_sid = seg_sid;
    d_seg = seg_no;
    seg_ready = 0;
    send_d();
}

/* a hold we asked for (W) is over */
void net_unhold(void)
{
    wake();
    d_sid = d_seg = 0;
    send_d();
}

void net_want(uint8_t reason, uint8_t secs)
{
    uint8_t w[2];
    w[0] = reason;
    w[1] = secs;
    send(SC_WANT, w, 2);
}

#if defined(MENU) || defined(ONE_PROGRAM)
/* The room list (blocking): asked again until it comes. */
uint8_t net_rooms(void)
{
    uint16_t t;
    uint8_t want;
    if (!net_open())
        return 0;
    room_n = 0xFF;
    room_have = 0;
    for (t = 0; t < 600; ++t) {
        if (room_n == 0xFF && t % ASK_AGAIN == 0)
            send(SC_ROOMS, 0, 0);
        frame_wait();
        if (net_poll() == NET_LOST)
            return 0;
        if (room_n != 0xFF) {
            want = (uint8_t)((1 << room_n) - 1);
            if ((room_have & want) == want)
                return room_n;
        }
    }
    return 0;
}

#endif

uint8_t net_act(uint8_t act, const uint8_t *args, uint8_t n)
{
    uint8_t a[8];
    if (++seq == 0)
        seq = 1;
    a[0] = seq;
    a[1] = act;
    if (n > 6)
        n = 6;
    memcpy(a + 2, args, n);
    send(SC_ACT, a, 2 + n);
    return seq;
}

void net_leave(void)
{
    if (joined)
        net_act(ACT_LEAVE, 0, 0);
    joined = 0;
}

void net_close(void)
{
    if (link) {
        if (joined)
            send(SC_BYE, 0, 0);
        drop();
    }
}
#endif
