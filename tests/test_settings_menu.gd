extends SceneTree
# Regression test for the interactive settings menu (resolution, volume, graphics) and the
# pause gate. Drives the public navigation methods directly (the established pattern), then
# verifies state transitions and that the apply helpers run without crashing and reach the
# AudioServer. Prints SETTINGS_MENU_TEST_PASS on success.

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

	# --- 1-3. Initial state ----------------------------------------------------
	if bool(main.get("paused")):
		_fail("paused should default to false")
	if bool(main.get("settings_open")):
		_fail("settings_open should default to false")
	if int(main.get("master_volume")) != 80:
		_fail("master_volume should default to 80")
	if String(main.get("graphics_quality")) != "high":
		_fail("graphics_quality should default to high")
	if int(main.get("resolution_index")) != 0:
		_fail("resolution_index should default to 0")
	if int(main.get("settings_cursor")) != 0:
		_fail("settings_cursor should default to 0")

	# --- 4. Open the settings menu --------------------------------------------
	if not failed:
		main.call("_toggle_settings")
		if not bool(main.get("settings_open")):
			_fail("settings_open should be true after toggle")
		if int(main.get("settings_cursor")) != 0:
			_fail("settings_cursor should reset to 0 on open")

	# --- 5. Cursor down (Resolution -> Volume) --------------------------------
	if not failed:
		main.call("_settings_cursor_move", 1)
		if int(main.get("settings_cursor")) != 1:
			_fail("settings_cursor should be 1 after move down, got %d" % int(main.get("settings_cursor")))

	# --- 6. Change volume right (80 -> 85) ------------------------------------
	if not failed:
		main.call("_settings_value_change", 1)
		if int(main.get("master_volume")) != 85:
			_fail("master_volume should be 85 after one step right, got %d" % int(main.get("master_volume")))

	# --- 7. Cursor to graphics row (2), change left (high -> medium) ----------
	if not failed:
		main.call("_settings_cursor_move", 1)
		if int(main.get("settings_cursor")) != 2:
			_fail("settings_cursor should be 2 (graphics), got %d" % int(main.get("settings_cursor")))
		main.call("_settings_value_change", -1)
		if String(main.get("graphics_quality")) != "medium":
			_fail("graphics_quality should be medium after left, got %s" % String(main.get("graphics_quality")))

	# --- 8-9. Pause toggle -----------------------------------------------------
	if not failed:
		main.call("_toggle_pause")
		if not bool(main.get("paused")):
			_fail("paused should be true after first toggle")
		main.call("_toggle_pause")
		if bool(main.get("paused")):
			_fail("paused should be false after second toggle")

	# --- 10. Close the settings menu ------------------------------------------
	if not failed:
		main.call("_toggle_settings")
		if bool(main.get("settings_open")):
			_fail("settings_open should be false after second toggle")

	# --- 11. _apply_graphics_quality does not crash for any quality -----------
	if not failed:
		for q in ["low", "medium", "high"]:
			main.set("graphics_quality", q)
			main.call("_apply_graphics_quality")

	# --- 12. _apply_master_volume reaches the Master bus ----------------------
	if not failed:
		main.set("master_volume", 85)
		main.call("_apply_master_volume")
		var bus: int = AudioServer.get_bus_index("Master")
		if bus < 0:
			_fail("Master audio bus not found")
		else:
			var got_db: float = AudioServer.get_bus_volume_db(bus)
			var want_db: float = linear_to_db(0.85)
			if absf(got_db - want_db) > 0.5:
				_fail("Master bus volume db mismatch: got %f want %f" % [got_db, want_db])
			# Volume 0 should mute the bus.
			main.set("master_volume", 0)
			main.call("_apply_master_volume")
			if not AudioServer.is_bus_mute(bus):
				_fail("Master bus should be muted at volume 0")

	if not failed:
		print("SETTINGS_MENU_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
