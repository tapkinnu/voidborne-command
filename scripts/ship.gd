extends Node3D
# Ship: a single space vessel (player, ally, hostile or neutral). Procedurally
# code-built mesh per class. No class_name (avoids circular imports). Driven by main.gd.

# Centralised balance knobs (also the "GameConstants" autoload). Preloaded for const-context
# access so the disable threshold stays in lockstep with main.gd / GameConstants.
const GC: GDScript = preload("res://scripts/game_constants.gd")

const FACTION_TINTS: Dictionary = {
	"player": Color(0.40, 1.00, 0.62),
	"ally": Color(0.42, 0.72, 1.00),
	"hostile": Color(1.00, 0.40, 0.34),
	"neutral": Color(0.72, 0.72, 0.74),
}

# Yaw applied to Meshy GLB visuals so their authored nose (the -X end, verified
# across all ship GLBs) points along the game's forward (-Z). See
# _fit_meshy_to_hull(). -90° about Y maps local -X -> world -Z.
const MESHY_FORWARD_YAW: float = -PI / 2.0

var ship_class: String = "fighter"
var faction: String = "hostile"
var ship_name: String = "Unknown"
var is_player: bool = false

var max_hull: float = 60.0
var hull: float = 60.0
var max_shield: float = 30.0
var shield: float = 30.0
var max_energy: float = 80.0
var energy: float = 80.0

var max_speed: float = 40.0
var accel: float = 20.0
var turn_rate: float = 2.0

var base_max_speed: float = 40.0
var base_accel: float = 20.0
var base_turn_rate: float = 2.0

var weapon_type: String = "cannon"
var weapon_dmg: float = 7.0
var fire_rate: float = 0.2
var base_weapon_dmg: float = 7.0
var base_fire_rate: float = 0.2
var weapon_range: float = 220.0
var weapon_cd: float = 0.0

# Permanent station-bought upgrades (0..UPGRADE_MAX_LEVEL). Each level adds a
# multiplicative bonus to the corresponding base stat. Stored on the ship so they
# survive save/load and apply to the flagship. Re-applied via apply_upgrades().
var upg_weapons: int = 0
var upg_shields: int = 0
var upg_hull: int = 0
var upg_engines: int = 0
var upg_reactor: int = 0

# Subsystem targeting. Each subsystem is a 0..1 health fraction. They never regen on
# their own (only station refit restores them). A subsystem at 0 is OFFLINE; below
# SUB_DAMAGED_FRAC it is DAMAGED; otherwise OK. The player can focus-fire one subsystem
# at a time, routing half the post-shield hull damage into it (see take_damage).
const SUB_DAMAGED_FRAC: float = 0.4
const SUB_HEALTH_FRAC: float = 0.5   # subsystem pool size relative to max_hull
var sub_engine: float = 1.0
var sub_weapon: float = 1.0
var sub_shield: float = 1.0

var crew_needed: int = 1
var crew_assigned: int = 0
var manned: bool = true

# Marines stationed aboard for defense against boarding. Set by class in setup(); halved
# when the ship is disabled (some defenders are casualties of the disabling fight). Player-owned
# prizes can be reinforced later via the [I] assign-garrison action.
var marine_garrison: int = 0

var velocity: Vector3 = Vector3.ZERO
var throttle: float = 0.0           # 0..1 commanded throttle
var boosting: bool = false
var disabled: bool = false
var destroyed: bool = false
# Capture/auto-demo only: when true the ship ignores all incoming damage so the
# flagship stays alive and framed for the entire screenshot window. Never set in
# normal gameplay.
var invulnerable: bool = false

var target: Node3D = null
var ai_state: String = "engage"
# Wing sub-group membership for player-owned escorts. "" = unassigned (follows the global
# fleet order); "alpha"/"beta"/"gamma" = follows that wing's independent standing order.
var wing_id: String = ""
# Persistent station assignment for the "guard_station" fleet order. Stored as the assigned
# station's ship_name (resolved to a live node at runtime via guard_station_node()). "" = none.
var guard_station_name: String = ""
var board_progress: float = 0.0     # 0..1 when being boarded by player marines
var being_boarded: bool = false

var class_color: Color = Color.WHITE
var _hull_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _engine_mat: StandardMaterial3D
var _running_light_mat: StandardMaterial3D  # shared emissive mat for this ship's running lights
var _exhaust_mat: StandardMaterial3D        # transparent blue-white engine plume mat
var _shield_mesh: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _shield_flash: float = 0.0
var _engine_nodes: Array = []
var _exhaust_nodes: Array = []      # MeshInstance3D exhaust cones, scaled/faded with throttle
static var _light_accum: float = 0.0  # shared pulse phase for running-light emission
var muzzles: Array = []             # Array[Vector3] local-space muzzle offsets

# Independent turret mounts. Each entry is a Dictionary:
#   "node": MeshInstance3D  — the visual turret (rotates around Y to track)
#   "pos": Vector3          — local position on the ship hull (static)
#   "muzzle_fwd": float     — how far forward (local -Z) the muzzle sits from the turret pivot
#   "yaw": float            — current tracked yaw angle in radians (0 = ship forward)
#   "arc_half": float       — half-angle fire arc in radians (turret can only track/fire within ±arc_half of ship forward)
#   "cd": float             — per-turret weapon cooldown timer
#   "base_cd": float        — per-turret base fire interval (seconds)
var turrets: Array = []

