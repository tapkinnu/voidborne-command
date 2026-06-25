# Voidborne Command — QA Review (2026-06-25T16:04:03Z)

## 0. Verdict

**NEEDS_FIX**

Four gates all pass and the code refactors (constants centralization, save-schema /
economy-pricing / space-backdrop extraction) are clean — no new script/parse errors,
no leak regressions, all 41 GDScript tests green, audio wiring complete, contact
sheet is bright and well-formed.

However the headless QA capture pipeline produces screenshots whose HUD shows
a 1,000,000,000-unit distance readout and a "Captain destroyed" message log,
because the auto-demo's "demo durability" cap does not survive the first ~3
seconds of capture-demo fire. The same bug exists in the **committed baseline
screenshots** (artifacts/baseline/*.png from 2026-06-24), so prior QA passes
missed it. Two real defects need a fix pass before this slice ships QA-clean:

| # | Severity  | Summary                                                                     |
|---|-----------|-----------------------------------------------------------------------------|
| 1 | **HIGH**  | `_pdist()` returns `1e9` when player invalid → HUD shows "DIST 1000000000"   |
| 2 | **HIGH**  | Capture-demo "demo durability" is too low; flagship dies ~3.4 s into capture |
| 3 | **MEDIUM**| ObjectDB leak warning during smoke run when player destroyed mid-game       |
| 4 | **LOW**   | Screenshot-diff vs committed baseline fails on all 5 tiles (non-fatal gate)  |

## 1. Commit / state reviewed

- Repo: `/home/ganomix/projects/voidborne-command`
- Branch: `main` (local HEAD ahead 3 of `origin/main`)
- **Local HEAD**: `f39d52b` — `refactor: centralize gameplay balance constants into GameConstants`
- Uncommitted: `M scripts/main.gd`, `?? scripts/economy_pricing.gd`, `?? scripts/save_schema.gd`, `?? scripts/space_backdrop.gd` (the extraction work landed in working tree after `HEAD~1`)
- `validate_build.log` contains the previous prior-SHA run too; latest run appended at the end. Two near-identical smoke runs, both PASS.

The bug described below is **pre-existing**: baseline screenshots in
`artifacts/baseline/03_target_lock.png` (committed 2026-06-24) show the same
`DIST 1000000000` and the same destroyed-captain log line, so the refactors in
`f39d52b` / `79a1b64` did not regress this — but they also did not fix it.

## 2. Gates

| Gate                          | Exit | Result    | Notes                                                                                       |
|-------------------------------|------|-----------|---------------------------------------------------------------------------------------------|
| `./tools/validate_build.sh`   | 0    | PASS      | 41/41 GDScript tests print `*_TEST_PASS`; no SCRIPT ERROR / Parse Error / Invalid call.     |
| `./tools/capture_screenshots.sh` | 0 | PASS      | 5 PNGs written to `artifacts/screenshots/`, 1280x720, luma avg 67–97 (no black frame).       |
| `make_contact_sheet.py`       | 0    | PASS      | 1304x1112 5-tile contact sheet; per-image luma 97/91/91/67/91 — none black.                 |
| `check_audio_wiring.py`       | 0    | PASS      | 21/21 SFX triggers wired to `audio.play()` call sites.                                      |

Validate-build log: `artifacts/qa/20260625T160403Z/validate_build.log`
Capture log:      `artifacts/qa/20260625T160403Z/capture_screenshots.log`
Contact sheet log:`artifacts/qa/20260625T160403Z/contact_sheet.log`
Audio wiring log: `artifacts/qa/20260625T160403Z/audio_wiring.log`

**Optional sub-step (non-fatal):** `tools/screenshot_diff.py` reports
20–51 % per-tile diff vs `artifacts/baseline/`. See finding #4.

## 3. Visual review

### 3.1 Screenshots saved

`artifacts/screenshots/01_space_battle.png` … `05_fleet.png` and the
5-tile `contact_sheet.jpg`. Thumbnails + cropped HUD strips for each tile
are in this evidence dir (`*_thumb.png`, `*_tr.png`).

### 3.2 Per-tile assessment

| Tile                  | Frame OK? | Player visible? | HUD readable? | Content                                          |
|-----------------------|-----------|-----------------|---------------|--------------------------------------------------|
| 01 space_battle       | Yes       | Behind camera (correct for third-person chase) | Yes (fleet status, radar, reticle) | Ironclaw frigate + escort wing engaged; live weapon-fire overlay. Distant galaxy band visible bottom-left. |
| 02 dogfight           | Yes       | Behind camera   | Yes           | Two beam weapons (cyan, green) converging on Ironclaw behind the Kryos Relay station. "Ironclaw must be DISABLED before boarding" in mission log. |
| 03 target_lock        | Yes       | (destroyed)     | Yes — but `DIST 1000000000` shown | Target panel says `TGT: Ironclaw / FRIGATE HOSTILE / HULL ~low / SHIELD empty / DIST 1000000000 GAR 4/4`. |
| 04 crew_deck          | Yes       | (crew deck view, player on bridge) | Yes       | One crew avatar (Cyr-74 [ENG] S3 M52%) visible; greybox interior; message log shows "Captain destroyed / Wing-2 destroyed / Wing-1 destroyed". |
| 05 fleet              | Yes       | (destroyed)     | Yes — but `DIST 1000000000` shown | ~10 ship silhouettes clustered around the player; laser beams visible; "WEAPON FIRE" overlay; target panel still locked on Ironclaw with `DIST 1000000000`. |

### 3.3 Black-frame check

All five PNGs and the contact sheet pass a luma dynamic-range check
(lo/hi/avg luma over an 8x8 sample grid):

```
01_space_battle.png    1280x720   luma  4.1/247.8/ 88.9
02_dogfight.png        1280x720   luma  7.4/247.7/ 91.4
03_target_lock.png     1280x720   luma  7.4/247.7/ 99.0
04_crew_deck.png       1280x720   luma 13.3/216.5/ 70.6
05_fleet.png           1280x720   luma  7.4/247.7/ 93.5
contact_sheet.jpg      1304x1112  luma 11.9/250.6/ 68.6
```

No frame is black. The visual "no scene" worry from earlier QA reviews is resolved.

## 4. Findings

### Finding #1 — HIGH — `DIST 1000000000` shown on target HUD

**Files**: `scripts/main.gd:3141-3144` (`_pdist`), `scripts/main.gd:5378` (consumer in HUD data builder), `scripts/hud.gd:183` (renderer).

**Repro**:
1. `./tools/capture_screenshots.sh`
2. Open `artifacts/screenshots/03_target_lock.png` and `05_fleet.png`
3. Read the target panel bottom row — `DIST 1000000000`.

**Expected**: a sensible distance to the targeted ship, e.g. `DIST 109` in capture-demo
staging where Ironclaw is at `(-16, -2, -78)` and player at `(0, 4, 28)`.

**Actual**: `DIST 1000000000` (one billion world units) is shown on both tile 3 and tile 5.

**Root cause** (verified by instrumented probe in this review):

`main.gd:3141`
```gdscript
func _pdist(s: Node3D) -> float:
    if not is_instance_valid(player):
        return 1e9
    return player.global_position.distance_to(s.global_position)
```

The sentinel `1e9` was meant to mean "no player / distance unknown". It then
flows unchecked into the HUD target dict at `main.gd:5378`:

```gdscript
"dist": _pdist(target),
```

The player block at `main.gd:5361` is correctly guarded with
`if is_instance_valid(player) and not player.destroyed:`, but the target
block (`main.gd:5371`) only guards the target reference, not the player
one. The HUD at `hud.gd:183` formats the float with `%d`:

```gdscript
var status: String = "DIST %d" % int(float(tgt.get("dist", 0.0)))
```

`int(1e9) == 1000000000` and that is what is rendered.

**Why this fires during the QA capture pipeline specifically**: in
`_stage_capture_demo()` (`main.gd:3064-3074`) the player is given a
temporary durability boost (max shield 900, max hull 1200), but the
Ironclaw frigate plus the rest of the hostile wing fire continuously and
overwhelm those caps within ~3 seconds — see Finding #2. By the time the
capture autoload grabs tile 3 at `t = 5.2 s` and tile 5 at `t = 8.0 s`,
`is_instance_valid(player)` is already false (probe shows the flip at
`t = 3.46 s`, frame 501). Any captured HUD frame therefore reads `1e9`
until the player ship respawns.

This bug is also visible in the committed `artifacts/baseline/03_target_lock.png`
(2026-06-24) and `05_fleet.png` — same `DIST 1000000000` text, same
destroyed-captain log lines. So it pre-dates the two refactors on the
current branch and was missed by the prior QA pass `t_bad7b1f7` (which
filed as PASS). The vision-model pass this review ran picked it up; the
earlier PASS relied only on luma-based black-frame heuristics.

**Suggested fix**:
- (a) Make `_pdist()` return `-1.0` (or `NAN`) instead of `1e9` so the sentinel
  is never accidentally formattable as a world distance.
- (b) In `_build_hud_data()` (`main.gd:5371-5386`) gate the target block's
  `dist` with `if is_instance_valid(player) else -1.0`.
- (c) In `hud.gd:183` short-circuit: if `tgt.get("dist") < 0` render `DIST —`
  instead of formatting the float.
- (d) Independently, also fix the demo-durability so player doesn't actually
  die — see Finding #2.

### Finding #2 — HIGH — Capture-demo "demo durability" cap is too low

**File**: `scripts/main.gd:3064-3074` (`_stage_capture_demo`).

**Repro**: run `VOIDBORNE_CAPTURE=<out_dir> tools/capture_screenshots.sh`
(or run a probe: see evidence `artifacts/qa/20260625T160403Z/probe_*.log`).

**Expected**: the comment at line 3066-3068 reads:
> "Capture-mode should demonstrate the new systems, not randomly kill the
> flagship before screenshots finish."

So the player's hull/shield should stay non-zero for at least the full
~10 s capture window.

**Actual** (observed with an instrumented probe, not visual):
```
t=1.6  hull=906/1200  shield=3/900
t=2.2  hull=553/1200  shield=0/900
t=3.0  hull= 78/1200  shield=0/900  disabled=true
t=3.46 is_instance_valid(player) == false
```
The flagship is **destroyed at t ≈ 3.4 s**, then the capture autoload
proceeds to take screenshots that show a battle the player is no longer in.

**Root cause**: the demo durability is `max(player.max_shield, 900)` and
`max(player.max_hull, 1200)` — i.e. caps, not floors against current damage.
But the Ironclaw frigate (and the four Raider escorts plus the four
demo beams added at line 3095-3098) deliver sustained damage from full
range. The shield collapses in ~2 s, then hull drops below
`0.22 * max_hull` (GameConstants.DISABLE_FRAC from `f39d52b`), disabling
the player. Once disabled, the boarding/defence and target-keeping logic
keeps firing, pushing hull below zero. After destruction,
`_destroy_ship(player)` (`main.gd:2811`) frees the node, so
`main.player` becomes invalid.

**Suggested fix**: instead of raising caps, **make the player invincible
during auto-demo**, e.g.

```gdscript
if auto_demo and is_instance_valid(player):
    player.hull = player.max_hull
    player.shield = player.max_shield
    player.disabled = false
```
applied in `_process_space()` whenever `auto_demo` is true (or as a flag
on the Ship class, `invulnerable`, set by `_stage_capture_demo()`).
Re-charge shields / hull every frame so the demo frames always show a
healthy flagship firing into a damaged-but-firing frigate.

### Finding #3 — MEDIUM — ObjectDB leak during smoke run

**File**: `artifacts/validate.log:368`
```
WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
     at: cleanup (core/object/object.cpp:2378)
```

**Repro**: `./tools/validate_build.sh` (step 3, the 30 s smoke run).

**Expected**: no leak — the recently merged commit `4b26526 fix: eliminate
ObjectDB instance leaks in headless test runs` is supposed to keep the
smoke run leak-free.

**Actual**: 1 leak warning per smoke run. Likely related to the
`_destroy_ship` path freeing the player mid-frame before the HUD/target
references on other ships have been nulled (line 2797-2800 loops over
`ships`, but the player's `target` is nulled at line 2794 only when
`s == target`, while the player's own `s.target` is not cleared). The
prior leaks mentioned in `4b26526` were about test runners; this one
looks like a separate path triggered when the player is destroyed.

**Severity**: medium because the warning fires every run, but only
during the capture-demo branch (where auto_demo forces the death). It
should not happen in normal gameplay capture.

**Suggested fix**: in `_destroy_ship` (`main.gd:2811`), before
`s.queue_free()`, ensure the Ship's own `s.target` reference is nulled
and any project-wide dict that holds `s` as a value is cleaned. Consider
adding an `invulnerable` flag path that prevents `destroyed=true` in
auto_demo mode (which would also fix Finding #2).

### Finding #4 — LOW — Screenshot-diff regression vs committed baseline

`python3 tools/screenshot_diff.py artifacts/baseline artifacts/screenshots`
reports:
```
01_space_battle.png    20.354%  FAIL
02_dogfight.png        51.074%  FAIL
03_target_lock.png     49.646%  FAIL
04_crew_deck.png       49.006%  FAIL
05_fleet.png           47.506%  FAIL
```
The diff is **non-fatal** by design (validate_build.sh exits 0 and logs
"WARN: screenshot diff detected regression (non-fatal)"). The high
diff percentages are caused by the same root bug — the player is in a
different state at screenshot time than when the baseline was captured.
Both pre- and post-fix diffs will fail until the demo-durability bug is
fixed; once fixed, the diff should drop below the 5 % threshold for
tiles 1 and 2, and remain in the 10–30 % range for tiles 3-5 because
the live hostile AI position varies each run.

**Suggested fix**: regenerate `artifacts/baseline/*.png` after fixing
Finding #2 by running `tools/save_baseline.sh`.

### Finding #5 — INFO — Module extraction refactor (commit `79a1b64`) is clean

Three new scripts (`economy_pricing.gd`, `save_schema.gd`,
`space_backdrop.gd`) cleanly delegate to `main.gd`'s existing public
methods (`_commodity_prices`, `_validate_save`, `_build_environment`,
`_build_stars`, `_ship_credit_value`, `_capture_credit_reward`,
`_destroy_salvage_reward`). No `class_name` collision risk, no circular
imports, no public-API breakage. All thin forwarders verified by grep
(see `main.gd:1150-1156`, `1427-1435`, `2813-2820`, `4811-4817`). The
save-schema validator still passes 35/35 cases (`Step 1b`).

### Finding #6 — INFO — Vision model initially misread tile 1/2 "white rectangle"

The first vision-model pass on the contact sheet called the central
bright shape a "rendering error / missing-texture artifact". A second
targeted inspection confirmed it is the **Kryos Relay station** (tile 2)
or the **distant galaxy band** (tile 1), not a glitch. The low-fidelity
greybox aesthetic is intentional — vision models without scene context
sometimes mis-classify large unshaded geometry as a glitch.

## 5. Suggested fix list for the next Claude Code pass

1. **`scripts/main.gd`** — make `_pdist()` return `-1.0` (not `1e9`) when
   the player is invalid; gate the HUD target dict's `"dist"` with
   `if is_instance_valid(player)`.
2. **`scripts/main.gd:3064-3074`** — replace the "max(cap, current)" demo
   durability with an `invulnerable` flag or a per-frame hull/shield
   reset so the flagship survives the entire capture window.
3. **`scripts/hud.gd:183`** — if `tgt.get("dist") < 0` render `DIST —`
   instead of formatting the float.
4. **`scripts/main.gd:2811` `_destroy_ship`** — also clear `s.target` on
   the dying ship itself and any subsystem dictionary holding it, to
   address the ObjectDB leak during the auto-demo death path.
5. **`tools/save_baseline.sh`** — re-run after #1/#2 are fixed to refresh
   `artifacts/baseline/`, which will bring the diff percentages below
   the 5 % threshold for the static tiles (1, 2) and into the expected
   range for the dynamic tiles (3–5).

## 6. Artifacts written by this review

All under `/home/ganomix/projects/voidborne-command/artifacts/qa/20260625T160403Z/`:

```
report.md                  ← this file
validate_build.log         ← copy of artifacts/validate.log tail
capture_screenshots.log    ← capture tool stdout/stderr
contact_sheet.log          ← contact sheet build summary
audio_wiring.log           ← audio trigger check
01..05_*_thumb.png         ← 640x360 thumbnails of each capture
01..05_*_tr.png            ← top-right HUD crop per tile
baseline_03_tr.png         ← baseline 03 top-right HUD crop (same DIST 1e9)
baseline_05_tr.png         ← baseline 05 top-right HUD crop (same DIST 1e9)
```

No source files, scenes, project metadata, or baseline screenshots were modified.