extends Node3D
# Main: orchestrator for the Voidborne Command vertical slice. Code-builds the whole
# space battle (environment, stars, ships, station, projectiles, beams, explosions,
# camera), runs flight/combat/AI/boarding/economy/fleet logic, hosts the crew deck,
# and feeds the HUD each frame. No class_name (attached via scenes/main.tscn ext_resource).

const ShipScript: GDScript = preload("res://scripts/ship.gd")
const HudScript: GDScript = preload("res://scripts/hud.gd")
const DeckScript: GDScript = preload("res://scripts/crew_deck.gd")
const AudioScript: GDScript = preload("res://scripts/audio.gd")

# --- World object registries ------------------------------------------------
var ships: Array = []              # all live Ship nodes (player, allies, hostiles, station)
var player: Node3D = null
var station: Node3D = null
var projectiles: Array = []        # Array of dicts {node, vel, dmg, ttl, faction}
var beams: Array = []              # Array of dicts {node, ttl}
var explosions: Array = []         # Array of dicts {node, mat, ttl, life, scale}

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var space_camera: Camera3D
var world_env: WorldEnvironment
var hud: Control
var deck: Node3D
var audio: Node

# --- Player flight/combat state ---------------------------------------------
var throttle: float = 0.4
var target: Node3D = null
var deck_mode: bool = false

# Boarding state.
var boarding_active: bool = false
var boarding_target: Node3D = null
var boarding_progress: float = 0.0
const BOARD_RATE: float = 0.32     # progress per second per marine-batch

# Economy costs.
const COST_CREW: int = 120
const COST_MARINE: int = 180
const SHIPYARD_CLASSES: Array = ["corvette", "fighter", "frigate", "capital"]
var shipyard_index: int = 0

# Capture/demo: when launched for screenshots, the player auto-fights so frames are lively.
var auto_demo: bool = false

var messages: Array = []           # rolling message log (strings)
var objective: String = "Disable & board the hostile FRIGATE, then capture the STATION."
var _elapsed: float = 0.0

func _ready() -> void:
	rng.seed = 20260623
	auto_demo = OS.get_environment("VOIDBORNE_CAPTURE") != "" or OS.has_feature("demo")
	Game.reset()
	_build_environment()
	_build_stars()
	_build_battle()
	if auto_demo:
		_stage_capture_demo()
	_build_hud()
	_build_deck()
	audio = AudioScript.new()
	audio.name = "Audio"
	add_child(audio)
	_msg("Voidborne Command online. WASD/QE fly, Space fire, Tab target.")
	_msg("Fly to the STATION (neutral) to recruit crew/marines and buy ships.")

# ---------------------------------------------------------------------------
# WORLD CONSTRUCTION
# ---------------------------------------------------------------------------
func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.20, 0.28)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	env.fog_enabled = false
	world_env.environment = env
	add_child(world_env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.9)
	add_child(sun)

	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(30, 140, 0)
	rim.light_energy = 0.35
	rim.light_color = Color(0.5, 0.6, 1.0)
	add_child(rim)

func _build_stars() -> void:
	# Procedural starfield: a MultiMesh shell of tiny unshaded emissive points, plus a
	# couple of nebula billboards so the backdrop is never a flat black frame.
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(2.2, 2.2)
	mm.mesh = qm
	var count: int = 900
	mm.instance_count = count
	for i in range(count):
		var dir: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var pos: Vector3 = dir * rng.randf_range(600.0, 900.0)
		var t: Transform3D = Transform3D(Basis(), pos)
		# Billboard-ish: face origin.
		t = t.looking_at(Vector3.ZERO, Vector3.UP)
		var s: float = rng.randf_range(0.4, 1.8)
		t = t.scaled_local(Vector3(s, s, s))
		mm.set_instance_transform(i, t)
		var b: float = rng.randf_range(0.5, 1.0)
		var tint: Color = Color(b, b, b * rng.randf_range(0.85, 1.0))
		if rng.randf() < 0.15:
			tint = Color(b * 0.8, b * 0.85, b)
		mm.set_instance_color(i, tint)
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var smat: StandardMaterial3D = StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1, 1, 1)
	smat.vertex_color_use_as_albedo = true
	smat.emission_enabled = true
	smat.emission = Color(1, 1, 1)
	smat.emission_energy_multiplier = 1.4
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mmi.material_override = smat
	add_child(mmi)

	# Two faint nebula clouds (large unshaded transparent spheres).
	for nb in [[Vector3(-300, 120, -400), Color(0.25, 0.1, 0.4, 0.10)], [Vector3(350, -80, -300), Color(0.1, 0.25, 0.4, 0.09)]]:
		var neb: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = 180.0
		sm.height = 360.0
		neb.mesh = sm
		var nmat: StandardMaterial3D = StandardMaterial3D.new()
		nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		nmat.albedo_color = nb[1]
		nmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		neb.mesh.surface_set_material(0, nmat)
		neb.position = nb[0]
		add_child(neb)

