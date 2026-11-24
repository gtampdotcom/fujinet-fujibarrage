# tools/adam/build.mk -- FujiBarrage for the Coleco Adam (z88dk: zcc with
# zsdcc, z80asm). From the top: make adam, which runs this in the defoogi
# container unless z88dk is installed (tools/z80/z88dk).
#
#   make -f tools/adam/build.mk             r2r/adam/barrage.ddp
#   ... TEST=1                              with the offline test scenes
#   ... TEST_SCENE=n TEST_ARG=a             a scene built in (adamcore can't poke)
#   ... VIDEO_CARD=1                        M0's test card on the screen
#   ... XFLAGS=-D...                        more flags, both programs
#
# Two programs on one medium, as on the Atari and the CoCo: the game
# (it boots: z88dk's bootstrap in block 0 loads it to 0000h) and the menu
# (-DMENU: the title, the name, the room list), after it. Each loads the
# other with EOS (src/adam/chain.asm); tools/adam/mkimage.py puts the menu
# after the game, fills both programs' chain tables and checks the memory.
#
# fujinet-lib is fujinet-lib-experimental built with zsdcc
# (tools/z80/fnlib_adam.sh: the released Adam library is sccz80's, whose
# arguments come in the other order), made by the top Makefile first.

ZCC := zcc
B := build/adam
R := r2r/adam
FNLIB := build/fnlib-adam

TARGET := +coleco -subtype=adam
CFLAGS := $(TARGET) -compiler=sdcc -SO2 -DUSING_FUJINET_LIB=1 \
	-Isrc -Isrc/platform-specific -Isrc/test -Igen -Igen/adam -Isrc/adam -Isrc/tms9918 -Isrc/z80 \
	-I$(FNLIB)/include
ifeq ($(TEST),1)
  TESTFLAGS := -DTEST_SCENES -DNO_APPKEYS $(TESTX)
endif
ifneq ($(TEST_SCENE),)
  TESTFLAGS += -DTEST_SCENE=$(TEST_SCENE) -DTEST_ARG=$(or $(TEST_ARG),0)
endif
ifeq ($(VIDEO_CARD),1)
  CFLAGS += -DVIDEO_CARD
endif
CFLAGS += $(XFLAGS)
# the NMI is ours (nmi.asm); z88dk's screen set-up, console and stdio left out
LDFLAGS := $(TARGET) -compiler=sdcc -m -create-app \
	-pragma-define:CRT_ENABLE_NMI=2 -pragma-define:CRT_INITIALIZE_BSS=1 \
	-pragma-define:CRT_ENABLE_STDIO=0 -pragma-define:CLIB_DEFAULT_SCREEN_MODE=-1 \
	-pragma-define:CLIB_EXIT_SCREEN_MODE=-1 -pragma-redirect:fputc_cons=l_ret
.DEFAULT_GOAL := all
GEN := gen/adam/art.bin gen/adam/fldart.asm gen/adam/title.asm gen/adam/sfx.asm gen/adam/tunes_game.asm gen/adam/tunes_menu.asm
HDRS := $(wildcard src/*.h src/platform-specific/*.h src/adam/*.h src/tms9918/*.h src/adam/test/*.h) gen/config.h

SHARED := src/main.c src/menus.c src/appkey.c src/net.c src/cat.c
GAME := src/play.c src/room.c src/test.c src/tms9918/field.asm src/tms9918/fld.asm src/tms9918/render.asm \
	gen/adam/fldart.asm gen/adam/tunes_game.asm src/z80/ply.asm src/z80/trk.asm src/z80/ops.asm src/z80/pt.asm
COMMON := src/adam/plat.c src/adam/input.c src/adam/nstrans.c src/adam/nmi.asm src/adam/vdp.asm \
	src/adam/eoscall.asm src/adam/chain.asm src/tms9918/scr.asm src/tms9918/card.c \
	src/sound/snd.asm src/sn76489/sn.asm gen/adam/sfx.asm

PROGS := game menu
game_SRC := $(SHARED) $(GAME) $(COMMON)
menu_SRC := $(SHARED) $(COMMON) src/tms9918/menu.asm src/tms9918/title.asm src/tms9918/lzd.asm gen/adam/title.asm gen/adam/tunes_menu.asm
game_FLAGS := $(TESTFLAGS)
menu_FLAGS := -DMENU

# a program: its objects (build/adam/<prog>/<source>.o) and its link; its
# flags in build/adam/<prog>.flags, rewritten when they change (TEST=1 and
# back), so its objects build again
define PROG_template
$(1)_OBJ := $$(patsubst %,$(B)/$(1)/%.o,$$(basename $$($(1)_SRC)))
$(B)/$(1).flags: FORCE
	@mkdir -p $(B)
	@echo '$$(CFLAGS) $$($(1)_FLAGS)' | cmp -s - $$@ || echo '$$(CFLAGS) $$($(1)_FLAGS)' > $$@
$(B)/$(1)/%.o: %.c $(HDRS) $(B)/$(1).flags
	@mkdir -p $$(dir $$@)
	$(ZCC) $$(CFLAGS) $$($(1)_FLAGS) -c -o $$@ $$<
$(B)/$(1)/%.o: %.asm $(B)/$(1).flags $(GEN) $(wildcard src/z80/*.inc src/adam/*.inc)
	@mkdir -p $$(dir $$@)
	$(ZCC) $$(CFLAGS) $$($(1)_FLAGS) -Ca-Isrc/z80 -Ca-Isrc/adam -Ca-Isrc -c -o $$@ $$<
$(B)/$(1).ddp: $$($(1)_OBJ) $(FNLIB)/fujinet-adam.lib
	$(ZCC) $$(LDFLAGS) -o $(B)/$(1).bin $$($(1)_OBJ) -L$(FNLIB) -lfujinet-adam
	rm -f $(B)/$(1)_BOOTSTRAP.bin
	@test -f $$@ || { echo "build.mk: no $$@ from appmake"; exit 1; }
endef
$(foreach p,$(PROGS),$(eval $(call PROG_template,$(p))))

all: $(R)/barrage.ddp

# the art (tools/mkgfx_tms.py)
gen/adam/fldart.asm: tools/mkgfx_tms.py
	python3 tools/mkgfx_tms.py field $@
gen/adam/art.bin: tools/mkgfx_tms.py gfx/coco/namco.bin
	python3 tools/mkgfx_tms.py art $@
gen/adam/title.asm: tools/mkgfx_tms.py tools/mktitle_coco.py gfx/coco/namco.bin
	python3 tools/mkgfx_tms.py title $@

# the sound (tools/mksfx_z80.py): the effects; the tunes, the menu's title,
# the game's others
SNDDEP := tools/mksfx_z80.py tools/mksfx_coco.py tools/mus.py tools/mkmus_intv.py src/intv/sfx.asm $(wildcard music/*.txt)
gen/adam/sfx.asm: $(SNDDEP)
	python3 tools/mksfx_z80.py sfx $@
gen/adam/tunes_game.asm: $(SNDDEP)
	python3 tools/mksfx_z80.py tunes $@ win=music/win.txt over=music/over.txt shop=music/shop.txt
gen/adam/tunes_menu.asm: $(SNDDEP)
	python3 tools/mksfx_z80.py tunes $@ title=music/title.txt

$(R)/barrage.ddp: $(B)/game.ddp $(B)/menu.ddp tools/adam/mkimage.py gen/adam/art.bin
	@mkdir -p $(R)
	python3 tools/adam/mkimage.py $(B) $(R)

.PHONY: all FORCE
FORCE:
