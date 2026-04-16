# Jet Ski Racing Game — Specification
## Platform & Toolchain

- **Target hardware:** Zeal 8-bit computer (Z80 at 10 MHz)
- **Video mode:** 320×240, 256-colour palette, tile-based (16×16 px tiles)
- **Tile budget:** 256 tiles
- **Language:** C, compiled with SDCC
- **Frame rate:** 30 fps (engine runs at 60 Hz vsync; update every other frame)
- **Display resolution in tiles:** 20 tiles wide × 15 tiles tall

---

## Screen Layout (tile rows, 16 px each)

| Region | Rows | Pixels |
|---|---|---|
| HUD | 1 | 16 px |
| Sky / background | 4 | 64 px |
| Water surface | 10 | 160 px |
| **Total** | **15** | **240 px** |

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

### Screens Required (MVP)
1. **Title screen** — static image + prompt to press start
2. **Main menu** — Start, Sound Settings, Exit
3. **Race screen** — full gameplay
4. **Results screen** — finishing position, lap times, trick points, combined score

### Course Unlock
- Courses are unlocked sequentially (top-3 finish on current course unlocks the next).
- No championship/cumulative scoring — each track has its own high score table (session only in MVP).

---

## Courses

| # | Status | Theme (examples) |
|---|---|---|
| 1 | MVP | TBD (e.g. tropical lagoon) |
| 2 | Post-MVP | TBD |
| 3 | Post-MVP | TBD |

All course data (segments, art, AI recordings) is loaded from a monolithic per-level `.dat` file at race start. The file is assumed to be in the current working directory.

---

## Asset File Format (`.dat`)

Based on the existing `DatEntry` format from other Zeal projects:

```c
typedef struct {
    uint32_t offset;  // byte offset in file (magic word for entry 0)
    uint16_t size;    // block size in bytes
    uint8_t  type;    // DAT_TYPE_*
    uint8_t  id;      // DAT_BLOCK_*
} DatEntry;
```

### Block IDs per level `.dat` file

| ID | Name | Contents |
|---|---|---|
| 0 | `DAT_BLOCK_MAGIC` | Magic cookie / header |
| 1 | `DAT_BLOCK_TILESET` | Level tiles (palette-cycled water, scenery, obstacles, ramps, flags) |
| 2 | `DAT_BLOCK_PALETTE` | 256-colour palette for level |
| 3 | `DAT_BLOCK_PLAYER_TS` | Player jet ski sprite sheet (pre-rendered sizes + lean frames) |
| 4 | `DAT_BLOCK_PLAYER_PAL` | Player sprite palette |
| 5 | `DAT_BLOCK_HUD_TS` | HUD tiles (font, boost indicator, position digits) |
| 6 | `DAT_BLOCK_HUD_PAL` | HUD palette |
| 7 | `DAT_BLOCK_TRACK` | Track segment data |
| 8 | `DAT_BLOCK_AI_0` | AI opponent 0 recording |
| 9 | `DAT_BLOCK_AI_1` | AI opponent 1 recording |
| 10 | `DAT_BLOCK_AI_2` | AI opponent 2 recording |
| 11 | `DAT_BLOCK_AI_3` | AI opponent 3 recording |
| 12 | `DAT_BLOCK_AI_4` | AI opponent 4 recording |

---

## Renderer

### Pseudo-3D Road Engine
- Classic segment-based renderer (inspired by Outrun / Turbo / Antarctic Adventure).
- Track defined as a sequence of segments, each with a **curve angle** and **length**.
- Scanline-based perspective projection: each horizontal row of the water region is drawn at a scaled offset derived from its distance from the horizon.

### Screen Regions
- **Sky (rows 1–4):** Scrolling or static background bitmap per level. Background scenery (trees, mountains, cliffs, crowd stands, beach, boardwalk) drawn here.
- **Water surface (rows 5–14):** Drawn scanline by scanline. Palette cycling on water tiles simulates the water flowing toward the player. Repetition is acceptable given the 256-tile budget.
- **Horizon line:** At the boundary between sky row 4 and water row 5.

