; art.asm -- the art block (the Adam's, its own on the Adam's medium:
; tools/mkgfx_tms.py art), the VRAM's 3800h-3BFFh: the tanks' sprite
; patterns, then (3A00h) the font, which the code reads back from there.
; In the program on the NABU.

        SECTION code_user

        PUBLIC  _art_load, _art_ram
        EXTERN  _va_addr, _va_src, _va_len, _va_writef

; void art_load(void): at start-up (the display blanked)
_art_load:
        ld      hl,$3800
        ld      (_va_addr),hl
        ld      hl,art
        ld      (_va_src),hl
        ld      hl,1024
        ld      (_va_len),hl
        jp      _va_writef

        SECTION rodata_user
_art_ram:                       ; (src/tms9918/scr.asm's vram8 reads it: ART_RAM)
art:    BINARY  "art.bin"
