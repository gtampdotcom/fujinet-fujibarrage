#!/usr/bin/env python3
"""tools/nabu/mkcopper.py -- the F18A's copper (src/nabu/f18a.c): a TMS9900
program for the F18A's GPU (a PICO9918's too) that sets four palette
entries every scanline of the field, so the field has the VGA build's look
(src/msdos/vga/video.c) in Graphics II's 16 colours: the sky a ramp from
its top to the horizon, the dirt in strata darker going down with a grain,
the fire's colours cycling down it.

    python tools/nabu/mkcopper.py gen/nabu/copper.h

A small assembler for the instructions it uses, then the program. It sits
in the VRAM at 1F00h, its tables at 3F00h (both free: src/tms9918/tms.h):

    3F00  the sky's colour, a word every 2 lines (84)        -> entry 4
    3FA8  the dirt's 8 strata: its colour, its grain's (2 words each)
                                                              -> entries 6, 2
    3FC8  the fire's 16 colours (line y's: (y / 4 + phase) & 15) -> entry 5
    3FE8  entries 2, 4, 5, 6 as the TMS9918A has them (the HUD's rows, and
          every line while the field isn't shown)
    3FF0  the fire's phase (a byte)
    3FF1  on: the field is shown (a byte)

The tiles draw with the palette's second 16 (VR24 = 1: a copy of the
TMS9918A's colours, f18a.c), so the first 16 stay as they were for whatever
runs after us. Entry n is the word at 5020h + 2n in the GPU's map; the
scanline drawn is the byte at 7000h (192 and up below the screen, 255 in
the blank). A line's colours are written while the line before it is
drawn: a PICO9918 takes the palette at the start of each line it draws.
"""
import sys

ORG = 0x1F00
SKY, DIRT, FIRE, STD, PHASE, ON = 0x3F00, 0x3FA8, 0x3FC8, 0x3FE8, 0x3FF0, 0x3FF1
PAL = 0x5020                    # tile palette group 1 (VR24 = 1): entries 16-31
LINE = 0x7000
TITLE_ORG = 0x1B80              # the title's part (free VRAM: src/tms9918/tms.h)
TITLE_TAB = 0x1C00              # its table: f18a.c puts back the shake's names there after
TITLE_PAIRS = 96
FIELD_H = 168
SCREEN_H = 192


class Asm:
    def __init__(self, org):
        self.org = org
        self.words = []         # ints, or (kind, label) to fix up
        self.labels = {}

    @property
    def pc(self):
        return self.org + 2 * len(self.words)

    def label(self, name):
        self.labels[name] = self.pc

    # an operand: ("r", n) Rn, ("ind", n) *Rn, ("sym", addr) @addr, ("idx", addr, n) @addr(Rn)
    def _ga(self, op):
        k = op[0]
        if k == "r":
            return 0, op[1], None
        if k == "ind":
            return 1, op[1], None
        if k == "inc":                      # *Rn+
            return 3, op[1], None
        if k == "sym":
            return 2, 0, op[1]
        if k == "idx":
            assert op[2] != 0
            return 2, op[2], op[1]
        raise ValueError(op)

    def two(self, opc, s, d):              # format I
        ts, sr, sx = self._ga(s)
        td, dr, dx = self._ga(d)
        self.words.append(opc << 12 | td << 10 | dr << 6 | ts << 4 | sr)
        if sx is not None:
            self.words.append(sx)
        if dx is not None:
            self.words.append(dx)

    def mov(self, s, d): self.two(0xC, s, d)
    def movb(self, s, d): self.two(0xD, s, d)
    def a(self, s, d): self.two(0xA, s, d)
    def c(self, s, d): self.two(0x8, s, d)

    def imm(self, opc, r, v):              # format VIII
        self.words += [opc | r, v & 0xFFFF]

    def li(self, r, v): self.imm(0x0200, r, v)
    def ai(self, r, v): self.imm(0x0220, r, v)
    def andi(self, r, v): self.imm(0x0240, r, v)
    def ci(self, r, v): self.imm(0x0280, r, v)

    def single(self, opc, op):             # format VI
        t, r, x = self._ga(op)
        self.words.append(opc | t << 4 | r)
        if x is not None:
            self.words.append(x)

    def clr(self, r): self.single(0x04C0, ("r", r))
    def inc(self, r): self.single(0x0580, ("r", r))
    def dec(self, r): self.single(0x0600, ("r", r))
    def b_r11(self): self.single(0x0440, ("ind", 11))
    def b(self, addr): self.single(0x0440, ("sym", addr))

    def bl(self, label):
        self.words += [0x06A0, ("abs", label)]

    def srl(self, r, n):
        assert 1 <= n <= 15
        self.words.append(0x0900 | n << 4 | r)

    def jump(self, opc, label):            # format II
        self.words.append(("jmp", opc, label))

    def jmp(self, l): self.jump(0x10, l)
    def jeq(self, l): self.jump(0x13, l)
    def jhe(self, l): self.jump(0x14, l)
    def jne(self, l): self.jump(0x16, l)
    def jl(self, l): self.jump(0x1A, l)

    def link(self):
        out = []
        for i, w in enumerate(self.words):
            if isinstance(w, tuple):
                if w[0] == "abs":
                    w = self.labels[w[1]]
                else:
                    disp = (self.labels[w[2]] - (self.org + 2 * i + 2)) // 2
                    assert -128 <= disp <= 127, w
                    w = w[1] << 8 | (disp & 0xFF)
            out += [w >> 8, w & 0xFF]
        return bytes(out)


