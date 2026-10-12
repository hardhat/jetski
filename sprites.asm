; Hardware sprite table, shore animation and perspective-scaled composite sprites
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

; Advance the shore one animation step per SHORE_CM_PER_STEP cm travelled, so it stops when the boat does.
UpdateShore:
	LD A,(Velocity+1) ; Whole cm/frame
	LD B,A
	LD A,(ShoreDistance)
	ADD A,B
@StepLoop:
	CP SHORE_CM_PER_STEP
	JR C,@StepsDone
	SUB SHORE_CM_PER_STEP
	PUSH AF
	CALL StepShore
	POP AF
	JR @StepLoop
@StepsDone:
	LD (ShoreDistance),A
	RET

StepShore:
	LD A,(Frame)
	CP 16
	JR Z,@Reset
	INC A
	LD (Frame),A
	LD HL,2 ; Slide 2 px down and 1 px left per step
	LD DE,-1
	JR @Apply
@Reset:
	XOR A
	LD (Frame),A
	LD HL,-32 ; Snap back one tile pitch
	LD DE,16
@Apply:
	LD (ShoreDY),HL
	LD (ShoreDX),DE
	LD A,(ShoreSides)
	LD C,A
	BIT 0,C
	JR Z,@NoLeft
	LD IX,(SpriteTileMap+2)	; Where the left shore sprite entries start
	LD A,(SpriteTileMap+4) ; How many entries there are
	LD B,A
	CALL StepShoreBlock
@NoLeft:
	BIT 1,C
	RET Z
	LD HL,(ShoreDX) ; The right shore is the mirror image, so it slides the other way in x
	XOR A
	SUB L
	LD L,A
	SBC A,A
	SUB H
	LD H,A
	LD (ShoreDX),HL
	LD IX,(SpriteTileMap+17)
	LD A,(SpriteTileMap+19)
	LD B,A

; In: IX = first sprite entry, B = entry count. Moves each entry by ShoreDX, ShoreDY; keeps C.
StepShoreBlock:
	LD A,B
	OR A
	RET Z
@Loop:
	LD L,(IX+sprite_y)
	LD H,(IX+sprite_y_msb)
	LD DE,(ShoreDY)
	ADD HL,DE
	LD (IX+sprite_y),L
	LD (IX+sprite_y_msb),H
	LD L,(IX+sprite_x)
	LD H,(IX+sprite_x_msb)
	LD DE,(ShoreDX)
	ADD HL,DE
	LD (IX+sprite_x),L
	LD (IX+sprite_x_msb),H
	LD DE,sprite_size
	ADD IX,DE
	DJNZ @Loop
	RET

; Switches the shore to the sides in the segment flags (SHORE_L / SHORE_R) when they change.
UpdateShoreSides:
	LD HL,(Segment)
	ADD HL,HL
	ADD HL,HL ; HL = segment*4 { int8_t curve; int16_t length; uint8_t flags; }
	LD DE,(CourseSegmentPtr)
	ADD HL,DE
	INC HL
	INC HL
	INC HL
	LD A,(HL) ; flags
	RRCA
	RRCA
	RRCA
	RRCA
	AND SHOW_LAND*3 ; bit 0 = shore on the left, bit 1 = on the right
	LD B,A
	LD A,(ShoreSides)
	CP B
	RET Z
	LD A,B

; In: A = shore sides. Rebuilds the land tiles and the edge sprites for those sides.
SetShoreSides:
	LD (ShoreSides),A
	XOR A
	LD (Frame),A
	LD A,(ShoreSides)
	CALL BuildShoreTiles
	LD DE,(SpriteTileMap+2)
	LD HL,TileMapShore
	LD A,(SpriteTileMap+4)
	LD B,A
	LD A,(ShoreSides)
	AND 1
	LD C,0
	CALL ResetShoreBlock
	LD DE,(SpriteTileMap+17)
	LD HL,TileMapShore
	LD A,(SpriteTileMap+19)
	LD B,A
	LD A,(ShoreSides)
	AND 2
	LD C,1
	CALL ResetShoreBlock
	; The right shore's sky sprites hide its edge sprites above the horizon, as the unmirrored sky sprites do on the left
	LD DE,(SpriteTileMap+22)
	LD HL,TileMapSky
	LD A,(SpriteTileMap+24)
	LD B,A
	LD A,(ShoreSides)
	AND 2
	LD C,1
	; Falls through

; In: DE = first sprite entry, HL = its tilemap, B = entry count, A = non-zero to show it, C = 1 to mirror it for a right shore.
ResetShoreBlock:
	OR A
	JR NZ,@Show
	LD L,B
	LD H,0
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL
	LD B,H
	LD C,L
	EX DE,HL
	LD E,L
	LD D,H
	INC DE
	LD (HL),0 ; An all-zero entry sits off screen
	DEC BC
	LDIR
	RET
