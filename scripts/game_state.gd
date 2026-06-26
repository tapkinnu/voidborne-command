extends Node
# Game: global state singleton (autoload). No class_name to avoid circular imports.
# Holds player economy, crew/marine roster, fleet ownership, and the ship-class data tables.

var credits: int = 4200
var crew_pool: int = 3      # available (recruited, unassigned) crew
var marine_pool: int = 6    # available marines for boarding / assignment
var captured_count: int = 0
var purchased_count: int = 0

# Named crew roster: each entry is an individual with a role, skill and morale.
# crew_pool tracks the COUNT of unassigned crew; crew_roster holds their detail. The
# invariant crew_pool == available_crew().size() is maintained by the helpers below.
# Each entry: { name:String, role:String, skill:int(1..10), morale:float(0..1), assigned:bool }
var crew_roster: Array = []

const CREW_ROLES: Array = ["pilot", "engineer", "gunner"]
const ROLE_ABBR: Dictionary = {"pilot": "PLT", "engineer": "ENG", "gunner": "GUN"}

# Named marine roster, mirroring the crew roster. marine_pool tracks the COUNT of
# unassigned (available) marines; marine_roster holds their detail. The invariant
# marine_pool == available_marines().size() is maintained by the helpers below.
# Each entry: { name:String, skill:int(1..10), morale:float(0..1), assigned:bool }
var marine_roster: Array = []

# Ship class definitions. Values are gameplay-tuned, deterministic, and read with
# explicit typing wherever they feed math, per project constraints.
const SHIP_CLASSES: Dictionary = {
	"fighter": {
		"display": "Fighter",
		"hull": 60.0,
		"shield": 30.0,
		"energy": 80.0,
		"max_speed": 46.0,
		"accel": 28.0,
		"turn_rate": 2.6,
		"scale": 1.0,
		"weapon": "cannon",
		"weapon_dmg": 7.0,
		"fire_rate": 0.18,
		"weapon_range": 220.0,
		"crew_needed": 1,
		"garrison": 0,
		"value": 800,
		"color": Color(0.55, 0.8, 1.0),
	},
	"corvette": {
		"display": "Corvette",
		"hull": 160.0,
		"shield": 90.0,
		"energy": 140.0,
		"max_speed": 34.0,
		"accel": 16.0,
		"turn_rate": 1.5,
		"scale": 2.1,
		"weapon": "cannon",
		"weapon_dmg": 12.0,
		"fire_rate": 0.28,
		"weapon_range": 260.0,
		"crew_needed": 3,
		"garrison": 2,
		"value": 2200,
		"color": Color(0.6, 0.85, 0.95),
	},
	"frigate": {
		"display": "Frigate",
		"hull": 340.0,
		"shield": 180.0,
		"energy": 220.0,
		"max_speed": 24.0,
		"accel": 9.0,
		"turn_rate": 0.85,
		"scale": 3.4,
		"weapon": "cannon",
		"weapon_dmg": 20.0,
		"fire_rate": 0.5,
		"weapon_range": 300.0,
		"crew_needed": 6,
		"garrison": 4,
		"value": 5200,
		"color": Color(0.7, 0.8, 0.9),
	},
	"capital": {
		"display": "Capital",
		"hull": 900.0,
		"shield": 420.0,
		"energy": 500.0,
		"max_speed": 14.0,
		"accel": 4.0,
		"turn_rate": 0.35,
		"scale": 6.5,
		"weapon": "beam",
		"weapon_dmg": 60.0,
		"fire_rate": 1.6,
		"weapon_range": 420.0,
		"crew_needed": 14,
		"garrison": 8,
		"value": 16000,
		"color": Color(0.8, 0.78, 0.85),
	},
	"station": {
		"display": "Station",
		"hull": 1600.0,
		"shield": 600.0,
		"energy": 800.0,
		"max_speed": 0.0,
		"accel": 0.0,
		"turn_rate": 0.05,
		"scale": 10.0,
		"weapon": "beam",
		"weapon_dmg": 45.0,
		"fire_rate": 1.2,
		"weapon_range": 460.0,
		"crew_needed": 20,
		"garrison": 12,
		"value": 30000,
		"color": Color(0.75, 0.75, 0.82),
	},
}

# Roster of named crew/marines the player can interact with on the crew deck.
const FIRST_NAMES: Array = [
	"Vega", "Ash", "Ren", "Kael", "Mira", "Dax", "Iyo", "Sol", "Bryn", "Tace",
	"Nox", "Pell", "Juno", "Cyr", "Wren", "Orin",
]

func class_stat(ship_class: String, key: String) -> float:
	var data: Dictionary = SHIP_CLASSES.get(ship_class, {})
	var v = data.get(key, 0.0)
	return float(v)

