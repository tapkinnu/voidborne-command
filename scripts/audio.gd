extends Node
# Audio: loads real OGG/WAV asset files from assets/audio/ and plays them
# through a small voice pool. main.gd calls play("<trigger>") for gameplay
# events. tools/check_audio_wiring.py statically verifies that every trigger
# below has a corresponding play("<trigger>") call in scripts.
# No class_name (instantiated by main.gd; avoids circular imports).

const ASSET_PREFIX: String = "res://assets/audio/"

# Trigger table. Each entry maps a trigger name to an asset file path.
# All 21 triggers match the original procedural SOUNDS table — same names,
# same play(trigger, pitch) call sites in main.gd.
const SOUNDS: Dictionary = {
	"laser":            ASSET_PREFIX + "sfx/laser.ogg",
	"beam":             ASSET_PREFIX + "sfx/beam.ogg",
	"hit":              ASSET_PREFIX + "sfx/hit.ogg",
	"shield":           ASSET_PREFIX + "sfx/shield.ogg",
	"explosion":        ASSET_PREFIX + "sfx/explosion.ogg",
	"disabled":         ASSET_PREFIX + "sfx/disabled.ogg",
	"subsystem_hit":    ASSET_PREFIX + "sfx/subsystem_hit.ogg",
	"board":            ASSET_PREFIX + "sfx/board.ogg",
	"boarding_round":   ASSET_PREFIX + "sfx/boarding_round.ogg",
	"boarding_fail":    ASSET_PREFIX + "sfx/boarding_fail.ogg",
	"capture":          ASSET_PREFIX + "sfx/capture.ogg",
	"ui_recruit":       ASSET_PREFIX + "sfx/ui_recruit.ogg",
	"ui_buy":           ASSET_PREFIX + "sfx/ui_buy.ogg",
	"ui_deny":          ASSET_PREFIX + "sfx/ui_deny.ogg",
	"thruster":         ASSET_PREFIX + "sfx/thruster.ogg",
	"ambient":          ASSET_PREFIX + "sfx/ambient.ogg",
	"weapon_overheat":  ASSET_PREFIX + "sfx/weapon_overheat.ogg",
	"hull_alarm":       ASSET_PREFIX + "sfx/hull_alarm.ogg",
	"engine_hit":       ASSET_PREFIX + "sfx/engine_hit.ogg",
	"mining_hit":       ASSET_PREFIX + "sfx/mining_hit.ogg",
	"asteroid_break":   ASSET_PREFIX + "sfx/asteroid_break.ogg",
}

# Music tracks (looped on a dedicated player).
const MUSIC: Dictionary = {
	"combat":      ASSET_PREFIX + "music/combat.ogg",
	"exploration": ASSET_PREFIX + "music/exploration.ogg",
	"station":     ASSET_PREFIX + "music/station.ogg",
}

# Voice barks (one-shot, played on the SFX voice pool).
const VOICE: Dictionary = {
	"commander_battle_stations": ASSET_PREFIX + "voice/commander_battle_stations.ogg",
	"commander_engage":          ASSET_PREFIX + "voice/commander_engage.ogg",
	"marine_contact":            ASSET_PREFIX + "voice/marine_contact.ogg",
	"marine_affirmative":        ASSET_PREFIX + "voice/marine_affirmative.ogg",
	"announcer_docking":         ASSET_PREFIX + "voice/announcer_docking.ogg",
	"announcer_welcome":         ASSET_PREFIX + "voice/announcer_welcome.ogg",
}

var _streams: Dictionary = {}      # trigger -> AudioStream (OGG/WAV file)
var _voice_streams: Dictionary = {} # voice trigger -> AudioStream
var _music_streams: Dictionary = {} # music name -> AudioStream
var _voices: Array = []            # pool of AudioStreamPlayer (one-shot SFX)
var _voice_idx: int = 0
var _ambient_player: AudioStreamPlayer = null   # dedicated looping ambient
var _music_player: AudioStreamPlayer = null      # dedicated music player
var enabled: bool = true

# True when there is no real audio output device: either the headless display driver
# (the GDScript test harness uses --headless) or the Dummy audio driver (the smoke run
# and screenshot capture pass --audio-driver Dummy under a real display driver). In both
# cases actually starting playbacks only creates AudioServer playback objects that never
# finish (the ambient drone loops), which surface as leaked AudioStreamWAV/
# AudioStreamPlaybackWAV instances at exit. Real gameplay has a live device, so audio
# plays normally there.
func _audio_unavailable() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	# The Dummy audio driver reports zero output latency (no real ring buffer). A live
	# device always reports a positive latency, so this distinguishes the capture/smoke
	# runs (which never have a working output device) from real gameplay.
	if AudioServer.get_output_latency() <= 0.0:
		return true
	return false

