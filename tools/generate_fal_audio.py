#!/usr/bin/env python3
"""Generate all 30 Voidborne Command audio assets via FAL endpoints + post-process.
Run with: python3 -u tools/generate_fal_audio.py
"""

import os
import sys
import time
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import soundfile as sf

# ── Config ──────────────────────────────────────────────────────────────
FAL_KEY = os.environ.get("FAL_KEY", "")
if not FAL_KEY:
    env_path = Path.home() / ".hermes/profiles/coder/.env"
    for line in env_path.read_text().splitlines():
        if line.startswith("FAL_KEY="):
            FAL_KEY = line.split("=", 1)[1].strip()
            break
if not FAL_KEY:
    print("ERROR: FAL_KEY not found", flush=True)
    sys.exit(1)
os.environ["FAL_KEY"] = FAL_KEY

import fal_client

REPO = Path("/home/ganomix/projects/voidborne-command/.worktrees/t_08774a2f")
AUDIO_DIR = REPO / "assets/audio"
SOURCES_PATH = REPO / "docs/SOURCES.md"

# ── Asset definitions ───────────────────────────────────────────────────
SFX_ASSETS = [
    ("sfx/laser.ogg",           "Sci-fi energy cannon fire, short punchy laser blast, cold clean military, 1 second", 2),
    ("sfx/beam.ogg",            "Sustained sci-fi beam weapon hum, energy weapon buzz, continuous fire, cold clean", 2),
    ("sfx/hit.ogg",             "Metallic hull impact thud, spaceship armor hit, physical weighty, debris rattle", 2),
    ("sfx/shield.ogg",          "Energy shield absorption bloom, clean electronic force field, sci-fi defensive", 2),
    ("sfx/explosion.ogg",      "Deep spaceship explosion, rumbling sub-bass, debris shockwave, cinematic", 3),
    ("sfx/disabled.ogg",       "Subsystem failure warning tone, descending electronic alarm, ship disabled", 2),
    ("sfx/subsystem_hit.ogg",  "Sharp targeted subsystem damage, electronic component failure, precise", 2),
    ("sfx/engine_hit.ogg",     "Engine damage rattle, mechanical distress, metal grinding, spaceship engine", 2),
    ("sfx/weapon_overheat.ogg","Dry mechanical overheat click, weapon system failure, short metallic", 2),
    ("sfx/hull_alarm.ogg",     "Urgent low hull warning klaxon, repeating-capable alarm, military sci-fi", 2),
    ("sfx/mining_hit.ogg",     "Asteroid mining impact chip, rocky brittle debris, short crunch", 2),
    ("sfx/asteroid_break.ogg", "Asteroid destruction crumble, satisfying rock fragmentation, space mining", 3),
    ("sfx/board.ogg",          "Airlock breach opening, marine deployment, pressurized hatch release", 2),
    ("sfx/boarding_round.ogg", "Brief firefight impact exchange, short combat burst, boarding action", 2),
    ("sfx/boarding_fail.ogg",  "Mission failure retreat tone, defeat alarm, descending military", 2),
    ("sfx/capture.ogg",        "Victory faction-switch fanfare, rising major interval, triumphant short", 2),
    ("sfx/ui_recruit.ogg",     "Positive UI confirmation chime, crew hired success, clean electronic", 1),
    ("sfx/ui_buy.ogg",         "Transaction purchase chime, commercial sci-fi, clean electronic", 1),
    ("sfx/ui_deny.ogg",        "Error denied buzzer, UI rejection, short electronic negative", 1),
    ("sfx/thruster.ogg",       "Engine thrust noise, spaceship main drive, low rumble, one-shot", 2),
    ("sfx/ambient.ogg",        "Space drone background hum, deep ambient void, seamless looping, 5 seconds", 5),
]

MUSIC_ASSETS = [
    ("music/combat.ogg",       "Driving aggressive electronic combat music, pounding percussion, dark synth bass, 90 BPM, D minor, instrumental, sci-fi space battle", 60),
    ("music/exploration.ogg",  "Calm ambient sci-fi exploration music, ethereal pads, distant signals, 90 BPM, D minor, instrumental, space travel", 60),
    ("music/station.ogg",     "Neutral industrial station music, commercial dock feel, mechanical rhythm, 90 BPM, D minor, instrumental, space station", 60),
]