func _spawn_ship(p_class: String, faction: String, ship_name: String, pos: Vector3, manned: bool = true) -> Node3D:
	var s: Node3D = ShipScript.new()
	s.name = "Ship_%s_%s" % [faction, ship_name]
	add_child(s)
	s.setup(p_class, faction, ship_name)
	s.global_position = pos
	s.manned = manned
	if not manned:
		s.crew_assigned = 0
	ships.append(s)
	return s

func _build_battle() -> void:
	# Neutral station hub (recruit / buy / capture objective).
	station = _spawn_ship("station", "neutral", "Halcyon", Vector3(0, 0, -40))

	# Player flagship (corvette) and starting wing.
	player = _spawn_ship("corvette", "player", "Captain", Vector3(0, 4, 80))
	player.is_player = true
	player.look_at(player.global_position + Vector3(0, 0, -1), Vector3.UP)

	var ally1: Node3D = _spawn_ship("fighter", "player", "Wing-1", Vector3(-10, 3, 90))
	var ally2: Node3D = _spawn_ship("fighter", "player", "Wing-2", Vector3(10, 3, 90))
	ally1.ai_state = "follow"
	ally2.ai_state = "follow"

	# Hostile wing of fighters.
	for i in range(4):
		var hp: Vector3 = Vector3(-30 + i * 18, rng.randf_range(-6, 8), -110 - i * 6)
		_spawn_ship("fighter", "hostile", "Raider-%d" % (i + 1), hp)

	# Larger hostile ships: a corvette and the frigate (primary boarding target).
	_spawn_ship("corvette", "hostile", "Cleaver", Vector3(40, 6, -90))
	var frig: Node3D = _spawn_ship("frigate", "hostile", "Ironclaw", Vector3(-20, -4, -150))
	frig.ai_state = "engage"

	# A hostile capital to show the largest silhouette class in the battle.
	_spawn_ship("capital", "hostile", "Dread Maw", Vector3(60, 10, -200))

	# Third-person chase camera.
	space_camera = Camera3D.new()
	space_camera.fov = 68.0
	space_camera.far = 2000.0
	add_child(space_camera)
	_update_camera(0.001, true)
	space_camera.current = true

func _build_hud() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	layer.add_child(hud)

func _build_deck() -> void:
	deck = DeckScript.new()
	deck.name = "CrewDeck"
	deck.position = Vector3(0, -500, 0)   # tucked away from the space scene
	add_child(deck)
	deck.build(rng)
	deck.set_active(false)

# ---------------------------------------------------------------------------
# MAIN LOOP
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_elapsed += delta
	if deck_mode:
		_process_deck(delta)
	else:
		_process_space(delta)
	for s in ships:
		if is_instance_valid(s):
			s.tick_visuals(delta)
	_update_hud()

func _process_deck(delta: float) -> void:
	var iv: Vector2 = Vector2(
		Input.get_action_strength("yaw_right") - Input.get_action_strength("yaw_left"),
		Input.get_action_strength("thrust_down") - Input.get_action_strength("thrust_up")
	)
	var follow_pressed: bool = Input.is_action_just_pressed("follow_toggle")
	deck.process_deck(delta, iv, follow_pressed)
	if follow_pressed and audio:
		audio.play("ui_recruit")

func _process_space(delta: float) -> void:
	if is_instance_valid(player) and not player.destroyed:
		_player_control(delta)
	_run_ai(delta)
	_integrate_motion(delta)
	_update_projectiles(delta)
	_update_beams(delta)
	_update_explosions(delta)
	_update_boarding(delta)
	_update_camera(delta, false)
	_handle_station_actions()

