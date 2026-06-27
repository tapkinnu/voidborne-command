#!/usr/bin/env python3
"""check_audio_wiring.py — static check that every audio trigger is wired.

Voidborne Command uses authored OGG/WAV assets (scripts/audio.gd) instead of
procedural synthesis. This checker verifies:

  1. Parse the SOUNDS, MUSIC, and VOICE tables in scripts/audio.gd.
  2. Grep all gameplay scripts for call sites:
       - audio.play("<trigger>") for SFX and voice
       - _play_voice_bark("<trigger>") for voice (wrapper that calls audio.play())
       - audio.play_music("<name>") for music
  3. FAIL if any declared trigger has no call site.
  4. WARN if any call references an undeclared trigger.

Exit 0 only when every declared trigger has at least one call site.

Usage: python3 tools/check_audio_wiring.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
AUDIO_GD = os.path.join(SCRIPTS, "audio.gd")

# Triggers that legitimately have no in-game call site yet.
ALLOW_UNUSED: set[str] = set()


def _parse_dict(text: str, dict_name: str) -> list[str]:
    """Extract string keys from a GDScript const Dictionary = {...}."""
    pattern = re.compile(
        rf"const\s+{re.escape(dict_name)}\s*:\s*Dictionary\s*=\s*\{{(.*?)\n\}}",
        re.S,
    )
    m = pattern.search(text)
    if not m:
        return []
    body = m.group(1)
    keys = re.findall(r'"([a-z0-9_]+)"\s*:', body)
    return keys


def declared_triggers() -> dict[str, list[str]]:
    """Return {"sfx": [...], "music": [...], "voice": [...]}."""
    if not os.path.exists(AUDIO_GD):
        print(f"FAIL: {AUDIO_GD} not found")
        sys.exit(1)
    with open(AUDIO_GD, encoding="utf-8") as f:
        text = f.read()
    return {
        "sfx": _parse_dict(text, "SOUNDS"),
        "music": _parse_dict(text, "MUSIC"),
        "voice": _parse_dict(text, "VOICE"),
    }


def _find_calls(pattern: re.Pattern) -> dict[str, list[str]]:
    """Return trigger -> list of files containing the call."""
    found: dict[str, list[str]] = {}
    for name in os.listdir(SCRIPTS):
        if not name.endswith(".gd") or name == "audio.gd":
            continue
        path = os.path.join(SCRIPTS, name)
        with open(path, encoding="utf-8") as f:
            for trig in pattern.findall(f.read()):
                found.setdefault(trig, []).append(name)
    return found


def play_calls() -> dict[str, list[str]]:
    """SFX/voice play() calls."""
    return _find_calls(re.compile(r'\.play\(\s*"([a-z0-9_]+)"'))


def voice_bark_calls() -> dict[str, list[str]]:
    """Voice _play_voice_bark() wrapper calls."""
    return _find_calls(re.compile(r'_play_voice_bark\(\s*"([a-z0-9_]+)"'))


def music_calls() -> dict[str, list[str]]:
    """Music play_music() calls."""
    return _find_calls(re.compile(r'\.play_music\(\s*"([a-z0-9_]+)"'))


def _check_category(
    declared: list[str],
    calls: dict[str, list[str]],
    category: str,
    call_fmt: str,
) -> bool:
    ok = True
    print(f"\n{category} triggers ({len(declared)}): {', '.join(declared) if declared else '(none)'}")
    for trig in declared:
        sites = calls.get(trig, [])
        if sites:
            print(f"  OK   {trig:30s} <- {call_fmt} in {', '.join(sorted(set(sites)))}")
        elif trig in ALLOW_UNUSED:
            print(f"  SKIP {trig:30s} (allow-listed, no call site)")
        else:
            print(f"  FAIL {trig:30s} declared but never called")
            ok = False
    # Warn on calls to undeclared triggers (only against this category's declared set)
    undeclared = sorted(set(calls.keys()) - set(declared))
    for trig in undeclared:
        print(f"  WARN {call_fmt}(\"{trig}\") has no entry (in {', '.join(sorted(set(calls[trig])))})")
    return ok


def main() -> int:
    tables = declared_triggers()
    sfx_calls = play_calls()
    music_call_sites = music_calls()
    voice_direct = play_calls()
    voice_bark = voice_bark_calls()

    # Merge voice call sites: both direct audio.play("voice_trigger") and
    # _play_voice_bark("voice_trigger") count as wired.
    voice_calls: dict[str, list[str]] = {}
    for trig, files in voice_direct.items():
        if trig in tables["voice"]:
            voice_calls.setdefault(trig, []).extend(files)
    for trig, files in voice_bark.items():
        voice_calls.setdefault(trig, []).extend(files)

    ok = True
    ok &= _check_category(tables["sfx"], sfx_calls, "SFX", "play()")
    ok &= _check_category(tables["music"], music_call_sites, "MUSIC", "play_music()")
    ok &= _check_category(tables["voice"], voice_calls, "VOICE", "play()/_play_voice_bark()")

    print()
    if not ok:
        print("FAIL: one or more declared audio triggers are not wired to gameplay.")
        return 1
    total = len(tables["sfx"]) + len(tables["music"]) + len(tables["voice"])
    print(f"PASS: all {total} audio triggers are wired to gameplay call sites.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
