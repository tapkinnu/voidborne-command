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

# Optional: screenshot regression baseline + diff
./tools/save_baseline.sh
python3 tools/screenshot_diff.py artifacts/baseline artifacts/screenshots
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
| `Tab` | Cycle hostile targets first (neutral assets only after hostiles are cleared) |
| `T` | Order your manned fleet to **attack / focus-fire** the current target (same as menu `[6]`) |
| `B` | Board a **disabled** target with marines |
| `V` / `L` | **Quick save / quick load** the current battle (versioned `user://voidborne_save.json`) |
| `F5` | Open the **save/load slot menu** — 6 named slots (`user://saves/slot_N.json`) with an in-game overlay to save, load, rename, or delete |
| (auto) | **Autosave** every 60 s of active flight + on jump/capture (separate `user://voidborne_autosave.json`) |
| `Z` | **Cycle subsystem focus** on the current target: none → engines → weapons → shields → none |
| `` ` `` (backtick) | Toggle **mouse-aim flight** — captures the cursor; mouse X→yaw, mouse Y→pitch (additive over keyboard) |
| `F1` | Toggle the **settings overlay** — interactive menu: resolution, volume, graphics quality, pause, mouse-aim, control scheme |
| `P` | **Pause** the game (flight/AI/combat freeze; HUD shows a "PAUSED" banner). Press `P` again to resume. *(Exception: while the fleet is on the **Patrol** order, `P` drops a patrol waypoint instead — see the command section.)* |
| `F2` | **Cycle control scheme**: Auto → Keyboard+Mouse → Gamepad → Auto |
| `M` | Toggle the **system map** overlay — top-down view of all stations, fleet, and threats (flight stays live); also lists the jump gates |
| `K` | **Jump to the next star system** — warps the player and the owned fleet to the next sector (three systems cycle); economy/crew/missions carry over; **captured stations persist** across jumps |
| `U` | **Open mission-giver overlay** — full list of all missions (active, complete, failed, locked) with cursor navigation; `Enter` to track, `A` to abandon, `U`/`Esc` to close |
| `O` | **Cycle active missions** — switches the tracked objective through the open missions; HUD panel and top-center objective follow the selection |

### Gamepad (when connected)
| Control | Action |
| --- | --- |
| Left stick | Yaw / pitch |
| Right stick X | Roll left / right |
| Triggers (L/R) | Throttle down / up |
| A / Cross | Fire weapons |
| B / Circle | Cycle targets |
| LB / RB | Brake / Boost |
| Y / Triangle | Board disabled target |
| Back / Select | Toggle crew deck |
| Start / Menu | Toggle mouse-aim |

In **Auto** mode both keyboard+mouse and gamepad work simultaneously. **Keyboard+Mouse** mode ignores gamepad axes; **Gamepad** mode ignores keyboard flight (UI keys like save/load still work).

### Settings menu (F1)
| Key | Action |
| --- | --- |
| `F1` / `Esc` | Open / close the settings overlay |
| `↑` / `↓` | Move the cursor between rows |
| `←` / `→` | Change the value of the highlighted row (resolution, volume, graphics) or toggle booleans (pause, mouse-aim, scheme) |
| `Enter` | Toggle the highlighted boolean (same as `→`) |
| `1`–`6` | Jump directly to a row (Resolution, Volume, Graphics, Pause, Mouse Aim, Scheme) |

The settings overlay shows six rows: **Resolution** (1280×720 / 1600×900 / 1920×1080),
**Volume** (0–100 %, mute at 0), **Graphics quality** (Low / Medium / High — toggles glow
and MSAA), **Pause**, **Mouse Aim**, and **Control Scheme**. While the menu is open,
flight input is ignored. Settings are display preferences — they are not saved to the
save file.

### Save / load slot menu (F5)
| Key | Action |
| --- | --- |
| `F5` / `Esc` | Open / close the save/load overlay |
| `↑` / `↓` | Move the cursor between the six slots |
| `S` / `D` | Switch to **Save** mode / **Load** mode |
| `Enter` | Confirm: write the selected slot (Save) or read it (Load) |
| `R` | Rename the selected slot (cycles a preset list of labels) |
| `X` / `Del` | Delete the selected slot (asks for `Enter` to confirm) |

The slot menu manages **six named saves** in `user://saves/slot_1.json` … `slot_6.json`.
Each slot reuses the exact same save format and version as quick-save, so a slot save is
just a quick-save written to its own file — the `V`/`L` quick-save slot and the autosave
slot are never touched. A small `user://saves/slots_meta.json` sidecar caches each slot's
label, credits, fleet size, system, and timestamp for the menu; if it is lost or corrupt
it is rebuilt by scanning the slot files. While the menu is open, flight/AI/combat freeze.

