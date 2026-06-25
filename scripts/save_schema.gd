extends RefCounted
# SaveSchema: stateless validator for persisted save payloads.
#
# Extracted from main.gd to isolate the (large, purely-functional) save-format contract
# from the rest of the god-script. Given a parsed save Variant it returns "" when the
# payload is acceptable, or a human-readable reason string otherwise. It mutates nothing
# and reads no live game state -- the version/game-id/system-count limits are passed in so
# the schema stays decoupled from main.gd's constants. main.gd keeps thin _validate_vec3 /
# _validate_save forwarders so the existing public API (and tests) are unchanged.
#
# No class_name (avoids circular-import pitfalls); called via preload from main.gd.

# Validate that a Variant is a [x, y, z] array of numbers. Returns "" or a reason.
static func validate_vec3(v: Variant) -> String:
	if typeof(v) != TYPE_ARRAY:
		return "not an array"
	var arr: Array = v
	if arr.size() != 3:
		return "needs 3 elements"
	for n in arr:
		if typeof(n) != TYPE_FLOAT and typeof(n) != TYPE_INT:
			return "non-numeric"
	return ""

# Validate a full save payload. Returns "" when acceptable, otherwise a reason string.
#   game_id      : the expected SAVE_GAME_ID marker
#   max_version  : the newest SAVE_VERSION this build can load
#   system_count : number of star systems (bounds-checks current_system_index)
static func validate_save(parsed: Variant, game_id: String, max_version: int, system_count: int) -> String:
	if typeof(parsed) != TYPE_DICTIONARY:
		return "corrupt or non-object save"
	var d: Dictionary = parsed
	if String(d.get("game_id", "")) != game_id:
		return "not a Voidborne save"
	if not d.has("version"):
		return "missing version"
	var ver_val: Variant = d["version"]
	if typeof(ver_val) != TYPE_FLOAT and typeof(ver_val) != TYPE_INT:
		return "invalid version"
	var ver_float: float = float(ver_val)
	var ver: int = int(ver_float)
	if abs(ver_float - float(ver)) > 0.001:
		return "invalid version"
	if ver < 1:
		return "invalid version"
	if ver > max_version:
		return "future version (v%d > v%d) — update the game" % [ver, max_version]
	if typeof(d.get("economy")) != TYPE_DICTIONARY:
		return "missing economy section"
	var econ: Dictionary = d["economy"]
	for key in ["credits", "crew_pool", "marine_pool", "captured_count", "purchased_count"]:
		if not econ.has(key):
			return "missing economy.%s" % key
	# Cargo is optional (backward compatible: old saves predate trading). If present it must be
	# a Dictionary of non-negative integer quantities.
	if econ.has("cargo"):
		if typeof(econ["cargo"]) != TYPE_DICTIONARY:
			return "economy.cargo not a dictionary"
		var cargo_d: Dictionary = econ["cargo"]
		for ck in cargo_d.keys():
			var qv: Variant = cargo_d[ck]
			if typeof(qv) != TYPE_FLOAT and typeof(qv) != TYPE_INT:
				return "economy.cargo.%s non-numeric" % String(ck)
			if float(qv) < 0.0:
				return "economy.cargo.%s negative" % String(ck)
	if typeof(d.get("ships")) != TYPE_ARRAY:
		return "missing ships section"
	# Missions are optional (backward compatible). If present, must be an Array.
	if d.has("missions") and typeof(d["missions"]) != TYPE_ARRAY:
		return "missions not an array"
	# Bounties are optional (backward compatible: old saves predate the bounty board). If
	# present, must be an Array; the per-class kill counter a Dictionary of non-negative ints.
	if d.has("bounties") and typeof(d["bounties"]) != TYPE_ARRAY:
		return "bounties not an array"
	if d.has("hostile_kills_by_class"):
		if typeof(d["hostile_kills_by_class"]) != TYPE_DICTIONARY:
			return "hostile_kills_by_class not a dictionary"
		var kills_d: Dictionary = d["hostile_kills_by_class"]
		for kk in kills_d.keys():
			var kv: Variant = kills_d[kk]
			if typeof(kv) != TYPE_FLOAT and typeof(kv) != TYPE_INT:
				return "hostile_kills_by_class.%s non-numeric" % String(kk)
			if float(kv) < 0.0:
				return "hostile_kills_by_class.%s negative" % String(kk)
	if d.has("bounty_seq"):
		var seq_val: Variant = d["bounty_seq"]
		if typeof(seq_val) != TYPE_FLOAT and typeof(seq_val) != TYPE_INT:
			return "bounty_seq non-numeric"
		if float(seq_val) < 0.0:
			return "bounty_seq negative"
	# System index is optional (v1 saves predate it). If present, an int in range.
	if d.has("current_system_index"):
		var sys_val: Variant = d["current_system_index"]
		if typeof(sys_val) != TYPE_FLOAT and typeof(sys_val) != TYPE_INT:
			return "current_system_index non-numeric"
		var sys_i: int = int(sys_val)
		if sys_i < 0 or sys_i >= system_count:
			return "current_system_index out of range"
	var ships_arr: Array = d["ships"]
	var player_count: int = 0
	for entry in ships_arr:
		if typeof(entry) != TYPE_DICTIONARY:
			return "invalid ship entry"
		var sd: Dictionary = entry
		for key in ["ship_name", "ship_class", "faction"]:
			if not sd.has(key):
				return "ship missing %s" % key
		if not Game.SHIP_CLASSES.has(String(sd["ship_class"])):
			return "unknown ship_class '%s'" % String(sd["ship_class"])
		var perr: String = validate_vec3(sd.get("pos"))
		if perr != "":
			return "ship %s pos %s" % [String(sd.get("ship_name", "?")), perr]
		var rerr: String = validate_vec3(sd.get("rot"))
		if rerr != "":
			return "ship %s rot %s" % [String(sd.get("ship_name", "?")), rerr]
		# Marine garrison is optional (backward compatible). If present, a non-negative int.
		if sd.has("marine_garrison"):
			var garr_val: Variant = sd["marine_garrison"]
			if typeof(garr_val) != TYPE_FLOAT and typeof(garr_val) != TYPE_INT:
				return "ship %s marine_garrison non-numeric" % String(sd.get("ship_name", "?"))
			if float(garr_val) < 0.0:
				return "ship %s marine_garrison negative" % String(sd.get("ship_name", "?"))
		if sd.has("garrisoned_marine_names") and typeof(sd["garrisoned_marine_names"]) != TYPE_ARRAY:
			return "ship %s garrisoned_marine_names not an array" % String(sd.get("ship_name", "?"))
		# Subsystem health is optional (backward compatible). If present, must be a 0..1 float.
		for sub_key in ["sub_engine", "sub_weapon", "sub_shield"]:
			if sd.has(sub_key):
				var sub_val: Variant = sd[sub_key]
				if typeof(sub_val) != TYPE_FLOAT and typeof(sub_val) != TYPE_INT:
					return "ship %s %s non-numeric" % [String(sd.get("ship_name", "?")), sub_key]
				var sub_f: float = float(sub_val)
				if sub_f < 0.0 or sub_f > 1.0:
					return "ship %s %s out of range" % [String(sd.get("ship_name", "?")), sub_key]
		# Turret state is optional (backward compatible). If present, must be an Array.
		if sd.has("turrets") and typeof(sd["turrets"]) != TYPE_ARRAY:
			return "ship %s turrets not an array" % String(sd.get("ship_name", "?"))
		# Upgrades are optional (backward compatible). If present, a dict of 0..5 levels.
		if sd.has("upgrades"):
			if typeof(sd["upgrades"]) != TYPE_DICTIONARY:
				return "ship %s upgrades not a dictionary" % String(sd.get("ship_name", "?"))
			var upg_d: Dictionary = sd["upgrades"]
			for uk in ["weapons", "shields", "hull", "engines", "reactor"]:
				if upg_d.has(uk):
					var uv: Variant = upg_d[uk]
					if typeof(uv) != TYPE_FLOAT and typeof(uv) != TYPE_INT:
						return "ship %s upgrades.%s non-numeric" % [String(sd.get("ship_name", "?")), uk]
					if float(uv) < 0.0 or float(uv) > 5.0:
						return "ship %s upgrades.%s out of range" % [String(sd.get("ship_name", "?")), uk]
		if bool(sd.get("is_player", false)):
			player_count += 1
	if player_count == 0:
		return "no player flagship in save"
	return ""