func _player_control(delta: float) -> void:
	# Throttle / boost / brake.
	throttle += (Input.get_action_strength("thrust_up") - Input.get_action_strength("thrust_down")) * delta * 0.8
	throttle = clamp(throttle, 0.0, 1.0)
	var boosting: bool = Input.is_action_pressed("boost") and player.energy > 0.0
	var braking: bool = Input.is_action_pressed("brake")
	player.throttle = throttle
	player.boosting = boosting

	# Rotation: yaw (A/D), pitch (arrows), roll (Q/E).
	var yaw: float = Input.get_action_strength("yaw_left") - Input.get_action_strength("yaw_right")
	var pitch: float = Input.get_action_strength("pitch_up") - Input.get_action_strength("pitch_down")
	var roll: float = Input.get_action_strength("roll_left") - Input.get_action_strength("roll_right")
	if auto_demo:
		# Steer toward the current target (with a little weave) so capture frames keep the
		# battle framed instead of drifting into empty space.
		if is_instance_valid(target):
			var lp: Vector3 = player.to_local(target.global_position)
			yaw += clamp(-lp.x * 0.15, -1.0, 1.0)
			pitch += clamp(lp.y * 0.15, -1.0, 1.0)
		yaw += sin(_elapsed * 0.7) * 0.2
	var rate: float = player.turn_rate
	player.rotate_object_local(Vector3.UP, yaw * rate * delta)
	player.rotate_object_local(Vector3.RIGHT, pitch * rate * delta)
	player.rotate_object_local(Vector3.FORWARD, roll * rate * 1.4 * delta)

	# Forward thrust along ship -Z.
	var fwd: Vector3 = -player.global_transform.basis.z
	var target_speed: float = player.max_speed * throttle * (1.7 if boosting else 1.0)
	if braking:
		target_speed *= 0.15
	player.velocity = player.velocity.move_toward(fwd * target_speed, player.accel * (2.2 if braking else 1.0) * delta)

	# Energy: boost drains, otherwise regen.
	if boosting:
		player.energy = max(0.0, player.energy - 30.0 * delta)
		if audio and int(_elapsed * 6.0) % 3 == 0:
			audio.play("thruster", rng.randf_range(0.9, 1.1))
	else:
		player.energy = min(player.max_energy, player.energy + 14.0 * delta)
	# Shield regen.
	if not player.disabled:
		player.shield = min(player.max_shield, player.shield + 6.0 * delta)

	# Firing.
	var want_fire: bool = Input.is_action_pressed("fire") or auto_demo
	if want_fire:
		_try_fire(player, delta)

	# Target cycling.
	if Input.is_action_just_pressed("next_target"):
		_cycle_target()
	if auto_demo and target == null:
		_cycle_target()

	# Board.
	if Input.is_action_just_pressed("board_ship") or (auto_demo and _elapsed > 3.0):
		_try_start_boarding()

func _run_ai(delta: float) -> void:
	for s in ships:
		if not is_instance_valid(s) or s.is_player or s.destroyed:
			continue
		if s.ship_class == "station":
			_station_ai(s, delta)
			continue
		if s.disabled or not s.manned:
			s.throttle = 0.0
			s.velocity = s.velocity.move_toward(Vector3.ZERO, s.accel * delta)
			continue
		if s.faction == "player":
			_ai_follow_player(s, delta)
		else:
			_ai_combat(s, delta)

func _ai_follow_player(s: Node3D, delta: float) -> void:
	# Fleet formation: ring offset behind the player; engage nearby hostiles.
	var enemy: Node3D = _nearest(s, "hostile")
	if enemy != null and s.global_position.distance_to(enemy.global_position) < s.weapon_range * 0.9:
		_steer_toward(s, enemy.global_position, delta, 0.9)
		_face_and_fire(s, enemy, delta)
		s.target = enemy
		return
	var idx: int = ships.find(s)
	var ang: float = float(idx) * 1.3
	var offset: Vector3 = Vector3(sin(ang) * 14.0, 3.0, 16.0 + float(idx % 3) * 6.0)
	var goal: Vector3 = player.global_position + player.global_transform.basis * offset
	_steer_toward(s, goal, delta, 1.0)

func _ai_combat(s: Node3D, delta: float) -> void:
	var foe: Node3D = _nearest(s, "player")
	if foe == null:
		foe = player
	if foe == null or not is_instance_valid(foe):
		s.throttle = 0.0
		return
	var dist: float = s.global_position.distance_to(foe.global_position)
	s.target = foe
	if dist > s.weapon_range * 0.6:
		_steer_toward(s, foe.global_position, delta, 1.0)
	else:
		# Strafe: hold range, keep facing.
		_steer_toward(s, foe.global_position, delta, 0.35)
	_face_and_fire(s, foe, delta)

func _station_ai(s: Node3D, delta: float) -> void:
	s.throttle = 0.0
	s.velocity = Vector3.ZERO
	if s.faction == "neutral" or s.disabled:
		return
	var foe: Node3D = _nearest(s, "hostile" if s.faction == "player" else "player")
	if foe != null and s.global_position.distance_to(foe.global_position) < s.weapon_range:
		s.target = foe
		_try_fire(s, delta, foe)

func _steer_toward(s: Node3D, goal: Vector3, delta: float, throttle_mul: float) -> void:
	var to: Vector3 = goal - s.global_position
	if to.length() < 0.5:
		s.velocity = s.velocity.move_toward(Vector3.ZERO, s.accel * delta)
		return
	var desired: Basis = Basis.looking_at(to.normalized(), Vector3.UP)
	s.global_transform.basis = s.global_transform.basis.slerp(desired, clamp(s.turn_rate * delta, 0.0, 1.0)).orthonormalized()
	var fwd: Vector3 = -s.global_transform.basis.z
	s.throttle = throttle_mul
	s.velocity = s.velocity.move_toward(fwd * s.max_speed * throttle_mul, s.accel * delta)

