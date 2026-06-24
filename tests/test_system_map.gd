extends SceneTree
# Regression test for the multi-station system map and respawning hostile threats.
# Verifies: 3+ stations exist, the system-map overlay toggles into the HUD data, and the
# threat-respawn system warps in fresh hostiles once mobile hostiles are cleared.

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

	# --- 1. At least 3 stations in the world ----------------------------------
	var station_count: int = 0
	for s in main.ships:
		if is_instance_valid(s) and String(s.ship_class) == "station":
			station_count += 1
	if station_count < 3:
		_fail("expected at least 3 stations, found %d" % station_count)

	# --- 2. system_map_open defaults to false ---------------------------------
	if bool(main.get("system_map_open")):
		_fail("system_map_open should default to false")

	# --- 3. Toggling the map flows into the HUD data --------------------------
	if not failed:
		main.call("_toggle_system_map")
		await process_frame
		if not bool(main.get("system_map_open")):
			_fail("system_map_open should be true after toggle")
		main.call("_update_hud")
		var hud_node: Node = main.get("hud")
		var hud_data: Dictionary = hud_node.get("data")
		if not bool(hud_data.get("system_map_open", false)):
			_fail("HUD data did not carry system_map_open=true")
		var map_data: Dictionary = hud_data.get("system_map", {})
		if map_data.is_empty() or Array(map_data.get("stations", [])).size() < 3:
			_fail("HUD system_map data missing stations")
		# Toggle back off.
		main.call("_toggle_system_map")
		if bool(main.get("system_map_open")):
			_fail("system_map_open should be false after second toggle")

	# --- 4. Respawn system replenishes cleared hostiles -----------------------
	if not failed:
		for s in main.ships:
			if is_instance_valid(s) and String(s.faction) == "hostile" and String(s.ship_class) != "station":
				s.set("destroyed", true)
		var live_before: int = int(main.call("_count_live_hostiles"))
		if live_before != 0:
			_fail("expected 0 live hostiles after clearing, found %d" % live_before)
		# RESPAWN_INTERVAL is 30.0; advance well past it in one tick to force a respawn.
		main.call("_update_respawns", 31.0)
		await process_frame
		var live_after: int = int(main.call("_count_live_hostiles"))
		if live_after < 2:
			_fail("respawn did not spawn new hostiles (live=%d)" % live_after)
		# Respawned threats must be mobile fighters, never stations.
		var live_fighters: int = 0
		for s in main.ships:
			if is_instance_valid(s) and not bool(s.get("destroyed")) and String(s.faction) == "hostile" and String(s.ship_class) == "fighter":
				live_fighters += 1
		if live_fighters < 2:
			_fail("respawned hostiles are not fighters (live fighters=%d)" % live_fighters)

	if not failed:
		print("SYSTEM_MAP_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
