# Jet Ski Racing Game — Specification

## Platform & Toolchain

- **Target hardware:** Zeal 8-bit Computer (Z80 at 10 MHz) with the Zeal Video Board and Zeal 8-bit OS
- **Language:** Z80 assembly, assembled with `z88dk-z80asm` (not C / SDCC)
- **Output:** single `jetski.bin` loaded at `0x4000` by Zeal OS and launched from `autoexec.zs`
- **Video mode:** `VID_MODE_GFX_320_4BIT` — 320×240, tile/sprite based, 16×16 px tiles, 4-bit (16-colour) tile data, 16-colour sub-palettes selected per tile/sprite
- **Display resolution in tiles:** 20 wide × 15 tall
- **Frame rate:** target 60 fps. The main loop is synchronised to the vertical blank and runs one update per frame. Fall back to 30 fps (update every other vblank) only if profiling shows the budget is exceeded.
- **Emulator/host:** Zeal emulator with host filesystem as `h:/`; debug text goes to the `#SER0` serial device.

### Build pipeline

| Step | Tool |
|---|---|
| Art source | Aseprite (`img/*.aseprite`) exported to GIF |
| GIF → 4-bit tileset (`.zts`) + palette (`.ztp`) | `Zeal-VideoBoard-SDK/tools/zeal2gif/gif2zeal.py -b 4` |
| Tileset compression (`.zts.zx0`) | `zx0` (decompressed at start-up by `dzx0_standard.asm`) |
| Tilemaps (`map/baselayer.tmx` → `baselayer000N.ztm`) | Tiled + `Zeal-VideoBoard-SDK/tools/tiled2zeal/tiled2zeal.py` |
| Course data (`course_index.asm`) | Course editor (`tools/courseed`, FastAPI + browser UI) stores courses as JSON and exports z80asm |
| Assemble/link | `z88dk-z80asm` → `jetski.bin` (copied to `s`) |

All assets are embedded in the binary with `incbin`; there is no separate `.dat` asset file and no runtime file loading.

Source modules:

| File | Purpose |
|---|---|
| `main.asm` | Initialisation, main loop, input, physics, HUD, sprite building, embedded assets |
| `math.asm` | Fixed-point helpers: `DE_Times_A`, `BC_Times_DE`, `Div24_16`, `Div_HL_D`, `DE_Div_BC_88`, `multi8_8`, `rand16`, `sine_88` |
| `course_index.asm` | Generated course table and per-course segment data |
| `dzx0_standard.asm` | ZX0 decompressor |
| `tools/gensine88.py` | Generates an 8.8 sine table (256 entries) |
| `prototype/` | Earlier SDL2/C prototype of the renderer; reference only, not part of the game |

---

## Memory & Video Hardware Usage

| Region | Use |
|---|---|
| `0x0000–0x3FFF` | Zeal OS |
| `0x4000–0x7FFF` | Game code, embedded assets, variables (`org 0x4000`) |
| `0x8000–0xBFFF` | Page 2 — remapped (port `0xF2`) to a 16 KB window of video memory (tileset, layers, palette, sprite table) |
| `0xC000–0xFFFF` | Page 3 — RAM; holds the staged 128-entry sprite table (`sprite_table = 0xC000`, 8 bytes per sprite) and scratch buffers |

### Video memory use
- **Layer 0:** tile indices. **Layer 1:** per-tile attributes (`[7–4]` palette, `3` flip X, `2` flip Y, `0` tile index high bit). Both are stored with a stride of 80 entries per row; only the first 20 are visible.
- **Sprites:** 128 hardware sprites, 8 bytes each (`y` word, `x` word, tile, flags, options, reserved). Sprite coordinates are offset by +16 px on both axes from screen coordinates.
- **Sprite table** is built in RAM each frame, then copied to video memory with `LDIR` right after vblank starts.
- **Palette:** 256 colours as 16 sub-palettes of 16 entries (32 bytes each); the sub-palette is chosen from the tile index range (below).

### Tile allocation

| Tile range | Content | Sub-palette |
|---|---|---|
| 0–63 | Player jet ski (and future NPC racers) | 0 |
| 64–127 | Background: sky, water gradient, shore, mountains | 1 |
| 128–159 | Tree / palm and buoy scenery | 2 |
| 160–191 | Ramp | 3 |
| 192–223 | Numbers and HUD font (`0`–`9`, `:`, `/`) | 4 |

Tile 0 in a composite sprite definition means "empty cell". Tile indices ≥ 256 are not yet supported by the sprite builder.

---

## Screen Layout (tile rows, 16 px each)

