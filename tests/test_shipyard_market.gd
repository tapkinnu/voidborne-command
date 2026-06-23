extends SceneTree
# Regression test for the station shipyard market. This test is intentionally
# SceneTree-based so it can run headless with the same autoloads as the game.

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

	if not main.has_method("_shipyard_class"):
		_fail("shipyard class accessor missing")
	if not main.has_method("_shipyard_cost"):
		_fail("shipyard cost accessor missing")
	if not main.has_method("_cycle_shipyard_class"):
		_fail("shipyard class cycling method missing")

	if not failed:
		var seen: Dictionary = {}
		for _i in range(6):
			var cls: String = String(main.call("_shipyard_class"))
			seen[cls] = true
			main.call("_cycle_shipyard_class")
		for required in ["fighter", "corvette", "frigate", "capital"]:
			if not seen.has(required):
				_fail("shipyard cycle did not expose class: %s" % required)

	if not failed:
		# Buy a fighter from the selected market to prove the chosen class, price, crew
		# assignment, and fleet join path are consumed by live station-economy code.
		for _i in range(8):
			if String(main.call("_shipyard_class")) == "fighter":
				break
			main.call("_cycle_shipyard_class")
		if String(main.call("_shipyard_class")) != "fighter":
			_fail("could not select fighter in shipyard cycle")
		else:
			var game: Node = root.get_node_or_null("Game")
			if game == null:
				_fail("Game autoload missing in test tree")
			else:
				var audio_node: Node = main.get("audio")
				if audio_node != null:
					audio_node.set("enabled", false)
				game.set("credits", 5000)
				game.set("crew_pool", 3)
				var before_count: int = main.ships.size()
				main.call("_buy_ship", true)
				await process_frame
				var after_count: int = main.ships.size()
				if after_count != before_count + 1:
					_fail("buying selected fighter did not spawn exactly one ship")
				else:
					var bought: Node = main.ships[after_count - 1]
					if String(bought.ship_class) != "fighter":
						_fail("buying selected fighter spawned %s" % String(bought.ship_class))
					if not bool(bought.manned):
						_fail("bought fighter should be manned when crew is available")
					if String(bought.ai_state) != "follow":
						_fail("bought manned fighter should join fleet formation")
					var fighter_cost: int = int(main.call("_shipyard_cost"))
					if int(game.get("credits")) != 5000 - fighter_cost:
						_fail("fighter cost was not charged correctly")

	if not failed:
		print("SHIPYARD_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
