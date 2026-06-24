extends SceneTree
# Regression test for the PATROL fleet order (the 7th fleet order). Proves the order can be
# set, that _ai_patrol survives both the empty-route and populated-route cases, that
# waypoints can be dropped, that [7] toggles the route clear, and that the route round-trips
# through save/load. Exercised via direct method calls only (no rendered input).

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

	# Find a manned player escort (not the flagship) and a hostile.
	var escort: Node = null
	var hostile: Node = null
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		if String(s.faction) == "player" and not bool(s.is_player) and bool(s.manned):
			if escort == null:
				escort = s
		elif String(s.faction) == "hostile" and String(s.ship_class) != "station":
			if hostile == null:
				hostile = s
	if escort == null:
		_fail("no manned player escort available for patrol-order test")
	if hostile == null:
		_fail("no hostile available for patrol-order test")

	var player: Node = main.get("player")
	if player == null:
		_fail("no player flagship for patrol-order test")

	# 4. Follow is the default standing order.
	if not failed:
		if str(main.get("fleet_order")) != "follow":
			_fail("fleet should start in follow order")

	# 5. Patrol order: fleet_order + every manned escort ai_state become 'patrol'.
	if not failed:
		main.call("_set_fleet_order", "patrol")
		await process_frame
		if str(main.get("fleet_order")) != "patrol":
			_fail("fleet_order should be 'patrol' after _set_fleet_order('patrol')")
		if str(escort.get("ai_state")) != "patrol":
			_fail("manned escort ai_state should be 'patrol' after order")

	# 6. With no waypoints, _ai_patrol falls back to follow formation without crashing.
	if not failed:
		main.call("_ai_patrol", escort, 0.016)
		if str(main.get("fleet_order")) != "patrol":
			_fail("fleet_order should remain 'patrol' after empty-route _ai_patrol")

	# 7. Drop two waypoints from two distinct flagship positions.
	if not failed:
		player.global_position = Vector3(40.0, 0.0, 40.0)
		main.call("_drop_patrol_waypoint")
		player.global_position = Vector3(-40.0, 0.0, -40.0)
		main.call("_drop_patrol_waypoint")
		var wps: Array = main.get("patrol_waypoints")
		if wps.size() != 2:
			_fail("patrol_waypoints should hold 2 entries after two drops, got %d" % wps.size())

	# 8. _ai_patrol with a populated route records a per-ship waypoint index.
	if not failed:
		main.call("_ai_patrol", escort, 0.016)
		var indices: Dictionary = main.get("patrol_indices")
		if not indices.has(escort.get_instance_id()):
			_fail("patrol_indices should have an entry for the patrolling escort")

	# 9. [7] toggles the route clear when already patrolling with waypoints set.
	if not failed:
		main.call("_handle_fleet_menu_key", KEY_7)
		var wps2: Array = main.get("patrol_waypoints")
		if not wps2.is_empty():
			_fail("pressing [7] while patrolling with waypoints should clear the route")

	# 10. Save/load round-trip: a populated route survives _build_save_dict -> _apply_save.
	if not failed:
		# Re-populate (fleet_order is still 'patrol' after the clear above).
		player.global_position = Vector3(60.0, 0.0, 0.0)
		main.call("_drop_patrol_waypoint")
		player.global_position = Vector3(0.0, 0.0, 60.0)
		main.call("_drop_patrol_waypoint")
		var save_dict: Dictionary = main.call("_build_save_dict")
		if not save_dict.has("patrol_waypoints"):
			_fail("save dict should include a 'patrol_waypoints' key")
		else:
			var saved_wps: Array = save_dict["patrol_waypoints"]
			if saved_wps.size() != 2:
				_fail("save dict 'patrol_waypoints' should hold 2 entries, got %d" % saved_wps.size())
		# Clear in memory, then reload from the dict and confirm the route is restored.
		var live_wps: Array = main.get("patrol_waypoints")
		live_wps.clear()
		main.call("_apply_save", save_dict)
		await process_frame
		var reloaded: Array = main.get("patrol_waypoints")
		if reloaded.size() != 2:
			_fail("patrol_waypoints should restore to 2 entries after load, got %d" % reloaded.size())

	if not failed:
		print("PATROL_ORDER_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
