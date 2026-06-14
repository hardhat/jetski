; jetski - Z80 asm code for the main game loop
	include "zvb_hardware_h.asm"
	include "zos_sys.asm"
	include "zos_err.asm"
	include "zos_keyboard.asm"
	include "zos_video.asm"

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

	CALL ReadKeyboard
	CALL UpdatePhysics

	JP GameLoop

QuitGame:
	LD	A,VID_MODE_TEXT_640
	OUT	(IO_CTRL_VID_MODE),A

	LD H,DEV_STDOUT
	LD C,CMD_RESET_SCREEN
	LD DE,0
	IOCTL

	LD H,0
	EXIT

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

; void plotLine(int x0, int y0, int x1, int y1)
; {
;    int dx =  abs(x1-x0), sx = x0<x1 ? 1 : -1;
;    int dy = -abs(y1-y0), sy = y0<y1 ? 1 : -1; 
;    int err = dx+dy, e2; /* error value e_xy */
 
;    for(;;){  /* loop */
;       setPixel(x0,y0);
;       if (x0==x1 && y0==y1) break;
;       e2 = 2*err;
;       if (e2 >= dy) { err += dy; x0 += sx; } /* e_xy+e_x > 0 */
;       if (e2 <= dx) { err += dx; y0 += sy; } /* e_xy+e_y < 0 */
;    }
; }

; void plotCircle(int xm, int ym, int r)
; {
;    int x = -r, y = 0, err = 2-2*r; /* II. Quadrant */ 
;    do {
;       setPixel(xm-x, ym+y); /*   I. Quadrant */
;       setPixel(xm-y, ym-x); /*  II. Quadrant */
;       setPixel(xm+x, ym-y); /* III. Quadrant */
;       setPixel(xm+y, ym+x); /*  IV. Quadrant */
;       r = err;
;       if (r <= y) err += ++y*2+1;           /* e_xy+e_y < 0 */
;       if (r > x || err > y) err += ++x*2+1; /* e_xy+e_x > 0 or no 2nd y-step */
;    } while (x < 0);
; }

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
	LD (HL),A
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
	JR PrintDec
PrintDec16:
	LD BC,-10000
	CALL SubCount
	LD BC,-1000
	CALL SubCount

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
	;Note: "0123456789:/" is the character set used, so '0' is tile 192.
PrintDigit:
	LD DE,(Cursor)
	ADD A,192
	LD (DE),A
	INC DE
	LD (Cursor),DE
	RET

UpdatePhysics:
	; Update the physics of the game here, including player movement, collision detection, etc. 
	;This is called once per frame after reading the keyboard input and before drawing the next frame.
	; First update the player's speed based on the throttle input
	; Then update the player's position based on the speed and steering input
	; Then check for collisions with the environment and update the game state accordingly (e.g.
	; if the player hits a tree, reset their position and speed)
	LD A,(Throttle)
	CP 0
	JR Z,NoThrottle
	; If throttle is not zero, increase speed by 1, up to a maximum of 10.
	LD HL,Speed
	LD A,(HL)
	CP 10
	JR NC,MaxSpeed
	INC A
	LD (HL),A
	JR UpdatePosition
MaxSpeed:
	LD (HL),10
	JR UpdatePosition
NoThrottle:
	; If throttle is zero, decrease speed by 1, down to a minimum of 0.
	LD HL,Speed
	LD A,(HL)
	CP 0
	JR Z,MinSpeed
	DEC A
	LD (HL),A
	JR UpdatePosition
MinSpeed:
	LD (HL),0
	JR UpdatePosition
UpdatePosition:
	; Update the player's position based on the current speed and steering input.
	; This is where you would use the sine and cosine functions to calculate the 
	; change in x and y based on the player's current angle and speed, and then update 
	; the player's position accordingly.
	LD A,(Steer)
	CP 0
	JR Z,NoSteer
	; If steering is not zero, update the player's angle based on the steering input.
	; For example, if the player is steering left, decrease the angle by a certain amount, and if they are steering right, increase the angle by a certain amount.
	; The angle should wrap around from 255 back to 0, since we are using an 8-bit value to represent the angle.
	; After updating the angle, use the sine and cosine functions to calculate the change in x and y based on the new angle and the current speed, and then update the player's position accordingly.
	; Note: The player's angle and position should be stored in memory, and you would need to load those values, update them, and then store them back in memory.
	; For example, you could store the player's angle in a variable called PlayerAngle, and the player's x and y position in variables called PlayerX and PlayerY. You would then load those values, update them based on the steering and speed, and then store them back in memory.
	; This is just a placeholder implementation, and you would need to fill in the actual calculations based on the player's current angle and speed, and how much you want the steering to affect the angle.
	LD HL,PlayerAngle
	LD A,(HL)
	CP 128
	JR NC,SteerRight
	; Steer left
	DEC A
	JR UpdateAngle