| Region | Rows | Pixels | Implementation |
|---|---|---|---|
| Top HUD | 0 | 0–15 | Layer 0 `hud` tilemap: LAP, TIME, POS |
| Sky / background | 1–4 | 16–79 | `sky` tilemap (mountains, horizon) |
| Water | 5–13 | 80–223 | `background` tilemap — pre-drawn dithered gradient from horizon to foreground |
| Bottom HUD | 14 | 224–239 | Speed (km/h) and BOOST bar |

The shore is drawn from sprites in front of the water. During development a two-row numeric debug overlay is drawn over tile rows 1–2.

---

## Game Flow

```
Title Screen
    └─> Main Menu
            ├─ Start Game
            ├─ Sound Settings (volume levels, disable toggle)
            └─ Exit

Start Game
    └─> Race (2 laps)
            ├─ Finish top 3 → Results Screen → option to proceed to next course (if unlocked)
            ├─ Finish 4th–6th → Results Screen → option to retry or exit
            └─ High score per track (session only; no persistence in MVP)
```

Currently the program boots directly into the race on course 0 and exits to the OS text mode on `Esc`.

### Screens Required (MVP)
1. **Title screen** — static image + prompt to press start
2. **Main menu** — Start, Sound Settings, Exit
3. **Race screen** — full gameplay (in progress)
4. **Results screen** — finishing position, lap times, trick points, combined score

### Course Unlock
- Courses are unlocked sequentially (top-3 finish on current course unlocks the next).
- No championship/cumulative scoring — each track has its own high score (session only in MVP).

---

## Courses

Courses are authored in the course editor and exported to `course_index.asm`. All courses are linked into the binary.

| Course | Difficulty | Segments | Status |
|---|---|---|---|
| The Lagoon | 1 | 14 | Playable test course (MVP course 1) |
| The River | 4 | 1 | Placeholder |
| Zig Zag Alley | 3 | 11 | Early draft |

### Course index entry (7 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | word | Pointer to zero-terminated course name |
| 2 | byte | Difficulty (1–5) |
| 3 | word | Segment count |
| 5 | word | Pointer to segment array |

`course_index_count` (word) is exported separately. Entry 0 is always selected today.

### Segment record (4 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | int8 | `curve` — heading change over the segment (radians × 32, 0 = straight) |
| 1 | word | `length` — segment length in cm |
| 3 | byte | `flags` |

Flag bits: `HAS_RAMP=1`, `HAS_OBSTACLE_L=2`, `HAS_OBSTACLE_R=4`, `SLOWZONE=8`, `SHORE_L=16`, `SHORE_R=32`.

- Track loops; 2 laps per race.
- Ramp clusters appear roughly every ~600 world units (~20 seconds at mid-speed), consistent with Wave Race pacing on a ~1.5-minute lap.
- Obstacle and ramp types/positions within a segment will be stored in a secondary array indexed by segment (not yet defined).

---

## Renderer

The renderer is a hybrid of a static tilemap background and a perspective-projected sprite layer, designed to stay within the Z80 budget.

### Background (tilemaps)
- **Water:** a pre-drawn dithered gradient fills rows 5–13 and provides the sense of depth. Motion toward the player is indicated by the scrolling shore and scenery. Palette animation is an optional later enhancement.
- **Sky:** mountains and sky band in rows 1–4, with the horizon at the sky/water boundary.
- **Layers loaded at start-up:** `background`, `shore`, `sky`, `hud`, `sprite` (Tiled layers exported as `baselayer0000`–`0004`). Only `background` is copied into the layer 0 tilemap; the `shore` and `sprite` layers are scanned and their non-empty tiles converted to hardware sprites.

### Shore
- Shore tiles become sprites at start-up and are animated every frame (+2 px down / −1 px left per frame, then snap back after 16 frames) to give a scrolling-toward-viewer effect.
- Planned: drive the scroll rate from player velocity and the shape from `SHORE_L` / `SHORE_R` flags and curve.

### Perspective-projected scenery
- Each frame the engine walks the next 5 segments from the player's current segment, computes a distance `z` (cm) relative to the player, and projects to screen:
  - `y = HORIZON + (Y_WORLD × DIST × SCALE) / z` (`Y_WORLD`=120 cm, `DIST`=208, `SCALE`=35)
  - `x = centre ± (500 cm × SCALE) / z` for left/right objects
  - Uses `Div24_16` from `math.asm`.
- Objects are drawn as **composite sprites**: grids of 16×16 tiles chosen from a pre-rendered size table. The `y` position selects the scale (larger sprites when lower on screen, i.e. closer).
- Composite sprite definition format:
  - List: `count, ptr[count]` (pointers ordered largest to smallest)
  - Entry: `columns, rows, tile_words[columns × rows]` (tile 0 = empty cell)
