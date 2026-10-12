; Player physics and course progress
	DEFC ACCELERATION = 75	; in 8.8 fixed-point cm/frame^2
	DEFC COAST = 25
	DEFC BREAK = 150
	DEFC MAX_SPEED = 46*256	; in 8.8 fixed-point cm/frame (about 100 km/h)
	DEFC MOUNTAIN_PERIOD = 320*64	; The mountain tilemap repeats every 320 px
	DEFC LATERAL_LIMIT = 1000*16	; Furthest the boat can get from the segment centre, in 1/16 cm

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
	; Move forward based on the velocity
	LD HL,(WorldPosZ)
	ADD HL,DE
	LD (WorldPosZ),HL
	PUSH DE
	CALL UpdateMountainScroll ; DE = distance travelled this frame
	POP DE
	CALL UpdateLateralPosition
	; Look for end of segment; loop since one frame can cross several short segments
CheckSegmentEnd:
	LD HL,(Segment)
	ADD HL,HL
	ADD HL,HL ; HL = segment*4 { int8_t curve; int16_t length; uint8_t flags; }
	LD DE,(CourseSegmentPtr)
	ADD HL,DE ; HL = pointer to current segment
	INC HL ; Skip curve
	LD E,(HL) ; Get length of segment
	INC HL
	LD D,(HL) ; DE = segment length
	LD HL,(WorldPosZ)
	OR A
	SBC HL,DE ; HL = WorldPosZ - segment length
	JR C,DoneSegmentCheck ; If we haven't reached the end of the segment, we're done
	; Carry the remainder into the next segment
	LD (WorldPosZ),HL
	LD HL,(Segment)
	INC HL
	LD DE,(CourseSegmentCount)
	PUSH HL
	OR A
	SBC HL,DE
	POP HL
	JR C,SegmentIndexSet
	LD HL,0 ; Past the last segment: loop back to the start of the course
SegmentIndexSet:
	LD (Segment),HL
	JR CheckSegmentEnd
DoneSegmentCheck:
	; Update elapsed time
	LD HL,(ElapsedTimeFrames)
	INC HL
	LD (ElapsedTimeFrames),HL
	LD A,L
	CP 60
	JR C,DoneTimeUpdate
	LD A,0
	LD (ElapsedTimeFrames),A	; Reset the lower byte of the frame counter
	LD (ElapsedTimeFrames+1),A	; Reset the upper byte of the frame counter
	LD HL,(ElapsedTime)
	INC HL
	LD (ElapsedTime),HL
DoneTimeUpdate:

	RET

; Slides the boat sideways: steering scales with speed, and the segment's curve pushes it outward.
; WorldPosXFine is in 1/16 cm, positive to the right; WorldPosX is its whole-cm part.
UpdateLateralPosition:
	LD HL,(Velocity)
	ADD HL,HL
	LD L,H
	LD H,0 ; Steering speed: velocity/128 in 1/16 cm, i.e. an eighth of the forward speed
	LD BC,(Steer)
	LD A,B
	OR C
	JR Z,@NoSteer
	BIT 7,B
	JR Z,@SteerDone
	XOR A
	SUB L
	LD L,A
	SBC A,A
	SUB H
	LD H,A
	JR @SteerDone
@NoSteer:
	LD HL,0
@SteerDone:
	PUSH HL
	LD HL,(Segment)
	ADD HL,HL
	ADD HL,HL ; HL = segment*4 { int8_t curve; int16_t length; uint8_t flags; }
	LD BC,(CourseSegmentPtr)
	ADD HL,BC
	LD A,(HL) ; curve
	OR A
	JR Z,@NoDrift
	INC HL
	LD C,(HL)
	INC HL
	LD B,(HL)
	PUSH BC ; segment length
	LD C,A ; keep the sign of the curve
	JP P,@DriftAbs
	NEG
