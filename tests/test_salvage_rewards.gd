extends SceneTree
# Regression test for credit rewards from the combat economy loop. Capturing hostile
# hulls should be economically better than destroying them, so boarding feeds the
# shipyard/fleet-growth loop instead of being only a faction flip.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _find_ship(main: Node, wanted_name: String) -> Node:
	for s in main.ships:
		if is_instance_valid(s) and String(s.ship_name) == wanted_name:
			return s
	return null

func _find_hostile_fighter(main: Node) -> Node:
	for s in main.ships:
		if is_instance_valid(s) and String(s.faction) == "hostile" and String(s.ship_class) == "fighter":
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

	var game: Node = root.get_node_or_null("Game")
	if game == null:
		_fail("Game autoload missing in test tree")

	var audio_node: Node = main.get("audio")
	if audio_node != null:
		audio_node.set("enabled", false)

	if not failed:
		_run(main, game)

	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	if not failed:
		print("SALVAGE_REWARD_TEST_PASS")
	quit(1 if failed else 0)

func _run(main: Node, game: Node) -> void:
	var frigate: Node = _find_ship(main, "Ironclaw")
	if frigate == null:
		_fail("expected hostile frigate Ironclaw for capture reward test")
		return
	if String(frigate.faction) != "hostile":
		_fail("Ironclaw should start hostile")
		return

	game.set("credits", 1000)
	game.set("crew_pool", 0)
	game.set("marine_pool", 6)
	frigate.disabled = true
	frigate.hull = frigate.max_hull * 0.10
	main.call("_complete_capture", frigate)

	# Frigate value is 5200 cr; capture reward should be 18% = 936 cr.
	if int(game.get("credits")) != 1936:
		_fail("capturing a hostile frigate should grant 936 cr bounty; got %d" % int(game.get("credits")))
	if int(game.get("captured_count")) != 1:
		_fail("capture should still increment captured_count")
	if String(frigate.faction) != "player":
		_fail("capture reward path must still flip faction to player")

	var fighter: Node = _find_hostile_fighter(main)
	if fighter == null:
		_fail("expected hostile fighter for destroy salvage test")
		return
	game.set("credits", 2000)
	main.call("_destroy_ship", fighter)

	# Fighter value is 800 cr; destruction salvage should be 8% = 64 cr.
	if int(game.get("credits")) != 2064:
		_fail("destroying a hostile fighter should grant 64 cr salvage; got %d" % int(game.get("credits")))
