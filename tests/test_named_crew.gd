extends SceneTree
# Regression test for named crew roster: roles, skills, morale, and ship stat bonuses.

var failed: bool = false
var game: Node = null

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	if not failed:
		print("NAMED_CREW_TEST_PASS")
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

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	game.reset()

	# 1. Roster is non-empty after reset
	if game.crew_roster.is_empty():
		_fail("crew_roster is empty after reset")

	# 2. Each entry has valid fields
	if not failed:
		for i in range(game.crew_roster.size()):
			var c: Dictionary = game.crew_roster[i]
			var c_name: String = String(c.get("name", ""))
			if c_name == "":
				_fail("crew %d has empty name" % i)
			var role: String = String(c.get("role", ""))
			if role not in ["pilot", "engineer", "gunner"]:
				_fail("crew %d has invalid role: %s" % [i, role])
			var skill: int = int(c.get("skill", 0))
			if skill < 1 or skill > 10:
				_fail("crew %d has invalid skill: %d" % [i, skill])
			var morale: float = float(c.get("morale", -1.0))
			if morale < 0.0 or morale > 1.0:
				_fail("crew %d has invalid morale: %f" % [i, morale])
			var assigned: bool = bool(c.get("assigned", true))
			if assigned:
				_fail("crew %d should be unassigned after reset" % i)

	# 3. crew_pool matches unassigned count
	if not failed:
		var avail: Array = game.available_crew()
		if game.crew_pool != avail.size():
			_fail("crew_pool (%d) != available_crew().size() (%d)" % [game.crew_pool, avail.size()])

	# 4. Recruit increments both roster and pool
	var roster_before: int = game.crew_roster.size()
	var pool_before: int = game.crew_pool
	if not failed:
		game.recruit_crew_member(rng)
		if game.crew_roster.size() != roster_before + 1:
			_fail("roster did not grow by 1 after recruit")
		if game.crew_pool != pool_before + 1:
			_fail("crew_pool did not increment after recruit")

	# 5. Assign crew, apply bonuses, verify stats change
	if not failed:
		var ship_script: Script = load("res://scripts/ship.gd")
		var ship: Node3D = ship_script.new()
		root.add_child(ship)
		ship.setup("corvette", "player", "TestShip")

		var avail2: Array = game.available_crew()
		var found_pilot: bool = false
		for c in avail2:
			if String(c.get("role", "")) == "pilot":
				found_pilot = true
				break
		while not found_pilot:
			var new_c: Dictionary = game.recruit_crew_member(rng)
			if String(new_c.get("role", "")) == "pilot":
				found_pilot = true

		var pool_before_assign: int = game.crew_pool
		var assigned: Array = game.assign_best_crew(1, "pilot")
		if assigned.is_empty():
			_fail("assign_best_crew returned empty")
		else:
			ship.apply_crew_bonuses(assigned)
			if ship.max_speed == ship.base_max_speed:
				_fail("pilot crew did not change max_speed")

		# Pool decreased by exactly the number assigned
		if game.crew_pool != pool_before_assign - assigned.size():
			_fail("crew_pool not correct after assignment (was %d, assign %d, now %d)" % [pool_before_assign, assigned.size(), game.crew_pool])

		# 7. Unassign restores pool
		var pool_after_assign: int = game.crew_pool
		game.unassign_crew(assigned)
		if game.crew_pool != pool_after_assign + assigned.size():
			_fail("crew_pool not restored after unassign")

		if is_instance_valid(ship):
			root.remove_child(ship)
			ship.free()

	_finish(main)
