#!/usr/bin/env python3.12
"""
Debug test for music and voice endpoints.
"""
import os, json, requests, time

# Get FAL key from environment or read it
FAL_KEY = os.environ.get("FAL_KEY", "")
if not FAL_KEY:
    with open(os.path.expanduser("~/.hermes/profiles/coder/.env")) as f:
        for line in f:
            if line.startswith("FAL_KEY="):
                FAL_KEY = line.strip().split("=", 1)[1]
                break

print(f"FAL_KEY: {FAL_KEY[:6]}...")
base_url = "https://queue.fal.run"

def submit_and_wait(endpoint, input_data, max_wait=300):
    """Submit and poll for result."""
    url = f"{base_url}/{endpoint}"
    headers = {"Authorization": f"Key {FAL_KEY}", "Content-Type": "application/json"}
    
    resp = requests.post(url, json=input_data, headers=headers, timeout=60)
    result = resp.json()
    request_id = result.get("request_id")
    print(f"  Submitted: {request_id}")
    
    status_url = f"{base_url}/{endpoint}/requests/{request_id}/status"
    
    for i in range(max_wait // 10):
        time.sleep(10)
        sr = requests.get(status_url, headers=headers, timeout=30)
        if sr.status_code != 200:
            print(f"  poll {i}: HTTP {sr.status_code}")
            continue
        sd = sr.json()
        status = sd.get("status", "")
        print(f"  [{i+1}] {status}")
        if status == "COMPLETED":
            result_url = sd.get("response_url")
            rr = requests.get(result_url, headers=headers, timeout=30)
            return rr.json()
        elif status == "FAILED":
            print(f"  FAILED: {sd}")
            return None
    return None

# Test music
print("\n--- Music Test ---")
result = submit_and_wait("fal-ai/stable-audio-25/text-to-audio", {
    "prompt": "Driving aggressive electronic combat music",
    "seconds_total": 60
})
if result:
    audio = result.get("audio", {})
    print(f"  Audio URL: {audio.get('url', 'none')}")
    # Download
    dl = requests.get(audio["url"], timeout=120)
    print(f"  Downloaded: {len(dl.content)} bytes")
    with open("/tmp/test_music.wav", "wb") as f:
        f.write(dl.content)
    print("  Saved to /tmp/test_music.wav")

# Test voice
print("\n--- Voice Test ---")
result = submit_and_wait("fal-ai/elevenlabs/tts/turbo-v2.5", {
    "text": "Battle stations. All hands to combat readiness.",
    "voice_style": "Competent military commander, slightly synthetic, cold clean, male"
})
if result:
    audio = result.get("audio", {})
    print(f"  Audio URL: {audio.get('url', 'none')}")
    dl = requests.get(audio["url"], timeout=60)
    print(f"  Downloaded: {len(dl.content)} bytes")
    with open("/tmp/test_voice.wav", "wb") as f:
        f.write(dl.content)
    print("  Saved to /tmp/test_voice.wav")

print("\nDone!")