SteerRight:
	INC A ; Steer right
UpdateAngle:
	LD (HL),A
	; Now calculate the change in x and y based on the new angle and current speed, and update the player's position accordingly.
	; This is where you would call the sine and cosine functions with the player's angle to get the change in x and y, and then update the player's position based on the current speed.
	; For example, you could call sine_88 with the player's angle to get the change in y, and cosine_88 to get the change in x, and then
	; multiply those values by the player's speed to get the actual change in position, and then update the player's x and y position accordingly.
	; Note: You would need to implement the sine_88 and cosine_88 functions in math.asm, and they would return the sine and cosine of the input angle as 8.8 fixed point numbers, which you would then need to multiply by the player's speed (also in 8
	; .8 fixed point) to get the change in position, and then update the player's x and y position (also in 8.8 fixed point) accordingly.
	; This is just a placeholder implementation, and you would need to fill in the actual calculations
	; based on how you are representing the player's angle, speed, and position in memory, and how you want the steering to affect the angle.
	; For example, if the player's speed is stored in a variable called PlayerSpeed, and
	; the player's x and y position are stored in variables called PlayerX and PlayerY, you would load those values, call the sine and cosine functions with the player's angle to get the change in x and y, multiply those by the player's speed to get the actual change in position, and then update the player's x and y position accordingly.
NoSteer:
	; If steering is zero, just update the player's position based on the current speed and angle without changing the angle.
	; This is where you would call the sine and cosine functions with the player's current angle to get the change in x and y, and then update the player's position based on the current speed.
	; For example, you could call sine_88 with the player's angle to get the change in y, and cosine_88 to get the change in x, and then multiply
	; those values by the player's speed to get the actual change in position, and then update the player's x and y position accordingly.
	; Note: You would need to implement the sine_88 and cosine_88 functions in math.asm, and they would return the sine and cosine of the input angle as 8.8
	RET

ReadKeyboard:
	LD DE,keyboard_buffer
	LD BC,16
	S_READ1 DEV_STDIN

	OR A	; Check for err success=0
	JR NZ,ReadKeyboardError

	LD B,C	; Number of characters in B
	LD A,B
	OR A
	RET Z	; No keyboard input
ReadKeyboardLoop:
	LD HL,keyboard_buffer
	LD A,(HL)
	LD C,A
	CP KB_ESC
	CALL Z,HandleEsc
	CP KB_UP_ARROW
	CALL Z,HandleUp
	CP KB_DOWN_ARROW
	CALL Z,HandleDown
	CP KB_LEFT_ARROW
	CALL Z,HandleLeft
	CP KB_RIGHT_ARROW
	CALL Z,HandleRight
	CP KB_KEY_SPACE
	CALL Z,HandleSpace
	CP KB_KEY_ENTER
	CALL Z,HandleEnter
	; Handle other keys here
	INC HL
	DJNZ ReadKeyboardLoop
	RET

ReadKeyboardError:
	LD DE,keyboard_error_message
	LD BC,keyboard_error_message_len
	S_WRITE1 DEV_STDOUT

	RET

HandleEsc:
	; Handle escape key press by quitting the game.
	JP QuitGame
HandleLeft:
	LD A,-1	; 0xff in 8-bit signed is -1
	LD (Steer),A
	LD A,C
	RET
HandleRight:
	LD A,1
	LD (Steer),A
	LD A,C
	RET
HandleUp:
	LD A,1
	LD (Throttle),A
	LD A,C
	RET
HandleDown:
	LD A,-1
	LD (Throttle),A
	LD A,C
	RET
HandleSpace:
	; Handle space key press by accelerating the jetski.
	LD A,1
	LD (Throttle),A
	LD A,C
	RET
HandleEnter:
	; Handle enter key press by resetting the game or performing another action.
	RET

Steer:
	DEFB 0
Throttle:
	DEFB 0
Speed:
	DEFW 0
PlayerAngle:
	DEFB 0,0


keyboard_error_message:
	DB "Error reading keyboard", 13, 10
keyboard_error_message_len EQU $-keyboard_error_message

   ; Include the DZX0 decompression routine

	include "dzx0_standard.asm"

keyboard_buffer:
    DS 16

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