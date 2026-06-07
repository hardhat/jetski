; jetski - Z80 asm code for the main game loop
	include "zvb_hardware_h.asm"

	org 0x4000

PageMapPort	EQU	0xF0	;+0 to +3 for each 16k bank
VRAMTileSetPage	EQU	VID_MEM_TILESET_ADDR>>14
VRAMBasePage	EQU	VID_MEM_PHYS_ADDR_START>>14
PaletteOffset	EQU	VID_MEM_PALETTE_OFFSET
Layer0Offset	EQU VID_MEM_LAYER0_OFFSET
Layer1Offset	EQU VID_MEM_LAYER1_OFFSET
SpritesOffset	EQU	VID_MEM_SPRITES_OFFSET
MappedMem	EQU	0x8000	;PAGE2_VADDR
buffer	EQU 0xc000	;PAGE3_VADDR
bufferLen	EQU 0x3000

InitVideo:
	XOR	A
	OUT (IO_CTRL_STATUS_REG),A	; Disable screen during setup

	LD	A,VID_MODE_GFX_320_4BIT
	OUT	(IO_CTRL_VID_MODE),A

	LD IX,TileSet
TileSetLoadLoop:
	LD A,(IX+1)	; Get high bit for 256-511
	SRL A
	LD A,(IX+0)	; Target tileset entry
	RR A   ; To find what page to use, divide by 0x40
	SRL A
	SRL A
	SRL A
	SRL A
	SRL A 
	SRL A
	ADD A,VRAMTileSetPage
	OUT	(PageMapPort+2),A

	LD A,(IX+0) ; Now determine where in the tile set to load
	LD H,(IX+1) ; so tile number in HA
	LD L,0			; We want HL = AH*128, so start with HAL = HA*256.
	SRL H	; Divide by 2 since each entry is 128 bytes
	RR A	; Divide by 2 since each entry is 128 bytes
	RR L ; Divide by 2 since each entry is 128 bytes
	AND 0x3F ; where in the 16KB page
	LD H,A
	LD DE,MappedMem
	ADD HL,DE	; Add the base address of the mapped memory to get the final address
	EX DE,HL	; Result in DE.
	; Find the source tile data for the tilemap entry
	LD L,(IX+2)
	LD H,(IX+3)
	PUSH IX
	CALL	dzx0_standard
	POP IX
	LD DE,6
	ADD IX,DE
	LD A,(IX+2)
	OR (IX+3)
	JR NZ,TileSetLoadLoop	; Loop until we hit the 0xffff terminator
	
	LD IX,TileMapBg
	LD	A,VRAMBasePage
	OUT	(PageMapPort+2),A
	XOR	A
	LD	DE,MappedMem+Layer1Offset
	LD	HL,MappedMem+Layer0Offset
	LD	C,15
FillNameRow:
	LD	B,20
FillNameCol:
	LD	A,(IX+0)
	LD	(HL),A
	PUSH BC
	LD C,0
	CP  64
	JR C,WritePalette
	INC C
	CP 128
	JR C,WritePalette
	INC C
	CP 160
	JR C,WritePalette
	INC C
	CP 192
	JR C,WritePalette
	INC C
WritePalette:
	LD A,C
	ADD A,A	;x16
	ADD A,A
	ADD A,A
	ADD A,A
	; control bits in layer 1 are: [7-4] palette, 3=flip x, 2=flip y, 1=unused, 0=high bit of index 
	LD  (DE),A
	POP BC

	INC	DE
	INC	HL
	INC IX
	DJNZ	FillNameCol
	PUSH	DE
	LD	DE,60
	ADD	HL,DE
	POP DE
	PUSH HL
	LD HL,60
	ADD HL,DE
	EX DE,HL
	POP HL
	DEC	C
	JR	NZ,FillNameRow

	LD	HL,Palette
	LD	DE,PaletteOffset+MappedMem
	LD	BC,PaletteSize
	LDIR

	LD	A,0x80	; Enable the display
	OUT	(IO_CTRL_STATUS_REG),A

	LD HL,buffer	; zero out the sprite table
	LD DE,buffer+1
	LD BC,sprite_size*128
	LD (HL),0
	LDIR

	LD IX,SpriteTileMap
	LD DE,buffer ; The sprite table output
