# Voidborne Command — QA Review @ dafc43a (post-audio merge)

- **Commit reviewed**: `dafc43a` ("feat(audio): replace procedural SFX with authored assets")
- **Branch / origin**: `main` @ `origin/main` (in sync)
- **Workspace**: `/home/ganomix/projects/voidborne-command`
- **Engine**: Godot 4.4.1 (`/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64`)
- **Reviewer**: `game-qa` (adversarial, read-only)
- **Verdict**: **NEEDS_FIX** (3 Critical regressions in delivery; gates are mechanically green but deliverable is broken)

---

## 1. Executive summary

| Severity | Count |
|---|---|
| Critical | **3** |
| High     | **4** |
| Medium   | **5** |
| Low      | **3** |

`./tools/validate_build.sh` PASSES (41/41 tests, no SCRIPT/Parse/Invalid errors), `check_audio_wiring.py` PASSES (21/21 SFX wired), and `capture_screenshots.sh` writes 5 non-black PNGs — but the **crew-deck screenshot regressed** versus the committed baseline (procedural crew figures that were visible on Jun 25 are now invisible), **6 newly-shipped voice barks and 3 music tracks are orphaned** (no call sites anywhere), and the **Meshy humanoid rig is parented at world y = -500** (off-screen). The slice still ships in `NEEDS_FIX` state — it does not meet the "Slice DoD" requirement of "Crew-deck interaction view with visible procedural humanoid crew/marines" and the `audio_production_brief.md` acceptance criterion of "voice lines wired to gameplay events".

---

## 2. Gates & canonical commands (exit codes + last lines)

### 2.1 Headless import — PASS

```bash
$ timeout 180 xvfb-run -a ~/.local/bin/godot --headless --rendering-driver vulkan \
    --path /home/ganomix/projects/voidborne-command --import
```

- **Exit code**: `0`
- **Errors**: 0 hits on `SCRIPT ERROR`, `Parse Error`, `Invalid call`, `ObjectDB`, `leaked`, `null instance`, `Failed loading resource`.
- **Last 5 lines** (from `artifacts/qa/20260627T190932Z/import.log`):
  ```
  loading_editor_layout: step 3: Loading central editor layout...
  loading_editor_layout: step 4: Loading plugin window layout...
  loading_editor_layout: step 5: Editor layout ready.
  loading_editor_layout: end
  ```
- Full import log scanned: `wc -l import.log` → 75 lines, no errors.

### 2.2 `check_audio_wiring.py` — PASS

```
Declared triggers (21): laser, beam, hit, shield, explosion, disabled, subsystem_hit,
                        board, boarding_round, boarding_fail, capture, ui_recruit,
                        ui_buy, ui_deny, thruster, ambient, weapon_overheat, hull_alarm,
                        engine_hit, mining_hit, asteroid_break
...
PASS: all 21 SFX triggers are wired to gameplay call sites.
EXIT=0
```

But see **C-2** — this check only inspects the `SOUNDS` dict. It does NOT cover the `MUSIC` or `VOICE` dicts in the same `audio.gd`, which is why the orphaned assets are silently green.

### 2.3 `validate_build.sh` — PASS

- **Step 1** (import): PASS
- **Step 1b** (save/load verifier): `VOIDBORNE_SAVE_LOAD_VERIFY: PASS (35 cases)`
- **Step 2** (GDScript tests): 41/41 `TEST_PASS`, 0 failures
- **Step 3** (smoke run 10s): exit 0, no SCRIPT/Parse/Invalid
- **Step 4** scan: clean
- **Step 5** (screenshot diff vs baseline): **4/5 frames FAIL** (>5% pixel diff)
  ```
  filename                      diff_pct mean_diff  result
  01_space_battle.png            49.096%    48.644  FAIL
  02_dogfight.png                61.555%    69.088  FAIL
  03_target_lock.png             73.457%    84.482  FAIL
  04_crew_deck.png                2.786%     3.514  PASS
  05_fleet.png                   71.458%   103.234  FAIL
  SCREENSHOT_DIFF: FAIL
  ```
  Step 5 is documented as non-fatal (WARN only). The 04_crew_deck PASS is misleading — see **C-1**.

### 2.4 `capture_screenshots.sh` + contact sheet — PASS (with concerns)

```
PASS: wrote 5 screenshot(s) to /home/ganomix/projects/voidborne-command/artifacts/screenshots
01_space_battle.png    727439 bytes
02_dogfight.png        685006 bytes
03_target_lock.png     736056 bytes
04_crew_deck.png       154706 bytes
05_fleet.png           427868 bytes
```

