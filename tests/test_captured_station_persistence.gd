extends SceneTree
# Regression test: captured stations persist across inter-system jumps.
# Verifies: (1) capturing a hostile station records it, (2) jumping away and
# back keeps the station player-faction, (3) save/load round-trips the record.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _find_station(ships: Array, name: String) -> Node3D:
	for s in ships:
		if is_instance_valid(s) and String(s.get("ship_name")) == name and String(s.get("ship_class")) == "station":
			return s
	return null

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

	# Autoloads are not compile-time identifiers in `-s` script mode; fetch via the tree.
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		_fail("Game autoload not found")
		quit(1)
		return

	var audio_node: Node = main.get("audio")
	if audio_node != null:
		audio_node.set("enabled", false)

	# --- 1. Find a hostile station in system 0 (Kryos Relay) ------------------
	var kryos: Node3D = _find_station(main.ships, "Kryos Relay")
	if kryos == null:
		_fail("Kryos Relay station not found in system 0")
	else:
		if String(kryos.get("faction")) != "hostile":
			_fail("Kryos Relay should start hostile, got %s" % String(kryos.get("faction")))

	# --- 2. Simulate capture via _complete_capture ----------------------------
	if not failed and kryos != null:
		# Set up boarding state so _complete_capture can run
		main.set("boarding_attacker_strength", 10)
		main.set("boarding_defender_strength", 0)
		main.set("boarding_initial_attacker", 10)
		main.set("boarding_initial_defender", 12)
		main.set("boarding_target", kryos)
		# Give enough crew to man it
		game.set("crew_pool", 20)
		main.call("_complete_capture", kryos)
		await process_frame
		if String(kryos.get("faction")) != "player":
			_fail("Kryos Relay should be player-faction after capture, got %s" % String(kryos.get("faction")))
		# Check the captured_station_names record
		var csn: Dictionary = main.get("captured_station_names")
		if not csn.has(0):
			_fail("captured_station_names missing system 0 key")
		else:
			var names: Array = csn[0]
			if not names.has("Kryos Relay"):
				_fail("captured_station_names[0] does not contain 'Kryos Relay'")

	# --- 3. Jump to system 1 and back, verify station is still player ---------
	if not failed:
		main.call("jump_to_system", 1)
		await process_frame
		await process_frame
		# In system 1 now — Kryos Relay should not exist here
		var kryos_in_sys1: Node3D = _find_station(main.ships, "Kryos Relay")
		if kryos_in_sys1 != null:
			_fail("Kryos Relay should not exist in system 1")

		# Jump back to system 0
		main.call("jump_to_system", 0)
		await process_frame
		await process_frame
		var kryos_back: Node3D = _find_station(main.ships, "Kryos Relay")
		if kryos_back == null:
			_fail("Kryos Relay station missing after jumping back to system 0")
		else:
			if String(kryos_back.get("faction")) != "player":
				_fail("Kryos Relay should still be player-faction after jump round-trip, got %s" % String(kryos_back.get("faction")))

	# --- 4. Save/load round-trips captured_station_names ----------------------
	if not failed:
		main.set("save_path", "user://test_captured_station.json")
		main.call("jump_to_system", 0)
		await process_frame
		main.call("_quick_save")
		# Jump away to change state, then load
		main.call("jump_to_system", 1)
		await process_frame
		main.call("_quick_load")
		await process_frame
		var csn_loaded: Dictionary = main.get("captured_station_names")
		if not csn_loaded.has(0):
			_fail("captured_station_names missing system 0 after save/load")
		else:
			var names_loaded: Array = csn_loaded[0]
			if not names_loaded.has("Kryos Relay"):
				_fail("captured_station_names[0] missing 'Kryos Relay' after save/load")
		# Verify the station is player-faction in the loaded game
		var kryos_loaded: Node3D = _find_station(main.ships, "Kryos Relay")
		if kryos_loaded == null:
			_fail("Kryos Relay missing after save/load")
		elif String(kryos_loaded.get("faction")) != "player":
			_fail("Kryos Relay should be player-faction after save/load, got %s" % String(kryos_loaded.get("faction")))
		# Clean up test save
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_captured_station.json"))

	if not failed:
		print("CAPTURED_STATION_PERSISTENCE_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
