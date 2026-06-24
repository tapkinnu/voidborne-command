# Definition of Done

## Slice DoD — must all be true (this delivery)

### Mechanics proven in-engine
- [x] Player flies a ship: throttle, boost, brake, yaw, pitch, roll.
- [x] Weapons fire (projectiles + beams); hull / shield / energy modeled.
- [x] Hostile-first target cycling with a target-lock HUD panel + radar ring.
- [x] Third-person chase camera; readable HUD (bars, radar, objective, messages, reticle).
- [x] Recruit crew and marines at the station.
- [x] Crew-deck interaction view with visible procedural humanoid crew/marines.
- [x] Interact with individual crew/marines and order them to follow the captain.
- [x] Hostiles can be **disabled** (not only destroyed).
- [x] Boarding with marines shows visible progress / resolution.
- [x] Captured ships/stations switch faction and become player-owned; a hostile relay
      station is present as a live station-capture objective.
- [x] Buy ships at the station.
- [x] Assign crew so purchased/captured ships are **manned**.
- [x] Manned ships follow in fleet formation and can be ordered to hold position.
- [x] Distinct classes: fighter, corvette, frigate, capital (+ station) with distinct
      stats, silhouette scale, greebles/turrets, and behavior.
- [x] Live battle: hostile wing, a larger hostile ship, a station, beams/projectiles/explosions.

### Engineering & gates
- [x] Imports + smoke-runs headless with no SCRIPT ERROR / Parse Error / Invalid call.
- [x] `validate_build.sh`, `capture_screenshots.sh`, `make_contact_sheet.py`,
      `check_audio_wiring.py` present and passing.
- [x] Screenshots are non-black and show battle + player/fleet/target/station + HUD.
- [x] No `class_name` on autoloads; explicit Variant typing; artifacts git-ignored.

### Docs
- [x] `README.md`, `docs/GDD.md`, and the five `docs/studio/*.md` briefs.

---

## Production backlog (next, beyond the slice)

### Flight & combat feel
- [x] Mouse-aim flight + gamepad support; configurable bindings. Shipped: backtick toggles
  mouse-aim (cursor captured, mouse X→yaw / Y→pitch, additive over keyboard); gamepad
  axes/buttons mapped to all flight actions (left stick steer, triggers throttle, right
  stick roll, A fire, B target, Y board, Back deck, Start mouse-aim); `F2` cycles control
  scheme Auto→Keyboard+Mouse→Gamepad→Auto; `F1` opens a centered settings overlay. The
  `_flight_strength()` / `_flight_axis()` gate reads the right source(s) per scheme.
  Covered by `tests/test_mouse_aim_gamepad.gd` (`MOUSE_AIM_GAMEPAD_TEST_PASS`).
- [x] Turret subsystems that track independently; per-mount fire arcs. Shipped: frigates
  (2 mounts, ±110° arc), capitals (8 mounts, ±85° broadside arc) and stations (4 mounts,
  ±170° arc) register independent turret nodes that rotate around Y toward the ship's target,
  clamped to their fire arc and tracking at 3 rad/s. Each turret carries its own cooldown
  (`base_cd` per class) and fires only when both ready and aimed — muzzles fire one at a time
  from their tracked position/direction, not all at once. Fighters/corvettes keep the fixed
  all-muzzle volley. The weapons subsystem still gates all turrets (OFFLINE = no fire,
  DAMAGED = doubled cooldown). Turret yaw/cooldown round-trips through save/load as a
  backward-compatible optional `turrets` array. Covered by `tests/test_turret_tracking.gd`
  (`TURRET_TRACKING_TEST_PASS`).
- [x] Subsystem targeting (engines/weapons/shields) feeding the disable model. Shipped: `Z`
  cycles subsystem focus on the current target (none → engines → weapons → shields → none).
  Player fire routes 50% of post-shield damage into the focused subsystem; AI always does
  generic damage. OFFLINE engines cut speed/accel to 20% and turn to 40%; OFFLINE weapons
  prevent firing; OFFLINE shields collapse the bubble and stop regen. DAMAGED (<0.4)
  subsystems apply partial penalties. Station `H` refit restores subsystems. Subsystem health
  round-trips through save/load (backward-compatible optional fields). Covered by
  `tests/test_subsystem_targeting.gd`.
