extends SceneTree
# Regression test for versioned persistent quick save / quick load.
# No key simulation: it drives main.gd's save/load API directly. It seeds a distinctive
# battle state, saves, mutates state away, loads, and asserts the world round-trips while
# rejected saves never clobber the live state.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _approx(a: float, b: float, eps: float = 0.05) -> bool:
	return abs(a - b) <= eps

func _find(main: Node, nm: String) -> Node:
	for s in main.ships:
		if is_instance_valid(s) and String(s.ship_name) == nm:
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

	var audio_node: Node = main.get("audio")
	if audio_node != null:
		audio_node.set("enabled", false)

	var game: Node = root.get_node_or_null("Game")
	if game == null:
		_fail("Game autoload missing in test tree")
		_finish(main)
		return

	# Redirect the save to a scratch file and start clean.
	main.set("save_path", "user://test_voidborne_save.json")
	if FileAccess.file_exists("user://test_voidborne_save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_voidborne_save.json"))

	# --- No-save load is denied cleanly ------------------------------------
	game.set("credits", 1234)
	var loaded_empty: bool = bool(main.call("_quick_load"))
	if loaded_empty:
		_fail("load succeeded despite no save file present")
	if int(game.get("credits")) != 1234:
		_fail("denied no-save load clobbered credits")

	# --- Seed a distinctive, capturable battle state -----------------------
	# Capture a hostile station so an owned station round-trips.
	var hostile_station: Node = null
	var doomed_hostile: Node = null
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		if String(s.ship_class) == "station" and String(s.faction) == "hostile":
			hostile_station = s
		if String(s.faction) == "hostile" and String(s.ship_class) == "fighter" and doomed_hostile == null:
			doomed_hostile = s
	if hostile_station == null:
		_fail("seed scenario missing hostile station")
	if doomed_hostile == null:
		_fail("seed scenario missing hostile fighter to destroy")

	var captured_station_name: String = ""
	if not failed:
		captured_station_name = String(hostile_station.ship_name)
		game.set("crew_pool", int(hostile_station.get("crew_needed")))
		game.set("marine_pool", 6)
		hostile_station.set("disabled", true)
		hostile_station.set("hull", float(hostile_station.get("max_hull")) * 0.15)
		main.call("_complete_capture", hostile_station)
		await process_frame
		if String(hostile_station.faction) != "player":
			_fail("setup: hostile station was not captured to player")

	# Destroy a hostile fighter: it must not resurrect after load.
	var doomed_name: String = ""
	if not failed:
		doomed_name = String(doomed_hostile.ship_name)
		main.call("_destroy_ship", doomed_hostile)
		await process_frame

	# A purchased/spawned player frigate with hand-set vitals and position.
	var buy_pos: Vector3 = Vector3(12.5, -3.25, 7.0)
	var bought: Node = null
	if not failed:
		bought = main.call("_spawn_ship", "frigate", "player", "TestBuy-1", buy_pos, true)
		bought.set("manned", true)
		bought.set("crew_assigned", 6)
		bought.set("hull", 222.0)
		bought.set("shield", 111.0)
		bought.set("energy", 55.0)
		bought.set("ai_state", "follow")

	# An unmanned owned ship: it must stay unmanned after load.
	var drifter: Node = null
	if not failed:
		drifter = main.call("_spawn_ship", "corvette", "player", "Drifter-1", Vector3(-20, 5, 30), false)
		drifter.set("manned", false)
		drifter.set("crew_assigned", 0)

	# Pin economy counters to distinctive values after capture side effects.
	if not failed:
		game.set("credits", 9876)
		game.set("crew_pool", 7)
		game.set("marine_pool", 4)
		game.set("captured_count", 5)
		game.set("purchased_count", 3)
		main.set("shipyard_index", 2)

	# --- Save --------------------------------------------------------------
	if not failed:
		var saved: bool = bool(main.call("_quick_save"))
		if not saved:
			_fail("quick_save returned false")
		if not FileAccess.file_exists("user://test_voidborne_save.json"):
			_fail("save file was not written")

	# --- Mutate state away from the saved snapshot -------------------------
	if not failed:
		game.set("credits", 0)
		game.set("crew_pool", 0)
		game.set("marine_pool", 0)
		game.set("captured_count", 0)
		game.set("purchased_count", 0)
		main.set("shipyard_index", 0)
		bought.set("hull", 1.0)
		bought.set("shield", 1.0)
		bought.set("energy", 1.0)
		bought.set("manned", false)
		bought.global_position = Vector3(500, 500, 500)
		drifter.set("manned", true)
		hostile_station.set("faction", "hostile")

	# --- Load --------------------------------------------------------------
	if not failed:
		# _apply_save runs synchronously; assert before any combat frame mutates vitals.
		var ok: bool = bool(main.call("_quick_load"))
		if not ok:
			_fail("quick_load returned false on a valid save")

	# --- Assertions: counters round-trip -----------------------------------
	if not failed:
		if int(game.get("credits")) != 9876:
			_fail("credits did not round-trip (%d)" % int(game.get("credits")))
		if int(game.get("crew_pool")) != 7:
			_fail("crew_pool did not round-trip")
		if int(game.get("marine_pool")) != 4:
			_fail("marine_pool did not round-trip")
		if int(game.get("captured_count")) != 5:
			_fail("captured_count did not round-trip")
		if int(game.get("purchased_count")) != 3:
			_fail("purchased_count did not round-trip")
		if int(main.get("shipyard_index")) != 2:
			_fail("shipyard_index did not round-trip")

	# Purchased player ship round-trips fully.
	if not failed:
		var rb: Node = _find(main, "TestBuy-1")
		if rb == null:
			_fail("purchased ship TestBuy-1 missing after load")
		else:
			if String(rb.ship_class) != "frigate":
				_fail("purchased ship class wrong after load")
			if not bool(rb.manned):
				_fail("purchased ship lost manned flag after load")
			if int(rb.crew_assigned) != 6:
				_fail("purchased ship crew_assigned wrong after load")
			if not _approx(float(rb.hull), 222.0):
				_fail("purchased ship hull wrong after load (%f)" % float(rb.hull))
			if not _approx(float(rb.shield), 111.0):
				_fail("purchased ship shield wrong after load")
			if not _approx(float(rb.energy), 55.0):
				_fail("purchased ship energy wrong after load")
			if not _approx(rb.global_position.x, buy_pos.x) or not _approx(rb.global_position.y, buy_pos.y) or not _approx(rb.global_position.z, buy_pos.z):
				_fail("purchased ship position wrong after load (%s)" % str(rb.global_position))

	# Captured station stays player-owned.
	if not failed:
		var rs: Node = _find(main, captured_station_name)
		if rs == null:
			_fail("captured station missing after load")
		elif String(rs.faction) != "player":
			_fail("captured station not player-owned after load (%s)" % String(rs.faction))

	# Destroyed hostile does not resurrect.
	if not failed and doomed_name != "":
		if _find(main, doomed_name) != null:
			_fail("destroyed hostile %s resurrected after load" % doomed_name)

	# Unmanned owned ship stays unmanned.
	if not failed:
		var rd: Node = _find(main, "Drifter-1")
		if rd == null:
			_fail("unmanned owned ship missing after load")
		elif bool(rd.manned):
			_fail("unmanned owned ship became manned after load")

	# Player flagship restored and wired to the player reference.
	if not failed:
		var p: Node = main.get("player")
		if p == null or not bool(p.is_player):
			_fail("player flagship not restored after load")

	# --- Rejected saves never clobber current state ------------------------
	if not failed:
		var before_credits: int = int(game.get("credits"))
		var test_path: String = "user://test_voidborne_save.json"

		_write_text(test_path, "{ not valid json ]")
		if bool(main.call("_quick_load")):
			_fail("corrupt save was accepted")
		if int(game.get("credits")) != before_credits:
			_fail("corrupt save clobbered credits")

		_write_text(test_path, JSON.stringify({"game_id": "not_voidborne", "version": 1, "economy": {}, "ships": []}))
		if bool(main.call("_quick_load")):
			_fail("wrong game_id save was accepted")
		if int(game.get("credits")) != before_credits:
			_fail("wrong game_id save clobbered credits")

		var future: Dictionary = main.call("_build_save_dict")
		future["version"] = int(future["version"]) + 1
		_write_text(test_path, JSON.stringify(future))
		if bool(main.call("_quick_load")):
			_fail("future-version save was accepted")
		if int(game.get("credits")) != before_credits:
			_fail("future-version save clobbered credits")

	# Cleanup scratch save.
	if FileAccess.file_exists("user://test_voidborne_save.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_voidborne_save.json"))

	if not failed:
		print("SAVE_LOAD_TEST_PASS")
	_finish(main)

func _write_text(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	quit(1 if failed else 0)
