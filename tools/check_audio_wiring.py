#!/usr/bin/env python3
"""check_audio_wiring.py — static check that every procedural SFX trigger is wired.

Voidborne Command uses a procedural synthesizer (scripts/audio.gd) instead of audio
asset files. This checker is therefore a *real* static analysis, not a no-op:

  1. Parse the SOUNDS table in scripts/audio.gd to learn the declared trigger names.
  2. Grep all gameplay scripts for `audio.play("<trigger>")` call sites.
  3. FAIL if any declared trigger is never played (dead sound), and WARN if any
     play() call references a trigger that is not declared (typo / missing sound).

Exit 0 only when every declared trigger has at least one play() call site.

Usage: python3 tools/check_audio_wiring.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
AUDIO_GD = os.path.join(SCRIPTS, "audio.gd")

# Triggers that legitimately have no in-game call site yet (none for this slice).
ALLOW_UNUSED: set[str] = set()


def declared_triggers() -> list[str]:
    if not os.path.exists(AUDIO_GD):
        print(f"FAIL: {AUDIO_GD} not found")
        sys.exit(1)
    with open(AUDIO_GD, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"const\s+SOUNDS\s*:\s*Dictionary\s*=\s*\{(.*?)\n\}", text, re.S)
    if not m:
        print("FAIL: could not locate SOUNDS table in audio.gd")
        sys.exit(1)
    body = m.group(1)
    keys = re.findall(r'"([a-z0-9_]+)"\s*:', body)
    return keys


def play_calls() -> dict[str, list[str]]:
    """Return trigger -> list of files containing audio.play("trigger")."""
    found: dict[str, list[str]] = {}
    pattern = re.compile(r'\.play\(\s*"([a-z0-9_]+)"')
    for name in os.listdir(SCRIPTS):
        if not name.endswith(".gd") or name == "audio.gd":
            continue
        path = os.path.join(SCRIPTS, name)
        with open(path, encoding="utf-8") as f:
            for trig in pattern.findall(f.read()):
                found.setdefault(trig, []).append(name)
    return found


def main() -> int:
    declared = declared_triggers()
    calls = play_calls()
    print(f"Declared triggers ({len(declared)}): {', '.join(declared)}")
    print()

    ok = True
    for trig in declared:
        sites = calls.get(trig, [])
        if sites:
            print(f"  OK   {trig:12s} <- play() in {', '.join(sorted(set(sites)))}")
        elif trig in ALLOW_UNUSED:
            print(f"  SKIP {trig:12s} (allow-listed, no call site)")
        else:
            print(f"  FAIL {trig:12s} declared but never played")
            ok = False

    # Warn on calls to undeclared triggers (typos / missing sounds).
    undeclared = sorted(set(calls.keys()) - set(declared))
    for trig in undeclared:
        print(f"  WARN play(\"{trig}\") has no SOUNDS entry (in {', '.join(sorted(set(calls[trig])))})")

    print()
    if not ok:
        print("FAIL: one or more declared SFX triggers are not wired to gameplay.")
        return 1
    print(f"PASS: all {len(declared)} SFX triggers are wired to gameplay call sites.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