VOICE_ASSETS = [
    ("voice/commander_battle_stations.ogg", "Battle stations. All hands to combat readiness.", "pz6K7Jcl0q7g1Twn5B0p", "Marcus - authoritative male commander"),
    ("voice/commander_engage.ogg",          "Engaging hostiles. Weapons free.",                   "pz6K7Jcl0q7g1Twn5B0p", "Marcus - authoritative male commander"),
    ("voice/marine_contact.ogg",            "Contact! Boarding party inbound!",                    "pz6K7Jcl0q7g1Twn5B0p", "Marcus - authoritative male marine"),
    ("voice/marine_affirmative.ogg",        "Affirmative. Moving to position.",                    "pz6K7Jcl0q7g1Twn5B0p", "Marcus - authoritative male marine"),
    ("voice/announcer_docking.ogg",         "Docking clearance granted. Welcome to the station.",  "jsSMF9q1HO2Qzh0HR8hn", "Charlotte - professional female announcer"),
    ("voice/announcer_welcome.ogg",         "Welcome aboard, Commander. Shipyard services are available.", "jsSMF9q1HO2Qzh0HR8hn", "Charlotte - professional female announcer"),
]

# ── FAL API calls ──────────────────────────────────────────────────────

def call_stable_audio(prompt: str, seconds_total: int) -> str:
    result = fal_client.submit("fal-ai/stable-audio", arguments={"prompt": prompt, "seconds_total": seconds_total}).get()
    url = result.get("audio_file", {}).get("url")
    if not url:
        raise RuntimeError(f"stable-audio: no audio_file url in {result}")
    return url

def call_stable_audio_25(prompt: str, seconds_total: int) -> str:
    result = fal_client.submit("fal-ai/stable-audio-25/text-to-audio", arguments={"prompt": prompt, "seconds_total": seconds_total}).get()
    url = result.get("audio", {}).get("url")
    if not url:
        raise RuntimeError(f"stable-audio-25: no audio url in {result}")
    return url

def call_elevenlabs_tts(text: str, voice_id: str) -> str:
    result = fal_client.submit("fal-ai/elevenlabs/tts/turbo-v2.5", arguments={"text": text, "voice_id": voice_id}).get()
    url = result.get("audio", {}).get("url")
    if not url:
        raise RuntimeError(f"elevenlabs: no audio url in {result}")
    return url

def download(url: str) -> str:
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp_path = tmp.name
    tmp.close()
    urllib.request.urlretrieve(url, tmp_path)
    return tmp_path

# ── Post-processing ─────────────────────────────────────────────────────

def postprocess_sfx(wav_path: str, out_ogg: Path):
    data, rate = sf.read(wav_path, dtype="float32")
    if data.ndim > 1:
        data = np.mean(data, axis=1)
    peak = np.max(np.abs(data))
    threshold = peak * 0.02
    above = np.where(np.abs(data) > threshold)[0]
    if len(above) > 0:
        lead = int(0.050 * rate)
        tail = int(0.150 * rate)
        start = max(0, above[0] - lead)
        end = min(len(data), above[-1] + tail + 1)
        data = data[start:end]
    peak = np.max(np.abs(data))
    if peak > 0:
        data = data * (0.85 / peak)
    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(out_ogg), data, rate, format="OGG", subtype="VORBIS")
    print(f"  OK: {out_ogg.name} ({len(data)/rate:.2f}s mono)", flush=True)

def postprocess_music(wav_path: str, out_ogg: Path):
    data, rate = sf.read(wav_path, dtype="float32")
    peak = np.max(np.abs(data))
    if peak > 0:
        data = data * (0.6 / peak)
    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(out_ogg), data, rate, format="OGG", subtype="VORBIS")
    print(f"  OK: {out_ogg.name} ({len(data)/rate:.2f}s stereo)", flush=True)

def postprocess_voice(wav_path: str, out_ogg: Path):
    data, rate = sf.read(wav_path, dtype="float32")
    if data.ndim > 1:
        data = np.mean(data, axis=1)
    peak = np.max(np.abs(data))
    if peak > 0:
        data = data * (0.8 / peak)
    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(out_ogg), data, rate, format="OGG", subtype="VORBIS")
    print(f"  OK: {out_ogg.name} ({len(data)/rate:.2f}s mono)", flush=True)

# ── Worker functions for parallel execution ─────────────────────────────

def gen_sfx(idx, rel_path, prompt, secs):
    """Generate one SFX asset. Returns (rel_path, endpoint, prompt) on success, None on failure."""
    out_ogg = AUDIO_DIR / rel_path
    print(f"[{idx+1}/21 SFX] {rel_path}: \"{prompt[:60]}...\"", flush=True)
    try:
        url = call_stable_audio(prompt, secs)
        wav_tmp = download(url)
        postprocess_sfx(wav_tmp, out_ogg)
        os.unlink(wav_tmp)
        return (rel_path, "fal-ai/stable-audio", prompt)
    except Exception as e:
        print(f"  FAIL: {e}", flush=True)
        return None

