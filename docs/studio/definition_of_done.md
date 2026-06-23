# Definition of Done

## Slice DoD — must all be true (this delivery)

### Mechanics proven in-engine
- [x] Player flies a ship: throttle, boost, brake, yaw, pitch, roll.
- [x] Weapons fire (projectiles + beams); hull / shield / energy modeled.
- [x] Target cycling with a target-lock HUD panel + radar ring.
- [x] Third-person chase camera; readable HUD (bars, radar, objective, messages, reticle).
- [x] Recruit crew and marines at the station.
- [x] Crew-deck interaction view with visible procedural humanoid crew/marines.
- [x] Interact with individual crew/marines and order them to follow the captain.
- [x] Hostiles can be **disabled** (not only destroyed).
- [x] Boarding with marines shows visible progress / resolution.
- [x] Captured ships/stations switch faction and become player-owned.
- [x] Buy ships at the station.
- [x] Assign crew so purchased/captured ships are **manned**.
- [x] Manned ships follow in fleet formation.
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
- [ ] Mouse-aim flight + gamepad support; configurable bindings.
- [ ] Turret subsystems that track independently; per-mount fire arcs.
- [ ] Subsystem targeting (engines/weapons) feeding the disable model.
- [ ] Hit decals, muzzle flashes, shield-impact shaders, debris.

### Crew & command depth
- [ ] Named crew with roles, skills, morale; station assignments affect ship stats.
- [ ] Boarding as a resolved squad action (attacker vs defender marines, casualties).
- [ ] Deck navigation across multiple rooms / multiple owned ships.
- [ ] Order menu (escort, attack-my-target, hold, dock) for fleet ships.

### Economy & world
- [ ] Persistent save/load of credits, roster, and fleet.
- [x] Station shipyard can cycle multiple buyable classes (fighter/corvette/frigate/capital).
- [ ] Station docking UI: repair/refit and a fuller market screen.
- [ ] Multiple stations / a small system map with travel and respawning threats.
- [ ] Mission/objective system beyond the single seeded scenario.

### Production pipeline
- [ ] Real (or higher-fidelity procedural) art + an authored audio pass.
- [ ] Automated screenshot diffing in CI; perf budget tests.
- [ ] Unit tests for damage/boarding/economy state transitions (headless harness).
- [ ] Settings menu (resolution, volume, graphics) and pause.

### Known limitations (current slice)
- Crew/marines are abstract pools surfaced as humanoids on the deck, not persistent
  individuals with stats.
- Boarding resolves on a timer scaled by marine count, not a modeled firefight.
- Fleet AI is a ring-formation + nearest-enemy engage heuristic, not orderable yet.
- The auto-demo (capture mode) targets the nearest object, which may be the neutral
  station; interactive play gives full target control via `Tab`.
- Single hand-seeded scenario; no persistence between runs.