Contact-sheet luma (0..255):
```
01_space_battle.png           91.24
02_dogfight.png               89.20
03_target_lock.png            91.84
04_crew_deck.png              66.19
05_fleet.png                  66.76
```

All well above the BLACK_LUMA_THRESHOLD = 8.0, no black frames.

**Contact sheet**: `/home/ganomix/projects/voidborne-command/artifacts/screenshots/contact_sheet.jpg` (1304x1112, 5 tiles)

**Log noise observed**: 304 `ERROR: No animation in cache.` lines from the Meshy rig AnimationPlayer retargeting. See **H-2**.

---

## 3. Critical findings

### C-1. Crew deck screenshot shows NO humanoids — DoD line broken

**Severity**: Critical
**Where**: `scripts/crew_deck.gd:108-162` (`_try_load_meshy_humanoid`)
**Evidence**:
- Baseline `artifacts/baseline/04_crew_deck.png` (Jun 25) shows **three procedural capsule humanoids with floating name labels** ("Nox-21 [PLT] S6 M70%", "Dax-43 [PLT] S7 M66%", "Nox-69 [PLT] S5 M63%") in the Bridge room.
- Current `artifacts/screenshots/04_crew_deck.png` (Jun 27) shows **four light-blue console cubes and nothing else** — no captain, no crew, no labels.
- A focused probe (now removed) instantiated the main scene, called `main.force_deck(true)`, and dumped the full scene tree. The Meshy captain rig's `position` was **`(-10.0, -500.0, 6.0)`** (local to captain). After composing with captain.position = `(-10, 0, 0)`, world y ≈ -500 — i.e. the rig is 500 units below the deck floor.
- Top-down and side probe shots confirm zero humanoid geometry in the camera frustum.

**Root cause** (`scripts/crew_deck.gd:126-142`):
```gdscript
rig.scale = Vector3(0.01, 0.01, 0.01)             # local scale set
...
rig.global_transform = procedural_node.global_transform   # global set BEFORE add_child
procedural_node.add_child(rig)                            # add after — Godot re-composes
```
Setting `global_transform` on a parentless Node3D stores it in `transform`; once `add_child` runs and the parent has a non-uniform parent transform chain, the rig's local position is recomputed by Godot and lands at `(-10, -500, 6)`. The Meshy humanoid renders at world y=-500 — completely off-screen.

Compare to `scripts/ship.gd:538-539`, which does it correctly: hide procedural FIRST, then `add_child(mi)` — the mesh stays at the ship's world position because it never has its `global_transform` set independently.

**Why `04_crew_deck.png` PASSes the pixel diff (2.79%):** the baseline already shows blurry small figures at this small thumbnail resolution, so removing them costs only 2-3% diff. Vision analysis (and any human reviewer) immediately catches the regression.

**DoD line broken**: "Crew-deck interaction view with visible procedural humanoid crew/marines."

**Suggested fix** (Big Pickle pass):
1. In `_try_load_meshy_humanoid`, set `procedural_node.add_child(rig)` FIRST, then set `rig.global_transform = procedural_node.global_transform`, OR simpler: set `rig.transform = Transform3D.IDENTITY` after `add_child`.
2. Also re-show the procedural capsule humanoids as a fallback if `Game.MESHY_VISUAL_UPGRADE_ENABLED` is false or the GLB fails to instantiate — the current code already hides the procedural parts unconditionally once the helper is reached.

### C-2. All 6 voice barks and 3 music tracks are orphaned (unwired)

**Severity**: Critical
**Where**: `scripts/audio.gd:38-52`, no call sites in `scripts/`
**Evidence**:
```bash
$ grep -nR "audio\.play_music\|audio\.stop_music\|audio\.set_music_volume\|commander_\|announcer_\|marine_contact\|marine_affirmative" scripts/ tools/
scripts/audio.gd:46:	"commander_battle_stations": ASSET_PREFIX + "voice/commander_battle_stations.ogg",
scripts/audio.gd:47:	"commander_engage":          ASSET_PREFIX + "voice/commander_engage.ogg",
scripts/audio.gd:48:	"marine_contact":            ASSET_PREFIX + "voice/marine_contact.ogg",
scripts/audio.gd:49:	"marine_affirmative":        ASSET_PREFIX + "voice/marine_affirmative.ogg",
scripts/audio.gd:50:	"announcer_docking":         ASSET_PREFIX + "voice/announcer_docking.ogg",
scripts/audio.gd:51:	"announcer_welcome":         ASSET_PREFIX + "voice/announcer_welcome.ogg",
```
Zero call sites for `play_music`, `stop_music`, `set_music_volume`, `set_ambient_volume`, and any of the 6 voice triggers anywhere in the project.

