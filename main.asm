; jetski - Z80 asm code for the main game loop
	include "zvb_hardware_h.asm"
	include "zos_sys.asm"
	include "zos_err.asm"
	include "zos_keyboard.asm"
	include "zos_video.asm"

	extern course_index
	extern Div24_16
	extern Div_HL_D
	extern DE_Times_A

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

Start:

InitKeyboard:
	; Initialize the keyboard here if necessary.  For now, we just read from it each frame in the main loop.
	; Initialize the keyboard by setting it to raw and non-blocking
    ;void* arg = (void*) (KB_READ_NON_BLOCK | KB_MODE_RAW);
	LD DE,KB_READ_NON_BLOCK | KB_MODE_RAW
	LD H,DEV_STDIN
	LD C,KB_CMD_SET_MODE
    ;ioctl(DEV_STDIN, KB_CMD_SET_MODE, arg);
	IOCTL

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
	; Always select track 0
	LD HL,(course_index+0) ; name_ptr
	LD (CourseName),HL
	LD A,(course_index+2) ; difficulty
	LD (CourseDifficulty),A
	LD HL,(course_index+3) ; segment_count
	LD (CourseSegmentCount),HL
	LD HL,(course_index+5) ; segments_ptr
	LD (CourseSegmentPtr),HL

GameLoop:
	CALL wait_for_vblank

	; Draw the sprites
	LD HL, sprite_table
	LD DE, MappedMem + SpritesOffset
	LD BC, sprite_size * 128
	LDIR

	CALL UpdateHud
	CALL UpdateShore
	CALL UpdateSprites

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

	LD DE,ThanksForPlayingMessage
	LD BC,ThanksForPlayingMessageLen
	S_WRITE1 DEV_STDOUT

	LD H,0
	EXIT

ThanksForPlayingMessage:
	DB "Thanks for playing!", 13, 10
ThanksForPlayingMessageLen EQU $-ThanksForPlayingMessage

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

UpdateHud:
	; Set cursor position to top left corner at the beginning of the mapped page 2 memory 0x8000
	LD DE,MappedMem+80+Layer0Offset ; 80 is the offset to the second row of the tilemap, so we can write numbers in the top left corner without worrying about the status bar
	LD (Cursor),DE

	; Select the color map for the number output
	LD DE,MappedMem+80+Layer1Offset ; The layer 1 tilemap is used for the color map for the layer 0 tilemap, so we can have different colored numbers without affecting the background
	LD A,$40    ; color map 4
	LD B, 20
@Loop:
	LD (DE),A
	INC DE
	DJNZ @Loop


	LD HL,(Throttle)
	CALL PrintDec16

	LD DE,(Cursor)
	LD A,192+10 ;':'
	LD (DE),A
	INC DE
	LD (Cursor),DE

	LD HL,(Segment)
	CALL PrintDec99

	LD DE,(Cursor)
	LD A,192+11 ;'/'
	LD (DE),A
	INC DE
	LD (Cursor),DE

	LD HL,(CourseSegmentCount)
	CALL PrintDec99


	LD DE,(Cursor)
	LD A,192+10 ;':'
	LD (DE),A
	INC DE
	LD (Cursor),DE

	LD HL,(WorldPosZ)
	CALL PrintDec16	; 5 digits for the z position in cm

	LD DE,(Cursor)
	LD A,192+10 ;':'
	LD (DE),A
	INC DE
	LD (Cursor),DE

	LD HL,(Velocity)
	LD L,H ;show only the whole part
	LD H,0
	CALL PrintDec99

	;Second line of output
	LD DE,MappedMem+160+Layer1Offset ; Move cursor to second line
	LD A,$40    ; color map 4
	LD B, 20