func setup(p_class: String, p_faction: String, p_name: String) -> void:
	ship_class = p_class
	faction = p_faction
	ship_name = p_name
	var info: Dictionary = Game.class_info(p_class)
	max_hull = float(info.get("hull", 60.0))
	hull = max_hull
	max_shield = float(info.get("shield", 30.0))
	shield = max_shield
	max_energy = float(info.get("energy", 80.0))
	energy = max_energy
	max_speed = float(info.get("max_speed", 40.0))
	accel = float(info.get("accel", 20.0))
	turn_rate = float(info.get("turn_rate", 2.0))
	weapon_type = String(info.get("weapon", "cannon"))
	weapon_dmg = float(info.get("weapon_dmg", 7.0))
	fire_rate = float(info.get("fire_rate", 0.2))
	weapon_range = float(info.get("weapon_range", 220.0))
	crew_needed = int(info.get("crew_needed", 1))
	crew_assigned = crew_needed
	manned = true
	base_max_speed = max_speed
	base_accel = accel
	base_turn_rate = turn_rate
	base_weapon_dmg = weapon_dmg
	base_fire_rate = fire_rate
	marine_garrison = int(info.get("garrison", 0))
	class_color = info.get("color", Color.WHITE)
	_build_mesh()

func apply_crew_bonuses(crew_list: Array) -> void:
	var pilot_bonus: float = 0.0
	var engineer_bonus: float = 0.0
	var gunner_bonus: float = 0.0
	var gunner_rate_bonus: float = 0.0
	for c in crew_list:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var role: String = String(c.get("role", ""))
		var skill: float = float(c.get("skill", 1))
		var morale: float = float(c.get("morale", 1.0))
		var morale_mult: float = 0.5 + morale * 0.5
		match role:
			"pilot":
				pilot_bonus += skill * 0.03 * morale_mult
			"engineer":
				engineer_bonus += skill * 0.03 * morale_mult
			"gunner":
				gunner_bonus += skill * 0.03 * morale_mult
				gunner_rate_bonus += skill * 0.02 * morale_mult
	max_speed = base_max_speed * (1.0 + pilot_bonus)
	turn_rate = base_turn_rate * (1.0 + pilot_bonus)
	accel = base_accel * (1.0 + engineer_bonus)
	weapon_dmg = base_weapon_dmg * (1.0 + gunner_bonus)
	fire_rate = max(0.1, base_fire_rate * (1.0 - gunner_rate_bonus))

func apply_upgrades() -> void:
	# Recompute every base_* stat (and max_hull/shield/energy) from the class defaults scaled
	# by the permanent upgrade levels, then re-apply crew bonuses on top. Class defaults are
	# read fresh from Game.class_info() each call (the table is the source of truth). Current
	# hull/shield/energy grow by the delta so installing an upgrade adds usable capacity.
	var info: Dictionary = Game.class_info(ship_class)
	var class_wdmg: float = float(info.get("weapon_dmg", 7.0))
	var class_fire_rate: float = float(info.get("fire_rate", 0.2))
	var class_speed: float = float(info.get("max_speed", 40.0))
	var class_accel: float = float(info.get("accel", 20.0))
	var class_turn: float = float(info.get("turn_rate", 2.0))
	var class_hull: float = float(info.get("hull", 60.0))
	var class_shield: float = float(info.get("shield", 30.0))
	var class_energy: float = float(info.get("energy", 80.0))

	# Weapons: more damage and a faster fire interval (lower cooldown is better, floor 0.1).
	base_weapon_dmg = class_wdmg * (1.0 + float(upg_weapons) * 0.15)
	base_fire_rate = max(0.1, class_fire_rate * (1.0 - float(upg_weapons) * 0.05))

	# Engines: speed, acceleration and turn rate all scale together.
	base_max_speed = class_speed * (1.0 + float(upg_engines) * 0.08)
	base_accel = class_accel * (1.0 + float(upg_engines) * 0.08)
	base_turn_rate = class_turn * (1.0 + float(upg_engines) * 0.08)

	# Hull/shield/reactor: grow the max and add the delta to the live pool.
	var new_max_hull: float = class_hull * (1.0 + float(upg_hull) * 0.12)
	hull += new_max_hull - max_hull
	max_hull = new_max_hull
	var new_max_shield: float = class_shield * (1.0 + float(upg_shields) * 0.15)
	shield += new_max_shield - max_shield
	max_shield = new_max_shield
	var new_max_energy: float = class_energy * (1.0 + float(upg_reactor) * 0.12)
	energy += new_max_energy - max_energy
	max_energy = new_max_energy

	# Re-apply crew bonuses so they stack on top of the upgraded base stats. The
	# assigned_crew meta may be absent (e.g. during load) — guard against null/non-Array.
	var crew_list: Array = []
	if has_meta("assigned_crew"):
		var crew_meta: Variant = get_meta("assigned_crew")
		if typeof(crew_meta) == TYPE_ARRAY:
			crew_list = crew_meta
	apply_crew_bonuses(crew_list)

func radius() -> float:
	return float(Game.class_info(ship_class).get("scale", 1.0)) * 3.0

func _faction_color() -> Color:
	var tint: Color = FACTION_TINTS.get(faction, Color.WHITE)
	return class_color.lerp(tint, 0.6)

