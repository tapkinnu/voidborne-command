extends Node
# Capture: screenshot autoload. Inactive unless VOIDBORNE_CAPTURE names an output dir.
# When active it lets the live battle run for a few seconds, grabs the rendered viewport
# at several beats (space, dogfight, crew deck), writes PNGs, then quits. A shell timeout
# in tools/capture_screenshots.sh is the safety net — we do NOT rely on tiny --quit-after.
# No class_name (autoload).

var out_dir: String = ""
var shots: Array = []          # [{at: seconds, name: String, deck: bool}]
var _t: float = 0.0
var _idx: int = 0
var _saved: int = 0
var _busy: bool = false
var _done: bool = false

func _ready() -> void:
	out_dir = OS.get_environment("VOIDBORNE_CAPTURE")
	if out_dir == "":
		set_process(false)
		return
	shots = [
		{"at": 2.0, "name": "01_space_battle", "deck": false},
		{"at": 3.6, "name": "02_dogfight", "deck": false},
		{"at": 5.2, "name": "03_target_lock", "deck": false},
		{"at": 6.6, "name": "04_crew_deck", "deck": true},
		{"at": 8.0, "name": "05_fleet", "deck": false},
	]
	print("[capture] active, out_dir=", out_dir)

func _process(delta: float) -> void:
	_t += delta
	if _busy or _done:
		return
	if _idx >= shots.size():
		_done = true
		print("[capture] done, saved ", _saved, " screenshots; quitting.")
		get_tree().quit(0)
		return
	var shot: Dictionary = shots[_idx]
	if _t >= float(shot["at"]):
		_busy = true
		await _take(shot)
		_idx += 1
		_busy = false

func _take(shot: Dictionary) -> void:
	var main: Node = get_tree().current_scene
	if main and main.has_method("force_deck"):
		main.force_deck(bool(shot["deck"]))
	# Let the requested view render before grabbing.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = out_dir.path_join(String(shot["name"]) + ".png")
	var err: int = img.save_png(path)
	if err == OK:
		_saved += 1
		print("[capture] saved ", path)
	else:
		printerr("[capture] FAILED to save ", path, " err=", err)