@Loop2:
	LD (DE),A
	INC DE
	DJNZ @Loop2

	LD DE,MappedMem+160+Layer0Offset ; Move cursor to second line
	LD (Cursor),DE

	LD HL,(ElapsedTime)
	LD D,60
	CALL Div_HL_D
	PUSH AF ; Remainder in A is the number of seconds, quotient in HL is the number of minutes
	CALL PrintDec99 ; Print minutes

	LD DE,(Cursor)
	LD A,192+10 ;':'
	LD (DE),A
	INC DE
	LD (Cursor),DE

	POP AF ; Get seconds back from the stack
	LD H,0
	LD L,A
	CALL PrintDec99 ; Print seconds

	LD A,11 ;':'
	CALL PrintDigit

	LD DE,(ElapsedTimeFrames)
	LD A,100
	CALL DE_Times_A ; Get the number of frames (0-99) for the sub-second part of the time
	; Result in HL
	LD D,60
	CALL Div_HL_D ; move to 100ths of a second: Frames*100/60
	CALL PrintDec99 ; Print frames as 2 digit number

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
PrintDec99:	; Only 2 digit output
	LD BC,-10
	CALL SubCount
	LD BC,-1
	CALL SubCount
	RET
SubCount:
	XOR A
SubCountLoop:
	INC A
	ADD HL,BC
	JR C,SubCountLoop
	OR A	;Clear the carry flag.
	SBC HL,BC
	;Note: "0123456789:/" is the character set used, so '0' is tile 192.
PrintDigit:
	LD DE,(Cursor)
	ADD A,192-1
	LD (DE),A
	INC DE
	LD (Cursor),DE
	RET

	DEFC ACCELERATION = 75	; in 8.8 fixed-point cm/frame^2
	DEFC COAST = 25
	DEFC BREAK = 150
	DEFC MAX_SPEED = 46*256	; in 8.8 fixed-point cm/frame (about 100 km/h)

UpdatePhysics:
	; Update the physics of the game here, including player movement, collision detection, etc. 
	;This is called once per frame after reading the keyboard input and before drawing the next frame.
	; First update the player's speed based on the throttle input
	; Then update the player's position based on the speed and steering input
	LD HL,(Velocity)
	LD DE,(Throttle)
	ADD HL,DE
	LD DE, -COAST
	ADD HL,DE

	BIT 7,H	; Check if speed is negative
	JR Z,SpeedPositive
	LD HL,0	; If speed is negative, set to 0
	JR DoneSpeedUpdate

SpeedPositive:
	LD DE, MAX_SPEED
	OR A
	SBC HL,DE
	JR C,NotMaxSpeed
	LD HL,MAX_SPEED
	JR DoneSpeedUpdate
NotMaxSpeed:
	ADD HL,DE ; Restore value

DoneSpeedUpdate:
	LD (Velocity),HL ; in 8.8 fixed-point cm/frame
	; Update position
	EX DE,HL ; DE = velocity
	LD E,D
	LD D,0	; We only care about the whole part of the velocity for movement, so we can ignore the fractional part in D.
	; For now, ignore steering and just move forward based on the velocity
	LD HL,(WorldPosZ)
	ADD HL,DE
	LD (WorldPosZ),HL
	; Look for end of segment
	LD HL,(Segment)
	ADD HL,HL
	ADD HL,HL ; HL = segment*4 { int8_t curve; int16_t length; uint8_t flags; }
	LD DE,(CourseSegmentPtr)
	ADD HL,DE ; HL = pointer to current segment
	INC HL ; Skip curve
	LD A,(HL) ; Get length of segment
	INC HL
	LD H,(HL)
	LD L,A	; segment length in HL
	LD DE,(WorldPosZ)
	EX DE,HL
	OR A
	SBC HL,DE ; HL = WorldPosZ - segment length
	JR C,DoneSegmentCheck ; If we haven't reached the end of the segment, we're done
	; Save position in new segment
	LD (WorldPosZ),HL
	; Move to the next segment
	LD HL,(Segment)
	INC HL
	LD (Segment),HL
	LD A,(CourseSegmentCount)
	CP L
	JR NZ,DoneSegmentCheck ; If we haven't reached the end of the course, we're done
	; Restart the course
	LD HL,0
	LD (Segment),HL
	LD (WorldPosZ),HL
DoneSegmentCheck:
	; TODO steering and curve handling

	; Update elapsed time
	LD HL,(ElapsedTimeFrames)
	INC HL
	LD (ElapsedTimeFrames),HL
	LD A,L
	CP 60
	JR C,DoneTimeUpdate
	LD A,0
	LD (ElapsedTimeFrames),A
	LD HL,(ElapsedTime)
	INC HL
	LD (ElapsedTime),HL
