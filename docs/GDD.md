# Voidborne Command — Game Design Document (Vertical Slice)

## 1. Vision
A captain-scale space sim where you do not just fly a ship — you build and command a
crew and a fleet. The fantasy: **disable, board, capture, and command.** Take an enemy
hull instead of merely destroying it; recruit the people who make it fly; lead them from
the cockpit and from the deck.

This document scopes the **first playable vertical slice**, which proves every pillar in
simplified, fully code-built form.

## 2. Pillars
1. **Fly your ship** — 6-DoF-ish arcade flight with throttle/boost/brake and yaw/pitch/roll.
2. **Crew & marines** — recruit, see them as humanoids, order them to follow.
3. **Disable → board → capture** — non-lethal takedown of ships and stations.
4. **Buy & command** — purchase ships, man them, and issue fleet orders (follow / hold / escort / defend / dock / attack / patrol / guard station) from the `F` order menu.
5. **Distinct classes** — fighter / corvette / frigate / capital / station.
6. **Live battle** — hostile wing + larger ships + neutral hub + hostile station, with weapons FX and a readable HUD.

## 3. Core loop
```
        ┌─────────────────────────────────────────────┐
        ▼                                             │
   Fly & fight ──► Disable hostile ──► Board w/ marines ──► Capture (faction flips)
        │                                             │
        ▼                                             ▼
   Dock at station ──► Recruit crew/marines ──► Buy ship ──► Man it ──► Fleet grows
        │
        └──► Crew deck: walk among crew, order follow
```

## 4. Systems

### 4.1 Flight model
Arcade-Newtonian. Each ship has `velocity`, a commanded `throttle` (0–1), and rotates in
local space. `velocity` is eased toward `forward * max_speed * throttle` by `accel`.
Boost multiplies target speed and drains energy; brake sharply reduces it. Per-class
`max_speed`, `accel`, and `turn_rate` give each hull a distinct feel.

### 4.2 Combat
- **Projectiles** (cannon): travelling capsule meshes, inherit shooter velocity, expire by range.
- **Beams** (capital/station): instantaneous hitscan with a short-lived cylinder mesh.
- **Damage**: shields absorb first (with a flash), then hull. Energy gates fire rate.
- **Disable threshold**: at ≤22% hull a ship becomes `disabled` (engines die, AI idles) and is boardable.
- **Destruction**: at 0 hull a ship explodes (expanding emissive sphere + SFX).

### 4.2b Subsystem targeting
Every ship has three subsystems — **engines**, **weapons**, **shields** — each a 0..1 health
fraction. The player can press `Z` to cycle a **subsystem focus** on the current target:
none → engines → weapons → shields → none. With a subsystem focused, 50% of post-shield
damage is routed into that subsystem's health and 50% to hull; AI ships always do generic
damage. Subsystem health never regens on its own — only station `H` repair/refit restores it.

| Subsystem | OFFLINE (0.0) | DAMAGED (<0.4) |
| --- | --- | --- |
| Engines | speed/accel 20%, turn 40% | speed/accel 60%, turn 70% |
| Weapons | cannot fire | fire rate halved (2× cooldown) |
| Shields | no regen, bubble collapsed | regen at 30% |

A subsystem below 0.4 is DAMAGED; at 0.0 it is OFFLINE. The HUD target panel shows a compact
ENG/WPN/SHD status strip with the focused subsystem marked by `>`. Subsystem health
round-trips through the versioned save/load schema (optional fields, backward compatible
with v1 saves that lack them).

### 4.3 Boarding & capture
A disabled, non-allied target within range can be boarded (`B`). Boarding is a **resolved
squad action**, not a timer: your marines (`Game.marine_pool`) assault the target's
**defending garrison** and both sides take casualties until one side is gone.