**Acceptance criterion broken**: `docs/audio_production_brief.md:92` — "At least 10 voice lines are produced and **wired to gameplay events**." (We have 6, none wired.)

**Files shipped that nobody plays**:
- `assets/audio/music/combat.ogg` (98 KB)
- `assets/audio/music/exploration.ogg` (70 KB)
- `assets/audio/music/station.ogg`
- `assets/audio/voice/commander_battle_stations.ogg`
- `assets/audio/voice/commander_engage.ogg`
- `assets/audio/voice/marine_contact.ogg`
- `assets/audio/voice/marine_affirmative.ogg`
- `assets/audio/voice/announcer_docking.ogg`
- `assets/audio/voice/announcer_welcome.ogg`

**Why gates pass**: `tools/check_audio_wiring.py` only parses the `SOUNDS` dict — it ignores `MUSIC` and `VOICE` entirely (see `check_audio_wiring.py:30-31`, only `SOUNDS` regex).

**Suggested fix** (Big Pickle pass):
- Wire `play_music("combat")` in `_ready` (and switch on fleet/disposition state in `_process_space`).
- Wire `audio.play_music("station")` when the player docks; `audio.play_music("exploration")` when undocked with no hostiles.
- Wire voice barks at:
  - `announcer_welcome` / `announcer_docking` — when `force_deck(false)→true` after docking
  - `commander_battle_stations` — when hostile count crosses threshold / first hostile acquired
  - `commander_engage` — when player fires weapons
  - `marine_contact` — when a boarding action initiates
  - `marine_affirmative` — when a boarding round resolves in the attacker's favor
- Extend `check_audio_wiring.py` to also enforce wiring of `MUSIC` and `VOICE` dicts (parse them the same way and grep for call sites), or add a new sibling check (`check_audio_assets.py`).

### C-3. Screenshot diff: 4/5 frames regressed vs committed baseline

**Severity**: Critical (delivery contract violation — the diff tool is non-fatal by design, but the regressions are real)
**Where**: `tools/validate_build.sh:90-105`
**Evidence**: Step 5 output above. Frames 01, 02, 03, 05 differ from baseline by 49–73%. Only 04 (crew deck) is "within tolerance" — and that is by accident (see C-1).
**Analysis**: The diffs are largely explained by:
1. **Meshy ship GLB upgrade chain** (commits `e956561` → `3c1af78` → `2774cf1` → `83e71d0` → `2837d00` → `2e66ddd` → `4ec86cb`) replaced procedural ships with authored GLBs. Visual change is intentional and expected.
2. **Crew deck regression** (C-1): baseline shows 3 procedural crew figures with labels; current shows zero.
3. **Camera framing drift in auto_demo**: the auto-demo path drives the player into close quarters; positions are non-deterministic but the seeding (`rng.seed = 20260623`) is deterministic, so framing should be stable. The current vs baseline diffs of 49-73% are higher than pure ship-swap should produce.

**Why this is Critical and not just a "we know visual change was intentional"**: the do-or-die `04_crew_deck.png` regression is masked by the diff budget. A real change here would slip through silently.

**Suggested fix**:
- Re-baseline after C-1 is fixed, then make the diff budget tighter (5% pixel + 0.95 structural similarity, or hand-pick ROIs).
- Add a `must_have_label_count` check to `04_crew_deck.png` — assert at least 2 Label3Ds visible in the deck shot. Would have caught C-1 deterministically.

---

## 4. High findings

### H-1. 304 `ERROR: No animation in cache.` lines on capture run

**Severity**: High
**Where**: `scripts/crew_deck.gd:144-162` (`AnimationPlayer.root_node` retargeting)
**Evidence**: `grep -c "No animation in cache" capture.log` → **304** hits in a 10-second capture run, plus continuing throughout smoke runs (`scene/animation/animation_mixer.cpp:1138/1188`).
**Root cause**: `_try_load_meshy_humanoid` does:
```gdscript
ap.root_node = rig.get_path_to(arm_node)
ap.play(chosen)
```
After setting `root_node` to a new path, the AnimationPlayer's animation cache (keyed by node paths) is invalidated, but the player continues to feed cached track entries that point at the old root. Each track lookup errors every frame.
**Impact**: Log spam clutters any debug/QA run; engine still renders frames so it's not a crash. The Meshy humanoids render but are not actually animated (they pose in their bind pose because the animation never resolves).
**Suggested fix**: After `ap.root_node = …`, call `ap.stop()` then re-assign the animation and `ap.play(chosen)` again. Better: instead of reassigning `root_node`, store the GLB-scoped rig at the same parent and use AnimationTree instead. Cheapest workaround: drop the `root_node` reassignment and accept bind-pose figures (acceptable for the slice).

