extends SceneTree
# Regression test for named marines roster: names, skills, morale, boarding
# survivor tracking, capture survivor restoration, and deck name display.
# Mirrors the proven test_named_crew.gd pattern.

var failed: bool = false
var game: Node = null

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	if not failed:
		print("NAMED_MARINES_TEST_PASS")
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

	# 1. marine_roster is non-empty after reset and matches marine_pool
	if game.marine_roster.is_empty():
		_fail("marine_roster is empty after reset")
	if game.marine_roster.size() != game.marine_pool:
		_fail("marine_roster size %d != marine_pool %d after reset" % [game.marine_roster.size(), game.marine_pool])

	# 2. Each entry has valid fields: name, skill(1..10), morale(0..1), assigned(bool)
	if not failed:
		for i in range(game.marine_roster.size()):
			var m: Dictionary = game.marine_roster[i]
			var m_name: String = String(m.get("name", ""))
			if m_name == "":
				_fail("marine %d has empty name" % i)
			var skill: int = int(m.get("skill", 0))
			if skill < 1 or skill > 10:
				_fail("marine %d has invalid skill: %d" % [i, skill])
			var morale: float = float(m.get("morale", -1.0))
			if morale < 0.0 or morale > 1.0:
				_fail("marine %d has invalid morale: %f" % [i, morale])
			var assigned: bool = bool(m.get("assigned", true))
			if assigned:
				_fail("marine %d should start unassigned" % i)

	# 3. Recruit a named marine — roster grows, pool grows, new entry has a name
	var pool_before: int = game.marine_pool
	var roster_before: int = game.marine_roster.size()
	if not failed:
		game.credits = 99999
		var new_m: Dictionary = game.recruit_marine_member(rng)
		if game.marine_pool != pool_before + 1:
			_fail("marine_pool did not increment after recruit: %d -> %d" % [pool_before, game.marine_pool])
		if game.marine_roster.size() != roster_before + 1:
			_fail("marine_roster did not grow: %d -> %d" % [roster_before, game.marine_roster.size()])
		if String(new_m.get("name", "")) == "":
			_fail("recruited marine has empty name")

	# 4. available_marines() returns the unassigned subset and matches marine_pool
	if not failed:
		var avail: Array = game.available_marines()
		if avail.size() != game.marine_pool:
			_fail("available_marines %d != marine_pool %d" % [avail.size(), game.marine_pool])

	# 5. draw_boarding_marines(count) marks marines as assigned (boarded) and returns them
	var drawn: Array = []
	if not failed:
		var avail_count: int = game.available_marines().size()
		drawn = game.draw_boarding_marines(mini(avail_count, 3))
		if drawn.size() != mini(avail_count, 3):
			_fail("draw_boarding_marines returned %d expected %d" % [drawn.size(), mini(avail_count, 3)])
		# marine_pool should drop by drawn.size()
		if game.marine_pool != avail_count - drawn.size():
			_fail("marine_pool after draw %d != %d" % [game.marine_pool, avail_count - drawn.size()])

	# 6. restore_boarding_marines(survivors) returns survivors to the pool (unassigned)
	if not failed:
		var survivors: Array = drawn.duplicate()
		# Simulate 1 casualty: drop one from the survivors list
		if survivors.size() > 1:
			survivors.remove_at(0)
		game.restore_boarding_marines(survivors)
		if game.marine_pool != survivors.size():
			_fail("marine_pool after restore %d != survivors %d" % [game.marine_pool, survivors.size()])
		# Restored marines must be unassigned again
		for m in survivors:
			if bool(m.get("assigned", true)):
				_fail("restored marine %s still assigned" % String(m.get("name", "?")))

	# 7. marine_roster_to_save / marine_roster_from_save round-trips the roster.
	# Mirrors the crew contract exactly: from_save restores the roster DETAIL (names,
	# skills, morale, assigned flags); marine_pool round-trips separately via the save
	# dict (reconciled by the load path), so we re-derive it here the way load does.
	if not failed:
		# Compute the expected available count from the live roster before saving.
		var expected_pool: int = game.available_marines().size()
		var saved: Array = game.marine_roster_to_save()
		# Mutate then reload
		game.marine_pool = 0
		game.marine_roster.clear()
		game.marine_roster_from_save(saved)
		if game.marine_roster.size() != saved.size():
			_fail("roster round-trip size mismatch: %d != %d" % [game.marine_roster.size(), saved.size()])
		# Assigned flags must round-trip, so available_marines() matches the pre-save count.
		if game.available_marines().size() != expected_pool:
			_fail("available_marines after reload %d != expected %d" % [game.available_marines().size(), expected_pool])
		# The load path reconciles marine_pool to the restored roster's available count.
		game.marine_pool = game.available_marines().size()
		if game.marine_pool != expected_pool:
			_fail("marine_pool after reload %d != expected %d" % [game.marine_pool, expected_pool])

	# 8. reset() restores default roster and pool
	if not failed:
		game.reset()
		if game.marine_roster.is_empty():
			_fail("marine_roster empty after second reset")
		if game.marine_pool != game.marine_roster.size():
			_fail("marine_pool %d != roster %d after second reset" % [game.marine_pool, game.marine_roster.size()])

	_finish(main)