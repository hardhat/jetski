; Keyboard input
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
	CP KB_KEY_M
	CALL Z,HandleM
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
HandleM:
	; Handle M key press by performing a specific action.
	LD A,SEMIHOST_PRINT_STRING
	LD HL,DbgMsgExiting
	OUT (0x10),A
	LD A,SEMIHOST_EXIT   ; Exits emulator
	LD L,3
	OUT (0x10),A
	RET
DbgMsgExiting: 
	DB "Exiting early...\n",0

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

keyboard_error_message:
	DB "Error reading keyboard", 13, 10
keyboard_error_message_len EQU $-keyboard_error_message

keyboard_buffer:
    DS 16
