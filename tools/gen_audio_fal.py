#!/usr/bin/env python3.12
"""
FAL Audio Generation Script for Voidborne Command
Generates all 30 audio assets using fal.ai endpoints:
- SFX: fal-ai/stable-audio (Open)
- Music: fal-ai/stable-audio-25/text-to-audio
- Voice: fal-ai/elevenlabs/tts/turbo-v2.5
"""

import os
import sys
import json
import time
import requests
import numpy as np
import soundfile as sf
from pathlib import Path

# Config
FAL_KEY = os.environ.get("FAL_KEY", "")
if not FAL_KEY:
    print("ERROR: FAL_KEY not set")
    sys.exit(1)

BASE_DIR = Path("/home/ganomix/projects/voidborne-command/.worktrees/t_08774a2f/assets/audio")
SOURCES_PATH = Path("/home/ganomix/projects/voidborne-command/.worktrees/t_08774a2f/docs/SOURCES.md")

# ─── FAL API helpers ────────────────────────────────────────────────────────

def fal_submit_and_wait(endpoint: str, input_data: dict, max_wait: int = 300) -> dict:
    """Submit a job to FAL queue and poll for result."""
    base_url = "https://queue.fal.run"
    url = f"{base_url}/{endpoint}"
    headers = {
        "Authorization": f"Key {FAL_KEY}",
        "Content-Type": "application/json",
    }
    
    # Submit
    resp = requests.post(url, json=input_data, headers=headers, timeout=60)
    if resp.status_code != 200:
        raise Exception(f"FAL submit failed [{resp.status_code}]: {resp.text[:500]}")
    
    result = resp.json()
    request_id = result.get("request_id")
    
    if not request_id:
        # Direct result
        return result
    
    # Poll for status (correct URL needs /status suffix)
    status_url = f"{base_url}/{endpoint}/requests/{request_id}/status"
    for i in range(max_wait // 10):
        time.sleep(10)
        status_resp = requests.get(status_url, headers=headers, timeout=30)
        if status_resp.status_code not in (200, 202):
            print(f"  poll {i}: got {status_resp.status_code}, retrying...")
            continue
        status_data = status_resp.json()
        status = status_data.get("status", "")
        if status == "COMPLETED":
            # Fetch result from response_url
            result_url = status_data.get("response_url", f"{base_url}/{endpoint}/requests/{request_id}")
            result_resp = requests.get(result_url, headers=headers, timeout=30)
            return result_resp.json()
        elif status == "FAILED":
            raise Exception(f"FAL job failed: {status_data.get('logs', '')[:500]}")
    
    raise Exception(f"FAL job timed out after {max_wait}s")


def download_audio(url: str) -> tuple[np.ndarray, int]:
    """Download audio from URL, return (data, sample_rate)."""
    resp = requests.get(url, timeout=60)
    if resp.status_code != 200:
        raise Exception(f"Download failed [{resp.status_code}]: url={url}")
    
    # Write to temp file and read with soundfile
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(resp.content)
        tmp_path = tmp.name
    
    try:
        data, rate = sf.read(tmp_path)
    finally:
        os.unlink(tmp_path)
    return data, rate


# ─── Post-processing ─────────────────────────────────────────────────────────

def post_process_sfx(data: np.ndarray, rate: int, target_peak: float = 0.85,
                     lead_ms: float = 50, tail_ms: float = 150) -> np.ndarray:
    """Post-process SFX: fold to mono, trim silence, normalize."""
    # Fold to mono if stereo
    if len(data.shape) > 1 and data.shape[1] > 1:
        data = data.mean(axis=1)
    
    # Trim silence (below 2% of peak)
    peak = np.max(np.abs(data))
    if peak > 0:
        threshold = peak * 0.02
        mask = np.abs(data) >= threshold
        first_nonzero = np.argmax(mask)
        last_nonzero = len(mask) - np.argmax(mask[::-1]) - 1
        
        # Add lead-in and tail
        lead_samples = int(rate * lead_ms / 1000)
        tail_samples = int(rate * tail_ms / 1000)
        
        start = max(0, first_nonzero - lead_samples)
        end = min(len(data), last_nonzero + 1 + tail_samples)
        data = data[start:end]
    
    # Peak normalize
    peak = np.max(np.abs(data))
    if peak > 0:
        data = data / peak * target_peak
    
    return data


def post_process_music(data: np.ndarray, rate: int, target_peak: float = 0.6) -> np.ndarray:
    """Post-process music: keep stereo, normalize."""
    peak = np.max(np.abs(data))
    if peak > 0:
        data = data / peak * target_peak
    return data


# ─── Asset definitions ───────────────────────────────────────────────────────

SFX_ASSETS = [
    ("sfx/laser.ogg", "Sci-fi energy cannon fire, short punchy laser blast, cold clean military, 1 second", 2),
    ("sfx/beam.ogg", "Sustained sci-fi beam weapon hum, energy weapon buzz, continuous fire, cold clean", 2),
    ("sfx/hit.ogg", "Metallic hull impact thud, spaceship armor hit, physical weighty, debris rattle", 2),
    ("sfx/shield.ogg", "Energy shield absorption bloom, clean electronic force field, sci-fi defensive", 2),
    ("sfx/explosion.ogg", "Deep spaceship explosion, rumbling sub-bass, debris shockwave, cinematic", 3),
    ("sfx/disabled.ogg", "Subsystem failure warning tone, descending electronic alarm, ship disabled", 2),
    ("sfx/subsystem_hit.ogg", "Sharp targeted subsystem damage, electronic component failure, precise", 2),
    ("sfx/engine_hit.ogg", "Engine damage rattle, mechanical distress, metal grinding, spaceship engine", 2),
    ("sfx/weapon_overheat.ogg", "Dry mechanical overheat click, weapon system failure, short metallic", 2),
    ("sfx/hull_alarm.ogg", "Urgent low hull warning klaxon, repeating-capable alarm, military sci-fi", 2),
    ("sfx/mining_hit.ogg", "Asteroid mining impact chip, rocky brittle debris, short crunch", 2),
    ("sfx/asteroid_break.ogg", "Asteroid destruction crumble, satisfying rock fragmentation, space mining", 3),
    ("sfx/board.ogg", "Airlock breach opening, marine deployment, pressurized hatch release", 2),
    ("sfx/boarding_round.ogg", "Brief firefight impact exchange, short combat burst, boarding action", 2),
    ("sfx/boarding_fail.ogg", "Mission failure retreat tone, defeat alarm, descending military", 2),
    ("sfx/capture.ogg", "Victory faction-switch fanfare, rising major interval, triumphant short", 2),
    ("sfx/ui_recruit.ogg", "Positive UI confirmation chime, crew hired success, clean electronic", 1),
    ("sfx/ui_buy.ogg", "Transaction purchase chime, commercial sci-fi, clean electronic", 1),
    ("sfx/ui_deny.ogg", "Error denied buzzer, UI rejection, short electronic negative", 1),
    ("sfx/thruster.ogg", "Engine thrust noise, spaceship main drive, low rumble, one-shot", 2),
    ("sfx/ambient.ogg", "Space drone background hum, deep ambient void, seamless looping, 5 seconds", 5),
]

MUSIC_ASSETS = [
    ("music/combat.ogg", "Driving aggressive electronic combat music, pounding percussion, dark synth bass, 90 BPM, D minor, instrumental, sci-fi space battle", 60),
    ("music/exploration.ogg", "Calm ambient sci-fi exploration music, ethereal pads, distant signals, 90 BPM, D minor, instrumental, space travel", 60),
    ("music/station.ogg", "Neutral industrial station music, commercial dock feel, mechanical rhythm, 90 BPM, D minor, instrumental, space station", 60),
]

VOICE_ASSETS = [
    ("voice/commander_battle_stations.ogg", "Battle stations. All hands to combat readiness.", "Competent military commander, slightly synthetic, cold clean, male"),
    ("voice/commander_engage.ogg", "Engaging hostiles. Weapons free.", "Same commander voice"),
    ("voice/marine_contact.ogg", "Contact! Boarding party inbound!", "Marine grunt, energetic, slightly synthetic, male"),
    ("voice/marine_affirmative.ogg", "Affirmative. Moving to position.", "Same marine voice"),
    ("voice/announcer_docking.ogg", "Docking clearance granted. Welcome to the station.", "Station announcer, neutral professional, slightly synthetic, female"),
    ("voice/announcer_welcome.ogg", "Welcome aboard, Commander. Shipyard services are available.", "Same announcer voice"),
]


# ─── Main generation ─────────────────────────────────────────────────────────

def generate_sfx(name: str, prompt: str, seconds: int) -> dict:
    """Generate a SFX asset using fal-ai/stable-audio"""
    endpoint = "fal-ai/stable-audio"
    input_data = {
        "prompt": prompt,
        "seconds_total": seconds,
    }
    result = fal_submit_and_wait(endpoint, input_data, max_wait=120)
    
    # Extract audio URL
    audio_url = None
    if "audio_file" in result:
        audio_url = result["audio_file"].get("url") if isinstance(result["audio_file"], dict) else result["audio_file"]
    elif "audio" in result:
        audio_url = result["audio"].get("url") if isinstance(result["audio"], dict) else result["audio"]
    
    if not audio_url:
        raise Exception(f"No audio URL in result: {json.dumps(result)[:300]}")
    
    data, rate = download_audio(audio_url)
    data = post_process_sfx(data, rate)
    
    output_path = BASE_DIR / name
    sf.write(output_path, data, rate, format="OGG", subtype="VORBIS")
    
    return {"endpoint": endpoint, "prompt": prompt, "seconds_total": seconds,
            "output": str(output_path), "samples": len(data), "rate": rate}


def generate_music(name: str, prompt: str, seconds: int) -> dict:
    """Generate a music asset using fal-ai/stable-audio-25/text-to-audio"""
    endpoint = "fal-ai/stable-audio-25/text-to-audio"
    input_data = {
        "prompt": prompt,
        "seconds_total": seconds,
    }
    result = fal_submit_and_wait(endpoint, input_data, max_wait=300)
    
    # Extract audio URL
    audio_url = None
    if "audio" in result:
        audio_url = result["audio"].get("url") if isinstance(result["audio"], dict) else result["audio"]
    elif "audio_file" in result:
        audio_url = result["audio_file"].get("url") if isinstance(result["audio_file"], dict) else result["audio_file"]
    
    if not audio_url:
        raise Exception(f"No audio URL in result: {json.dumps(result)[:300]}")
    
    data, rate = download_audio(audio_url)
    data = post_process_music(data, rate)
    
    output_path = BASE_DIR / name
    sf.write(output_path, data, rate, format="OGG", subtype="VORBIS")
    
    return {"endpoint": endpoint, "prompt": prompt, "seconds_total": seconds,
            "output": str(output_path), "samples": len(data), "rate": rate}


def generate_voice(name: str, text: str, voice_style: str) -> dict:
    """Generate a voice line using fal-ai/elevenlabs/tts/turbo-v2.5"""
    endpoint = "fal-ai/elevenlabs/tts/turbo-v2.5"
    input_data = {
        "text": text,
        "voice_style": voice_style,
    }
    result = fal_submit_and_wait(endpoint, input_data, max_wait=120)
    
    # Extract audio URL
    audio_url = None
    if "audio" in result:
        audio_url = result["audio"].get("url") if isinstance(result["audio"], dict) else result["audio"]
    elif "audio_file" in result:
        audio_url = result["audio_file"].get("url") if isinstance(result["audio_file"], dict) else result["audio_file"]
    
    if not audio_url:
        raise Exception(f"No audio URL in result: {json.dumps(result)[:300]}")
    
    data, rate = download_audio(audio_url)
    # Voice: fold to mono, normalize
    if len(data.shape) > 1 and data.shape[1] > 1:
        data = data.mean(axis=1)
    peak = np.max(np.abs(data))
    if peak > 0:
        data = data / peak * 0.85
    
    output_path = BASE_DIR / name
    sf.write(output_path, data, rate, format="OGG", subtype="VORBIS")
    
    return {"endpoint": endpoint, "text": text, "voice_style": voice_style,
            "output": str(output_path), "samples": len(data), "rate": rate}


def write_sources_md(records: list):
    """Write docs/SOURCES.md with provenance for all assets."""
    lines = ["# Voidborne Command — Audio Asset Provenance\n",
             "All assets generated via fal.ai. Endpoint, prompt, and output path for each.\n"]
    
    lines.append("## SFX (fal-ai/stable-audio)\n")
    for r in records:
        if "seconds_total" in r:
            lines.append(f"- `{r['output']}`")
            lines.append(f"  - Endpoint: `{r['endpoint']}`")
            lines.append(f"  - Prompt: {r['prompt']}")
            lines.append(f"  - Duration: {r['seconds_total']}s")
            lines.append("")
    
    lines.append("## Music (fal-ai/stable-audio-25/text-to-audio)\n")
    for r in records:
        if r["endpoint"] == "fal-ai/stable-audio-25/text-to-audio":
            lines.append(f"- `{r['output']}`")
            lines.append(f"  - Endpoint: `{r['endpoint']}`")
            lines.append(f"  - Prompt: {r['prompt']}")
            lines.append(f"  - Duration: {r['seconds_total']}s")
            lines.append("")
    
    lines.append("## Voice (fal-ai/elevenlabs/tts/turbo-v2.5)\n")
    for r in records:
        if r["endpoint"] == "fal-ai/elevenlabs/tts/turbo-v2.5":
            lines.append(f"- `{r['output']}`")
            lines.append(f"  - Endpoint: `{r['endpoint']}`")
            lines.append(f"  - Text: {r['text']}")
            lines.append(f"  - Voice style: {r['voice_style']}")
            lines.append("")
    
    SOURCES_PATH.parent.mkdir(parents=True, exist_ok=True)
    SOURCES_PATH.write_text("\n".join(lines))
    print(f"\nWrote {SOURCES_PATH}")


def main():
    print(f"FAL Audio Generation — Voidborne Command")
    print(f"Generating 30 assets (21 SFX + 3 music + 6 voice)\n")
    
    records = []
    errors = []
    start_time = time.time()
    
    # Generate SFX
    for i, (name, prompt, seconds) in enumerate(SFX_ASSETS):
        print(f"[{i+1}/21] SFX: {name} ({seconds}s)...", flush=True)
        try:
            record = generate_sfx(name, prompt, seconds)
            records.append(record)
            print(f"  OK — {record['samples']} samples @ {record['rate']}Hz")
        except Exception as e:
            print(f"  FAIL — {e}")
            errors.append((name, str(e)))
    
    # Generate Music
    for i, (name, prompt, seconds) in enumerate(MUSIC_ASSETS):
        print(f"[{i+1}/3] Music: {name} ({seconds}s)...", flush=True)
        try:
            record = generate_music(name, prompt, seconds)
            records.append(record)
            print(f"  OK — {record['samples']} samples @ {record['rate']}Hz")
        except Exception as e:
            print(f"  FAIL — {e}")
            errors.append((name, str(e)))
    
    # Generate Voice
    for i, (name, text, voice_style) in enumerate(VOICE_ASSETS):
        print(f"[{i+1}/6] Voice: {name}...", flush=True)
        try:
            record = generate_voice(name, text, voice_style)
            records.append(record)
            print(f"  OK — {record['samples']} samples @ {record['rate']}Hz")
        except Exception as e:
            print(f"  FAIL — {e}")
            errors.append((name, str(e)))
    
    elapsed = time.time() - start_time
    
    # Write SOURCES.md
    write_sources_md(records)
    
    # Summary
    print(f"\n{'='*60}")
    print(f"Done in {elapsed:.0f}s")
    print(f"Success: {len(records)}/30")
    if errors:
        print(f"FAILED ({len(errors)}):")
        for name, err in errors:
            print(f"  - {name}: {err[:100]}")
    
    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