func class_info(ship_class: String) -> Dictionary:
	return SHIP_CLASSES.get(ship_class, {})

# --- Meshy visual-upgrade flag ---------------------------------------------
# When true, ALL entity classes swap their procedural visual for a
# Meshy-generated GLB under res://assets/models/meshy_visual_upgrade/.
# Flip to false to revert without touching the swap code paths.
const MESHY_VISUAL_UPGRADE_ENABLED: bool = true

# Map of "ship_class|faction" -> Meshy GLB basename under
# res://assets/models/meshy_visual_upgrade/. Any ship not in this table
# keeps its procedural visual regardless of the flag. The pipe delimiter
# is safe because Godot class and faction identifiers never contain pipes.
const MESHY_SHIP_GLB: Dictionary = {
	"corvette|player": "player_corvette",
	"capital|hostile": "capital_ship",
	"fighter|hostile": "hostile_fighter",
	"fighter|player": "fighter_player",
	"frigate|hostile": "frigate_any",
	"corvette|hostile": "player_corvette",   # reuse player corvette model for hostile corvettes
	"station|neutral": "station_neutral",
	"station|hostile": "station_hostile",
	"station|player": "friendly_station",    # captured stations -> friendly station model
}

const MESHY_CAPTAIN_GLB: String = "crew_captain"
const MESHY_CREW_GLB: String = "crew_humanoid"
const MESHY_MARINE_GLB: String = "marine_humanoid"

func random_name(rng: RandomNumberGenerator) -> String:
	var i: int = rng.randi_range(0, FIRST_NAMES.size() - 1)
	var n: int = rng.randi_range(10, 99)
	return "%s-%d" % [FIRST_NAMES[i], n]

# --- Named crew roster helpers ---------------------------------------------
func _make_crew_member(rng: RandomNumberGenerator) -> Dictionary:
	# A fresh, unassigned crew member with a random role, mid skill and good morale.
	var role: String = String(CREW_ROLES[rng.randi_range(0, CREW_ROLES.size() - 1)])
	return {
		"name": random_name(rng),
		"role": role,
		"skill": rng.randi_range(3, 7),
		"morale": rng.randf_range(0.7, 1.0),
		"assigned": false,
	}

func recruit_crew_member(rng: RandomNumberGenerator) -> Dictionary:
	# Create a new crew member, add to the roster, and bump the available count.
	var c: Dictionary = _make_crew_member(rng)
	crew_roster.append(c)
	crew_pool += 1
	return c

func available_crew() -> Array:
	var out: Array = []
	for c in crew_roster:
		var cd: Dictionary = c
		if not bool(cd.get("assigned", false)):
			out.append(cd)
	return out

func assign_best_crew(count: int, preferred_role: String = "") -> Array:
	# Mark up to `count` available crew as assigned and return them. Prefers matching
	# role first, then highest skill. Decrements crew_pool by the number actually taken.
	var pool: Array = available_crew()
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_match: int = 1 if String(a.get("role", "")) == preferred_role else 0
		var b_match: int = 1 if String(b.get("role", "")) == preferred_role else 0
		if a_match != b_match:
			return a_match > b_match
		return int(a.get("skill", 0)) > int(b.get("skill", 0))
	)
	var taken: Array = []
	for c in pool:
		if taken.size() >= count:
			break
		var cd: Dictionary = c
		cd["assigned"] = true
		taken.append(cd)
	crew_pool = max(0, crew_pool - taken.size())
	return taken

func unassign_crew(crew_list: Array) -> void:
	# Return assigned crew to the available pool.
	for c in crew_list:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cd: Dictionary = c
		if bool(cd.get("assigned", false)):
			cd["assigned"] = false
			crew_pool += 1

func crew_role_counts() -> Dictionary:
	# Count AVAILABLE (unassigned) crew by role, for the HUD summary line.
	var counts: Dictionary = {"pilot": 0, "engineer": 0, "gunner": 0}
	for c in available_crew():
		var cd: Dictionary = c
		var r: String = String(cd.get("role", ""))
		if counts.has(r):
			counts[r] = int(counts[r]) + 1
	return counts

func roster_to_save() -> Array:
	# Serialise the full roster (assigned crew included) for the save file.
	var out: Array = []
	for c in crew_roster:
		var cd: Dictionary = c
		out.append({
			"name": String(cd.get("name", "")),
			"role": String(cd.get("role", "pilot")),
			"skill": int(cd.get("skill", 1)),
			"morale": float(cd.get("morale", 1.0)),
			"assigned": bool(cd.get("assigned", false)),
		})
	return out