@Show:
	LD A,B
	LD (ShoreCount),A
	LD A,C
	LD (ShoreMirror),A
	PUSH DE
	LD C,15
@RowLoop:
	LD B,20
@ColLoop:
	LD A,(HL)
	CP 0xff
	PUSH HL
	CALL NZ,InitSprite
	POP HL
	INC HL
	DJNZ @ColLoop
	DEC C
	JR NZ,@RowLoop
	POP IX
	LD A,(ShoreMirror)
	OR A
	RET Z
	LD A,(ShoreCount)
	LD B,A
@Mirror:
	LD HL,336 ; Column c at x = 16+16*c moves to column 19-c
	LD E,(IX+sprite_x)
	LD D,(IX+sprite_x_msb)
	OR A
	SBC HL,DE
	LD (IX+sprite_x),L
	LD (IX+sprite_x_msb),H
	SET 3,(IX+sprite_flags) ; flip x
	LD DE,sprite_size
	ADD IX,DE
	DJNZ @Mirror
	RET

; In: A = shore sides. Rewrites the land in rows SHORE_FIRST_ROW.. of both tilemap layers.
BuildShoreTiles:
	LD (ShoreSides),A
	LD IX,MappedMem+Layer0Offset+SHORE_FIRST_ROW*80
	LD HL,TileMapBg+SHORE_FIRST_ROW*20
	LD (ShoreSrc),HL
	LD A,SHORE_ROWS
	LD (ShoreRowsLeft),A
@Row:
	LD HL,(ShoreSrc)
	LD DE,19
	ADD HL,DE
	LD A,(HL) ; The last column of each row is plain water
	LD (ShoreWater),A
	LD B,0
@Water:
	LD A,(ShoreWater)
	LD C,0
	CALL PutShoreTile
	INC B
	LD A,B
	CP 20
	JR C,@Water
	LD A,(ShoreSides)
	BIT 0,A
	JR Z,@NoLeft
	LD B,0
@Left:
	LD HL,(ShoreSrc)
	LD E,B
	LD D,0
	ADD HL,DE
	LD A,(HL)
	LD C,0
	CALL PutShoreTile
	INC B
	LD A,B
	CP SHORE_LAND_COLS
	JR C,@Left
@NoLeft:
	LD A,(ShoreSides)
	BIT 1,A
	JR Z,@NoRight
	LD B,0
@Right:
	LD HL,(ShoreSrc)
	LD E,B
	LD D,0
	ADD HL,DE
	LD D,(HL) ; tile
	LD C,8 ; flip x
	PUSH BC
	LD A,19
	SUB B
	LD B,A
	LD A,D
	CALL PutShoreTile
	POP BC
	INC B
	LD A,B
	CP SHORE_LAND_COLS
	JR C,@Right
@NoRight:
	LD HL,(ShoreSrc)
	LD DE,20
	ADD HL,DE
	LD (ShoreSrc),HL
	LD DE,80
	ADD IX,DE
	LD A,(ShoreRowsLeft)
	DEC A
	LD (ShoreRowsLeft),A
	JR NZ,@Row
	RET

; In: IX = layer 0 address of the row, B = column, A = tile, C = attribute bits to add (flip x). Keeps BC.
PutShoreTile:
	PUSH BC
	PUSH IX
	POP HL
	LD E,B
	LD D,0
	ADD HL,DE
	LD (HL),A
	LD B,0 ; Palette from the tile number, as in the tilemap fill
	CP 64
	JR C,@Palette
	INC B
	CP 128
	JR C,@Palette
	INC B
	CP 160
	JR C,@Palette
	INC B
	CP 192
	JR C,@Palette
	INC B
@Palette:
	LD A,B
	ADD A,A
	ADD A,A
	ADD A,A
	ADD A,A
	OR C
	LD DE,Layer1Offset-Layer0Offset
	ADD HL,DE
	LD (HL),A
	POP BC
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

UpdateSprites:
	; Update the sprites based on the player's position, speed, etc. 
	; Start by zeroing out the sprite table for this frame
	LD HL,(SpriteTable)
	LD (NextSpriteEntry),HL	; Start of free sprites

	LD A,(SpriteTableCount) ; The sprite table output
	OR A
	JR Z,NoSpritesToUpdate
	EX DE,HL ; DE = start of sprite table, HL = number of sprites to update
	LD H,0
	LD L,A
	ADD HL,HL
	ADD HL,HL
	ADD HL,HL ; A*8 for the size of each sprite entry
	LD B,H
	LD C,L
	EX DE,HL ; HL = start of sprite table
	LD (HL),0
	LD D,H
	LD E,L
	INC DE
	LDIR
