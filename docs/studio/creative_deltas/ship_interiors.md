# Creative Delta: Ship-Type-Specific Interiors

> **Status:** brief (prompts only — GLB generation deferred to implementation card)
> **Date:** 2026-06-28
> **Author:** game-creative
> **Depends on:** `docs/studio/01_creative_bible.md`, `scripts/crew_deck.gd`, `scripts/game_state.gd`
> **Unblocks:** implementation card that runs `tools/meshy_generate.py` and patches `crew_deck.gd`

---

## 1. Problem

`scripts/crew_deck.gd` currently builds the **same 3-room layout** (Bridge, Crew
Quarters, Marine Barracks) at fixed `ROOM_CENTERS = [-10, 0, 10]` regardless of
which ship class the player is on. A fighter's deck is identical to a
station's — the "ugly rectangular rooms" the user wants replaced.

The Meshy visual-upgrade pipeline already supports swapping procedural geometry
for real Meshy GLBs (see `_try_load_meshy_humanoid` in `crew_deck.gd` —
`add_child(rig)`, hide procedural `VisualInstance3D` children, return anim
handle). This brief extends that pattern to swap `_room_container` geometry
for Meshy ship-interior GLBs, with room count, dimensions, and style
parameterised by ship class.

---

## 2. Per-Ship-Class Interior Specs

### Design principles

- **Scale with class.** ROOM_W grows from 6 (fighter) to 22 (station). ROOM_D
  tracks at ~1.5x ROOM_W so larger ships feel spacious, not corridor-narrow.
- **Walkable.** Camera height `EYE_HEIGHT = 2.0` means ceiling must be >= 3.5
  units above floor. All rooms keep ceiling clearance >= 4.0.
- **Palette.** Concord Fleet (player) uses cool blues/teals with emerald
  accents. Sundered Reach (hostile) uses warm rust/red with amber warning
  lighting. Neutral (station) uses desaturated grey with white/cyan readouts.
  Since the crew deck is always the player's ship, the **Concord Fleet palette
  dominates** — but captured-ship interiors can carry faint Sundered rust
  accents as a visual "this was theirs" storytelling detail.
- **Signature feature per class** gives instant silhouette readability even
  from the first-person walk-around view.

---

### 2.1 Fighter (1 room)

| Field | Value |
|---|---|
| Room count | 1 (Cockpit only) |
| ROOM_W | 6.0 |
| ROOM_D | 9.0 |
| crew_needed | 1 |
| garrison | 0 |
| Signature visual | **Wraparound cockpit canopy** — a semi-transparent dome with structural ribbing, single pilot seat, holographic HUD projections. Cramped, intimate, all controls within arm's reach. |
| Palette / mood | Cool blue console glow on dark grey panels. Single warm amber instrument backlight. "One person, one ship, no backup." |

### 2.2 Corvette (3 rooms)

| Field | Value |
|---|---|
| Room count | 3 (Bridge, Crew Quarters, Marine Barracks) |
| ROOM_W | 10.0 |
| ROOM_D | 15.0 |
| crew_needed | 3 |
| garrison | 2 |
| Signature visual | **Cramped corridor** — narrow hallways, exposed cable runs, low ceiling. Every surface is functional. Feels like a submarine. |
| Palette / mood | Desaturated steel-blue walls, warm amber bunk lighting in quarters, red instrument glow in barracks. "Tight ship, tight crew." |

### 2.3 Frigate (5 rooms)

| Field | Value |
|---|---|
| Room count | 5 (Bridge, Engineering, Crew Quarters, Marine Barracks, Armory) |
| ROOM_W | 14.0 |
| ROOM_D | 21.0 |
| crew_needed | 6 |
| garrison | 4 |
| Signature visual | **Central spine corridor** — a clear main hallway running the length of the ship with rooms branching off both sides. You can see from one end to the other. |
| Palette / mood | Cool white overhead strips with teal floor lighting. Engineering has amber hazard striping. Armory has red weapon-rack backlights. "A real warship now." |

### 2.4 Capital (7 rooms)