@DriftAbs:
	PUSH BC
	LD DE,(Velocity)
	LD E,D
	LD D,0 ; DE = dz
	CALL DE_Times_A ; A:HL = dz * |curve|
	EX DE,HL
	LD A,(Velocity+1)
	CALL DE_Times_A ; A:HL = dz^2 * |curve|
	ADD HL,HL
	RLA ; x2 gives 4x the physical outward drift (|curve|*dz^2/(8*length) cm), in 1/16 cm
	POP DE ; E = signed curve
	POP BC ; BC = segment length
	PUSH DE
	CALL Div24_16
	POP DE
	LD A,E
	OR A
	JP P,@DriftSigned ; Positive curve is a left turn, which throws the boat to the right
	XOR A
	SUB L
	LD L,A
	SBC A,A
	SUB H
	LD H,A
@DriftSigned:
	POP DE ; steering
	ADD HL,DE
	JR @ApplyLateral
@NoDrift:
	POP HL
@ApplyLateral:
	LD DE,(WorldPosXFine)
	ADD HL,DE
	LD DE,LATERAL_LIMIT
	OR A
	SBC HL,DE
	BIT 7,H
	JR NZ,@BelowMax
	LD HL,0 ; Clamp to +limit
@BelowMax:
	ADD HL,DE
	ADD HL,DE ; HL + limit is negative only below -limit
	BIT 7,H
	JR Z,@AboveMin
	LD HL,0 ; Clamp to -limit
@AboveMin:
	OR A
	SBC HL,DE
	LD (WorldPosXFine),HL
	LD B,4
@LateralDown:
	SRA H
	RR L
	DJNZ @LateralDown
	LD (WorldPosX),HL
	RET

; Out: HL = velocity in km/h. 60 frames/s * 0.036 km/h per cm/s = 2.16 km/h per cm/frame, approximated as 69/8192 of the 8.8 velocity.
VelocityToKmh:
	LD DE,(Velocity)
	LD A,69
	CALL DE_Times_A
	LD L,H
	LD H,A
	LD B,5
@KmhShift:
	SRL H
	RR L
	DJNZ @KmhShift
	RET

; Pans the mountains by the heading change over the current segment: curve/32 rad * 208 px/rad, in 1/64 px.
; In: DE = distance travelled this frame in cm
UpdateMountainScroll:
	LD HL,(Segment)
	ADD HL,HL
	ADD HL,HL ; HL = segment*4 { int8_t curve; int16_t length; uint8_t flags; }
	LD BC,(CourseSegmentPtr)
	ADD HL,BC
	LD A,(HL) ; curve
	OR A
	RET Z
	INC HL
	LD C,(HL)
	INC HL
	LD B,(HL)
	PUSH BC ; segment length
	LD C,A ; keep the sign of the curve
	JP P,@CurveAbs
	NEG
@CurveAbs:
	PUSH BC
	CALL DE_Times_A ; A:HL = dz * |curve|
	EX DE,HL
	LD A,13
	CALL DE_Times_A ; x13 here and x32 below make the 416 = 6.5 px * 64
	LD B,5
@Mul32:
	ADD HL,HL
	RLA
	DJNZ @Mul32
	POP DE ; E = signed curve
	POP BC ; BC = segment length
	PUSH DE
	CALL Div24_16 ; HL = |curve|*dz*416/length
	POP DE
	LD A,E
	LD DE,(ScrollMountainFine)
	OR A
	JP M,@PanRight
	EX DE,HL ; Positive curve turns left, so the scenery moves right and the view scrolls left
	OR A
	SBC HL,DE
	JR NC,@PanStore
	LD DE,MOUNTAIN_PERIOD
	ADD HL,DE
	JR @PanStore
@PanRight:
	ADD HL,DE
	LD DE,MOUNTAIN_PERIOD
	OR A
	SBC HL,DE
	JR NC,@PanStore
	ADD HL,DE
@PanStore:
	LD (ScrollMountainFine),HL
	LD B,6
@PanDown:
	SRL H
	RR L
	DJNZ @PanDown
	LD (ScrollMountain),HL
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
	DEFW 0	; in frames, for sub-second timing
WorldPosX:
	DEFW 0	; from center of segment, in cm, positive to the right
WorldPosXFine:
	DEFW 0	; WorldPosX in 1/16 cm
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
ScrollMountain:
	DEFW 0	; Horizontal scroll position for the mountain layer, in pixels (0-319)
ScrollMountainFine:
	DEFW 0	; ScrollMountain in 1/64 px, wrapping at MOUNTAIN_PERIOD