NoSpritesToUpdate:
	XOR A
	LD (SpriteTableCount),A
	; Now ready to build the sprites.
	CALL BuildCourseSegmentSprites
	CALL BuildPlayerSprite

	RET

BuildCourseSegmentSprites:
	; Build sprites for the current course segment based on the player's position and the segment's curve, etc. 
	; For now, just build some placeholder sprites to represent the course segments.

	; Sprites with a higher table index are drawn in front, so collect the next segments near to far
	; and then draw them far to near.
	; SegDist = total length of the segments from the current one up to the one being collected
	LD HL,0
	LD (SegDist),HL
	XOR A
	LD (SegDrawCount),A
	LD HL,SegDrawList
	LD (SegDrawPtr),HL
	LD HL,(Segment)
	LD (DrawSegment),HL
	LD C,5 ; Look at the next 5 segments for sprites to add
@CollectLoop:
	LD HL,(DrawSegment)
	ADD HL,HL
	ADD HL,HL ; HL = segment*4 { int8_t curve; int16_t length; uint8_t flags; }
	LD DE,(CourseSegmentPtr)
	ADD HL,DE ; HL = pointer to segment
	INC HL ; Skip curve
	LD E,(HL) ; Get length
	INC HL
	LD D,(HL)
	INC HL
	LD B,(HL) ; Get flags
	LD HL,(SegDist)
	ADD HL,DE
	JR C,@CollectDone ; Total no longer fits in 16 bits, so everything further is too far to see
	LD (SegDist),HL
	LD DE,(WorldPosZ)
	OR A
	SBC HL,DE ; HL = distance from the player to the end of this segment
	EX DE,HL
	LD HL,(SegDrawPtr)
	LD (HL),E ; Store z and flags in SegDrawList
	INC HL
	LD (HL),D
	INC HL
	LD (HL),B
	INC HL
	LD (SegDrawPtr),HL
	LD A,(SegDrawCount)
	INC A
	LD (SegDrawCount),A
	LD HL,(DrawSegment)
	INC HL
	LD DE,(CourseSegmentCount)
	PUSH HL
	OR A
	SBC HL,DE
	POP HL
	JR C,@DrawSegmentSet
	LD HL,0 ; Wrap around to the start of the course
@DrawSegmentSet:
	LD (DrawSegment),HL
	DEC C
	JR NZ,@CollectLoop
@CollectDone:
	CALL BuildCurveTable
	CALL BuildMarkerSprites

	LD A,(SegDrawCount)
	OR A
	RET Z
	LD C,A
@DrawLoop:
	LD HL,(SegDrawPtr) ; Walk the list backwards: farthest first
	DEC HL
	LD B,(HL) ; flags
	DEC HL
	LD D,(HL)
	DEC HL
	LD E,(HL) ; DE = distance to the end of this segment
	LD (SegDrawPtr),HL
	; For now, just add a sprite based on the flags as a placeholder
	; In the future, we can use the curve, length, and flags to determine what
	; sprites to add for the course segment, such as shore sprites, obstacle sprites, etc.
	PUSH BC
	LD B,D
	LD C,E ; BC = z distance to the end of this segment
	POP AF
	PUSH AF ; Get the flags into A
	; Trees stand beside the track on each side the segment flags mark as shore
	BIT 4,A ; SHORE_L
	JR Z,@NoLeftTree
	PUSH AF
	PUSH BC
	LD HL,-TREE_LATERAL
	LD DE,TreeSpriteList
	CALL AddGroundSprite
	POP BC
	POP AF
@NoLeftTree:
	BIT 5,A ; SHORE_R
	JR Z,@NoRightTree
	LD HL,TREE_LATERAL
	LD DE,TreeSpriteList
	CALL AddGroundSprite
@NoRightTree:
	; Next segment
	POP BC
	DEC C
	JP NZ,@DrawLoop

	RET

; Buoys mark both edges of the track every MARKER_SPACING cm.
BuildMarkerSprites:
	LD HL,(MarkerPhase)
	EX DE,HL
	LD HL,MARKER_SPACING*MARKER_COUNT
	OR A
	SBC HL,DE
	LD (MarkerZ),HL ; Start with the farthest so nearer buoys are drawn in front
	LD A,MARKER_COUNT
	LD (MarkerLeft),A
@Marker:
	LD BC,(MarkerZ)
	CALL AddMarkerPair
	LD HL,(MarkerZ)
	LD DE,MARKER_SPACING
	OR A
	SBC HL,DE
	LD (MarkerZ),HL
	LD A,(MarkerLeft)
	DEC A
	LD (MarkerLeft),A
	JR NZ,@Marker
	RET

