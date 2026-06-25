extends SceneTree
# TDD regression for assigning reserve marines as defensive garrisons on captured/
# purchased player assets. This closes the loop after boarding: surviving marines can
# be stationed aboard the prize, the reserve pool shrinks, invalid targets are denied,
# and the garrison value persists through save/load.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _find_by_name(main: Node, nm: String) -> Node3D:
	for s in main.ships:
		if is_instance_valid(s) and String(s.ship_name) == nm:
			return s
	return null

func _set_test_marines(game: Node, count: int) -> void:
	var marines: Array = []
	for i in range(count):
		marines.append({"name": "Garrison%d" % i, "skill": 5, "wounds": 0, "morale": 1.0, "assigned": false})
	game.set("marine_roster", marines)
	game.set("marine_pool", count)

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
		quit(1)
		return

	if not main.has_method("_assign_marine_garrison"):
		_fail("main is missing _assign_marine_garrison()")

	var prize: Node3D = _find_by_name(main, "Ironclaw")
	if prize == null:
		_fail("Ironclaw missing for garrison assignment test")

	if not failed and prize != null:
		# Simulate a captured prize: player-owned, non-flagship, ungarrisoned.
		prize.set_faction("player")
		prize.set("disabled", false)
		prize.set("marine_garrison", 0)
		var player_for_pos: Node3D = main.get("player")
		prize.global_position = player_for_pos.global_position + Vector3(0, 0, -30)
		main.set("target", prize)
		_set_test_marines(game, 3)

		var ok1: bool = bool(main.call("_assign_marine_garrison"))
		if not ok1:
			_fail("first garrison assignment returned false")
		if int(prize.get("marine_garrison")) != 1:
			_fail("first assignment garrison %d != 1" % int(prize.get("marine_garrison")))
		if int(game.get("marine_pool")) != 2:
			_fail("first assignment marine_pool %d != 2" % int(game.get("marine_pool")))

		var ok2: bool = bool(main.call("_assign_marine_garrison"))
		if not ok2:
			_fail("second garrison assignment returned false")
		if int(prize.get("marine_garrison")) != 2:
			_fail("second assignment garrison %d != 2" % int(prize.get("marine_garrison")))
		if int(game.get("marine_pool")) != 1:
			_fail("second assignment marine_pool %d != 1" % int(game.get("marine_pool")))

		# Invalid targets must not consume marines or alter garrisons when no owned
		# non-flagship candidate is in range.
		for s in main.ships:
			if is_instance_valid(s) and s != main.get("player") and s.faction == "player":
				s.global_position = player_for_pos.global_position + Vector3(0, 0, 1000 + float(main.ships.find(s)) * 20.0)
		var before_pool: int = int(game.get("marine_pool"))
		var player_ship: Node3D = main.get("player")
		main.set("target", player_ship)
		if bool(main.call("_assign_marine_garrison")):
			_fail("no-candidate flagship target should not accept reserve marine garrison")
		if int(game.get("marine_pool")) != before_pool:
			_fail("invalid flagship/no-candidate target consumed a marine")

		prize.set_faction("hostile")
		prize.global_position = player_for_pos.global_position + Vector3(0, 0, -30)
		main.set("target", prize)
		if bool(main.call("_assign_marine_garrison")):
			_fail("hostile target should not accept a player garrison when no owned fallback is in range")
		if int(game.get("marine_pool")) != before_pool:
			_fail("hostile/no-candidate target consumed a marine")

		prize.set_faction("player")
		prize.global_position = player_for_pos.global_position + Vector3(0, 0, -30)
		main.set("target", prize)
		game.set("marine_pool", 0)
		if bool(main.call("_assign_marine_garrison")):
			_fail("garrison assignment should fail with no available marines")
		if int(prize.get("marine_garrison")) != 2:
			_fail("no-marine attempt changed garrison to %d" % int(prize.get("marine_garrison")))

		# Save/load should preserve the manually assigned defensive garrison.
		game.set("marine_pool", 1)
		main.set("save_path", "user://voidborne_garrison_assignment_test.json")
		if not bool(main.call("_quick_save")):
			_fail("quick save failed for garrison assignment state")
		elif not bool(main.call("_quick_load")):
			_fail("quick load failed for garrison assignment state")
		else:
			await process_frame
			var reloaded: Node3D = _find_by_name(main, "Ironclaw")
			if reloaded == null:
				_fail("Ironclaw missing after load")
			elif int(reloaded.get("marine_garrison")) != 2:
				_fail("assigned garrison did not persist: %d != 2" % int(reloaded.get("marine_garrison")))

	if not failed:
		print("MARINE_GARRISON_ASSIGNMENT_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