DoneTimeUpdate:

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
	CP KB_RELEASED
	JR Z,ReadRelease
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
ReadRelease:
	DEC B
	RET Z	; No more keys to read
	INC HL
	LD A,(HL)
	CP KB_UP_ARROW
	CALL Z,HandleUpRelease
	CP KB_DOWN_ARROW
	CALL Z,HandleDownRelease
	CP KB_LEFT_ARROW
	CALL Z,HandleLeftRelease
	CP KB_RIGHT_ARROW
	CALL Z,HandleRightRelease
	CP KB_KEY_SPACE
	CALL Z,HandleSpaceRelease
	CP KB_KEY_ENTER
	CALL Z,HandleEnterRelease
	; Handle other key releases here
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
	LD DE,-1	; 0xff in 8-bit signed is -1
	LD (Steer),DE
	RET
HandleRight:
	LD DE,1
	LD (Steer),DE
	RET
HandleUp:
	LD DE,ACCELERATION
	LD (Throttle),DE
	RET
HandleDown:
	LD DE,-BREAK
	LD (Throttle),DE
	RET
HandleSpace:
	; Handle space key press by accelerating the jetski.
	LD DE,ACCELERATION
	LD (Throttle),DE
	RET
HandleEnter:
	; Handle enter key press by resetting the game or performing another action.
	RET

HandleLeftRelease:
	LD DE,0
	LD (Steer),DE
	RET

HandleRightRelease:
	LD DE,0
	LD (Steer),DE
	RET

HandleUpRelease:
	LD DE,0
	LD (Throttle),DE
	RET

HandleDownRelease:
	LD DE,0
	LD (Throttle),DE
	RET

HandleSpaceRelease:
	LD DE,0
	LD (Throttle),DE
	RET

HandleEnterRelease:
	; Handle enter key release by resetting the game or performing another action.
	RET

UpdateSprites:
	; Update the sprites based on the player's position, speed, etc. 
	; For example, you could move enemy sprites towards the player, animate the player's sprite based on speed, etc.
	
	RET

CourseName:
	DEFW 0	; Pointer to the course name string
CourseDifficulty:
	DEFB 0	; Difficulty level of the course (0-255)
CourseSegmentCount:
	DEFW 0	; Number of segments in the course
CourseSegmentPtr:
	DEFW 0	; Pointer to the array of track segments for the course
Segment:
	DEFW 0	; Current segment index


ElapsedTime:
	DEFW 0	; in seconds
ElapsedTimeFrames:
	DEFB 0	; in frames, for sub-second timing
WorldPosX:
	DEFW 0	; from center of segment, in cm
WorldPosZ:
	DEFW 0	; from beginning of segment, in cm
Yaw:
	DEFB 0	; player's angle, 0-255 representing 0-360 degrees
Steer:
	DEFW 0	; player's steering, in cm/s
Throttle:
	DEFW 0	; player's throttle, in 8.8 fixed-point, cm/frame^2
Velocity:
	DEFW 0	; player's speed, in 8.8 fixed-point cm/frame


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

; With tiles, always skip number 0 when making sprites
BoatSpriteList: ; Different scales of boat sprites for different distances from the viewer
	db 5 ; Number of different boat sprites
	defw BoatSprite1, BoatSprite2, BoatSprite3, BoatSprite4, BoatSprite5
; Each boat sprite is a different combination of 16x16 tiles, arranged in rows and columns
BoatSprite1: ; Closest, most detailed boat sprite (uses 16 tiles, 4x4)
	db 4,4 ; 4 columns, 4 rows
	dw -0,1,2,0 ; top row of tiles
	dw 0,17,18,0 ; second row of tiles
	dw 32,33,34,35 ; third row of tiles	
	dw 48,49,50,51 ; bottom row of tiles
BoatSprite2: ; Medium distance boat sprite (uses 12 tiles, 3x4)
	db 3,4 ; 3 columns, 4 rows
	dw 0,5,6 ; top row of tiles
	dw 20,21,22 ; second row of tiles
	dw 36,37,38 ; third row of tiles
	dw 52,53,54 ; bottom row of tiles
BoatSprite3: ; Far distance boat sprite (uses 9 tiles, 3x3)
	db 3,3 ; 3 columns, 3 rows
	dw 23,24,25 ; top row of tiles
	dw 39,40,41 ; middle row of tiles
	dw 55,56,57 ; bottom row of tiles
