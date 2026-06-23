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
4. **Buy & command** — purchase ships, man them, and issue follow/hold/attack fleet orders.
5. **Distinct classes** — fighter / corvette / frigate / capital / station.
6. **Live battle** — hostile wing + larger ships + station, with weapons FX and a readable HUD.

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

### 4.3 Boarding & capture
A disabled, non-allied target within range can be boarded (`B`). A boarding bar fills at
a rate scaled by your marine count. On completion the ship `set_faction("player")`,
consumes marines, and is added to your fleet — **manned** if you have spare crew for its
`crew_needed`, otherwise captured-but-unmanned. Stations capture the same way and become
your hub.

### 4.4 Crew, marines & the deck
`Game.crew_pool` / `Game.marine_pool` are abstract counts spent on manning and boarding.
The **crew deck** (`C`) is a walkable interior that instantiates one procedural humanoid
per pooled crew/marine. The captain avatar walks (WASD) and orders the nearest humanoid
to follow (`F`); followers trail the captain in a loose formation.

### 4.5 Economy & fleet
At the station: recruit crew (120) / marines (180), cycle the shipyard offer with `G`,
and buy the selected class with `Y` (fighter 800, corvette 2200, frigate 5200,
capital 16000). Purchased and captured ships need `crew_needed` crew to be **manned**.
Once no unmanned owned ships need crew, `F` toggles the active fleet order between
**follow** (ring formation behind the player, with nearest-enemy engagement) and
**hold** (escorts brake at their current tactical points while still covering nearby
hostiles). `T` issues an explicit **attack** order: with a valid hostile selected, every
manned escort breaks off to focus-fire that one target (`fleet_order = "attack"`,
`fleet_attack_target` stored) regardless of which enemy is nearest. The order auto-clears
back to **follow** the instant the target is destroyed, captured, turns friendly, or
becomes invalid; toggling `F` also clears it. The fleet/economy panel and radar render the
standing order as `FOLLOW`, `HOLD`, or `ATTACK <target>`.

### 4.6 Ship classes
See the table in `README.md` and the authoritative `SHIP_CLASSES` dictionary in
`scripts/game_state.gd`. Each class has distinct stats, silhouette scale, and a unique
procedural mesh (wings, pods, turrets, bridge towers, greebles, torus station).

## 5. HUD
Immediate-mode `_draw` overlay: economy/fleet panel, top-center objective, target panel
(name/faction/class/hull/shield/distance/disabled), bottom-left player bars
(hull/shield/energy/throttle + class & speed), bottom-right **radar** with faction-tinted
blips and a target ring, a center reticle, a boarding progress bar, a rolling message
log, and context prompts.

## 6. Audio
Procedural — `scripts/audio.gd` synthesizes 16-bit PCM `AudioStreamWAV` tones at runtime
for laser, beam, hit, shield, explosion, disabled, board, capture, UI, and thruster
events. No audio files ship. `tools/check_audio_wiring.py` statically verifies every
declared trigger has a gameplay call site.

## 7. Out of scope for the slice (production backlog)
Persistent save/economy, station docking interiors, multi-system map, crew skills/morale,
mouse-flight, controller support, real art/audio pipeline, networked or scripted
campaign. Tracked in `docs/studio/definition_of_done.md`.
