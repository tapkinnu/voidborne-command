extends SceneTree
# Regression test for the morale system: morale modulates ship crew bonuses and marine
# boarding strength, and _adjust_morale changes/clamps roster morale.

var failed: bool = false
var game: Node = null

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	if not failed:
		print("MORALE_SYSTEM_TEST_PASS")
	quit(1 if failed else 0)

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

	game = root.get_node_or_null("Game")
	if game == null:
		_fail("Game autoload missing")
		_finish(main)
		return

	game.reset()

	# a) Crew morale modulates ship bonuses.
	var ship_script: Script = load("res://scripts/ship.gd")
	var ship: Node3D = ship_script.new()
	root.add_child(ship)
	ship.setup("corvette", "player", "TestShip")
	var base_speed: float = ship.base_max_speed

	var crew_high: Array = [{"role": "pilot", "skill": 8, "morale": 1.0}]
	ship.apply_crew_bonuses(crew_high)
	var speed_high: float = ship.max_speed
	if speed_high <= base_speed:
		_fail("morale 1.0 pilot did not raise max_speed above base")

	var crew_low: Array = [{"role": "pilot", "skill": 8, "morale": 0.0}]
	ship.apply_crew_bonuses(crew_low)
	var speed_low: float = ship.max_speed
	if speed_low >= speed_high:
		_fail("morale 0.0 should give lower max_speed than morale 1.0 (high=%f low=%f)" % [speed_high, speed_low])
	if speed_low <= base_speed:
		_fail("morale 0.0 pilot should still raise max_speed above base (min effect)")
	if ship.base_max_speed != base_speed:
		_fail("base_max_speed changed by apply_crew_bonuses (should be untouched)")

	if is_instance_valid(ship):
		root.remove_child(ship)
		ship.free()

	# b) Marine morale modulates boarding strength.
	if not failed:
		var marines_high: Array = [
			{"morale": 1.0, "wounds": 0},
			{"morale": 1.0, "wounds": 0},
			{"morale": 1.0, "wounds": 0},
		]
		var str_high: int = main._marine_effective_strength(marines_high)
		var marines_low: Array = [
			{"morale": 0.0, "wounds": 0},
			{"morale": 0.0, "wounds": 0},
			{"morale": 0.0, "wounds": 0},
		]
		var str_low: int = main._marine_effective_strength(marines_low)
		if str_low >= str_high:
			_fail("morale 0.0 marines should have lower strength than morale 1.0 (high=%d low=%d)" % [str_high, str_low])

	# c) _adjust_morale changes roster morale.
	if not failed:
		# Force a known starting morale on the whole roster.
		for c in game.crew_roster:
			if typeof(c) == TYPE_DICTIONARY:
				(c as Dictionary)["morale"] = 0.8
		for m in game.marine_roster:
			if typeof(m) == TYPE_DICTIONARY:
				(m as Dictionary)["morale"] = 0.8

		main._adjust_morale(-0.2)
		for c in game.crew_roster:
			if typeof(c) == TYPE_DICTIONARY:
				if not is_equal_approx(float((c as Dictionary).get("morale", 1.0)), 0.6):
					_fail("crew morale did not decrease by 0.2 (got %f)" % float((c as Dictionary).get("morale", 1.0)))
		for m in game.marine_roster:
			if typeof(m) == TYPE_DICTIONARY:
				if not is_equal_approx(float((m as Dictionary).get("morale", 1.0)), 0.6):
					_fail("marine morale did not decrease by 0.2 (got %f)" % float((m as Dictionary).get("morale", 1.0)))

		# +0.5 from 0.6 -> clamps at 1.0.
		main._adjust_morale(0.5)
		for c in game.crew_roster:
			if typeof(c) == TYPE_DICTIONARY:
				if not is_equal_approx(float((c as Dictionary).get("morale", 1.0)), 1.0):
					_fail("crew morale should clamp to 1.0 after +0.5 (got %f)" % float((c as Dictionary).get("morale", 1.0)))

		# -2.0 -> clamps at 0.0.
		main._adjust_morale(-2.0)
		for c in game.crew_roster:
			if typeof(c) == TYPE_DICTIONARY:
				if not is_equal_approx(float((c as Dictionary).get("morale", 1.0)), 0.0):
					_fail("crew morale should clamp to 0.0 after -2.0 (got %f)" % float((c as Dictionary).get("morale", 1.0)))
		for m in game.marine_roster:
			if typeof(m) == TYPE_DICTIONARY:
				if not is_equal_approx(float((m as Dictionary).get("morale", 1.0)), 0.0):
					_fail("marine morale should clamp to 0.0 after -2.0 (got %f)" % float((m as Dictionary).get("morale", 1.0)))

	# d) Morale clamps to [0, 1] after extreme adjustments.
	if not failed:
		main._adjust_morale(5.0)
		for c in game.crew_roster:
			if typeof(c) == TYPE_DICTIONARY:
				var mv: float = float((c as Dictionary).get("morale", 1.0))
				if mv < 0.0 or mv > 1.0:
					_fail("crew morale out of [0,1] range: %f" % mv)
		for m in game.marine_roster:
			if typeof(m) == TYPE_DICTIONARY:
				var mvm: float = float((m as Dictionary).get("morale", 1.0))
				if mvm < 0.0 or mvm > 1.0:
					_fail("marine morale out of [0,1] range: %f" % mvm)

	_finish(main)