func _make_mat(col: Color, emission_strength: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.35)
	m.metallic = 0.55
	m.roughness = 0.45
	if emission_strength > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emission_strength
	return m

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _add_cyl(parent: Node3D, radius_top: float, radius_bottom: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = radius_top
	cm.bottom_radius = radius_bottom
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _running_light_color() -> Color:
	if faction == "player" or faction == "ally":
		return Color(0.30, 1.00, 0.42)
	if faction == "hostile":
		return Color(1.00, 0.32, 0.26)
	return Color(1.00, 1.00, 1.00)

func _add_light(parent: Node3D, pos: Vector3) -> MeshInstance3D:
	# Small emissive navigation sphere using the ship's shared running-light material.
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	mi.mesh = sm
	mi.material_override = _running_light_mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _add_exhaust(parent: Node3D, pos: Vector3, base_len: float) -> MeshInstance3D:
	# Tapered cylinder (narrow tip → wide base) rotated to point backward (+Z) behind an engine.
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.3
	cm.height = base_len
	mi.mesh = cm
	mi.material_override = _exhaust_mat
	mi.position = pos
	mi.rotation.x = PI / 2.0   # mesh +Y (narrow top) maps to +Z, base toward the engine
	parent.add_child(mi)
	_exhaust_nodes.append(mi)
	return mi

func _build_mesh() -> void:
	var hull_col: Color = _faction_color()
	_hull_mat = _make_mat(hull_col, 0.0)
	var accent_mat: StandardMaterial3D = _make_mat(hull_col, 1.6)
	_engine_mat = _make_mat(Color(1.0, 0.65, 0.25), 4.0)

	# Shared running-light material (faction-tinted, unshaded emissive). Pulsed in tick_visuals.
	var rl_col: Color = _running_light_color()
	_running_light_mat = StandardMaterial3D.new()
	_running_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_running_light_mat.albedo_color = rl_col
	_running_light_mat.emission_enabled = true
	_running_light_mat.emission = rl_col
	_running_light_mat.emission_energy_multiplier = 1.4

	# Engine exhaust plume material (transparent blue-white, double-sided).
	_exhaust_mat = StandardMaterial3D.new()
	_exhaust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_exhaust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_exhaust_mat.albedo_color = Color(0.5, 0.7, 1.0, 0.35)
	_exhaust_mat.emission_enabled = true
	_exhaust_mat.emission = Color(0.6, 0.8, 1.0)
	_exhaust_mat.emission_energy_multiplier = 3.0
	_exhaust_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var root: Node3D = Node3D.new()
	root.name = "Hull"
	add_child(root)
	var s: float = float(Game.class_info(ship_class).get("scale", 1.0))
	root.scale = Vector3(s, s, s)

	# Ships point toward -Z (Godot forward).
	match ship_class:
		"fighter":
			_add_box(root, Vector3(0.9, 0.5, 3.0), Vector3(0, 0, 0), _hull_mat)
			_add_box(root, Vector3(3.4, 0.18, 1.1), Vector3(0, 0, 0.4), _hull_mat)     # wings
			_add_box(root, Vector3(0.5, 0.45, 0.8), Vector3(0, 0.25, -1.0), accent_mat) # cockpit
			_engine_nodes.append(_add_box(root, Vector3(0.5, 0.4, 0.5), Vector3(0, 0, 1.6), _engine_mat))
			muzzles = [Vector3(0.9, 0, -1.6), Vector3(-0.9, 0, -1.6)]
			# Greebles: wing panels + cockpit antenna.
			_add_box(root, Vector3(0.2, 0.08, 0.4), Vector3(1.2, 0.05, 0.4), accent_mat)
			_add_box(root, Vector3(0.2, 0.08, 0.4), Vector3(-1.2, 0.05, 0.4), accent_mat)
			_add_box(root, Vector3(0.15, 0.1, 0.3), Vector3(0, 0.3, -0.2), accent_mat)
			_add_cyl(root, 0.02, 0.04, 0.5, Vector3(0, 0.5, -0.6), accent_mat)
			# Running lights: wingtips, nose, engine.
			_add_light(root, Vector3(1.6, 0.05, 0.5))
			_add_light(root, Vector3(-1.6, 0.05, 0.5))
			_add_light(root, Vector3(0.2, 0.0, -1.5))
			_add_light(root, Vector3(-0.2, 0.0, -1.5))
			_add_light(root, Vector3(0.25, 0.0, 1.5))
			_add_light(root, Vector3(-0.25, 0.0, 1.5))
		"corvette":
			_add_box(root, Vector3(1.4, 1.0, 5.0), Vector3(0, 0, 0), _hull_mat)
			_add_box(root, Vector3(2.6, 0.3, 1.6), Vector3(0, 0.2, 0.6), _hull_mat)
			_add_box(root, Vector3(0.6, 0.6, 1.2), Vector3(0, 0.55, -1.6), accent_mat)
			_add_box(root, Vector3(0.4, 0.4, 0.8), Vector3(1.0, 0, 1.0), _hull_mat)
			_add_box(root, Vector3(0.4, 0.4, 0.8), Vector3(-1.0, 0, 1.0), _hull_mat)
			_engine_nodes.append(_add_box(root, Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0, 2.6), _engine_mat))
			_engine_nodes.append(_add_box(root, Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0, 2.6), _engine_mat))
			muzzles = [Vector3(0.7, 0, -2.6), Vector3(-0.7, 0, -2.6)]
			# Greebles: hull panel strips + dorsal antennas.
			_add_box(root, Vector3(0.15, 0.15, 1.5), Vector3(0.75, 0.1, 0), accent_mat)
			_add_box(root, Vector3(0.15, 0.15, 1.5), Vector3(-0.75, 0.1, 0), accent_mat)
			_add_box(root, Vector3(0.12, 0.12, 1.0), Vector3(0.75, 0.1, 1.5), accent_mat)
			_add_box(root, Vector3(0.12, 0.12, 1.0), Vector3(-0.75, 0.1, 1.5), accent_mat)
			_add_box(root, Vector3(0.5, 0.1, 0.4), Vector3(0, 0.6, 0.5), accent_mat)
			_add_cyl(root, 0.03, 0.05, 0.6, Vector3(0.2, 0.85, -1.6), accent_mat)
			_add_cyl(root, 0.03, 0.05, 0.6, Vector3(-0.2, 0.85, -1.6), accent_mat)
			# Running lights: flanks, nose, engines.
			_add_light(root, Vector3(1.3, 0.2, 0.6))
			_add_light(root, Vector3(-1.3, 0.2, 0.6))
			_add_light(root, Vector3(0.3, 0.3, -2.4))
			_add_light(root, Vector3(-0.3, 0.3, -2.4))
			_add_light(root, Vector3(0.5, 0.0, 2.7))
			_add_light(root, Vector3(-0.5, 0.0, 2.7))
		"frigate":
			_add_box(root, Vector3(2.4, 1.6, 7.0), Vector3(0, 0, 0), _hull_mat)
			_add_box(root, Vector3(1.2, 1.0, 2.0), Vector3(1.6, 0, 1.0), _hull_mat)    # side pods
			_add_box(root, Vector3(1.2, 1.0, 2.0), Vector3(-1.6, 0, 1.0), _hull_mat)
			var frig_t0: MeshInstance3D = _add_cyl(root, 0.5, 0.5, 0.6, Vector3(0, 1.1, -1.5), accent_mat)  # turret
			var frig_t1: MeshInstance3D = _add_cyl(root, 0.5, 0.5, 0.6, Vector3(0, 1.1, 1.5), accent_mat)
			_register_turret(frig_t0, Vector3(0, 1.1, -1.5), deg_to_rad(110.0), 1.2, fire_rate * 1.3)
			_register_turret(frig_t1, Vector3(0, 1.1, 1.5), deg_to_rad(110.0), 1.2, fire_rate * 1.3)
			_add_box(root, Vector3(0.8, 0.7, 1.2), Vector3(0, 0.9, -2.4), accent_mat)  # bridge
			_engine_nodes.append(_add_box(root, Vector3(0.7, 0.7, 0.6), Vector3(0.8, 0, 3.6), _engine_mat))
			_engine_nodes.append(_add_box(root, Vector3(0.7, 0.7, 0.6), Vector3(-0.8, 0, 3.6), _engine_mat))
			muzzles = [Vector3(1.0, 0.4, -3.6), Vector3(-1.0, 0.4, -3.6), Vector3(0, 1.1, -2.2)]
			# Greebles: hull + pod panels.
			_add_box(root, Vector3(0.2, 0.2, 2.0), Vector3(1.25, 0.2, 0), accent_mat)
			_add_box(root, Vector3(0.2, 0.2, 2.0), Vector3(-1.25, 0.2, 0), accent_mat)
			_add_box(root, Vector3(0.15, 0.15, 1.0), Vector3(1.7, 0.3, 1.0), accent_mat)
			_add_box(root, Vector3(0.15, 0.15, 1.0), Vector3(-1.7, 0.3, 1.0), accent_mat)
			_add_box(root, Vector3(0.3, 0.15, 0.6), Vector3(0, 0.85, 0.5), accent_mat)
			_add_box(root, Vector3(0.3, 0.15, 0.6), Vector3(0, 0.85, -0.5), accent_mat)
			# Vent cylinders underneath (equal radii — not exhaust plumes).
			_add_cyl(root, 0.12, 0.12, 0.3, Vector3(0.6, -0.85, 0.5), accent_mat)
			_add_cyl(root, 0.12, 0.12, 0.3, Vector3(-0.6, -0.85, 0.5), accent_mat)
			_add_cyl(root, 0.12, 0.12, 0.3, Vector3(0.6, -0.85, -0.5), accent_mat)
			_add_cyl(root, 0.12, 0.12, 0.3, Vector3(-0.6, -0.85, -0.5), accent_mat)
			# Running lights: pods, bridge, engines.
			_add_light(root, Vector3(2.2, 0.0, 1.0))
			_add_light(root, Vector3(-2.2, 0.0, 1.0))
			_add_light(root, Vector3(0.4, 0.9, -2.4))
			_add_light(root, Vector3(-0.4, 0.9, -2.4))
			_add_light(root, Vector3(0.8, 0.0, 3.7))
			_add_light(root, Vector3(-0.8, 0.0, 3.7))
		"capital":
			_add_box(root, Vector3(3.6, 2.4, 12.0), Vector3(0, 0, 0), _hull_mat)
			_add_box(root, Vector3(2.0, 1.2, 4.0), Vector3(0, 1.6, -1.0), _hull_mat)
			_add_box(root, Vector3(1.2, 0.9, 1.6), Vector3(0, 2.4, -3.0), accent_mat)  # bridge tower
			for i in range(4):
				var zz: float = -3.5 + float(i) * 2.4
				var cap_r: MeshInstance3D = _add_cyl(root, 0.45, 0.6, 0.9, Vector3(1.0, 1.4, zz), accent_mat)
				var cap_l: MeshInstance3D = _add_cyl(root, 0.45, 0.6, 0.9, Vector3(-1.0, 1.4, zz), accent_mat)
				_register_turret(cap_r, Vector3(1.0, 1.4, zz), deg_to_rad(85.0), 1.0, fire_rate * 2.0)
				_register_turret(cap_l, Vector3(-1.0, 1.4, zz), deg_to_rad(85.0), 1.0, fire_rate * 2.0)
			_add_box(root, Vector3(3.0, 1.8, 1.2), Vector3(0, 0, 6.2), _engine_mat)
			_engine_nodes.append(_add_box(root, Vector3(0.9, 0.9, 0.6), Vector3(1.0, 0, 6.6), _engine_mat))
			_engine_nodes.append(_add_box(root, Vector3(0.9, 0.9, 0.6), Vector3(-1.0, 0, 6.6), _engine_mat))
			muzzles = [Vector3(1.6, 0.6, -6.0), Vector3(-1.6, 0.6, -6.0), Vector3(0, 2.0, -5.0)]
			# Greebles: hull panels along both flanks.
			for gz in [-4.0, -2.0, 0.0, 2.0, 4.0]:
				_add_box(root, Vector3(0.25, 0.25, 1.2), Vector3(1.85, 0.4, gz), accent_mat)
				_add_box(root, Vector3(0.25, 0.25, 1.2), Vector3(-1.85, 0.4, gz), accent_mat)
			# Bridge-tower antenna array.
			for ai in range(5):
				_add_cyl(root, 0.04, 0.06, 0.8, Vector3(-0.4 + float(ai) * 0.2, 3.0, -3.0), accent_mat)
			# Belly vent cylinders (equal radii — not exhaust plumes).
			_add_cyl(root, 0.2, 0.2, 0.4, Vector3(0.8, -1.3, 2.0), accent_mat)
			_add_cyl(root, 0.2, 0.2, 0.4, Vector3(-0.8, -1.3, 2.0), accent_mat)
			# Running lights: flanks, nose, engines.
			_add_light(root, Vector3(1.9, 0.5, -5.0))
			_add_light(root, Vector3(-1.9, 0.5, -5.0))
			_add_light(root, Vector3(0.3, 1.0, -6.0))
			_add_light(root, Vector3(-0.3, 1.0, -6.0))
			_add_light(root, Vector3(1.0, 0.0, 6.5))
			_add_light(root, Vector3(-1.0, 0.0, 6.5))
		"station":
			var t: MeshInstance3D = MeshInstance3D.new()
			var torus: TorusMesh = TorusMesh.new()
			torus.inner_radius = 4.0
			torus.outer_radius = 6.0
			t.mesh = torus
			t.material_override = _hull_mat
			root.add_child(t)
			_add_cyl(root, 1.6, 1.6, 4.0, Vector3.ZERO, accent_mat)                   # central hub
			for i in range(6):
				var ang: float = float(i) * TAU / 6.0
				var sp: Node3D = Node3D.new()
				root.add_child(sp)
				_add_box(sp, Vector3(0.5, 0.5, 5.0), Vector3(sin(ang) * 2.6, 0, 0), _hull_mat)
				sp.rotation.y = ang
			_add_box(root, Vector3(1.0, 1.0, 1.0), Vector3(0, 2.4, 0), accent_mat)     # comms
			muzzles = [Vector3(0, 0, 6.0), Vector3(6.0, 0, 0), Vector3(-6.0, 0, 0), Vector3(0, 0, -6.0)]
			var st_positions: Array = [Vector3(0, 0, 6.0), Vector3(6.0, 0, 0), Vector3(-6.0, 0, 0), Vector3(0, 0, -6.0)]
			for sp_pos in st_positions:
				var st_t: MeshInstance3D = _add_cyl(root, 0.5, 0.5, 1.0, sp_pos, accent_mat)
				_register_turret(st_t, sp_pos, deg_to_rad(170.0), 1.5, fire_rate)
			# Greebles: ring-edge sensor blocks + hub strakes.
			for si in range(6):
				var sang: float = float(si) * TAU / 6.0
				_add_box(root, Vector3(0.4, 0.4, 0.4), Vector3(cos(sang) * 5.0, 0, sin(sang) * 5.0), accent_mat)
			_add_box(root, Vector3(1.8, 0.2, 0.2), Vector3(0, 1.2, 0), accent_mat)
			_add_box(root, Vector3(0.2, 0.2, 1.8), Vector3(0, -1.2, 0), accent_mat)
			# Running lights around the ring.
			for li in range(6):
				var lang: float = float(li) * TAU / 6.0
				_add_light(root, Vector3(cos(lang) * 5.0, 0.3, sin(lang) * 5.0))
		_:
			_add_box(root, Vector3(1, 1, 2), Vector3.ZERO, _hull_mat)
			muzzles = [Vector3(0, 0, -1.5)]

	# Engine exhaust plume behind each engine node (none for engineless stations).
	for en in _engine_nodes:
		var ep: Vector3 = en.position
		_add_exhaust(root, Vector3(ep.x, ep.y, ep.z + 0.8), 1.2)

	# Shield bubble (hidden until hit).
	_shield_mesh = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = radius() * 1.15
	sm.height = radius() * 2.3
	_shield_mesh.mesh = sm
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.albedo_color = Color(0.4, 0.7, 1.0, 0.0)
	_shield_mat.emission_enabled = true
	_shield_mat.emission = Color(0.4, 0.7, 1.0)
	_shield_mat.emission_energy_multiplier = 1.5
	_shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mesh.material_override = _shield_mat
	add_child(_shield_mesh)
	_try_load_meshy_visual()