func _face_and_fire(s: Node3D, foe: Node3D, delta: float) -> void:
	var to: Vector3 = (foe.global_position - s.global_position)
	var dist: float = to.length()
	if dist > s.weapon_range:
		return
	var fwd: Vector3 = -s.global_transform.basis.z
	if fwd.dot(to.normalized()) > 0.92:
		_try_fire(s, delta, foe)

func _integrate_motion(delta: float) -> void:
	for s in ships:
		if not is_instance_valid(s) or s.destroyed:
			continue
		if s.ship_class == "station":
			continue
		s.global_position += s.velocity * delta

# ---------------------------------------------------------------------------
# WEAPONS
# ---------------------------------------------------------------------------
func _try_fire(s: Node3D, delta: float, forced_target: Node3D = null) -> void:
	s.weapon_cd -= delta
	if s.weapon_cd > 0.0:
		return
	if s.energy < 2.0:
		return
	s.weapon_cd = s.fire_rate
	s.energy = max(0.0, s.energy - 2.0)
	var aim_target: Node3D = forced_target if forced_target != null else (target if s.is_player else s.target)
	if s.weapon_type == "beam":
		_fire_beam(s, aim_target)
	else:
		_fire_projectile(s, aim_target)

func _muzzle_world(s: Node3D, local: Vector3) -> Vector3:
	var scale: float = s.radius() / 3.0
	return s.global_transform * (local * scale)

func _fire_projectile(s: Node3D, aim_target: Node3D) -> void:
	var muzzles: Array = s.muzzles if s.muzzles.size() > 0 else [Vector3(0, 0, -2)]
	var fwd: Vector3 = -s.global_transform.basis.z
	var aim_dir: Vector3 = fwd
	if aim_target != null and is_instance_valid(aim_target):
		aim_dir = (aim_target.global_position - s.global_position).normalized()
		# Blend toward muzzle-forward so shots still look like they come from the ship.
		aim_dir = (aim_dir * 0.7 + fwd * 0.3).normalized()
	for m in muzzles:
		var origin: Vector3 = _muzzle_world(s, m)
		var node: MeshInstance3D = MeshInstance3D.new()
		var cm: CapsuleMesh = CapsuleMesh.new()
		cm.radius = 0.26
		cm.height = 3.2
		node.mesh = cm
		var col: Color = Color(0.5, 1.0, 0.6) if s.faction == "player" else Color(1.0, 0.5, 0.35)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 8.0
		node.material_override = mat
		add_child(node)
		node.global_position = origin
		node.look_at(origin + aim_dir, Vector3.UP)
		node.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		var speed: float = 90.0
		projectiles.append({
			"node": node,
			"vel": aim_dir * speed + s.velocity,
			"dmg": s.weapon_dmg,
			"ttl": s.weapon_range / speed + 0.4,
			"faction": s.faction,
		})
	if audio:
		audio.play("laser", rng.randf_range(0.9, 1.1))

func _fire_beam(s: Node3D, aim_target: Node3D) -> void:
	if aim_target == null or not is_instance_valid(aim_target):
		return
	var origin: Vector3 = _muzzle_world(s, s.muzzles[0] if s.muzzles.size() > 0 else Vector3(0, 0, -3))
	var dest: Vector3 = aim_target.global_position
	var mid: Vector3 = (origin + dest) * 0.5
	var length: float = origin.distance_to(dest)
	var node: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.4
	cm.height = length
	node.mesh = cm
	var col: Color = Color(0.6, 1.0, 0.8) if s.faction == "player" else Color(1.0, 0.4, 0.5)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 5.0
	node.material_override = mat
	add_child(node)
	node.global_position = mid
	node.look_at(dest, Vector3.UP)
	node.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	beams.append({"node": node, "ttl": 0.3})
	# Hitscan damage.
	_apply_damage(s, aim_target, s.weapon_dmg)
	if audio:
		audio.play("beam")

func _update_projectiles(delta: float) -> void:
	var keep: Array = []
	for p in projectiles:
		var pd: Dictionary = p
		var node: Node3D = pd["node"]
		if not is_instance_valid(node):
			continue
		node.global_position += pd["vel"] * delta
		pd["ttl"] = float(pd["ttl"]) - delta
		var hit: bool = false
		for s in ships:
			if not is_instance_valid(s) or s.destroyed:
				continue
			if s.faction == pd["faction"]:
				continue
			if pd["faction"] == "player" and s.faction == "neutral":
				continue   # don't shoot the neutral station accidentally
			if node.global_position.distance_to(s.global_position) < s.radius():
				_apply_damage_from_faction(pd["faction"], s, float(pd["dmg"]))
				hit = true
				break
		if hit or float(pd["ttl"]) <= 0.0:
			node.queue_free()
		else:
			keep.append(pd)
	projectiles = keep