func _ready() -> void:
	if _audio_unavailable():
		enabled = false
	# Pre-load all SFX streams so first-play does not stutter.
	for key in SOUNDS.keys():
		var path: String = SOUNDS[key]
		var stream: AudioStream = load(path)
		if stream == null:
			push_warning("audio.gd: failed to load SFX asset: %s" % path)
			continue
		_streams[key] = stream
	# Pre-load voice streams.
	for key in VOICE.keys():
		var path: String = VOICE[key]
		var stream: AudioStream = load(path)
		if stream == null:
			push_warning("audio.gd: failed to load voice asset: %s" % path)
			continue
		_voice_streams[key] = stream
	# Pre-load music streams.
	for key in MUSIC.keys():
		var path: String = MUSIC[key]
		var stream: AudioStream = load(path)
		if stream == null:
			push_warning("audio.gd: failed to load music asset: %s" % path)
			continue
		_loop_stream(stream)
		_music_streams[key] = stream
	# Voice pool for one-shot SFX.
	for i in range(10):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	# Dedicated ambient drone player (looping).
	var amb_stream: AudioStream = _streams.get("ambient")
	if amb_stream != null:
		_loop_stream(amb_stream)
		_ambient_player = AudioStreamPlayer.new()
		_ambient_player.bus = "Ambient"
		_ambient_player.stream = amb_stream
		add_child(_ambient_player)
	# Dedicated music player.
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

func _loop_stream(stream: AudioStream) -> void:
	# Set looping on AudioStreamWAV or AudioStreamOggVorbis as appropriate.
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		if stream.data != null:
			stream.loop_end = stream.data.size() / 2
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
		stream.loop_offset = 0.0

# Public trigger: play a named SFX. main.gd routes every gameplay event through here.
# The "ambient" trigger is special-cased onto the dedicated looping player rather than the
# one-shot voice pool, so the background drone never steals a voice from gameplay SFX.
func play(trigger: String, pitch: float = 1.0) -> void:
	if not enabled:
		return
	if trigger == "ambient":
		start_ambient()
		return
	if _streams.has(trigger):
		var p: AudioStreamPlayer = _voices[_voice_idx]
		_voice_idx = (_voice_idx + 1) % _voices.size()
		p.stream = _streams[trigger]
		p.pitch_scale = clamp(pitch, 0.5, 2.0)
		p.play()
	elif _voice_streams.has(trigger):
		var p: AudioStreamPlayer = _voices[_voice_idx]
		_voice_idx = (_voice_idx + 1) % _voices.size()
		p.stream = _voice_streams[trigger]
		p.bus = "Voice"
		p.pitch_scale = clamp(pitch, 0.5, 2.0)
		p.play()
		p.bus = "SFX"

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

# Play a music track by name. Stops any currently playing music first.
func play_music(name: String) -> void:
	if not enabled or _music_player == null:
		return
	if not _music_streams.has(name):
		return
	_music_player.stop()
	_music_player.stream = _music_streams[name]
	_music_player.play()

# Stop the current music track.
func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()

# Check if a voice trigger exists in the voice table.
func has_voice(trigger: String) -> bool:
	return _voice_streams.has(trigger)

# Set the music volume (0..1 linear).
func set_music_volume(vol: float) -> void:
	if _music_player == null:
		return
	_music_player.volume_db = linear_to_db(clamp(vol, 0.0001, 1.0))

# Stop the ambient drone and every voice player (cleanup / quit).
func stop_all() -> void:
	if _ambient_player != null:
		_ambient_player.stop()
	if _music_player != null:
		_music_player.stop()
	for p in _voices:
		if p != null:
			p.stop()

# Full teardown on tree exit: stop every voice, detach streams so the
# AudioServer releases its playbacks, and drop our stream references.
func _exit_tree() -> void:
	stop_all()
	for p in _voices:
		if is_instance_valid(p):
			p.stream = null
	if is_instance_valid(_ambient_player):
		_ambient_player.stream = null
	if is_instance_valid(_music_player):
		_music_player.stream = null
	_streams.clear()
	_voice_streams.clear()
	_music_streams.clear()