### Track Edge & Out-of-Bounds
- Track has defined edges. Beyond the edge = **slow-down zone** (speed reduced, no wipeout).
- No invisible walls; the player can always drift off the edge but pays a speed penalty.

### Trackside Markers
- Flags and buoys placed at regular intervals along track edges, rendered as pre-rendered scaled sprites.
- Serve as speed reference objects (they appear to rush toward the player).

### Sprite Scaling
- No hardware sprite scaling; all scaled frames are pre-rendered.
- **NPC racers:** 1×1 tile (distant) up to 4×4 tiles (close). Simple scaled sprite sets, no lean frames.
- **Player jet ski:** 4×4 tiles at full size. Has lean-left frames; lean-right is a horizontal mirror (hardware mirroring supported). Sheering effect achieved via seam offsets between 16×16 tile columns.
- **Obstacles / ramps:** Pre-rendered at multiple sizes.

---

## Track Format (`DAT_BLOCK_TRACK`)

Binary array of segment records:

```c
typedef struct {
    int8_t   curve;    // signed curve angle (-128 to +127, 0 = straight)
    uint16_t length;   // segment length in world units
    uint8_t  flags;    // bitmask: HAS_RAMP, HAS_OBSTACLE_L, HAS_OBSTACLE_R, SLOWZONE
} TrackSegment;
```

- Obstacle and ramp types/positions within a segment stored as a secondary array indexed by segment ID.
- Track loops; 2 laps per race.
- Ramp clusters appear roughly every ~600 world units (~20 seconds at mid-speed), consistent with Wave Race pacing on a ~1.5-minute lap.

---

## AI Opponents

### Count
5 opponents per race (6 racers total including player).

### Behaviour
- Each opponent has a **unique pre-recorded playthrough** stored as `DAT_BLOCK_AI_0` through `DAT_BLOCK_AI_4`.
- Recordings capture position along the track and lateral offset at each game tick (30 fps).
- Opponents are spread across a range of skill levels (slowest to fastest) to act as position reference points for the player.
- Playback is deterministic replay; no runtime pathfinding required.

### AI Recording Format (per opponent block)
```c
typedef struct {
    uint16_t track_pos;   // position along track (world units)
    int8_t   lateral;     // lateral offset from track centre
} AIFrame;
```
One `AIFrame` per game tick for the full 2-lap duration.

---

## Player Physics (momentum-based)

| Property | Behaviour |
|---|---|
| Acceleration | Gradual build-up on throttle |
| Deceleration | Momentum-based coast-down; brake reduces speed faster |
| Turning | Lateral drift; turning radius increases at higher speed |
| Out-of-bounds | Speed reduced in slow-down zone; continues when steered back |
| Obstacle collision | Speed penalty (no wipeout/respawn) |
| Boost | Flat speed burst applied on clean jump landing (see Tricks) |

---

## Jumps & Tricks

### Ramps
- Fixed ramp segments embedded in the track data.
- Hitting a ramp launches the player airborne.

### Tricks (airborne only)
- 4 tricks, one per face button (SNES: A, B, X, Y / keyboard: arrow keys).
- Performing a trick while airborne plays a brief animation (pre-rendered sprite frames).
- **Clean landing:** Trick bonus points added to score + flat speed boost applied.
- **Failed landing** (obstacle hit mid-air or poor landing): No bonus points, speed penalty.

| Button (SNES) | Keyboard | Trick name (TBD) |
|---|---|---|
| A | Arrow Right | Trick A |
| B | Arrow Down | Trick B |
| X | Arrow Up | Trick C |
| Y | Arrow Left | Trick D |

---

## Controls

| Action | Keyboard | SNES Controller |
|---|---|---|
| Accelerate | W | D-pad Up |
| Brake / Reverse | S | D-pad Down |
| Steer Left | A | D-pad Left |
| Steer Right | D | D-pad Right |
| Left shoulder / brake boost | Q | L shoulder |
| Right shoulder | E | R shoulder |
| Trick A | Arrow Right | A |
| Trick B | Arrow Down | B |
| Trick C | Arrow Up | X |
| Trick D | Arrow Left | Y |
| Pause / Menu | Esc | Start |

---

## HUD (top row, 16 px)