- [x] Hit decals, muzzle flashes, shield-impact shaders, debris. Shipped: four
  code-built VFX systems in `main.gd` — (1) muzzle flashes: faction-tinted glow
  spheres at every muzzle on all four fire paths (fixed/turret × projectile/beam),
  expanding 1→2.5× and fading over 0.12s; (2) shield impacts: blue ripple sphere
  at the exact projectile hit point when shields absorb damage (beam hitscan passes
  `Vector3.ZERO` and falls back to the existing full-bubble `_shield_flash`); (3)
  hit decals: dark scorch `QuadMesh` parented to the ship `Hull` node at hull-damage
  impact points, capped at 8 per ship via `decal_count` metadata, persisting for the
  ship's lifetime; (4) debris: 4–8 emissive box fragments flung from `_destroy_ship`
  with random velocity/spin, fading over 1.5s. The impact position is threaded
  through `_update_projectiles → _deal_damage → _handle_damage_events` with
  backward-compatible optional `Vector3.ZERO` defaults so all existing callers
  (including `_apply_damage` for beams) are unaffected. All update functions follow
  the existing `_update_explosions` cull pattern and are wired into `_process_space`.
  Covered by `tests/test_combat_vfx.gd` (`COMBAT_VFX_TEST_PASS`).

### Crew & command depth
- [x] Named crew with roles, skills, morale; station assignments affect ship stats.
  Shipped: `Game.crew_roster` array of named individuals (name, role, skill 1..10,
  morale 0..1, assigned flag). Three roles (pilot, engineer, gunner) each modify
  different ship stats when assigned: pilots boost speed/turn, engineers boost
  accel, gunners boost weapon damage/fire rate. Crew are recruited as named
  individuals at the station, assigned to ships via the existing man/crew path
  (F key, buy ship, boarding capture), and freed back to the pool when their ship
  is destroyed. The crew deck shows each crew member's name, role abbreviation,
  and skill level on a Label3D above their humanoid. The HUD economy panel shows
  available crew counts by role (P/E/G). Roster round-trips through save/load
  (backward-compatible: old saves rebuild a default roster). Covered by
  `tests/test_named_crew.gd` (`NAMED_CREW_TEST_PASS`).
- [x] Boarding as a resolved squad action (attacker vs defender marines, casualties).
  Shipped: ships carry a class-based `marine_garrison` (halved on disable); boarding runs
  fixed 0.5s rounds where attacker and defender marines exchange casualties (`0.15` rate ×
  seeded `0.7–1.3` roll), capturing when defenders hit 0 and failing — losing all marines —
  if attackers hit 0 first. HUD shows `ATK/DEF` and capture nearness; garrison saves/loads.
  Regression: `tests/test_boarding_squad.gd` (`BOARDING_SQUAD_TEST_PASS`).
- [x] Deck navigation across multiple rooms / multiple owned ships. Shipped: 3 named rooms
  (Bridge, Crew Quarters, Marine Barracks) with distinct colors and greeble layouts;
  door-trigger walk transitions at room boundaries; R key cycles owned ships; HUD shows
  "DECK: Class [ShipName]" and "Room: RoomName" labels; crew are distributed per room
  (pilots/engineers on Bridge, gunners in Quarters, marines in Barracks); `cycle_ship()`
  and `goto_room()` API for tests; `set_ship_list()` wired into deck entry; backward
  compatible: single-ship behaviour unchanged. Covered by `tests/test_deck_navigation.gd`
  (`DECK_NAV_TEST_PASS`).
- [x] Order menu (escort, attack-my-target, dock) for fleet ships beyond the current follow/hold toggle.
  Shipped: `F` opens a **fleet order menu** overlay (when no unmanned ship needs crew); number
  keys pick the standing order — `[1]` Follow, `[2]` Hold, `[3]` Escort (tight defensive ring
  that engages hostiles closing on the flagship but never chases past `weapon_range * 0.9`),
  `[4]` Defend (orbit/screen the current target at ~20 units), `[5]` Dock (route manned escorts
  to the nearest friendly station and auto-repair hull/shield/energy at half the manual service
  cost), `[6]` Attack (focus-fire, same as `T`). `Esc` closes without changing the order. Each
  order routes through `_set_fleet_order()` with validation; attack/defend self-clear via
  `_validate_fleet_attack()` / `_validate_fleet_defend()` and dock reverts to follow when no
  station is reachable, all falling back to FOLLOW. `fleet_defend_target` saves/loads (old
  saves default to follow). Covered by `tests/test_fleet_order_menu.gd` (`FLEET_ORDER_MENU_TEST_PASS`).

### Economy & world
- [x] Persistent save/load of credits, roster, and fleet. Shipped: versioned JSON quick
  save (`V`) / quick load (`L`) at `user://voidborne_save.json` (`save_path` is overridable
  for tests). Round-trips economy (credits, crew/marine pools, captured/purchased counts),
  shipyard offer, fleet order + focus target, and every live ship/station (class, faction,
  ownership, manned/crew, hull/shield/energy, disabled, position/rotation). Loads rebuild the
  battle, keep captured/purchased ships, leave unmanned prizes unmanned, and never resurrect
  destroyed/cleared hostiles. Saves are rejected (without clobbering live state) when corrupt,
  wrong `game_id`, missing required sections, or a future `version`. Covered by
  `tests/test_save_load.gd` and the producer-side `tools/verify_save_load.py` (wired into
  `validate_build.sh`). Multi-slot/named saves and cross-system persistence remain backlog.