Every ship carries a `marine_garrison` set by class — fighter 0, corvette 2, frigate 4,
capital 8, station 12. When a ship is **disabled** its garrison is halved (rounded down):
some defenders are casualties of the disabling fight. Combat then resolves in fixed
`0.5s` rounds. Each round:
- attacker casualties `= defender_strength × 0.15 × roll(0.7–1.3)`
- defender casualties `= attacker_strength × 0.15 × roll(0.7–1.3)`

(rolls come from the main seeded RNG, and each non-empty side inflicts at least one
casualty per round so small forces never stalemate). Boarding **succeeds** when the
defenders reach 0 — the surviving attackers become the new `marine_pool` and the asset
`set_faction("player")`. Boarding **fails** if the attackers reach 0 first: all your
marines are lost, the boarding is cancelled, and the target stays hostile (still disabled).
A captured asset starts with garrison 0 (the new owner must garrison it themselves —
out of scope this increment). The HUD boarding bar shows nearness to capture (defenders
remaining vs initial) with an `ATK: N  DEF: M` readout; a failed assault prints a
red-tinted `BOARDING FAILED` line.

A successful capture is added to your fleet — **manned** if you have spare crew for its
`crew_needed`, otherwise captured-but-unmanned. Hostile captures pay a boarding bounty
(`18%` of the ship-class value, minimum 100 cr), while destroying a hostile instead pays
smaller salvage (`8%`, minimum 40 cr). This keeps boarding economically superior and feeds
the buy/crew/fleet-growth loop. Stations capture the same way: the seeded
scenario keeps neutral **Halcyon** as the recruit/shipyard hub and adds hostile **Kryos
Relay** as a boardable station-capture objective.

### 4.4 Crew, marines & the deck
`Game.crew_pool` / `Game.marine_pool` are abstract counts spent on manning and boarding.
The **crew deck** (`C`) is a walkable interior that instantiates one procedural humanoid
per pooled crew/marine. The captain avatar walks (WASD) and orders the nearest humanoid
to follow (`F`); followers trail the captain in a loose formation.

### 4.5 Economy & fleet
At the station: recruit crew (120) / marines (180), cycle the shipyard offer with `G`,
and buy the selected class with `Y` (fighter 800, corvette 2200, frigate 5200,
capital 16000). Purchased and captured ships need `crew_needed` crew to be **manned**.
Once no unmanned owned ships need crew, `F` opens the **fleet order menu**; number keys set
the standing order (all routed through `_set_fleet_order()`):

- **`[1]` Follow** — ring formation behind the player, engaging the nearest hostile.
- **`[2]` Hold** — escorts brake at their current tactical points while covering nearby hostiles.
- **`[3]` Escort** — a *tight* defensive ring (half the follow radius) that prioritizes shooting
  any hostile closing on the flagship but never chases past `weapon_range * 0.9` from the captain.
- **`[4]` Defend** — escorts orbit and screen the current target (`fleet_defend_target`) at ~20 u,
  firing on hostiles that approach it. An invalid/hostile target reverts to follow.
- **`[5]` Dock** — manned escorts route to the nearest friendly/neutral station and auto-repair
  hull/shield/energy at half the manual `H` service rate (`_process_docking()`); no station in
  range reverts to follow.
- **`[6]` Attack** — focus-fire the current hostile (`fleet_attack_target`), identical to the `T`
  hotkey, regardless of which enemy is nearest.
- **`[7]` Patrol** — escorts cycle through a player-defined route (`patrol_waypoints`, max 8),
  peeling off to engage hostiles within `weapon_range * 0.8` before returning to the route
  (`_ai_patrol()`). With the order active, `P` drops a waypoint at the flagship's position;
  pressing `[7]` again clears the route. With no waypoints set the order falls back to follow
  formation. Waypoints are sector-local (cleared on system jump) but persist in the save.
