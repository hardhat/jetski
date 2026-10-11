; HUD / debug overlay and decimal printing into the layer 0 tilemap
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

	;LD HL,HudMsg
	;CALL PrintString

	RET

;HudMsg:
;	DEFB "Hello: 12/3",0

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

PrintString:	; Print a null-terminated string at the current cursor position
	LD DE,(Cursor)
@PrintStringLoop:
	LD A,(HL)
	CP 0
	RET Z ; End of string
	; Remap 0-9, ':' and '/' to the character set used at 192
	; Remap A-Z or a-z to the alphabet at 192+34 for 'A' or 'a'
	CP ':'
	JR Z,@PrintStringRemapColon
	CP '/'
	JR Z,@PrintStringRemapSlash
	CP 'A'
	JR NC,@PrintStringRemapAlpha
	CP '0'
	JR C,@PrintStringPrint ; before '0' don't remap
	CP '9'+1
	JR C,@PrintStringRemapDigit
	JR @PrintStringPrint ; Let through all others without remapping

@PrintStringRemapDigit:
	ADD A,192-'0'
	JR @PrintStringPrint

@PrintStringRemapColon:
	ADD A,192+10-':' 
	JR @PrintStringPrint

@PrintStringRemapSlash:
	ADD A,192+11-'/' 
	JR @PrintStringPrint

@PrintStringRemapAlpha:
	CP 'z'+1
	JR NC,@PrintStringPrint	; after 'z' don't remap
	AND 255-('a'-'A')	; Convert lowercase to uppercase
	ADD A,192+34-'A'
	;JR @PrintStringPrint
@PrintStringPrint:
	LD (DE),A
	INC DE
	INC HL
	JR @PrintStringLoop

Cursor:
	DEFW 0