def gen_music(idx, rel_path, prompt, secs):
    out_ogg = AUDIO_DIR / rel_path
    print(f"[{idx+1}/3 MUSIC] {rel_path}: \"{prompt[:60]}...\"", flush=True)
    try:
        url = call_stable_audio_25(prompt, secs)
        wav_tmp = download(url)
        postprocess_music(wav_tmp, out_ogg)
        os.unlink(wav_tmp)
        return (rel_path, "fal-ai/stable-audio-25/text-to-audio", prompt)
    except Exception as e:
        print(f"  FAIL: {e}", flush=True)
        return None

def gen_voice(idx, rel_path, text, voice_id, voice_desc):
    out_ogg = AUDIO_DIR / rel_path
    print(f"[{idx+1}/6 VOICE] {rel_path}: \"{text[:40]}...\"", flush=True)
    try:
        url = call_elevenlabs_tts(text, voice_id)
        wav_tmp = download(url)
        postprocess_voice(wav_tmp, out_ogg)
        os.unlink(wav_tmp)
        return (rel_path, "fal-ai/elevenlabs/tts/turbo-v2.5", f'text="{text}", voice={voice_desc}')
    except Exception as e:
        print(f"  FAIL: {e}", flush=True)
        return None

# ── Main ────────────────────────────────────────────────────────────────

def main():
    sources = []

    # ── SFX: batch in groups of 3 ──────────────────────────────────────
    print(f"\n=== SFX: {len(SFX_ASSETS)} assets via fal-ai/stable-audio ===", flush=True)
    batch_size = 3
    for batch_start in range(0, len(SFX_ASSETS), batch_size):
        batch = SFX_ASSETS[batch_start:batch_start + batch_size]
        with ThreadPoolExecutor(max_workers=len(batch)) as ex:
            futures = {ex.submit(gen_sfx, batch_start + i, *args): i for i, args in enumerate(batch)}
            for f in as_completed(futures):
                result = f.result()
                if result:
                    sources.append(("SFX", *result))
        time.sleep(0.5)

    # ── Music: one at a time (each is 60s, heavy) ────────────────────
    print(f"\n=== MUSIC: {len(MUSIC_ASSETS)} assets via fal-ai/stable-audio-25 ===", flush=True)
    for i, (rel_path, prompt, secs) in enumerate(MUSIC_ASSETS):
        result = gen_music(i, rel_path, prompt, secs)
        if result:
            sources.append(("Music", *result))
        time.sleep(1)

    # ── Voice: batch all 6 in parallel ───────────────────────────────
    print(f"\n=== VOICE: {len(VOICE_ASSETS)} assets via fal-ai/elevenlabs/tts ===", flush=True)
    with ThreadPoolExecutor(max_workers=3) as ex:
        futures = {ex.submit(gen_voice, i, *args): i for i, args in enumerate(VOICE_ASSETS)}
        for f in as_completed(futures):
            result = f.result()
            if result:
                sources.append(("Voice", *result))

    # ── Write SOURCES.md ────────────────────────────────────────────
    print(f"\n=== Writing docs/SOURCES.md ===", flush=True)
    SOURCES_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(SOURCES_PATH, "w") as f:
        f.write("# Audio Asset Sources\n\n")
        f.write("Provenance for all 30 audio assets in Voidborne Command.\n")
        f.write("Generated via FAL.ai endpoints and post-processed (mono/normalize/trim → OGG Vorbis).\n\n")
        for cat in ["SFX", "Music", "Voice"]:
            items = [s for s in sources if s[0] == cat]
            if not items:
                continue
            f.write(f"## {cat}\n\n")
            f.write("| File | Endpoint | Prompt |\n")
            f.write("|------|----------|--------|\n")
            for _, rel_path, endpoint, prompt_text in items:
                f.write(f"| `{rel_path}` | `{endpoint}` | {prompt_text} |\n")
            f.write("\n")
    print(f"Wrote {SOURCES_PATH}", flush=True)

    # ── Verify ──────────────────────────────────────────────────────
    print(f"\n=== Verification ===", flush=True)
    all_ogg = list(AUDIO_DIR.glob("sfx/*.ogg")) + list(AUDIO_DIR.glob("music/*.ogg")) + list(AUDIO_DIR.glob("voice/*.ogg"))
    ok = bad = 0
    for ogg in sorted(all_ogg):
        try:
            data, rate = sf.read(str(ogg))
            size = ogg.stat().st_size
            if size > 0 and len(data) > 0:
                ok += 1
            else:
                print(f"  BAD: {ogg} (empty)", flush=True); bad += 1
        except Exception as e:
            print(f"  BAD: {ogg} ({e})", flush=True); bad += 1
    print(f"Result: {ok} OK, {bad} BAD out of {len(all_ogg)}", flush=True)
    if ok >= 30:
        print("SUCCESS!", flush=True)
    else:
        print(f"INCOMPLETE: only {ok}/30 OK", flush=True)

if __name__ == "__main__":
    main()
