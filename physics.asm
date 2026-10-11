; Player physics and course progress
	DEFC ACCELERATION = 75	; in 8.8 fixed-point cm/frame^2
	DEFC COAST = 25
	DEFC BREAK = 150
	DEFC MAX_SPEED = 46*256	; in 8.8 fixed-point cm/frame (about 100 km/h)
	DEFC MOUNTAIN_PERIOD = 320*64	; The mountain tilemap repeats every 320 px

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
	CALL UpdateMountainScroll ; DE = distance travelled this frame
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
	; TODO steering and curve handling

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
ScrollMountain:
	DEFW 0	; Horizontal scroll position for the mountain layer, in pixels (0-319)
ScrollMountainFine:
	DEFW 0	; ScrollMountain in 1/64 px, wrapping at MOUNTAIN_PERIOD
