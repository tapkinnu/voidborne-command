# 00 — Master Brief

## Product
**Voidborne Command** — an original captain-scale 3D space simulator built in Godot
4.4.1 with GDScript and fully procedural / code-built 3D content (no editor authoring,
no imported art).

## Mandate
Ship a **first playable vertical slice** that visibly proves, in one runnable scene,
every requested mechanic:

1. Fly your own ship (throttle, boost, brake, yaw/pitch/roll, weapons, target cycling,
   hull/shield/energy, third-person camera, readable HUD).
2. Recruit crew and marines at a station; interact with them in an in-game interaction
   view (crew deck) and order them to follow the captain.
3. Disable, board (with visible progress), and capture hostile ships/stations; captured
   units switch faction and become the player's.
4. Buy ships at a station; assign crew so they are manned; manned ships follow in fleet
   formation.
5. Distinct ship classes: fighter, corvette, frigate, capital (+ station).
6. A live space battle: hostile wing, a larger hostile ship, a station, beams /
   projectiles / explosions, radar / target lock / objective HUD.

## Non-negotiables
- Runs headlessly; imports and smoke-runs with **no** `SCRIPT ERROR`, `Parse Error`, or
  `Invalid call`.
- Capture pipeline produces non-black screenshots that show the battle, the
  player/fleet/target/station, and the HUD.
- A small, robust script set over many fragile hand-authored `.tscn` files.
- No `class_name` on autoloads; explicit typing for Dictionary/JSON Variant values.
- Engine artifacts (`.godot/`, `.import`, caches) and screenshots stay out of git.

## Success = the four acceptance commands pass
```
./tools/validate_build.sh
./tools/capture_screenshots.sh
python3 tools/make_contact_sheet.py artifacts/screenshots artifacts/screenshots/contact_sheet.jpg
python3 tools/check_audio_wiring.py
```

## Team-of-one workflow
Foundation engineer (this pass) delivers the slice + docs + tools. Hermes owns Kanban
lifecycle, review, and handoff. Production tasks beyond the slice are captured in
`definition_of_done.md`.
