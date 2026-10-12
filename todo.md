# Jet Ski Racing (Z80 asm, Zeal 8-bit Computer) — Development Todo

## Known Issues (from reviewing `main.asm` and the running build)
- [x] Player boat scale and centring: scale selection now maps nearer (larger `y`) to larger sprites, and the player is centred at `SpriteCenterX` (176) — verify in emulator
- [x] `BuildCourseSegmentSprites` now passes DE = x, BC = y, and accumulates distance across segments (`SegDist`) instead of using each segment's own length — verify tree scaling in emulator
- [x] Tree placement now uses `SHORE_L` / `SHORE_R` and stands on the shore edge (`ShoreEdgeX`) — tune `SHORE_EDGE_X` / `TREE_INSET` in the emulator
- [x] End-of-course check uses the 16-bit segment index and keeps the remainder when looping
- [x] Segment-end test loops, so one frame can cross several short segments
- [X] `ElapsedTimeFrames` is declared `DEFB` but accessed as a word, overwriting the byte after it (`WorldPosX`)
- [ ] Scenery x offset is `500 cm × 208 × 35 / z`, which is off-screen for `z` < ~22000 cm; tune constants/segment spacing now that distance is cumulative
- [ ] Horizon is `64` in the projection code but the sky/water boundary is at y = 80
- [x] `Makefile`: `main.o` now depends on all five `.ztm` layers, the `.ztp` palettes and the included modules; `make run` added
- [ ] `Makefile`: generate `course_index.asm` from the course editor JSON (the editor has no export command yet)
- [ ] HUD values (LAP, TIME, POS, speed, boost) in the screenshot are static mock-up tiles

## Phase 1: Project Setup & Infrastructure
- [x] `z88dk-z80asm` Makefile with asset pipeline (gif → zts → zx0, tmx → ztm)
- [x] Zeal OS start-up: serial debug port, raw non-blocking keyboard, video mode switch
- [x] ZX0 tileset decompression into video memory pages
- [x] Tilemap + attribute (palette) fill from `.ztm`, palette load
- [x] vblank-synchronised main loop with sprite table copy
- [x] Serial debug helpers (`DbgMsg`, `DbgA`, `DbgHL`, `DbgBC`, `DbgDE`)
- [x] `math.asm` library (multiply, divide, rand16, sine)
- [x] Fix Makefile dependencies (see Known Issues)
- [x] Split `main.asm` into modules (`game`, `input`, `physics`, `hud`, `sprites`, `debug`, `assets`), pulled in with `include`
- [x] Game state variable and state machine (`GameState` dispatches to `RunTitle`, `RunMenu`, `RunRace`, `RunResults`; only the race exists, the rest are placeholders)
- [x] `make run` starts `zeal-native` with `jetski.bin` as the user program and the project directory as `h:/`

## Phase 2: Background, Sky & Shore
- [x] Water gradient + sky/mountains tilemaps
- [x] Shore tiles converted to sprites and animated
- [x] Tie shore scroll rate to player velocity (stop when stationary)
- [x] Choose left/right shore per segment (`SHORE_L` / `SHORE_R`) — verify in emulator
- [ ] Align horizon constant with the sky/water boundary
- [X] Shift sky/mountains horizontally on curves
- [ ] Optional: water motion via palette animation

## Phase 3: Track Data & Course Editor
- [x] Segment format (`curve`, `length`, `flags`) and course index layout
- [x] Course editor web tool and generated `course_index.asm`
- [x] Course 0 loaded into `Course*` variables at start-up
- [x] Advance through segments and loop at end of course
- [ ] 16-bit segment compare; course selection from menu
- [ ] Define secondary per-segment object table (ramp/obstacle type and lateral position)
- [ ] Add course editor export step to the Makefile
- [ ] Design final Course 1 (curves, shore, ramps, obstacles)