All elements fit within the single 16 px HUD tile row at the top of the screen.

| Element | Description |
|---|---|
| **POS** | Current race position (1–6) |
| **LAP** | Current lap / total laps (e.g. `LAP 1/2`) |
| **TIME** | Current lap time (MM:SS.s) |
| **SPEED** | Numeric km/h readout |
| **BOOST** | Boost indicator bar (lights up on boost, fades as boost depletes) |
| **TRICK** | Trick point flash (brief on-screen display on trick landing) |

---

## Scoring

Combined score per race:

```
Score = Position Points + Time Bonus + Trick Points
```

- **Position Points:** Fixed points per finishing place (1st = most, 6th = least).
- **Time Bonus:** Decreasing bonus based on total race time.
- **Trick Points:** Accumulated through clean trick landings during the race.
- No persistence in MVP; scores displayed on results screen only.

---

## Audio

- **Hardware:** 3-channel chiptune (square, triangle, noise, sine) + 1-channel 8-bit wavetable.
- **MVP:** Engine roar only (wavetable channel, pitch scales with speed).
- **Settings:** Volume control (multiple levels + disable), accessible from main menu.
- **Post-MVP additions:** Music, trick jingles, splash/collision effects.

---

## Sprite & Art Requirements

### Player Jet Ski (4×4 tiles = 64×64 px)
- Straight ahead frame
- Lean left (2–3 levels of lean)
- Lean right = horizontal mirror of lean left
- Airborne frame (per trick: 4 variants)
- Multiple distance sizes for when player appears in background (if applicable)

### NPC Racers (1×1 to 4×4 tiles, pre-rendered sizes)
- 4 sizes minimum: 1×1, 2×2, 3×3, 4×4 tiles
- No lean frames (straight-ahead only)
- Each opponent can share the same sprite sheet (differentiated by palette swap, post-MVP)

### Trackside Markers
- Flag sprites at multiple sizes (at minimum 4 scale steps)
- Buoy sprites at multiple sizes

### Obstacles
- Rock / log / buoy obstacle sprites at multiple sizes

### Ramps
- Ramp sprite at multiple sizes

### Background / Scenery
- Per-level scrolling background (sky band, 4 tile rows = 64 px tall, 320 px wide + scroll buffer)

---

## File & Project Structure (proposed)

```
jetski/
├── src/
│   ├── main.c
│   ├── render.c / render.h      # pseudo-3D road renderer
│   ├── physics.c / physics.h    # player physics & collision
│   ├── ai.c / ai.h              # AI playback
│   ├── tricks.c / tricks.h      # trick system
│   ├── hud.c / hud.h            # HUD rendering
│   ├── audio.c / audio.h        # engine sound
│   ├── input.c / input.h        # keyboard + SNES controller
│   ├── dat.c / dat.h            # asset file loader (adapted from wsorrow)
│   └── game.c / game.h          # game state machine (title/menu/race/results)
├── assets/
│   ├── track1/
│   │   ├── track1.dat           # monolithic level asset file
│   │   └── (source art files)
├── tools/
│   ├── dat_packer/              # tool to pack assets into .dat
│   └── ai_recorder/             # tool to record/export AI opponent paths
├── specification.md
└── Makefile
```

---

## MVP Scope Summary

| Feature | MVP | Post-MVP |
|---|---|---|
| 1 course | ✓ | |
| 2 additional courses | | ✓ |
| 5 AI opponents (pre-recorded) | ✓ | |
| Pseudo-3D renderer | ✓ | |
| Palette cycling water | ✓ | |
| Scaled trackside markers | ✓ | |
| Momentum physics | ✓ | |
| 4 tricks + boost | ✓ | |
| Static obstacles | ✓ | |
| Slow-down zone (out of bounds) | ✓ | |
| HUD (pos, lap, time, speed, boost) | ✓ | |
| Title + menu + results screens | ✓ | |
| Engine sound + volume settings | ✓ | |
| Keyboard + SNES controller | ✓ | |
| High score persistence | | ✓ |
| Multiple riders / stat differences | | ✓ |
| Music + SFX | | ✓ |
| Opponent palette differentiation | | ✓ |