BoatSprite4: ; Farthest, least detailed boat sprite (uses 6 tiles, 2x3)
	db 2,3 ; 2 columns, 3 rows
	dw 26,27 ; top row of tiles
	dw 42,43 ; middle row of tiles
	dw 58,59 ; bottom row of tiles
BoatSprite5: ; Very far distance boat sprite (uses 4 tiles, 2x2)
	db 2,2 ; 2 columns, 2 rows
	dw 44,45 ; top row of tiles
	dw 60,61 ; bottom row of tiles

BuoySpriteList: ; Different scales of buoy sprites for different distances from the viewer
	db 4 ; Number of different buoy sprites
	defw BuoySprite1, BuoySprite2, BuoySprite3, BuoySprite4
; Each buoy sprite is a single 16x16 tile
TreeTileBase EQU 128 ; Base tile index for tree sprites in the tile set
BuoySprite1: ; Closest, most detailed buoy sprite
	db 1,1 ; 1 column, 1 row
	dw TreeTileBase+8+6
BuoySprite2: ; Medium distance buoy sprite
	db 1,1 ; 1 column, 1 row
	dw TreeTileBase+6
BuoySprite3: ; Far distance buoy sprite
	db 1,1 ; 1 column, 1 row
	dw TreeTileBase+8+7
BuoySprite4: ; Farthest, least detailed buoy sprite
	db 1,1 ; 1 column, 1 row
	dw TreeTileBase+7

TreeSpriteList: ; Different scales of tree sprites for different distances from the viewer
	db 5 ; Number of different tree sprites
	defw TreeSprite1, TreeSprite2, TreeSprite3, TreeSprite4, TreeSprite5
; Each tree sprite is a different combination of 16x16 tiles, arranged in rows and columns
TreeSprite1: ; Closest, most detailed tree sprite (uses 8 tiles, 2x4)
	db 2,4 ; 2 columns, 4 rows
	dw TreeTileBase+0, TreeTileBase+1 ; top row of tiles
	dw TreeTileBase+8, TreeTileBase+9 ; second row of tiles
	dw TreeTileBase+16, TreeTileBase+17 ; third row of tiles	
	dw TreeTileBase+24, 0 ; bottom row of tiles
TreeSprite2: ; Medium distance tree sprite (uses 8 tiles, 2x4)
	db 2,4 ; 2 columns, 4 rows
	dw TreeTileBase+2, TreeTileBase+3 ; top row of tiles
	dw TreeTileBase+10, TreeTileBase+11 ; second row of tiles
	dw TreeTileBase+18, TreeTileBase+19 ; third row of tiles	
	dw TreeTileBase+26, 0 ; bottom row of tiles
TreeSprite3: ; Far distance tree sprite (uses 6 tiles, 2x3)
	db 2,3 ; 2 columns, 3 rows
	dw TreeTileBase+12, TreeTileBase+13 ; top row of tiles
	dw TreeTileBase+20, TreeTileBase+21 ; middle row of tiles	
	dw TreeTileBase+28, 0 ; bottom row of tiles
TreeSprite4: ; Farthest, least detailed tree sprite (uses 2 tiles, 1x2)
	db 1,2 ; 1 columns, 2 rows
	dw TreeTileBase+22 ; top row of tiles
	dw TreeTileBase+30 ; bottom row of tiles
TreeSprite5: ; Very far distance tree sprite (uses 2 tiles, 1x2)
	db 1,2 ; 1 column, 2 rows
	dw TreeTileBase+23 ; top row of tiles
	dw TreeTileBase+31 ; bottom row of tiles


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
PlayerPalette:
	incbin "img/player.ztp"
PlayerPaletteSize EQU $-PlayerPalette
BgPalette:
	incbin "img/bg.ztp"
BgPaletteSize EQU $-BgPalette
TreePalette:
	incbin "img/tree.ztp"
TreePaletteSize EQU $-TreePalette
RampPalette:
	incbin "img/ramp.ztp"
	ds 24	; Pad the pallete to 16 entries (32 bytes) since the hardware reads in 16 entry chunks
RampPaletteSize EQU $-RampPalette
NumbersPalette:
	incbin "img/numbers.ztp"
	ds 16	; Pad the palette to 16 entries (32 bytes) since the hardware reads in 16 entry chunks
NumbersPaletteSize EQU $-NumbersPalette
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