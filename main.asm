; jetski - Z80 asm code for the main game loop
	include "zvb_hardware_h.asm"
	include "zos_sys.asm"
	include "zos_err.asm"
	include "zos_keyboard.asm"
	include "zos_video.asm"

	; Define semihosting constants for the Z80 emulator.  
	; Put the corresponding value in register A and do `OUT (0x10),A` to trigger the semihosting call.
    SEMIHOST_EXIT          = 0x00; Exit emulator, L as error code
    SEMIHOST_PRINT_CHAR    = 0x01; Print register L as a character
    SEMIHOST_PRINT_INT     = 0x02; Print HL as a 16-bit decimal integer
    SEMIHOST_PRINT_STRING  = 0x03; Print null-terminated string at memory address HL
    SEMIHOST_READ_CHAR     = 0x04; Read a character from standard input into A
    SEMIHOST_READ_STRING   = 0x05; Read null-terminated string from stdin into memory at HL
    SEMIHOST_PRINT_HEX     = 0x06; Print HL as hexadecimal
    SEMIHOST_READ_INT      = 0x07; Read 16-bit integer from stdin into HL
    SEMIHOST_COUNTER_START = 0x08; Start t-states counter: L = counter ID (0-7)
    SEMIHOST_COUNTER_STOP  = 0x09; Stop counter and print elapsed t-states: L = counter ID
    SEMIHOST_COUNTER_SPLIT = 0x0A; Split counter (print since last split, don't stop): L = counter ID
    SEMIHOST_VERSION       = 0xFF; Return semihost version in A

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
SpriteCenterX	EQU	160+16	; Screen centre x in sprite coordinates (sprites are offset by +16)
buffer	EQU 0xc000	;PAGE3_VADDR
bufferLen	EQU 0x3000

Start:
	LD BC,SerialPortName
	LD H, O_WRONLY
	OPEN
	LD (SerialPort),A ; File handle to serial port or error if negative. 

	CALL DbgMsg
	db "Starting jetski.asm", 13, 10, 0
	LD HL,MappedMem
	CALL DbgHL

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
	CALL StartRace

GameLoop:
	LD A,(GameState)
	ADD A,A
	LD E,A
	LD D,0
	LD HL,GameStateTable
	ADD HL,DE
	LD A,(HL)
	INC HL
	LD H,(HL)
	LD L,A
	LD DE,GameLoop
	PUSH DE ; The state handler runs one frame and returns to GameLoop
	JP (HL)

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

	LD A,(SerialPort)
	LD H,A
	CLOSE

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

	include "game.asm"
	include "input.asm"
	include "physics.asm"
	include "hud.asm"
	include "sprites.asm"
	include "debug.asm"
	include "dzx0_standard.asm"
	include "assets.asm"

