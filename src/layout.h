/* layout.h -- where the text screens and the HUD put things: 40 columns
 * (the Atari, the Apple II, the CoCo 3) or 32 (the CoCo 1/2, the Adam: SCR_COLS,
 * scr.h). The 40-column values are the literals the screens always had. */
#ifndef LAYOUT_H
#define LAYOUT_H

#include "scr.h"

#if SCR_COLS == 32
/* the waiting room's and the results' seat rows */
#define SEAT_NAME_C  1
#define SEAT_KIND_C  10              /* BOT, (LINK DOWN) */
#define SEAT_TIER_C  14
#define SEAT_TIER_N  9
#define SEAT_HOST_C  24              /* HOST, WINS */
#define SEAT_WN_C    29
/* the settings' rows */
#define SET_NAME_C   1
#define SET_NAME_N   16
#define SET_VAL_C    18
/* the shop */
#define SHOP_NAME_N  13
#define SHOP_PRICE_C 15
#define SHOP_BUNDLE_C 21
#define SHOP_OWN_C   26
#define SHOP_ROUND_L "SHOP ROUND"
#define SHOP_ROUND_C 12
#define SHOP_CASH_L  15
#define SHOP_CASH_C  20
#define SHOP_TIMER_C 30
#define TXT_SHOP_HEAD "ITEM          PRICE BUY  OWN"
#if defined(__ADAM__) || defined(__NABU__)  /* (the Adam, the NABU: RETURN, and a TAB key) */
#define TXT_SHOP_HINT "FIRE BUY  LEFT SELL  RETURN DONE"
#define TXT_W_HOSTSET "S SEATS TAB PAGE <> SET FIRE GO"
#define TXT_W_SET     "S SEATS  TAB PAGE"
#else
#define TXT_SHOP_HINT "FIRE BUY  LEFT SELL  ENTER DONE"
/* the waiting room's last row */
#define TXT_W_HOSTSET "S SEATS  W PAGE  <> SET FIRE GO"
#define TXT_W_SET     "S SEATS  W PAGE"
#endif
#define TXT_W_WAIT    "WAITING FOR THE HOST  S: SET"
#define TXT_W_PEOPLE  "FIRE STARTS (2+ PEOPLE) S: SET"
#define TXT_W_BOTS    "FIRE STARTS (BOTS FILL) S: SET"
/* the title */
#define TXT_TAGLINE  "ARTILLERY FOR TEN ON FUJINET"
#define TXT_GALORE   "WEAPONS, SHIELDS, BOTS GALORE."
/* the HUD: row 0 name, angle, power, energy; row 1 the weapon, the wind;
 * row 2 the round, what is happening, the timer */
