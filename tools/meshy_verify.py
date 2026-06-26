#!/usr/bin/env python3
"""
tools/meshy_verify.py — verify the 5 repacked Meshy GLBs are Godot-importable
and meet the size/triangle/texture/bone budget.

For each *.repacked.glb under assets/models/meshy_visual_upgrade/, runs
Godot in headless mode (-s tools/meshy_verify.gd) and parses the
`MESHY_VERIFY <id> ...` lines emitted by the GDScript inspector.

Exits 0 iff every asset reports OK and MESHY_VERIFY_OVERALL=OK.
Exits 1 otherwise. Prints a tabular summary.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = os.environ.get(
    "GODOT_BIN",
    "/home/ganomix/tools/godot/Godot_v4.4.1-stable_linux.x86_64",
)
ASSETS_DIR = ROOT / "assets" / "meshy_visual_upgrade" if False else ROOT / "assets" / "models" / "meshy_visual_upgrade"
VERIFY_GD = ROOT / "tools" / "meshy_verify.gd"

LINE_RE = re.compile(
    r"MESHY_VERIFY\s+(\S+)\s+kind=(\S+)\s+triangles=(\d+)\s+textures=(\d+)\s+aabb=(.+?)\s+"
    r"(?:bones=(\d+)\s+)?status=(\S+)"
)
OVERALL_RE = re.compile(r"MESHY_VERIFY_OVERALL=(\S+)")


def main() -> int:
    if not ASSETS_DIR.exists():
        print(f"FAIL: assets dir missing: {ASSETS_DIR}")
        return 1
    if not VERIFY_GD.exists():
        print(f"FAIL: verify script missing: {VERIFY_GD}")
        return 1
    if not Path(GODOT).exists():
        print(f"FAIL: Godot binary missing: {GODOT}")
        return 1

    cmd = [
        GODOT,
        "--headless",
        "--path", str(ROOT),
        "-s", str(VERIFY_GD.relative_to(ROOT)),
    ]
    print(f"running: {' '.join(cmd)}")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180, cwd=str(ROOT))
    except subprocess.TimeoutExpired:
        print("FAIL: Godot headless verify timed out after 180s")
        return 1

    out = proc.stdout + "\n" + proc.stderr
    rows = []
    overall = None
    for line in out.splitlines():
        m = LINE_RE.search(line)
        if m:
            rows.append({
                "asset": m.group(1),
                "kind": m.group(2),
                "triangles": int(m.group(3)),
                "textures": int(m.group(4)),
                "aabb": m.group(5).strip(),
                "bones": int(m.group(6)) if m.group(6) else None,
                "status": m.group(7),
            })
            continue
        m = OVERALL_RE.search(line)
        if m:
            overall = m.group(1)

    # Tabular summary
    if rows:
        print()
        print("asset             kind     triangles  textures  bones  status   glb")
        for r in rows:
            glb_path = ASSETS_DIR / f"{r['asset']}.repacked.glb"
            size_kb = glb_path.stat().st_size / 1024 if glb_path.exists() else 0.0
            bones = r["bones"] if r["bones"] is not None else "-"
            print(
                f"{r['asset']:<17}{r['kind']:<8}{r['triangles']:>10}  {r['textures']:>8}  "
                f"{bones:>5}  {r['status']:<7}  {r['asset']}.repacked.glb {size_kb:.0f}KB"
            )
        print()

    if overall == "OK" and all(r["status"] == "OK" for r in rows):
        print(f"VOIDBORNE_MESHY_VERIFY: PASS  ({len(rows)} assets)")
        return 0
    print(f"VOIDBORNE_MESHY_VERIFY: FAIL  overall={overall} rows={len(rows)}")
    print("--- godot output (last 40 lines) ---")
    for line in out.splitlines()[-40:]:
        print(line)
    return 1


if __name__ == "__main__":
    sys.exit(main())