- Sprites are anchored at bottom centre. Up to 128 hardware sprites are available per frame across shore, scenery, player and (later) NPCs.

### Sprite sets currently defined

| Set | Scales | Largest size |
|---|---|---|
| Boat (player / NPC) | 5 | 4×4 tiles |
| Tree (palm) | 5 | 2×4 tiles |
| Buoy | 4 | 1×1 tile |

### Track Edge & Out-of-Bounds
- Track has defined edges. Beyond the edge = **slow-down zone** (speed reduced, no wipeout).
- No invisible walls; the player can always drift off the edge but pays a speed penalty.

### Curves
- Curves are expressed via the segment `curve` value and shift scenery and horizon content laterally. Not yet implemented in the renderer.

### Trackside Markers
- Flags and buoys at regular intervals along the track edges, rendered as scaled composite sprites; they serve as speed reference objects.

---

## Player

### Rendering
- 4×4 tile jet ski at the nearest scale, anchored at the bottom of the water area, horizontally centred on screen (allowing for the +16 px sprite coordinate offset).
- Lean-left frames; lean-right via horizontal flip (`flag_flip_x`).
- Steering input currently shifts the sprite horizontally.

### Physics (momentum-based)
All values are 8.8 fixed point, evaluated once per frame.

| Constant | Value | Meaning |
|---|---|---|
| `ACCELERATION` | 75 | Throttle added to velocity per frame |
| `COAST` | 25 | Drag subtracted per frame |
| `BREAK` | 150 | Brake (negative throttle) |
| `MAX_SPEED` | 46 × 256 | Cap in cm/frame (≈ 100 km/h) |

| Property | Behaviour |
|---|---|
| Acceleration | `velocity += throttle − coast`, clamped to `[0, MAX_SPEED]` |
| Position | `WorldPosZ` (cm into the current segment) advances by the whole part of velocity; on exceeding the segment length the remainder carries into the next segment; the course loops after the final segment |
| Turning | Lateral drift; radius increases with speed (not yet implemented; `WorldPosX`, `Yaw`, `Steer` are reserved) |
| Out-of-bounds | Speed reduced in slow-down zone; continues when steered back |
| Obstacle collision | Speed penalty (no wipeout/respawn) |
| Boost | Flat speed burst applied on clean jump landing (see Tricks) |

### Race clock
- 60 frames = 1 second. HUD displays `MM:SS:cc` (centiseconds derived from frames).

---

## AI Opponents

### Count
5 opponents per race (6 racers total including player).

### Behaviour
- Each opponent follows a **pre-recorded playthrough** assembled into the binary (one data block per opponent per course).
- Recordings capture position along the track and lateral offset at each game tick.
- Opponents are spread across a range of skill levels to act as position reference points.
- Playback is deterministic replay; no runtime pathfinding.

### AI Recording Format (per tick)
```
defw track_pos   ; world units along the whole course
defb lateral     ; signed lateral offset from track centre
```
One record per game tick for the full 2-lap duration. Size must be checked against available RAM (3 bytes × ticks × 5 opponents); if too large, record at a lower tick rate and interpolate, or store per-segment deltas.

---

## Jumps & Tricks

### Ramps
- Ramps are segment flags (`HAS_RAMP`) plus ramp sprites (tiles 160–191).
- Hitting a ramp launches the player airborne.

### Tricks (airborne only)
- 4 tricks on 4 keys (keys TBD; arrow keys are currently used for steering/throttle).
- Performing a trick while airborne plays a brief animation (pre-rendered sprite frames).
- **Clean landing:** trick bonus points added to score + flat speed boost.
- **Failed landing** (obstacle hit mid-air or poor landing): no bonus points, speed penalty.

---

## Controls

Keyboard is read through the Zeal OS keyboard driver in raw, non-blocking mode (press and release events), polled once per frame.

| Action | Current key | Planned |
|---|---|---|
| Accelerate | Up arrow, Space | + SNES D-pad Up |
| Brake | Down arrow | + SNES D-pad Down |
| Steer left / right | Left / Right arrow | + SNES D-pad |
| Quit to OS | Esc | Pause / Menu (Start) |
| Tricks (4) | — | TBD key mapping; SNES A/B/X/Y |
| Select / Confirm | Enter (stub) | |

SNES controller support is planned after keyboard play is complete.

---

## HUD

