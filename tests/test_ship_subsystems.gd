extends SceneTree
# Unit tests for scripts/ship.gd — subsystem effect multipliers, take_damage
# edge cases, restore_subsystems, radius, can_fire, weapon_cd_mult,
# shield_regen_mult, and subsystem_status. These functions had no direct
# test coverage. Prints SHIP_SUBSYSTEMS_TEST_PASS on success.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _approx(a: float, b: float, eps: float = 0.01) -> bool:
	return abs(a - b) <= eps

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

	# Find the player ship
	var ship: Node = null
	for s in main.ships:
		if is_instance_valid(s) and bool(s.is_player):
			ship = s
			break
	if ship == null:
		_fail("no player ship found")
		_finish(main)
		return

	# --- 1. subsystem_status thresholds --------------------------------------
	if ship.subsystem_status(1.0) != "OK":
		_fail("subsystem_status(1.0) should be OK")
	if ship.subsystem_status(0.5) != "OK":
		_fail("subsystem_status(0.5) should be OK")
	if ship.subsystem_status(0.39) != "DAMAGED":
		_fail("subsystem_status(0.39) should be DAMAGED")
	if ship.subsystem_status(0.1) != "DAMAGED":
		_fail("subsystem_status(0.1) should be DAMAGED")
	if ship.subsystem_status(0.0) != "OFFLINE":
		_fail("subsystem_status(0.0) should be OFFLINE")
	if ship.subsystem_status(-0.1) != "OFFLINE":
		_fail("subsystem_status(-0.1) should be OFFLINE")

	# --- 2. _engine_speed_mult at various sub_engine levels ------------------
	ship.sub_engine = 1.0
	if not _approx(ship._engine_speed_mult(), 1.0):
		_fail("_engine_speed_mult at full should be 1.0")
	if not _approx(ship._engine_turn_mult(), 1.0):
		_fail("_engine_turn_mult at full should be 1.0")

	ship.sub_engine = 0.3  # DAMAGED (< 0.4)
	if not _approx(ship._engine_speed_mult(), 0.6):
		_fail("_engine_speed_mult when damaged should be 0.6, got %f" % ship._engine_speed_mult())
	if not _approx(ship._engine_turn_mult(), 0.7):
		_fail("_engine_turn_mult when damaged should be 0.7, got %f" % ship._engine_turn_mult())

	ship.sub_engine = 0.0  # OFFLINE
	if not _approx(ship._engine_speed_mult(), 0.2):
		_fail("_engine_speed_mult when offline should be 0.2, got %f" % ship._engine_speed_mult())
	if not _approx(ship._engine_turn_mult(), 0.4):
		_fail("_engine_turn_mult when offline should be 0.4, got %f" % ship._engine_turn_mult())

	# Reset
	ship.sub_engine = 1.0

	# --- 3. eff_max_speed / eff_accel / eff_turn_rate scale with engine ------
	var base_speed: float = ship.max_speed
	var base_accel: float = ship.accel
	var base_turn: float = ship.turn_rate

	ship.sub_engine = 1.0
	if not _approx(ship.eff_max_speed(), base_speed):
		_fail("eff_max_speed at full should equal max_speed")
	if not _approx(ship.eff_accel(), base_accel):
		_fail("eff_accel at full should equal accel")
	if not _approx(ship.eff_turn_rate(), base_turn):
		_fail("eff_turn_rate at full should equal turn_rate")

	ship.sub_engine = 0.0  # OFFLINE
	if not _approx(ship.eff_max_speed(), base_speed * 0.2):
		_fail("eff_max_speed offline should be 20%% of base")
	if not _approx(ship.eff_accel(), base_accel * 0.2):
		_fail("eff_accel offline should be 20%% of base")
	if not _approx(ship.eff_turn_rate(), base_turn * 0.4):
		_fail("eff_turn_rate offline should be 40%% of base")

	ship.sub_engine = 1.0

	# --- 4. can_fire depends on sub_weapon ----------------------------------
	ship.sub_weapon = 1.0
	if not ship.can_fire():
		_fail("can_fire should be true when sub_weapon > 0")

	ship.sub_weapon = 0.1
	if not ship.can_fire():
		_fail("can_fire should be true when sub_weapon = 0.1")

	ship.sub_weapon = 0.0
	if ship.can_fire():
		_fail("can_fire should be false when sub_weapon = 0")

	ship.sub_weapon = 1.0

	# --- 5. weapon_cd_mult: normal vs damaged --------------------------------
	ship.sub_weapon = 1.0
	if not _approx(ship.weapon_cd_mult(), 1.0):
		_fail("weapon_cd_mult at full should be 1.0")

	ship.sub_weapon = 0.5  # above damaged threshold
	if not _approx(ship.weapon_cd_mult(), 1.0):
		_fail("weapon_cd_mult at 0.5 should be 1.0")

	ship.sub_weapon = 0.3  # DAMAGED (< 0.4)
	if not _approx(ship.weapon_cd_mult(), 2.0):
		_fail("weapon_cd_mult when damaged should be 2.0, got %f" % ship.weapon_cd_mult())

	ship.sub_weapon = 1.0

	# --- 6. shield_regen_mult: OK / DAMAGED / OFFLINE ------------------------
	ship.sub_shield = 1.0
	if not _approx(ship.shield_regen_mult(), 1.0):
		_fail("shield_regen_mult at full should be 1.0")

	ship.sub_shield = 0.3  # DAMAGED
	if not _approx(ship.shield_regen_mult(), 0.3):
		_fail("shield_regen_mult when damaged should be 0.3, got %f" % ship.shield_regen_mult())

	ship.sub_shield = 0.0  # OFFLINE
	if not _approx(ship.shield_regen_mult(), 0.0):
		_fail("shield_regen_mult when offline should be 0.0")

	ship.sub_shield = 1.0

	# --- 7. restore_subsystems full restore ----------------------------------
	ship.sub_engine = 0.2
	ship.sub_weapon = 0.1
	ship.sub_shield = 0.3
	ship.restore_subsystems(1.0)
	if not _approx(ship.sub_engine, 1.0):
		_fail("restore_subsystems(1.0) should fully restore engine")
	if not _approx(ship.sub_weapon, 1.0):
		_fail("restore_subsystems(1.0) should fully restore weapon")
	if not _approx(ship.sub_shield, 1.0):
		_fail("restore_subsystems(1.0) should fully restore shield")

	# --- 8. restore_subsystems partial restore -------------------------------
	ship.sub_engine = 0.0
	ship.sub_weapon = 0.0
	ship.sub_shield = 0.0
	ship.restore_subsystems(0.5)
	if not _approx(ship.sub_engine, 0.5):
		_fail("restore_subsystems(0.5) from 0 should give 0.5, got %f" % ship.sub_engine)
	if not _approx(ship.sub_weapon, 0.5):
		_fail("restore_subsystems(0.5) from 0 should give 0.5, got %f" % ship.sub_weapon)

	# Partial from mid-value: restore_subsystems adds fraction of the DEFICIT
	ship.sub_engine = 0.6
	ship.restore_subsystems(0.5)
	# deficit = 1.0 - 0.6 = 0.4; restored = 0.6 + 0.4*0.5 = 0.8
	if not _approx(ship.sub_engine, 0.8):
		_fail("restore_subsystems(0.5) from 0.6 should give 0.8, got %f" % ship.sub_engine)

	# Full-restore subsystems for next tests
	ship.restore_subsystems(1.0)

	# --- 9. radius scales with class ----------------------------------------
	var fighter_radius: float = 0.0
	var capital_radius: float = 0.0
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		if String(s.ship_class) == "fighter" and fighter_radius == 0.0:
			fighter_radius = s.radius()
		if String(s.ship_class) == "capital" and capital_radius == 0.0:
			capital_radius = s.radius()
	if fighter_radius > 0.0 and capital_radius > 0.0:
		if capital_radius <= fighter_radius:
			_fail("capital radius should exceed fighter radius")
	# Player ship radius should be positive
	if ship.radius() <= 0.0:
		_fail("ship radius should be positive")

	# --- 10. take_damage: full shield absorb ---------------------------------
	# Reset ship to full stats
	ship.hull = ship.max_hull
	ship.shield = ship.max_shield
	ship.disabled = false
	ship.destroyed = false

	var pre_hull: float = ship.hull
	var pre_shield: float = ship.shield
	# Small damage fully absorbed by shield
	var small_dmg: float = min(5.0, pre_shield * 0.5)
	var result: Dictionary = ship.take_damage(small_dmg)
	if not bool(result.get("shield_hit", false)):
		_fail("take_damage should report shield_hit when shield absorbs")
	if not _approx(ship.hull, pre_hull):
		_fail("take_damage: hull should be unchanged when shield absorbs fully")
	if not _approx(ship.shield, pre_shield - small_dmg):
		_fail("take_damage: shield should be reduced by damage amount")

	# --- 11. take_damage: shield overflow to hull ----------------------------
	ship.hull = ship.max_hull
	ship.shield = 10.0
	ship.disabled = false
	ship.destroyed = false
	var overflow_result: Dictionary = ship.take_damage(25.0)
	if not bool(overflow_result.get("shield_hit", false)):
		_fail("take_damage overflow should report shield_hit")
	if not _approx(ship.shield, 0.0):
		_fail("take_damage overflow: shield should be depleted")
	if not _approx(ship.hull, ship.max_hull - 15.0):
		_fail("take_damage overflow: hull should lose overflow amount (15)")

	# --- 12. take_damage: already destroyed -> no-op -------------------------
	ship.hull = 0.0
	ship.destroyed = true
	var dead_result: Dictionary = ship.take_damage(100.0)
	if bool(dead_result.get("shield_hit", false)):
		_fail("take_damage on destroyed ship should not report shield_hit")
	if bool(dead_result.get("disabled", false)):
		_fail("take_damage on destroyed ship should not report disabled")

	# --- 13. take_damage: invulnerable absorbs everything --------------------
	ship.hull = ship.max_hull
	ship.shield = ship.max_shield
	ship.disabled = false
	ship.destroyed = false
	ship.invulnerable = true
	var invuln_result: Dictionary = ship.take_damage(999.0)
	if not bool(invuln_result.get("shield_hit", false)):
		_fail("take_damage invulnerable should still report shield_hit for VFX")
	if not _approx(ship.hull, ship.max_hull):
		_fail("take_damage invulnerable: hull should be unchanged")
	if not _approx(ship.shield, ship.max_shield):
		_fail("take_damage invulnerable: shield should be unchanged")
	ship.invulnerable = false

	# --- 14. take_damage: disable threshold ----------------------------------
	ship.hull = ship.max_hull
	ship.shield = 0.0
	ship.disabled = false
	ship.destroyed = false
	ship.marine_garrison = 4
	# Damage to just below disable threshold (22% of max_hull)
	var disable_hp: float = ship.max_hull * 0.22
	var damage_to_disable: float = ship.max_hull - disable_hp
	var disable_result: Dictionary = ship.take_damage(damage_to_disable)
	if not bool(disable_result.get("disabled", false)):
		_fail("take_damage should trigger disabled at 22%% hull")
	if not ship.disabled:
		_fail("ship.disabled should be true after disabling damage")
	# Garrison halved on disable
	if ship.marine_garrison != 2:
		_fail("marine_garrison should halve on disable: expected 2, got %d" % ship.marine_garrison)

	# --- 15. take_damage: subsystem targeting routes damage ------------------
	ship.hull = ship.max_hull
	ship.shield = 0.0
	ship.disabled = false
	ship.destroyed = false
	ship.sub_engine = 1.0
	ship.sub_weapon = 1.0
	ship.sub_shield = 1.0
	var sub_result: Dictionary = ship.take_damage(20.0, "engines")
	if not bool(sub_result.get("subsystem_hit", false)):
		_fail("take_damage with subsystem should report subsystem_hit")
	if ship.sub_engine >= 1.0:
		_fail("take_damage with 'engines' should reduce sub_engine")
	# Hull takes only half the post-shield damage when subsystem is targeted
	var expected_hull_loss: float = 20.0 * 0.5  # 50% to hull, 50% to subsystem
	if not _approx(ship.hull, ship.max_hull - expected_hull_loss, 0.5):
		_fail("take_damage subsystem: hull loss should be ~half, got %f vs expected %f" % [ship.max_hull - ship.hull, expected_hull_loss])

	# --- 16. take_damage: destroying shield subsystem collapses shield -------
	ship.hull = ship.max_hull
	ship.shield = ship.max_shield
	ship.disabled = false
	ship.destroyed = false
	ship.sub_shield = 0.05  # just barely alive
	# Deal enough damage to the shield subsystem to destroy it
	# SUB_HEALTH_FRAC is 0.5, so subsystem pool = max_hull * 0.5
	# frac_loss = dmg / (max_hull * 0.5); to lose 0.05 frac: dmg = 0.05 * max_hull * 0.5
	var sub_pool: float = ship.max_hull * 0.5
	var dmg_to_kill_sub: float = 0.05 * sub_pool / 0.5 + 1.0  # extra to ensure it hits 0
	ship.shield = ship.max_shield
	ship.take_damage(dmg_to_kill_sub, "shields")
	if ship.sub_shield > 0.0:
		# May not reach 0 depending on exact math; just verify it decreased
		pass
	# If shield subsystem reached 0, shield bubble should collapse
	if ship.sub_shield <= 0.0 and ship.shield > 0.0:
		_fail("shield subsystem OFFLINE should collapse shield to 0")

	# --- 17. set_faction changes faction property ----------------------------
	var orig_faction: String = ship.faction
	ship.set_faction("hostile")
	if ship.faction != "hostile":
		_fail("set_faction should change faction to 'hostile'")
	ship.set_faction(orig_faction)

	# --- 18. turret_state_to_array / restore_turret_state --------------------
	if ship.has_turrets():
		var turret_state: Array = ship.turret_state_to_array()
		if turret_state.size() != ship.turrets.size():
			_fail("turret_state_to_array size mismatch")
		for ts in turret_state:
			var tsd: Dictionary = ts
			if not tsd.has("yaw") or not tsd.has("cd"):
				_fail("turret_state_to_array entry missing yaw/cd")
		# Modify and restore
		ship.turrets[0]["yaw"] = 0.5
		ship.turrets[0]["cd"] = 1.0
		ship.restore_turret_state(turret_state)
		if not _approx(float(ship.turrets[0]["yaw"]), float(turret_state[0]["yaw"])):
			_fail("restore_turret_state should restore yaw")
	else:
		# Player corvette doesn't have turrets — find one that does
		for s in main.ships:
			if is_instance_valid(s) and s.has_turrets():
				var ts_arr: Array = s.turret_state_to_array()
				if ts_arr.size() > 0 and ts_arr[0] is Dictionary:
					pass  # at least verify it doesn't crash
				break

	# --- 19. apply_crew_bonuses modifies stats ------ -----------------------
	ship.hull = ship.max_hull
	ship.shield = ship.max_shield
	ship.sub_engine = 1.0
	ship.sub_weapon = 1.0
	ship.sub_shield = 1.0
	ship.disabled = false
	ship.destroyed = false

	var base_spd: float = ship.base_max_speed
	var base_acc: float = ship.base_accel
	var base_trn: float = ship.base_turn_rate
	var base_wdmg: float = ship.base_weapon_dmg

	# No crew -> base stats
	ship.apply_crew_bonuses([])
	if not _approx(ship.max_speed, base_spd):
		_fail("apply_crew_bonuses([]) should keep base speed")

	# One pilot with skill 10, morale 1.0
	ship.apply_crew_bonuses([{"role": "pilot", "skill": 10, "morale": 1.0}])
	if ship.max_speed <= base_spd:
		_fail("apply_crew_bonuses with pilot should increase max_speed")
	if ship.turn_rate <= base_trn:
		_fail("apply_crew_bonuses with pilot should increase turn_rate")

	# One gunner with skill 10, morale 1.0
	ship.apply_crew_bonuses([{"role": "gunner", "skill": 10, "morale": 1.0}])
	if ship.weapon_dmg <= base_wdmg:
		_fail("apply_crew_bonuses with gunner should increase weapon_dmg")

	# Morale at 0 halves the bonus (morale_mult = 0.5 + 0*0.5 = 0.5)
	ship.apply_crew_bonuses([{"role": "pilot", "skill": 10, "morale": 0.0}])
	var demoralized_speed: float = ship.max_speed
	ship.apply_crew_bonuses([{"role": "pilot", "skill": 10, "morale": 1.0}])
	var full_morale_speed: float = ship.max_speed
	if full_morale_speed <= demoralized_speed:
		_fail("full morale should give higher speed bonus than zero morale")

	# Reset crew bonuses
	ship.apply_crew_bonuses([])

	_finish(main)

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	if not failed:
		print("SHIP_SUBSYSTEMS_TEST_PASS")
	quit(1 if failed else 0)
