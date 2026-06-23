extends SceneTree
# Regression test for station repair/refit dock services. SceneTree-based so it runs
# headless with the same autoloads as the game. No key simulation: the service method
# is invoked directly after deterministically damaging the fleet and setting credits.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _approx(a: float, b: float, eps: float = 0.01) -> bool:
	return abs(a - b) <= eps

func _dock_player(main: Node) -> void:
	# Park the flagship right next to the neutral Halcyon hub so it is in service range.
	main.player.global_position = main.station.global_position + Vector3(0, 0, 18)

func _find_manned_escort(main: Node) -> Node:
	for s in main.ships:
		if is_instance_valid(s) and s.faction == "player" and not s.is_player and s.manned and not s.destroyed and s.ship_class != "station":
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

	if not main.has_method("_station_service"):
		_fail("station service method missing")
	if not main.has_method("_service_station"):
		_fail("service station accessor missing")

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
		print("STATION_SERVICE_TEST_PASS")
	quit(1 if failed else 0)

func _run(main: Node, game: Node) -> void:
	var player: Node = main.player
	var escort: Node = _find_manned_escort(main)
	if escort == null:
		_fail("no manned escort available for service test")
		return

	# --- Scenario 1: affordable full service repairs flagship + manned escort ----
	_dock_player(main)
	player.hull = player.max_hull * 0.4
	player.shield = 0.0
	player.energy = player.max_energy * 0.25
	escort.hull = escort.max_hull * 0.5
	escort.shield = escort.max_shield * 0.3
	escort.energy = 0.0
	game.set("credits", 6000)
	var before_credits: int = int(game.get("credits"))
	main.call("_station_service")

	if not (player.hull > player.max_hull * 0.4):
		_fail("flagship hull did not improve after service")
	if not _approx(player.hull, player.max_hull):
		_fail("flagship hull should cap at max after full service")
	if not _approx(player.shield, player.max_shield):
		_fail("flagship shield should be restored to max")
	if not _approx(player.energy, player.max_energy):
		_fail("flagship energy should be refilled to max")
	if not _approx(escort.hull, escort.max_hull):
		_fail("escort hull should be restored to max")
	if not _approx(escort.shield, escort.max_shield):
		_fail("escort shield should be restored to max")
	if not _approx(escort.energy, escort.max_energy):
		_fail("escort energy should be refilled to max")
	if int(game.get("credits")) >= before_credits:
		_fail("credits should decrease when repair work is performed")

	# --- Scenario 2: repeated service at full health charges nothing -------------
	var full_credits: int = int(game.get("credits"))
	main.call("_station_service")
	if int(game.get("credits")) != full_credits:
		_fail("service at full health must not charge credits")

	# --- Scenario 3: minimum dock charge still governs light damage --------------
	player.hull = player.max_hull - 20.0  # raw hull bill is below SERVICE_MIN_CHARGE
	player.shield = player.max_shield
	player.energy = player.max_energy
	escort.hull = escort.max_hull
	escort.shield = escort.max_shield
	escort.energy = escort.max_energy
	game.set("credits", 30)
	main.call("_station_service")
	if int(game.get("credits")) != 0:
		_fail("partial light-damage service should spend the available sub-minimum budget")
	if player.hull >= player.max_hull - 0.01:
		_fail("sub-minimum budget should not fully repair light damage")
	if not (player.hull > player.max_hull - 20.0):
		_fail("sub-minimum budget should still repair some light damage")

	# --- Scenario 4: disabled flagship is cleared once hull clears threshold -----
	player.hull = player.max_hull * 0.1
	player.disabled = true
	game.set("credits", 6000)
	main.call("_station_service")
	if player.disabled:
		_fail("disabled flagship should be cleared after repair above threshold")

	# --- Scenario 4: away from any station the service is denied -----------------
	player.global_position = Vector3(0, 0, 6000)
	player.hull = player.max_hull * 0.5
	game.set("credits", 6000)
	var away_credits: int = int(game.get("credits"))
	main.call("_station_service")
	if int(game.get("credits")) != away_credits:
		_fail("service away from a station must not charge credits")
	if player.hull > player.max_hull * 0.5 + 0.01:
		_fail("flagship should not be repaired away from a station")

	# --- Scenario 5: hostile station refuses service ----------------------------
	var relay: Node = null
	for s in main.ships:
		if is_instance_valid(s) and s.ship_class == "station" and s.faction == "hostile":
			relay = s
			break
	if relay == null:
		_fail("expected a hostile station in the scenario")
	else:
		player.global_position = relay.global_position + Vector3(0, 0, 14)
		player.hull = player.max_hull * 0.5
		game.set("credits", 6000)
		var hostile_credits: int = int(game.get("credits"))
		main.call("_station_service")
		if int(game.get("credits")) != hostile_credits:
			_fail("hostile station must not charge for service")
		if player.hull > player.max_hull * 0.5 + 0.01:
			_fail("hostile station must not repair the flagship")

	# --- Scenario 6: an unmanned owned ship is not silently repaired -------------
	_dock_player(main)
	escort.manned = false
	escort.crew_assigned = 0
	escort.hull = escort.max_hull * 0.3
	var unmanned_hull: float = escort.hull
	player.hull = player.max_hull * 0.6
	game.set("credits", 6000)
	main.call("_station_service")
	if not _approx(escort.hull, unmanned_hull):
		_fail("unmanned owned ship should not be repaired")
	escort.manned = true
	escort.crew_assigned = escort.crew_needed

	# --- Scenario 7: partial service when credits cannot cover full cost ---------
	_dock_player(main)
	player.hull = player.max_hull * 0.2
	player.shield = 0.0
	player.energy = 0.0
	escort.hull = escort.max_hull * 0.2
	escort.shield = 0.0
	escort.energy = 0.0
	game.set("credits", 30)
	var partial_before: int = int(game.get("credits"))
	var hull_before: float = player.hull
	main.call("_station_service")
	if int(game.get("credits")) >= partial_before:
		_fail("partial service should spend available credits")
	if not (player.hull > hull_before):
		_fail("partial service should still repair some hull")
	if player.hull >= player.max_hull - 0.01:
		_fail("partial service should not fully restore hull on a tiny budget")