## Phase 4: Player Physics
- [x] Throttle acceleration, coast, brake, max speed (8.8 fixed point)
- [x] Apply `Steer` to `WorldPosX` with speed-dependent turning
- [x] Apply segment `curve` as lateral/yaw drift
- [x] Use `Yaw` / `sine_88` if a heading model is needed (not needed: lateral model works without a heading)
- [ ] Track edge detection and slow-down zone speed reduction
- [ ] Obstacle collision + speed penalty
- [ ] Boost state (duration, decay)
- [x] Convert velocity to km/h for display
- [ ] Tune constants (`ACCELERATION`, `COAST`, `BREAK`, `MAX_SPEED`)

## Phase 5: Perspective Sprites
- [x] Composite sprite format and scaled tile grids (boat, tree, buoy)
- [x] Perspective projection of the next 5 segments using `Div24_16`
- [ ] Fix scale selection and x/y argument order (Known Issues)
- [ ] Place scenery left/right of the track using segment flags and lateral offset
- [ ] Reduce per-frame cost (skip off-screen objects, avoid the 24/16 divide for far sprites, e.g. reciprocal table)
- [ ] Clip sprites to the screen edges and the 128-sprite budget
- [ ] Z-order: far objects first, player and near objects in front
- [ ] Obstacle sprite sets (rocks, logs)
- [ ] Ramp scale table (tiles 160–191)
- [x] Trackside flag/buoy markers at regular intervals — verify in emulator
- [ ] Player sprite: 4×4 at bottom centre, lean levels, flip for right lean
- [ ] Verify per-scanline sprite limits on hardware/emulator

## Phase 6: Jumps & Tricks
- [ ] Airborne state triggered by ramp
- [ ] 4 trick inputs and key mapping
- [ ] Trick animation frames (art + frame selection)
- [ ] Clean/failed landing detection
- [ ] Bonus points + boost on clean landing; penalty on failure

## Phase 7: AI Opponents
- [ ] Define AI record layout in asm (`track_pos` word, `lateral` byte); decide tick rate and storage size
- [ ] PC-side recording tool that exports `.asm` data per opponent per course
- [ ] Playback: tick counter → record
- [ ] Map AI world position relative to the player to screen x/y and scale
- [ ] Draw AI boats with correct depth ordering
- [ ] Record 5 playthroughs at varied skill levels

## Phase 8: HUD
- [x] Static HUD mock-up tiles in `hud` tilemap
- [x] Digit/colon/slash tile printing (`PrintDec16`, `PrintDec99`, `PrintDigit`)
- [x] Debug overlay (throttle, segment, z, velocity, time)
- [ ] Live LAP, TIME, POS (with `st`/`nd`/`rd`/`th` suffix tiles), SPEED, BOOST
- [ ] Remove debug overlay (or toggle with a key)
- [ ] Trick point flash

## Phase 9: Race Logic & Scoring
- [ ] Lap counting at course loop; 2-lap end
- [ ] Live position vs AI
- [ ] Finish order and race clock reset/hold
- [ ] Scoring formula and top-3 unlock flag
- [ ] Pre-race countdown (3-2-1-GO)

## Phase 10: Screens & Game Flow
- [ ] Title screen
- [ ] Main menu (Start, Sound Settings, Exit)
- [ ] Sound settings
- [ ] Results screen
- [ ] Post-race flow (retry / next course / exit)
- [x] Exit path that restores text mode (`QuitGame` on `Esc`)

## Phase 11: Input
- [x] Keyboard: arrows, Space, Esc, Enter (press/release)
- [ ] Hold-state input flags instead of overwriting throttle on press/release
- [ ] Final key map (including tricks)
- [ ] SNES controller support

## Phase 12: Audio
- [ ] Engine roar on wavetable channel (pitch ∝ speed)
- [ ] Volume control and mute

## Phase 13: Performance & Polish
- [ ] Measure main-loop frame time; confirm 60 fps (or move to 30 fps)
- [ ] Optimise sprite rebuild and sprite table clearing
- [ ] Tune AI spread and physics
- [ ] Playtest and bug-fix pass
- [ ] Remove debug serial output from the release build

---

## Post-MVP (backlog)
- [ ] Track 2 and 3 content, art, AI recordings
- [ ] High score persistence
- [ ] Background music
- [ ] Trick jingle and collision/splash SFX
- [ ] Opponent palette differentiation
- [ ] Selectable riders with different stats
