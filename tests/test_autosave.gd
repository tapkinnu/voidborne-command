extends SceneTree
# Regression test for the non-destructive autosave system.
# It drives main.gd's autosave API directly (no key simulation) and asserts:
#   - _do_autosave() writes the autosave slot and round-trips via _load_autosave()
#   - the autosave slot never touches the manual save slot (save_path)
#   - auto_demo (capture/screenshot mode) suppresses autosaves
#   - the periodic timer fires once it crosses AUTOSAVE_INTERVAL in _process()

var failed: bool = false

const AUTOSAVE_SCRATCH: String = "user://test_voidborne_autosave.json"
const SAVE_SCRATCH: String = "user://test_voidborne_save.json"

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var audio_node: Node = main.get("audio")
	if audio_node != null:
		audio_node.set("enabled", false)

	var game: Node = root.get_node_or_null("Game")
	if game == null:
		_fail("Game autoload missing in test tree")
		_finish(main)
		return

	# Redirect both slots to scratch files and start clean.
	main.set("save_path", SAVE_SCRATCH)
	main.set("autosave_path", AUTOSAVE_SCRATCH)
	main.set("auto_demo", false)
	_remove(AUTOSAVE_SCRATCH)
	_remove(SAVE_SCRATCH)

	# --- _do_autosave writes the autosave slot -----------------------------
	if not failed:
		game.set("credits", 4242)
		var ok: bool = bool(main.call("_do_autosave"))
		if not ok:
			_fail("_do_autosave returned false")
		if not FileAccess.file_exists(AUTOSAVE_SCRATCH):
			_fail("autosave file was not written")

	# --- Autosave file is valid JSON with the right game_id ----------------
	if not failed:
		var f: FileAccess = FileAccess.open(AUTOSAVE_SCRATCH, FileAccess.READ)
		if f == null:
			_fail("could not reopen autosave file")
		else:
			var text: String = f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) != TYPE_DICTIONARY:
				_fail("autosave is not a JSON object")
			else:
				var d: Dictionary = parsed
				if String(d.get("game_id", "")) != "voidborne_command":
					_fail("autosave game_id wrong (%s)" % String(d.get("game_id", "")))

	# --- The manual save slot was NOT written by _do_autosave --------------
	if not failed:
		if FileAccess.file_exists(SAVE_SCRATCH):
			_fail("_do_autosave wrote the manual save slot")

	# --- _load_autosave round-trips a distinctive economy state ------------
	if not failed:
		game.set("credits", 13579)
		var saved: bool = bool(main.call("_do_autosave"))
		if not saved:
			_fail("_do_autosave returned false on second save")
		# Mutate away from the snapshot.
		game.set("credits", 1)
		var loaded: bool = bool(main.call("_load_autosave"))
		if not loaded:
			_fail("_load_autosave returned false on a valid autosave")
		if int(game.get("credits")) != 13579:
			_fail("credits did not round-trip via autosave (%d)" % int(game.get("credits")))

	# --- auto_demo suppresses autosave -------------------------------------
	if not failed:
		_remove(AUTOSAVE_SCRATCH)
		main.set("auto_demo", true)
		var demo_ok: bool = bool(main.call("_do_autosave"))
		if demo_ok:
			_fail("_do_autosave returned true in auto_demo mode")
		if FileAccess.file_exists(AUTOSAVE_SCRATCH):
			_fail("_do_autosave wrote a file in auto_demo mode")
		main.set("auto_demo", false)

	# --- Periodic timer fires when it crosses AUTOSAVE_INTERVAL ------------
	if not failed:
		_remove(AUTOSAVE_SCRATCH)
		# AUTOSAVE_INTERVAL is a const (60.0); consts are not reachable via Node.get().
		var interval: float = 60.0
		main.set("auto_demo", false)
		main.set("_autosave_timer", interval - 0.05)
		# One _process frame with a delta that pushes the accumulator over the interval.
		main.call("_process", 0.1)
		await process_frame
		if not FileAccess.file_exists(AUTOSAVE_SCRATCH):
			_fail("periodic timer did not trigger an autosave")
		if float(main.get("_autosave_timer")) >= interval:
			_fail("autosave timer was not reset after firing")

	# Cleanup scratch files.
	_remove(AUTOSAVE_SCRATCH)
	_remove(SAVE_SCRATCH)

	if not failed:
		print("AUTOSAVE_TEST_PASS")
	_finish(main)

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	quit(1 if failed else 0)
