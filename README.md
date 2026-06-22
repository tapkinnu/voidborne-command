# Voidborne Command

An original Godot 4.4.1 3D space-sim vertical slice: fly your ship, recruit crew and
marines, disable / board / capture hostiles, buy ships, and command a fleet in a live
space battle. Everything is **code-built / procedural** — no imported art assets, no
editor authoring required.

> Status: first playable vertical slice. Every requested mechanic is proven in
> simplified, readable form. See `docs/studio/definition_of_done.md` for the production
> backlog.

---

## Quick start

```bash
# From the project root
/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64 --path . --rendering-driver vulkan
```

Headless validation, screenshots, and checks:

```bash
./tools/validate_build.sh
./tools/capture_screenshots.sh
python3 tools/make_contact_sheet.py artifacts/screenshots artifacts/screenshots/contact_sheet.jpg
python3 tools/check_audio_wiring.py
```

Screenshots are written to `artifacts/screenshots/` (plus a `contact_sheet.jpg`).

---

## Controls

### Flight (space mode)
| Key | Action |
| --- | --- |
| `W` / `S` | Throttle up / down |
| `Shift` | Boost (drains energy) |
| `X` | Brake |
| `A` / `D` | Yaw left / right |
| `↑` / `↓` | Pitch up / down |
| `Q` / `E` | Roll left / right |
| `Space` / LMB | Fire weapons |
| `Tab` | Cycle target |
| `B` | Board a **disabled** target with marines |

### Command & economy (fly near the STATION)
| Key | Action |
| --- | --- |
| `R` | Recruit crew (120 cr) |
| `M` | Recruit marine (180 cr) |
| `Y` | Buy a corvette (auto-mans if crew available) |
| `F` | Man any unmanned owned ships / hold formation |
| `C` | Toggle the **crew deck** interior view |

### Crew deck (interior mode)
| Key | Action |
| --- | --- |
| `A` / `D` / `W` / `S` | Walk the captain |
| `F` | Order the nearest crew/marine to follow / stop |
| `C` | Return to the bridge |

---

## The loop in one paragraph

You start in a corvette with a small fighter wing near a neutral station and a hostile
formation (fighter wing, corvette, frigate, and a capital). Whittle a hostile's hull to
the **disable** threshold (~22%), close within boarding range, and press `B` — marines
breach and a boarding bar fills. On completion the ship **switches to your faction**; if
you have spare crew it is manned and joins your **fleet formation**, otherwise it sits
captured-but-unmanned until you recruit crew. At the station you recruit crew/marines,
buy ships, and step into the **crew deck** to walk among your procedurally-built
humanoid crew and order them to follow you.

## Ship classes

| Class | Hull | Shield | Speed | Turn | Scale | Weapon | Role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Fighter | 60 | 30 | fast | high | 1.0 | cannon | skirmisher |
| Corvette | 160 | 90 | med | med | 2.1 | cannon | player flagship / escort |
| Frigate | 340 | 180 | slow | low | 3.4 | cannon | line ship / board target |
| Capital | 900 | 420 | crawl | min | 6.5 | beam | heavy hitter |
| Station | 1600 | 600 | — | — | 10.0 | beam | recruit / buy / capture hub |

(Full tables in `scripts/game_state.gd` and `docs/GDD.md`.)

## Project layout

```
scenes/main.tscn        Thin scene: a Node3D with scripts/main.gd attached.
scripts/main.gd         Orchestrator: world, flight, combat, AI, boarding, economy, fleet, HUD feed.
scripts/ship.gd         Procedural per-class ship mesh + stats + damage/disable/capture.
scripts/game_state.gd   Autoload "Game": economy, rosters, ship-class data tables.
scripts/hud.gd          Immediate-mode HUD: radar, bars, target panel, objective, messages.
scripts/crew_deck.gd    Walkable interior with procedural humanoid crew/marines.
scripts/audio.gd        Procedural SFX synthesizer (no audio files).
scripts/capture.gd      Autoload that grabs screenshots headlessly, then quits.
tools/                  validate_build.sh, capture_screenshots.sh, make_contact_sheet.py, check_audio_wiring.py
docs/                   GDD + studio briefs + QA gates + DoD.
```

See `docs/studio/03_technical_architecture.md` for the deeper design notes.