| Field | Value |
|---|---|
| Room count | 7 (Bridge, CIC, Engineering, Officer Quarters, Crew Quarters, Marine Barracks, Sick Bay) |
| ROOM_W | 18.0 |
| ROOM_D | 27.0 |
| crew_needed | 14 |
| garrison | 8 |
| Signature visual | **Atrium / multi-deck** — a central open space with a catwalk or mezzanine, vertical sightlines between decks. The bridge overlooks a lower CIC level. |
| Palette / mood | Polished white/blue panels with gold trim accents. Officer quarters have warm wood-grain composite. Sick Bay has sterile white with soft blue underglow. "Flagship prestige." |

### 2.5 Station (9 rooms)

| Field | Value |
|---|---|
| Room count | 9 (Command Center, Reactor, Trade Hub, Crew Quarters, Marine Barracks, Brig, Sick Bay, Cargo Bay, Docking Control) |
| ROOM_W | 22.0 |
| ROOM_D | 33.0 |
| crew_needed | 20 |
| garrison | 12 |
| Signature visual | **Radial hub** — a central circular atrium with corridors radiating outward like spokes. The reactor core is visible through reinforced glass at the hub center. |
| Palette / mood | Neutral grey with white structural beams. Trade Hub has colourful holographic advertisements. Reactor has pulsing blue Cherenkov-style glow. Brig has harsh red overhead. "A small city in the void." |

---

## 3. Meshy Prompt Pack

Each prompt below is a verbatim string for `tools/meshy_generate.py`. All
prompts target:
- **Non-rigged** prop (no animation)
- **target_polycount:** ~15000–25000
- **art_style:** "realistic"
- **Keywords appended to every prompt:** `hard surface, game asset, clean topology, walkable interior, no exterior hull`

---

### fighter_cockpit

prompt: "low-poly sci-fi fighter cockpit interior, single pilot seat, wraparound transparent canopy dome with structural ribbing, holographic HUD projections floating in air, control panels with glowing blue displays, cramped intimate space, dark grey panels with cool blue console glow, hard surface, game asset, clean topology, walkable interior, no exterior hull"

---

### corvette_bridge

prompt: "low-poly sci-fi corvette bridge interior, central captain chair, curved console panels with glowing blue displays, forward viewport showing stars, cramped submarine-like space, exposed cable runs, desaturated steel-blue walls, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### corvette_crew_quarters

prompt: "low-poly sci-fi corvette crew quarters interior, two-tier bunk beds against wall, personal lockers, warm amber bunk lighting, cramped narrow space, desaturated blue-grey walls, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### corvette_marine_barracks

prompt: "low-poly sci-fi corvette marine barracks interior, fold-down bunks, weapon rack with rifles, equipment lockers, red instrument glow accent lighting, cramped military sleeping quarters, hard surface, game asset, clean topology, walkable interior, no exterior hull"

---

### frigate_bridge

prompt: "low-poly sci-fi frigate bridge interior, elevated captain chair, wide panoramic console desk with multiple crew stations, holographic tactical display table, cool white overhead lighting with teal accents, central spine corridor visible through doorway, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### frigate_engineering

prompt: "low-poly sci-fi frigate engineering room interior, wall-mounted reactor coolant pipes, power junction boxes with amber hazard striping, tool racks, warning lights, industrial machinery, exposed conduits on ceiling, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### frigate_crew_quarters

prompt: "low-poly sci-fi frigate crew quarters interior, four bunk beds in two rows, personal reading lights, fold-down desks, warm neutral lighting, spacious military dormitory, teal floor lighting strips, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### frigate_marine_barracks

prompt: "low-poly sci-fi frigate marine barracks interior, reinforced bunk frames, equipment staging area, weapon cleaning station, red overhead accent lighting, military readiness room, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### frigate_armory

prompt: "low-poly sci-fi frigate armory interior, floor-to-ceiling weapon racks with rifles and sidearms, armour locker cabinets, ammunition crates, red weapon-rack backlight glow, reinforced door frame, hard surface, game asset, clean topology, walkable interior, no exterior hull"

---

### capital_bridge

prompt: "low-poly sci-fi capital ship bridge interior, grand elevated command platform, multiple officer stations with holographic displays, panoramic forward windows showing space, gold trim accents on white panels, catwalk overlooking lower level, prestigious flagship command center, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### capital_cic

prompt: "low-poly sci-fi capital ship CIC interior, Combat Information Center with large central holographic tactical table, surrounding operator stations, multi-tier layout with catwalk above, blue holographic glow illuminating operators from below, white and blue paneling, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### capital_engineering

