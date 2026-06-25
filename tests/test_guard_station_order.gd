extends SceneTree
# Regression test for the GUARD STATION fleet order (the 8th fleet order). Proves the order
# can be set both fleet-wide and per-wing, that the escort's ai_state + per-ship
# guard_station_name are assigned, that _ai_guard_station survives a tick, that the order
# self-clears when the station vanishes, and that the whole state round-trips through
# save/load. Exercised via direct method calls only (no rendered input).

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

	# Find a manned player escort (not flagship), a friendly/neutral station, and a hostile.
	var escort: Node = null
	var hostile: Node = null
	var the_station: Node = main.get("station")
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		if String(s.faction) == "player" and not bool(s.is_player) and bool(s.manned):
			if escort == null:
				escort = s
		elif String(s.faction) == "hostile" and String(s.ship_class) != "station":
			if hostile == null:
				hostile = s
		elif String(s.ship_class) == "station" and String(s.faction) != "hostile":
			if the_station == null:
				the_station = s
	# If the autoload 'station' ref isn't a friendly/neutral station, scan for one.
	if not (is_instance_valid(the_station) and String(the_station.ship_class) == "station" and String(the_station.faction) != "hostile"):
		the_station = null
		for s in main.ships:
			if is_instance_valid(s) and String(s.ship_class) == "station" and String(s.faction) != "hostile":
				the_station = s
				break

	if escort == null:
		_fail("no manned player escort available for guard_station test")
	if the_station == null:
		_fail("no friendly/neutral station available for guard_station test")
	if hostile == null:
		_fail("no hostile available for guard_station test")

	# 3. Follow is the default standing order.
	if not failed:
		if str(main.get("fleet_order")) != "follow":
			_fail("fleet should start in follow order")

	# 4. Guard station order: fleet_order, station name, and escort ai_state/assignment.
	if not failed:
		main.set("target", the_station)
		main.call("_set_fleet_order", "guard_station")
		await process_frame
		if str(main.get("fleet_order")) != "guard_station":
			_fail("fleet_order should be 'guard_station' after _set_fleet_order")
		if String(main.get("fleet_guard_station_name")) != String(the_station.ship_name):
			_fail("fleet_guard_station_name should equal the station name")
		if str(escort.get("ai_state")) != "guard_station":
			_fail("manned escort ai_state should be 'guard_station' after order")
		if String(escort.get("guard_station_name")) != String(the_station.ship_name):
			_fail("escort guard_station_name should equal the station name")

	# 5. _ai_guard_station survives a tick without crashing.
	if not failed:
		main.call("_ai_guard_station", escort, 0.016)
		if str(main.get("fleet_order")) != "guard_station":
			_fail("fleet_order should remain 'guard_station' after _ai_guard_station tick")

	# 6. Self-clear: a missing station reverts the order to follow.
	if not failed:
		main.set("fleet_guard_station_name", "NONEXISTENT")
		main.call("_validate_fleet_guard_station")
		if str(main.get("fleet_order")) != "follow":
			_fail("guard_station should self-clear to 'follow' when station is gone")
		if String(main.get("fleet_guard_station_name")) != "":
			_fail("fleet_guard_station_name should clear when station is gone")

	# 7. Wing guard_station order.
	if not failed:
		escort.set("wing_id", "alpha")
		main.set("target", the_station)
		main.call("_set_wing_order", "alpha", "guard_station")
		await process_frame
		var worders: Dictionary = main.get("wing_orders")
		if String(worders.get("alpha", "")) != "guard_station":
			_fail("alpha wing order should be 'guard_station'")
		var wgsn: Dictionary = main.get("wing_guard_station_names")
		if String(wgsn.get("alpha", "")) != String(the_station.ship_name):
			_fail("wing_guard_station_names['alpha'] should equal the station name")
		if String(escort.get("guard_station_name")) != String(the_station.ship_name):
			_fail("winged escort guard_station_name should equal the station name")
		# Restore escort to unassigned for the global save/load test below.
		escort.set("wing_id", "")
		var wo: Dictionary = main.get("wing_orders")
		wo.clear()
		var wg: Dictionary = main.get("wing_guard_station_names")
		wg.clear()

	# 8. Save/load round-trip: the global guard_station order survives.
	if not failed:
		main.set("target", the_station)
		main.call("_set_fleet_order", "guard_station")
		await process_frame
		var save_dict: Dictionary = main.call("_build_save_dict")
		if not save_dict.has("fleet_guard_station_name"):
			_fail("save dict should include a 'fleet_guard_station_name' key")
		elif String(save_dict["fleet_guard_station_name"]) != String(the_station.ship_name):
			_fail("save dict 'fleet_guard_station_name' should equal the station name")
		# Clear in memory, then reload from the dict and confirm the order is restored.
		main.set("fleet_guard_station_name", "")
		main.set("fleet_order", "follow")
		main.call("_apply_save", save_dict)
		await process_frame
		await process_frame
		if str(main.get("fleet_order")) != "guard_station":
			_fail("fleet_order should restore to 'guard_station' after load")
		if String(main.get("fleet_guard_station_name")) == "":
			_fail("fleet_guard_station_name should restore after load")

	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	if not failed:
		print("GUARD_STATION_TEST_PASS")
	quit(1 if failed else 0)
