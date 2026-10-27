ZAS?=z88dk-z80asm
EMU?=zeal-native
OS_IMG?=../Zeal-8-bit-OS/build/os_with_romdisk.img
INCLUDE=-I../Zeal-VideoBoard-SDK/include -I../Zeal-8-bit-OS/sdk/z88dk-z80asm
OBJ=main.o math.o course_index.o
IMG=img/bg.zts.zx0 img/player.zts.zx0 img/tree.zts.zx0 img/ramp.zts.zx0 img/numbers.zts.zx0
PAL=img/bg.ztp img/player.ztp img/tree.ztp img/ramp.ztp img/numbers.ztp
LVL=map/baselayer0000.ztm map/baselayer0001.ztm map/baselayer0002.ztm map/baselayer0003.ztm map/baselayer0004.ztm
SRC_INC=game.asm input.asm physics.asm hud.asm sprites.asm debug.asm assets.asm dzx0_standard.asm

all: jetski.bin

main.o: main.asm $(SRC_INC) $(LVL) $(IMG) $(PAL)
	$(ZAS) $(INCLUDE) -o=main.o main.asm
math.o: math.asm
	$(ZAS) $(INCLUDE) -o=math.o math.asm
course_index.o: course_index.asm
	$(ZAS) $(INCLUDE) -o=course_index.o course_index.asm

jetski.bin: $(OBJ)
	$(ZAS) $(INCLUDE) -m -l -s -b -o=jetski.bin $(OBJ)
	cp jetski.bin s

%.zts.zx0: %.zts
	zx0 -f $<

%.zts %.ztp &: %.gif
	../Zeal-VideoBoard-SDK/tools/zeal2gif/gif2zeal.py -i $< -b 4

$(LVL) &: map/baselayer.tmx $(wildcard map/*.tsx)
	../Zeal-VideoBoard-SDK/tools/tiled2zeal/tiled2zeal.py -i map/baselayer.tmx

# -u loads jetski.bin as the user program so the OS starts it automatically; -H exposes this directory as h:/
run: jetski.bin
	$(EMU) -r $(OS_IMG) -u jetski.bin -H .

clean:
	-rm img/*.zx0
	-rm img/*.zt[sp]
	-rm map/baselayer*.ztm
	-rm $(OBJ)
	-rm jetski.bin
	-rm main.sym jetski.map main.lis

.PHONY: all run clean