prompt: "low-poly sci-fi capital ship engineering interior, massive reactor housing with glowing coolant pipes, control consoles in a gallery arrangement, amber and blue status lights, catwalk grating floor, industrial cathedral scale, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### capital_officer_quarters

prompt: "low-poly sci-fi capital ship officer quarters interior, private single cabin, wood-grain composite desk, personal holographic display, warm ambient lighting, porthole window showing stars, comfortable military accommodation, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### capital_crew_quarters

prompt: "low-tier sci-fi capital ship crew quarters interior, eight bunk beds in open bay, personal storage lockers, soft blue-white overhead lighting, spacious military dormitory, clean white panels with teal accents, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### capital_marine_barracks

prompt: "low-poly sci-fi capital ship marine barracks interior, reinforced bunk frames in rows, equipment armoury along walls, red accent strip lighting, military staging area with weapon racks, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### capital_sick_bay

prompt: "low-poly sci-fi capital ship sick bay interior, two medical beds with overhead surgical lights, diagnostic equipment on walls, medicine cabinets with blue underglow, sterile white panels with soft blue ambient lighting, clean medical bay, hard surface, game asset, clean topology, walkable interior, no exterior hull"

---

### station_command_center

prompt: "low-poly sci-fi space station command center interior, circular room with central command holographic globe, surrounding operator stations, panoramic windows showing docking ships, neutral grey walls with white structural beams, cool white overhead lighting, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### station_reactor

prompt: "low-poly sci-fi space station reactor room interior, central reactor core visible through reinforced glass housing, pulsing blue Cherenkov-style glow, coolant pipe arrays on walls, radiation warning markings, catwalk around the core, industrial hazard lighting, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### station_trade_hub

prompt: "low-poly sci-fi space station trade hub interior, open market stalls with holographic advertisement displays, colourful neon signs, civilian foot traffic area, neutral grey floor with coloured lighting from vendor booths, bustling commercial atmosphere, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### station_crew_quarters

prompt: "low-poly sci-fi space station crew quarters interior, modular bunk pods in rows, personal storage, soft warm lighting, civilian-military hybrid accommodation, grey panels with cyan accent strips, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### station_marine_barracks

prompt: "low-poly sci-fi space station marine barracks interior, military bunk area within station, weapon lockers, equipment staging, red overhead accent lighting, security force quarters, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### station_brig

prompt: "low-poly sci-fi space station brig interior, reinforced cell with energy barrier across doorway, harsh red overhead lighting, single cot, grey walls with warning markings, detention cell, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### station_sick_bay

prompt: "low-poly sci-fi space station sick bay interior, three medical beds with diagnostic scanners, medicine storage with blue glow, surgical robot arm mounted on ceiling, sterile white panels with soft blue lighting, station medical facility, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### station_cargo_bay

prompt: "low-poly sci-fi space station cargo bay interior, large open space with stacked shipping containers, cargo crane rail on ceiling, yellow hazard floor markings, industrial lighting, forklift parking area, hard surface, game asset, clean topology, walkable interior, no exterior hull"

### station_docking_control

prompt: "low-poly sci-fi space station docking control interior, window overlooking docking bay with small ship attached, control console with status displays, communication equipment, white and grey paneling with blue status lights, airlock control station, hard surface, game asset, clean topology, walkable interior, no exterior hull"

---

## 4. Integration Plan

### 4.1 New data structure in `crew_deck.gd`

Define a new constant dictionary mapping ship class to ordered list of room
basenames (matching the Meshy GLB basenames):

```gdscript
const MESHY_INTERIOR_GLB: Dictionary = {
    "fighter":  ["fighter_cockpit"],
    "corvette": ["corvette_bridge", "corvette_crew_quarters", "corvette_marine_barracks"],
    "frigate":  ["frigate_bridge", "frigate_engineering", "frigate_crew_quarters",
                 "frigate_marine_barracks", "frigate_armory"],
    "capital":  ["capital_bridge", "capital_cic", "capital_engineering",
                 "capital_officer_quarters", "capital_crew_quarters",
                 "capital_marine_barracks", "capital_sick_bay"],
    "station":  ["station_command_center", "station_reactor", "station_trade_hub",
                 "station_crew_quarters", "station_marine_barracks", "station_brig",
                 "station_sick_bay", "station_cargo_bay", "station_docking_control"],
}
```

