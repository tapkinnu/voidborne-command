extends SceneTree
# Regression test for the multi-slot named-save system. No key simulation: it drives
# main.gd's slot API directly (save_to_slot/load_from_slot/delete_slot/get_slot_meta) in a
# scratch directory, asserting slot files round-trip, the meta sidecar is consistent and
# self-healing, the manual quick-save slot is never touched, and the F5 menu freezes flight.

var failed: bool = false

const SCRATCH_DIR: String = "user://test_saves/"
const SCRATCH_SAVE: String = "user://test_voidborne_manual.json"

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _scratch_path(rel: String) -> String:
	return ProjectSettings.globalize_path(SCRATCH_DIR.path_join(rel))

func _clean_scratch() -> void:
	var dir: DirAccess = DirAccess.open(ProjectSettings.globalize_path(SCRATCH_DIR))
	if dir != null:
		dir.list_dir_begin()
		var fn: String = dir.get_next()
		while fn != "":
			if not dir.current_is_dir():
				dir.remove(fn)
			fn = dir.get_next()
		dir.list_dir_end()
	if FileAccess.file_exists(SCRATCH_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))

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

	# Redirect the slot dir and manual save path to scratch, starting clean.
	main.set("save_slot_dir", SCRATCH_DIR)
	main.set("save_path", SCRATCH_SAVE)
	_clean_scratch()

	# --- 1. save_to_slot writes a valid file -------------------------------
	game.set("credits", 4242)
	var ok1: bool = bool(main.call("save_to_slot", 1, "Alpha"))
	if not ok1:
		_fail("save_to_slot(1) returned false")
	var slot1_path: String = String(main.call("slot_path", 1))
	if not FileAccess.file_exists(slot1_path):
		_fail("slot 1 file not written at %s" % slot1_path)
	if not failed:
		var f: FileAccess = FileAccess.open(slot1_path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			_fail("slot 1 file is not valid JSON object")
		elif String((parsed as Dictionary).get("game_id", "")) != "voidborne_command":
			_fail("slot 1 file has wrong game_id")

	# --- 2. slot_exists ----------------------------------------------------
	if not failed:
		if not bool(main.call("slot_exists", 1)):
			_fail("slot_exists(1) should be true")
		if bool(main.call("slot_exists", 2)):
			_fail("slot_exists(2) should be false")

	# --- 3. get_slot_meta --------------------------------------------------
	if not failed:
		var metas: Array = main.call("get_slot_meta")
		if metas.size() != 6:
			_fail("get_slot_meta did not return 6 entries (%d)" % metas.size())
		else:
			var e0: Dictionary = metas[0]
			if not bool(e0.get("exists", false)):
				_fail("meta entry 0 should exist")
			if String(e0.get("name", "")) != "Alpha":
				_fail("meta entry 0 name wrong (%s)" % String(e0.get("name", "")))
			if int(e0.get("credits", -1)) != int(game.get("credits")):
				_fail("meta entry 0 credits mismatch")
			if int(e0.get("index", -1)) != 1:
				_fail("meta entry 0 index wrong")

	# --- 4. load_from_slot round-trips -------------------------------------
	if not failed:
		game.set("credits", 999)
		var okl: bool = bool(main.call("load_from_slot", 1))
		if not okl:
			_fail("load_from_slot(1) returned false")
		if int(game.get("credits")) != 4242:
			_fail("load_from_slot did not restore credits (%d)" % int(game.get("credits")))

	# --- 5. load_from_slot on empty slot fails -----------------------------
	if not failed:
		game.set("credits", 7777)
		var okEmpty: bool = bool(main.call("load_from_slot", 2))
		if okEmpty:
			_fail("load_from_slot(2) on empty slot returned true")
		if int(game.get("credits")) != 7777:
			_fail("failed empty load clobbered live state")

	# --- 6. delete_slot ----------------------------------------------------
	if not failed:
		var okd: bool = bool(main.call("delete_slot", 1))
		if not okd:
			_fail("delete_slot(1) returned false")
		if bool(main.call("slot_exists", 1)):
			_fail("slot 1 still exists after delete")
		var metas2: Array = main.call("get_slot_meta")
		if bool((metas2[0] as Dictionary).get("exists", true)):
			_fail("meta entry 0 still marked exists after delete")

	# --- 7. invalid slot index --------------------------------------------
	if not failed:
		if bool(main.call("save_to_slot", 0, "bad")):
			_fail("save_to_slot(0) should fail")
		if bool(main.call("save_to_slot", 99, "bad")):
			_fail("save_to_slot(99) should fail")
		if bool(main.call("load_from_slot", 0)):
			_fail("load_from_slot(0) should fail")

	# --- 8. slot save does not touch the manual save_path ------------------
	if not failed:
		if FileAccess.file_exists(SCRATCH_SAVE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))
		var okg: bool = bool(main.call("save_to_slot", 3, "Gamma"))
		if not okg:
			_fail("save_to_slot(3) returned false")
		if FileAccess.file_exists(SCRATCH_SAVE):
			_fail("slot save wrote the manual save_path file")

	# --- 9. save_menu_open freezes flight ----------------------------------
	if not failed:
		var player: Node3D = main.get("player")
		if player == null:
			_fail("player missing for freeze test")
		else:
			var before: Vector3 = player.global_position
			main.set("save_menu_open", true)
			main.call("_process_space", 0.016)
			var after: Vector3 = player.global_position
			if before.distance_to(after) > 0.0001:
				_fail("save_menu_open did not freeze flight (moved %s)" % str(after - before))
			main.set("save_menu_open", false)

	# --- 10. get_slot_meta rebuilds from corrupt meta ----------------------
	if not failed:
		var meta_path: String = SCRATCH_DIR.path_join("slots_meta.json")
		var cf: FileAccess = FileAccess.open(meta_path, FileAccess.WRITE)
		if cf != null:
			cf.store_string("{ this is not valid array json ]")
			cf.close()
		var metas3: Array = main.call("get_slot_meta")
		if metas3.size() != 6:
			_fail("get_slot_meta did not rebuild 6 entries from corrupt meta (%d)" % metas3.size())
		else:
			# Slot 3 (Gamma) was saved above; rebuild should still detect it exists.
			if not bool((metas3[2] as Dictionary).get("exists", false)):
				_fail("rebuilt meta lost slot 3 existence")

	_clean_scratch()
	if not failed:
		print("SAVE_SLOTS_TEST_PASS")
	_finish(main)

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	quit(1 if failed else 0)