- **`[8]` Guard Station** — with a friendly/neutral station as the current target, manned
  escorts anchor in a ~25 u orbit of that station (`fleet_guard_station_name`, mirrored to each
  escort's `guard_station_name`) and engage any hostile that closes within `weapon_range` of it
  (`_ai_guard_station()`). An order without a valid station target reverts to follow, and the
  order self-clears via `_validate_fleet_guard_station()` if the station is destroyed or turns
  hostile. The station assignment round-trips through save/load.

`Esc` (or `F`) closes the menu without changing the order. Attack and defend self-clear via
`_validate_fleet_attack()` / `_validate_fleet_defend()` when their target is destroyed,
captured, or flips faction, guard station self-clears via `_validate_fleet_guard_station()`,
and every fallback resolves to **follow**. The fleet/economy panel
and radar render the standing order as `FOLLOW`, `HOLD`, `ESCORT`, `DEFEND <target>`, `DOCK`,
`ATTACK <target>`, `PATROL (<n> wp)`, or `GUARD STN <name>`.

**Dock services (repair/refit).** While the flagship is within `SERVICE_RANGE` (70 u) of a
**non-hostile** station — the neutral Halcyon hub or any captured/player-owned station —
`H` services the fleet. It restores hull, shields, and energy across the flagship and every
**manned** player-owned mobile ship (unmanned captured hulls and destroyed ships are
skipped) and clears `disabled` on any serviced ship whose repaired hull rises above the
disable threshold. The charge is deterministic: `hull_missing*0.6 + shield_missing*0.35 +
energy_missing*0.15` summed across serviced ships, with a `SERVICE_MIN_CHARGE` (40 cr) floor
when any work is done. If credits can't cover the bill, the dock applies proportional
**partial** repairs and spends only what's available; if nothing is damaged it charges
nothing and reports "all systems nominal". Hostile stations and open space refuse service
(`ui_deny`). The economy panel surfaces an `[H] Repair/refit` cost hint while docked.

### 4.5b Persistence (quick save / quick load)
`V` writes a save and `L` loads one in both space and crew-deck mode (a load returns the
player to the bridge). The save is a **versioned JSON** document at a deterministic path,
`user://voidborne_save.json` — exposed via the `save_path` script variable so tests redirect
it to a scratch file. The schema carries `game_id` (`voidborne_command`), an integer
`version` (currently `1`), an `economy` block (credits, crew/marine pools, captured/purchased
tallies), `shipyard_index`, the standing `fleet_order` and focus-fire target name, the
current target name, and a `ships` array. Each ship entry stores its unique `ship_name`,
`ship_class`, `faction`, `is_player`, `manned`, `crew_assigned`, hull/shield/energy (current
and max), `disabled`/`destroyed` flags, `ai_state`, and `pos`/`rot` float arrays. Destroyed
ships are omitted, so a rebuild never resurrects a cleared hostile.

Loading first **validates** the payload and rejects — without touching live state — anything
that is corrupt/non-object, carries the wrong `game_id`, is missing a required section/field,
has a malformed position/rotation array or unknown ship class, lacks a player flagship, or
declares a `version` greater than the current one. A valid load tears down the live battle,
clears transient state (boarding, projectiles, beams, explosions, fleet hold points), rebuilds
every saved ship, re-wires the `player` and `station` references (preferring the neutral hub,
then an owned, then any non-hostile station so service/shipyard prompts keep working), reverts
an attack order to **follow** if its focus target is gone, and re-acquires a hostile target
when the saved lock is missing. Captured stations/ships stay player-owned, purchased ships
persist, and unmanned prizes stay unmanned. A producer-side Python verifier,
`tools/verify_save_load.py`, mirrors this schema policy independently (wired into
`tools/validate_build.sh`) so drift is caught even without running the engine.

### 4.6 Ship classes
See the table in `README.md` and the authoritative `SHIP_CLASSES` dictionary in
`scripts/game_state.gd`. Each class has distinct stats, silhouette scale, and a unique
procedural mesh (wings, pods, turrets, bridge towers, greebles, torus station).

### 4.7 System map & respawning threats
The slice is a **small single system** with **four stations** spread hundreds of units
apart so travel between them is meaningful: the neutral **Halcyon** recruit/shipyard hub
(the primary dock the `station` reference and all proximity logic point at), the neutral
**Aurora Station** trade outpost, and two capturable hostile stations, **Kryos Relay** and
**Ironhold**. Pressing `M` toggles a centered top-down **system map** overlay (`hud.gd
_draw_system_map`): stations as faction-coloured labelled squares, every other ship as a
dot, the player as a heading arrow, plus a distance-scale bar. It is an overlay, not a
pause — flight stays live, and the open/closed state is transient UI (not saved).

**Respawning threats** keep the sector from going dead: `_update_respawns` watches the live
mobile-hostile count, and once it falls below `RESPAWN_THRESHOLD` (3) a timer runs for
`RESPAWN_INTERVAL` (30 s) before warping in 2–3 fresh hostile fighters (`Raider-N`,
incrementing) at the edge of the system, 360–480 units from the player. Hostile **stations**
are never respawned, and the whole system is disabled during capture/demo mode so
screenshots stay deterministic.

### 4.8 Mission system
The slice ships a set of named **missions** (`main.gd _init_missions`), each a Dictionary with
an `id`, `title`, `desc`, `reward`, a `state` (`active` / `complete` / `failed`), and a list of
`objectives` carrying a `check` tag the per-frame evaluator reads. The five starting missions are:
**Capture Kryos Relay** (3000 cr), **Capture Ironhold** (5000 cr), **Break the Raiders** —
destroy 5 hostile mobile ships, cumulative (1500 cr), **Commission a Frigate** — buy a frigate
at the shipyard (800 cr), and **Build a Fleet** — command 3 manned fleet ships at once (2000 cr).

Pressing `O` (`_cycle_mission`) advances the tracked mission through the open ones, wrapping and
skipping completed/failed entries; the **top-center objective string** is derived from the tracked
mission as `"[<title>] <first incomplete objective>"` (`_current_objective_text`). `_check_missions`
runs on a half-second throttle: for each active mission it marks satisfied objectives done
(`_evaluate_objective` — station capture by faction flip, a cumulative `_destroyed_hostile_count`
counter incremented in `_destroy_ship`, a `_purchased_frigate` flag set in `_buy_ship`, and a live
`_count_fleet()` check). When every objective is done the mission flips to `complete`, pays its
reward into `Game.credits`, logs `MISSION COMPLETE`, and plays `ui_buy`. The HUD draws a compact
top-right **mission panel** (`hud.gd _draw_mission_panel`) showing the title, reward, a state badge,
and each objective with a `[x]`/`[ ]` checkbox. Mission state (per-mission `state`, objective done
flags, the tracking counters, and the current index) is **persisted** in the quick save and restored
on load; old saves without a `missions` key load fine and keep the default active missions.

## 5. HUD
Immediate-mode `_draw` overlay: economy/fleet panel, top-center objective, target panel
(name/faction/class/hull/shield/distance/disabled), bottom-left player bars
(hull/shield/energy/throttle + class & speed), bottom-right **radar** with faction-tinted
blips and a target ring, a center reticle, a boarding progress bar, a rolling message
log, and context prompts.

Target cycling prioritizes hostile contacts while any remain alive; neutral/non-player
assets are fallback targets only after the hostile force is cleared, which keeps the
station market usable without intercepting combat target lock.

## 6. Audio
Procedural — `scripts/audio.gd` synthesizes 16-bit PCM `AudioStreamWAV` tones at runtime
for laser, beam, hit, shield, explosion, disabled, board, capture, UI, and thruster
events. No audio files ship. `tools/check_audio_wiring.py` statically verifies every
declared trigger has a gameplay call site.

## 7. Out of scope for the slice (production backlog)
Station docking interiors, multi-system map, crew skills/morale, mouse-flight, controller
support, real art/audio pipeline, networked or scripted campaign. Tracked in
`docs/studio/definition_of_done.md`. (Single-system **quick save/load** of credits, roster,
and fleet is now shipped — see §4.5b; multi-slot/named saves and multi-system persistence
remain backlog.)