### Command & economy (fly near the STATION)
| Key | Action |
| --- | --- |
| `J` | Open the **station market/dock screen** (multi-tab: Shipyard / Crew / Repair / Info) — only at a friendly station |
| `R` | Recruit crew (120 cr) |
| `N` | Recruit marine (180 cr) |
| `G` | Cycle the station shipyard offer (fighter / corvette / frigate / capital) |
| `Y` | Buy the selected shipyard class (auto-mans if crew available) |
| `H` | **Repair / refit**: restore hull, shields, and energy across your flagship and manned fleet (cost scales with damage; partial work if short on credits) |
| `F` | Man any unmanned owned ships; if none need crew, open/close the **fleet order menu** |
| `1`–`7` | While the fleet order menu is open: `[1]` Follow · `[2]` Hold · `[3]` Escort · `[4]` Defend target · `[5]` Dock · `[6]` Attack target · `[7]` Patrol (press `[7]` again to clear the route) |
| `P` | While on the **Patrol** order: drop a patrol waypoint at the flagship's current position (otherwise `P` pauses/resumes) |
| `Esc` | Close the fleet order menu without changing the order |
| `C` | Toggle the **crew deck** interior view |

Repair/refit works at the neutral **Halcyon** hub *and* at any station you have captured. Hostile stations refuse service until taken.

Press `J` near a friendly station to open the **station market** — a multi-tab screen consolidating shipyard purchases, crew/marine recruitment, fleet repair/refit, and station info. Navigate tabs with `←`/`→` (or `Tab`), rows with `↑`/`↓`, and confirm with `Enter`. The screen freezes flight while open (the underlying single-key actions still work too).

### Crew deck (interior mode)
| Key | Action |
| --- | --- |
| `A` / `D` / `W` / `S` | Walk the captain |
| `F` | Order the nearest crew/marine to follow / stop |
| `C` | Return to the bridge |
| `R` | Cycle to the next owned ship's deck |
| `V` / `L` | Quick save / quick load (a load returns you to the bridge) |

The crew deck has three rooms — **Bridge** (pilots/engineers at command consoles),
**Crew Quarters** (gunners at bunks), and **Marine Barracks** (marines at weapon racks).
Walk through the door gaps at the room boundaries to move between rooms. The HUD shows
the current ship and room. Press `R` to step onto a different owned ship's deck (when
you have captured or purchased additional ships).

---

## The loop in one paragraph

You start in a corvette with a small fighter wing near a neutral station and a hostile
formation (fighter wing, corvette, frigate, capital, and a hostile relay station). The system
spans **four stations** — the neutral **Halcyon** recruit/shipyard hub and **Aurora Station**
trade outpost, plus the capturable hostile **Kryos Relay** and **Ironhold** — spread hundreds
of units apart, so travelling between them takes real time. Press `M` for a top-down **system
map** to navigate. The sector also **respawns threats**: once mobile hostiles thin out, a
fresh raider wing warps in from the edge of the system, so the battle never simply ends. `Tab`
cycles combat hostiles first so the neutral shipyard hub does not steal target lock.
Whittle a hostile ship or a hostile station (**Kryos Relay** / **Ironhold**) to the **disable** threshold
(~22%), close within boarding range, and press `B` — your marines breach and fight the
target's **defending garrison** in a resolved **squad action**. Each round both sides take
casualties (scaled by their strength and a seeded roll); boarding **succeeds** when the
defenders are cleared and **fails** — losing all your marines — if your boarders are wiped
first. Attacker casualties first **wound** marines (W1 light → W3 critical, spreading across
the squad) — wounded marines fight at reduced effectiveness (`1.0 − wounds×0.25` each) and
only die once fully wounded, so survivors limp home injured rather than dead. Dock at a
friendly station (`H`) to **patch up** the whole squad back to full health; the crew deck
tags wounded marines (`W#`, colour-coded) and the HUD shows the wounded count (`Marines: N (W:n)`).
Bigger hulls garrison more marines (corvette 2 → frigate 4 → capital 8 → station 12),
so disabling them first (which already halves the garrison) and bringing enough marines
matters. On a successful boarding the asset **switches to your faction**, the surviving
attackers become your marine pool, and hostile captures pay a better
credit bounty than simple destruction salvage; if you have spare crew it is
manned and joins your **fleet formation**, otherwise it sits captured-but-unmanned until
you recruit crew. Docking at a friendly station (the neutral hub or a captured one) also
unlocks a `H` **repair/refit** service that restores hull, shields, and energy across your
flagship and every manned fleet ship, charging credits in proportion to the damage actually
mended — and applying partial work when your treasury can't cover a full overhaul. At the
neutral station you recruit crew/marines, cycle a shipyard offer
across fighter/corvette/frigate/capital classes, buy the selected ship, and step into the
**crew deck** to walk among your procedurally-built humanoid crew and order them to follow
you. Once ships are manned, `F` opens the **fleet order menu** — pick an order with the
number keys: `[1]` **Follow** (ring formation on the flagship), `[2]` **Hold** (pin the
current tactical positions while covering nearby hostiles), `[3]` **Escort** (a tight
defensive ring that shoots any hostile closing on the captain but never chases far), `[4]`
**Defend** (orbit and screen your current target), `[5]` **Dock** (head to the nearest
friendly station and auto-repair at half the manual rate), `[6]` **Attack** (focus-fire
the current target — the same order as the `T` hotkey), or `[7]` **Patrol** (described
below). `Esc` closes the menu without changing the order. Attack and defend orders
self-clear when their target is destroyed, captured, or turns friendly/hostile, and dock
reverts to follow if no station is in range — in each case the fleet falls back to follow.
The fleet/economy panel and radar ping show the standing order (`FOLLOW`, `HOLD`, `ESCORT`,
`DEFEND <target>`, `DOCK`, `ATTACK <target>`, or `PATROL (<n> wp)`).