; In: BC = distance ahead in cm.
AddMarkerPair:
	PUSH BC
	LD HL,-TRACK_HALF_WIDTH
	LD DE,BuoySpriteList
	CALL AddGroundSprite
	POP BC
	LD HL,TRACK_HALF_WIDTH
	LD DE,BuoySpriteList

; In: BC = distance ahead in cm, HL = lateral position in cm from the track centre, DE = composite sprite list.
AddGroundSprite:
	PUSH DE
	CALL ProjectGround
	POP HL
	RET C
	XOR A ; No shear
	JP AddScaledCompositeSprite

; In: BC = distance ahead in cm, HL = lateral position in cm from the track centre.
; Out: DE = x, BC = y in sprite coordinates; carry set if it is off screen.
ProjectGround:
	LD A,B
	OR C
	SCF
	RET Z
	PUSH HL
	PUSH BC
	CALL CurveAtZ
	EX DE,HL
	POP BC
	POP HL
	OR A
	SBC HL,DE ; The track centre has moved left by the curve shift
	PUSH HL
	; HORIZON=64 pixels, Y_WORLD=120 cm above horizon, DIST=208 (75 degree FOV), SCALE=35 for 1.0x scale
	; y = HORIZON + (Y_WORLD * DIST * SCALE) / z, and 120*208*35 = 0xD5480
	LD HL,0x5480
	LD A,0xD
	CALL Div24_16 ; HL = pixels below the horizon
	OR H
	JR NZ,@Far
	LD A,L
	LD H,0
	LD DE,64
	ADD HL,DE
	EX (SP),HL ; Stack = y, HL = lateral
	CALL LateralToScreenX
	POP BC
	RET
@Far:
	POP HL
	SCF
	RET

; Fills SegCurve with the end distance and sideways shift of the track centre for each listed segment.
; The shift is in cm with a gain of 1/16 folded in, positive when the track has moved left, and follows
; the heading of the track (8.8 radians, from the segment curve values) relative to the camera.
BuildCurveTable:
	LD A,(SegDrawCount)
	OR A
	RET Z
	LD (CurveLeft),A
	LD HL,0
	LD (CurveTheta),HL
	LD (CurveC),HL
	LD HL,(Segment)
	LD (CurveSeg),HL
	LD HL,SegCurve
	LD (CurvePtr),HL
	LD HL,SegDrawList
	LD (CurveListPtr),HL
	LD A,1
	LD (CurveFirst),A
@Next:
	LD HL,(CurveSeg)
	ADD HL,HL
	ADD HL,HL ; HL = segment*4 { int8_t curve; int16_t length; uint8_t flags; }
	LD DE,(CourseSegmentPtr)
	ADD HL,DE
	LD A,(HL)
	LD (CurveVal),A
	INC HL
	LD C,(HL)
	INC HL
	LD B,(HL) ; BC = segment length
	LD HL,(CurveListPtr)
	LD E,(HL)
	INC HL
	LD D,(HL) ; DE = distance to the end of this segment
	INC HL
	INC HL ; Skip the flags
	LD (CurveListPtr),HL
	LD HL,(CurvePtr)
	LD (HL),E
	INC HL
	LD (HL),D
	INC HL
	LD (CurvePtr),HL
	LD A,(CurveFirst)
	OR A
	JR Z,@FullSegment
	XOR A
	LD (CurveFirst),A
	; Only the part of the first segment ahead of the player counts: l = DE, q = l/length in 8.8
	LD (CurveL),DE
	LD H,D
	LD L,E
	LD A,H
	LD H,L
	LD L,0 ; A:HL = l * 256
	CALL Div24_16
	LD (CurveQ),HL
	LD B,H
	LD C,L
	LD DE,(CurveL)
	CALL BC_Times_DE ; HL = q * l / 256 = l^2 / length
	LD (CurveM),HL
	JR @Terms
@FullSegment:
	LD (CurveL),BC
	LD (CurveM),BC
	LD HL,256
	LD (CurveQ),HL
@Terms:
	; Shift from the heading on entry: theta * l / 256 / 16
	LD HL,(CurveTheta)
	LD A,H
	PUSH AF
	BIT 7,H
	CALL NZ,NegHL
	LD B,H
	LD C,L
	LD DE,(CurveL)
	CALL BC_Times_DE ; B:HL:A = |theta| * l
	LD A,B
	OR A
	JR Z,@NoSat
	LD HL,0x7FFF
@NoSat:
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	POP AF
	BIT 7,A
	CALL NZ,NegHL
	PUSH HL
	; Shift from turning within the segment: curve/32 rad * l^2 / length / 2 / 16, so |curve| * m / 1024
	LD A,(CurveVal)
	OR A
	JP P,@AbsCurve1
	NEG
