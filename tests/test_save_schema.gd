extends SceneTree
# Unit tests for scripts/save_schema.gd — the stateless save-file validator.
# Exercises validate_vec3 and validate_save with valid payloads, edge cases,
# and various malformed inputs. Prints SAVE_SCHEMA_TEST_PASS on success.

const SaveSchema: GDScript = preload("res://scripts/save_schema.gd")

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

# --- Helpers ---------------------------------------------------------------
const GAME_ID: String = "voidborne_command"
const MAX_VER: int = 2
const SYS_COUNT: int = 3

func _minimal_ship(p_name: String = "TestShip", p_class: String = "fighter",
		p_faction: String = "player", is_player: bool = false) -> Dictionary:
	return {
		"ship_name": p_name,
		"ship_class": p_class,
		"faction": p_faction,
		"is_player": is_player,
		"pos": [0.0, 0.0, 0.0],
		"rot": [0.0, 0.0, 0.0],
	}

func _minimal_save() -> Dictionary:
	return {
		"game_id": GAME_ID,
		"version": 2,
		"economy": {
			"credits": 1000,
			"crew_pool": 3,
			"marine_pool": 6,
			"captured_count": 0,
			"purchased_count": 0,
		},
		"ships": [_minimal_ship("Flagship", "corvette", "player", true)],
	}

