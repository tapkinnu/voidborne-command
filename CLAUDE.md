# Project: Voidborne Command

Build a new original Godot 4.4.1 3D space simulator under this repository.

## Runtime/tooling
- Godot binary: `/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64`
- Renderer for capture: `--rendering-driver vulkan` under `xvfb-run` (fallback opengl3 only if Vulkan fails).
- Use GDScript and code-built/procedural 3D assets. Do not require the editor.
- Keep `.godot/`, `.import`, `__pycache__/`, and build artifacts out of git.

## Required first playable vertical slice
Create a working, playable 3D space-sim prototype that visibly supports the user's requested systems:

1. **Fly own ship**
   - Player controls a ship in 3D space with throttle, boost/brake, yaw/pitch/roll, target cycling, weapons, hull/shields/energy.
   - Third-person camera and readable HUD.

2. **Crew and marines**
   - Player can recruit crew members and marines at a station.
   - Include a ship-interior/crew-deck interaction mode or an equivalent in-game interaction view where procedural humanoid crew/marines are visible.
   - Player can interact with individual crew/marines and order them to follow the captain/player.

3. **Disable, board, and capture ships/stations**
   - Hostile ships/stations can be disabled (not only destroyed).
   - Boarding with marines has a visible boarding progress / combat resolution.
   - Captured ships/stations switch faction and become owned by the player.

4. **Buy and command other ships**
   - Player can buy other ships at stations.
   - Purchased/captured ships need crew assigned to be considered manned.
   - Manned ships follow the player in fleet formation.

5. **Ship classes**
   - Include fighters, corvettes, frigates, and capital ships with distinct stats, silhouette scale, turrets/greebles, and behavior.

6. **Combat space battle**
   - Include hostile wing, at least one larger hostile ship, a station, beams/projectiles/explosions, radar/target lock/objective HUD.

7. **Docs and gates**
   - `README.md` with controls and scope.
   - `docs/GDD.md`.
   - `docs/studio/00_master_brief.md`, `01_creative_bible.md`, `02_qa_gates.md`, `03_technical_architecture.md`, `definition_of_done.md`.
   - `tools/validate_build.sh` that imports and smoke-runs the project, failing on `SCRIPT ERROR`, `Parse Error`, or `Invalid call`.
   - `tools/capture_screenshots.sh` that writes current screenshots to `artifacts/screenshots/` using Xvfb, plus a contact sheet if practical.
   - `tools/make_contact_sheet.py` and `tools/check_audio_wiring.py` (can be lightweight but must actually check referenced procedural/audio trigger wiring where possible).

## Acceptance commands to run before finishing
Run these from `/home/ganomix/projects/voidborne-command`:

```bash
./tools/validate_build.sh
./tools/capture_screenshots.sh
python3 tools/make_contact_sheet.py artifacts/screenshots artifacts/screenshots/contact_sheet.jpg
python3 tools/check_audio_wiring.py
```

The screenshot must not be black and must show a space battle, player/fleet/target/station, and HUD. Record exact command outputs in `.studio/claude_foundation.log` or your final report.

## Implementation constraints
- Prefer a small set of robust scripts over many fragile hand-written TSCN files.
- Avoid `class_name` circular import problems. Prefer one or a few scripts attached via TSCN ext_resource.
- GDScript: use explicit types for values from dictionaries and JSON; avoid `:=` when return type is Variant.
- If building the entire requested game is too large for one pass, still ship a working vertical slice that proves each requested mechanic in simplified form, and document the next production tasks.
- Do not fabricate verification; if a command fails, fix it or report the exact blocker.