InitSpriteTable:
	LD L,(IX+0) ; What TileMap to analyze for sprites.
	LD H,(IX+1)
	LD A,H
	OR L
	JR Z,DoneInitSprites

	LD (IX+2),E
	LD (IX+3),D ; save where in the sprite table this is

	LD C,15
InitSpritesRowLoop:
	LD B,20
InitSpritesColLoop:
	PUSH IX
	LD A,(HL)
	CP 0xff
	PUSH HL
	CALL NZ,InitSprite
	POP HL
	INC HL
	DJNZ InitSpritesColLoop
	DEC C
	JR NZ,InitSpritesRowLoop

	PUSH DE	; Save next sprite table entry
	LD L,(IX+2) ; Calculate current table entry - first table entry
	LD H,(IX+3)
	EX DE,HL
	OR A
	SBC HL,DE
	POP DE

	SRA H	; Then Divide by 8
	RR L
	SRA H
	RR L
	SRA H
	RR L
	LD (IX+4),L ; How many sprites in this block 

	LD BC,5
	ADD IX,BC

	JR InitSpriteTable

DoneInitSprites:
	; LD  HL,
	; LD	DE,buffer
	; LD	BC,sprite_size*2
	; LDIR

GameLoop:
	CALL wait_for_vblank

	; Draw the sprites
	LD HL, sprite_table
	LD DE, MappedMem + SpritesOffset
	LD BC, sprite_size * 128
	LDIR

	CALL UpdateShore

	; Wait for the next frame
	CALL wait_end_vblank

	JP GameLoop

	ret

    ; Wait for the FPGA to be initialized, read the status register and wait for VBlank
wait_for_vblank:
    in a, (IO_CTRL_STATUS_REG)
    and 2
    jr z, wait_for_vblank
    ret

wait_end_vblank:
    in a, (IO_CTRL_STATUS_REG)
    and 2
    jr nz, wait_end_vblank
    ret

;InitSprite
; fills in the sprite table at DE with a sprite tile A at tile B,C
; Input: 
; A = sprite index to display
; DE = sprite table entry to fill in
; B = 19-col in tiles
; C = 14-row in tiles
; destroys HL, AF
; DE is advanced to next entry
InitSprite:
	PUSH AF
	LD H,0	; sprite_y = (16-C)*16
	LD A,16
	SUB C
	LD L,A
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL ;x16
	EX DE,HL
	LD (HL),E
	INC HL
	LD (HL),D
	INC HL
	EX DE,HL

	LD H,0 ; sprite_x = (21-B)*16
	LD A,21
	SUB B
	LD L,A
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL ;x16
	EX DE,HL
	LD (HL),E
	INC HL
	LD (HL),D
	INC HL
	EX DE,HL

	POP AF
	LD (DE),A	; sprite_tile = A
	INC DE

	PUSH BC	; sprite_flags based on palette to use
	LD C,0
	CP  64
	JR C,WriteSpriteFlags
	INC C
	CP 128
	JR C,WriteSpriteFlags
	INC C
	CP 160
	JR C,WriteSpriteFlags
	INC C
	CP 192
	JR C,WriteSpriteFlags
	INC C
WriteSpriteFlags:
	LD A,C
	ADD A,A	;x16
	ADD A,A
	ADD A,A
	ADD A,A
	; control bits in layer 1 are: [7-4] palette, 3=flip x, 2=flip y, 1=unused, 0=high bit of index 
	LD  (DE),A
	POP BC
	INC DE
	XOR A
	LD (DE),A ; Zero out 2 pad bytes
	INC DE
	LD (DE),A
	INC DE
	
	RET