def program():
    g = Asm(ORG)
    R1, R2, R3, R4, R5, R7, R8 = 1, 2, 3, 4, 5, 7, 8

    def line(r):                # R2 = the scanline
        g.movb(("ind", R1), ("r", r))
        g.srl(r, 8)

    g.li(R1, LINE)
    g.label("frame")            # below the screen first (the HUD's rows drawn)
    g.label("w1")
    line(R2)
    g.ci(R2, SCREEN_H)
    g.jl("w1")
    g.movb(("sym", ON), ("r", R2))
    g.jeq("off")
    g.srl(R2, 8)                # (MOVB: the high byte only)
    g.ci(R2, 2)                 # on = 2: the title (title())
    g.jne("on")
    g.b(TITLE_ORG)
    g.label("off")
    g.bl("std")                 # off: the TMS9918A's colours, once a frame
    g.label("w2")
    line(R2)
    g.ci(R2, SCREEN_H)
    g.jhe("w2")
    g.jmp("frame")

    g.label("on")               # line 0's colours, in the blank
    g.clr(R3)                   # R3: the line
    g.clr(R4)                   # R4: the stratum's offset (4 a stratum)
    g.li(R5, FIELD_H // 8)      # R5: its lines left
    g.bl("sub")
    g.label("wz")               # the frame begins
    line(R2)
    g.ci(R2, FIELD_H)
    g.jhe("wz")
    g.label("next")             # line R3 is drawn: the next's colours
    g.inc(R3)
    g.ci(R3, FIELD_H)
    g.jeq("done")
    g.dec(R5)
    g.jne("ns")
    g.li(R5, FIELD_H // 8)
    g.ai(R4, 4)
    g.label("ns")
    g.bl("sub")
    g.label("wt")               # till line R3 is drawn
    line(R2)
    g.ci(R2, FIELD_H)
    g.jhe("done")               # (behind: the field's lines are over)
    g.c(("r", R2), ("r", R3))
    g.jl("wt")
    g.jmp("next")

    g.label("done")             # the field's last line drawn: the HUD's colours
    line(R2)
    g.ci(R2, FIELD_H - 1)
    g.jl("done")
    g.bl("std")
    g.jmp("frame")

    g.label("std")
    for k, e in enumerate((2, 4, 5, 6)):
        g.mov(("sym", STD + 2 * k), ("sym", PAL + 2 * e))
    g.b_r11()

    g.label("sub")              # line R3's colours
    g.mov(("r", R3), ("r", R7))
    g.andi(R7, 0xFFFE)
    g.mov(("idx", SKY, R7), ("sym", PAL + 2 * 4))
    g.mov(("idx", DIRT, R4), ("sym", PAL + 2 * 6))
    g.mov(("idx", DIRT + 2, R4), ("sym", PAL + 2 * 2))
    g.mov(("r", R3), ("r", R7))
    g.srl(R7, 2)
    g.movb(("sym", PHASE), ("r", R8))
    g.srl(R8, 8)
    g.a(("r", R8), ("r", R7))
    g.andi(R7, 15)
    g.a(("r", R7), ("r", R7))
    g.mov(("idx", FIRE, R7), ("sym", PAL + 2 * 5))
    g.b_r11()
    code = g.link()
    assert len(code) <= 256, len(code)
    return code, g.labels["frame"]


def title(frame):
    """on = 2, the title (src/nabu/f18a.c f18a_title): its table's 4 words
    a pair of lines (entry << 12 | 0RGB: tools/mkgfx_tms.py f18a_table)
    into the tiles' entries, pair k's while line 2k - 1 is drawn (pair 0's
    in the blank)"""
    g = Asm(TITLE_ORG)
    R2, R3, R6, R7, R8, R9, R10 = 2, 3, 6, 7, 8, 9, 10
    g.li(6, TITLE_TAB)
    g.bl("put")
    g.li(R3, 1)                 # R3: the line to wait for
    g.li(R9, TITLE_PAIRS - 1)
    g.label("tw")
    g.movb(("ind", 1), ("r", R2))
    g.srl(R2, 8)
    g.ci(R2, SCREEN_H)
    g.jhe("tw")                 # (below the screen: the frame's still to begin)
    g.c(("r", R2), ("r", R3))
    g.jl("tw")
    g.bl("put")
    g.ai(R3, 2)
    g.dec(R9)
    g.jne("tw")
    g.b(frame)
    g.label("put")
    g.li(R10, 4)
    g.label("pl")
    g.mov(("inc", R6), ("r", R7))
    g.mov(("r", R7), ("r", R8))
    g.srl(R8, 12)
    g.a(("r", R8), ("r", R8))
    g.andi(R7, 0x0FFF)
    g.mov(("r", R7), ("idx", PAL, R8))
    g.dec(R10)
    g.jne("pl")
    g.b_r11()
    code = g.link()
    assert len(code) <= 0x80, len(code)
    return code


def main():
    code, frame = program()
    tcode = title(frame)
    out = ["/* GENERATED by tools/nabu/mkcopper.py: the F18A GPU's copper. */",
           "#define COPPER_ORG 0x%04X" % ORG,
           "#define COPPER_TAB 0x%04X" % SKY,
           "#define COPPER_TITLE_ORG 0x%04X" % TITLE_ORG,
           "#define COPPER_TITLE_TAB 0x%04X" % TITLE_TAB]
    for name, c in (("copper", code), ("copper_title", tcode)):
        out.append("static const uint8_t %s[%d] = {" % (name, len(c)))
        for i in range(0, len(c), 12):
            out.append("    " + ", ".join("0x%02X" % b for b in c[i:i + 12]) + ",")
        out.append("};")
    open(sys.argv[1], "w").write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