@AbsCurve1:
	LD DE,(CurveM)
	CALL DE_Times_A
	LD L,H
	LD H,A
	SRL H
	RR L
	SRL H
	RR L
	LD A,(CurveVal)
	OR A
	CALL M,NegHL
	POP DE
	LD (CurveT1),DE
	ADD HL,DE
	LD DE,(CurveC)
	ADD HL,DE
	LD (CurveC),HL
	EX DE,HL
	LD HL,(CurvePtr)
	LD (HL),E
	INC HL
	LD (HL),D
	INC HL
	LD DE,(CurveT1)
	LD (HL),E
	INC HL
	LD (HL),D
	INC HL
	LD (CurvePtr),HL
	; Heading change over the part counted: curve * 8 * q / 256 in 8.8 radians
	LD A,(CurveVal)
	OR A
	JP P,@AbsCurve2
	NEG
@AbsCurve2:
	LD DE,(CurveQ)
	CALL DE_Times_A
	LD B,5
@ThetaShift:
	SRL H
	RR L
	DJNZ @ThetaShift
	LD A,(CurveVal)
	OR A
	CALL M,NegHL
	LD DE,(CurveTheta)
	ADD HL,DE
	LD (CurveTheta),HL
	LD HL,(CurveSeg)
	INC HL
	LD DE,(CourseSegmentCount)
	PUSH HL
	OR A
	SBC HL,DE
	POP HL
	JR C,@SegSet
	LD HL,0 ; Wrap around to the start of the course
@SegSet:
	LD (CurveSeg),HL
	LD A,(CurveLeft)
	DEC A
	LD (CurveLeft),A
	JP NZ,@Next
	RET

; In: BC = distance ahead in cm. Out: HL = sideways shift of the track centre there, positive to the left.
; Within a segment the shift follows C0 + T1*f + (C1 - C0 - T1)*f^2: T1 is the shift from the heading on entry,
; so a bend eases in from the heading it started with. f is the fraction of the segment, 0..1.
CurveAtZ:
	LD A,(SegDrawCount)
	OR A
	JR Z,@None
	LD (CurveLeft),A
	LD HL,0
	LD (CurveZ0),HL
	LD (CurveC0),HL
	LD HL,SegCurve
@Scan:
	LD E,(HL)
	INC HL
	LD D,(HL)
	INC HL
	LD (CurveZ1),DE
	PUSH HL
	EX DE,HL
	OR A
	SBC HL,BC
	JR NC,@Found
	POP HL
	LD E,(HL)
	INC HL
	LD D,(HL)
	INC HL
	INC HL
	INC HL ; Skip T1
	LD (CurveC0),DE
	LD DE,(CurveZ1)
	LD (CurveZ0),DE
	LD A,(CurveLeft)
	DEC A
	LD (CurveLeft),A
	JR NZ,@Scan
@None:
	LD HL,(CurveC0) ; Beyond the last listed segment, or nothing listed
	RET
@Found:
	POP HL
	LD E,(HL)
	INC HL
	LD D,(HL) ; DE = shift at the end of this segment
	INC HL
	LD A,(HL)
	INC HL
	LD H,(HL)
	LD L,A
	LD (CurveT1),HL
	PUSH DE
	LD HL,(CurveZ1)
	LD DE,(CurveZ0)
	OR A
	SBC HL,DE ; HL = segment length ahead of the previous end
	LD A,H
	OR L
	JR Z,@ZeroLength
	PUSH HL
	LD H,B
	LD L,C
	OR A
	SBC HL,DE ; HL = distance into the segment
	LD A,H
	LD H,L
	LD L,0 ; A:HL = distance * 256
	POP BC
	CALL Div24_16 ; HL = f in 8.8
	LD (CurveF),HL
	LD B,H
	LD C,L
	LD D,H
	LD E,L
	CALL BC_Times_DE ; HL = f^2 in 8.8
	LD (CurveF2),HL
	POP HL
	LD DE,(CurveC0)
	OR A
	SBC HL,DE
	LD DE,(CurveT1)
	OR A
	SBC HL,DE ; HL = C1 - C0 - T1
	LD DE,(CurveF2)
	CALL ScaleFrac
	PUSH HL
	LD HL,(CurveT1)
	LD DE,(CurveF)
	CALL ScaleFrac
	POP DE
	ADD HL,DE
	LD DE,(CurveC0)
	ADD HL,DE
	RET
@ZeroLength:
	POP DE
	LD HL,(CurveC0)
	RET

; In: HL = signed value, DE = fraction 0..256 in 8.8. Out: HL = HL * DE / 256.
ScaleFrac:
	LD A,H
	PUSH AF
	BIT 7,H
	CALL NZ,NegHL
	LD B,H
	LD C,L
	CALL BC_Times_DE
	POP AF
	BIT 7,A
	CALL NZ,NegHL
	RET