func _update_beams(delta: float) -> void:
	var keep: Array = []
	for b in beams:
		var bd: Dictionary = b
		bd["ttl"] = float(bd["ttl"]) - delta
		if float(bd["ttl"]) <= 0.0:
			if is_instance_valid(bd["node"]):
				bd["node"].queue_free()
		else:
			keep.append(bd)
	beams = keep

# ---------------------------------------------------------------------------
# DAMAGE / DESTRUCTION
# ---------------------------------------------------------------------------
func _apply_damage_from_faction(attacker_faction: String, victim: Node3D, dmg: float) -> void:
	var ev: Dictionary = victim.take_damage(dmg)
	_handle_damage_events(victim, ev)

func _apply_damage(attacker: Node3D, victim: Node3D, dmg: float) -> void:
	if not is_instance_valid(victim):
		return
	var ev: Dictionary = victim.take_damage(dmg)
	_handle_damage_events(victim, ev)

func _handle_damage_events(victim: Node3D, ev: Dictionary) -> void:
	if audio:
		if bool(ev.get("shield_hit", false)):
			audio.play("shield", 1.0)
		else:
			audio.play("hit", rng.randf_range(0.9, 1.2))
	if bool(ev.get("disabled", false)):
		_msg("%s DISABLED — board it with marines [B]." % victim.ship_name)
		if audio:
			audio.play("disabled")
	if bool(ev.get("destroyed", false)):
		_destroy_ship(victim)

func _destroy_ship(s: Node3D) -> void:
	_spawn_explosion(s.global_position, s.radius())
	if audio:
		audio.play("explosion")
	_msg("%s destroyed." % s.ship_name)
	if s == target:
		target = null
	if boarding_target == s:
		_cancel_boarding()
	ships.erase(s)
	s.queue_free()

func _spawn_explosion(pos: Vector3, base_radius: float) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	node.mesh = sm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.7, 0.3, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	mat.emission_energy_multiplier = 6.0
	node.material_override = mat
	add_child(node)
	node.global_position = pos
	explosions.append({"node": node, "mat": mat, "ttl": 0.7, "life": 0.7, "scale": base_radius * 3.0})

func _update_explosions(delta: float) -> void:
	var keep: Array = []
	for e in explosions:
		var ed: Dictionary = e
		ed["ttl"] = float(ed["ttl"]) - delta
		var node: Node3D = ed["node"]
		if not is_instance_valid(node):
			continue
		var t: float = 1.0 - clamp(float(ed["ttl"]) / float(ed["life"]), 0.0, 1.0)
		var sc: float = lerp(1.0, float(ed["scale"]), t)
		node.scale = Vector3(sc, sc, sc)
		var mat: StandardMaterial3D = ed["mat"]
		mat.albedo_color = Color(1.0, 0.7 - t * 0.4, 0.3 - t * 0.2, 1.0 - t)
		if float(ed["ttl"]) <= 0.0:
			node.queue_free()
		else:
			keep.append(ed)
	explosions = keep

# ---------------------------------------------------------------------------
# TARGETING / RADAR
# ---------------------------------------------------------------------------
func _cycle_target() -> void:
	var candidates: Array = []
	for s in ships:
		if is_instance_valid(s) and not s.is_player and not s.destroyed and s.faction != "player":
			candidates.append(s)
	if candidates.is_empty():
		target = null
		return
	candidates.sort_custom(func(a, b): return _pdist(a) < _pdist(b))
	var idx: int = candidates.find(target)
	target = candidates[(idx + 1) % candidates.size()]
	_msg("Target: %s (%s)" % [target.ship_name, target.faction])

func _stage_capture_demo() -> void:
	# Capture-only staging keeps screenshots focused on active combat instead of
	# the neutral station being selected just because it is nearest at startup.
	var frigate: Node3D = null
	for s in ships:
		if is_instance_valid(s) and s.ship_name == "Ironclaw":
			frigate = s
			break
	if frigate == null:
		return
	player.global_position = Vector3(0, 4, 28)
	frigate.global_position = Vector3(-16, -2, -78)
	# Give the capture-demo frigate enough temporary durability to stay on target
	# through all space screenshots while still starting visibly under attack.
	frigate.max_shield = max(frigate.max_shield, 520.0)
	frigate.shield = frigate.max_shield * 0.55
	frigate.max_hull = max(frigate.max_hull, 1300.0)
	frigate.hull = frigate.max_hull * 0.72
	frigate.look_at(player.global_position, Vector3.UP)
	target = frigate
	for s2 in ships:
		if not is_instance_valid(s2) or s2 == player:
			continue
		if s2.faction == "player":
			var idx2: int = ships.find(s2)
			s2.global_position = player.global_position + Vector3(-12.0 + float(idx2) * 8.0, rng.randf_range(-2.0, 4.0), 16.0 + float(idx2 % 2) * 8.0)
			s2.look_at(frigate.global_position, Vector3.UP)
		elif s2.faction == "hostile" and s2 != frigate:
			var hidx: int = ships.find(s2)
			s2.global_position = frigate.global_position + Vector3(-24.0 + float(hidx % 5) * 12.0, rng.randf_range(-5.0, 6.0), -18.0 - float(hidx % 3) * 8.0)
			s2.look_at(player.global_position, Vector3.UP)
	_add_demo_beam(player.global_position + Vector3(-3, 0, -8), frigate.global_position + Vector3(0, 1.5, 0), Color(0.45, 1.0, 0.65))
	_add_demo_beam(player.global_position + Vector3(8, 2, 10), frigate.global_position + Vector3(7, 0, -3), Color(0.45, 0.8, 1.0))
	_add_demo_beam(frigate.global_position + Vector3(-7, 0, -3), player.global_position + Vector3(0, 1, -3), Color(1.0, 0.35, 0.35))
	_add_demo_burst(frigate.global_position + Vector3(4, 2.2, -2), 5.5)
	_msg("Capture demo: hostile frigate Ironclaw is under fleet attack.")

func _add_demo_beam(from_pos: Vector3, to_pos: Vector3, col: Color) -> void:
	var length: float = from_pos.distance_to(to_pos)
	if length <= 0.1:
		return
	var node: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.7
	cm.height = length
	node.mesh = cm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 12.0
	node.material_override = mat
	add_child(node)
	node.global_position = (from_pos + to_pos) * 0.5
	node.look_at(to_pos, Vector3.UP)
	node.rotate_object_local(Vector3.RIGHT, PI / 2.0)

func _add_demo_burst(pos: Vector3, radius: float) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	node.mesh = sm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.18, 0.78)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.38, 0.08)
	mat.emission_energy_multiplier = 9.0
	node.material_override = mat
	add_child(node)
	node.global_position = pos

func _pdist(s: Node3D) -> float:
	if not is_instance_valid(player):
		return 1e9
	return player.global_position.distance_to(s.global_position)

func _nearest(from: Node3D, faction: String) -> Node3D:
	var best: Node3D = null
	var bd: float = 1e9
	for s in ships:
		if not is_instance_valid(s) or s.destroyed or s == from:
			continue
		if s.faction != faction:
			continue
		if s.disabled and faction != "player":
			continue
		var d: float = from.global_position.distance_to(s.global_position)
		if d < bd:
			bd = d
			best = s
	return best

# ---------------------------------------------------------------------------
# BOARDING & CAPTURE
# ---------------------------------------------------------------------------
func _try_start_boarding() -> void:
	if boarding_active:
		return
	if target == null or not is_instance_valid(target):
		_msg("No target to board. [Tab] to select one.")
		if audio: audio.play("ui_deny")
		return
	if target.faction == "player":
		_msg("%s is already yours." % target.ship_name)
		return
	if not target.disabled:
		_msg("%s must be DISABLED before boarding (reduce hull)." % target.ship_name)
		if audio: audio.play("ui_deny")
		return
	if Game.marine_pool <= 0:
		_msg("No marines available. Recruit at the station [M].")
		if audio: audio.play("ui_deny")
		return
	if _pdist(target) > 90.0:
		_msg("Too far to board — close in on %s." % target.ship_name)
		if audio: audio.play("ui_deny")
		return
	boarding_active = true
	boarding_target = target
	boarding_progress = 0.0
	_msg("Boarding %s — marines breaching!" % target.ship_name)
	if audio: audio.play("board")

func _update_boarding(delta: float) -> void:
	if not boarding_active:
		return
	if not is_instance_valid(boarding_target) or boarding_target.destroyed:
		_cancel_boarding()
		return
	# Marines must stay close; progress scales with marine count.
	if _pdist(boarding_target) > 120.0:
		_msg("Boarding aborted — drifted out of range.")
		_cancel_boarding()
		return
	var marines: int = max(1, Game.marine_pool)
	boarding_progress += BOARD_RATE * (0.6 + 0.12 * float(marines)) * delta
	if int(_elapsed * 4.0) % 8 == 0 and audio:
		audio.play("board", rng.randf_range(0.9, 1.2))
	if boarding_progress >= 1.0:
		_complete_capture(boarding_target)

func _cancel_boarding() -> void:
	boarding_active = false
	boarding_target = null
	boarding_progress = 0.0

func _complete_capture(s: Node3D) -> void:
	s.set_faction("player")
	s.disabled = false
	s.hull = max(s.hull, s.max_hull * 0.4)
	Game.marine_pool = max(0, Game.marine_pool - 2)
	Game.captured_count += 1
	# Try to man it from the crew pool; otherwise it is captured-but-unmanned.
	if Game.crew_pool >= s.crew_needed:
		Game.crew_pool -= s.crew_needed
		s.crew_assigned = s.crew_needed
		s.manned = true
		s.ai_state = "follow"
		_msg("%s CAPTURED and manned — joins your fleet!" % s.ship_name)
	else:
		s.manned = false
		s.crew_assigned = 0
		_msg("%s CAPTURED but UNMANNED — recruit crew to fly it." % s.ship_name)
	if audio: audio.play("capture")
	_cancel_boarding()

# ---------------------------------------------------------------------------
# STATION ECONOMY: recruit / buy / deck toggle
# ---------------------------------------------------------------------------
func _handle_station_actions() -> void:
	if Input.is_action_just_pressed("toggle_deck"):
		_set_deck_mode(not deck_mode)
		return
	var near_station: bool = is_instance_valid(station) and _pdist(station) < 70.0
	if Input.is_action_just_pressed("cycle_shipyard"):
		_cycle_shipyard_class(near_station)
	if Input.is_action_just_pressed("recruit_crew"):
		_recruit("crew", near_station)
	if Input.is_action_just_pressed("recruit_marine"):
		_recruit("marine", near_station)
	if Input.is_action_just_pressed("buy_ship"):
		_buy_ship(near_station)
	if Input.is_action_just_pressed("follow_toggle"):
		_toggle_fleet_follow()

func _shipyard_class() -> String:
	return String(SHIPYARD_CLASSES[shipyard_index % SHIPYARD_CLASSES.size()])

func _shipyard_cost() -> int:
	return int(Game.class_stat(_shipyard_class(), "value"))

func _cycle_shipyard_class(near_station: bool = true) -> void:
	if not near_station:
		_msg("Fly to the STATION to browse the shipyard.")
		if audio: audio.play("ui_deny")
		return
	shipyard_index = (shipyard_index + 1) % SHIPYARD_CLASSES.size()
	_msg("Shipyard selected: %s (%d cr)." % [_shipyard_class().to_upper(), _shipyard_cost()])
	if audio: audio.play("ui_recruit")

func _recruit(kind: String, near_station: bool) -> void:
	if not near_station:
		_msg("Fly to the STATION to recruit.")
		if audio: audio.play("ui_deny")
		return
	var cost: int = COST_CREW if kind == "crew" else COST_MARINE
	if Game.credits < cost:
		_msg("Not enough credits (%d needed)." % cost)
		if audio: audio.play("ui_deny")
		return
	Game.credits -= cost
	if kind == "crew":
		Game.crew_pool += 1
		_msg("Recruited crew (%d available). Cost %d." % [Game.crew_pool, cost])
	else:
		Game.marine_pool += 1
		_msg("Recruited marine (%d available). Cost %d." % [Game.marine_pool, cost])
	if deck and deck.has_method("refresh_roster"):
		deck.refresh_roster()
	if audio: audio.play("ui_recruit")

func _buy_ship(near_station: bool) -> void:
	if not near_station:
		_msg("Fly to the STATION to buy ships.")
		if audio: audio.play("ui_deny")
		return
	var buy_class: String = _shipyard_class()
	var cost: int = _shipyard_cost()
	if Game.credits < cost:
		_msg("Not enough credits for a %s (%d)." % [buy_class, cost])
		if audio: audio.play("ui_deny")
		return
	Game.credits -= cost
	Game.purchased_count += 1
	var pos: Vector3 = station.global_position + Vector3(rng.randf_range(-14, 14), 6, 18)
	var s: Node3D = _spawn_ship(buy_class, "player", "%s-%d" % [buy_class.capitalize(), Game.purchased_count], pos)
	var need: int = s.crew_needed
	if Game.crew_pool >= need:
		Game.crew_pool -= need
		s.crew_assigned = need
		s.manned = true
		s.ai_state = "follow"
		_msg("Bought %s and assigned %d crew — manned, joins fleet." % [buy_class, need])
	else:
		s.manned = false
		s.crew_assigned = 0
		_msg("Bought %s but UNMANNED (needs %d crew)." % [buy_class, need])
	if audio: audio.play("ui_buy")

func _toggle_fleet_follow() -> void:
	# Re-man any unmanned owned ships if crew is now available.
	var changed: int = 0
	for s in ships:
		if not is_instance_valid(s) or s.faction != "player" or s.is_player:
			continue
		if not s.manned and Game.crew_pool >= s.crew_needed:
			Game.crew_pool -= s.crew_needed
			s.crew_assigned = s.crew_needed
			s.manned = true
			s.ai_state = "follow"
			changed += 1
	if changed > 0:
		_msg("Assigned crew to %d ship(s) — now manned and following." % changed)
		if audio: audio.play("ui_recruit")
	else:
		_msg("Fleet holding formation.")

func _set_deck_mode(on: bool) -> void:
	deck_mode = on
	deck.set_active(on)
	if on:
		deck.refresh_roster()
		_msg("Entered CREW DECK. WASD move, F order follow, C exit.")
	else:
		space_camera.current = true
		_msg("Returned to the bridge.")

# ---------------------------------------------------------------------------
# CAMERA
# ---------------------------------------------------------------------------
func _update_camera(delta: float, instant: bool) -> void:
	if not is_instance_valid(player):
		return
	var back: Vector3 = player.global_transform.basis.z * (14.0 + player.radius() * 1.6)
	var up: Vector3 = player.global_transform.basis.y * (4.0 + player.radius() * 0.6)
	var goal: Vector3 = player.global_position + back + up
	if instant:
		space_camera.global_position = goal
	else:
		space_camera.global_position = space_camera.global_position.lerp(goal, clamp(delta * 4.0, 0.0, 1.0))
	space_camera.look_at(player.global_position - player.global_transform.basis.z * 8.0, player.global_transform.basis.y)

# ---------------------------------------------------------------------------
# HUD FEED
# ---------------------------------------------------------------------------
func _msg(text: String) -> void:
	messages.append(text)
	while messages.size() > 6:
		messages.pop_front()

func _update_hud() -> void:
	var d: Dictionary = {}
	d["mode"] = "deck" if deck_mode else "space"
	d["credits"] = Game.credits
	d["crew_pool"] = Game.crew_pool
	d["marine_pool"] = Game.marine_pool
	d["fleet_count"] = _count_fleet()
	d["captured"] = Game.captured_count
	d["shipyard_class"] = _shipyard_class()
	d["shipyard_cost"] = _shipyard_cost()
	d["objective"] = objective
	d["messages"] = messages.duplicate()
	d["capture_demo"] = auto_demo

	if deck_mode:
		var st: Dictionary = deck.status()
		var nm: String = String(st.get("nearest", ""))
		if nm != "":
			d["prompt"] = "Near %s — [F] %s" % [nm, "STOP follow" if bool(st.get("nearest_following", false)) else "order FOLLOW"]
		else:
			d["prompt"] = "Walk up to a crew/marine, then [F]. Following: %d" % int(st.get("follow_count", 0))
		hud.set_data(d)
		return

	# Player block.
	if is_instance_valid(player) and not player.destroyed:
		d["player"] = {
			"hull_frac": player.hull / player.max_hull,
			"shield_frac": player.shield / max(1.0, player.max_shield),
			"energy_frac": player.energy / max(1.0, player.max_energy),
			"throttle": throttle,
			"class": player.ship_class,
			"speed": player.velocity.length(),
		}
	# Target block.
	if is_instance_valid(target) and not target.destroyed:
		d["target"] = {
			"name": target.ship_name,
			"faction": target.faction,
			"class": target.ship_class,
			"hull_frac": target.hull / max(1.0, target.max_hull),
			"shield_frac": target.shield / max(1.0, target.max_shield),
			"dist": _pdist(target),
			"disabled": target.disabled,
		}
	# Boarding block.
	if boarding_active and is_instance_valid(boarding_target):
		d["boarding"] = {"active": true, "name": boarding_target.ship_name, "progress": boarding_progress}

	# Prompt based on context.
	d["prompt"] = _context_prompt()

	# Radar.
	d["radar"] = _build_radar()
	hud.set_data(d)

func _count_fleet() -> int:
	var n: int = 0
	for s in ships:
		if is_instance_valid(s) and s.faction == "player" and not s.is_player and not s.destroyed:
			n += 1
	return n

func _context_prompt() -> String:
	if is_instance_valid(station) and _pdist(station) < 70.0:
		return "STATION: [G] %s %dcr  [Y] buy  [R] crew  [M] marine  [C] deck  [F] man" % [_shipyard_class().to_upper(), _shipyard_cost()]
	if is_instance_valid(target) and target.disabled and target.faction != "player":
		return "[B] board %s with marines" % target.ship_name
	return "[Tab] cycle target   [C] crew deck"

func _build_radar() -> Array:
	var blips: Array = []
	if not is_instance_valid(player):
		return blips
	var inv: Basis = player.global_transform.basis.inverse()
	var rng_max: float = 320.0
	for s in ships:
		if not is_instance_valid(s) or s.destroyed:
			continue
		var rel3: Vector3 = inv * (s.global_position - player.global_position)
		var p2: Vector2 = Vector2(rel3.x, -rel3.z) / rng_max
		if p2.length() > 1.0:
			p2 = p2.normalized()
		blips.append({
			"pos": p2,
			"faction": s.faction,
			"target": s == target,
			"self": s == player,
		})
	return blips

# Public hook used by the capture autoload to force the crew deck view for a screenshot.
func force_deck(on: bool) -> void:
	_set_deck_mode(on)
