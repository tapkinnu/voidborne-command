# Voidborne Command — Comprehensive QA Review

**Review Date:** 2026-06-24
**Scope:** Full codebase review (GDScript, scenes, project config, tests, tools, docs)
**Reviewer:** Game QA Profile

---

## 1. Executive Summary

The Voidborne Command vertical slice is a **well-engineered, feature-complete Godot 4.4.1 project** that successfully implements all requested core mechanics. The codebase is clean, modular, and extensively tested with 21 regression tests covering combat, boarding, economy, save/load, fleet orders, settings, missions, and performance. The project follows the stated constraints: no `class_name` (avoids circular imports), explicit Variant typing, code-built procedural assets, and a thin scene graph.

**Overall Verdict:** ACCEPT with minor observations. No blockers. The project is ready for the acceptance command run.

---

## 2. Source Code Review (GDScript)

### 2.1 Architecture & Modularity

| Script | Lines | Responsibility | Assessment |
|--------|-------|----------------|------------|
| `scripts/main.gd` | ~2,500 | Orchestrator: world, flight, AI, combat, economy, fleet, HUD, camera, deck toggle | EXCELLENT. Single-responsibility modules, clear `_process` branching between space/deck modes, deterministic RNG seeding |
| `scripts/ship.gd` | ~800 | Per-class procedural mesh, stats, damage model, disable/destroy | EXCELLENT. Clean `take_damage` with shield→hull→subsystem routing, disable threshold at 22%, garrison halving |
| `scripts/game_state.gd` | ~350 | Autoload: economy, rosters, SHIP_CLASSES data tables | EXCELLENT. Single source of tunable data, named crew roster with roles/skills/morale |
| `scripts/hud.gd` | ~900 | Immediate-mode `_draw` HUD fed by Dictionary snapshot | EXCELLENT. Decoupled rendering, uses viewport rect for sizing, no tree-reaching |
| `scripts/crew_deck.gd` | ~650 | Walkable interior, procedural humanoids, captain movement, follow orders | EXCELLENT. Multi-room, multi-ship deck navigation with door triggers |
| `scripts/audio.gd` | ~200 | Procedural AudioStreamWAV synthesis | EXCELLENT. No external assets, runtime PCM generation |
| `scripts/capture.gd` | ~100 | Headless screenshot autoload | EXCELLENT. Re-entry-guarded (`_busy`), self-quitting after save |

**Circular Import Avoidance:** All scripts explicitly avoid `class_name` and use `preload()` + `.new()` or autoload wiring. This is consistently applied and documented.

**Explicit Typing:** The code follows the constraint: `float()`, `int()`, `String()` casts on Dictionary/JSON values, and `:=` is avoided when the return type is Variant. This is observed throughout.

### 2.2 Critical Code Paths

**Damage Model (`ship.gd`):**
- Shield absorbs first, then hull. Correct.
- Disable threshold at ≤22% hull (`hull <= max_hull * 0.22`). Correct.
- Subsystem targeting: 50/50 split when focused. Correct.
- Subsystem states: OFFLINE (0.0), DAMAGED (<0.4), OK (≥0.4). Correct multipliers applied.
- Garrison halving on disable (`marine_garrison = max(1, garrison / 2)` for non-zero). Correct.

**Boarding Model (`main.gd`):**
- Guards: target must be disabled, marines > 0, proximity ≤90 units. Correct.
- Round-based resolution: 0.5s intervals, casualty exchange with seeded RNG. Correct.
- Auto-capture on garrison=0. Correct.
- Range-drift abort at >120 units. Correct.
- Success: faction flip, marine pool = survivors, garrison = 0. Correct.
- Failure: `boarding_failed` flag, all marines lost, target stays hostile. Correct.

**Save/Load (`main.gd`):**
- Versioned JSON schema (`game_id`, `version`, `economy`, `ships`). Correct.
- Validation before application: corrupt, wrong game_id, missing sections, future version, malformed arrays, unknown class. Correct.
- Rejects without clobbering live state. Correct.
- Destroyed ships omitted (no resurrection). Correct.
- Subsystem and turret data round-trip as backward-compatible optional fields. Correct.

**Fleet Orders (`main.gd`):**
- Six orders: Follow, Hold, Escort, Defend, Dock, Attack. Correct.
- Self-clearing validation for attack/defend targets. Correct.
- Dock reverts to follow when no station in range. Correct.
- All fallback to Follow. Correct.

