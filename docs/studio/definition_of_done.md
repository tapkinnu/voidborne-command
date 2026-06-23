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
- [ ] Turret subsystems that track independently; per-mount fire arcs.
- [x] Subsystem targeting (engines/weapons/shields) feeding the disable model. Shipped: `Z`
  cycles subsystem focus on the current target (none → engines → weapons → shields → none).
  Player fire routes 50% of post-shield damage into the focused subsystem; AI always does
  generic damage. OFFLINE engines cut speed/accel to 20% and turn to 40%; OFFLINE weapons
  prevent firing; OFFLINE shields collapse the bubble and stop regen. DAMAGED (<0.4)
  subsystems apply partial penalties. Station `H` refit restores subsystems. Subsystem health
  round-trips through save/load (backward-compatible optional fields). Covered by
  `tests/test_subsystem_targeting.gd`.
- [ ] Hit decals, muzzle flashes, shield-impact shaders, debris.

### Crew & command depth
- [ ] Named crew with roles, skills, morale; station assignments affect ship stats.
- [x] Boarding as a resolved squad action (attacker vs defender marines, casualties).
  Shipped: ships carry a class-based `marine_garrison` (halved on disable); boarding runs
  fixed 0.5s rounds where attacker and defender marines exchange casualties (`0.15` rate ×
  seeded `0.7–1.3` roll), capturing when defenders hit 0 and failing — losing all marines —
  if attackers hit 0 first. HUD shows `ATK/DEF` and capture nearness; garrison saves/loads.
  Regression: `tests/test_boarding_squad.gd` (`BOARDING_SQUAD_TEST_PASS`).
- [ ] Deck navigation across multiple rooms / multiple owned ships.
- [ ] Order menu (escort, attack-my-target, dock) for fleet ships beyond the current follow/hold toggle.

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
- [ ] Multiple stations / a small system map with travel and respawning threats.
- [ ] Mission/objective system beyond the single seeded scenario.

### Production pipeline
- [ ] Real (or higher-fidelity procedural) art + an authored audio pass.
- [ ] Automated screenshot diffing in CI; perf budget tests.
- [ ] Broader unit tests for damage/boarding/economy state transitions (headless harness).
- [ ] Settings menu (resolution, volume, graphics) and pause.

### Known limitations (current slice)
- Crew/marines are abstract pools surfaced as humanoids on the deck, not persistent
  individuals with stats.
- Boarding resolves as a per-round attacker-vs-defender casualty exchange (with a class-based
  defender garrison), but the marines themselves are still abstract counts, not individuals.
- Fleet AI is a ring-formation / hold-position / attack-target command set; richer
  orders such as escort roles and docking are not built yet.
- Target cycling prioritizes hostiles; neutral assets are fallback targets only after the
  hostile force is cleared.
- Single hand-seeded scenario. Within a run, the battle state can be quick-saved/loaded
  (`V`/`L`) to one versioned slot; there is no autosave, multi-slot, or cross-system
  persistence yet.