UpdateShore:
	LD IX,(SpriteTileMap+2)	; Where the sprite entries start
	LD A,(SpriteTileMap+4) ; How many entries there are
	LD B,A

	LD A,(Frame)
	CP 16
	JR Z,ResetShore
	INC A
	LD (Frame),A
ShoreShiftLoop:
	;sprite_y += 2
	LD L,(IX+sprite_y)
	LD H,(IX+sprite_y_msb)
	INC HL
	INC HL
	LD (IX+sprite_y),L
	LD (IX+sprite_y_msb),H
	;sprite_x -= 1
	LD L,(IX+sprite_x)
	LD H,(IX+sprite_x_msb)
	DEC HL
	LD (IX+sprite_x),L
	LD (IX+sprite_x_msb),H

	LD DE,8
	ADD IX,DE

	DJNZ ShoreShiftLoop

	RET

ResetShore:
	XOR A
	LD (Frame),A

	; sprite_y-=16
	LD L,(IX+sprite_y)
	LD H,(IX+sprite_y_msb)
	LD DE,-32
	ADD HL,DE
	LD (IX+sprite_y),L
	LD (IX+sprite_y_msb),H
	; sprite_x-=8
	LD L,(IX+sprite_x)
	LD H,(IX+sprite_x_msb)
	LD DE,16
	ADD HL,DE
	LD (IX+sprite_x),L
	LD (IX+sprite_x_msb),H
	
	LD DE,8
	ADD IX,DE
	DJNZ ResetShore

	RET


CopySprite:	; Copy the sprite at DE to the next available sprite entry
	PUSH DE
	LD HL,(NextSpriteEntry)	; Our destination
	LD BC,sprite_size
	EX DE,HL
	LDIR
	EX DE,HL
	POP DE
	LD (NextSpriteEntry),HL
	ret

WordPlus16:
	LD A,(HL)
	ADD A,16
	LD (HL),a
	INC HL
	LD A,(HL)
	ADC A,0
	LD (HL),a
	INC HL
	RET

UpdateTile:	; Update the tile number in the sprite table.  A the the tile offset requested
	PUSH HL
	LD BC,-sprite_size+sprite_tile
	ADD HL,BC
	LD C,A
	LD A,(HL)
	ADD A,C
	LD (HL),A
	POP HL
	RET

UpdateFrame: ; In: Old frame in A, Out: new frame in A
	LD B,a
	AND 0xf8 ;Mask out the bottom 3 bits
	LD C,a
	INC B
	INC B ; +2
	LD A,7
	AND B	; Just the bottom 3 bits
	OR C	; Add the top 5 bits
	RET

PrintDecAt:	; Print a 16-bit number in HL to the screen at the specified position in DE
	LD (Cursor),DE

PrintDec:	; Print a 16-bit number in HL to the screen at the current cursor position
	LD BC,-100
	CALL SubCount
	LD BC,-10
	CALL SubCount
	LD BC,-1
	CALL SubCount
	RET
SubCount:
	xOR a
SubCountLoop:
	INC A
	ADD HL,BC
	JR C,SubCountLoop
	OR A	;Clear the carry flag.
	SBC HL,BC
	;Note: " 0123456789:+" is the character set used, so '0' is tile 1.
PrintDigit:
	LD DE,(Cursor)
	LD (DE),a
	INC DE
	LD (Cursor),DE
	RET

   ; Include the DZX0 decompression routine

	include "dzx0_standard.asm"

Frame:
	DEFB 0

Cursor:
	DEFW 0

   ; Put the sprite table at 0xc000
    defc sprite_table = 0xc000
    defc sprite_y = 0   ; 16-bit Y position
	defc sprite_y_msb = 1
    defc sprite_x = 2   ; 16-bit X position
	defc sprite_x_msb = 3
    defc sprite_tile = 4  ; 8-bit tile number
    defc sprite_flags = 5  ; 8-bit flags (from msb: 4-bit palette, flip x=8, flip y=4, behind fg=2, tile number high bit)
	defc sprite_options = 6 ; bit 1 = 32 pixel tall sprite, using 2 tiles vertically.  All other bits reserved for future use.
	defc sprite_options_msb = 7 ; reserved for future use (keep 0), must be written after options.
    defc sprite_size = 8    ; Size of each sprite entry

	defc flag_behind_fg = 2
	defc flag_flip_x = 8
	defc flag_flip_y = 4