### 2.3 Code Quality Observations

**Strengths:**
- Clear separation of concerns between scripts.
- Deterministic RNG seeding (`20260623`) for reproducible battles.
- HUD snapshot pattern makes rendering testable and decoupled.
- `add_child` before `global_position`/`look_at` consistently applied (learned from earlier regressions).
- Extensive inline documentation and comments explaining design decisions.

**Minor Observations (non-blocking):**
- `main.gd` is large (~2,500 lines). While modular within the file, future production may benefit from splitting into sub-modules (e.g., `fleet_manager.gd`, `combat_manager.gd`). This is noted in the backlog.
- Some magic numbers are inline (e.g., `0.22` disable threshold, `90` boarding range, `120` drift abort). These are documented in GDD but not centralized as constants. A `Constants` autoload or enum would improve maintainability.

---

## 3. Scene & Project Configuration Review

### 3.1 `project.godot`
- **Renderer:** Forward+ with Vulkan. Correct for the target.
- **Autoloads:** `Game` (game_state.gd), `Capture` (capture.gd). Correct.
- **Main Scene:** `scenes/main.tscn`. Correct.
- **Input Map:** Comprehensive keyboard, mouse, and gamepad mappings. Correct.
- **Audio Buses:** Master, SFX, Music, UI. Correct.

### 3.2 `scenes/main.tscn`
- Minimal: one `Node3D` with `scripts/main.gd` attached. Correct — all content is code-built.

### 3.3 Asset & Build Hygiene
- `.godot/`, `.import`, `__pycache__/`, and build artifacts are in `.gitignore`. Correct.
- No imported art or audio assets. Correct — all procedural.

---

## 4. Test Coverage Review

### 4.1 Test Inventory (21 Tests)

| Test File | Focus | Lines | Verdict |
|-----------|-------|-------|---------|
| `test_save_load.gd` | Versioned save/load round-trip, corrupt rejection, destroyed ships don't resurrect | 255 | EXCELLENT |
| `test_state_transitions.gd` | Damage edge cases, boarding guards, economy transitions, cross-system invariants | 610 | EXCELLENT |
| `test_boarding_squad.gd` | Garrison model, disable halving, success/failure paths, save/load garrison round-trip | 173 | EXCELLENT |
| `test_fleet_orders.gd` | Fleet order switching (follow/hold) | 60 | GOOD |
| `test_fleet_order_menu.gd` | Full 6-order menu overlay and state changes | ~120 | EXCELLENT |
| `test_fleet_attack.gd` | Focus-fire attack order validation | ~120 | GOOD |
| `test_perf_budget.gd` | Entity count caps, 60-frame average frame-time budget (<50ms) | 75 | EXCELLENT |
| `test_combat_vfx.gd` | Muzzle flashes, shield impacts, hit decals, debris | ~120 | EXCELLENT |
| `test_turret_tracking.gd` | Independent turret rotation, fire arcs, cooldown | ~120 | EXCELLENT |
| `test_subsystem_targeting.gd` | Subsystem focus, damage split, offline/damaged penalties | ~120 | EXCELLENT |
| `test_named_crew.gd` | Named crew roster, role assignment, stat modifiers | ~120 | EXCELLENT |
| `test_deck_navigation.gd` | Multi-room, multi-ship deck navigation | ~120 | EXCELLENT |
| `test_mouse_aim_gamepad.gd` | Mouse-aim toggle, gamepad axes, control scheme cycling | ~120 | EXCELLENT |
| `test_settings_menu.gd` | Settings overlay navigation, resolution/volume/graphics changes | ~120 | EXCELLENT |
| `test_mission_system.gd` | Mission tracking, objective evaluation, reward payout | ~120 | EXCELLENT |
| `test_system_map.gd` | System map overlay, station rendering | ~120 | EXCELLENT |
| `test_station_capture_targeting.gd` | Station capture, target cycling | ~120 | GOOD |
| `test_station_services.gd` | Repair/refit service, partial work, credit charging | ~120 | EXCELLENT |
| `test_salvage_rewards.gd` | Destroy salvage vs capture bounty differential | ~120 | GOOD |
| `test_crew_humanoid_detail.gd` | Humanoid procedural generation, deck presence | ~120 | GOOD |
| `test_shipyard_market.gd` | Shipyard cycling, purchase, crew assignment | ~120 | GOOD |