NegHL:
	XOR A
	SUB L
	LD L,A
	SBC A,A
	SUB H
	LD H,A
	RET

; Projects a point on the ground beside the track: screen offset = (lateral - WorldPosX) * pixels below the horizon / LATERAL_DIV.
; In: HL = lateral position in cm from the track centre, A = pixels below the horizon (0-255).
; Out: DE = x in sprite coordinates; carry set if it is off the side of the screen.
LateralToScreenX:
	LD B,A
	LD DE,(WorldPosX)
	OR A
	SBC HL,DE
	LD C,H ; Sign of the offset
	PUSH BC
	BIT 7,H
	JR Z,@Positive
	XOR A
	SUB L
	LD L,A
	SBC A,A
	SUB H
	LD H,A
@Positive:
	EX DE,HL
	LD A,B
	CALL DE_Times_A
	LD BC,LATERAL_DIV
	CALL Div24_16
	POP BC
	LD A,H
	OR A
	JR NZ,@OffScreen
	LD A,L
	CP 200
	JR NC,@OffScreen
	LD DE,SpriteCenterX
	BIT 7,C
	JR NZ,@Left
	ADD HL,DE
	JR @HaveX
@Left:
	EX DE,HL
	OR A
	SBC HL,DE
@HaveX:
	EX DE,HL
	OR A
	RET
@OffScreen:
	SCF
	RET

BuildPlayerSprite:
	; Build the player's sprite based on the player's position, speed, etc.

	LD DE,SpriteCenterX	; DE = x position in screen coordinates
	LD A,(Steer)
	ADD A,A ; Lean 2 pixels per row for each unit of steer
	LD BC,240-16 ; bottom of boat sprite is 16 pixels from the bottom of the screen
	LD HL,BoatSpriteList
	CALL AddScaledCompositeSprite

	RET

; =================================================================================================
; Adds a multisprite entry, scaled based on the y value of the sprite.  The sprites is anchored at the bottom center, so the x and y 
; position refer to the bottom center of the sprite.  The tile number is for the top left tile of the sprite, and the sprite is made 
; up of a grid of tiles as defined in the boat sprite list.  The scale is determined by which boat sprite is used, with larger sprites 
; used for closer objects and smaller sprites used for farther objects.
; Input: HL = pointer to the composite sprite definition which includes the {scale_count, scale_list[]} which point to {column_count, row_count, tile numbers[]} }
;         DE = x position of the sprite in screen coordinates
;         BC = y position of the sprite in screen coordinates
;         A = shear: signed pixels each row sits left of the row above it; 0 for upright sprites. The bottom row stays anchored.
; since sprits are displayed between y positions 64 and 240, we can use the y position to determine the scale of the sprite to use, with closer objects 
; (y closer to 240) using larger sprites and farther objects (y closer to 64) using smaller sprites.
AddScaledCompositeSprite:
	LD (SCS_Shear),A ; Sign-extend to 16 bits
	ADD A,A
	SBC A,A
	LD (SCS_Shear+1),A
	; CALL DbgMsg
	; DB "AddScaledCompositeSprite: HL=",0
	; CALL DbgHL
	; CALL DbgMsg
	; DB " y=",0
	; CALL DbgBC
	; CALL DbgMsg
	; DB " x=",0
	; CALL DbgDE
	; CALL DbgMsg
	; DB 13,10,0

	LD A,B
	CP 2
	RET NC ; y >= 512 is far below the screen; also keeps the scale maths within 16 bits
	LD A,(HL) ; Get the number of different scales for this sprite
	INC HL
	PUSH BC ; y position
	PUSH DE ; x position
	PUSH HL ; Save the pointer to the composite sprite definition for later use after we determine which scale to use
	PUSH AF ; Save the scale count for later use after we determine which scale to use
	; Determine which scale to use based on the y position in BC
	LD H,B
	LD L,C
	LD DE,-64
	ADD HL,DE
	BIT 7,H ; ADD HL,DE does not update the sign flag, so test the sign bit directly
	JP NZ,UseSmallestSprite ; If y < 64, use the smallest sprite
	EX DE,HL ; Adjusted y position in DE
	CALL DE_Times_A ; Get the scale index by dividing the adjusted y position by the range of y positions (240-64=176) and multiplying by the number of scales
	; Now DE is y pos - 64, and HL is DE*sprite_count
	LD D,176
	CALL Div_HL_D ; Divide by 176 to get the scale index
	; HL = q, 0 at the horizon up to count at the bottom of the screen.  Lists are ordered largest first, so index = count-1-q
	POP BC ; B=number of scales
	LD A,H
	OR A
	JR NZ,UseLargestSprite
	LD A,L
	CP B
	JR NC,UseLargestSprite ; q >= count: at or below the bottom of the water, use the largest sprite
	LD A,B
	DEC A
	SUB L
	LD L,A
	LD H,0
	JR UseScale