### H-2. Bus layout volume defaults need review

**Severity**: High (gameplay-comfort, not a defect per se)
**Where**: `default_bus_layout.tscn`
**Evidence**: Bus volumes baked in:
- `Music: -6.0 dB`, `Ambient: -12.0 dB`, `Voice: 0.0 dB`, `SFX: 0.0 dB`, `Master: 0.0 dB`.
The `Music` and `Ambient` ducker-friendly bus levels are sensible, but the settings menu (`F1` → Volume row, 0–100% on `Master`) overrides only the Master bus via `linear_to_db`, never the children. When a player turns Master to 50%, all child buses drop with it, but if they want to boost music vs SFX, they have no per-bus control.
**Suggested fix**: Add per-bus rows to the settings menu (Music dB, SFX dB, Voice dB, Ambient dB), persisted in the save file (or kept display-only like the rest of settings).

### H-3. Owner-inconsistency warnings on every Meshy GLB instantiation

**Severity**: High (clutter + sign of fragile reparenting)
**Where**: `scripts/crew_deck.gd:128-135`, `scripts/ship.gd:613-632`
**Evidence**: Every Meshy GLB instantiation produces 4–5 `WARNING: Adding 'X' as child to 'Y' will make owner '...' inconsistent. Consider unsetting the owner beforehand.` warnings. The capture run produces 50+ warnings just for the captain + 2 crew + 14 ship entities.
**Impact**: Warnings are benign in Godot (the owner is only used for editor serialization, not runtime), but they make the validate log 80+ lines of noise that hides real issues.
**Suggested fix**: Before `add_child`, set `n.owner = null` (or set owner after the add_child). The ship path correctly does `node.remove_child(found)` before `add_child(found)`; crew_deck should do the same for the rig subtree.

### H-4. `check_audio_wiring.py` does not cover MUSIC/VOICE

**Severity**: High (silent coverage gap)
**Where**: `tools/check_audio_wiring.py:30-31, 47-62`
**Evidence**: The checker parses only `SOUNDS`. `MUSIC` and `VOICE` tables in the same `audio.gd` are completely ignored. This is why C-2 slipped through.
**Suggested fix**: Replace the single-`SOUNDS` regex with a sweep for any `const <NAME>: Dictionary` whose entries are string paths under `res://assets/audio/`, then grep for call sites per dict. Or factor out `audio.gd` dict scanning and have `check_audio_wiring.py` cover SFX+Music+Voice with one pass.

---

## 5. Medium findings

### M-1. Screenshot diff's `--max-diff-pct` (5%) is too lenient for visual fidelity

**Severity**: Medium
**Where**: `tools/screenshot_diff.py` (threshold=30, max_diff_pct=5%)
**Evidence**: Step 5 result above shows 49–73% pixel diffs flagged as WARN-only.
**Suggested fix**: Tighten to 10–15% diff for non-crew-deck frames (intentional ship swap should be <20% per frame), and add a structural-similarity threshold (e.g. pHash distance ≤ 6) as a second gate.

### M-2. `_set_deck_mode(true)` doesn't reset the crew-deck camera angle for the captain position

**Severity**: Medium (UX)
**Where**: `scripts/crew_deck.gd:206-214` (`_update_camera_for_room`)
**Evidence**: Camera is fixed at `(cx, 6, 13)` pitch -19°. With captain starting at `(cx, 0, 6)`, the captain is 60° below the camera's forward axis — *off-screen*. The probe in C-1 showed the captain at y=0, z=6 — outside the FOV half-angle of 29°.
**Suggested fix**: Either lower the camera (y=2.5, z=18, pitch=-12°) or move the captain into the visible area (z=-2 to z=2). Whichever is chosen, the captain and consoles must both be in frame.

### M-3. `auto_demo` mode enters deck with the Meshy rig mis-parented