func _try_load_meshy_visual() -> void:
	# Opt-in swap: replace the procedural Hull visual with the Meshy GLB for
	# the 5 hard-scoped hero classes. All other entities (frigate, neutral
	# station, friendly fighter, etc.) keep their procedural visual.
	# Falls back silently to the procedural build if the GLB is missing or
	# Godot fails to import it (e.g. before meshy_generate.py has finished).
	if not Game.MESHY_VISUAL_UPGRADE_ENABLED:
		return
	var key: String = "%s|%s" % [ship_class, faction]
	var basename: Variant = Game.MESHY_SHIP_GLB.get(key, null)
	if basename == null:
		return
	var path: String = "res://assets/models/meshy_visual_upgrade/%s.repacked.glb" % String(basename)
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("[meshy] %s: GLB missing or failed to import — keeping procedural visual" % path)
		return
	var glb_root: Node = packed.instantiate()
	if glb_root == null:
		push_warning("[meshy] %s: GLB instantiate() returned null — keeping procedural" % path)
		return
	# The visual child we want is the first MeshInstance3D in the GLB tree;
	# for rigged GLBs it lives under a Skeleton3D. Pull it up so its
	# transforms (scale, rotation) compose directly with the ship node and
	# we don't double-render the Skeleton3D's empty child meshes.
	var mi: MeshInstance3D = _detach_first_mesh_instance(glb_root)
	glb_root.queue_free()
	if mi == null:
		push_warning("[meshy] %s: GLB has no MeshInstance3D child — keeping procedural" % path)
		return
	mi.name = "%sMeshy" % String(basename).capitalize()
	# Reparent the mesh out of glb_root BEFORE freeing the root, otherwise
	# queue_free cascades and our visual gets destroyed with it.
	if mi.get_parent() != null:
		mi.get_parent().remove_child(mi)
	glb_root.queue_free()
	# Scale + center the Meshy mesh to match the procedural model's footprint
	# for this class. Meshy GLBs are all normalized to ~1.9 units regardless
	# of class, but procedural models range from ~3 units (fighter) up to
	# ~120 units (station, scale 10). Without this the Meshy station renders
	# as a tiny speck where a huge station should be. Must run while the
	# procedural Hull is still visible so we can measure it.
	_fit_meshy_to_hull(mi)
	# Hide procedural meshes BEFORE adding the Meshy mesh, or the Meshy
	# mesh (also a VisualInstance3D) would get caught in the hide sweep
	# over get_children() and be made invisible too. The procedural mesh
	# remains attached (for raycast hitboxes that depend on the original
	# Node3D layout) but is hidden from view.
	_hide_procedural_visual()
	add_child(mi)

