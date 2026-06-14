; z80 math functions for the simulation in 8.8 fixed point format (8 bits for the fraction)
; all functions assume the input is in the range of 2047 and -2048, and will return a result in the same range (except for multiplication which can return up to 4095)
; the functions are implemented using lookup tables and linear interpolation for speed, so they are not perfectly accurate, but they are good enough for our purposes.
multi8_8:
    ; multiplies two 8.8 fixed point numbers, returns a 8.8 fixed point number
    ; input: a in hl, b in de
    ; output: result in hl
    ld a, h
    or l
    jr z, mult_zero
    ld a, d
    or e
    jr z, mult_zero

    ; multiply the two numbers as integers, then shift right by 8 to get the fixed point result
    ld b,h
    ld c,l
    call BC_Times_DE
    ; now we have the result in b:hl:a so just return with h.l as the result
    RET

mult_zero:
    ld hl, 0
    ret

; See https://learn.cemetech.net/index.php/Z80:Advanced_Math for below

; Mutliply a 16-bit number in DE by an 8-bit number in A, returning the 24-bit result in A:HL (DE is unchanged)
    PUBLIC DE_Times_A
 DE_Times_A:      ; AHL = DE × A
       ld hl,0      ; Use HL to store the product
       ld b,8       ; Eight bits to check
       ld c,h
   @loop:
       add hl,hl
       adc a,a      ; Check most-significant bit of accumulator
       jr nc,@skip  ; If zero, skip addition
       add hl,de
       adc a,c      ;add in overflow as needed.
   @skip:
       djnz @loop
       ret

; =============================================================================
; Routine: Div24_16
; Function: Divides a 24-bit unsigned integer by a 16-bit unsigned integer.
; Inputs:   A:HL = 24-bit Dividend
;           BC   = 16-bit Divisor (must be non-zero)
; Outputs:  A:HL = 24-bit Quotient
;           DE   = 16-bit Remainder
; Destroys: IY
; Notes:    BC is preserved (divisor)
; =============================================================================
    PUBLIC Div24_16
Div24_16:
    ld de, 0        ; Clear the remainder accumulator

    ld ixl, 24
   

@loop:
    ; 1. Shift the 24-bit dividend/quotient left by 1 bit.
    ; The Most Significant Bit (MSB) shifts out into the Carry flag.
    add hl, hl      ; Shift HL left, MSB of HL → Carry
    rla             ; Shift A left, Carry → bit 0 of A, MSB of A → Carry

    ; 2. Shift the Carry flag into the 16-bit remainder
    ex de, hl       ; remainder → HL
    adc hl, hl      ; remainder <<= 1, MSB of dividend → bit 0

    ; 3. Trial subtraction of the divisor from the remainder
    or a            ; Clear Carry before subtraction
    sbc hl, bc      ; HL = remainder - divisor; C=0 on success, C=1 on borrow

    jr nc, @skip    ; No borrow → subtraction succeeded

    ; 4. Restore remainder on failure.
    ; Note: add hl,bc here always sets Carry (the 16-bit-wrapped value + divisor
    ; overflows 16 bits), so Carry=1 on failure and Carry=0 on success at @skip.
    add hl, bc

@skip:
    ex de, hl       ; remainder → DE, quotient → HL

    ; 5. Inject the quotient bit.
    ; Carry=0 on success, Carry=1 on failure. ccf inverts so:
    ;   success → C=1 → keep the inc (bit=1)
    ;   failure → C=0 → dec undoes the inc (bit=0)
    ; add hl,hl at step 1 guarantees bit 0 of L is 0 before inc.
    ccf
    inc l
    jr c, @bit0
    dec l
@bit0:
    dec ixl
    jr nz,@loop
    ret


; ======================================================================
; 16-bit ÷ 8-bit Divide (16-bit Quotient, 8-bit Remainder)
; Inputs:  HL = Dividend
;          D = Divisor
; Outputs: HL = Quotient, A = Remainder
; Destroys: A, B
; ======================================================================
    PUBLIC Div_HL_D
 Div_HL_D:            ; HL = HL ÷ D, A = remainder
       XOR    A         ; Clear upper eight bits of AHL
       LD     B, 16     ; Sixteen bits in dividend
   @loop:
       ADD    HL, HL    ; Do a SLA HL. If the upper bit was 1, the c flag is set
       RLA              ; This moves the upper bits of the dividend into A
       JR     C, @overflow
       CP     D         ; Check if we can subtract the divisor
       JR     C, @skip  ; Carry means D > A
   @overflow:
       SUB    D         ; Do subtraction for real this time
       INC    L         ; Set the next bit of the quotient (currently bit 0)
   @skip:
       DJNZ   @loop
       RET

; =====================================================================
; 16-bit * 16-bit Multiply (24-bit Result)
; Inputs:  BC = Multiplier
;          DE = Multiplicand
; Outputs: B:HL:A = 24-bit Product (HL = high 16 bits, A = low 8 bits)
; Destroys: BC
; =====================================================================
    PUBLIC BC_Times_DE