#define HUD_ANG_L    9
#define HUD_ANG_C    13
#define HUD_POW_L    17
#define HUD_POW_C    21
#define HUD_E_L      26
#define HUD_E_C      28
#define TXT_ANGLE    "ANG"
#define TXT_POWER    "POW"
#define HUD_WPN_N    12
#define HUD_X_C      13
#define HUD_WIND_C   18
#define HUD_DIR_C    23
#define HUD_WV_C     24
#define HUD_TIMER_C  29
#define TXT_ROUND    "RD"
#define HUD_RD_C     3
#define TXT_OF       "/"
#define HUD_OF_C     5
#define HUD_RDS_C    6
#define HUD_MSG_C    9
#define TXT_AIM_FIRE "YOUR TURN: FIRE!"   /* (18 to the timer) */
/* the items line */
#define ITM_NAME_N   12
#define ITM_X_C      13
#define ITM_ON_C     18
#define ITM_USE_C    21
#define ITM_ON_TGT_C 22
#define ITM_FUEL_C   15
#define ITM_DONE_C   22
#else
#define SEAT_NAME_C  2
#define SEAT_KIND_C  12
#define SEAT_TIER_C  16
#define SEAT_TIER_N  12
#define SEAT_HOST_C  30
#define SEAT_WN_C    35
#define SET_NAME_C   2
#define SET_NAME_N   20
#define SET_VAL_C    26
#define SHOP_NAME_N  18
#define SHOP_PRICE_C 21
#define SHOP_BUNDLE_C 27
#define SHOP_OWN_C   34
#define SHOP_ROUND_L "SHOP   ROUND"
#define SHOP_ROUND_C 14
#define SHOP_CASH_L  24
#define SHOP_CASH_C  29
#define SHOP_TIMER_C 36
#define TXT_SHOP_HEAD "ITEM                PRICE  BUNDLE  OWN"
#ifdef _COCO_BASIC_                     /* (the CoCo 3: no TAB key, W is one) */
#define TXT_W_HOSTSET "S SEATS  W PAGE  <> CHANGE  FIRE GO"
#define TXT_W_SET     "S SEATS  W PAGE"
#elif defined(__ATARI5200__)            /* (the keypad's 0, the lower button) */
#define TXT_W_HOSTSET "0 SEATS  LOWER PAGE  <> CHANGE  FIRE GO"
#define TXT_W_SET     "0 SEATS  LOWER BUTTON PAGE"
#else
#define TXT_W_HOSTSET "S SEATS  TAB PAGE  <> CHANGE  FIRE GO"
#define TXT_W_SET     "S SEATS  TAB PAGE"
#endif
#ifdef __ATARI5200__
#define TXT_W_WAIT    "WAITING FOR THE HOST  0 SETTINGS"
#define TXT_W_PEOPLE  "FIRE STARTS (2+ PEOPLE)  0 SETTINGS"
#define TXT_W_BOTS    "FIRE STARTS (BOTS FILL)  0 SETTINGS"
#else
#define TXT_W_WAIT    "WAITING FOR THE HOST  S SETTINGS"
#define TXT_W_PEOPLE  "FIRE STARTS (2+ PEOPLE)  S SETTINGS"
#define TXT_W_BOTS    "FIRE STARTS (BOTS FILL)  S SETTINGS"
#endif
#define TXT_TAGLINE  "ARTILLERY FOR UP TO TEN, ON FUJINET"
#define TXT_GALORE   "WEAPONS, SHIELDS AND BOTS GALORE."
#define HUD_ANG_L    10
#define HUD_ANG_C    16
#define HUD_POW_L    21
#define HUD_POW_C    27
#define HUD_E_L      33
#define HUD_E_C      35
#define TXT_ANGLE    "ANGLE"
#define TXT_POWER    "POWER"
#define HUD_WPN_N    16
#define HUD_X_C      17
#define HUD_WIND_C   24
#define HUD_DIR_C    29
#define HUD_WV_C     31
#define HUD_TIMER_C  37
#define TXT_ROUND    "ROUND"
#define HUD_RD_C     6
#define TXT_OF       "OF"
#define HUD_OF_C     9
#define HUD_RDS_C    12
#define HUD_MSG_C    16
#define TXT_AIM_FIRE "YOUR TURN: AIM, FIRE"
#define ITM_NAME_N   16
#define ITM_X_C      19
#define ITM_ON_C     24
#define ITM_USE_C    29
#define ITM_ON_TGT_C 29
#define ITM_FUEL_C   15
#define ITM_DONE_C   27
#if defined(_COCO_BASIC_) || defined(__MSDOS__)  /* (the CoCo 3, the PC: the key is ENTER) */
#define TXT_SHOP_HINT "FIRE BUYS  LEFT SELLS  ENTER: DONE"
#elif defined(__ATARI5200__)
#define TXT_SHOP_HINT "FIRE BUYS  LEFT SELLS  START: DONE"
#else
#define TXT_SHOP_HINT "FIRE BUYS  LEFT SELLS  RETURN: DONE"
#endif
#endif

#if defined(_COCO_BASIC_) || defined(__MSDOS__)
#define TXT_DEFENCES "SET UP DEFENCES, ENTER: DONE"
#elif defined(__ADAM__) || defined(__NABU__)
#define TXT_DEFENCES "SET UP DEFENCES, RETURN DONE"   /* (28: the timer at 29) */
#elif defined(__ATARI5200__)
#define TXT_DEFENCES "SET UP DEFENCES, START: DONE"
#endif

#ifdef __NABU__
#define QUIT_HINT "ESC: QUIT"           /* the title: ESC resets to the NABU's menu (plat_quit) */
#endif
#ifdef __MSDOS__
#define QUIT_HINT "ESC: LOBBY"          /* the title: ESC goes back to the lobby (menus.c) */
#endif

#endif
