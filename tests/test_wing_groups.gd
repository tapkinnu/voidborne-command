extends SceneTree
# Regression test for WING SUB-GROUPING: per-wing independent fleet orders.
# Proves ships can be assigned to named wings (alpha/beta/gamma), each wing carries
# an independent order, unassigned ships fall back to the global fleet_order, and the
# whole state round-trips through save/load.

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

	# Gather escorts (manned, player-owned, not flagship) and a hostile.
	var escorts: Array = []
	var hostile: Node = null
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		if String(s.faction) == "player" and not bool(s.is_player) and bool(s.manned):
			escorts.append(s)
		elif String(s.faction) == "hostile" and String(s.ship_class) != "station":
			if hostile == null:
				hostile = s
	if escorts.size() < 2:
		_fail("need at least 2 manned escorts for wing test (found %d)" % escorts.size())
	if hostile == null:
		_fail("no hostile available for wing attack-order test")

	# 1. Default: all escorts have empty wing_id and follow the global fleet_order.
	if not failed:
		for s in escorts:
			if str(s.get("wing_id")) != "":
				_fail("escort should start with empty wing_id")
		if str(main.get("fleet_order")) != "follow":
			_fail("fleet should start in follow order")

	# 2. Assign escorts to wings. Use Alpha and Beta (we have 2 escorts).
	if not failed:
		escorts[0].set("wing_id", "alpha")
		escorts[1].set("wing_id", "beta")
		main.call("_set_wing_order", "alpha", "attack", hostile)
		main.call("_set_wing_order", "beta", "hold")
		await process_frame
		var worders: Dictionary = main.get("wing_orders")
		if String(worders.get("alpha", "")) != "attack":
			_fail("alpha wing order should be 'attack'")
		if String(worders.get("beta", "")) != "hold":
			_fail("beta wing order should be 'hold'")

	# 3. _get_ship_order returns the wing's order for winged ships, global for unassigned.
	if not failed:
		if str(main.call("_get_ship_order", escorts[0])) != "attack":
			_fail("alpha ship effective order should be 'attack'")
		if str(main.call("_get_ship_order", escorts[1])) != "hold":
			_fail("beta ship effective order should be 'hold'")

	# 4. Unassigned ship uses the global fleet_order.
	if not failed:
		escorts[0].set("wing_id", "")
		if str(main.call("_get_ship_order", escorts[0])) != str(main.get("fleet_order")):
			_fail("unassigned ship should use global fleet_order")
		# Restore for save/load test.
		escorts[0].set("wing_id", "alpha")

	# 5. Save / load round-trip: wing assignments and wing orders persist.
	if not failed:
		var tmp_path: String = "user://test_wing_save.json"
		main.set("save_path", tmp_path)
		var dir: DirAccess = DirAccess.open("user://")
		if dir != null and dir.file_exists("test_wing_save.json"):
			dir.remove("test_wing_save.json")
		main.call("_quick_save")
		# Clear wing state, then load.
		escorts[0].set("wing_id", "")
		escorts[1].set("wing_id", "")
		var wo: Dictionary = main.get("wing_orders")
		wo.clear()
		main.call("_quick_load")
		await process_frame
		await process_frame
		# After load, ships are rebuilt — find them again by wing assignment.
		var alpha_found: bool = false
		var beta_found: bool = false
		for s in main.ships:
			if not is_instance_valid(s):
				continue
			if String(s.faction) != "player" or bool(s.is_player) or not bool(s.manned):
				continue
			var wid: String = String(s.get("wing_id"))
			if wid == "alpha":
				alpha_found = true
				if str(main.call("_get_ship_order", s)) != "attack":
					_fail("loaded alpha ship order should still be 'attack'")
			elif wid == "beta":
				beta_found = true
				if str(main.call("_get_ship_order", s)) != "hold":
					_fail("loaded beta ship order should still be 'hold'")
		if not alpha_found:
			_fail("alpha wing assignment did not round-trip through save/load")
		if not beta_found:
			_fail("beta wing assignment did not round-trip through save/load")

	# 6. Clearing a wing_id reverts the ship to the global order.
	if not failed:
		var alpha_ship: Node = null
		for s in main.ships:
			if is_instance_valid(s) and String(s.faction) == "player" and not bool(s.is_player) and String(s.get("wing_id")) == "alpha":
				alpha_ship = s
				break
		if alpha_ship == null:
			_fail("could not find alpha ship post-load for clear test")
		else:
			alpha_ship.set("wing_id", "")
			var eff: String = str(main.call("_get_ship_order", alpha_ship))
			var glob: String = str(main.get("fleet_order"))
			if eff != glob:
				_fail("after clearing wing_id, effective order (%s) should match global (%s)" % [eff, glob])

	# Cleanup.
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	if not failed:
		print("WING_GROUPS_TEST_PASS")
	quit(1 if failed else 0)