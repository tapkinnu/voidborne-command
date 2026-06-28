extends SceneTree
# Unit tests for scripts/game_state.gd — the Game autoload singleton.
# Covers functions not exercised by existing tests: class_stat, class_info,
# random_name, crew_role_counts, roster_to_save / roster_from_save round-trip,
# rebuild_default_roster, rebuild_default_marine_roster, unassign_crew, and reset.
# Prints GAME_STATE_ROSTER_TEST_PASS on success.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _initialize() -> void:
	var game: Node = root.get_node_or_null("/root/Game")
	if game == null:
		_fail("Game autoload missing")
		quit(1)
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42

	# --- 1. class_stat returns correct values for known classes ---------------
	var fighter_hull: float = game.class_stat("fighter", "hull")
	if fighter_hull != 60.0:
		_fail("class_stat fighter hull should be 60, got %f" % fighter_hull)

	var capital_hull: float = game.class_stat("capital", "hull")
	if capital_hull != 900.0:
		_fail("class_stat capital hull should be 900, got %f" % capital_hull)

	# Unknown class returns 0
	var unknown: float = game.class_stat("battlecruiser", "hull")
	if unknown != 0.0:
		_fail("class_stat unknown class should return 0, got %f" % unknown)

	# Unknown key returns 0
	var unknown_key: float = game.class_stat("fighter", "nonexistent")
	if unknown_key != 0.0:
		_fail("class_stat unknown key should return 0, got %f" % unknown_key)

	# --- 2. class_info returns dict with expected keys -----------------------
	var info: Dictionary = game.class_info("corvette")
	if info.is_empty():
		_fail("class_info('corvette') returned empty dict")
	for key in ["hull", "shield", "energy", "max_speed", "accel", "turn_rate",
			"weapon", "weapon_dmg", "fire_rate", "weapon_range", "crew_needed",
			"garrison", "value", "scale"]:
		if not info.has(key):
			_fail("class_info('corvette') missing key '%s'" % key)

	# Unknown class returns empty
	var unk_info: Dictionary = game.class_info("unknown")
	if not unk_info.is_empty():
		_fail("class_info('unknown') should return empty dict")

	# --- 3. random_name format: "Name-NN" -----------------------------------
	var name1: String = game.random_name(rng)
	if name1.length() < 4 or not name1.contains("-"):
		_fail("random_name format wrong: '%s'" % name1)
	var parts: PackedStringArray = name1.split("-")
	if parts.size() != 2:
		_fail("random_name should have exactly one dash: '%s'" % name1)
	var num_str: String = parts[1]
	if num_str.length() != 2 or not num_str.is_valid_int():
		_fail("random_name suffix should be 2-digit number: '%s'" % name1)
	var num: int = int(num_str)
	if num < 10 or num > 99:
		_fail("random_name number out of range 10..99: %d" % num)

	# Name part comes from FIRST_NAMES
	var first: String = parts[0]
	if not game.FIRST_NAMES.has(first):
		_fail("random_name first part '%s' not in FIRST_NAMES" % first)

	# --- 4. reset restores defaults ------------------------------------------
	game.credits = 999
	game.crew_pool = 99
	game.marine_pool = 99
	game.captured_count = 10
	game.purchased_count = 5
	game.reset()
	if game.credits != 4200:
		_fail("reset credits should be 4200, got %d" % game.credits)
	if game.crew_pool != 3:
		_fail("reset crew_pool should be 3, got %d" % game.crew_pool)
	if game.marine_pool != 6:
		_fail("reset marine_pool should be 6, got %d" % game.marine_pool)
	if game.captured_count != 0:
		_fail("reset captured_count should be 0, got %d" % game.captured_count)
	if game.purchased_count != 0:
		_fail("reset purchased_count should be 0, got %d" % game.purchased_count)
	# After reset, crew_roster size matches crew_pool
	if game.crew_roster.size() != game.crew_pool:
		_fail("reset crew_roster.size() %d != crew_pool %d" % [game.crew_roster.size(), game.crew_pool])
	if game.marine_roster.size() != game.marine_pool:
		_fail("reset marine_roster.size() %d != marine_pool %d" % [game.marine_roster.size(), game.marine_pool])

	# --- 5. crew_role_counts on a fresh roster --------------------------------
	game.reset()
	var counts: Dictionary = game.crew_role_counts()
	# Sum of role counts should equal crew_pool (all unassigned after reset)
	var total: int = int(counts.get("pilot", 0)) + int(counts.get("engineer", 0)) + int(counts.get("gunner", 0))
	if total != game.crew_pool:
		_fail("crew_role_counts total %d != crew_pool %d" % [total, game.crew_pool])
	# All three roles present as keys
	for role in ["pilot", "engineer", "gunner"]:
		if not counts.has(role):
			_fail("crew_role_counts missing key '%s'" % role)

	# --- 6. crew_role_counts excludes assigned crew --------------------------
	game.reset()
	game.assign_best_crew(1)
	var counts2: Dictionary = game.crew_role_counts()
	var total2: int = int(counts2.get("pilot", 0)) + int(counts2.get("engineer", 0)) + int(counts2.get("gunner", 0))
	if total2 != game.crew_pool:
		_fail("crew_role_counts after assign: total %d != crew_pool %d" % [total2, game.crew_pool])

	# --- 7. roster_to_save / roster_from_save round-trip ---------------------
	game.reset()
	# Recruit some extra to have a bigger roster
	for i in range(5):
		game.recruit_crew_member(rng)
	game.assign_best_crew(2, "pilot")
	var saved: Array = game.roster_to_save()
	if saved.size() != game.crew_roster.size():
		_fail("roster_to_save size mismatch: %d vs %d" % [saved.size(), game.crew_roster.size()])

	# Verify saved entries have required fields
	for entry in saved:
		var ed: Dictionary = entry
		for key in ["name", "role", "skill", "morale", "assigned"]:
			if not ed.has(key):
				_fail("roster_to_save entry missing key '%s'" % key)

	# Clear and reload
	var orig_size: int = game.crew_roster.size()
	game.crew_roster.clear()
	game.roster_from_save(saved)
	if game.crew_roster.size() != orig_size:
		_fail("roster_from_save size mismatch: %d vs %d" % [game.crew_roster.size(), orig_size])

	# Verify names round-trip
	var saved_names: Array = []
	for e in saved:
		saved_names.append(String(e["name"]))
	for c in game.crew_roster:
		if not saved_names.has(String(c["name"])):
			_fail("roster_from_save name '%s' not found in saved" % String(c["name"]))

	# --- 8. roster_from_save clamps skill and morale -------------------------
	game.crew_roster.clear()
	var bad_entries: Array = [
		{"name": "OutOfRange", "role": "pilot", "skill": 20, "morale": 2.5, "assigned": false},
		{"name": "Negative", "role": "gunner", "skill": -5, "morale": -1.0, "assigned": false},
	]
	game.roster_from_save(bad_entries)
	if game.crew_roster.size() != 2:
		_fail("roster_from_save should accept 2 entries")
	var c0: Dictionary = game.crew_roster[0]
	if int(c0["skill"]) > 10:
		_fail("roster_from_save should clamp skill to 10, got %d" % int(c0["skill"]))
	if float(c0["morale"]) > 1.0:
		_fail("roster_from_save should clamp morale to 1.0, got %f" % float(c0["morale"]))
	var c1: Dictionary = game.crew_roster[1]
	if int(c1["skill"]) < 1:
		_fail("roster_from_save should clamp skill >= 1, got %d" % int(c1["skill"]))
	if float(c1["morale"]) < 0.0:
		_fail("roster_from_save should clamp morale >= 0.0, got %f" % float(c1["morale"]))

	# --- 9. roster_from_save skips non-dict entries --------------------------
	game.crew_roster.clear()
	game.roster_from_save(["not a dict", 42, null])
	if game.crew_roster.size() != 0:
		_fail("roster_from_save should skip non-dict entries, got %d" % game.crew_roster.size())

	# --- 10. rebuild_default_roster creates N unassigned crew ----------------
	game.crew_roster.clear()
	game.rebuild_default_roster(rng, 5)
	if game.crew_roster.size() != 5:
		_fail("rebuild_default_roster should create 5 crew, got %d" % game.crew_roster.size())
	for c in game.crew_roster:
		var cd: Dictionary = c
		if bool(cd.get("assigned", true)):
			_fail("rebuild_default_roster crew should all be unassigned")
		if not game.CREW_ROLES.has(String(cd.get("role", ""))):
			_fail("rebuild_default_roster crew has invalid role: '%s'" % String(cd.get("role", "")))

	# rebuild_default_roster with 0 count
	game.rebuild_default_roster(rng, 0)
	if game.crew_roster.size() != 0:
		_fail("rebuild_default_roster(0) should create empty roster")

	# --- 11. marine_roster_to_save / marine_roster_from_save round-trip ------
	game.reset()
	for i in range(3):
		game.recruit_marine_member(rng)
	var m_saved: Array = game.marine_roster_to_save()
	if m_saved.size() != game.marine_roster.size():
		_fail("marine_roster_to_save size mismatch")
	for entry in m_saved:
		var md: Dictionary = entry
		for key in ["name", "skill", "morale", "assigned", "wounds"]:
			if not md.has(key):
				_fail("marine_roster_to_save entry missing key '%s'" % key)

	var orig_marine_size: int = game.marine_roster.size()
	game.marine_roster.clear()
	game.marine_roster_from_save(m_saved)
	if game.marine_roster.size() != orig_marine_size:
		_fail("marine_roster_from_save size mismatch: %d vs %d" % [game.marine_roster.size(), orig_marine_size])

	# --- 12. marine_roster_from_save clamps wounds ---------------------------
	game.marine_roster.clear()
	var bad_marines: Array = [
		{"name": "Wounded", "skill": 5, "morale": 0.8, "assigned": false, "wounds": 10},
	]
	game.marine_roster_from_save(bad_marines)
	var m0: Dictionary = game.marine_roster[0]
	if int(m0["wounds"]) > 3:
		_fail("marine_roster_from_save should clamp wounds to 3, got %d" % int(m0["wounds"]))

	# --- 13. rebuild_default_marine_roster creates N unassigned marines ------
	game.marine_roster.clear()
	game.rebuild_default_marine_roster(rng, 4)
	if game.marine_roster.size() != 4:
		_fail("rebuild_default_marine_roster should create 4 marines, got %d" % game.marine_roster.size())
	for m in game.marine_roster:
		var md: Dictionary = m
		if bool(md.get("assigned", true)):
			_fail("rebuild_default_marine_roster marines should all be unassigned")

	# --- 14. unassign_crew returns assigned crew to pool ---------------------
	game.reset()
	var pre_pool: int = game.crew_pool
	var taken: Array = game.assign_best_crew(2)
	if game.crew_pool != pre_pool - 2:
		_fail("assign_best_crew should reduce pool by 2")
	game.unassign_crew(taken)
	if game.crew_pool != pre_pool:
		_fail("unassign_crew should restore pool to %d, got %d" % [pre_pool, game.crew_pool])

	# unassign_crew with non-dict entries (should be safe)
	game.unassign_crew(["not a dict", 42])

	# unassign_crew with already-unassigned crew (no double-count)
	var already_free: Array = game.available_crew()
	game.unassign_crew(already_free)
	if game.crew_pool != pre_pool:
		_fail("unassign_crew should not double-count already-free crew")

	# --- 15. available_crew matches crew_pool --------------------------------
	game.reset()
	var avail: Array = game.available_crew()
	if avail.size() != game.crew_pool:
		_fail("available_crew size %d != crew_pool %d" % [avail.size(), game.crew_pool])

	# --- 16. available_marines matches marine_pool ---------------------------
	game.reset()
	var m_avail: Array = game.available_marines()
	if m_avail.size() != game.marine_pool:
		_fail("available_marines size %d != marine_pool %d" % [m_avail.size(), game.marine_pool])

	# --- 17. assign_best_crew prefers matching role --------------------------
	game.reset()
	# Recruit extra crew with known roles
	for i in range(6):
		game.recruit_crew_member(rng)
	var pilots: Array = game.assign_best_crew(1, "pilot")
	if pilots.size() == 1:
		var p: Dictionary = pilots[0]
		# If any pilot was available, should get one
		var had_pilot: bool = false
		for c in game.crew_roster:
			if String(c.get("role", "")) == "pilot":
				had_pilot = true
				break
		if had_pilot and String(p.get("role", "")) != "pilot":
			_fail("assign_best_crew should prefer matching role 'pilot'")

	# Cleanup
	game.reset()

	if not failed:
		print("GAME_STATE_ROSTER_TEST_PASS")
	quit(1 if failed else 0)