BC_Times_DE:
;  BC*DE->BHLA
   	ld a,b
   	ld hl,0
   	ld b,h
   	add a,a \ jr nc,$+5 \ ld h,d \ ld l,e
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,b
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,b
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,b
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,b
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,b
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,b
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,b
   	push hl
   	ld h,b
   	ld l,b
   	ld b,a
   	ld a,c
   	ld c,h
   	add a,a \ jr nc,$+5 \ ld h,d \ ld l,e
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,c
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,c
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,c
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,c
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,c
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,c
   	add hl,hl \ rla \ jr nc,$+4 \ add hl,de \ adc a,c    
   	pop de
   	ld c,a
   	ld a,l
   	ld l,h
   	ld h,c
   	add hl,de
   	ret nc
   	inc b   ; overflow in b
   	ret

; =====================================================================
; 16-bit * 16-bit Multiply (24-bit Result)
; Inputs:  BC = Multiplier
;          DE = Multiplicand
; Outputs: B:HL:A = 24-bit Product (HL = high 16 bits, A = low 8 bits)
; Destroys: BC
; =====================================================================
    PUBLIC DE_Div_BC_88
 DE_Div_BC_88:
   ;Inputs:
   ;     DE,BC are 8.8 Fixed Point numbers
   ;Outputs:
   ;     DE is the 8.8 Fixed Point result (rounded to the least significant bit)
       ld a,d
       xor b
       push af
       call m,@negDE
       call @div8sub
       pop af
       ret p
   @negDE:
       xor a
       sub e
       ld e,a
       sbc a,a
       sub d
       ld d,a
       ret
   @div8sub:
       ld a,8
       ld hl,0
   @Loop1:
       rl d
       adc hl,hl
       sbc hl,bc
       jr nc,$+3
   	add hl,bc
       dec a
       jr nz,@Loop1
       ld d,e
       ld e,a
       ld a,16
  	jp $+6
   @DivLoop:
       add hl,bc
       dec a
       ret z
       sla e
       rl d
       adc hl,hl
   	jr c,@overflow
       sbc hl,bc
       jr c,@DivLoop
       inc e
       jp @DivLoop+1
   @overflow:
   	or a
   	sbc hl,bc
   	inc e
   	jp @DivLoop

seed1_0:
	dw 12345
seed1_1:
	dw 0x5678
seed2_0:
	dw 0x9ABC
seed2_1:
	dw 0xDEF0

    PUBLIC rand16
rand16:
   ;Inputs:
   ;   seed1
   ;   seed2>0
   ;Output:
   ;   HL
   ;Destroys:
   ;   A,BC,DE. Could all be used as 'less random' options, too.
   ;Notes:
   ;   Tested and passes all CAcert Labs tests.
   ;   Has a period of 18,446,744,069,414,584,320 (roughly 18.4 quintillion)
   ;   This would take over 11.3 million years at 15MHz to finish a full period.
   ;291cc, +32cc if not using smc
   ;58 bytes, +2 if not using smc
   ;;lcg
	ld hl,(seed1_0)
	ld de,(seed1_1)

       ld b,h
       ld c,l
       add hl,hl \ rl e \ rl d
       add hl,hl \ rl e \ rl d
       inc l
       add hl,bc
       ld (seed1_0),hl
       ld hl,(seed1_1)
       adc hl,de
       ld (seed1_1),hl
       ex de,hl
   ;;lfsr
       ld hl,(seed2_0)
       ld bc,(seed2_1)

       add hl,hl
       rl c
       rl b
       ld (seed2_1),bc
       sbc a,a
       and %11000101
       xor l
       ld l,a
       ld (seed2_0),hl
       ex de,hl
       add hl,bc
       ret

;Note that:
;   sin(x) : x-85x^3/512+x^5/128 is within 8 bits of accuracy on [-pi/2,pi/2]
;   cos(x) : 1-x^2/2+5x^4/128 is within 8 bits of accuracy on [-pi/2,pi/2] for almost all values
;======================================================================
;Inputs:
;   DE is an 8.8 fixed point number representing an angle in radians, where 256 is a full circle, so 64 is pi/2, 128 is pi, etc.
;sine_88 and cosine_88 return the sine and cosine of the input angle, respectively, as 8.8 fixed point numbers in HL. The functions use the above polynomial approximations for sine and cosine, and are accurate enough for our purposes.
;======================================================================
    PUBLIC sine_88
sine_88:
   ;Inputs: de
       push de
       sra d \ rr e
       ld b,d \ ld c,e
       call BC_Times_DE
       push hl     ;x^2/4
       sra h \ rr l
       ex de,hl
       ld b,d \ ld c,e
       call BC_Times_DE
       sra h \ rr l
       inc h
       ex (sp),hl    ;x^4/128+1 is on stack, HL=x^2/4
       xor a
       ld d,a
       ld b,h
       ld c,l
       add hl,hl \ rla
       add hl,hl \ rla
       add hl,bc \ adc a,d
       ld b,h
       ld c,l
       add hl,hl \ rla
       add hl,hl \ rla
       add hl,hl \ rla
       add hl,hl \ rla
       add hl,bc \ adc a,d
       ld e,l
       ld l,h
       ld h,a
       rl e
       adc hl,hl
       rl e
       jr nc,$+3
       inc hl
   
       pop de
       ex hl,de
       or a
       sbc hl,de
       ex de,hl
       pop bc
       jp BC_Times_DE