**Severity**: Medium (affects delivery artifact, not gameplay)
**Where**: `scripts/main.gd:402, 414-416`; `scripts/crew_deck.gd:108-162`
**Evidence**: When `auto_demo` flips on, `force_deck(true)` is exercised by the capture timeline. The deck shot 04 is the screenshot deliverable that ships with the release; with C-1 unfixed it's a blank room.
**Suggested fix**: Fix C-1. No additional M-3 work needed once the rig parenting is corrected.

### M-4. `README.md` still claims "Everything is **code-built / procedural** — no imported art assets"

**Severity**: Medium (docs drift)
**Where**: `README.md:6`
**Evidence**: Since commit `e956561` (Meshy visual upgrade), 14 entity classes are Meshy GLBs and 30+ OGG audio assets are imported. The README intro still claims procedural-only.
**Suggested fix**: Update README intro to reflect authored art + authored audio.

### M-5. `docs/audio_production_brief.md` acceptance criteria mismatch

**Severity**: Medium
**Where**: `docs/audio_production_brief.md:89-97`
**Evidence**: Brief says "At least 10 voice lines", but only 6 are produced. The brief's acceptance also says "wired to gameplay events" — see C-2.
**Suggested fix**: Either produce 4 more voice lines and wire all 10, or amend the brief's bar to match what shipped.

---

## 6. Low findings

### L-1. Save verifier exit status read by `_do_autosave` may not respect current `SAVE_VERSION` if brief is re-bumped

**Severity**: Low
**Where**: `tools/verify_save_load.py` + `scripts/main.gd:184`
**Evidence**: `SAVE_VERSION = 2` is the current. The verifier is pinned to v2. If a future bump to v3 lands without updating the verifier, a v2 save will be flagged as a future-version reject.
**Suggested fix**: Read `SAVE_VERSION` from `scripts/main.gd` programmatically instead of hard-coding.

### L-2. `artifacts/qa_report.md` at repo root is stale (last touched Jun 19)

**Severity**: Low
**Where**: `/home/ganomix/projects/voidborne-command/artifacts/qa_report.md`
**Evidence**: Last modified date is older than the current kanban run. Per kanban convention, fresh QA artifacts go under `artifacts/qa/<timestamp>/report.md`. The root file is leftover from a prior kanban worker.
**Suggested fix**: Either delete or move the root file under `artifacts/qa/<old-timestamp>/` and rely on the per-run subfolder.

### L-3. Probe tooling left behind during review (cleaned up)

**Severity**: Low (transient)
**Where**: `tools/`
**Evidence**: Created `tools/qa_deck_probe.gd` + `tools/qa_deck_probe.tscn` to gather C-1 evidence; deleted before completion. Confirm via `ls tools/` — both files removed.
**Suggested fix**: None — cleanup verified.

---

## 7. DoD cross-check (definition_of_done.md)

| Line | DoD claim | Status | Evidence |
|---|---|---|---|
| Player flies a ship (throttle, boost, brake, yaw, pitch, roll) | VERIFIED | Inputs wired in project.godot; smoke test passes. |
| Weapons fire (projectiles + beams); hull/shield/energy modeled | VERIFIED | `_fire_weapon`, `_update_projectiles`, `_fire_beam` all in main.gd. |
| Hostile-first target cycling + target-lock HUD | VERIFIED | Tab cycles in main.gd; HUD has target panel. |
| Third-person chase camera + readable HUD | VERIFIED | `space_camera` follows player; HUD bars/radar/reticle/messages render. |
| Recruit crew and marines at station | VERIFIED | `_recruit` paths in main.gd. |
| **Crew-deck view with visible procedural humanoid crew/marines** | **BROKEN** | **C-1 — Meshy rig at y=-500; deck shot is empty.** |
| Interact with crew/marines, order follow | VERIFIED | `process_deck` + `_handle_deck_actions`. |
| Hostiles can be disabled | VERIFIED | DISABLE_FRAC = 0.22 (in GameConstants); tests pass. |
| Boarding with marines shows progress | VERIFIED | `boarding_progress`, `boarding_attacker_strength`, etc. |
| Captured ships/stations switch faction | VERIFIED | `Game.captured_count`, faction update. |
| Buy ships at station | VERIFIED | SHIPYARD_CLASSES + `_buy_ship`. |
| Assign crew so ships are manned | VERIFIED | `apply_crew_bonuses`. |
| Manned ships follow in fleet formation | VERIFIED | `fleet_order == "follow"` AI in main.gd. |
| Distinct classes (fighter/corvette/frigate/capital + station) | VERIFIED | SHIP_CLASSES table; distinct stats/scale/weapons. |
| Live battle: hostile wing, larger hostile, station, beams/projectiles/explosions | VERIFIED | STAR_SYSTEMS[0] Halcyon Reach battle. |
| Imports + smoke-runs headless with no SCRIPT/Parse/Invalid | VERIFIED | validate_build.sh exit 0, clean. |
| validate/capture/contact-sheet/check-audio present and passing | VERIFIED | All four tools exit 0 (but see H-4). |
| Screenshots non-black, show battle + HUD | **PARTIAL** | Luma OK, but C-1 means deck shot is empty; HUD always shows. |
| No `class_name` on autoloads | VERIFIED | Autoloads have no class_name. |
| Docs (README, GDD, studio briefs) | VERIFIED | All present. |
| Music tracks loop cleanly | **UNVERIFIED** | 3 OGGs shipped; never played (C-2). Loop integrity unverified by any test. |
| Voice lines wired to gameplay events | **BROKEN** | **C-2 — 6 voice barks, zero call sites.** |