**Patrol routes.** With the **Patrol** order set (`[7]`), fly the flagship to a spot and
press `P` to drop a patrol **waypoint** there; drop up to eight (the oldest rolls off after
that). Your manned escorts then cycle through the waypoints in order, peeling off to engage
any hostile that strays within weapon range before returning to the route. Pressing `[7]`
again while already patrolling **clears** the route. Waypoints are positions in the current
sector, so they are wiped when you jump to a new system; the route itself is saved with the
game. (Outside the Patrol order, `P` keeps its usual pause behaviour.)

At any point press `V` to **quick-save** and `L` to **quick-load**. The save is a versioned
JSON document (`user://voidborne_save.json`) carrying your economy (credits, crew/marine
pools, captured/purchased tallies), the shipyard offer, the standing fleet order, and every
live ship and station — class, faction, ownership, manned/crew state, hull/shield/energy,
disabled flag, and position/rotation. Loading rebuilds the whole battle: your flagship and
fleet return, captured stations and ships stay yours, purchased ships persist, unmanned
prizes stay unmanned, and destroyed or already-cleared hostiles do **not** come back. A save
is rejected (without touching your current game) if it is corrupt, is not a Voidborne save,
is missing required sections, or was written by a newer game version.

The game also **autosaves** to a separate slot (`user://voidborne_autosave.json`) every 60 s
of active flight, on every system jump, and whenever you capture a ship or station. The
autosave never overwrites your manual save — `L` always loads the manual slot.

While targeting a hostile, press `Z` to **cycle subsystem focus**: none → engines → weapons →
shields → none. With a subsystem focused, half of your post-shield damage is routed into that
subsystem's health pool (0–1) and half goes to hull as normal; AI ships always do generic
damage. An **OFFLINE** engine subsystem cuts a ship's speed/accel to 20% and turn to 40%;
OFFLINE weapons prevent firing entirely; OFFLINE shields collapse the bubble and stop regen.
**Damaged** subsystems (below 40%) apply partial penalties. Subsystem health does not regen
on its own — only the station `H` repair/refit service restores it, and it round-trips through
save/load. The target panel shows a compact ENG/WPN/SHD status strip with the focused one
marked.

### Independent turrets

Larger ships fight with **independently-tracking turret mounts** instead of a fixed muzzle
volley. Frigates (2 mounts, ±110° arc), capitals (8 broadside mounts, ±85° arc) and stations
(4 mounts, ±170° arc) each rotate their turrets toward the ship's current target, clamped to
the mount's fire arc. Every turret carries its own cooldown and fires only when it is both
ready and aimed — so muzzles fire one at a time from their tracked angle rather than all at
once. Fighters and corvettes keep the classic all-muzzle volley. The weapons subsystem still
gates every turret (OFFLINE = no fire, DAMAGED = half rate).

## Ship classes

| Class | Hull | Shield | Speed | Turn | Scale | Weapon | Role |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Fighter | 60 | 30 | fast | high | 1.0 | cannon | skirmisher |
| Corvette | 160 | 90 | med | med | 2.1 | cannon | player flagship / escort |
| Frigate | 340 | 180 | slow | low | 3.4 | cannon | line ship / board target |
| Capital | 900 | 420 | crawl | min | 6.5 | beam | heavy hitter |
| Station | 1600 | 600 | — | — | 10.0 | beam | recruit / buy / capture hub |

(Full tables in `scripts/game_state.gd` and `docs/GDD.md`.)

### Named crew & marines

Crew and marines are no longer just numbers — each crew member has a name, a role
(pilot, engineer, or gunner), a skill level (1–10), and morale, and each marine has a
name, skill, and morale. When assigned to a ship, crew skills directly modify its
combat stats: pilots boost speed and turn rate, engineers boost acceleration, and
gunners boost weapon damage and fire rate. Marines are named individuals in a
`marine_roster` (mirroring the crew roster); boarding draws your available marines
(highest-skill first), suffers casualties by count, and restores the survivors by
name. Recruit crew and marines at the station, then step onto the **crew deck** to
see each crew member's and marine's name and skill displayed above their humanoid
avatar.

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
