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
# flagship stays framed for the entire screenshot window. Never set in
# normal gameplay.
var invulnerable: bool = false

var attack_target: Node3D = null
var ai_state: String = ""
var wander_origin: Vector3 = Vector3.ZERO
var wander_offset: float = 0.0
var evading: bool = false
var evade_timer: float = 0.0
var flee_timer: float = 0.0
var boarder_alert: bool = false

var _engine_nodes: Array = []
var _turret_nodes: Array = []
var _hull_mat: StandardMaterial3D = null
var _shield_mesh: MeshInstance3D = null
var _shield_mat: StandardMaterial3D = null
var _shield_flash: float = 0.0
var _class_color: Color = Color.WHITE
var class_color: Color:
	get: return _class_color
	set(v):
		_class_color = v
		_update_material_colors()

var _tone: Color = Color.WHITE

const UPGRADE_MAX_LEVEL: int = 4

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
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _add_cyl(parent: Node3D, r: float, h: float, z_scale: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = h
	mi.mesh = cyl
	mi.scale = Vector3(1, z_scale, 1)
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _add_sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi

func _add_light(parent: Node3D, pos: Vector3) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	mi.mesh = sm
	mi.position = pos
	var lm: StandardMaterial3D = StandardMaterial3D.new()
	lm.albedo_color = Color(0.3, 1.0, 0.4)
	lm.emission_enabled = true
	lm.emission = Color(0.3, 1.0, 0.4)
	lm.emission_energy_multiplier = 2.0
	mi.material_override = lm
	parent.add_child(mi)

func _add_exhaust(parent: Node3D, pos: Vector3, scale: float) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.3 * scale
	cone.height = 0.6 * scale
	mi.mesh = cone
	mi.position = pos
	var em: StandardMaterial3D = StandardMaterial3D.new()
	em.albedo_color = Color(1, 0.6, 0.2)
	em.emission_enabled = true
	em.emission = Color(1, 0.5, 0.1)
	em.emission_energy_multiplier = 1.5
	mi.material_override = em
	parent.add_child(mi)

var muzzles: Array = []

func _register_turret(mi: MeshInstance3D, pos: Vector3, arc_rad: float, turn_speed: float, custom_fire_rate: float) -> void:
	# Place a turret mesh at the given local position and register it for AI control.
	# The turret can only rotate within ±arc_rad of its initial forward (Z-) direction.
	# Also registers a muzzle (half a unit forward of the turret root) for projectile spawn.
	_turret_nodes.append({"node": mi, "pos": pos, "arc": arc_rad, "speed": turn_speed, "fire_rate": custom_fire_rate, "yaw": 0.0})
	muzzles.append(pos + Vector3(0, 0, -0.5))

func _update_material_colors() -> void:
	if _hull_mat == null:
		return
	var col: Color = _faction_color()
	_hull_mat.albedo_color = col.darkened(0.35)
	_hull_mat.emission = col

func _build_mesh() -> void:
	var r: float = radius()
	var root: Node3D = Node3D.new()
	root.name = "Hull"
	add_child(root)
	# Class-coloured hull. Assign once so it persists for _update_material_colors calls.
	var col: Color = _faction_color()
	_hull_mat = _make_mat(col, 0.0)
	muzzles = []
	# Build the procedural hull based on ship_class.
	match ship_class:
		"fighter":
			# Small, angular fuselage
			_add_box(root, Vector3(0.5, 0.3, 1.2), Vector3.ZERO, _hull_mat)
			_add_box(root, Vector3(1.2, 0.2, 0.3), Vector3(0, 0, 0.6), _hull_mat)
			_add_cyl(root, 0.15, 0.8, 1.0, Vector3(0, 0, -1.0), _hull_mat)
			_engine_nodes = [Node3D.new(), Node3D.new()]
			_engine_nodes[0].position = Vector3(-0.3, 0, -1.0)
			_engine_nodes[1].position = Vector3(0.3, 0, -1.0)
			for en in _engine_nodes:
				root.add_child(en)
			muzzles = [Vector3(0, 0, -1.5)]
		"corvette":
			# Medium wedge
			_add_box(root, Vector3(0.7, 0.4, 1.6), Vector3(0, 0, 0.2), _hull_mat)
			_add_box(root, Vector3(1.4, 0.25, 0.4), Vector3(0, 0, 0.8), _hull_mat)
			_add_cyl(root, 0.2, 1.0, 1.0, Vector3(0, 0, -1.2), _hull_mat)
			_engine_nodes = [Node3D.new(), Node3D.new()]
			_engine_nodes[0].position = Vector3(-0.5, 0, -1.2)
			_engine_nodes[1].position = Vector3(0.5, 0, -1.2)
			for en in _engine_nodes:
				root.add_child(en)
			muzzles = [Vector3(0, 0, -2.0)]
		"frigate":
			# Long hull
			_add_box(root, Vector3(1.0, 0.5, 2.8), Vector3.ZERO, _hull_mat)
			_add_box(root, Vector3(0.4, 0.3, 0.6), Vector3(-0.8, 0, 1.4), _hull_mat)
			_add_box(root, Vector3(0.4, 0.3, 0.6), Vector3(0.8, 0, 1.4), _hull_mat)
			_add_cyl(root, 0.25, 1.2, 1.0, Vector3(0, 0, -2.0), _hull_mat)
			_engine_nodes = [Node3D.new(), Node3D.new(), Node3D.new(), Node3D.new()]
			_engine_nodes[0].position = Vector3(-0.6, 0, -2.0)
			_engine_nodes[1].position = Vector3(0.6, 0, -2.0)
			_engine_nodes[2].position = Vector3(-0.3, 0.3, -2.0)
			_engine_nodes[3].position = Vector3(0.3, -0.3, -2.0)
			for en in _engine_nodes:
				root.add_child(en)
			muzzles = [Vector3(0, 0, -3.0)]
		"capital":
			# Largest: boxy with flank accents
			_add_box(root, Vector3(1.6, 0.7, 3.6), Vector3.ZERO, _hull_mat)
			_add_box(root, Vector3(2.0, 0.3, 0.6), Vector3(0, 0, 1.8), _hull_mat)
			_add_box(root, Vector3(0.4, 0.4, 0.8), Vector3(-1.2, 0, 1.2), _hull_mat)
			_add_box(root, Vector3(0.4, 0.4, 0.8), Vector3(1.2, 0, 1.2), _hull_mat)
			_add_box(root, Vector3(0.3, 0.6, 0.3), Vector3(-1.0, 0.5, -0.5), _hull_mat)
			_add_box(root, Vector3(0.3, 0.6, 0.3), Vector3(1.0, 0.5, -0.5), _hull_mat)
			_add_cyl(root, 0.3, 1.6, 1.0, Vector3(0, 0, -2.8), _hull_mat)
			_engine_nodes = [Node3D.new(), Node3D.new(), Node3D.new(), Node3D.new(), Node3D.new(), Node3D.new()]
			_engine_nodes[0].position = Vector3(-1.0, 0, -2.8)
			_engine_nodes[1].position = Vector3(1.0, 0, -2.8)
			_engine_nodes[2].position = Vector3(-0.5, 0.4, -2.8)
			_engine_nodes[3].position = Vector3(0.5, -0.4, -2.8)
			_engine_nodes[4].position = Vector3(-0.5, -0.4, -2.8)
			_engine_nodes[5].position = Vector3(0.5, 0.4, -2.8)
			for en in _engine_nodes:
				root.add_child(en)
			muzzles = [Vector3(0, 0, -3.8)]
		"station":
			# Ring-shaped hub
			var accent_mat: StandardMaterial3D = _make_mat(col.lightened(0.3), 0.4)
			var accent_col: Color = col.lightened(0.3)
			# Main ring
			_add_cyl(root, 5.0, 0.5, 1.0, Vector3.ZERO, _hull_mat)
			# Central hub
			_add_cyl(root, 1.5, 2.0, 1.0, Vector3.ZERO, _hull_mat)
			# Spokes connecting hub to ring
			_add_box(root, Vector3(0.2, 0.2, 4.0), Vector3(0, 0, 0), accent_mat)
			_add_box(root, Vector3(4.0, 0.2, 0.2), Vector3(0, 0, 0), accent_mat)
			# Turrets on ring edge
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
	mi.scale = Vector3.ONE  # Meshy ships are ~1m-class; matches procedural scale
	# Reparent the mesh out of glb_root BEFORE freeing the root, otherwise
	# queue_free cascades and our visual gets destroyed with it.
	if mi.get_parent() != null:
		mi.get_parent().remove_child(mi)
	glb_root.queue_free()
	# Hide procedural meshes BEFORE adding the Meshy mesh, or the Meshy
	# mesh (also a VisualInstance3D) would get caught in the hide sweep.
	_hide_procedural_visual()
	add_child(mi)

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
	# Walks both the Hull child (primitives built by _build_mesh) and any
	# siblings added directly to the entity itself (e.g. _shield_mesh,
	# turret meshes, engine exhaust cones). The collision shapes are not
	# VisualInstance3D so they stay live for raycasts and hitboxes.
	var hull: Node = get_node_or_null("Hull")
	if hull != null:
		for c in hull.get_children():
			if c is VisualInstance3D:
				(c as VisualInstance3D).visible = false
	for c in get_children():
		if c is VisualInstance3D:
			(c as VisualInstance3D).visible = false
