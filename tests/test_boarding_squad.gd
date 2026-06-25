extends SceneTree
# Regression test for boarding as a resolved squad action. Proves the marine garrison
# model, the disable-time garrison loss, attacker/defender resolution with casualties,
# the failure path (outnumbered attackers wiped, target stays hostile), and that the
# garrison round-trips through save/load. Exercised purely via direct method calls
# (no key simulation) so the squad combat resolves deterministically.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _find_by_class(main: Node, cls: String, fac: String) -> Node3D:
	for s in main.ships:
		if is_instance_valid(s) and String(s.ship_class) == cls and String(s.faction) == fac:
			return s
	return null

func _find_by_name(main: Node, nm: String) -> Node3D:
	for s in main.ships:
		if is_instance_valid(s) and String(s.ship_name) == nm:
			return s
	return null

func _disable_ship(s: Node3D) -> void:
	# Drop the shield then deal enough hull damage to cross the disable threshold without
	# destroying it, so take_damage applies the disable-time garrison halving.
	s.shield = 0.0
	var dmg: float = float(s.max_hull) * 0.80
	s.call("take_damage", dmg, "")

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

	# --- 1) Garrison by class -------------------------------------------------
	var expected: Dictionary = {"fighter": 0, "corvette": 2, "frigate": 4, "capital": 8, "station": 12}
	for cls in expected.keys():
		var ship: Node3D = _find_by_class(main, cls, "hostile")
		if cls == "fighter":
			ship = _find_by_class(main, "fighter", "hostile")
		if ship == null:
			_fail("no hostile %s present to check garrison" % cls)
			continue
		var want: int = int(expected[cls])
		if int(ship.get("marine_garrison")) != want:
			_fail("%s garrison %d != expected %d" % [cls, int(ship.get("marine_garrison")), want])

	# --- 2) Disable halves the garrison (frigate 4 -> 2) ----------------------
	var frig: Node3D = _find_by_name(main, "Ironclaw")
	if frig == null:
		frig = _find_by_class(main, "frigate", "hostile")
	if frig == null:
		_fail("hostile frigate missing")
	elif not failed:
		_disable_ship(frig)
		if not bool(frig.disabled):
			_fail("frigate did not become disabled")
		if int(frig.get("marine_garrison")) != 2:
			_fail("disabled frigate garrison %d != 2 (halved from 4)" % int(frig.get("marine_garrison")))

	# --- 3) Successful boarding: attackers far outnumber defenders -------------
	if not failed and frig != null:
		var player: Node3D = main.get("player")
		if not is_instance_valid(player):
			_fail("player ship missing")
		else:
			frig.global_position = player.global_position + Vector3(0, 0, -10)
			# Build a deterministic 20-marine roster at full morale so the attacker
			# strength assertion reflects squad size (morale modulates strength).
			var full_marines: Array = []
			for mi in range(20):
				full_marines.append({"name": "Boarder%d" % mi, "skill": 5, "wounds": 0, "morale": 1.0, "assigned": false})
			game.set("marine_roster", full_marines)
			game.set("marine_pool", 20)
			main.set("target", frig)
			var before_captured: int = int(game.get("captured_count"))
			main.call("_try_start_boarding")
			if not bool(main.get("boarding_active")):
				_fail("boarding did not start on disabled frigate")
			if int(main.get("boarding_attacker_strength")) != 20:
				_fail("boarding attacker strength %d != 20" % int(main.get("boarding_attacker_strength")))
			if int(main.get("boarding_defender_strength")) != 2:
				_fail("boarding defender strength %d != 2" % int(main.get("boarding_defender_strength")))
			# Resolve the squad combat with large deltas (no awaits, so _process can't race).
			var guard: int = 0
			while bool(main.get("boarding_active")) and guard < 200:
				main.call("_update_boarding", 2.0)
				guard += 1
			if guard >= 200:
				_fail("boarding never resolved (possible stalemate)")
			if String(frig.faction) != "player":
				_fail("boarded frigate did not switch to player faction")
			if int(game.get("captured_count")) != before_captured + 1:
				_fail("successful boarding did not increment captured_count")
			# Wound model: in a lopsided fight no marine dies, so the whole squad returns
			# to the pool but carries injuries rather than being killed off.
			var pool_after: int = int(game.get("marine_pool"))
			if pool_after <= 0:
				_fail("marine_pool %d should retain survivors after capture" % pool_after)
			var wounded_after: int = 0
			for rm in game.get("marine_roster"):
				if typeof(rm) == TYPE_DICTIONARY and int((rm as Dictionary).get("wounds", 0)) > 0:
					wounded_after += 1
			if wounded_after <= 0:
				_fail("boarding squad took no wounds (expected casualty-based injuries)")
			# Captured ship is left ungarrisoned for the new owner.
			if int(frig.get("marine_garrison")) != 0:
				_fail("captured ship garrison %d != 0" % int(frig.get("marine_garrison")))

	# --- 4) Failure case: one marine vs a defended capital --------------------
	if not failed:
		var cap: Node3D = _find_by_class(main, "capital", "hostile")
		if cap == null:
			_fail("hostile capital missing")
		else:
			_disable_ship(cap)
			var def_after_disable: int = int(cap.get("marine_garrison"))
			if def_after_disable <= 0:
				_fail("disabled capital has no defenders to resist boarding")
			var player2: Node3D = main.get("player")
			cap.global_position = player2.global_position + Vector3(0, 0, -10)
			game.set("marine_pool", 1)
			main.set("target", cap)
			main.call("_try_start_boarding")
			if not bool(main.get("boarding_active")):
				_fail("boarding did not start against capital")
			var guard2: int = 0
			while bool(main.get("boarding_active")) and guard2 < 200:
				main.call("_update_boarding", 2.0)
				guard2 += 1
			if bool(main.get("boarding_active")):
				_fail("failed boarding never resolved")
			if not bool(main.get("boarding_failed")):
				_fail("boarding_failed flag not set on a lost assault")
			if String(cap.faction) != "hostile":
				_fail("capital should remain hostile after a failed boarding")
			if int(game.get("marine_pool")) != 0:
				_fail("failed boarding should lose all marines (pool != 0)")

	# --- 5) Garrison round-trips through save/load -----------------------------
	if not failed:
		var corv: Node3D = _find_by_class(main, "corvette", "hostile")
		if corv == null:
			_fail("hostile corvette missing for save/load check")
		else:
			corv.set("marine_garrison", 7)
			var sentinel: String = String(corv.ship_name)
			if not bool(main.call("_quick_save")):
				_fail("quick save failed")
			elif not bool(main.call("_quick_load")):
				_fail("quick load failed")
			else:
				await process_frame
				var reloaded: Node3D = _find_by_name(main, sentinel)
				if reloaded == null:
					_fail("corvette %s missing after load" % sentinel)
				elif int(reloaded.get("marine_garrison")) != 7:
					_fail("garrison did not round-trip: %d != 7" % int(reloaded.get("marine_garrison")))

	if not failed:
		print("BOARDING_SQUAD_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