- [x] Station shipyard can cycle multiple buyable classes (fighter/corvette/frigate/capital).
- [~] Station docking UI: repair/refit and a fuller market screen. Repair/refit dock
  service (`H`) is shipped — restores hull/shield/energy across the manned, player-owned
  fleet at any friendly station, charges proportional credits with partial work on a tight
  budget, and refuses at hostile stations. A fuller multi-tab market/dock screen is still TODO.
- [x] Multiple stations / a small system map with travel and respawning threats.
  Shipped: the world now holds **four stations** spread hundreds of units apart — the neutral
  **Halcyon** hub (still the `station` reference / primary dock) and **Aurora Station**, plus
  the capturable hostile **Kryos Relay** and **Ironhold** — so travel between them is
  meaningful. `M` toggles a centered top-down **system map** overlay (`hud.gd
  _draw_system_map`): faction-coloured labelled station squares, ship dots, a player heading
  arrow, and a distance-scale bar; it is a live overlay (flight keeps working) with transient,
  unsaved open/closed state. Respawning threats (`_update_respawns`) warp in 2–3 fresh
  `Raider-N` fighters at the system edge whenever live mobile hostiles drop below
  `RESPAWN_THRESHOLD` (3) for `RESPAWN_INTERVAL` (30 s), with quiet-sector / reinforcement HUD
  messages; hostile stations never respawn and the system is disabled in capture/demo mode.
  Camera far plane (3000) and the starfield shell (800–1200) were widened for the larger area.
  Covered by `tests/test_system_map.gd` (`SYSTEM_MAP_TEST_PASS`). A multi-system / inter-system
  jump layer remains backlog.
- [x] Mission/objective system beyond the single seeded scenario. `main.gd _init_missions`
      defines five trackable missions (capture Kryos Relay / Ironhold, destroy 5 raiders, buy a
      frigate, command a 3-ship fleet) with credit rewards; `O` cycles the tracked mission,
      `_check_missions` evaluates and pays them on a throttle, the HUD shows a top-right mission
      panel, and mission state persists through quick save/load (old saves stay compatible).
      Covered by `tests/test_mission_system.gd` (`MISSION_SYSTEM_TEST_PASS`). Branching/chained
      mission scripting and a mission-giver UI remain backlog.

### Production pipeline
- [ ] Real (or higher-fidelity procedural) art + an authored audio pass.
- [ ] Automated screenshot diffing in CI; perf budget tests.
- [ ] Broader unit tests for damage/boarding/economy state transitions (headless harness).
- [x] Settings menu (resolution, volume, graphics) and pause. Shipped: `F1` opens an
      interactive settings overlay with six rows — Resolution (1280×720 / 1600×900 /
      1920×1080, applied to the window), Volume (0–100 %, applied to the Master audio bus
      via `linear_to_db` with mute at 0), Graphics quality (Low / Medium / High, toggles
      glow intensity/bloom and MSAA 0×/2×/4×), Pause (boolean gate), Mouse Aim, and
      Control Scheme. Navigation: `↑`/`↓` move the cursor, `←`/`→` change the value,
      `Enter` toggles booleans, `1`–`6` jump to a row, `F1` or `Esc` closes. `P` pauses
      outside the menu — a boolean gate (`paused`) early-returns `_process_space()` so
      flight/AI/combat/boarding freeze while the HUD keeps drawing a "PAUSED" banner;
      `get_tree().paused` is deliberately NOT used so timers and the headless capture
      autoload keep running. Settings are display preferences and are not part of the
      save file. Covered by `tests/test_settings_menu.gd` (`SETTINGS_MENU_TEST_PASS`).

### Known limitations (current slice)
- Crew are named individuals with roles, skills, and morale; marines are still
  abstract pool counts surfaced as humanoids on the deck.
- Boarding resolves as a per-round attacker-vs-defender casualty exchange (with a class-based
  defender garrison), but the marines themselves are still abstract counts, not individuals.
- Fleet AI is a six-order command set (follow, hold, escort, defend, dock, attack) issued
  through the `F` fleet order menu; richer doctrine (patrol routes, wing sub-grouping) is
  still future work.
- Target cycling prioritizes hostiles; neutral assets are fallback targets only after the
  hostile force is cleared.
- Single hand-seeded scenario. Within a run, the battle state can be quick-saved/loaded
  (`V`/`L`) to one versioned slot; there is no autosave, multi-slot, or cross-system
  persistence yet.