| Element | Location | Status |
|---|---|---|
| **LAP** current/total (e.g. `LAP 1 / 2`) | Top row | Static tiles (mock-up) |
| **TIME** | Top row | Static tiles (mock-up); live time in debug overlay |
| **POS** (1st–6th) | Top row | Static tiles (mock-up) |
| **SPEED** km/h | Bottom row, left | Static tiles (mock-up) |
| **BOOST** bar | Bottom row, right | Static tiles (mock-up) |
| **TRICK** points flash | TBD | Not started |
| Debug overlay | Rows 1–2 | Throttle : segment / count : z position : velocity; elapsed `MM:SS:cc` |

Numbers are written as tile indices `192 + digit` (`:` = 202, `/` = 203) into layer 0, with sub-palette 4 set in layer 1. Dynamic HUD values will use the existing digit printing routines (`PrintDec16`, `PrintDec99`, `PrintDigit`). The debug overlay is removed from the release build.

---

## Scoring

```
Score = Position Points + Time Bonus + Trick Points
```

- **Position Points:** fixed points per finishing place (1st = most, 6th = least).
- **Time Bonus:** decreasing bonus based on total race time.
- **Trick Points:** accumulated through clean trick landings.
- No persistence in MVP; scores shown on the results screen only.

---

## Audio

- **Hardware:** Zeal Video Board sound: 3-channel chiptune (square, triangle, noise, sine) + 1-channel 8-bit wavetable.
- **MVP:** engine roar only (wavetable channel, pitch scales with speed).
- **Settings:** volume control (multiple levels + disable), from the main menu.
- **Post-MVP:** music, trick jingles, splash/collision effects.

---

## Art Requirements

Tile budget is shared by all sprites and backgrounds (currently 224 of 256 tile slots allocated; up to 512 with the high-bit attribute).

### Player jet ski (4×4 tiles)
- Straight ahead; lean left (2–3 levels); lean right via flip
- Airborne frames per trick (4)
- Smaller scales — drawn: 4×4, 3×4, 3×3, 2×3, 2×2

### NPC racers
- Share the boat tile set and scale table; differentiated by sub-palette (post-MVP)

### Scenery & obstacles
- Palm trees (5 scales) — done
- Buoys (4 scales) — done
- Rocks / logs / flags — not drawn
- Ramp — tile set exists, no scale table yet

### Backgrounds
- Water gradient, shore, sky/mountains — done for course 1; per-course variants post-MVP

---

## Project Structure

```
jetski/
├── main.asm             # game code + embedded assets
├── math.asm             # fixed-point math library
├── course_index.asm     # generated by course editor
├── dzx0_standard.asm    # ZX0 decompressor
├── autoexec.zs          # Zeal OS startup script (runs jetski.bin from h:/)
├── Makefile
├── img/                 # Aseprite sources, .ztp palettes, .zts.zx0 tilesets
├── map/                 # Tiled project, .tmx/.tsx, exported .ztm tilemaps
├── tools/
│   ├── courseed/        # course editor (FastAPI + browser UI, JSON courses)
│   └── gensine88.py
├── prototype/           # earlier SDL2/C prototype (reference only)
├── specification.md
└── todo.md
```

Dependencies expected as sibling directories: `../Zeal-VideoBoard-SDK` (headers, asset tools) and `../Zeal-8-bit-OS` (kernel headers).

---

## MVP Scope Summary

| Feature | MVP | Status |
|---|---|---|
| Z80 asm build pipeline, asset embedding | ✓ | Done |
| Tilemap background + palettes | ✓ | Done |
| Course editor + course data | ✓ | Tool done; more content needed |
| Keyboard input | ✓ | Basic |
| Momentum throttle/brake/coast + segment progression | ✓ | Done |
| Perspective scenery sprites (trees) | ✓ | Prototype, needs fixes |
| Shore animation | ✓ | Basic |
| Player sprite | ✓ | Placeholder (small scale, off-centre) |
| Steering, curves, slow-down zone | ✓ | Not started |
| Live HUD (pos, lap, time, speed, boost) | ✓ | Debug overlay only |
| 1 course | ✓ | Test course only |
| 5 AI opponents (pre-recorded) | ✓ | Not started |
| Ramps, 4 tricks + boost | ✓ | Not started |
| Static obstacles | ✓ | Not started |
| Lap/race logic and scoring | ✓ | Not started |
| Title + menu + results screens | ✓ | Not started |
| Engine sound + volume settings | ✓ | Not started |
| SNES controller | | After keyboard |
| 2 additional courses | | Post-MVP |
| High score persistence | | Post-MVP |
| Multiple riders / stat differences | | Post-MVP |
| Music + SFX | | Post-MVP |
| Opponent palette differentiation | | Post-MVP |
