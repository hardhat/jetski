# Jet Ski Racing — Development Todo

## Phase 1: Project Setup & Infrastructure
- [ ] Set up SDCC build environment and Makefile
- [ ] Port and adapt `dat.c` / `dat.h` from wsorrow; define new `DAT_BLOCK_*` constants
- [ ] Implement `input.c` — keyboard (WASD/QE/arrows/Esc) and SNES controller polling
- [ ] Implement `game.c` — top-level state machine (TITLE, MENU, RACE, RESULTS)
- [ ] Stub out all remaining modules with empty function signatures

## Phase 2: Renderer — Water & Sky
- [ ] Implement scanline perspective projection for flat water surface (rows 5–14)
- [ ] Implement palette cycling on water tiles to simulate motion toward player
- [ ] Implement sky/background region rendering (rows 1–4, static or horizontally scrolling)
- [ ] Implement horizon line placement at sky/water boundary

## Phase 3: Renderer — Track Curves
- [ ] Implement segment-based track curvature (offset horizon and road edges per segment)
- [ ] Implement lateral road edge rendering (track boundary lines visible in water region)
- [ ] Implement track looping (seamless 2-lap repeat)
- [ ] Implement camera position advancing through segments at player speed

## Phase 4: Track Data System
- [ ] Define and document `TrackSegment` binary struct (curve, length, flags)
- [ ] Implement track block loader from `.dat` (`DAT_BLOCK_TRACK`)
- [ ] Implement track position tracking (world units, segment lookup)
- [ ] Implement ramp segment detection (flag `HAS_RAMP`)
- [ ] Implement out-of-bounds / slow-down zone detection (track edge threshold)

## Phase 5: Player Physics
- [ ] Implement throttle acceleration (gradual build-up)
- [ ] Implement momentum-based deceleration (coast-down and brake)
- [ ] Implement lateral steering with speed-dependent turning radius
- [ ] Implement slow-down zone speed reduction (out-of-bounds edges)
- [ ] Implement obstacle collision detection and speed penalty
- [ ] Implement flat speed boost state (duration + decay after clean landing)

## Phase 6: Jumps & Tricks
- [ ] Implement airborne state triggered by ramp segments
- [ ] Implement 4 trick inputs (arrow keys / SNES face buttons), active while airborne
- [ ] Implement trick animation frame selection (pre-rendered airborne sprite variants)
- [ ] Implement clean landing detection (no obstacle mid-air, valid landing surface)
- [ ] Implement failed landing handling (no points, speed penalty)
- [ ] Integrate trick bonus points and boost trigger on clean landing

## Phase 7: Sprite Rendering
- [ ] Implement scaled sprite blitter (index into pre-rendered size table by distance)
- [ ] Implement player jet ski rendering: straight, lean-left levels, lean-right (mirror)
- [ ] Implement player sheer effect via tile column seam offsets
- [ ] Implement NPC racer scaled sprite rendering (1×1 to 4×4 tile sizes)
- [ ] Implement trackside marker rendering (flags/buoys, 4+ scale steps, at track edges)
- [ ] Implement obstacle sprite rendering (multiple sizes, placed per segment flags)
- [ ] Implement ramp sprite rendering (multiple sizes)

## Phase 8: AI Opponents
- [ ] Define `AIFrame` binary struct (track_pos, lateral)
- [ ] Implement AI recording block loader (`DAT_BLOCK_AI_0` through `DAT_BLOCK_AI_4`)
- [ ] Implement per-opponent frame playback (tick counter → AIFrame index)
- [ ] Implement AI world position → screen position mapping (depth + lateral to screen x/y)
- [ ] Integrate AI racers into renderer (sorted by depth, correct sprite size selection)

## Phase 9: HUD
- [ ] Implement HUD tile row renderer (uses `DAT_BLOCK_HUD_TS` / `DAT_BLOCK_HUD_PAL`)
- [ ] Render current race position (1–6)
- [ ] Render lap counter (e.g. `LAP 1/2`)
- [ ] Render current lap time (MM:SS.s)
- [ ] Render numeric speed readout (km/h)
- [ ] Render boost indicator bar (fill level reflects boost remaining)
- [ ] Implement trick point flash (brief on-screen display on clean landing)

## Phase 10: Race Logic & Scoring
- [ ] Implement lap detection (crossing start/finish line increments lap counter)
- [ ] Implement 2-lap race end trigger
- [ ] Implement live position tracking (compare player track_pos vs all AI track_pos)
- [ ] Implement race finish order recording
- [ ] Implement scoring formula: Position Points + Time Bonus + Trick Points
- [ ] Implement top-3 finish → next course unlock flag

## Phase 11: Screens & Game Flow
- [ ] Implement title screen (static image + press start prompt)
- [ ] Implement main menu (Start, Sound Settings, Exit)
- [ ] Implement sound settings screen (volume levels + disable)
- [ ] Implement pre-race countdown (3-2-1-GO)
- [ ] Implement results screen (position, lap times, trick points, combined score)
- [ ] Implement post-race flow (retry / next course / exit options)

## Phase 12: Audio
- [ ] Implement engine roar on wavetable channel (pitch proportional to player speed)
- [ ] Implement volume control (multiple levels + mute), hooked to settings menu

## Phase 13: Asset Pipeline & Tools
- [ ] Write `dat_packer` tool (PC-side): packs tileset, palette, track data, AI recordings into `.dat`
- [ ] Write `ai_recorder` tool (or process): play/simulate opponent paths and export `AIFrame` streams
- [ ] Document `.dat` block layout and packing order for track 1

## Phase 14: Track 1 Content
- [ ] Design track 1 segment data (curves, lengths, obstacle placements, ramp clusters)
- [ ] Create / source art: water tiles, sky background, trackside scenery
- [ ] Create obstacle sprites (rock/buoy) at multiple sizes
- [ ] Create ramp sprites at multiple sizes
- [ ] Create flag/buoy trackside marker sprites at multiple sizes
- [ ] Create player jet ski sprite sheet (straight, 2–3 lean levels, 4 trick airborne frames)
- [ ] Create NPC racer sprite sheet (4 scaled sizes)
- [ ] Record 5 AI opponent playthroughs at varied skill levels
- [ ] Pack all track 1 assets into `track1.dat`
- [ ] Full integration test: race track 1 start to finish

## Phase 15: Performance & Polish
- [ ] Profile render loop on 10 MHz Z80; verify stable 30 fps (within 2-frame vsync budget)
- [ ] Tune player physics constants (acceleration, turning feel, boost duration)
- [ ] Tune AI opponent timing and spread across skill levels
- [ ] Fix bugs identified during integration testing
- [ ] Final playtesting pass

---

## Post-MVP (backlog)
- [ ] Track 2 content + art + AI recordings
- [ ] Track 3 content + art + AI recordings
- [ ] High score persistence (save to storage)
- [ ] Background music (chiptune channels)
- [ ] Trick jingle SFX on landing
- [ ] Collision / splash SFX
- [ ] Opponent palette differentiation (each NPC has a distinct colour)
- [ ] Multiple selectable riders with different stats
