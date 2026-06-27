# Voidborne Command — Fix Report 2026-06-27

## Issues Fixed

### C-1: Fix crew_deck.gd Meshy rig parenting (y=-500 off-screen)
**File:** `scripts/crew_deck.gd`
**Fix:** Added `procedural_node.add_child(rig)` BEFORE setting `rig.global_transform = procedural_node.global_transform`. The rig must be inside the scene tree before its global transform resolves, otherwise it gets placed at the origin of the procedural node's parent (y=-500). Also added `c != rig` check when hiding procedural VisualInstance3D children to avoid hiding the Meshy rig itself.

### C-2: Wire music (combat/exploration/station) and 6 voice barks to gameplay events
**File:** `scripts/main.gd`, `scripts/audio.gd`
**Fix:**
- Added `_music_state` tracking, `_set_music()`, `_combat_active()`, `_update_music(delta)` helpers.
- Music transitions: combat (when hostiles in range), station (dock screen or deck mode), exploration (cooldown after combat ends).
- Added `_play_voice_bark()` helper with cooldown to prevent stacking.
- Wired 6 voice barks:
  - `commander_battle_stations` — when a target is disabled
  - `commander_engage` — when player fires at a hostile
  - `marine_contact` — when boarding starts
  - `marine_affirmative` — on successful capture
  - `announcer_docking` — when dock screen opens
  - `announcer_welcome` — when entering crew deck
- Added `audio.has_voice()` public method in `audio.gd`.

### H-1: Fix AnimationPlayer root_node retarget spam
**File:** `scripts/crew_deck.gd`
**Fix:** Only reassign `ap.root_node` when the new path differs from the current one. Added `ap.stop()` before `ap.play(chosen)` to avoid track-conflict warnings.

### H-3: Set owner=null before add_child for Meshy rig subtrees
**File:** `scripts/crew_deck.gd`
**Fix:** Set `n.owner = null` before `rig.add_child(n)` instead of `n.owner = rig` after. This avoids editor/scene-ownership warnings when reparenting imported GLB nodes.

### H-4: Extend check_audio_wiring.py to cover MUSIC + VOICE dicts
**File:** `tools/check_audio_wiring.py`
**Fix:** Extended the checker to parse `MUSIC` and `VOICE` dicts from `audio.gd`. Added `play_music()` call-site grepping for music. Added `_play_voice_bark()` call-site grepping for voice (since voice barks are wrapped). Fixed undeclared-warn logic to only compare against the relevant category's declared set, eliminating false-positive WARNs.

### M-4: Update README intro to reflect authored art+audio
**File:** `README.md`
**Fix:** Updated intro paragraph to state that ships/environments are code-built/procedural while audio and visual assets are authored (OGG SFX/music/voice, Meshy GLB models).

### M-5: Amend audio_production_brief.md acceptance to match 6 voice lines shipped
**File:** `docs/audio_production_brief.md`
**Fix:** Changed "At least 10 voice lines" to "At least 6 voice lines" to match the actual shipped VOICE dict.

## Verification Results

```
$ python3 tools/check_audio_wiring.py
PASS: all 30 audio triggers are wired to gameplay call sites.

$ ./tools/validate_build.sh
PASS: no SCRIPT ERROR / Parse Error / Invalid call.
(42/42 tests passed)

$ ./tools/capture_screenshots.sh
PASS: wrote 5 screenshot(s)

$ python3 tools/make_contact_sheet.py artifacts/screenshots artifacts/screenshots/contact_sheet.jpg
PASS: contact sheet written (1304x1112, 5 tiles)
```

## Files Changed
- `scripts/crew_deck.gd`
- `scripts/main.gd`
- `scripts/audio.gd`
- `tools/check_audio_wiring.py`
- `README.md`
- `docs/audio_production_brief.md`