UseLargestSprite:
	LD HL,0
	JR UseScale
UseSmallestSprite:
	POP AF ; A = scale count; keeps the stack balanced with the PUSH AF above
	LD H,0
	LD L,A
	DEC L ; Use the last entry in the scale list (smallest sprite)
UseScale:
	ADD HL,HL ; Multiply by 2 for the size of each scale entry
	POP BC ; Get the table pointer back in BC
	ADD HL,BC ; Add the base address of the scale list to get the pointer to the scale entry to use
	LD A,(HL) ; entry LSB
	INC HL
	LD H,(HL) ; entry MSB
	LD L,A
	; Now HL points to the scale entry to use, which includes the column count, row count, and tile numbers for the sprite at this scale
	LD B,(HL) ; Get the column count
	INC HL
	LD C,(HL) ; Get the row count
	INC HL

	; Now HL points to the tile numbers for the sprite, and BC has the column and row count for the sprite at the appropriate scale.
	; Calculate the location of the first sprite, based on the bottom center anchor point and the column and row count of the sprite
	LD A,B
	LD (SCS_Columns),A ; Save the column count
	ADD A,A
	ADD A,A
	ADD A,A ; A = column count * 16 / 2 for the x offset from the center
	EX DE,HL ;DE = tile table
	POP HL ; Get x position back in HL
	PUSH BC ; Save row count for later use
	LD B,0
	LD C,A
	OR A
	SBC HL,BC ; Move left by the x offset to get the leftmost x position for the first sprite
	POP BC ; Get column count back in BC
	PUSH DE
	PUSH BC
	LD DE,(SCS_Shear)
	DEC C
	JR Z,@ShearDone
@ShearLoop:
	ADD HL,DE ; Top row is offset by shear*(rows-1)
	DEC C
	JR NZ,@ShearLoop
@ShearDone:
	POP BC
	POP DE
	LD (SCS_X),HL ; Save the x position for the first sprite in screen coordinates
	LD (SCS_X_Left),HL ; Also save the leftmost x position for this sprite for later use in culling
	POP HL ; Get y position back in HL
	LD A,C ; Get the row count for the sprite
	ADD A,A
	ADD A,A
	ADD A,A
	ADD A,A ; A = row count * 16 for the y offset from the bottom anchor
	PUSH DE ; DE holds the tile table pointer
	LD E,A
	LD D,0
	OR A
	SBC HL,DE ; HL = y of the top row
	POP DE
	LD A,H
	OR A
	RET NZ ; Top is at or below the bottom of the screen: not visible
	LD (SCS_Y),HL ; Save the y position for the first sprite in screen coordinates
	; Now we have the starting position for the first sprite in screen coordinates in SCS_X and SCS_Y
	; DE= tile table, and B=columns and C=rows.
MakeSpritesLoop:
	LD A,(DE) ; Get the tile number for this sprite
	INC DE
	INC DE ; Skip the 2 pad bytes in the tile table (for tile 256 and above, but not supported yet)
	OR A
	JP Z,SkipSprite ; If tile number is 0, skip this sprite (used for blank spaces in the composite sprite)
	; Add a sprite entry for this tile at the current position in SCS_X and SCS_Y
	PUSH BC ; Save column and row count for later use
	PUSH DE ; Save the pointer to the tile table for later use
	LD HL,(NextSpriteEntry) ; Get the next free sprite entry
	LD DE,(SCS_Y) ; Get the y position for this sprite
	LD (HL),E ; Set the y position for this sprite
	INC HL
	LD (HL),D ; Set the y position for this sprite
	INC HL
	LD DE,(SCS_X) ; Get the x position for this sprite
	LD (HL),E ; Set the x position for this sprite
	INC HL
	LD (HL),D ; Set the x position for this sprite
	INC HL
	LD (HL),A ; Set the tile number for this sprite
	INC HL
	LD C,0
	CP  64
	JR C,@WriteFlags
	INC C
	CP 128
	JR C,@WriteFlags
	INC C
	CP 160
	JR C,@WriteFlags
	INC C
	CP 192
	JR C,@WriteFlags
	INC C
@WriteFlags:
	LD A,C
	ADD A,A	;x16
	ADD A,A
	ADD A,A
	ADD A,A
	; control bits in layer 1 are: [7-4] palette, 3=flip x, 2=flip y, 1=unused, 0=high bit of index 
	LD  (HL),A
	INC HL
	LD (HL),0 ; Zero out sprite options for now
	INC HL
	LD (HL),0
	INC HL
	LD (NextSpriteEntry),HL ; Update the next free sprite entry
	LD A,(SpriteTableCount)
	INC A
	LD (SpriteTableCount),A ; Increment the sprite count for this layer

	POP DE ; Get the tile table pointer back in DE
	POP BC ; Get the column and row count back in BC
