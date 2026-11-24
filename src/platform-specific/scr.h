/* scr.h -- text screens (menus, rooms, the waiting room, results): 24 rows
 * of 40 characters, each row its own colours. */
#ifndef SCR_H
#define SCR_H

#include <stdint.h>

#define SCR_ROWS 24
#if (defined(_COCO_BASIC_) && !defined(COCO3)) || defined(__ADAM__) || defined(__NABU__)
#define SCR_COLS 32             /* the CoCo 1/2: 4 colour pixels a column (src/coco2/scr2.c); the TMS9918 */
#else
#define SCR_COLS 40
#endif

/* palettes for a row */
enum { PAL_TEXT, PAL_TITLE, PAL_HEAD, PAL_HILITE, PAL_DIM, PAL_SEAT };

void scr_init(void);                            /* the display, at start-up */
void scr_begin(void);                           /* clear, all rows PAL_TEXT; off */
void scr_row(uint8_t row, uint8_t pal);         /* PAL_SEAT + seat: in its colour */
void scr_text(uint8_t row, uint8_t col, const char *s);
void scr_inverse(uint8_t row, uint8_t col, uint8_t n);  /* highlight n cells */
void scr_clear_row(uint8_t row);
void scr_scroll(uint8_t row, uint8_t n, uint8_t up);    /* rows row..row+n-1 move a row */
void scr_show(void);                            /* on, from the next frame */
#if defined(_COCO_BASIC_) || defined(__ADAM__) || defined(__MSDOS__) || defined(__NABU__)
#define SCR_PICTURE 1
void scr_picture(void);                         /* the title: a picture, its words in it */
#endif

#endif
