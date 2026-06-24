extends SceneTree
# Regression test for the live station-capture path and hostile-first target cycling.
# The vertical slice needs a boardable/capturable station target while preserving the
# neutral station as the recruit/shipyard hub.

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

	var neutral_station: Node = null
	var hostile_station: Node = null
	var hostile_count: int = 0
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		if String(s.faction) == "hostile":
			hostile_count += 1
		if String(s.ship_class) == "station":
			if String(s.faction) == "neutral":
				neutral_station = s
			elif String(s.faction) == "hostile":
				hostile_station = s

	if neutral_station == null:
		_fail("neutral recruit/shipyard station missing")
	if hostile_station == null:
		_fail("hostile capturable station missing")
	if hostile_count <= 0:
		_fail("hostile target set missing")

	# With hostiles alive, [Tab] targeting must not pick the neutral station first or cycle
	# into it. The neutral hub remains a fallback after combat targets are cleared.
	if not failed:
		main.set("target", null)
		for _i in range(hostile_count + 2):
			main.call("_cycle_target")
			var cycled: Node = main.get("target")
			if cycled == null:
				_fail("target cycling returned null while hostiles exist")
				break
			if String(cycled.faction) == "neutral":
				_fail("target cycling selected neutral station while hostiles exist")
				break

	# Prove the hostile station can complete the same boarding/capture resolution as ships:
	# faction flips, disabled clears, crew can man it, and captured count increments.
	if not failed:
		var game: Node = root.get_node_or_null("Game")
		if game == null:
			_fail("Game autoload missing in test tree")
		else:
			var needed: int = int(hostile_station.get("crew_needed"))
			# Populate crew roster to match crew_pool.
			var trng: RandomNumberGenerator = RandomNumberGenerator.new()
			trng.randomize()
			game.call("rebuild_default_roster", trng, needed)
			game.set("crew_pool", needed)
			game.set("marine_pool", 6)
			var before_captured: int = int(game.get("captured_count"))
			hostile_station.set("disabled", true)
			hostile_station.set("hull", float(hostile_station.get("max_hull")) * 0.15)
			main.call("_complete_capture", hostile_station)
			await process_frame
			if String(hostile_station.faction) != "player":
				_fail("captured hostile station did not switch to player faction")
			if bool(hostile_station.disabled):
				_fail("captured hostile station remained disabled")
			if not bool(hostile_station.manned):
				_fail("captured hostile station was not manned despite enough crew")
			if int(hostile_station.crew_assigned) != needed:
				_fail("captured hostile station did not consume/assign required crew")
			if int(game.get("captured_count")) != before_captured + 1:
				_fail("capturing hostile station did not increment captured_count")

	if not failed:
		print("STATION_CAPTURE_TARGETING_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