SkipSprite:
	LD HL,(SCS_X)
	PUSH BC
	LD BC,16
	ADD HL,BC ; Move to the next column position for the next sprite
	LD (SCS_X),HL
	POP BC

	DEC B
	JP NZ,MakeSpritesLoop ; Loop until we've processed all columns for this sprite
	;DJNZ MakeSpritesLoop ; Loop until we've processed all columns for this sprite

	; Now reset the column position and move to the next row for the next sprite
	LD HL,(SCS_X_Left) ; Reset x position to the leftmost position for this sprite, less one row of shear
	PUSH BC
	LD BC,(SCS_Shear)
	OR A
	SBC HL,BC
	POP BC
	LD (SCS_X_Left),HL
	LD (SCS_X),HL
	LD HL,(SCS_Y)
	PUSH BC
	LD BC,16
	ADD HL,BC ; Move to the next row position for the next sprite
	LD (SCS_Y),HL
	POP BC
	LD A,(SCS_Columns) ; Check if we've processed all rows for this sprite
	LD B,A
	DEC C
	JP NZ,MakeSpritesLoop ; If not, loop back to process the next row

	RET

SCS_X:
	DEFW 0	; Scaled composite sprite x position for the current segment
SCS_Y:
	DEFW 0	; Scaled composite sprite y position for the current segment
SCS_Columns:
	DEFB 0	; Number of columns in the current sprite
SCS_Shear:
	DEFW 0	; Signed x shift applied per row of the current sprite
SCS_X_Left:
	DEFW 0	; The leftmost x position for the current sprite
DrawSegment:
	DEFW 0	; Segment index being projected in BuildCourseSegmentSprites
SegDist:
	DEFW 0	; Total length in cm from the current segment through DrawSegment
SegDrawCount:
	DEFB 0	; Entries in SegDrawList this frame
SegDrawPtr:
	DEFW 0	; Next free entry in SegDrawList while collecting, then the end of the list while drawing
SegDrawList:
	DS 5*3	; Per segment: z distance (word), flags (byte)

Frame:
	DEFB 0
	DEFC SHORE_FIRST_ROW = 5 ; First background row with water and land
	DEFC SHOW_LAND = 0 ; Land stays hidden until x scroll per scanline works in emulation
	DEFC SHORE_ROWS = 9
	DEFC SHORE_LAND_COLS = 5 ; Columns on the left of each row that differ from open water
ShoreSides:
	DEFB 0xff	; Bit 0 = shore on the left, bit 1 = on the right; 0xff forces the first rebuild
ShoreDX:
	DEFW 0
ShoreDY:
	DEFW 0
ShoreMirror:
	DEFB 0
ShoreCount:
	DEFB 0
	DEFC TRACK_HALF_WIDTH = 200 ; Buoys stand this far either side of the track centre, in cm
	DEFC TREE_LATERAL = 300 ; Trees stand this far from the track centre, beyond the buoys
	DEFC LATERAL_DIV = 320 ; 200 cm lands 100 px from the centre at the boat's row
	DEFC MARKER_COUNT = 12 ; Buoys per side that are in range at once
MarkerZ:
	DEFW 0
MarkerLeft:
	DEFB 0
SegCurve:
	DS 5*6 ; Per listed segment: end distance, sideways shift at its end, shift from the entry heading (words)
CurveTheta:
	DEFW 0
CurveC:
	DEFW 0
CurveSeg:
	DEFW 0
CurvePtr:
	DEFW 0
CurveListPtr:
	DEFW 0
CurveLeft:
	DEFB 0
CurveFirst:
	DEFB 0
CurveVal:
	DEFB 0
CurveL:
	DEFW 0
CurveQ:
	DEFW 0
CurveM:
	DEFW 0
CurveZ0:
	DEFW 0
CurveZ1:
	DEFW 0
CurveC0:
	DEFW 0
CurveT1:
	DEFW 0
CurveF:
	DEFW 0
CurveF2:
	DEFW 0
ShoreSrc:
	DEFW 0
ShoreWater:
	DEFB 0
ShoreRowsLeft:
	DEFB 0
ShoreDistance:
	DEFB 0	; cm travelled towards the next shore step
	DEFC SHORE_CM_PER_STEP = MAX_SPEED>>8 ; One step per frame at top speed
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
	defw TileMapShore ; Second copy of the shore sprites, mirrored for a right shore
	defw 0xffff
	defb 0
	defw TileMapSky ; Second copy of the sky sprites, mirrored and drawn over the right shore
	defw 0xffff
	defb 0
	defw TileMapSprites
SpriteTable:
	defw 0xffff
SpriteTableCount:
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
