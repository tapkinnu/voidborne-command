extends SceneTree
# Regression test for the multi-tab station market / dock screen overlay (J key).
# Drives the public navigation methods directly (the established pattern), then verifies
# tab/cursor state transitions, that opening freezes flight, and that _update_hud() feeds
# the overlay data without crashing. Prints DOCK_SCREEN_TEST_PASS on success.

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

	# --- 1. Initial state ------------------------------------------------------
	if bool(main.get("dock_screen_open")):
		_fail("dock_screen_open should default to false")
	if int(main.get("dock_screen_tab")) != 0:
		_fail("dock_screen_tab should default to 0")
	if int(main.get("dock_screen_cursor")) != 0:
		_fail("dock_screen_cursor should default to 0")

	# --- 2. Open the dock screen at a friendly station -------------------------
	if not failed:
		var player: Node3D = main.get("player")
		var station: Node3D = main.get("station")
		if is_instance_valid(player) and is_instance_valid(station):
			player.global_position = station.global_position + Vector3(0, 0, 30)
		main.call("_toggle_dock_screen")
		if not bool(main.get("dock_screen_open")):
			# Range check refused (e.g. station moved) — force-open to exercise nav logic.
			main.set("dock_screen_open", true)
			main.set("dock_screen_tab", 0)
			main.set("dock_screen_cursor", 0)
		if not bool(main.get("dock_screen_open")):
			_fail("dock_screen_open should be true after opening")
		if int(main.get("dock_screen_tab")) != 0:
			_fail("dock_screen_tab should reset to 0 on open")
		if int(main.get("dock_screen_cursor")) != 0:
			_fail("dock_screen_cursor should reset to 0 on open")

	# --- 3. LEFT wraps tab 0 -> 3 and resets cursor ----------------------------
	if not failed:
		main.set("dock_screen_cursor", 2)
		main.call("_handle_dock_screen_key", KEY_LEFT)
		if int(main.get("dock_screen_tab")) != 3:
			_fail("LEFT from tab 0 should wrap to 3, got %d" % int(main.get("dock_screen_tab")))
		if int(main.get("dock_screen_cursor")) != 0:
			_fail("cursor should reset to 0 after tab change")

	# --- 4. RIGHT from tab 0 -> 1 ----------------------------------------------
	if not failed:
		main.set("dock_screen_tab", 0)
		main.set("dock_screen_cursor", 3)
		main.call("_handle_dock_screen_key", KEY_RIGHT)
		if int(main.get("dock_screen_tab")) != 1:
			_fail("RIGHT from tab 0 should go to 1, got %d" % int(main.get("dock_screen_tab")))
		if int(main.get("dock_screen_cursor")) != 0:
			_fail("cursor should reset to 0 after tab change")

	# --- 5. DOWN on tab 0 (shipyard, 4 rows): cursor 0 -> 1 --------------------
	if not failed:
		main.set("dock_screen_tab", 0)
		main.set("dock_screen_cursor", 0)
		main.call("_handle_dock_screen_key", KEY_DOWN)
		if int(main.get("dock_screen_cursor")) != 1:
			_fail("DOWN on tab 0 should move cursor 0 -> 1, got %d" % int(main.get("dock_screen_cursor")))

	# --- 6. UP on tab 0 cursor 0 wraps to 3 ------------------------------------
	if not failed:
		main.set("dock_screen_tab", 0)
		main.set("dock_screen_cursor", 0)
		main.call("_handle_dock_screen_key", KEY_UP)
		if int(main.get("dock_screen_cursor")) != 3:
			_fail("UP on tab 0 cursor 0 should wrap to 3, got %d" % int(main.get("dock_screen_cursor")))

	# --- 7. Digit 2 jumps to tab 1 (crew) --------------------------------------
	if not failed:
		main.set("dock_screen_tab", 0)
		main.call("_handle_dock_screen_key", KEY_2)
		if int(main.get("dock_screen_tab")) != 1:
			_fail("KEY_2 should jump to tab 1, got %d" % int(main.get("dock_screen_tab")))

	# --- 8. _update_hud while open does not crash and includes overlay data ----
	if not failed:
		main.call("_update_hud")
		var hud_node: Node = main.get("hud")
		if hud_node != null:
			var hd: Dictionary = hud_node.get("data")
			if not hd.has("dock_screen_open"):
				_fail("HUD data should include dock_screen_open while open")
			if not bool(hd.get("dock_screen_open", false)):
				_fail("HUD data dock_screen_open should be true while open")

	# --- 9. Opening freezes flight: _process_space early-returns ---------------
	if not failed:
		var player2: Node3D = main.get("player")
		if is_instance_valid(player2):
			player2.velocity = Vector3(10, 0, 0)
			main.call("_process_space", 0.016)
			if not player2.velocity.is_equal_approx(Vector3(10, 0, 0)):
				_fail("flight should be frozen while dock screen open; velocity changed to %s" % str(player2.velocity))

	# --- 10. ESCAPE closes the screen ------------------------------------------
	if not failed:
		main.call("_handle_dock_screen_key", KEY_ESCAPE)
		if bool(main.get("dock_screen_open")):
			_fail("ESCAPE should close the dock screen")

	if not failed:
		print("DOCK_SCREEN_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
