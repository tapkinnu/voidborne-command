extends Node
# Game: global state singleton (autoload). No class_name to avoid circular imports.
# Holds player economy, crew/marine roster, fleet ownership, and the ship-class data tables.

var credits: int = 4200
var crew_pool: int = 3      # available (recruited, unassigned) crew
var marine_pool: int = 6    # available marines for boarding / assignment
var captured_count: int = 0
var purchased_count: int = 0

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

func random_name(rng: RandomNumberGenerator) -> String:
	var i: int = rng.randi_range(0, FIRST_NAMES.size() - 1)
	var n: int = rng.randi_range(10, 99)
	return "%s-%d" % [FIRST_NAMES[i], n]

func reset() -> void:
	credits = 4200
	crew_pool = 3
	marine_pool = 6
	captured_count = 0
	purchased_count = 0
