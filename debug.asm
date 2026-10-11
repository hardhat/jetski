; Debug output over the #SER0 serial device
SerialPortName:
	DB "#SER0", 0
SerialPort:
	DB 0

DbgSerial:
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH AF
	LD (SerialMsg),A
	LD A,(SerialPort)
	LD H,A
	LD DE,SerialMsg
	LD BC,1
	WRITE
	POP AF
	POP HL
	POP DE
	POP BC
	RET

SerialMsg:
	DB 0

DbgA:
	PUSH AF
	RRCA
	RRCA
	RRCA
	RRCA
	AND 15
	CP 10
	JR C,@DbgA1
	ADD A,7
@DbgA1:
	ADD A,48	;'0'
	CALL DbgSerial
	POP AF
	PUSH AF
	AND 15
	CP 10
	JR C,@DbgA2
	ADD A,7
@DbgA2:
	ADD A,48	;'0'
	CALL DbgSerial ; Send to the debug output port
	POP AF
	RET

DbgHL:
	PUSH HL
	PUSH AF
	LD A,H
	CALL DbgA
	LD A,L
	CALL DbgA
	POP AF
	POP HL
	RET

DbgBC:
	PUSH BC
	PUSH AF
	LD A,B
	CALL DbgA
	LD A,C
	CALL DbgA
	POP AF
	POP BC
	RET

DbgDE:
	PUSH DE
	PUSH AF
	LD A,D
	CALL DbgA
	LD A,E
	CALL DbgA
	POP AF
	POP DE
	RET

DbgMsg:
	EX (SP),HL
	PUSH AF
@DbgMsgLoop:
	LD A,(HL)
	OR A
	JR Z,@DbgMsgDone
	CALL DbgSerial
	INC HL
	JR @DbgMsgLoop
@DbgMsgDone:
	POP AF
	EX (SP),HL
	RET