func _fit_meshy_to_hull(mi: MeshInstance3D) -> void:
	# Resize the detached Meshy mesh so its horizontal footprint matches the
	# procedural Hull it is replacing, then recenter it on the Hull centroid.
	# Purely visual — gameplay radius()/collision are unaffected.
	var hull: Node3D = get_node_or_null("Hull")
	if hull == null or mi.mesh == null:
		mi.scale = Vector3.ONE
		return
	var hull_aabb: AABB = _subtree_local_aabb(hull)
	var mesh_aabb: AABB = mi.mesh.get_aabb()
	var hs: float = hull.scale.x  # Hull uses uniform class scale
	# Procedural size in ship-space = local AABB * Hull scale.
	var target: Vector3 = hull_aabb.size * hs
	var target_span: float = max(target.x, target.z)
	var mesh_span: float = max(mesh_aabb.size.x, mesh_aabb.size.z)
	if target_span <= 0.0 or mesh_span <= 0.0:
		mi.scale = Vector3.ONE
		return
	var f: float = target_span / mesh_span
	# Meshy GLBs are authored with the hull's long axis along X, but the game
	# flies -Z forward (procedural ships are built pointing -Z). Yaw the mesh
	# so its long axis aligns with the direction of travel; without this the
	# ship visibly flies sideways. Stations are radially symmetric, so the
	# same yaw is a harmless no-op for them.
	var basis: Basis = Basis(Vector3.UP, MESHY_FORWARD_YAW).scaled(Vector3(f, f, f))
	mi.basis = basis
	# Align the mesh centroid with the Hull centroid (both in ship space),
	# measuring the mesh AABB AFTER the yaw+scale so the offset is correct.
	var t_aabb: AABB = _xform_aabb(Transform3D(basis, Vector3.ZERO), mesh_aabb)
	var hull_center: Vector3 = (hull_aabb.position + hull_aabb.size * 0.5) * hs
	var mesh_center: Vector3 = t_aabb.position + t_aabb.size * 0.5
	mi.position = hull_center - mesh_center

