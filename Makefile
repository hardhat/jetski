INCLUDE=-I../Zeal-VideoBoard-SDK/include -I../Zeal-8-bit-OS/kernel_headers/z88dk-z80asm
OBJ=main.o math.o
IMG=img/bg.zts.zx0 img/player.zts.zx0 img/tree.zts.zx0 img/ramp.zts.zx0 img/numbers.zts.zx0
LVL=map/baselayer0000.ztm

all: jetski.bin

main.o: main.asm dzx0_standard.asm $(LVL) $(IMG)
	z88dk-z80asm $(INCLUDE) -o=main.o main.asm

math.o: math.asm
	z88dk-z80asm $(INCLUDE) -o=math.o math.asm

jetski.bin: $(OBJ)
	z88dk-z80asm $(INCLUDE) -m -l -b -o=jetski.bin $(OBJ)

%.zts.zx0: %.zts
	zx0 -f $<

%.zts: %.gif
	../Zeal-VideoBoard-SDK/tools/zeal2gif/gif2zeal.py -i $< -b 4

$(LVL): map/baselayer.tmx
	../Zeal-VideoBoard-SDK/tools/tiled2zeal/tiled2zeal.py -i map/baselayer.tmx

clean:
	-rm img/*.zx0
	-rm img/*.zt[sp]
	-rm map/baselayer*.ztm
	-rm $(OBJ)
	-rm jetski.bin
	-rm main.sym jetski.map main.lis
