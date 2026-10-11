; Top-level game state machine.  The main loop calls the handler for GameState once per frame.

	DEFC STATE_TITLE = 0
	DEFC STATE_MENU = 1
	DEFC STATE_RACE = 2
	DEFC STATE_RESULTS = 3

GameState:
	DEFB STATE_RACE	; The title, menu and results screens don't exist yet, so boot straight into the race

GameStateTable:	; Indexed by GameState
	DEFW RunTitle, RunMenu, RunRace, RunResults

StartRace:
	; Always select track 0
	LD HL,(course_index+0) ; name_ptr
	LD (CourseName),HL
	LD A,(course_index+2) ; difficulty
	LD (CourseDifficulty),A
	LD HL,(course_index+3) ; segment_count
	LD (CourseSegmentCount),HL
	LD HL,(course_index+5) ; segments_ptr
	LD (CourseSegmentPtr),HL
	LD A,STATE_RACE
	LD (GameState),A
	RET

RunRace:
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
	RET

RunTitle:
RunMenu:
RunResults:
	; Placeholders: keep the loop paced to vblank and Esc working
	CALL wait_for_vblank
	CALL wait_end_vblank
	CALL ReadKeyboard
	RET