---

## 8. Fix list for Big Pickle (opencode-zen) pass

Ordered by impact, smallest to largest churn:

1. **C-2 / H-4** — wire music + voice. Add a small audio coordinator that calls `play_music` on system enter and on dock/undock, and fires voice barks at the events listed in C-2. Extend `check_audio_wiring.py` to also enforce `MUSIC` and `VOICE` wiring (one sweep over all `*: Dictionary` string-path constants in `audio.gd`).
2. **C-1 / M-2 / M-3** — fix Meshy humanoid rig parenting in `_try_load_meshy_humanoid`. Set `procedural_node.add_child(rig)` BEFORE `rig.global_transform = procedural_node.global_transform`, OR just `rig.transform = Transform3D.IDENTITY` post-add. Re-test deck shot — it should restore the 3 capsule crew figures and add 1 captain Meshy rig.
3. **C-3** — re-baseline `artifacts/screenshots/` after C-1 fix; tighten `screenshot_diff.py` thresholds and add a Label3D-presence check on `04_crew_deck.png`.
4. **H-1** — fix or drop the `AnimationPlayer.root_node` retarget; bind-pose figures are acceptable for the slice.
5. **H-3** — `n.owner = null` before add_child in crew_deck rig subtree (mirrors ship.gd's reparent pattern).
6. **H-2** — optional per-bus sliders in settings menu.
7. **M-4** — update README intro to reflect authored art + audio.
8. **M-5** — produce 4 more voice lines OR amend the brief to match what shipped.

After C-1 + C-2 are fixed and C-3 is re-baselined, the slice meets every line of the DoD, and the gates will continue to pass without warning churn.

---

## 9. Artifacts written by this review

- `/home/ganomix/projects/voidborne-command/artifacts/qa/20260627T190932Z/report.md` (this file)
- `/home/ganomix/projects/voidborne-command/artifacts/qa/20260627T190932Z/import.log` (headless import, 75 lines)
- `/home/ganomix/projects/voidborne-command/artifacts/qa/20260627T190932Z/validate.log` (validate_build.sh output)
- `/home/ganomix/projects/voidborne-command/artifacts/qa/20260627T190932Z/capture.log` (capture_screenshots.sh output)
- `/home/ganomix/projects/voidborne-command/artifacts/qa/20260627T190932Z/audio_wiring.log` (check_audio_wiring.py output)
- `/home/ganomix/projects/voidborne-command/artifacts/qa/20260627T190932Z/contact_sheet.log` (make_contact_sheet.py output)
- `/home/ganomix/projects/voidborne-command/artifacts/screenshots/contact_sheet.jpg` (regenerated contact sheet, 1304x1112)
- `/home/ganomix/projects/voidborne-command/artifacts/screenshots/*.png` (5 screenshots, all non-black)

---

## 10. Return-format summary

1. **Report path**: `/home/ganomix/projects/voidborne-command/artifacts/qa/20260627T190932Z/report.md`
2. **Verdict**: **NEEDS_FIX**
3. **Issues by severity**: C=3, H=4, M=5, L=3 (total **15**)
4. **Headless import**: exit 0; last 5 lines show "Editor layout ready" + "loading_editor_layout: end"
5. **Contact sheet**: `/home/ganomix/projects/voidborne-command/artifacts/screenshots/contact_sheet.jpg` (1304x1112, 5 tiles); per-image mean luma 91.24 / 89.20 / 91.84 / 66.19 / 66.76 — all far above the 8.0 black threshold.