func _initialize() -> void:
	# --- validate_vec3 -------------------------------------------------------
	# Valid vec3
	var r: String = SaveSchema.validate_vec3([1.0, 2.0, 3.0])
	if r != "":
		_fail("validate_vec3 rejected valid [1,2,3]: %s" % r)

	# Integer components are fine
	r = SaveSchema.validate_vec3([0, 5, -3])
	if r != "":
		_fail("validate_vec3 rejected int components: %s" % r)

	# Not an array
	r = SaveSchema.validate_vec3("hello")
	if r == "":
		_fail("validate_vec3 accepted a string")
	if r != "not an array":
		_fail("validate_vec3 wrong reason for string: %s" % r)

	# Wrong size
	r = SaveSchema.validate_vec3([1.0, 2.0])
	if r == "" or r != "needs 3 elements":
		_fail("validate_vec3 wrong reason for 2-elem: %s" % r)

	r = SaveSchema.validate_vec3([1.0, 2.0, 3.0, 4.0])
	if r == "" or r != "needs 3 elements":
		_fail("validate_vec3 wrong reason for 4-elem: %s" % r)

	# Non-numeric element
	r = SaveSchema.validate_vec3([1.0, "two", 3.0])
	if r == "" or r != "non-numeric":
		_fail("validate_vec3 wrong reason for non-numeric: %s" % r)

	# Empty array
	r = SaveSchema.validate_vec3([])
	if r == "":
		_fail("validate_vec3 accepted empty array")

	# Null
	r = SaveSchema.validate_vec3(null)
	if r == "":
		_fail("validate_vec3 accepted null")

	# --- validate_save: valid payload ----------------------------------------
	var save: Dictionary = _minimal_save()
	r = SaveSchema.validate_save(save, GAME_ID, MAX_VER, SYS_COUNT)
	if r != "":
		_fail("validate_save rejected minimal valid save: %s" % r)

	# --- validate_save: wrong type -------------------------------------------
	r = SaveSchema.validate_save("not a dict", GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "corrupt or non-object save":
		_fail("validate_save wrong reason for non-dict: %s" % r)

	# --- validate_save: wrong game_id ----------------------------------------
	var bad_id: Dictionary = _minimal_save()
	bad_id["game_id"] = "wrong_game"
	r = SaveSchema.validate_save(bad_id, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "not a Voidborne save":
		_fail("validate_save wrong reason for bad game_id: %s" % r)

	# --- validate_save: missing version --------------------------------------
	var no_ver: Dictionary = _minimal_save()
	no_ver.erase("version")
	r = SaveSchema.validate_save(no_ver, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "missing version":
		_fail("validate_save wrong reason for missing version: %s" % r)

	# --- validate_save: version too high (future) ----------------------------
	var future_ver: Dictionary = _minimal_save()
	future_ver["version"] = 99
	r = SaveSchema.validate_save(future_ver, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.begins_with("future version"):
		_fail("validate_save wrong reason for future version: %s" % r)

	# --- validate_save: version 0 (invalid) ----------------------------------
	var zero_ver: Dictionary = _minimal_save()
	zero_ver["version"] = 0
	r = SaveSchema.validate_save(zero_ver, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "invalid version":
		_fail("validate_save wrong reason for version 0: %s" % r)

	# --- validate_save: fractional version -----------------------------------
	var frac_ver: Dictionary = _minimal_save()
	frac_ver["version"] = 1.5
	r = SaveSchema.validate_save(frac_ver, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "invalid version":
		_fail("validate_save wrong reason for fractional version: %s" % r)

	# --- validate_save: missing economy --------------------------------------
	var no_econ: Dictionary = _minimal_save()
	no_econ.erase("economy")
	r = SaveSchema.validate_save(no_econ, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "missing economy section":
		_fail("validate_save wrong reason for missing economy: %s" % r)

	# --- validate_save: missing economy.credits ------------------------------
	var bad_econ: Dictionary = _minimal_save()
	var econ: Dictionary = bad_econ["economy"].duplicate()
	econ.erase("credits")
	bad_econ["economy"] = econ
	r = SaveSchema.validate_save(bad_econ, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "missing economy.credits":
		_fail("validate_save wrong reason for missing credits: %s" % r)

	# --- validate_save: missing ships section --------------------------------
	var no_ships: Dictionary = _minimal_save()
	no_ships.erase("ships")
	r = SaveSchema.validate_save(no_ships, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "missing ships section":
		_fail("validate_save wrong reason for missing ships: %s" % r)

	# --- validate_save: no player flagship -----------------------------------
	var no_player: Dictionary = _minimal_save()
	no_player["ships"] = [_minimal_ship("NPC", "fighter", "hostile", false)]
	r = SaveSchema.validate_save(no_player, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "no player flagship in save":
		_fail("validate_save wrong reason for no player: %s" % r)

	# --- validate_save: ship missing required field --------------------------
	var bad_ship: Dictionary = _minimal_save()
	var s: Dictionary = _minimal_ship("X", "fighter", "player", true)
	s.erase("ship_class")
	bad_ship["ships"] = [s]
	r = SaveSchema.validate_save(bad_ship, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "ship missing ship_class":
		_fail("validate_save wrong reason for missing ship_class: %s" % r)

	# --- validate_save: unknown ship_class -----------------------------------
	var unk_class: Dictionary = _minimal_save()
	var s2: Dictionary = _minimal_ship("Y", "battlecruiser", "player", true)
	unk_class["ships"] = [s2]
	r = SaveSchema.validate_save(unk_class, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.begins_with("unknown ship_class"):
		_fail("validate_save wrong reason for unknown class: %s" % r)

	# --- validate_save: bad ship pos -----------------------------------------
	var bad_pos: Dictionary = _minimal_save()
	var s3: Dictionary = _minimal_ship("Z", "fighter", "player", true)
	s3["pos"] = [1.0, 2.0]  # only 2 elements
	bad_pos["ships"] = [s3]
	r = SaveSchema.validate_save(bad_pos, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "":
		_fail("validate_save accepted ship with bad pos")

	# --- validate_save: system index out of range ----------------------------
	var bad_sys: Dictionary = _minimal_save()
	bad_sys["current_system_index"] = 99
	r = SaveSchema.validate_save(bad_sys, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "current_system_index out of range":
		_fail("validate_save wrong reason for sys index OOB: %s" % r)

	# --- validate_save: valid system index -----------------------------------
	var ok_sys: Dictionary = _minimal_save()
	ok_sys["current_system_index"] = 1
	r = SaveSchema.validate_save(ok_sys, GAME_ID, MAX_VER, SYS_COUNT)
	if r != "":
		_fail("validate_save rejected valid system index: %s" % r)

	# --- validate_save: cargo validation (valid) -----------------------------
	var cargo_ok: Dictionary = _minimal_save()
	cargo_ok["economy"]["cargo"] = {"ore": 5, "alloy": 10}
	r = SaveSchema.validate_save(cargo_ok, GAME_ID, MAX_VER, SYS_COUNT)
	if r != "":
		_fail("validate_save rejected valid cargo: %s" % r)

	# --- validate_save: cargo negative value ---------------------------------
	var cargo_neg: Dictionary = _minimal_save()
	cargo_neg["economy"]["cargo"] = {"ore": -3}
	r = SaveSchema.validate_save(cargo_neg, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.contains("negative"):
		_fail("validate_save wrong reason for negative cargo: %s" % r)

	# --- validate_save: cargo non-dict ---------------------------------------
	var cargo_bad: Dictionary = _minimal_save()
	cargo_bad["economy"]["cargo"] = "not a dict"
	r = SaveSchema.validate_save(cargo_bad, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "economy.cargo not a dictionary":
		_fail("validate_save wrong reason for non-dict cargo: %s" % r)

	# --- validate_save: missions must be array if present --------------------
	var bad_missions: Dictionary = _minimal_save()
	bad_missions["missions"] = "not an array"
	r = SaveSchema.validate_save(bad_missions, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "missions not an array":
		_fail("validate_save wrong reason for non-array missions: %s" % r)

	# --- validate_save: bounties must be array if present --------------------
	var bad_bounties: Dictionary = _minimal_save()
	bad_bounties["bounties"] = 42
	r = SaveSchema.validate_save(bad_bounties, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "bounties not an array":
		_fail("validate_save wrong reason for non-array bounties: %s" % r)

	# --- validate_save: hostile_kills_by_class negative ----------------------
	var bad_kills: Dictionary = _minimal_save()
	bad_kills["hostile_kills_by_class"] = {"fighter": -1}
	r = SaveSchema.validate_save(bad_kills, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.contains("negative"):
		_fail("validate_save wrong reason for negative kills: %s" % r)

	# --- validate_save: bounty_seq negative ----------------------------------
	var bad_seq: Dictionary = _minimal_save()
	bad_seq["bounty_seq"] = -5
	r = SaveSchema.validate_save(bad_seq, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or r != "bounty_seq negative":
		_fail("validate_save wrong reason for negative bounty_seq: %s" % r)

	# --- validate_save: marine_garrison negative -----------------------------
	var bad_gar: Dictionary = _minimal_save()
	var sg: Dictionary = _minimal_ship("Flag", "corvette", "player", true)
	sg["marine_garrison"] = -2
	bad_gar["ships"] = [sg]
	r = SaveSchema.validate_save(bad_gar, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.contains("negative"):
		_fail("validate_save wrong reason for negative garrison: %s" % r)

	# --- validate_save: subsystem out of range (>1) --------------------------
	var bad_sub: Dictionary = _minimal_save()
	var ss: Dictionary = _minimal_ship("Flag", "fighter", "player", true)
	ss["sub_engine"] = 1.5
	bad_sub["ships"] = [ss]
	r = SaveSchema.validate_save(bad_sub, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.contains("out of range"):
		_fail("validate_save wrong reason for subsystem > 1: %s" % r)

	# --- validate_save: upgrades out of range --------------------------------
	var bad_upg: Dictionary = _minimal_save()
	var su: Dictionary = _minimal_ship("Flag", "corvette", "player", true)
	su["upgrades"] = {"weapons": 6}
	bad_upg["ships"] = [su]
	r = SaveSchema.validate_save(bad_upg, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.contains("out of range"):
		_fail("validate_save wrong reason for upgrade > 5: %s" % r)

	# --- validate_save: valid upgrades in range ------------------------------
	var ok_upg: Dictionary = _minimal_save()
	var su2: Dictionary = _minimal_ship("Flag", "corvette", "player", true)
	su2["upgrades"] = {"weapons": 3, "shields": 5, "hull": 0, "engines": 1, "reactor": 2}
	ok_upg["ships"] = [su2]
	r = SaveSchema.validate_save(ok_upg, GAME_ID, MAX_VER, SYS_COUNT)
	if r != "":
		_fail("validate_save rejected valid upgrades: %s" % r)

	# --- validate_save: turrets must be array --------------------------------
	var bad_turr: Dictionary = _minimal_save()
	var st: Dictionary = _minimal_ship("Flag", "frigate", "player", true)
	st["turrets"] = "not an array"
	bad_turr["ships"] = [st]
	r = SaveSchema.validate_save(bad_turr, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.contains("turrets not an array"):
		_fail("validate_save wrong reason for non-array turrets: %s" % r)

	# --- validate_save: v1 save accepted (backward compat) -------------------
	var v1: Dictionary = _minimal_save()
	v1["version"] = 1
	r = SaveSchema.validate_save(v1, GAME_ID, MAX_VER, SYS_COUNT)
	if r != "":
		_fail("validate_save rejected v1 save: %s" % r)

	# --- validate_save: garrisoned_marine_names must be array ----------------
	var bad_gmn: Dictionary = _minimal_save()
	var sgm: Dictionary = _minimal_ship("Flag", "corvette", "player", true)
	sgm["garrisoned_marine_names"] = "not an array"
	bad_gmn["ships"] = [sgm]
	r = SaveSchema.validate_save(bad_gmn, GAME_ID, MAX_VER, SYS_COUNT)
	if r == "" or not r.contains("garrisoned_marine_names not an array"):
		_fail("validate_save wrong reason for non-array marine names: %s" % r)

	# Done
	if not failed:
		print("SAVE_SCHEMA_TEST_PASS")
	quit(1 if failed else 0)
