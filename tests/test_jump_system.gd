extends SceneTree
# Regression test for the multi-system / inter-system jump layer.
# Verifies: multiple star systems exist, jumping switches the active system,
# the battle rebuilds with new stations/hostiles, and save/load round-trips
# the current system index.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

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

	# --- 1. Multiple star systems defined ------------------------------------
	var system_count: int = int(main.get("system_count"))
	if system_count < 2:
		_fail("expected at least 2 star systems, found %d" % system_count)

	# --- 2. current_system_index starts at 0 ----------------------------------
	var start_idx: int = int(main.get("current_system_index"))
	if start_idx != 0:
		_fail("current_system_index should start at 0, got %d" % start_idx)

	# --- 3. Jump to next system changes the index -----------------------------
	if not failed:
		var prev_idx: int = int(main.get("current_system_index"))
		# Record ship count before jump
		var ships_before: int = 0
		for s in main.ships:
			if is_instance_valid(s):
				ships_before += 1
		main.call("jump_to_system", prev_idx + 1)
		await process_frame
		await process_frame
		var new_idx: int = int(main.get("current_system_index"))
		if new_idx == prev_idx:
			_fail("current_system_index did not change after jump")
		# After a jump, the ships array should be rebuilt with new entities.
		var ships_after: int = 0
		for s in main.ships:
			if is_instance_valid(s):
				ships_after += 1
		if ships_after == 0:
			_fail("no ships exist after jump")
		# Player should still exist.
		var has_player: bool = false
		for s in main.ships:
			if is_instance_valid(s) and bool(s.get("is_player")):
				has_player = true
		if not has_player:
			_fail("player ship missing after jump")

	# --- 4. System names are distinct and non-empty ---------------------------
	if not failed:
		var names: Array = []
		for i in range(system_count):
			names.append(main.call("system_name", i))
		for n in names:
			if String(n) == "":
				_fail("system name is empty")
		# At least 2 distinct names
		var unique: Dictionary = {}
		for n in names:
			unique[n] = true
		if unique.size() < 2:
			_fail("system names are not distinct")

	# --- 5. Save/load round-trips current_system_index -----------------------
	if not failed:
		main.set("save_path", "user://test_jump_save.json")
		main.call("jump_to_system", 0)
		await process_frame
		main.call("_quick_save")
		main.call("jump_to_system", 1)
		await process_frame
		var idx_before_load: int = int(main.get("current_system_index"))
		main.call("_quick_load")
		await process_frame
		var idx_after_load: int = int(main.get("current_system_index"))
		if idx_after_load == idx_before_load:
			_fail("save/load did not restore system index (still at %d)" % idx_after_load)
		# Clean up test save
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_jump_save.json"))

	# --- 6. System map shows jump gates --------------------------------------
	if not failed:
		main.call("force_system_map", true)
		await process_frame
		main.call("_update_hud")
		var hud_node: Node = main.get("hud")
		var hud_data: Dictionary = hud_node.get("data")
		var map_data: Dictionary = hud_data.get("system_map", {})
		var gates: Array = map_data.get("jump_gates", [])
		if gates.size() == 0:
			_fail("system map does not show jump gates")
		var sys_label: String = String(map_data.get("current_system", ""))
		if sys_label == "":
			_fail("system map does not show current system name")
		main.call("force_system_map", false)

	if not failed:
		print("JUMP_SYSTEM_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)