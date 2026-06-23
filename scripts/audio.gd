extends Node
# Audio: procedural SFX synthesizer. Builds short 16-bit PCM AudioStreamWAV tones at
# runtime (no asset files) and plays them through a small voice pool. main.gd calls
# play("<trigger>") for gameplay events. tools/check_audio_wiring.py statically verifies
# that every SOUNDS trigger below has a corresponding play("<trigger>") call in scripts.
# No class_name (instantiated by main.gd; avoids circular imports).

const MIX_RATE: int = 22050

# Trigger table. Each entry fully describes a procedural waveform.
#   freq0/freq1  : start/end frequency sweep (Hz)
#   dur          : seconds
#   wave         : "sine" | "square" | "saw" | "noise"
#   vol          : 0..1 amplitude
const SOUNDS: Dictionary = {
	"laser":     {"freq0": 880.0, "freq1": 220.0, "dur": 0.14, "wave": "saw",    "vol": 0.35},
	"beam":      {"freq0": 140.0, "freq1": 180.0, "dur": 0.40, "wave": "square", "vol": 0.30},
	"hit":       {"freq0": 320.0, "freq1": 90.0,  "dur": 0.12, "wave": "square", "vol": 0.40},
	"shield":    {"freq0": 600.0, "freq1": 900.0, "dur": 0.16, "wave": "sine",   "vol": 0.30},
	"explosion": {"freq0": 200.0, "freq1": 40.0,  "dur": 0.55, "wave": "noise",  "vol": 0.55},
	"disabled":  {"freq0": 440.0, "freq1": 110.0, "dur": 0.30, "wave": "saw",    "vol": 0.40},
	"subsystem_hit": {"freq0": 520.0, "freq1": 140.0, "dur": 0.18, "wave": "square", "vol": 0.42},
	"board":     {"freq0": 330.0, "freq1": 660.0, "dur": 0.25, "wave": "square", "vol": 0.35},
	"capture":   {"freq0": 440.0, "freq1": 880.0, "dur": 0.45, "wave": "sine",   "vol": 0.45},
	"ui_recruit":{"freq0": 520.0, "freq1": 780.0, "dur": 0.12, "wave": "sine",   "vol": 0.30},
	"ui_buy":    {"freq0": 660.0, "freq1": 990.0, "dur": 0.18, "wave": "sine",   "vol": 0.35},
	"ui_deny":   {"freq0": 220.0, "freq1": 160.0, "dur": 0.16, "wave": "square", "vol": 0.30},
	"thruster":  {"freq0": 70.0,  "freq1": 70.0,  "dur": 0.30, "wave": "noise",  "vol": 0.18},
}

var _streams: Dictionary = {}      # trigger -> AudioStreamWAV
var _voices: Array = []            # pool of AudioStreamPlayer
var _voice_idx: int = 0
var enabled: bool = true

func _ready() -> void:
	for key in SOUNDS.keys():
		_streams[key] = _build_stream(SOUNDS[key])
	for i in range(10):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_voices.append(p)

func _build_stream(spec: Dictionary) -> AudioStreamWAV:
	var dur: float = float(spec.get("dur", 0.2))
	var wave: String = String(spec.get("wave", "sine"))
	var f0: float = float(spec.get("freq0", 440.0))
	var f1: float = float(spec.get("freq1", 440.0))
	var vol: float = float(spec.get("vol", 0.3))
	var n: int = int(MIX_RATE * dur)
	var data: PackedByteArray = PackedByteArray()
	data.resize(n * 2)
	var phase: float = 0.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(f0 * 1000.0) + int(dur * 100.0)
	for i in range(n):
		var t: float = float(i) / float(n)
		var freq: float = lerp(f0, f1, t)
		phase += freq / float(MIX_RATE)
		var ph: float = fmod(phase, 1.0)
		var s: float = 0.0
		match wave:
			"sine":
				s = sin(ph * TAU)
			"square":
				s = 1.0 if ph < 0.5 else -1.0
			"saw":
				s = ph * 2.0 - 1.0
			"noise":
				s = rng.randf_range(-1.0, 1.0)
			_:
				s = sin(ph * TAU)
		# Attack/decay envelope so tones do not click.
		var env: float = 1.0
		if t < 0.05:
			env = t / 0.05
		elif t > 0.7:
			env = (1.0 - t) / 0.3
		var sample: int = int(clamp(s * env * vol, -1.0, 1.0) * 32767.0)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav

# Public trigger: play a named SFX. main.gd routes every gameplay event through here.
func play(trigger: String, pitch: float = 1.0) -> void:
	if not enabled:
		return
	if not _streams.has(trigger):
		return
	var p: AudioStreamPlayer = _voices[_voice_idx]
	_voice_idx = (_voice_idx + 1) % _voices.size()
	p.stream = _streams[trigger]
	p.pitch_scale = clamp(pitch, 0.5, 2.0)
	p.play()