And a dimensions table:

```gdscript
const CLASS_ROOM_DIMS: Dictionary = {
    "fighter":  {"w": 6.0,  "d": 9.0},
    "corvette": {"w": 10.0, "d": 15.0},
    "frigate":  {"w": 14.0, "d": 21.0},
    "capital":  {"w": 18.0, "d": 27.0},
    "station":  {"w": 22.0, "d": 33.0},
}
```

### 4.2 Per-class room build

Replace the current `ROOM_NAMES`, `ROOM_W`, `ROOM_CENTERS`, `ROOM_BOUNDARIES`
constants with **dynamic values** derived from `MESHY_INTERIOR_GLB[current_class]`:

```gdscript
var current_class: String = "corvette"
var ROOM_NAMES: Array = []
var ROOM_W: float = 10.0
var ROOM_D: float = 15.0
var ROOM_CENTERS: Array = []
var ROOM_BOUNDARIES: Array = []
```

A new function `_reconfigure_for_class(cls: String)` computes `ROOM_NAMES`,
`ROOM_W`, `ROOM_D`, `ROOM_CENTERS` (evenly spaced along X), and
`ROOM_BOUNDARIES` (midpoints between centers) from the dictionary.

### 4.3 GLB swap on ship switch

When `cycle_ship()` or `set_ship_list()` is called and the ship class changes:

1. Read `ship_list[current_ship_index].class` (lowercase key into `SHIP_CLASSES`).
2. Call `_reconfigure_for_class(new_class)`.
3. Call `_build_all_rooms()` — which now loads Meshy GLBs per room.
4. If a GLB is missing, fall back to the existing procedural box geometry.

### 4.4 Room geometry with GLB fallback

`_build_room_geometry(idx)` is extended:

```gdscript
func _build_room_geometry(idx: int) -> void:
    var cx: float = float(ROOM_CENTERS[idx])
    var room_name: String = String(ROOM_NAMES[idx])
    var glb_basename: String = _glb_name_for_room(room_name)

    # Try Meshy GLB first
    var loaded: bool = _try_load_meshy_room(glb_basename, idx, cx)
    if loaded:
        return

    # Fallback: existing procedural box geometry (current implementation)
    _build_procedural_room(idx)
```

`_try_load_meshy_room` mirrors `_try_load_meshy_humanoid`:
- Load `res://assets/models/meshy_visual_upgrade/<glb_basename>.repacked.glb`
- Instantiate, add to `_room_container` at the room's X center
- Hide procedural `VisualInstance3D` children of the placeholder
- Return `true` on success, `false` on missing/failed load

### 4.5 Walkable bounds

`process_deck()` already computes `min_x`, `max_x`, `hd` from `ROOM_CENTERS`
and `ROOM_W`/`ROOM_D`. Since these are now dynamic per class, the bounds
automatically scale. No change needed to the movement logic — it already
reads the current values each frame.

### 4.6 Doorway logic

`ROOM_BOUNDARIES` is recomputed by `_reconfigure_for_class` as midpoints
between adjacent `ROOM_CENTERS`. The existing doorway-gap check in
`process_deck()` (`abs(new_pos.z) > DOOR_HALF`) works unchanged.

---

## 5. Asset Manifest

