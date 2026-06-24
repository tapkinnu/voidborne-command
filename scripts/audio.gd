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
	"boarding_round": {"freq0": 420.0, "freq1": 260.0, "dur": 0.10, "wave": "square", "vol": 0.30},
	"boarding_fail":  {"freq0": 360.0, "freq1": 70.0,  "dur": 0.50, "wave": "saw",    "vol": 0.42},
	"capture":   {"freq0": 440.0, "freq1": 880.0, "dur": 0.45, "wave": "sine",   "vol": 0.45},
	"ui_recruit":{"freq0": 520.0, "freq1": 780.0, "dur": 0.12, "wave": "sine",   "vol": 0.30},
	"ui_buy":    {"freq0": 660.0, "freq1": 990.0, "dur": 0.18, "wave": "sine",   "vol": 0.35},
	"ui_deny":   {"freq0": 220.0, "freq1": 160.0, "dur": 0.16, "wave": "square", "vol": 0.30},
	"thruster":  {"freq0": 70.0,  "freq1": 70.0,  "dur": 0.30, "wave": "noise",  "vol": 0.18},
	"ambient":   {"freq0": 55.0,  "freq1": 55.0,  "dur": 4.00, "wave": "sine",   "vol": 0.08},
	"weapon_overheat": {"freq0": 300.0, "freq1": 150.0, "dur": 0.30, "wave": "saw",    "vol": 0.25},
	"hull_alarm":      {"freq0": 880.0, "freq1": 440.0, "dur": 0.40, "wave": "square", "vol": 0.30},
	"engine_hit":      {"freq0": 200.0, "freq1": 80.0,  "dur": 0.15, "wave": "noise",  "vol": 0.35},
}

var _streams: Dictionary = {}      # trigger -> AudioStreamWAV
var _voices: Array = []            # pool of AudioStreamPlayer (one-shot SFX)
var _voice_idx: int = 0
var _ambient_player: AudioStreamPlayer = null   # dedicated looping drone (never in the voice pool)
var enabled: bool = true

func _ready() -> void:
	for key in SOUNDS.keys():
		_streams[key] = _build_stream(SOUNDS[key])
	for i in range(10):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_voices.append(p)
	# Dedicated ambient drone player, looping its stream so it never re-triggers the voice pool.
	var amb: AudioStreamWAV = _streams["ambient"]
	amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
	amb.loop_begin = 0
	amb.loop_end = amb.data.size() / 2   # loop_end is in sample frames (16-bit mono => 2 bytes/frame)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Master"
	_ambient_player.stream = amb
	add_child(_ambient_player)

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
# The "ambient" trigger is special-cased onto the dedicated looping player rather than the
# one-shot voice pool, so the background drone never steals a voice from gameplay SFX.
func play(trigger: String, pitch: float = 1.0) -> void:
	if not enabled:
		return
	if trigger == "ambient":
		start_ambient()
		return
	if not _streams.has(trigger):
		return
	var p: AudioStreamPlayer = _voices[_voice_idx]
	_voice_idx = (_voice_idx + 1) % _voices.size()
	p.stream = _streams[trigger]
	p.pitch_scale = clamp(pitch, 0.5, 2.0)
	p.play()

# Start (or resume) the looping ambient drone on its dedicated player.
func start_ambient() -> void:
	if not enabled or _ambient_player == null:
		return
	if not _ambient_player.playing:
		_ambient_player.play()

# Set the ambient drone volume (0..1 linear). Independent of the SFX voice pool.
func set_ambient_volume(vol: float) -> void:
	if _ambient_player == null:
		return
	_ambient_player.volume_db = linear_to_db(clamp(vol, 0.0001, 1.0))

# Stop the ambient drone and every voice player (cleanup / quit).
func stop_all() -> void:
	if _ambient_player != null:
		_ambient_player.stop()
	for p in _voices:
		if p != null:
			p.stop()