NextSpriteEntry:
	DEFW	0
Player0:	; Made of 2x2 grid of 16x16 sprites
	DEFW	144	; Y position
	DEFW	64	; X position
	DEFB	32	; Tile number
	DEFB	flag_behind_fg | flag_flip_x	; Flag
	DEFB	0	; Padding
	DEFB	0	; Padding
Player1:	; Made of 2x2 grid of 16x16 sprites
	DEFW	144	; Y position
	DEFW	320-64	; X position
	DEFB	72	; Tile number
	DEFB	flag_behind_fg 	; Flag
	DEFB	0	; Padding
	DEFB	0	; Padding

SpriteTileMap:
	defw TileMapShore
	defw 0xffff ; Where the sprites are
	defb 0 ; Count of sprites for this layer
	dw TileMapSky
	defw 0xffff
	defb 0
	dw TileMapHud
	defw 0xffff
	defb 0
	defw TileMapSprites
	defw 0xffff
	defb 0
	defw 0 ; End of table

TileMapBg:
BaseLayer0000: ;bg
	incbin "map/baselayer0000.ztm"
BaseLayer0000Size EQU $-BaseLayer0000
TileMapShore:
BaseLayer0001: ;shore
	incbin "map/baselayer0001.ztm"
BaseLayer0001Size EQU $-BaseLayer0001
TileMapSky:
BaseLayer0002: ;sky
	incbin "map/baselayer0002.ztm"
BaseLayer0002Size EQU $-BaseLayer0002
TileMapHud:
BaseLayer0003: ;hud
	incbin "map/baselayer0003.ztm"
BaseLayer0003Size EQU $-BaseLayer0003
TileMapSprites:
BaseLayer0004: ;sprite layer (trees, ramps, etc)
	incbin "map/baselayer0004.ztm"
BaseLayer0004Size EQU $-BaseLayer0004

Palette:
	incbin "img/player.ztp"
	incbin "img/bg.ztp"
	incbin "img/tree.ztp"
	incbin "img/ramp.ztp"
	ds 24	; Pad the pallete to 16 entries (32 bytes) since the hardware reads in 16 entry chunks
	incbin "img/numbers.ztp"
	ds 16	; Pad the palette to 16 entries (32 bytes) since the hardware reads in 16 entry chunks
PaletteSize EQU $-Palette

TileSet:
	dw 0 ; First entry index ofr player tile map
	dw PlayerTileSet, PlayerTileSetSize
	dw 64 ; First entry index for background tile map
	dw BgTileSet, BgTileSetSize
	dw 128 ; First entry index for tree tile map
	dw TreeTileSet, TreeTileSetSize
	dw 160; First entry index for ramp tile map
	dw RampTileSet, RampTileSetSize
	dw 192 ; First entry index for numbers tile map
	dw NumbersTileSet, NumbersTileSetSize
	dw 0xffff	; Terminator for the tile map
	dw 0,0	; End of tile map

PlayerTileSet:
	incbin "img/player.zts.zx0"
PlayerTileSetSize EQU $-PlayerTileSet
BgTileSet:
	incbin "img/bg.zts.zx0"
BgTileSetSize EQU $-BgTileSet
TreeTileSet:
	incbin "img/tree.zts.zx0"
TreeTileSetSize EQU $-TreeTileSet
RampTileSet:
	incbin "img/ramp.zts.zx0"
RampTileSetSize EQU $-RampTileSet
NumbersTileSet:
	incbin "img/numbers.zts.zx0"
NumbersTileSetSize EQU $-NumbersTileSet
EndOfLine: