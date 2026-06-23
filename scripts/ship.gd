extends Node3D
# Ship: a single space vessel (player, ally, hostile or neutral). Procedurally
# code-built mesh per class. No class_name (avoids circular imports). Driven by main.gd.

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

var weapon_type: String = "cannon"
var weapon_dmg: float = 7.0
var fire_rate: float = 0.2
var weapon_range: float = 220.0
var weapon_cd: float = 0.0

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
# when the ship is disabled (some defenders are casualties of the disabling fight); zeroed
# on capture (the new owner must garrison it themselves — out of scope this increment).
var marine_garrison: int = 0

var velocity: Vector3 = Vector3.ZERO
var throttle: float = 0.0           # 0..1 commanded throttle
var boosting: bool = false
var disabled: bool = false
var destroyed: bool = false

var target: Node3D = null
var ai_state: String = "engage"
var board_progress: float = 0.0     # 0..1 when being boarded by player marines
var being_boarded: bool = false

var class_color: Color = Color.WHITE
var _hull_mat: StandardMaterial3D
var _accent_mat: StandardMaterial3D
var _engine_mat: StandardMaterial3D
var _shield_mesh: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _shield_flash: float = 0.0
var _engine_nodes: Array = []
var muzzles: Array = []             # Array[Vector3] local-space muzzle offsets

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
	marine_garrison = int(info.get("garrison", 0))
	class_color = info.get("color", Color.WHITE)
	_build_mesh()

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

func _build_mesh() -> void:
	var hull_col: Color = _faction_color()
	_hull_mat = _make_mat(hull_col, 0.0)
	var accent_mat: StandardMaterial3D = _make_mat(hull_col, 1.6)
	_engine_mat = _make_mat(Color(1.0, 0.65, 0.25), 4.0)

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
		"corvette":
			_add_box(root, Vector3(1.4, 1.0, 5.0), Vector3(0, 0, 0), _hull_mat)
			_add_box(root, Vector3(2.6, 0.3, 1.6), Vector3(0, 0.2, 0.6), _hull_mat)
			_add_box(root, Vector3(0.6, 0.6, 1.2), Vector3(0, 0.55, -1.6), accent_mat)
			_add_box(root, Vector3(0.4, 0.4, 0.8), Vector3(1.0, 0, 1.0), _hull_mat)
			_add_box(root, Vector3(0.4, 0.4, 0.8), Vector3(-1.0, 0, 1.0), _hull_mat)
			_engine_nodes.append(_add_box(root, Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0, 2.6), _engine_mat))
			_engine_nodes.append(_add_box(root, Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0, 2.6), _engine_mat))
			muzzles = [Vector3(0.7, 0, -2.6), Vector3(-0.7, 0, -2.6)]
		"frigate":
			_add_box(root, Vector3(2.4, 1.6, 7.0), Vector3(0, 0, 0), _hull_mat)
			_add_box(root, Vector3(1.2, 1.0, 2.0), Vector3(1.6, 0, 1.0), _hull_mat)    # side pods
			_add_box(root, Vector3(1.2, 1.0, 2.0), Vector3(-1.6, 0, 1.0), _hull_mat)
			_add_cyl(root, 0.5, 0.5, 0.6, Vector3(0, 1.1, -1.5), accent_mat)           # turret
			_add_cyl(root, 0.5, 0.5, 0.6, Vector3(0, 1.1, 1.5), accent_mat)
			_add_box(root, Vector3(0.8, 0.7, 1.2), Vector3(0, 0.9, -2.4), accent_mat)  # bridge
			_engine_nodes.append(_add_box(root, Vector3(0.7, 0.7, 0.6), Vector3(0.8, 0, 3.6), _engine_mat))
			_engine_nodes.append(_add_box(root, Vector3(0.7, 0.7, 0.6), Vector3(-0.8, 0, 3.6), _engine_mat))
			muzzles = [Vector3(1.0, 0.4, -3.6), Vector3(-1.0, 0.4, -3.6), Vector3(0, 1.1, -2.2)]
		"capital":
			_add_box(root, Vector3(3.6, 2.4, 12.0), Vector3(0, 0, 0), _hull_mat)
			_add_box(root, Vector3(2.0, 1.2, 4.0), Vector3(0, 1.6, -1.0), _hull_mat)
			_add_box(root, Vector3(1.2, 0.9, 1.6), Vector3(0, 2.4, -3.0), accent_mat)  # bridge tower
			for i in range(4):
				var zz: float = -3.5 + float(i) * 2.4
				_add_cyl(root, 0.45, 0.6, 0.9, Vector3(1.0, 1.4, zz), accent_mat)
				_add_cyl(root, 0.45, 0.6, 0.9, Vector3(-1.0, 1.4, zz), accent_mat)
			_add_box(root, Vector3(3.0, 1.8, 1.2), Vector3(0, 0, 6.2), _engine_mat)
			_engine_nodes.append(_add_box(root, Vector3(0.9, 0.9, 0.6), Vector3(1.0, 0, 6.6), _engine_mat))
			_engine_nodes.append(_add_box(root, Vector3(0.9, 0.9, 0.6), Vector3(-1.0, 0, 6.6), _engine_mat))
			muzzles = [Vector3(1.6, 0.6, -6.0), Vector3(-1.6, 0.6, -6.0), Vector3(0, 2.0, -5.0)]
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
		_:
			_add_box(root, Vector3(1, 1, 2), Vector3.ZERO, _hull_mat)
			muzzles = [Vector3(0, 0, -1.5)]

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

func take_damage(amount: float, subsystem: String = "") -> Dictionary:
	# Returns event info. When a subsystem is targeted, 50% of the post-shield hull
	# damage is routed into that subsystem's health and 50% to the hull as normal.
	var result: Dictionary = {"shield_hit": false, "disabled": false, "destroyed": false, "subsystem_hit": false}
	if destroyed:
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
	# Disable threshold: 22% hull. Stations/capitals can be disabled then boarded.
	if not disabled and hull <= max_hull * 0.22 and hull > 0.0:
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