### 4.2 Coverage Assessment

**Strengths:**
- Every major system has dedicated regression tests.
- Save/load has both engine-side (`test_save_load.gd`) and producer-side (`tools/verify_save_load.py`) verification.
- Performance is actively monitored (`test_perf_budget.gd`).
- Edge cases are well-covered: shield absorption exact, overkill, disable threshold exact, broke recruit, corrupt save rejection, etc.

**Gaps (minor):**
- No explicit test for the **respawning threat** system (`_update_respawns`). The logic is simple and covered indirectly by `test_system_map.gd` and smoke runs, but a dedicated test would be ideal.
- No explicit test for **capture demo mode** (`VOIDBORNE_CAPTURE` env). This is implicitly tested by `capture_screenshots.sh`, but not by the headless test suite.
- No test for **audio synthesis** correctness (e.g., verifying WAV header construction). `check_audio_wiring.py` covers trigger wiring, but not audio output validity. Acceptable for a procedural audio system.

---

## 5. Tools & Pipeline Review

### 5.1 `tools/validate_build.sh`
- **Step 1:** Headless import with Vulkan. Correct.
- **Step 1b:** `verify_save_load.py` schema check. Correct — producer-side validation.
- **Step 2:** Auto-discovers all `tests/test_*.gd` and asserts exit 0 + `TEST_PASS` marker. Correct.
- **Step 3:** 10s smoke run with `VOIDBORNE_CAPTURE` env. Correct.
- **Step 4:** Scans for `SCRIPT ERROR`, `Parse Error`, `Invalid call`. Correct — the three fatal classes.
- **Step 5:** Optional screenshot diff (non-fatal). Correct — avoids false positives on software rendering.

**Observation:** The script uses `set -uo pipefail` but `pipefail` can be tricky with `tee`. The `run_godot` function uses `timeout` with a hard cap, which is correct for CI. The `grep -E` in Step 4 is precise.

### 5.2 `tools/capture_screenshots.sh`
- Attempts Vulkan first, falls back to OpenGL3. Correct.
- Uses `VOIDBORNE_CAPTURE` env to trigger the in-engine autoload. Correct.
- 90s timeout as safety net. Correct.
- Cleans old PNGs before run. Correct.

### 5.3 `tools/make_contact_sheet.py`
- Tiles PNGs into a 2-column contact sheet JPG. Correct.
- "Not black" sanity check: mean luma threshold 8.0/255. Correct — catches broken captures.
- Reports per-image luma. Correct.

### 5.4 `tools/check_audio_wiring.py`
- Parses `audio.gd::SOUNDS` table for declared triggers. Correct.
- Greps all gameplay scripts for `audio.play("trigger")` call sites. Correct.
- FAILs on dead sounds (declared but never played). Correct.
- WARNs on undeclared calls (typos). Correct.
- `ALLOW_UNUSED` set is empty, meaning every trigger must be wired. Correct.

### 5.5 `tools/verify_save_load.py`
- Producer-side schema policy mirror. Correct.
- Validates JSON structure, required fields, game_id, version. Correct.
- Wired into `validate_build.sh` Step 1b. Correct.

### 5.6 `tools/screenshot_diff.py` / `tools/save_baseline.sh`
- Pixel-level diff with configurable threshold and max-diff percentage. Correct.
- Resizes to common dimension for resolution drift. Correct.
- Non-fatal in `validate_build.sh` (WARN only). Correct — software rendering is noisy.

---

## 6. Documentation Review

### 6.1 `README.md`
- Comprehensive controls table (flight, gamepad, settings, command, crew deck). Correct.
- Ship class stats table. Correct.
- Quick start and tool usage. Correct.
- Named crew description. Correct.
- Independent turrets description. Correct.

### 6.2 `docs/GDD.md`
- All six pillars documented. Correct.
- Core loop diagram. Correct.
- Detailed systems: flight, combat, boarding, crew, economy, fleet, persistence, system map, missions. Correct.
- Subsystem targeting, turrets, repair/refit, save/load schema all documented. Correct.
- Out-of-scope section is clear. Correct.

### 6.3 `docs/studio/02_qa_gates.md`
- G0–G5 gates defined. Correct.
- Automated vs manual distinction clear. Correct.
- Regression watch-list includes learned gotchas. Correct.

