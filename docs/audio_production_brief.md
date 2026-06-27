# Voidborne Command — Audio Asset Production Brief

## Project Context
- **Game**: Voidborne Command — Godot 4.4.1 3D space-sim vertical slice
- **Current State**: All audio is procedural (runtime-synthesized 16-bit PCM WAV). 21 SFX triggers exist.
- **Goal**: Replace procedural SFX with authored audio assets (sound effects, ambient, music, voice lines).
- **Technical Constraint**: Godot 4.4.1, OGG Vorbis preferred for music/ambient, WAV for short SFX (or OGG). No FMOD — native Godot AudioStreamPlayer/AudioStreamPlayer3D only.
- **Asset Path**: `assets/audio/` (to be created)

## Tone & Style (from Creative Bible)
- Cold, clean, hopeful-under-pressure. Not grimdark.
- The win fantasy is *command*, not carnage.
- Audio should reinforce competence and tension, not horror.

## Asset Categories

### 1. Combat SFX (replace procedural triggers)
| Trigger | Current Procedural | Desired Real Asset | Notes |
|---------|-------------------|-------------------|-------|
| `laser` | Saw wave 880→220 Hz, 0.14s | Sci-fi projectile/cannon fire | Short, punchy, layered |
| `beam` | Square wave 140→180 Hz, 0.40s | Sustained beam weapon hum/buzz | Continuous fire sound |
| `hit` | Square wave 320→90 Hz, 0.12s | Hull impact / metallic thud | Physical, weighty |
| `shield` | Sine wave 600→900 Hz, 0.16s | Energy shield absorption/bloom | Clean, electronic |
| `explosion` | Noise 200→40 Hz, 0.55s | Ship explosion | Deep, rumbling, debris |
| `disabled` | Saw wave 440→110 Hz, 0.30s | Subsystem failure / ship disabled | Warning tone, descending |
| `subsystem_hit` | Square wave 520→140 Hz, 0.18s | Targeted subsystem damage | Sharp, specific |
| `engine_hit` | Noise 200→80 Hz, 0.15s | Engine damage rattle | Mechanical, distressed |
| `weapon_overheat` | Saw wave 300→150 Hz, 0.30s | Low energy / overheat click | Dry, mechanical click |
| `hull_alarm` | Square wave 880→440 Hz, 0.40s | Low hull warning klaxon | Urgent, repeating-capable |
| `mining_hit` | Noise 180→120 Hz, 0.10s | Asteroid impact chip | Rocky, brittle |
| `asteroid_break` | Noise 140→50 Hz, 0.40s | Asteroid destruction | Crumbling, satisfying |

### 2. Boarding SFX
| Trigger | Desired Asset |
|---------|--------------|
| `board` | Breach/airlock opening, marine deployment |
| `boarding_round` | Brief firefight/impact exchange (0.5s rounds) |
| `boarding_fail` | Mission failure tone, retreat/defeat |
| `capture` | Victory/faction-switch fanfare (rising major interval feel) |

### 3. UI SFX
| Trigger | Desired Asset |
|---------|--------------|
| `ui_recruit` | Positive confirmation (crew hired, success) |
| `ui_buy` | Transaction/purchase chime |
| `ui_deny` | Error/denied buzzer |

### 4. Ambient & Environment
| Trigger | Desired Asset |
|---------|--------------|
| `ambient` | Space drone/background hum (looping, ~4s+ seamless) |
| `thruster` | Engine thrust noise (player ship, looped or one-shot) |

### 5. Music (NEW — no current trigger)
- **Combat music**: Dynamic layer for active combat (hostiles present, weapons firing)
- **Exploration music**: Calm ambient layer for travel/mining/system map
- **Station/dock music**: Neutral, industrial, commercial feel
- **Victory stinger**: Short (3-5s) on successful capture/boarding
- **Defeat stinger**: Short (3-5s) on player destruction/game over

Music should be **loopable OGG** files, 44.1kHz, stereo.

### 6. Voice Lines (NEW — no current trigger)
- **Commander announcements**: 5-10 short barked lines (e.g., "Target disabled", "Boarding party away", "Capture confirmed", "Hull critical", "Jump complete")
- **Marine barks**: 3-5 short combat shouts for boarding rounds
- **Station announcer**: 3-5 dock/trade announcements (e.g., "Docking clearance granted", "Shipyard open")
- Style: Competent, military-but-not-grim, slightly synthetic/cold. Could be AI-generated TTS with a filter, or synthesized.
- Format: Short WAV or OGG, mono, 22.05kHz or 44.1kHz.

## Godot Audio Bus Layout (proposed)
```
Master
├── Music (ducked -6dB during combat)
├── SFX
│   ├── Weapons (laser, beam, hit, explosion)
│   ├── UI (ui_recruit, ui_buy, ui_deny)
│   ├── Voice (commander, marine, station)
│   └── Ambient (space drone, thrusters)
```

## Integration Notes
- The existing `audio.gd` script uses a voice pool of 10 `AudioStreamPlayer` nodes on the `Master` bus.
- New assets should be loaded as `AudioStream` resources (preload or load at runtime).
- The `play(trigger, pitch)` API should be preserved; real assets can ignore pitch or use Godot's `pitch_scale`.
- Ambient should remain on its dedicated player (currently `_ambient_player`).
- Music should use a new `AudioStreamPlayer` with `bus = "Music"`.
- Voice lines should use a separate player or sub-pool with `bus = "Voice"`.

## Acceptance Criteria
- All 21 existing SFX triggers have authored replacements.
- At least 3 music tracks (combat, exploration, station) are produced and loop cleanly.
- At least 10 voice lines are produced and wired to gameplay events.
- Audio assets are placed in `assets/audio/` with subfolders: `sfx/`, `music/`, `voice/`.
- `project.godot` is updated with the new audio bus layout.
- `audio.gd` is updated to load real assets instead of synthesizing.
- `check_audio_wiring.py` still passes (all triggers wired).
- `validate_build.sh` passes headlessly (audio assets load without error under `--audio-driver Dummy`).

## Deliverables
1. `assets/audio/sfx/*.ogg` or `*.wav` — all SFX triggers
2. `assets/audio/music/*.ogg` — loopable music tracks
3. `assets/audio/voice/*.ogg` or `*.wav` — voice lines
4. Updated `scripts/audio.gd` with real asset loading
5. Updated `project.godot` with audio bus layout
6. Updated `docs/audio_design.md` documenting the asset list and bus layout