```json
{
  "project": "voidborne-command",
  "destination": "res://assets/models/meshy_visual_upgrade/",
  "total_assets": 25,
  "assets": [
    {"id": "fighter_cockpit",             "ship_class": "fighter",  "room_name": "Cockpit",            "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "corvette_bridge",             "ship_class": "corvette", "room_name": "Bridge",            "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "corvette_crew_quarters",      "ship_class": "corvette", "room_name": "Crew Quarters",     "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "corvette_marine_barracks",    "ship_class": "corvette", "room_name": "Marine Barracks",   "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "frigate_bridge",              "ship_class": "frigate",  "room_name": "Bridge",            "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "frigate_engineering",         "ship_class": "frigate",  "room_name": "Engineering",       "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "frigate_crew_quarters",      "ship_class": "frigate",  "room_name": "Crew Quarters",     "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "frigate_marine_barracks",    "ship_class": "frigate",  "room_name": "Marine Barracks",   "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "frigate_armory",              "ship_class": "frigate",  "room_name": "Armory",            "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "capital_bridge",              "ship_class": "capital",  "room_name": "Bridge",            "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "capital_cic",                 "ship_class": "capital",  "room_name": "CIC",               "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "capital_engineering",         "ship_class": "capital",  "room_name": "Engineering",       "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "capital_officer_quarters",   "ship_class": "capital",  "room_name": "Officer Quarters",  "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "capital_crew_quarters",      "ship_class": "capital",  "room_name": "Crew Quarters",     "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "capital_marine_barracks",    "ship_class": "capital",  "room_name": "Marine Barracks",   "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "capital_sick_bay",            "ship_class": "capital",  "room_name": "Sick Bay",          "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_command_center",      "ship_class": "station",  "room_name": "Command Center",    "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_reactor",             "ship_class": "station",  "room_name": "Reactor",           "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_trade_hub",           "ship_class": "station",  "room_name": "Trade Hub",         "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_crew_quarters",       "ship_class": "station",  "room_name": "Crew Quarters",     "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_marine_barracks",     "ship_class": "station",  "room_name": "Marine Barracks",   "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_brig",                "ship_class": "station",  "room_name": "Brig",              "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_sick_bay",            "ship_class": "station",  "room_name": "Sick Bay",          "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_cargo_bay",           "ship_class": "station",  "room_name": "Cargo Bay",         "rigged": false, "target_polycount": [15000, 25000]},
    {"id": "station_docking_control",     "ship_class": "station",  "room_name": "Docking Control",   "rigged": false, "target_polycount": [15000, 25000]}
  ]
}
```

---

## 6. Acceptance Criteria

| # | Check | Pass condition |
|---|---|---|
| AC1 | Headless import | `godot --headless --quit` exits 0, no `SCRIPT ERROR` in stderr |
| AC2 | All GLBs exist | Every `res://assets/models/meshy_visual_upgrade/<id>.repacked.glb` file exists on disk |
| AC3 | All GLBs load | Each GLB passes `load()` and `instantiate()` without error in headless mode |
| AC4 | Fighter = 1 room | Switching to fighter shows exactly 1 room, ROOM_W=6, ROOM_D=9 |
| AC5 | Corvette = 3 rooms | Switching to corvette shows 3 rooms, ROOM_W=10, ROOM_D=15 |
| AC6 | Frigate = 5 rooms | Switching to frigate shows 5 rooms, ROOM_W=14, ROOM_D=21 |
| AC7 | Capital = 7 rooms | Switching to capital shows 7 rooms, ROOM_W=18, ROOM_D=27 |
| AC8 | Station = 9 rooms | Switching to station shows 9 rooms, ROOM_W=22, ROOM_D=33 |
| AC9 | Walkable bounds | Captain can walk the full length of each deck; clamps match ROOM_W/ROOM_D |
| AC10 | Doorway pass-through | Captain can pass between rooms through doorway gaps; blocked by walls |
| AC11 | Fallback works | Renaming/removing a GLB causes procedural box geometry to appear (no crash) |
| AC12 | Visual distinction | Screenshots of each class show visibly different room layouts and scales |
| AC13 | No regression | Existing humanoid Meshy swap (`_try_load_meshy_humanoid`) still works |
| AC14 | Performance | Crew deck loads in < 2s with all 9 station rooms on modest hardware |

---

## 7. Out of Scope

- **GLB generation** — this brief only produces prompts. A follow-up
  implementation card runs `tools/meshy_generate.py` with the 25 new assets.
- **Exterior ship models** — already handled by the existing `MESHY_SHIP_GLB`
  pipeline.
- **Animation** — interior rooms are static props. No rigging, no skeletal
  animation.
- **Lighting bake** — Meshy outputs untextured/unlit GLBs. Lighting is handled
  in-engine by the existing `DirectionalLight3D` + `OmniLight3D` setup in
  `_build_room_geometry`.
- **Faction-specific interior variants** — the crew deck is always the
  player's ship (Concord Fleet palette). Captured ships reuse the same
  interior GLBs; faction identity is conveyed by exterior hull tint, not
  interior geometry.