func roster_from_save(data: Array) -> void:
	crew_roster.clear()
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ed: Dictionary = entry
		crew_roster.append({
			"name": String(ed.get("name", "Crew")),
			"role": String(ed.get("role", "pilot")),
			"skill": clampi(int(ed.get("skill", 1)), 1, 10),
			"morale": clampf(float(ed.get("morale", 1.0)), 0.0, 1.0),
			"assigned": bool(ed.get("assigned", false)),
		})

func rebuild_default_roster(rng: RandomNumberGenerator, count: int) -> void:
	# Backward-compatible fallback for old saves with no roster: synthesise `count`
	# unassigned crew so crew_pool == available_crew().size() still holds.
	crew_roster.clear()
	for i in range(max(0, count)):
		var c: Dictionary = _make_crew_member(rng)
		c["assigned"] = false
		crew_roster.append(c)

# --- Named marine roster helpers (mirror crew) -----------------------------
func _make_marine_member(rng: RandomNumberGenerator) -> Dictionary:
	# A fresh unassigned marine. No "role" field (marines have one role).
	return {
		"name": random_name(rng),
		"skill": rng.randi_range(3, 7),
		"morale": rng.randf_range(0.7, 1.0),
		"assigned": false,
		"wounds": 0,
	}

func recruit_marine_member(rng: RandomNumberGenerator) -> Dictionary:
	var m: Dictionary = _make_marine_member(rng)
	marine_roster.append(m)
	marine_pool += 1
	return m

func available_marines() -> Array:
	var out: Array = []
	for m in marine_roster:
		var md: Dictionary = m
		if not bool(md.get("assigned", false)):
			out.append(md)
	return out

# Draw up to `count` available marines for a boarding action; mark them assigned
# and decrement marine_pool. Returns the drawn list (references into the roster).
func draw_boarding_marines(count: int) -> Array:
	var want: int = max(0, count)
	var pool: Array = available_marines()
	# Reconcile a desynced pool: if marine_pool was set higher than the roster holds
	# (legacy save or direct assignment), materialise the shortfall so the boarding
	# party honours the requested count.
	if pool.size() < want:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.randomize()
		while pool.size() < want:
			var extra: Dictionary = _make_marine_member(rng)
			marine_roster.append(extra)
			pool.append(extra)
	# Prefer highest skill marines for the boarding party.
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("skill", 0)) > int(b.get("skill", 0))
	)
	var drawn: Array = []
	for m in pool:
		if drawn.size() >= want:
			break
		var md: Dictionary = m
		md["assigned"] = true
		drawn.append(md)
	marine_pool = max(0, marine_pool - drawn.size())
	return drawn

# Return surviving boarders to the available pool. A boarding action commits the
# ENTIRE available pool (draw_boarding_marines(marine_pool)), so the marines who
# come back ARE the whole new available pool — marine_pool is set to the count
# actually restored, keeping marine_pool == available_marines().size() after a real
# boarding (pool was 0 going in).
func restore_boarding_marines(survivors: Array) -> void:
	var restored: int = 0
	for m in survivors:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		if bool(md.get("assigned", false)):
			md["assigned"] = false
			restored += 1
	marine_pool = restored

func marine_roster_to_save() -> Array:
	var out: Array = []
	for m in marine_roster:
		var md: Dictionary = m
		out.append({
			"name": String(md.get("name", "")),
			"skill": int(md.get("skill", 1)),
			"morale": float(md.get("morale", 1.0)),
			"assigned": bool(md.get("assigned", false)),
			"wounds": clampi(int(md.get("wounds", 0)), 0, 3),
		})
	return out

func marine_roster_from_save(data: Array) -> void:
	marine_roster.clear()
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ed: Dictionary = entry
		marine_roster.append({
			"name": String(ed.get("name", "Marine")),
			"skill": clampi(int(ed.get("skill", 1)), 1, 10),
			"morale": clampf(float(ed.get("morale", 1.0)), 0.0, 1.0),
			"assigned": bool(ed.get("assigned", false)),
			"wounds": clampi(int(ed.get("wounds", 0)), 0, 3),
		})

func rebuild_default_marine_roster(rng: RandomNumberGenerator, count: int) -> void:
	# Backward-compatible fallback for old saves with no marine roster: synthesise
	# `count` unassigned marines so marine_pool == available_marines().size() holds.
	marine_roster.clear()
	for i in range(max(0, count)):
		marine_roster.append(_make_marine_member(rng))

func reset() -> void:
	credits = 4200
	crew_pool = 3
	marine_pool = 6
	captured_count = 0
	purchased_count = 0
	# Seed the starting roster of 3 unassigned crew matching crew_pool.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	crew_roster.clear()
	for i in range(crew_pool):
		crew_roster.append(_make_crew_member(rng))
	# Seed the starting marine roster matching marine_pool.
	marine_roster.clear()
	for i in range(marine_pool):
		marine_roster.append(_make_marine_member(rng))