func _subtree_local_aabb(root: Node3D) -> AABB:
	# Union of every descendant MeshInstance3D AABB, expressed in root's local
	# space (root's own transform excluded). Handles nested Node3D layers such
	# as the station's spoke nodes.
	var acc: Dictionary = {"aabb": AABB(), "has": false}
	_accum_aabb(root, Transform3D.IDENTITY, acc)
	return acc["aabb"] if acc["has"] else AABB()

func _accum_aabb(node: Node, xform: Transform3D, acc: Dictionary) -> void:
	for c in node.get_children():
		var cx: Transform3D = xform
		if c is Node3D:
			cx = xform * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var t: AABB = _xform_aabb(cx, (c as MeshInstance3D).mesh.get_aabb())
			if not acc["has"]:
				acc["aabb"] = t
				acc["has"] = true
			else:
				acc["aabb"] = (acc["aabb"] as AABB).merge(t)
		_accum_aabb(c, cx, acc)

func _xform_aabb(t: Transform3D, a: AABB) -> AABB:
	# Transform an AABB by a Transform3D and return the enclosing axis-aligned box.
	var corners: Array = [
		a.position,
		a.position + Vector3(a.size.x, 0, 0),
		a.position + Vector3(0, a.size.y, 0),
		a.position + Vector3(0, 0, a.size.z),
		a.position + Vector3(a.size.x, a.size.y, 0),
		a.position + Vector3(a.size.x, 0, a.size.z),
		a.position + Vector3(0, a.size.y, a.size.z),
		a.position + a.size,
	]
	var out: AABB = AABB(t * (corners[0] as Vector3), Vector3.ZERO)
	for i in range(1, 8):
		out = out.expand(t * (corners[i] as Vector3))
	return out

func _detach_first_mesh_instance(node: Node) -> MeshInstance3D:
	# Walk the instantiated GLB scene, find the first MeshInstance3D with a
	# mesh, and reparent it to its current top-level root. Returns null if
	# no suitable mesh was found. Reparenting (instead of re-instantiating)
	# preserves the MeshInstance3D's world transform when added to the ship.
	for c in node.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var found: MeshInstance3D = c
			# Capture the local transform relative to its parent so we can
			# apply it after reparenting to the ship node.
			var xform: Transform3D = found.transform
			found.transform = Transform3D.IDENTITY
			node.remove_child(found)
			node.add_child(found)
			found.transform = xform
			return found
		var found2: MeshInstance3D = _detach_first_mesh_instance(c)
		if found2 != null:
			return found2
	return null

func _hide_procedural_visual() -> void:
	# Hide every procedural VisualInstance3D so only the Meshy mesh renders.
	# Walks the Hull subtree (primitives built by _build_mesh) and any
	# siblings added directly to the entity itself (e.g. _shield_mesh,
	# turret meshes, engine exhaust cones). The collision shapes are not
	# VisualInstance3D so they stay live for raycasts and hitboxes.
	#
	# The walk MUST recurse: the station class nests its spoke-arm meshes
	# under intermediate Node3D "spoke" nodes (see _build_mesh "station"),
	# so a one-level sweep of Hull's direct children would leave those arms
	# visible and the Meshy station would render buried inside the
	# procedural ring. _hide_visuals_recursive descends the full subtree.
	var hull: Node = get_node_or_null("Hull")
	if hull != null:
		_hide_visuals_recursive(hull)
	for c in get_children():
		if c is VisualInstance3D:
			(c as VisualInstance3D).visible = false

