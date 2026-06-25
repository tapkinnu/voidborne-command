# 02 — QA Gates

Every gate below must pass before the slice is considered green. Automated gates are
enforced by the scripts in `tools/`; manual gates are verified against captured
screenshots.

## G0 — Build integrity (automated)
- `./tools/validate_build.sh` exits 0.
- Headless **import** completes; **smoke run** completes.
- Engine output contains **no** `SCRIPT ERROR`, `Parse Error`, or `Invalid call`.
- Full log archived at `artifacts/validate.log`.

## G1 — Capture pipeline (automated)
- `./tools/capture_screenshots.sh` exits 0 and writes ≥1 PNG to `artifacts/screenshots/`.
- Vulkan is attempted first; opengl3 fallback only if Vulkan yields no frames.
- The in-engine `Capture` autoload quits itself; the shell timeout is only a safety net.

## G2 — Not-black / contact sheet (automated)
- `make_contact_sheet.py` exits 0 and writes `contact_sheet.jpg`.
- The run **fails** if *every* frame's mean luma < 8/255 (i.e. all black).
- Per-image luma is printed for the record.

## G3 — Audio wiring (automated)
- `check_audio_wiring.py` exits 0.
- Every trigger declared in `audio.gd::SOUNDS` has at least one `play("<trigger>")` call
  site in gameplay scripts. Undeclared `play()` calls are reported as warnings.

## G4 — Visible mechanics (manual, vs screenshots)
A reviewer confirms the captured frames collectively show:
- [ ] Space battle: player ship + station + other ships on screen.
- [ ] HUD: economy/fleet panel, objective, target panel, player bars, radar with blips,
      reticle, message log.
- [ ] Target lock: a selected target reflected in the target panel and radar ring.
- [ ] Crew deck: procedural humanoid captain + crew + marines in the interior view.
- [ ] Fleet / weapons FX: projectiles, beams, or explosions present across the set.

## G5 — Mechanic correctness (manual, in-engine)
Run the build interactively and confirm:
- [ ] Throttle/boost/brake and yaw/pitch/roll all respond; camera chases.
- [ ] `Tab` cycles targets; firing damages shields then hull.
- [ ] A hostile reaching ≤22% hull reads **DISABLED**; `B` within range fills a boarding
      bar; on completion the target re-tints to player and (crew permitting) joins the fleet.
- [ ] Near the station, `R`/`M`/`Y` adjust credits/pools/fleet; `I` assigns a reserve
      marine to a player-owned prize garrison; `F` mans unmanned ships, then toggles manned
      fleet orders between follow/hold/escort/defend/dock/attack/patrol/guard-station.
- [ ] `C` enters the deck; walking up to a crew member and pressing `F` toggles follow.

## Regression watch-list
- Setting `global_position` / `look_at` before `add_child` (must add to tree first).
- HUD must use the viewport rect, not `Control.size`, or the bottom HUD vanishes.
- Capture must be re-entry-safe so the final shot is not lost to an async race.
