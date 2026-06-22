# 03 — Technical Architecture

## Engine & constraints
- **Godot 4.4.1**, GDScript only, Forward+ renderer.
- All 3D content is **code-built** (primitive meshes + `StandardMaterial3D`); no imported
  art or audio assets, no editor-authored scenes beyond one thin root `.tscn`.
- **No `class_name`** on shared/autoload scripts (avoids circular-import fragility).
  Scripts are wired via `preload(...)` + `.new()` or autoload.
- Dictionary/JSON Variant values are read through explicit `float()/int()/String()` casts.

## Scene graph
```
scenes/main.tscn  →  Node3D (scripts/main.gd)   [project main_scene]
Autoloads:
  Game     → scripts/game_state.gd   (economy, rosters, SHIP_CLASSES tables)
  Capture  → scripts/capture.gd      (headless screenshot driver; inert unless env set)
```
`main.gd` builds everything else at runtime as children: `WorldEnvironment`, lights, a
`MultiMeshInstance3D` starfield, nebula billboards, ship nodes, the chase `Camera3D`, a
`CanvasLayer`+HUD, the crew deck, and the audio node.

## Module responsibilities
| Script | Type | Responsibility |
| --- | --- | --- |
| `main.gd` | `Node3D` | Orchestrator: world build, input/flight, AI, weapons, damage, boarding, economy, fleet, camera, HUD feed, deck toggle. |
| `ship.gd` | `Node3D` | One vessel: per-class procedural mesh, stats, `take_damage` → shield/hull/disable/destroy, faction tinting, engine/shield visual ticks. |
| `game_state.gd` | autoload | Credits, crew/marine pools, capture/purchase counts, `SHIP_CLASSES` data, name RNG. The single source of tunable data. |
| `hud.gd` | `Control` | Immediate-mode `_draw` HUD fed a plain `Dictionary` each frame via `set_data`. |
| `crew_deck.gd` | `Node3D` | Walkable interior, procedural humanoids from the pools, captain movement + follow orders, own camera. |
| `audio.gd` | `Node` | Procedural `AudioStreamWAV` synthesis + a voice pool; `play("trigger")`. |
| `capture.gd` | autoload | Times several beats, toggles the deck via `main.force_deck`, saves PNGs, self-quits. |

## Data flow (per frame)
```
Input ──► main._process ──► (space) flight + AI + weapons + damage + boarding + camera
                         └► (deck)  crew_deck.process_deck
        main._update_hud() builds a Dictionary snapshot ──► hud.set_data() ──► queue_redraw
        ship.tick_visuals(delta) updates engine glow / shield flash
```
The HUD never reaches into game objects; it only renders the snapshot dictionary. This
keeps rendering decoupled and makes the HUD trivially testable.

## Key design decisions & gotchas (learned in-build)
- **Add to tree before transforming.** Setting `global_position` or calling `look_at`
  before `add_child` triggers "Node not inside tree" errors and bad transforms.
  Projectiles, beams, and explosions all `add_child` first.
- **HUD sizing.** A `Control` under a `CanvasLayer` can report `size == 0` before layout
  settles. `hud._draw` uses `get_viewport_rect().size` so the bottom HUD never clips off.
- **Capture race.** `capture.gd` is re-entry-guarded (`_busy`) and only quits after the
  last `await`ed save resolves, so no screenshot is dropped.
- **Procedural audio works headless** with `--audio-driver Dummy`; streams are still
  constructed, so wiring is exercised without a sound device.
- **Neutral safety.** Player projectiles ignore the neutral station so you cannot grief
  your own objective; the station is taken by boarding, not gunfire.

## Determinism & capture
`main.gd` seeds its RNG (`20260623`) so battles and the starfield are reproducible. When
`VOIDBORNE_CAPTURE` is set, `main` enters an **auto-demo** (auto-fire + steer toward
target) so headless frames are lively without human input.

## Performance notes
Single-scene, a few dozen nodes, MultiMesh stars, pooled audio voices, and transient
arrays for projectiles/beams/explosions with explicit `queue_free`. Comfortably real-time
at 1280×720 for the slice's scope.

## Extension points
- New ship class = one entry in `SHIP_CLASSES` + a `match` arm in `ship._build_mesh`.
- New SFX = one entry in `audio.SOUNDS` + a `play()` call (the checker enforces wiring).
- New HUD widget = read another key from the snapshot dict in `hud._draw`.