func _hide_visuals_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is VisualInstance3D:
			(c as VisualInstance3D).visible = false
		_hide_visuals_recursive(c)

func take_damage(amount: float, subsystem: String = "") -> Dictionary:
	# Returns event info. When a subsystem is targeted, 50% of the post-shield hull
	# damage is routed into that subsystem's health and 50% to the hull as normal.
	var result: Dictionary = {"shield_hit": false, "disabled": false, "destroyed": false, "subsystem_hit": false}
	if destroyed:
		return result
	if invulnerable:
		# Demo/capture flagship: report a shield flash for VFX but absorb everything.
		result["shield_hit"] = true
		_shield_flash = 0.35
		return result
	var dmg: float = amount
	if shield > 0.0:
		result["shield_hit"] = true
		_shield_flash = 0.35
		var absorbed: float = min(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
	if dmg > 0.0:
		var hull_dmg: float = dmg
		if subsystem != "":
			var sub_dmg: float = dmg * 0.5
			hull_dmg = dmg - sub_dmg
			_damage_subsystem(subsystem, sub_dmg)
			result["subsystem_hit"] = true
		hull -= hull_dmg
	# Disable threshold (GameConstants.DISABLE_FRAC). Stations/capitals can be disabled then boarded.
	if not disabled and hull <= max_hull * GC.DISABLE_FRAC and hull > 0.0:
		disabled = true
		result["disabled"] = true
		# Disabling fight costs the defenders half their garrison (rounded down).
		marine_garrison = int(floor(float(marine_garrison) / 2.0))
	if hull <= 0.0:
		hull = 0.0
		# Disabled ships are captured, not destroyed, when reduced further while boarded.
		destroyed = true
		result["destroyed"] = true
	return result

func _damage_subsystem(subsystem: String, dmg: float) -> void:
	# Convert raw post-shield damage into a 0..1 health loss scaled to this ship's hull.
	var frac_loss: float = dmg / max(1.0, max_hull * SUB_HEALTH_FRAC)
	match subsystem:
		"engines":
			sub_engine = max(0.0, sub_engine - frac_loss)
		"weapons":
			sub_weapon = max(0.0, sub_weapon - frac_loss)
		"shields":
			sub_shield = max(0.0, sub_shield - frac_loss)
			if sub_shield <= 0.0:
				shield = 0.0   # shield generator destroyed: collapse the bubble

func subsystem_status(frac: float) -> String:
	if frac <= 0.0:
		return "OFFLINE"
	if frac < SUB_DAMAGED_FRAC:
		return "DAMAGED"
	return "OK"

# --- Subsystem effect multipliers ------------------------------------------
# Engines: OFFLINE -> 20% speed/accel, 40% turn; DAMAGED -> 60% speed/accel, 70% turn.
func _engine_speed_mult() -> float:
	if sub_engine <= 0.0:
		return 0.2
	if sub_engine < SUB_DAMAGED_FRAC:
		return 0.6
	return 1.0

func _engine_turn_mult() -> float:
	if sub_engine <= 0.0:
		return 0.4
	if sub_engine < SUB_DAMAGED_FRAC:
		return 0.7
	return 1.0

func eff_max_speed() -> float:
	return max_speed * _engine_speed_mult()

func eff_accel() -> float:
	return accel * _engine_speed_mult()

func eff_turn_rate() -> float:
	return turn_rate * _engine_turn_mult()

func guard_station_node() -> Node3D:
	# Resolve the assigned guard station by name. The ships registry lives on Main (this
	# ship's parent), not in a group, so we duck-type _find_ship_by_name() on the parent.
	# Returns null unless the named node is a live, non-hostile station.
	if guard_station_name == "":
		return null
	var p: Node = get_parent()
	if p == null or not p.has_method("_find_ship_by_name"):
		return null
	var st: Node3D = p.call("_find_ship_by_name", guard_station_name)
	if not is_instance_valid(st):
		return null
	if String(st.ship_class) != "station" or bool(st.destroyed) or String(st.faction) == "hostile":
		return null
	return st

# Weapons: OFFLINE -> cannot fire; DAMAGED -> fire cooldown doubled (half rate).
func can_fire() -> bool:
	return sub_weapon > 0.0

func weapon_cd_mult() -> float:
	if sub_weapon < SUB_DAMAGED_FRAC:
		return 2.0
	return 1.0

# Shields: OFFLINE -> no regen (and bubble collapsed); DAMAGED -> 30% regen.
func shield_regen_mult() -> float:
	if sub_shield <= 0.0:
		return 0.0
	if sub_shield < SUB_DAMAGED_FRAC:
		return 0.3
	return 1.0

func restore_subsystems(fraction: float = 1.0) -> void:
	sub_engine = min(1.0, sub_engine + (1.0 - sub_engine) * fraction)
	sub_weapon = min(1.0, sub_weapon + (1.0 - sub_weapon) * fraction)
	sub_shield = min(1.0, sub_shield + (1.0 - sub_shield) * fraction)

func set_faction(p_faction: String) -> void:
	faction = p_faction
	var col: Color = _faction_color()
	if _hull_mat:
		_hull_mat.albedo_color = col.darkened(0.35)

func tick_visuals(delta: float) -> void:
	# Engine glow scales with throttle; shield flashes on hit.
	var glow: float = 2.0 + throttle * 4.0
	if disabled:
		glow = 0.2
	if _engine_mat:
		_engine_mat.emission_energy_multiplier = glow
	if _shield_flash > 0.0:
		_shield_flash -= delta
	var a: float = clamp(_shield_flash, 0.0, 0.35)
	if _shield_mat:
		_shield_mat.albedo_color = Color(0.4, 0.7, 1.0, a)
	# Running lights pulse slowly between 0.8 and 2.0 energy on a shared phase.
	_light_accum += delta
	if _running_light_mat:
		_running_light_mat.emission_energy_multiplier = 1.4 + sin(_light_accum * 2.0) * 0.6
	# Engine exhaust grows and brightens with throttle; near-invisible when disabled.
	var ex_len: float = 0.5 + throttle * 1.5
	var ex_alpha: float = 0.3 + throttle * 0.4
	if disabled:
		ex_len = 0.3
		ex_alpha = 0.05
	if _exhaust_mat:
		_exhaust_mat.albedo_color = Color(0.5, 0.7, 1.0, ex_alpha)
	for ex in _exhaust_nodes:
		if is_instance_valid(ex):
			ex.scale = Vector3(1.0, ex_len, 1.0)  # mesh-local Y == plume length (post-rotation Z)

# --- Independent turret subsystems -----------------------------------------
func _register_turret(node: MeshInstance3D, pos: Vector3, arc_half: float, muzzle_fwd: float, base_cd: float) -> void:
	turrets.append({
		"node": node,
		"pos": pos,
		"muzzle_fwd": muzzle_fwd,
		"yaw": 0.0,
		"arc_half": arc_half,
		"cd": 0.0,
		"base_cd": base_cd,
	})

func has_turrets() -> bool:
	return turrets.size() > 0

func tick_turrets(delta: float, aim_target: Node3D) -> void:
	# Rotate each turret toward the aim target, clamped to its fire arc.
	# Decrement per-turret cooldown. Called from main.gd _process_space.
	if turrets.is_empty():
		return
	if aim_target == null or not is_instance_valid(aim_target):
		# No target: turrets return to center (yaw → 0) and cooldowns still tick.
		for t in turrets:
			var td: Dictionary = t
			td["yaw"] = move_toward(float(td["yaw"]), 0.0, 1.5 * delta)
			td["cd"] = max(0.0, float(td["cd"]) - delta)
			_apply_turret_visual(td)
		return
	var to_target: Vector3 = aim_target.global_position - global_position
	var local_dir: Vector3 = global_transform.basis.inverse() * to_target
	# Desired yaw = atan2 of local_dir.x, -local_dir.z (ship forward is -Z)
	var desired_yaw: float = atan2(local_dir.x, -local_dir.z)
	for t in turrets:
		var td: Dictionary = t
		var clamped_yaw: float = clamp(desired_yaw, -float(td["arc_half"]), float(td["arc_half"]))
		# Smoothly track toward the clamped yaw
		var track_speed: float = 3.0  # radians per second
		td["yaw"] = move_toward(float(td["yaw"]), clamped_yaw, track_speed * delta)
		td["cd"] = max(0.0, float(td["cd"]) - delta)
		_apply_turret_visual(td)

func _apply_turret_visual(td: Dictionary) -> void:
	var node: MeshInstance3D = td["node"]
	if is_instance_valid(node):
		node.rotation.y = float(td["yaw"])

func turret_muzzle_world(idx: int) -> Vector3:
	# World position of a turret's muzzle, accounting for turret yaw.
	var td: Dictionary = turrets[idx]
	var yaw: float = float(td["yaw"])
	var pos: Vector3 = td["pos"]
	var fwd: float = float(td["muzzle_fwd"])
	# Muzzle local offset: turret pos + forward rotated by yaw
	var muzzle_local: Vector3 = pos + Vector3(sin(yaw) * fwd, 0.0, -cos(yaw) * fwd)
	var scale: float = float(Game.class_info(ship_class).get("scale", 1.0))
	return global_transform * (muzzle_local * scale)

func turret_fire_dir(idx: int) -> Vector3:
	# World-space direction the turret is currently pointing.
	var td: Dictionary = turrets[idx]
	var yaw: float = float(td["yaw"])
	var local_dir: Vector3 = Vector3(sin(yaw), 0.0, -cos(yaw))
	return (global_transform.basis * local_dir).normalized()

func turret_in_arc(idx: int, aim_target: Node3D) -> bool:
	# True if the target is within this turret's fire arc.
	if aim_target == null or not is_instance_valid(aim_target):
		return false
	var td: Dictionary = turrets[idx]
	var to_target: Vector3 = (aim_target.global_position - global_position).normalized()
	var local_dir: Vector3 = global_transform.basis.inverse() * to_target
	var desired_yaw: float = atan2(local_dir.x, -local_dir.z)
	return abs(desired_yaw) <= float(td["arc_half"])

func turret_aimed(idx: int, aim_target: Node3D, tolerance: float = 0.1) -> bool:
	# True if turret yaw is close enough to the desired yaw to fire.
	if not turret_in_arc(idx, aim_target):
		return false
	var to_target: Vector3 = (aim_target.global_position - global_position).normalized()
	var local_dir: Vector3 = global_transform.basis.inverse() * to_target
	var desired_yaw: float = atan2(local_dir.x, -local_dir.z)
	var td: Dictionary = turrets[idx]
	return abs(float(td["yaw"]) - desired_yaw) < tolerance

func turret_ready_and_aimed(idx: int, aim_target: Node3D) -> bool:
	var td: Dictionary = turrets[idx]
	return float(td["cd"]) <= 0.0 and turret_aimed(idx, aim_target)

func turret_state_to_array() -> Array:
	var out: Array = []
	for t in turrets:
		var td: Dictionary = t
		out.append({"yaw": float(td["yaw"]), "cd": float(td["cd"])})
	return out

func restore_turret_state(state: Array) -> void:
	for i in range(mini(state.size(), turrets.size())):
		var sd: Dictionary = state[i]
		var td: Dictionary = turrets[i]
		td["yaw"] = float(sd.get("yaw", 0.0))
		td["cd"] = float(sd.get("cd", 0.0))
		_apply_turret_visual(td)
