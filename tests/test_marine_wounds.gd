extends SceneTree
# Regression test for per-marine wound/injury state: wounds field on roster,
# effective-strength reduction, boarding casualty wounding/killing, save/load
# round-trip of wounds, and station-service healing.
# Mirrors the proven test_named_marines.gd pattern.

var failed: bool = false
var game: Node = null

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	if not failed:
		print("MARINE_WOUNDS_TEST_PASS")
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

	# 1. All marines start healthy (wounds == 0) after reset.
	for i in range(game.marine_roster.size()):
		var m: Dictionary = game.marine_roster[i]
		if int(m.get("wounds", -1)) != 0:
			_fail("marine %d not healthy after reset: wounds=%d" % [i, int(m.get("wounds", -1))])

	# 2. Recruited marine starts with wounds == 0.
	if not failed:
		game.credits = 99999
		var new_m: Dictionary = game.recruit_marine_member(rng)
		if int(new_m.get("wounds", -1)) != 0:
			_fail("recruited marine wounds != 0: %d" % int(new_m.get("wounds", -1)))

	# 3. _marine_effective_strength: build a list, wound 2 of them, verify reduced sum.
	if not failed:
		var party: Array = []
		for k in range(4):
			party.append({"wounds": 0})
		# 4 healthy => 4.0 -> 4
		if int(main._marine_effective_strength(party)) != 4:
			_fail("effective strength of 4 healthy != 4: %d" % int(main._marine_effective_strength(party)))
		# Set wounds 1 and 2 on two marines: 0.75 + 0.5 + 1.0 + 1.0 = 3.25 -> round 3
		party[0]["wounds"] = 1
		party[1]["wounds"] = 2
		var es: int = int(main._marine_effective_strength(party))
		if es != 3:
			_fail("effective strength with W1+W2 expected 3, got %d" % es)

	# 4. _apply_boarding_casualties(3) on 4 healthy marines -> 3 marines wounds=1, 0 killed.
	var drawn: Array = []
	if not failed:
		drawn = []
		for k in range(4):
			drawn.append({"name": "M%d" % k, "skill": 5, "morale": 1.0, "assigned": true, "wounds": 0})
		# Add them to roster so kill-removal has something to erase.
		game.marine_roster.clear()
		for d in drawn:
			game.marine_roster.append(d)
		var killed1: int = int(main._apply_boarding_casualties(drawn, 3))
		if killed1 != 0:
			_fail("apply_boarding_casualties(3) killed %d, expected 0" % killed1)
		if drawn.size() != 4:
			_fail("drawn size after 3 casualties %d, expected 4" % drawn.size())
		var w1: int = 0
		for d in drawn:
			if int(d.get("wounds", 0)) == 1:
				w1 += 1
		if w1 != 3:
			_fail("expected 3 marines at wounds=1, got %d" % w1)

	# 5. _apply_boarding_casualties(2) again -> injuries spread lowest-first. Starting from
	#    [1,1,1,0], 2 more hits land on the healthy one then a light one => [2,1,1,1].
	#    So all 4 are now wounded with exactly one at wounds=2 (total wounds = 5), 0 killed.
	if not failed:
		var killed2: int = int(main._apply_boarding_casualties(drawn, 2))
		if killed2 != 0:
			_fail("apply_boarding_casualties(2) second pass killed %d, expected 0" % killed2)
		if drawn.size() != 4:
			_fail("drawn size after second pass %d, expected 4" % drawn.size())
		var w2: int = 0
		var total_w: int = 0
		var healthy: int = 0
		for d in drawn:
			var dw: int = int(d.get("wounds", 0))
			total_w += dw
			if dw == 2:
				w2 += 1
			if dw == 0:
				healthy += 1
		if w2 != 1:
			_fail("expected 1 marine at wounds=2 after spread, got %d" % w2)
		if healthy != 0:
			_fail("expected all 4 marines wounded after spread, %d still healthy" % healthy)
		if total_w != 5:
			_fail("expected total wounds 5 after spread, got %d" % total_w)

	# 6. All at wounds=3 -> next 2 casualties kill 2 marines, drawn shrinks to 2.
	if not failed:
		for d in drawn:
			d["wounds"] = 3
		var killed3: int = int(main._apply_boarding_casualties(drawn, 2))
		if killed3 != 2:
			_fail("apply_boarding_casualties(2) on full-wound party killed %d, expected 2" % killed3)
		if drawn.size() != 2:
			_fail("drawn size after kills %d, expected 2" % drawn.size())

	# 7. wounds round-trip through save/load.
	if not failed:
		game.reset()
		game.marine_roster[0]["wounds"] = 1
		game.marine_roster[1]["wounds"] = 3
		var saved: Array = game.marine_roster_to_save()
		game.marine_roster.clear()
		game.marine_roster_from_save(saved)
		if int(game.marine_roster[0].get("wounds", -1)) != 1:
			_fail("wounds[0] did not round-trip: %d" % int(game.marine_roster[0].get("wounds", -1)))
		if int(game.marine_roster[1].get("wounds", -1)) != 3:
			_fail("wounds[1] did not round-trip: %d" % int(game.marine_roster[1].get("wounds", -1)))

	# 7b. Old save without "wounds" defaults to 0.
	if not failed:
		var legacy: Array = [{"name": "Old", "skill": 5, "morale": 1.0, "assigned": false}]
		game.marine_roster_from_save(legacy)
		if int(game.marine_roster[0].get("wounds", -1)) != 0:
			_fail("legacy marine wounds default != 0: %d" % int(game.marine_roster[0].get("wounds", -1)))

	# 8. Station service heals wounds back to 0.
	if not failed:
		game.reset()
		game.marine_roster[0]["wounds"] = 2
		game.marine_roster[1]["wounds"] = 1
		main._heal_marines_at_station("Test Dock")
		var any_wounded: bool = false
		for m in game.marine_roster:
			if int(m.get("wounds", 0)) > 0:
				any_wounded = true
		if any_wounded:
			_fail("marines still wounded after station heal")

	_finish(main)
