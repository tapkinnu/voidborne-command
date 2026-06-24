extends SceneTree
# Broader unit tests for damage/boarding/economy state transitions. Exercises edge
# cases in the damage model (shield absorption, disable threshold, subsystem splits,
# offline/penalty multipliers), boarding flow (guards, range, auto-capture, round
# resolution), and economy (recruit, buy, salvage/bounty ratios), plus cross-system
# invariants.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _approx(a: float, b: float, eps: float = 0.005) -> bool:
	return abs(a - b) <= eps

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
	s.shield = 0.0
	s.hull = s.max_hull
	s.destroyed = false
	s.disabled = false
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

	var player: Node3D = main.get("player")
	if player == null:
		_fail("player ship missing")
		quit(1)
		return

	# ===================================================================
	# 1. DAMAGE MODEL EDGE CASES
	# ===================================================================

	if not failed:
		# 1a) Shield absorbs exactly all damage
		var s1: Node3D = _find_by_class(main, "fighter", "hostile")
		if s1 == null:
			_fail("no hostile fighter for shield-absorb test")
		else:
			s1.set("shield", 30.0)
			s1.set("hull", 60.0)
			s1.set("max_hull", 60.0)
			var r1: Dictionary = s1.call("take_damage", 30.0, "")
			if float(s1.shield) != 0.0:
				_fail("shield not depleted on exact hit")
			if float(s1.hull) != 60.0:
				_fail("hull changed when shield absorbed exact damage")
			if not bool(r1.get("shield_hit", false)):
				_fail("shield_hit not set on shield absorption")
			if bool(r1.get("disabled", false)):
				_fail("disabled set when shield absorbed all damage")
			if bool(r1.get("destroyed", false)):
				_fail("destroyed set when shield absorbed all damage")

	if not failed:
		# 1b) Overkill damage: shield=10, deal 100 to max_hull=60 ship
		var s2: Node3D = _find_by_class(main, "fighter", "hostile")
		if s2 == null:
			_fail("no hostile fighter for overkill test")
		else:
			s2.set("shield", 10.0)
			s2.set("hull", 60.0)
			s2.set("max_hull", 60.0)
			var r2: Dictionary = s2.call("take_damage", 100.0, "")
			if float(s2.shield) != 0.0:
				_fail("shield not zeroed on overkill")
			if float(s2.hull) != 0.0:
				_fail("hull not zeroed on overkill")
			if not bool(r2.get("destroyed", false)):
				_fail("destroyed not set on overkill")

	if not failed:
		# 1c) Subsystem 50/50 split: shield=0, deal 20 subsystem=engines, max_hull=100
		var s3: Node3D = _find_by_class(main, "fighter", "hostile")
		if s3 == null:
			_fail("no hostile fighter for subsystem split test")
		else:
			s3.set("shield", 0.0)
			s3.set("hull", 100.0)
			s3.set("max_hull", 100.0)
			s3.set("sub_engine", 1.0)
			s3.set("disabled", false)
			s3.set("destroyed", false)
			var r3: Dictionary = s3.call("take_damage", 20.0, "engines")
			if not _approx(float(s3.hull), 90.0, 0.01):
				_fail("subsystem split hull wrong: got %f expected 90.0" % float(s3.hull))
			if not _approx(float(s3.sub_engine), 0.8, 0.01):
				_fail("sub_engine damage wrong: got %f expected 0.8" % float(s3.sub_engine))
			if not bool(r3.get("subsystem_hit", false)):
				_fail("subsystem_hit not set on focused damage")

	if not failed:
		# 1d) Disable threshold exact: 22% of max_hull
		var s4a: Node3D = _find_by_class(main, "fighter", "hostile")
		if s4a == null:
			_fail("no hostile fighter for disable threshold test")
		else:
			s4a.set("shield", 0.0)
			s4a.set("hull", 100.0)
			s4a.set("max_hull", 100.0)
			s4a.set("disabled", false)
			s4a.set("destroyed", false)
			var r4a: Dictionary = s4a.call("take_damage", 78.0, "")
			if float(s4a.hull) != 22.0:
				_fail("disable threshold hull wrong: got %f expected 22.0" % float(s4a.hull))
			if not bool(r4a.get("disabled", false)):
				_fail("disabled not set at threshold (22/100)")
			if bool(r4a.get("destroyed", false)):
				_fail("destroyed set at disable threshold")

	if not failed:
		var s4b: Node3D = _find_by_class(main, "fighter", "hostile")
		if s4b == null:
			_fail("no hostile fighter for below-threshold test")
		else:
			s4b.set("shield", 0.0)
			s4b.set("hull", 100.0)
			s4b.set("max_hull", 100.0)
			s4b.set("disabled", false)
			s4b.set("destroyed", false)
			var r4b: Dictionary = s4b.call("take_damage", 77.0, "")
			if bool(r4b.get("disabled", false)):
				_fail("disabled set when hull=23 (>22% of 100)")

	if not failed:
		# 1e) Disable halves garrison
		var s5: Node3D = _find_by_class(main, "frigate", "hostile")
		if s5 == null:
			_fail("no hostile frigate for garrison halving test")
		else:
			s5.set("shield", 0.0)
			s5.set("marine_garrison", 8)
			_disable_ship(s5)
			if not bool(s5.disabled):
				_fail("frigate not disabled by 80% hull damage")
			if int(s5.marine_garrison) != 4:
				_fail("garrison halving failed: got %d expected 4" % int(s5.marine_garrison))

	if not failed:
		# 1f) Destroyed ships can't take more damage
		var s6: Node3D = _find_by_class(main, "fighter", "hostile")
		if s6 == null:
			_fail("no hostile fighter for destroyed-noop test")
		else:
			s6.set("destroyed", true)
			s6.set("hull", 0.0)
			s6.set("max_hull", 60.0)
			var r6: Dictionary = s6.call("take_damage", 50.0, "")
			if bool(r6.get("shield_hit", false)):
				_fail("destroyed ship registered shield_hit")
			if bool(r6.get("disabled", false)):
				_fail("destroyed ship registered disabled")
			if bool(r6.get("destroyed", false)):
				_fail("destroyed ship registered destroyed again")
			if bool(r6.get("subsystem_hit", false)):
				_fail("destroyed ship registered subsystem_hit")
			if float(s6.hull) != 0.0:
				_fail("destroyed ship hull changed")

	if not failed:
		# 1g) Weapons subsystem: OFFLINE blocks firing, DAMAGED doubles cooldown
		var s7: Node3D = _find_by_class(main, "fighter", "hostile")
		if s7 == null:
			_fail("no hostile fighter for weapon subsystem test")
		else:
			s7.set("sub_weapon", 0.0)
			if bool(s7.call("can_fire")):
				_fail("can_fire true with sub_weapon=0 (OFFLINE)")
			s7.set("sub_weapon", 0.3)
			if not bool(s7.call("can_fire")):
				_fail("can_fire false with sub_weapon=0.3 (DAMAGED)")
			if not _approx(float(s7.call("weapon_cd_mult")), 2.0, 0.01):
				_fail("weapon_cd_mult not 2.0 for DAMAGED weapons")
			s7.set("sub_weapon", 1.0)
			if not bool(s7.call("can_fire")):
				_fail("can_fire false with sub_weapon=1.0 (OK)")
			if not _approx(float(s7.call("weapon_cd_mult")), 1.0, 0.01):
				_fail("weapon_cd_mult not 1.0 for OK weapons")

	if not failed:
		# 1h) Shield regen multiplier
		var s8: Node3D = _find_by_class(main, "fighter", "hostile")
		if s8 == null:
			_fail("no hostile fighter for shield regen test")
		else:
			s8.set("sub_shield", 0.0)
			if not _approx(float(s8.call("shield_regen_mult")), 0.0, 0.01):
				_fail("shield_regen_mult not 0.0 at sub_shield=0")
			s8.set("sub_shield", 0.3)
			if not _approx(float(s8.call("shield_regen_mult")), 0.3, 0.01):
				_fail("shield_regen_mult not 0.3 at sub_shield=0.3")
			s8.set("sub_shield", 1.0)
			if not _approx(float(s8.call("shield_regen_mult")), 1.0, 0.01):
				_fail("shield_regen_mult not 1.0 at sub_shield=1.0")

	if not failed:
		# 1i) Engine speed/turn multipliers
		var s9: Node3D = _find_by_class(main, "fighter", "hostile")
		if s9 == null:
			_fail("no hostile fighter for engine mult test")
		else:
			var base_speed: float = float(s9.max_speed)
			var base_turn: float = float(s9.turn_rate)
			s9.set("sub_engine", 0.0)
			if not _approx(float(s9.call("eff_max_speed")), base_speed * 0.2, 0.5):
				_fail("eff_max_speed wrong at sub_engine=0: got %f expected %f" % [float(s9.call("eff_max_speed")), base_speed * 0.2])
			if not _approx(float(s9.call("eff_turn_rate")), base_turn * 0.4, 0.1):
				_fail("eff_turn_rate wrong at sub_engine=0")
			s9.set("sub_engine", 0.3)
			if not _approx(float(s9.call("eff_max_speed")), base_speed * 0.6, 0.5):
				_fail("eff_max_speed wrong at sub_engine=0.3")
			if not _approx(float(s9.call("eff_turn_rate")), base_turn * 0.7, 0.1):
				_fail("eff_turn_rate wrong at sub_engine=0.3")
			s9.set("sub_engine", 1.0)
			if not _approx(float(s9.call("eff_max_speed")), base_speed * 1.0, 0.5):
				_fail("eff_max_speed wrong at sub_engine=1.0")
			if not _approx(float(s9.call("eff_turn_rate")), base_turn * 1.0, 0.1):
				_fail("eff_turn_rate wrong at sub_engine=1.0")

	# ===================================================================
	# 2. BOARDING STATE TRANSITIONS
	# ===================================================================

	if not failed:
		# 2a) Boarding requires disabled target
		var ba1: Node3D = _find_by_class(main, "corvette", "hostile")
		if ba1 == null:
			_fail("no hostile corvette for boarding disabled check")
		else:
			main.set("target", ba1)
			game.set("marine_pool", 5)
			main.call("_try_start_boarding")
			if bool(main.get("boarding_active")):
				_fail("boarding started on non-disabled target")

	if not failed:
		# 2b) Boarding requires marines (marine_pool > 0)
		var ba2: Node3D = _find_by_class(main, "corvette", "hostile")
		if ba2 == null:
			_fail("no hostile corvette for boarding marines check")
		else:
			if not bool(ba2.disabled):
				_disable_ship(ba2)
			if not bool(ba2.disabled):
				_fail("corvette should be disabled for marines check")
			main.set("target", ba2)
			game.set("marine_pool", 0)
			main.call("_try_start_boarding")
			if bool(main.get("boarding_active")):
				_fail("boarding started with marine_pool=0")

	if not failed:
		# 2c) Boarding requires proximity (<=90 units)
		var ba3: Node3D = _find_by_class(main, "fighter", "hostile")
		if ba3 == null:
			_fail("no hostile fighter for proximity check")
		else:
			ba3.global_position = player.global_position + Vector3(0, 0, 200)
			_disable_ship(ba3)
			if not bool(ba3.disabled):
				_fail("fighter should be disabled for proximity check")
			main.set("target", ba3)
			game.set("marine_pool", 5)
			main.call("_try_start_boarding")
			if bool(main.get("boarding_active")):
				_fail("boarding started on target >90 units away")

	if not failed:
		# 2d) Boarding starts correctly: disabled, in range, marines > 0
		var ba4: Node3D = _find_by_name(main, "Ironclaw")
		if ba4 == null:
			_fail("no Ironclaw for boarding start test")
		else:
			_disable_ship(ba4)
			if not bool(ba4.disabled):
				_fail("Ironclaw should be disabled")
			ba4.global_position = player.global_position + Vector3(0, 0, -10)
			game.set("marine_pool", 8)
			main.set("target", ba4)
			main.call("_try_start_boarding")
			if not bool(main.get("boarding_active")):
				_fail("boarding did not start on valid disabled target")
			if int(main.get("boarding_attacker_strength")) != 8:
				_fail("boarding attacker strength %d != 8" % int(main.get("boarding_attacker_strength")))
			if int(main.get("boarding_defender_strength")) != 2:
				_fail("boarding defender strength %d != 2 (Ironclaw 4 halved to 2)" % int(main.get("boarding_defender_strength")))
			main.call("_cancel_boarding")

	if not failed:
		# 2e) Undefended target auto-captures (marine_garrison=0)
		var ba5: Node3D = _find_by_class(main, "fighter", "hostile")
		if ba5 == null:
			_fail("no hostile fighter for auto-capture test")
		else:
			_disable_ship(ba5)
			if not bool(ba5.disabled):
				_fail("fighter should be disabled for auto-capture")
			ba5.global_position = player.global_position + Vector3(0, 0, -10)
			ba5.set("marine_garrison", 0)
			game.set("marine_pool", 3)
			main.set("target", ba5)
			var before_cap: int = int(game.get("captured_count"))
			main.call("_try_start_boarding")
			if String(ba5.faction) != "player":
				_fail("undefended target did not auto-capture (faction %s)" % String(ba5.faction))
			if int(game.get("captured_count")) != before_cap + 1:
				_fail("auto-capture did not increment captured_count")

	if not failed:
		# 2f) Boarding abort on range drift (>120 units)
		var ba6: Node3D = _find_by_name(main, "Ironclaw")
		if ba6 == null:
			_fail("no Ironclaw for range drift test")
		else:
			if not bool(ba6.disabled):
				_disable_ship(ba6)
			ba6.global_position = player.global_position + Vector3(0, 0, -10)
			game.set("marine_pool", 5)
			main.set("target", ba6)
			main.call("_try_start_boarding")
			if not bool(main.get("boarding_active")):
				_fail("boarding should have started before drift")
			ba6.global_position = Vector3(0, 0, 300)
			main.call("_update_boarding", 0.6)
			if bool(main.get("boarding_active")):
				_fail("boarding did not cancel on range drift")

	if not failed:
		# 2g) Boarding round count increments
		var ba7: Node3D = _find_by_class(main, "capital", "hostile")
		if ba7 == null:
			_fail("no hostile capital for boarding round test")
		else:
			_disable_ship(ba7)
			ba7.global_position = player.global_position + Vector3(0, 0, -10)
			game.set("marine_pool", 10)
			main.set("target", ba7)
			main.call("_try_start_boarding")
			if not bool(main.get("boarding_active")):
				_fail("boarding should have started for round test")
			main.call("_update_boarding", 0.6)
			if int(main.get("boarding_round_count")) < 1:
				_fail("boarding round count not incremented after one interval")
			main.call("_cancel_boarding")

	if not failed:
		# 2h) Boarding capture path: attackers outnumber and win
		var ba8: Node3D = _find_by_class(main, "corvette", "hostile")
		if ba8 == null:
			_fail("no hostile corvette for capture path test")
		else:
			if not bool(ba8.disabled):
				_disable_ship(ba8)
			ba8.global_position = player.global_position + Vector3(0, 0, -10)
			game.set("marine_pool", 10)
			main.set("target", ba8)
			var before_cap2: int = int(game.get("captured_count"))
			var before_marines: int = int(game.get("marine_pool"))
			main.call("_try_start_boarding")
			if not bool(main.get("boarding_active")):
				_fail("boarding should have started for capture path")
			var guard: int = 0
			while bool(main.get("boarding_active")) and guard < 100:
				main.call("_update_boarding", 2.0)
				guard += 1
			if guard >= 100:
				_fail("boarding capture never resolved (stalemate)")
			if String(ba8.faction) != "player":
				_fail("captured ship did not switch to player faction")
			if int(game.get("captured_count")) != before_cap2 + 1:
				_fail("successful boarding did not increment captured_count")
			var after_marines: int = int(game.get("marine_pool"))
			if after_marines <= 0:
				_fail("no marine survivors after capture")
			if after_marines >= before_marines:
				_fail("marine pool not reduced by casualties")

	# ===================================================================
	# 3. ECONOMY STATE TRANSITIONS
	# ===================================================================

	if not failed:
		# 3a) Recruit crew when broke (credits < COST_CREW)
		game.set("credits", 50)
		var before_crew: int = int(game.get("crew_pool"))
		var before_cr: int = int(game.get("credits"))
		main.call("_recruit", "crew", true)
		if int(game.get("crew_pool")) != before_crew:
			_fail("crew pool changed on broke recruit")
		if int(game.get("credits")) != before_cr:
			_fail("credits changed on broke recruit")

	if not failed:
		# 3b) Recruit crew succeeds
		game.set("credits", 500)
		var before_crew2: int = int(game.get("crew_pool"))
		main.call("_recruit", "crew", true)
		if int(game.get("credits")) != 500 - 120:
			_fail("recruit crew didn't deduct %d (got %d)" % [120, int(game.get("credits"))])
		if int(game.get("crew_pool")) != before_crew2 + 1:
			_fail("recruit crew didn't increase pool by 1")

	if not failed:
		# 3c) Recruit marine succeeds
		game.set("credits", 500)
		var before_marine: int = int(game.get("marine_pool"))
		main.call("_recruit", "marine", true)
		if int(game.get("credits")) != 500 - 180:
			_fail("recruit marine didn't deduct %d (got %d)" % [180, int(game.get("credits"))])
		if int(game.get("marine_pool")) != before_marine + 1:
			_fail("recruit marine didn't increase pool by 1")

	if not failed:
		# 3d) Recruit away from station (near_station=false)
		game.set("credits", 500)
		var before_c3: int = int(game.get("crew_pool"))
		var before_cr3: int = int(game.get("credits"))
		main.call("_recruit", "crew", false)
		if int(game.get("crew_pool")) != before_c3:
			_fail("crew pool changed on away recruit")
		if int(game.get("credits")) != before_cr3:
			_fail("credits changed on away recruit")

	if not failed:
		# 3e) Buy ship when broke (credits < ship cost)
		game.set("credits", 100)
		var before_purch: int = int(game.get("purchased_count"))
		var before_ships: int = main.ships.size()
		main.call("_buy_ship", true)
		if int(game.get("credits")) != 100:
			_fail("credits changed on broke buy")
		if int(game.get("purchased_count")) != before_purch:
			_fail("purchased_count changed on broke buy")
		if main.ships.size() != before_ships:
			_fail("ship added on broke buy")

	if not failed:
		# 3f) Buy ship succeeds
		game.set("credits", 10000)
		var before_purch2: int = int(game.get("purchased_count"))
		var before_ships2: int = main.ships.size()
		main.call("_buy_ship", true)
		if int(game.get("credits")) >= 10000:
			_fail("credits not decreased after buy")
		if int(game.get("purchased_count")) != before_purch2 + 1:
			_fail("purchased_count not incremented")
		if main.ships.size() != before_ships2 + 1:
			_fail("new ship not in fleet after buy")
		var found_new: bool = false
		for s in main.ships:
			if is_instance_valid(s) and String(s.faction) == "player" and not s.is_player:
				found_new = true
				break
		if not found_new:
			_fail("no player-faction non-flagship found after buy")

	if not failed:
		# 3g) Crew pool invariant: crew_pool == available_crew().size()
		var pool_val: int = int(game.get("crew_pool"))
		var avail: Array = game.call("available_crew")
		var avail_size: int = avail.size()
		if pool_val != avail_size:
			_fail("crew pool invariant broken: pool=%d available=%d" % [pool_val, avail_size])

	if not failed:
		# 3h) Credits never go negative
		if int(game.get("credits")) < 0:
			_fail("credits went negative")

	if not failed:
		# 3i) Destroy salvage reward
		var loot_target: Node3D = main.call("_spawn_ship", "fighter", "hostile", "LootTest", Vector3(0, 0, 300))
		if not is_instance_valid(loot_target):
			_fail("could not spawn salvage test ship")
		else:
			var salvage_expected: int = int(main.call("_destroy_salvage_reward", loot_target))
			game.set("credits", 0)
			main.call("_destroy_ship", loot_target)
			await process_frame
			var credits_after: int = int(game.get("credits"))
			if credits_after < 40:
				_fail("destroy salvage %d < MIN_DESTROY_SALVAGE 40" % credits_after)
			if credits_after != salvage_expected:
				_fail("destroy salvage %d != expected %d" % [credits_after, salvage_expected])

	if not failed:
		# 3j) Capture bounty > destroy salvage for the same class
		var cmp: Node3D = _find_by_class(main, "fighter", "hostile")
		if cmp == null:
			_fail("no hostile fighter for bounty comparison")
		else:
			var cap_rew: int = int(main.call("_capture_credit_reward", cmp))
			var des_rew: int = int(main.call("_destroy_salvage_reward", cmp))
			if cap_rew <= des_rew:
				_fail("capture bounty %d not > destroy salvage %d" % [cap_rew, des_rew])

	# ===================================================================
	# 4. CROSS-SYSTEM INVARIANT CHECKS
	# ===================================================================

	if not failed:
		# 4a) Disabled ships remain in ships array
		var inv1: Node3D = _find_by_class(main, "frigate", "hostile")
		if inv1 == null:
			_fail("no hostile frigate for disabled-remains test")
		else:
			if not bool(inv1.disabled):
				_disable_ship(inv1)
			if not bool(inv1.disabled):
				_fail("frigate not disabled for remains check")
			var found: bool = false
			for s in main.ships:
				if s == inv1:
					found = true
					break
			if not found:
				_fail("disabled ship removed from ships array")

	if not failed:
		# 4b) Destroyed ships removed from ships array
		var inv2: Node3D = _find_by_class(main, "fighter", "hostile")
		if inv2 == null:
			_fail("no hostile fighter for destroyed-removed test")
		else:
			main.call("_destroy_ship", inv2)
			await process_frame
			var found_des: bool = false
			for s in main.ships:
				if s == inv2:
					found_des = true
					break
			if found_des:
				_fail("destroyed ship still in ships array")

	if not failed:
		# 4c) Stale target clearing: other ships' target cleared after destroy
		var inv3: Node3D = _find_by_class(main, "frigate", "hostile")
		var inv4: Node3D = _find_by_class(main, "fighter", "hostile")
		if inv3 == null or inv4 == null:
			_fail("need hostile frigate and fighter for stale target test")
		else:
			inv3.set("target", inv4)
			main.call("_destroy_ship", inv4)
			await process_frame
			if is_instance_valid(inv3.target):
				_fail("stale target not cleared after destruction")

	if not failed:
		# 4d) Faction switch on capture: captured ship switches to player, hull restored
		var inv5: Node3D = _find_by_class(main, "fighter", "hostile")
		if inv5 == null:
			_fail("no hostile fighter for faction switch test")
		else:
			_disable_ship(inv5)
			inv5.set("marine_garrison", 0)
			inv5.global_position = player.global_position + Vector3(0, 0, -10)
			game.set("marine_pool", 5)
			main.set("target", inv5)
			main.call("_try_start_boarding")
			# Auto-capture path: undefended (garrison=0) ships capture instantly
			if String(inv5.faction) != "player":
				_fail("captured ship faction is %s, expected player" % String(inv5.faction))
			if float(inv5.hull) < float(inv5.max_hull) * 0.4 - 0.01:
				_fail("captured hull %f not restored to >= 40%% of max_hull %f" % [float(inv5.hull), float(inv5.max_hull)])
			if bool(inv5.disabled):
				_fail("captured ship should not be disabled after capture")

	# ===================================================================
	# DONE
	# ===================================================================
	if not failed:
		print("STATE_TRANSITION_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