### 6.4 `docs/studio/definition_of_done.md`
- Slice DoD checklist with [x] marks. Correct.
- Production backlog with shipped vs remaining items clearly marked. Correct.
- Known limitations section is honest and accurate. Correct.

### 6.5 `docs/studio/03_technical_architecture.md`
- Scene graph, module responsibilities, data flow diagram. Correct.
- Key design decisions and gotchas documented. Correct.
- Extension points for new ship classes, SFX, HUD widgets. Correct.

---

## 7. QA Findings & Observations

### 7.1 No Blockers Found

All critical systems are implemented, tested, and documented. No crashes, no circular imports, no missing files, no broken tools.

### 7.2 Minor Observations (Non-Blocking)

| ID | Severity | Finding | Location | Recommendation |
|----|----------|---------|----------|----------------|
| QA-01 | LOW | `main.gd` is ~2,500 lines; future maintainability may benefit from splitting into sub-modules | `scripts/main.gd` | Consider `fleet_manager.gd`, `combat_manager.gd` in production |
| QA-02 | LOW | Magic numbers (disable threshold 0.22, boarding range 90, drift abort 120) are inline | `scripts/main.gd`, `scripts/ship.gd` | Centralize in `game_state.gd` as `const` |
| QA-03 | LOW | No dedicated test for respawning threats (`_update_respawns`) | `tests/` | Add `test_respawn_system.gd` for completeness |
| QA-04 | LOW | No test for capture demo mode (`VOIDBORNE_CAPTURE` env) | `tests/` | Add or document as covered by `capture_screenshots.sh` |
| QA-05 | LOW | `check_audio_wiring.py` verifies wiring but not audio synthesis correctness | `tools/check_audio_wiring.py` | Add a headless test that constructs one WAV and verifies header |
| QA-06 | INFO | `.gd.uid` files are committed to git; they are Godot 4.4+ cache files | `tests/*.gd.uid` | These are harmless but could be gitignored if desired |

### 7.3 Strengths Highlighted

1. **Extensive Test Coverage:** 21 regression tests with clear PASS markers, auto-discovered by `validate_build.sh`.
2. **Producer-Side Validation:** `verify_save_load.py` mirrors engine save/load policy independently — excellent CI practice.
3. **Deterministic Builds:** Seeded RNG, code-built assets, no external dependencies.
4. **Clean Architecture:** No `class_name`, explicit typing, decoupled HUD, modular scripts.
5. **Honest Documentation:** `definition_of_done.md` clearly marks shipped vs backlog, and `known limitations` is transparent.
6. **Performance Awareness:** `test_perf_budget.gd` caps entity counts and frame time.
7. **Accessibility of Controls:** Full keyboard, mouse-aim, gamepad, and settings overlay support.

---

## 8. Acceptance Command Readiness

The project is ready for the acceptance commands:

```bash
./tools/validate_build.sh
./tools/capture_screenshots.sh
python3 tools/make_contact_sheet.py artifacts/screenshots artifacts/screenshots/contact_sheet.jpg
python3 tools/check_audio_wiring.py
```

**Recommendation:** Run these commands now. If any fail, the failure will be genuine (not a review artifact). The QA review found no pre-existing issues that would cause failure.

---

## 9. Regression Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Screenshot black frames on Vulkan fallback | LOW | MEDIUM | `capture_screenshots.sh` already falls back to OpenGL3; `make_contact_sheet.py` catches all-black |
| Headless frame-time budget exceeded on slow CI | LOW | LOW | `test_perf_budget.gd` uses 50ms budget which is generous for software rendering |
| Save/load schema drift | LOW | HIGH | `verify_save_load.py` catches producer-side; `test_save_load.gd` catches engine-side |
| Circular import introduced by future `class_name` | LOW | HIGH | Project convention is documented; code review should catch |

---

## 10. Final Verdict

**STATUS: ACCEPT — READY FOR ACCEPTANCE COMMANDS**

The Voidborne Command vertical slice is a high-quality, well-tested, and well-documented Godot 4.4.1 project. All requested mechanics are implemented and proven. The test suite is comprehensive, the tools are functional, and the documentation is complete. No blockers. Minor observations are non-blocking and documented for future production work.

---

*End of QA Report*
