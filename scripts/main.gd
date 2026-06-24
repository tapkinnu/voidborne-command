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
var _muzzle_flashes: Array = []    # Array of dicts {node, mat, ttl, life, start_scale, end_scale}
var _shield_impacts: Array = []    # Array of dicts {node, mat, ttl, life, start_scale, end_scale}
var _debris: Array = []            # Array of dicts {node, vel, rot_vel, ttl, life, mat}
var _decals: Array = []            # reserved; hit decals are children of ship Hull nodes (count tracked via metadata)

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var space_camera: Camera3D
var world_env: WorldEnvironment
var hud: Control
var deck: Node3D
var audio: Node

# --- Player flight/combat state ---------------------------------------------
var throttle: float = 0.4
var target: Node3D = null

# --- Input / control settings -----------------------------------------------
# mouse_aim captures the cursor and steers the ship with mouse motion (additive over
# the keyboard). control_scheme gates which input sources feed flight: "auto" reads
# keyboard/mouse and gamepad together; "keyboard" ignores gamepad axes; "gamepad"
# ignores keyboard/mouse flight (UI keys like save/load still work). settings_open
# toggles a HUD overlay summarising these bindings.
var mouse_aim: bool = false
var settings_open: bool = false
var control_scheme: String = "auto"   # "auto" | "keyboard" | "gamepad"
var _mouse_aim_delta: Vector2 = Vector2.ZERO   # accumulated mouse motion this frame
const MOUSE_AIM_SENS: float = 0.003

# Per-source flight binding tables. The action system merges keyboard and gamepad
# events, so to honour control_scheme ("keyboard" / "gamepad" / "auto") we read each
# source explicitly. These mirror the events declared in project.godot [input].
const _FLIGHT_KEYS: Dictionary = {
	"thrust_up": KEY_W, "thrust_down": KEY_S,
	"yaw_left": KEY_A, "yaw_right": KEY_D,
	"pitch_up": KEY_UP, "pitch_down": KEY_DOWN,
	"roll_left": KEY_Q, "roll_right": KEY_E,
	"boost": KEY_SHIFT, "brake": KEY_X, "fire": KEY_SPACE,
}
const _FLIGHT_JOY_AXIS: Dictionary = {
	# action -> [axis, direction(+1/-1)]
	"thrust_up": [JOY_AXIS_TRIGGER_RIGHT, 1], "thrust_down": [JOY_AXIS_TRIGGER_LEFT, 1],
	"yaw_left": [JOY_AXIS_LEFT_X, -1], "yaw_right": [JOY_AXIS_LEFT_X, 1],
	"pitch_up": [JOY_AXIS_LEFT_Y, -1], "pitch_down": [JOY_AXIS_LEFT_Y, 1],
	"roll_left": [JOY_AXIS_RIGHT_X, -1], "roll_right": [JOY_AXIS_RIGHT_X, 1],
}
const _FLIGHT_JOY_BTN: Dictionary = {
	"boost": JOY_BUTTON_RIGHT_SHOULDER, "brake": JOY_BUTTON_LEFT_SHOULDER, "fire": JOY_BUTTON_A,
}
var subsystem_focus: String = ""          # "" | "engines" | "weapons" | "shields"
var deck_mode: bool = false
var fleet_order: String = "follow"        # follow | hold | attack
var fleet_hold_positions: Dictionary = {}  # instance_id -> Vector3
var fleet_attack_target: Node3D = null     # focus-fire target while fleet_order == "attack"

# Boarding state. Boarding is now a resolved squad action: the player's marines
# (boarding_attacker_strength, drawn from Game.marine_pool) fight the target's defenders
# (boarding_defender_strength, the ship's marine_garrison after its disable loss). Each
# round both sides take casualties; capture happens when defenders hit 0, failure when
# attackers hit 0. boarding_progress is kept only as the HUD bar fraction (capture nearness).
var boarding_active: bool = false
var boarding_target: Node3D = null
var boarding_progress: float = 0.0        # 0..1 capture nearness for the HUD bar
var boarding_attacker_strength: int = 0
var boarding_defender_strength: int = 0
var boarding_initial_attacker: int = 0
var boarding_initial_defender: int = 0
var boarding_round_timer: float = 0.0     # accumulates game time toward the next round
var boarding_round_count: int = 0
var boarding_failed: bool = false         # set briefly so the HUD can flag a failed assault
const BOARD_ROUND_INTERVAL: float = 0.5   # seconds of game time per combat round
const BOARD_EXCHANGE_RATE: float = 0.15   # casualty fraction inflicted per round

# Economy costs.
const COST_CREW: int = 120
const COST_MARINE: int = 180
const SHIPYARD_CLASSES: Array = ["corvette", "fighter", "frigate", "capital"]
var shipyard_index: int = 0

# Station repair/refit service. Cost scales with the hull/shield/energy actually
# restored across the manned, player-owned fleet; partial work is applied when the
# player cannot afford a full service.
const SERVICE_RANGE: float = 70.0
const SERVICE_MIN_CHARGE: int = 40
const SERVICE_HULL_RATE: float = 0.6
const SERVICE_SHIELD_RATE: float = 0.35
const SERVICE_ENERGY_RATE: float = 0.15
const SERVICE_SUBSYS_RATE: float = 20.0   # per full subsystem (0..1) restored during refit
const DISABLE_FRAC: float = 0.22   # hull fraction at/below which a ship is "disabled"

# Combat economy. Capturing hostile assets pays better than destroying them so the
# requested disable/board/capture loop feeds the shipyard and fleet-growth economy.
const CAPTURE_BOUNTY_RATE: float = 0.18
const DESTROY_SALVAGE_RATE: float = 0.08
const MIN_CAPTURE_BOUNTY: int = 100
const MIN_DESTROY_SALVAGE: int = 40

# Capture/demo: when launched for screenshots, the player auto-fights so frames are lively.
var auto_demo: bool = false

# --- Persistent save/load ---------------------------------------------------
# Versioned quick save/load of the current single-system battle. save_path is a
# script variable so tests can redirect it to a scratch file.
const SAVE_GAME_ID: String = "voidborne_command"
const SAVE_VERSION: int = 1
var save_path: String = "user://voidborne_save.json"

var messages: Array = []           # rolling message log (strings)
var objective: String = "Disable & board Ironclaw, then capture hostile Kryos Relay station."
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
	_msg("` mouse-aim   F1 settings   F2 control scheme.")

func _input(event: InputEvent) -> void:
	# Accumulate relative mouse motion while mouse-aim is engaged; consumed (and zeroed)
	# each frame in _player_control. Ignored when the active scheme excludes mouse/keyboard.
	if mouse_aim and control_scheme != "gamepad" and event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event
		_mouse_aim_delta += m.relative

# ---------------------------------------------------------------------------
# INPUT SOURCE GATING + CONTROL SETTINGS
# ---------------------------------------------------------------------------
func _joy_axis(axis: int) -> float:
	# Strongest reading of an axis across connected pads, with a small deadzone.
	var v: float = 0.0
	for d in Input.get_connected_joypads():
		var a: float = Input.get_joy_axis(d, axis)
		if abs(a) > abs(v):
			v = a
	return v if abs(v) >= 0.2 else 0.0

func _flight_strength(action: String) -> float:
	# 0..1 strength for a flight action honouring control_scheme: keyboard source unless
	# scheme is "gamepad"; gamepad source unless scheme is "keyboard".
	var v: float = 0.0
	if control_scheme != "gamepad" and _FLIGHT_KEYS.has(action):
		if Input.is_key_pressed(int(_FLIGHT_KEYS[action])):
			v = 1.0
	if control_scheme != "keyboard":
		if _FLIGHT_JOY_AXIS.has(action):
			var pair: Array = _FLIGHT_JOY_AXIS[action]
			var comp: float = _joy_axis(int(pair[0])) * float(pair[1])
			if comp > 0.0:
				v = max(v, comp)
		if _FLIGHT_JOY_BTN.has(action):
			for d in Input.get_connected_joypads():
				if Input.is_joy_button_pressed(d, int(_FLIGHT_JOY_BTN[action])):
					v = max(v, 1.0)
	return v

func _flight_axis(pos_action: String, neg_action: String) -> float:
	return _flight_strength(pos_action) - _flight_strength(neg_action)

func _flight_pressed(action: String) -> bool:
	return _flight_strength(action) > 0.5

func _toggle_mouse_aim() -> void:
	mouse_aim = not mouse_aim
	_mouse_aim_delta = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_aim else Input.MOUSE_MODE_VISIBLE
	_msg("MOUSE AIM: %s" % ("ON" if mouse_aim else "OFF"))
	if audio: audio.play("ui_recruit")

func _toggle_settings() -> void:
	settings_open = not settings_open
	_msg("Settings %s." % ("opened" if settings_open else "closed"))
	if audio: audio.play("ui_recruit")

func _cycle_control_scheme() -> void:
	# auto -> keyboard -> gamepad -> auto
	if control_scheme == "auto":
		control_scheme = "keyboard"
	elif control_scheme == "keyboard":
		control_scheme = "gamepad"
	else:
		control_scheme = "auto"
	_msg("Control scheme: %s" % control_scheme.to_upper())
	if audio: audio.play("ui_recruit")

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

	# A hostile capital to show the largest mobile silhouette class in the battle.
	_spawn_ship("capital", "hostile", "Dread Maw", Vector3(60, 10, -200))

	# Capturable hostile station/outpost. The neutral Halcyon station remains the
	# recruit/shipyard hub; this relay proves the station capture path in live combat.
	var relay: Node3D = _spawn_ship("station", "hostile", "Kryos Relay", Vector3(-95, -10, -185))
	relay.ai_state = "guard"

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
	_handle_save_load()
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
	_validate_fleet_attack()
	_run_ai(delta)
	_integrate_motion(delta)
	# Tick independent turret tracking for all ships that have turrets.
	for s in ships:
		if is_instance_valid(s) and not s.destroyed and s.has_method("tick_turrets") and s.has_turrets():
			var tt: Node3D = s.target if not s.is_player else target
			if tt == null or not is_instance_valid(tt):
				tt = null  # no target: turrets center
			s.tick_turrets(delta, tt)
	_update_projectiles(delta)
	_update_beams(delta)
	_update_explosions(delta)
	_update_muzzle_flashes(delta)
	_update_shield_impacts(delta)
	_update_debris(delta)
	_update_boarding(delta)
	_update_camera(delta, false)
	_handle_station_actions()

func _player_control(delta: float) -> void:
	# control_scheme gates which input sources feed flight. _flight_axis() reads the right
	# mix (keyboard, gamepad, or both) for each directional pair.
	# Throttle / boost / brake.
	throttle += _flight_axis("thrust_up", "thrust_down") * delta * 0.8
	throttle = clamp(throttle, 0.0, 1.0)
	var boosting: bool = _flight_pressed("boost") and player.energy > 0.0
	var braking: bool = _flight_pressed("brake")
	player.throttle = throttle
	player.boosting = boosting

	# Rotation: yaw (A/D), pitch (arrows), roll (Q/E).
	var yaw: float = _flight_axis("yaw_left", "yaw_right")
	var pitch: float = _flight_axis("pitch_up", "pitch_down")
	var roll: float = _flight_axis("roll_left", "roll_right")
	# Mouse-aim steering: additive over the keyboard. Scaled by 1/delta so the per-frame
	# relative motion becomes frame-rate independent once multiplied by rate*delta below.
	if mouse_aim and control_scheme != "gamepad":
		yaw += -_mouse_aim_delta.x * MOUSE_AIM_SENS / max(delta, 0.0001)
		pitch += -_mouse_aim_delta.y * MOUSE_AIM_SENS / max(delta, 0.0001)
	_mouse_aim_delta = Vector2.ZERO
	if auto_demo:
		# Steer toward the current target (with a little weave) so capture frames keep the
		# battle framed instead of drifting into empty space.
		if is_instance_valid(target):
			var lp: Vector3 = player.to_local(target.global_position)
			yaw += clamp(-lp.x * 0.15, -1.0, 1.0)
			pitch += clamp(lp.y * 0.15, -1.0, 1.0)
		yaw += sin(_elapsed * 0.7) * 0.2
	var rate: float = player.eff_turn_rate()
	player.rotate_object_local(Vector3.UP, yaw * rate * delta)
	player.rotate_object_local(Vector3.RIGHT, pitch * rate * delta)
	player.rotate_object_local(Vector3.FORWARD, roll * rate * 1.4 * delta)

	# Forward thrust along ship -Z. Damaged/offline engines cut speed and accel.
	var fwd: Vector3 = -player.global_transform.basis.z
	var target_speed: float = player.eff_max_speed() * throttle * (1.7 if boosting else 1.0)
	if braking:
		target_speed *= 0.15
	player.velocity = player.velocity.move_toward(fwd * target_speed, player.eff_accel() * (2.2 if braking else 1.0) * delta)

	# Energy: boost drains, otherwise regen.
	if boosting:
		player.energy = max(0.0, player.energy - 30.0 * delta)
		if audio and int(_elapsed * 6.0) % 3 == 0:
			audio.play("thruster", rng.randf_range(0.9, 1.1))
	else:
		player.energy = min(player.max_energy, player.energy + 14.0 * delta)
	# Shield regen, scaled by the shield subsystem (offline = none, damaged = 30%).
	if not player.disabled:
		player.shield = min(player.max_shield, player.shield + 6.0 * delta * player.shield_regen_mult())

	# Firing.
	var want_fire: bool = _flight_pressed("fire") or auto_demo
	if want_fire:
		_try_fire(player, delta)

	# Target cycling.
	if Input.is_action_just_pressed("next_target"):
		_cycle_target()
	if auto_demo and target == null:
		_cycle_target()

	# Subsystem focus cycling: none -> engines -> weapons -> shields -> none.
	if Input.is_action_just_pressed("cycle_subsystem"):
		_cycle_subsystem_focus()

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
			if fleet_order == "attack" and is_instance_valid(fleet_attack_target):
				_ai_attack_target(s, delta)
			elif s.ai_state == "hold" or fleet_order == "hold":
				_ai_hold_position(s, delta)
			else:
				_ai_follow_player(s, delta)
		else:
			_ai_combat(s, delta)

func _ai_hold_position(s: Node3D, delta: float) -> void:
	# Fleet command mode: hold the current tactical point while still firing at
	# close hostiles. This makes [F] a real command order, not only a crew-assignment key.
	var id: int = s.get_instance_id()
	if not fleet_hold_positions.has(id):
		fleet_hold_positions[id] = s.global_position
	var goal: Vector3 = fleet_hold_positions[id]
	var enemy: Node3D = _nearest(s, "hostile")
	if enemy != null and s.global_position.distance_to(enemy.global_position) < s.weapon_range:
		_face_and_fire(s, enemy, delta)
		s.target = enemy
	if s.global_position.distance_to(goal) > 7.0:
		_steer_toward(s, goal, delta, 0.45)
	else:
		s.throttle = 0.0
		s.velocity = s.velocity.move_toward(Vector3.ZERO, s.accel * delta)

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

func _ai_attack_target(s: Node3D, delta: float) -> void:
	# Fleet attack order: every manned escort focus-fires the commanded target even when
	# other hostiles are closer. Validity is guaranteed by _validate_fleet_attack().
	var foe: Node3D = fleet_attack_target
	s.target = foe
	var dist: float = s.global_position.distance_to(foe.global_position)
	if dist > s.weapon_range * 0.7:
		_steer_toward(s, foe.global_position, delta, 1.0)
	else:
		# Hold attack range while keeping the nose on the target.
		_steer_toward(s, foe.global_position, delta, 0.4)
	_face_and_fire(s, foe, delta)

func _validate_fleet_attack() -> void:
	# Drop attack mode the moment the commanded target is captured, destroyed, turned
	# friendly or otherwise invalid, falling the fleet back to follow formation.
	if fleet_order != "attack":
		return
	var t: Node3D = fleet_attack_target
	if is_instance_valid(t) and not t.destroyed and t.faction != "player":
		return
	fleet_attack_target = null
	fleet_order = "follow"
	for s in ships:
		if is_instance_valid(s) and s.faction == "player" and not s.is_player and s.manned:
			s.ai_state = "follow"
	_msg("Attack target lost — fleet reverts to FOLLOW formation.")

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
	s.global_transform.basis = s.global_transform.basis.slerp(desired, clamp(s.eff_turn_rate() * delta, 0.0, 1.0)).orthonormalized()
	var fwd: Vector3 = -s.global_transform.basis.z
	s.throttle = throttle_mul
	s.velocity = s.velocity.move_toward(fwd * s.eff_max_speed() * throttle_mul, s.eff_accel() * delta)

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
func _try_fire(s: Node3D, delta: float, forced_target: Node3D = null) -> bool:
	# Weapons subsystem OFFLINE: cannot fire, and the cooldown never advances.
	if not s.can_fire():
		return false
	var aim_target: Node3D = forced_target if forced_target != null else (target if s.is_player else s.target)
	# Ships with independent turrets fire each mount on its own cooldown/arc.
	if s.has_turrets():
		return _try_fire_turrets(s, delta, aim_target)
	# --- fixed-muzzle path (fighter/corvette): fire all muzzles at once ---
	s.weapon_cd -= delta
	if s.weapon_cd > 0.0:
		return false
	if s.energy < 2.0:
		return false
	# DAMAGED weapons fire at half rate (doubled cooldown).
	s.weapon_cd = s.fire_rate * s.weapon_cd_mult()
	s.energy = max(0.0, s.energy - 2.0)
	if s.weapon_type == "beam":
		_fire_beam(s, aim_target)
	else:
		_fire_projectile(s, aim_target)
	return true

func _try_fire_turrets(s: Node3D, delta: float, aim_target: Node3D) -> bool:
	# Each turret tracks/cools on its own (ticked in _process_space). Here we only fire
	# the mounts that are both ready and aimed at the target within their arc.
	if aim_target == null or not is_instance_valid(aim_target):
		return false
	var fired: bool = false
	var cd_mult: float = s.weapon_cd_mult()
	for i in range(s.turrets.size()):
		var td: Dictionary = s.turrets[i]
		if float(td["cd"]) > 0.0:
			continue
		if not s.turret_ready_and_aimed(i, aim_target):
			continue
		if s.energy < 1.0:
			break
		td["cd"] = float(td["base_cd"]) * cd_mult
		s.energy = max(0.0, s.energy - 1.0)
		var origin: Vector3 = s.turret_muzzle_world(i)
		var fire_dir: Vector3 = s.turret_fire_dir(i)
		if s.weapon_type == "beam":
			_fire_beam_from(s, aim_target, origin, fire_dir)
		else:
			_fire_projectile_from(s, aim_target, origin, fire_dir)
		fired = true
	return fired

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
		_spawn_muzzle_flash(origin, s.faction)
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
		# Only player shots carry a subsystem focus; AI fire is always generic hull damage.
		var shot_sub: String = subsystem_focus if s.is_player else ""
		projectiles.append({
			"node": node,
			"vel": aim_dir * speed + s.velocity,
			"dmg": s.weapon_dmg,
			"ttl": s.weapon_range / speed + 0.4,
			"faction": s.faction,
			"subsystem": shot_sub,
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
	_spawn_muzzle_flash(origin, s.faction)
	beams.append({"node": node, "ttl": 0.3})
	# Hitscan damage.
	_apply_damage(s, aim_target, s.weapon_dmg)
	if audio:
		audio.play("beam")

func _fire_projectile_from(s: Node3D, aim_target: Node3D, origin: Vector3, fire_dir: Vector3) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var cm: CapsuleMesh = CapsuleMesh.new()
	cm.radius = 0.26
	cm.height = 3.2
	node.mesh = cm
	var col: Color = Color(0.5, 1.0, 0.6, 1.0) if s.faction == "player" else Color(1.0, 0.5, 0.35, 1.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 8.0
	node.material_override = mat
	add_child(node)
	node.global_position = origin
	_spawn_muzzle_flash(origin, s.faction)
	node.look_at(origin + fire_dir, Vector3.UP)
	node.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var speed: float = 90.0
	var shot_sub: String = subsystem_focus if s.is_player else ""
	projectiles.append({
		"node": node,
		"vel": fire_dir * speed + s.velocity,
		"dmg": s.weapon_dmg,
		"ttl": s.weapon_range / speed + 0.4,
		"faction": s.faction,
		"subsystem": shot_sub,
	})
	if audio:
		audio.play("laser", rng.randf_range(0.9, 1.1))

func _fire_beam_from(s: Node3D, aim_target: Node3D, origin: Vector3, fire_dir: Vector3) -> void:
	# Beam hitscan along fire_dir, up to weapon_range.
	var dest: Vector3 = origin + fire_dir * s.weapon_range
	# If we have a valid target, snap the beam endpoint to the target for visual clarity.
	if aim_target != null and is_instance_valid(aim_target):
		dest = aim_target.global_position
	var mid: Vector3 = (origin + dest) * 0.5
	var length: float = origin.distance_to(dest)
	var node: MeshInstance3D = MeshInstance3D.new()
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.4
	cm.height = length
	node.mesh = cm
	var col: Color = Color(0.6, 1.0, 0.8, 1.0) if s.faction == "player" else Color(1.0, 0.4, 0.5, 1.0)
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
	_spawn_muzzle_flash(origin, s.faction)
	beams.append({"node": node, "ttl": 0.3})
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
				_deal_damage(s, float(pd["dmg"]), String(pd.get("subsystem", "")), node.global_position)
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
func _apply_damage(attacker: Node3D, victim: Node3D, dmg: float) -> void:
	# Used by hitscan beams and tests. Player attacks route into the focused subsystem
	# (the same focus carried by player projectiles); all AI damage stays generic.
	if not is_instance_valid(victim):
		return
	var sub: String = subsystem_focus if (is_instance_valid(attacker) and attacker.is_player) else ""
	var ev: Dictionary = victim.take_damage(dmg, sub)
	# Beam hitscan position is less precise; pass ZERO so the shield impact is skipped
	# (the full-bubble _shield_flash in ship.tick_visuals still fires for beams).
	_handle_damage_events(victim, ev, Vector3.ZERO)

func _deal_damage(victim: Node3D, dmg: float, subsystem: String = "", impact_pos: Vector3 = Vector3.ZERO) -> void:
	# Used by projectile impacts: the subsystem focus is baked into the projectile at
	# fire time so the shot routes correctly even if the player re-focuses mid-flight.
	if not is_instance_valid(victim):
		return
	var ev: Dictionary = victim.take_damage(dmg, subsystem)
	_handle_damage_events(victim, ev, impact_pos)

func _handle_damage_events(victim: Node3D, ev: Dictionary, impact_pos: Vector3 = Vector3.ZERO) -> void:
	if audio:
		if bool(ev.get("subsystem_hit", false)):
			audio.play("subsystem_hit", rng.randf_range(0.95, 1.1))
		elif bool(ev.get("shield_hit", false)):
			audio.play("shield", 1.0)
		else:
			audio.play("hit", rng.randf_range(0.9, 1.2))
	# Localized impact VFX at the precise hit point (projectile impacts only; beams pass ZERO).
	if impact_pos != Vector3.ZERO and is_instance_valid(victim):
		if bool(ev.get("shield_hit", false)):
			_spawn_shield_impact(impact_pos, victim)
		# Shields down -> the hull is taking the hit: scorch the hull at the impact point.
		if float(victim.shield) <= 0.0 and not bool(ev.get("destroyed", false)):
			_spawn_hit_decal(victim, impact_pos)
	if bool(ev.get("disabled", false)):
		_msg("%s DISABLED — board it with marines [B]." % victim.ship_name)
		if audio:
			audio.play("disabled")
	if bool(ev.get("destroyed", false)):
		_destroy_ship(victim)

func _destroy_ship(s: Node3D) -> void:
	_spawn_explosion(s.global_position, s.radius())
	_spawn_debris(s.global_position, s.radius(), s.faction)
	if audio:
		audio.play("explosion")
	if s.faction == "hostile":
		var reward: int = _destroy_salvage_reward(s)
		Game.credits += reward
		_msg("%s destroyed — salvage +%d cr." % [s.ship_name, reward])
	else:
		_msg("%s destroyed." % s.ship_name)
	if s.has_meta("assigned_crew"):
		var assigned_crew: Array = s.get_meta("assigned_crew", [])
		Game.unassign_crew(assigned_crew)
		s.remove_meta("assigned_crew")
	if s == target:
		target = null
	if boarding_target == s:
		_cancel_boarding()
	# Clear stale target references on other ships so they don't hold a freed instance.
	for other in ships:
		if is_instance_valid(other) and other.target == s:
			other.target = null
	ships.erase(s)
	s.queue_free()

func _ship_credit_value(s: Node3D) -> int:
	return int(Game.class_stat(s.ship_class, "value"))

func _capture_credit_reward(s: Node3D) -> int:
	return max(MIN_CAPTURE_BOUNTY, int(ceil(float(_ship_credit_value(s)) * CAPTURE_BOUNTY_RATE)))

func _destroy_salvage_reward(s: Node3D) -> int:
	return max(MIN_DESTROY_SALVAGE, int(ceil(float(_ship_credit_value(s)) * DESTROY_SALVAGE_RATE)))

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
# COMBAT VFX: muzzle flashes, shield impacts, hit decals, debris
# ---------------------------------------------------------------------------
func _spawn_muzzle_flash(pos: Vector3, faction: String) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.8
	sm.height = 1.6
	node.mesh = sm
	var col: Color = Color(0.5, 1.0, 0.6, 1.0) if faction == "player" else Color(1.0, 0.5, 0.35, 1.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 10.0
	node.material_override = mat
	add_child(node)
	node.global_position = pos
	_muzzle_flashes.append({"node": node, "mat": mat, "ttl": 0.12, "life": 0.12, "start_scale": 1.0, "end_scale": 2.5})

func _update_muzzle_flashes(delta: float) -> void:
	var keep: Array = []
	for e in _muzzle_flashes:
		var ed: Dictionary = e
		ed["ttl"] = float(ed["ttl"]) - delta
		var node: Node3D = ed["node"]
		if not is_instance_valid(node):
			continue
		var t: float = 1.0 - clamp(float(ed["ttl"]) / float(ed["life"]), 0.0, 1.0)
		var sc: float = lerp(float(ed["start_scale"]), float(ed["end_scale"]), t)
		node.scale = Vector3(sc, sc, sc)
		var mat: StandardMaterial3D = ed["mat"]
		mat.albedo_color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 1.0 - t)
		if float(ed["ttl"]) <= 0.0:
			node.queue_free()
		else:
			keep.append(ed)
	_muzzle_flashes = keep

func _spawn_shield_impact(pos: Vector3, victim: Node3D) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 1.5
	sm.height = 3.0
	node.mesh = sm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.5, 0.8, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.7, 1.0)
	mat.emission_energy_multiplier = 4.0
	node.material_override = mat
	add_child(node)
	node.global_position = pos
	_shield_impacts.append({"node": node, "mat": mat, "ttl": 0.3, "life": 0.3, "start_scale": 0.5, "end_scale": 2.0})

func _update_shield_impacts(delta: float) -> void:
	var keep: Array = []
	for e in _shield_impacts:
		var ed: Dictionary = e
		ed["ttl"] = float(ed["ttl"]) - delta
		var node: Node3D = ed["node"]
		if not is_instance_valid(node):
			continue
		var t: float = 1.0 - clamp(float(ed["ttl"]) / float(ed["life"]), 0.0, 1.0)
		var sc: float = lerp(float(ed["start_scale"]), float(ed["end_scale"]), t)
		node.scale = Vector3(sc, sc, sc)
		var mat: StandardMaterial3D = ed["mat"]
		mat.albedo_color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, 0.8 * (1.0 - t))
		if float(ed["ttl"]) <= 0.0:
			node.queue_free()
		else:
			keep.append(ed)
	_shield_impacts = keep

func _spawn_hit_decal(victim: Node3D, impact_pos: Vector3) -> void:
	# Cap per ship so long fights don't grow unbounded decal counts.
	if int(victim.get_meta("decal_count", 0)) >= 8:
		return
	var parent: Node3D = victim.get_node_or_null("Hull")
	if parent == null:
		parent = victim
	var node: MeshInstance3D = MeshInstance3D.new()
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(0.8, 0.8)
	node.mesh = qm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.03, 0.02, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.1, 0.05)
	mat.emission_energy_multiplier = 0.3
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	node.material_override = mat
	parent.add_child(node)
	# Sit just outside the hull at the impact point, facing outward from the ship centre.
	var outward: Vector3 = (impact_pos - victim.global_position).normalized()
	node.global_position = impact_pos + outward * 0.05
	node.look_at(victim.global_position, Vector3.UP)
	victim.set_meta("decal_count", int(victim.get_meta("decal_count", 0)) + 1)

func _spawn_debris(pos: Vector3, base_radius: float, faction: String) -> void:
	var hull_col: Color = Color(0.4, 0.4, 0.42, 1.0)
	if faction == "player":
		hull_col = Color(0.25, 0.6, 0.38, 1.0)
	elif faction == "hostile":
		hull_col = Color(0.6, 0.25, 0.2, 1.0)
	var count: int = rng.randi_range(4, 8)
	for i in range(count):
		var node: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		var fs: float = rng.randf_range(0.5, 1.5)
		bm.size = Vector3(0.4, 0.4, 0.4) * fs
		node.mesh = bm
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = hull_col
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.4, 0.15)
		mat.emission_energy_multiplier = 2.0
		node.material_override = mat
		add_child(node)
		node.global_position = pos + Vector3(
			rng.randf_range(-base_radius, base_radius),
			rng.randf_range(-base_radius, base_radius),
			rng.randf_range(-base_radius, base_radius))
		var vel: Vector3 = Vector3(rng.randf_range(-15, 15), rng.randf_range(-15, 15), rng.randf_range(-15, 15))
		var rot_vel: Vector3 = Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		_debris.append({"node": node, "vel": vel, "rot_vel": rot_vel, "ttl": 1.5, "life": 1.5, "mat": mat})

func _update_debris(delta: float) -> void:
	var keep: Array = []
	for e in _debris:
		var ed: Dictionary = e
		ed["ttl"] = float(ed["ttl"]) - delta
		var node: Node3D = ed["node"]
		if not is_instance_valid(node):
			continue
		var vel: Vector3 = ed["vel"]
		var rot_vel: Vector3 = ed["rot_vel"]
		node.global_position += vel * delta
		node.rotate_x(rot_vel.x * delta)
		node.rotate_y(rot_vel.y * delta)
		node.rotate_z(rot_vel.z * delta)
		var mat: StandardMaterial3D = ed["mat"]
		mat.albedo_color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, clamp(float(ed["ttl"]) / float(ed["life"]), 0.0, 1.0))
		if float(ed["ttl"]) <= 0.0:
			node.queue_free()
		else:
			keep.append(ed)
	_debris = keep

# ---------------------------------------------------------------------------
# TARGETING / RADAR
# ---------------------------------------------------------------------------
func _cycle_target() -> void:
	var hostile_candidates: Array = []
	var other_candidates: Array = []
	for s in ships:
		if is_instance_valid(s) and not s.is_player and not s.destroyed and s.faction != "player":
			if s.faction == "hostile":
				hostile_candidates.append(s)
			else:
				other_candidates.append(s)
	# Combat targeting should cycle hostiles first so the neutral shipyard hub does not
	# steal the first [Tab] target. Fall back to neutral/non-player assets only after the
	# hostile force has been cleared.
	var candidates: Array = hostile_candidates if not hostile_candidates.is_empty() else other_candidates
	if candidates.is_empty():
		target = null
		return
	candidates.sort_custom(func(a, b): return _pdist(a) < _pdist(b))
	var idx: int = candidates.find(target)
	target = candidates[(idx + 1) % candidates.size()]
	_msg("Target: %s (%s)" % [target.ship_name, target.faction])

func _cycle_subsystem_focus() -> void:
	# Player-only tactical aim: route fire into one subsystem of the current target.
	match subsystem_focus:
		"engines":
			subsystem_focus = "weapons"
		"weapons":
			subsystem_focus = "shields"
		"shields":
			subsystem_focus = ""
		_:
			subsystem_focus = "engines"
	var label: String = subsystem_focus if subsystem_focus != "" else "none"
	_msg("Subsystem focus: %s" % label)
	if audio: audio.play("ui_recruit")

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
	# Capture-mode should demonstrate the new systems, not randomly kill the flagship
	# before screenshots finish. Give the player temporary demo durability only when
	# VOIDBORNE_CAPTURE/auto_demo stages the scene.
	player.max_shield = max(player.max_shield, 900.0)
	player.shield = player.max_shield
	player.max_hull = max(player.max_hull, 1200.0)
	player.hull = player.max_hull
	player.max_energy = max(player.max_energy, 500.0)
	player.energy = player.max_energy
	player.disabled = false
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
	_order_fleet_attack()   # set ATTACK order so the HUD/radar show the focus-fire command
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
	boarding_failed = false
	boarding_target = target
	boarding_progress = 0.0
	boarding_round_timer = 0.0
	boarding_round_count = 0
	boarding_attacker_strength = Game.marine_pool
	boarding_defender_strength = int(target.marine_garrison)
	boarding_initial_attacker = boarding_attacker_strength
	boarding_initial_defender = boarding_defender_strength
	_msg("Boarding %s — %d marines vs %d defenders!" % [target.ship_name, boarding_attacker_strength, boarding_defender_strength])
	if audio: audio.play("board")
	# An undefended target is captured the instant the boarders cross over.
	if boarding_defender_strength <= 0:
		_complete_capture(boarding_target)

func _update_boarding(delta: float) -> void:
	if not boarding_active:
		return
	if not is_instance_valid(boarding_target) or boarding_target.destroyed:
		_cancel_boarding()
		return
	# Marines must stay close; the boarding craft cannot tow a fleeing/disabled hull far.
	if _pdist(boarding_target) > 120.0:
		_msg("Boarding aborted — drifted out of range.")
		_cancel_boarding()
		return
	# Resolve squad combat in fixed-length rounds. Large frame deltas (tests) resolve
	# several rounds at once; each round may end the boarding (capture or failure).
	boarding_round_timer += delta
	while boarding_active and boarding_round_timer >= BOARD_ROUND_INTERVAL:
		boarding_round_timer -= BOARD_ROUND_INTERVAL
		_resolve_boarding_round()
	_update_boarding_bar()

func _resolve_boarding_round() -> void:
	var atk: int = boarding_attacker_strength
	var def: int = boarding_defender_strength
	# Each side inflicts casualties proportional to its own strength. Guarantee at least one
	# casualty on a non-empty foe so small forces still resolve (no integer-floor stalemate).
	var atk_cas: int = 0
	if def > 0:
		atk_cas = max(1, int(round(float(def) * BOARD_EXCHANGE_RATE * rng.randf_range(0.7, 1.3))))
	var def_cas: int = 0
	if atk > 0:
		def_cas = max(1, int(round(float(atk) * BOARD_EXCHANGE_RATE * rng.randf_range(0.7, 1.3))))
	boarding_attacker_strength = max(0, atk - atk_cas)
	boarding_defender_strength = max(0, def - def_cas)
	boarding_round_count += 1
	if audio:
		audio.play("boarding_round", rng.randf_range(0.9, 1.2))
	# Report every other round to keep the log readable during a long assault.
	if boarding_round_count % 2 == 1:
		_msg("Breach round %d — ATK: %d (-%d)  DEF: %d (-%d)" % [boarding_round_count, boarding_attacker_strength, atk_cas, boarding_defender_strength, def_cas])
	if boarding_defender_strength <= 0:
		_complete_capture(boarding_target)
	elif boarding_attacker_strength <= 0:
		_fail_boarding()

func _update_boarding_bar() -> void:
	# Bar shows nearness to capture, derived from defenders remaining / initial defenders.
	if boarding_initial_defender <= 0:
		boarding_progress = 1.0
	else:
		boarding_progress = clamp(1.0 - float(boarding_defender_strength) / float(boarding_initial_defender), 0.0, 1.0)

func _fail_boarding() -> void:
	var lost: int = boarding_initial_attacker
	var holders: int = boarding_defender_strength
	var nm: String = boarding_target.ship_name if is_instance_valid(boarding_target) else "target"
	Game.marine_pool = 0
	boarding_failed = true
	_msg("BOARDING FAILED — all %d marines lost. %s holds with %d defenders." % [lost, nm, holders])
	if audio: audio.play("boarding_fail")
	_cancel_boarding()

func _cancel_boarding() -> void:
	boarding_active = false
	boarding_target = null
	boarding_progress = 0.0
	boarding_round_timer = 0.0
	boarding_round_count = 0
	boarding_attacker_strength = 0
	boarding_defender_strength = 0

func _complete_capture(s: Node3D) -> void:
	var was_hostile: bool = s.faction == "hostile"
	var reward: int = _capture_credit_reward(s) if was_hostile else 0
	var attackers_lost: int = max(0, boarding_initial_attacker - boarding_attacker_strength)
	var defenders_lost: int = max(0, boarding_initial_defender - boarding_defender_strength)
	s.set_faction("player")
	s.disabled = false
	s.hull = max(s.hull, s.max_hull * 0.4)
	# Captured asset starts ungarrisoned; the surviving boarders become the new marine pool.
	s.marine_garrison = 0
	Game.marine_pool = max(0, boarding_attacker_strength)
	Game.captured_count += 1
	_msg("Boarding won: %d attackers lost, %d defenders lost." % [attackers_lost, defenders_lost])
	if reward > 0:
		Game.credits += reward
		_msg("Boarding prize secured: +%d cr capture bounty." % reward)
	# Try to man it from the crew pool; otherwise it is captured-but-unmanned.
	if Game.crew_pool >= s.crew_needed:
		var assigned_crew: Array = Game.assign_best_crew(s.crew_needed)
		s.set_meta("assigned_crew", assigned_crew)
		s.apply_crew_bonuses(assigned_crew)
		s.crew_assigned = assigned_crew.size()
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
	# Control settings toggles (always available regardless of control_scheme).
	if Input.is_action_just_pressed("mouse_aim"):
		_toggle_mouse_aim()
	if Input.is_action_just_pressed("settings"):
		_toggle_settings()
	if Input.is_action_just_pressed("cycle_scheme"):
		_cycle_control_scheme()
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
	if Input.is_action_just_pressed("station_service"):
		_station_service()
	if Input.is_action_just_pressed("follow_toggle"):
		_toggle_fleet_follow()
	if Input.is_action_just_pressed("fleet_attack"):
		_order_fleet_attack()

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
		var new_crew: Dictionary = Game.recruit_crew_member(rng)
		var role_abbr: String = String(Game.ROLE_ABBR.get(new_crew.get("role", ""), "?"))
		_msg("Recruited %s [%s] S%d (%d available). Cost %d." % [new_crew.get("name", "Crew"), role_abbr, int(new_crew.get("skill", 1)), Game.crew_pool, cost])
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
		var assigned_crew: Array = Game.assign_best_crew(need)
		s.set_meta("assigned_crew", assigned_crew)
		s.apply_crew_bonuses(assigned_crew)
		s.crew_assigned = assigned_crew.size()
		s.manned = true
		s.ai_state = "follow"
		_msg("Bought %s and assigned %d crew — manned, joins fleet." % [buy_class, assigned_crew.size()])
	else:
		s.manned = false
		s.crew_assigned = 0
		_msg("Bought %s but UNMANNED (needs %d crew)." % [buy_class, need])
	if audio: audio.play("ui_buy")

# ---------------------------------------------------------------------------
# STATION REPAIR / REFIT SERVICE
# ---------------------------------------------------------------------------
func _service_station() -> Node3D:
	# Nearest non-hostile station within docking-service range of the flagship.
	# Both the neutral hub and any captured/player-owned station provide service.
	if not is_instance_valid(player):
		return null
	var best: Node3D = null
	var bd: float = SERVICE_RANGE
	for s in ships:
		if not is_instance_valid(s) or s.destroyed or s.ship_class != "station":
			continue
		if s.faction == "hostile":
			continue
		var d: float = _pdist(s)
		if d <= bd:
			bd = d
			best = s
	return best

func _service_targets() -> Array:
	# Flagship plus every manned, non-destroyed player-owned mobile ship. Unmanned
	# captured ships and owned stations are intentionally excluded.
	var out: Array = []
	for s in ships:
		if not is_instance_valid(s) or s.destroyed:
			continue
		if s.faction != "player" or not s.manned or s.ship_class == "station":
			continue
		out.append(s)
	return out

func _service_raw_cost(targets: Array) -> float:
	var raw: float = 0.0
	for s in targets:
		raw += max(0.0, s.max_hull - s.hull) * SERVICE_HULL_RATE
		raw += max(0.0, s.max_shield - s.shield) * SERVICE_SHIELD_RATE
		raw += max(0.0, s.max_energy - s.energy) * SERVICE_ENERGY_RATE
		var sub_deficit: float = (1.0 - s.sub_engine) + (1.0 - s.sub_weapon) + (1.0 - s.sub_shield)
		raw += sub_deficit * SERVICE_SUBSYS_RATE
	return raw

func _service_estimate() -> Dictionary:
	# HUD helper: what the dock would charge right now, if a service station is in range.
	var svc: Node3D = _service_station()
	if svc == null:
		return {}
	var raw: float = _service_raw_cost(_service_targets())
	var cost: int = 0
	if raw >= 1.0:
		cost = max(SERVICE_MIN_CHARGE, int(ceil(raw)))
	return {"station": svc.ship_name, "cost": cost}

func _station_service() -> void:
	var svc: Node3D = _service_station()
	if svc == null:
		# Clarify the hostile-station case so the deny reads as a gameplay rule, not a bug.
		var near_hostile: bool = false
		for s in ships:
			if is_instance_valid(s) and not s.destroyed and s.ship_class == "station" and s.faction == "hostile" and _pdist(s) <= SERVICE_RANGE:
				near_hostile = true
				break
		if near_hostile:
			_msg("Hostile station denies dock services — capture it first.")
		else:
			_msg("No friendly station in range — dock at a station for repair/refit [H].")
		if audio: audio.play("ui_deny")
		return

	var targets: Array = _service_targets()
	var raw_cost: float = _service_raw_cost(targets)
	if raw_cost < 1.0:
		_msg("%s: all fleet systems nominal — no repair/refit needed." % svc.ship_name)
		return

	var budget: int = Game.credits
	if budget <= 0:
		_msg("No credits for repairs at %s." % svc.ship_name)
		if audio: audio.play("ui_deny")
		return

	var desired_charge: int = max(SERVICE_MIN_CHARGE, int(ceil(raw_cost)))
	var fraction: float = 1.0
	var charge: int = desired_charge
	if budget < desired_charge:
		# Partial service: spend the available budget and restore proportionally against
		# the actual service bill, including the minimum dock charge for light damage.
		fraction = clamp(float(budget) / float(desired_charge), 0.0, 1.0)
		charge = budget

	var serviced: int = 0
	for s in targets:
		s.hull = min(s.max_hull, s.hull + (s.max_hull - s.hull) * fraction)
		s.shield = min(s.max_shield, s.shield + (s.max_shield - s.shield) * fraction)
		s.energy = min(s.max_energy, s.energy + (s.max_energy - s.energy) * fraction)
		s.restore_subsystems(fraction)   # refit also rebuilds engine/weapon/shield subsystems
		if s.disabled and s.hull > s.max_hull * DISABLE_FRAC:
			s.disabled = false
		serviced += 1

	Game.credits -= charge
	if fraction >= 1.0:
		_msg("%s serviced %d ship(s): hull/shield/energy restored. Cost %d cr." % [svc.ship_name, serviced, charge])
	else:
		_msg("%s partial refit (%d%%) on %d ship(s) — credits limited. Spent %d cr." % [svc.ship_name, int(round(fraction * 100.0)), serviced, charge])
	if audio: audio.play("ui_buy")

func _order_fleet_attack() -> void:
	# Explicit tactical command: order every manned escort to focus-fire the current
	# target. Space mode only (this runs from _handle_station_actions).
	if target == null or not is_instance_valid(target) or target.destroyed:
		_msg("No valid target to attack. [Tab] to select a hostile first.")
		if audio: audio.play("ui_deny")
		return
	if target.faction == "player":
		_msg("%s is one of yours — pick a hostile to attack." % target.ship_name)
		if audio: audio.play("ui_deny")
		return
	if target.faction == "neutral":
		_msg("%s is neutral — we don't fire on neutrals. Pick a hostile." % target.ship_name)
		if audio: audio.play("ui_deny")
		return
	fleet_order = "attack"
	fleet_attack_target = target
	fleet_hold_positions.clear()
	var n: int = 0
	for s in ships:
		if not is_instance_valid(s) or s.faction != "player" or s.is_player or not s.manned:
			continue
		s.ai_state = "attack"
		s.target = target
		n += 1
	if n > 0:
		_msg("Fleet order: ATTACK %s — %d escort(s) focus fire." % [target.ship_name, n])
	else:
		_msg("Fleet order: ATTACK %s (no manned escorts yet)." % target.ship_name)
	if audio: audio.play("ui_recruit")

func _toggle_fleet_follow() -> void:
	# First use available crew to man any owned ships; if none need crew, [F] toggles
	# a tactical fleet order between follow formation and hold position.
	var changed: int = 0
	for s in ships:
		if not is_instance_valid(s) or s.faction != "player" or s.is_player:
			continue
		if not s.manned and Game.crew_pool >= s.crew_needed:
			var assigned_crew: Array = Game.assign_best_crew(s.crew_needed)
			s.set_meta("assigned_crew", assigned_crew)
			s.apply_crew_bonuses(assigned_crew)
			s.crew_assigned = assigned_crew.size()
			s.manned = true
			s.ai_state = fleet_order if fleet_order != "attack" else "follow"
			changed += 1
	if changed > 0:
		_msg("Assigned crew to %d ship(s) — now manned and ordered." % changed)
		if audio: audio.play("ui_recruit")
		return

	# Toggling follow/hold always clears any standing attack order; an attack order
	# resolves to follow (its escorts disengage the focus target and re-form).
	fleet_attack_target = null

	if fleet_order == "follow":
		fleet_order = "hold"
		fleet_hold_positions.clear()
		for fs in ships:
			if is_instance_valid(fs) and fs.faction == "player" and not fs.is_player and fs.manned:
				fs.ai_state = "hold"
				fleet_hold_positions[fs.get_instance_id()] = fs.global_position
		_msg("Fleet order: HOLD POSITION and cover the flagship.")
	else:
		fleet_order = "follow"
		fleet_hold_positions.clear()
		for fs2 in ships:
			if is_instance_valid(fs2) and fs2.faction == "player" and not fs2.is_player and fs2.manned:
				fs2.ai_state = "follow"
		_msg("Fleet order: FOLLOW formation on the flagship.")
	if audio: audio.play("ui_recruit")

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
# PERSISTENT SAVE / LOAD
# ---------------------------------------------------------------------------
func _handle_save_load() -> void:
	# Works in both space and crew-deck mode; loading from the deck returns to the bridge.
	if Input.is_action_just_pressed("quick_save"):
		_quick_save()
	if Input.is_action_just_pressed("quick_load"):
		_quick_load()

func _quick_save() -> bool:
	var data: Dictionary = _build_save_dict()
	var f: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		_msg("Save failed: cannot open %s" % save_path)
		if audio: audio.play("ui_deny")
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_msg("Game SAVED (v%d) — %d cr, fleet %d." % [SAVE_VERSION, Game.credits, _count_fleet()])
	if audio: audio.play("ui_buy")
	return true

func _build_save_dict() -> Dictionary:
	var ship_list: Array = []
	for s in ships:
		if not is_instance_valid(s) or s.destroyed:
			continue   # destroyed ships are omitted; they must not resurrect on load
		ship_list.append(_ship_to_dict(s))
	var atk_name: String = ""
	if is_instance_valid(fleet_attack_target):
		atk_name = String(fleet_attack_target.ship_name)
	var tgt_name: String = ""
	if is_instance_valid(target) and not target.destroyed:
		tgt_name = String(target.ship_name)
	return {
		"game_id": SAVE_GAME_ID,
		"version": SAVE_VERSION,
		"economy": {
			"credits": Game.credits,
			"crew_pool": Game.crew_pool,
			"marine_pool": Game.marine_pool,
			"captured_count": Game.captured_count,
			"purchased_count": Game.purchased_count,
			"crew_roster": Game.roster_to_save(),
		},
		"shipyard_index": shipyard_index,
		"fleet_order": fleet_order,
		"fleet_attack_target": atk_name,
		"target": tgt_name,
		"ships": ship_list,
	}

func _ship_to_dict(s: Node3D) -> Dictionary:
	var d: Dictionary = {
		"ship_name": s.ship_name,
		"ship_class": s.ship_class,
		"faction": s.faction,
		"is_player": s.is_player,
		"manned": s.manned,
		"crew_assigned": s.crew_assigned,
		"marine_garrison": s.marine_garrison,
		"hull": s.hull,
		"max_hull": s.max_hull,
		"shield": s.shield,
		"max_shield": s.max_shield,
		"energy": s.energy,
		"max_energy": s.max_energy,
		"disabled": s.disabled,
		"destroyed": s.destroyed,
		"ai_state": s.ai_state,
		"sub_engine": s.sub_engine,
		"sub_weapon": s.sub_weapon,
		"sub_shield": s.sub_shield,
		"pos": [s.global_position.x, s.global_position.y, s.global_position.z],
		"rot": [s.rotation.x, s.rotation.y, s.rotation.z],
	}
	# Independent turret state is only saved for ships that actually have turrets.
	if s.has_turrets():
		d["turrets"] = s.turret_state_to_array()
	return d

func _quick_load() -> bool:
	if not FileAccess.file_exists(save_path):
		_msg("No save found — press [V] to save first.")
		if audio: audio.play("ui_deny")
		return false
	var f: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		_msg("Load failed: cannot open save file.")
		if audio: audio.play("ui_deny")
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	var reason: String = _validate_save(parsed)
	if reason != "":
		# Rejected saves never clobber the live battle state.
		_msg("Save rejected: %s" % reason)
		if audio: audio.play("ui_deny")
		return false
	_apply_save(parsed)
	_msg("Game LOADED (v%d) — %d cr, fleet %d." % [int((parsed as Dictionary)["version"]), Game.credits, _count_fleet()])
	if audio: audio.play("ui_buy")
	return true

func _validate_vec3(v: Variant) -> String:
	if typeof(v) != TYPE_ARRAY:
		return "not an array"
	var arr: Array = v
	if arr.size() != 3:
		return "needs 3 elements"
	for n in arr:
		if typeof(n) != TYPE_FLOAT and typeof(n) != TYPE_INT:
			return "non-numeric"
	return ""

func _validate_save(parsed: Variant) -> String:
	# Returns "" when the payload is acceptable, otherwise a human-readable reason.
	if typeof(parsed) != TYPE_DICTIONARY:
		return "corrupt or non-object save"
	var d: Dictionary = parsed
	if String(d.get("game_id", "")) != SAVE_GAME_ID:
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
	if ver > SAVE_VERSION:
		return "future version (v%d > v%d) — update the game" % [ver, SAVE_VERSION]
	if typeof(d.get("economy")) != TYPE_DICTIONARY:
		return "missing economy section"
	var econ: Dictionary = d["economy"]
	for key in ["credits", "crew_pool", "marine_pool", "captured_count", "purchased_count"]:
		if not econ.has(key):
			return "missing economy.%s" % key
	if typeof(d.get("ships")) != TYPE_ARRAY:
		return "missing ships section"
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
		var perr: String = _validate_vec3(sd.get("pos"))
		if perr != "":
			return "ship %s pos %s" % [String(sd.get("ship_name", "?")), perr]
		var rerr: String = _validate_vec3(sd.get("rot"))
		if rerr != "":
			return "ship %s rot %s" % [String(sd.get("ship_name", "?")), rerr]
		# Marine garrison is optional (backward compatible). If present, a non-negative int.
		if sd.has("marine_garrison"):
			var garr_val: Variant = sd["marine_garrison"]
			if typeof(garr_val) != TYPE_FLOAT and typeof(garr_val) != TYPE_INT:
				return "ship %s marine_garrison non-numeric" % String(sd.get("ship_name", "?"))
			if float(garr_val) < 0.0:
				return "ship %s marine_garrison negative" % String(sd.get("ship_name", "?"))
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
		if bool(sd.get("is_player", false)):
			player_count += 1
	if player_count == 0:
		return "no player flagship in save"
	return ""

func _apply_save(parsed: Dictionary) -> void:
	# Clear transient combat/UI state, tear down the live battle, then rebuild from the save.
	_cancel_boarding()
	_clear_transient_nodes()
	if deck_mode:
		_set_deck_mode(false)
	fleet_hold_positions.clear()
	fleet_attack_target = null
	target = null

	for s in ships:
		if is_instance_valid(s):
			s.queue_free()
	ships.clear()
	player = null
	station = null

	var econ: Dictionary = parsed["economy"]
	Game.credits = int(econ["credits"])
	Game.crew_pool = int(econ["crew_pool"])
	Game.marine_pool = int(econ["marine_pool"])
	Game.captured_count = int(econ["captured_count"])
	Game.purchased_count = int(econ["purchased_count"])
	shipyard_index = int(parsed.get("shipyard_index", 0))

	if econ.has("crew_roster"):
		Game.roster_from_save(econ["crew_roster"])
	else:
		var rebuild_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rebuild_rng.randomize()
		Game.rebuild_default_roster(rebuild_rng, int(econ.get("crew_pool", 0)))

	var used_names: Dictionary = {}
	for entry in parsed["ships"]:
		_ship_from_dict(entry, used_names)

	station = _pick_station_ref()

	# Fleet order: an attack order with a missing/invalid focus target falls back to follow.
	fleet_order = String(parsed.get("fleet_order", "follow"))
	var atk_name: String = String(parsed.get("fleet_attack_target", ""))
	fleet_attack_target = _find_ship_by_name(atk_name) if atk_name != "" else null
	if fleet_order == "attack" and not (is_instance_valid(fleet_attack_target) and not fleet_attack_target.destroyed and fleet_attack_target.faction != "player"):
		fleet_order = "follow"
		fleet_attack_target = null
		for s in ships:
			if is_instance_valid(s) and s.faction == "player" and not s.is_player and s.manned:
				s.ai_state = "follow"

	# Target: keep the saved lock if still valid/hostile, else pick a remaining hostile.
	var tname: String = String(parsed.get("target", ""))
	var saved_target: Node3D = _find_ship_by_name(tname) if tname != "" else null
	if is_instance_valid(saved_target) and not saved_target.destroyed and saved_target.faction != "player":
		target = saved_target
	else:
		target = _nearest_hostile()

	if is_instance_valid(player):
		_update_camera(0.001, true)
		space_camera.current = true
		throttle = clamp(player.throttle, 0.0, 1.0)

func _ship_from_dict(entry: Variant, used_names: Dictionary) -> Node3D:
	var sd: Dictionary = entry
	var p_class: String = String(sd["ship_class"])
	var p_faction: String = String(sd["faction"])
	var nm: String = String(sd["ship_name"])
	# Guarantee a stable unique name even if a save somehow carries duplicates.
	if used_names.has(nm):
		var k: int = 2
		while used_names.has("%s#%d" % [nm, k]):
			k += 1
		nm = "%s#%d" % [nm, k]
	used_names[nm] = true

	var s: Node3D = ShipScript.new()
	s.name = "Ship_%s_%s" % [p_faction, nm]
	add_child(s)
	s.setup(p_class, p_faction, nm)
	s.ship_name = nm
	s.is_player = bool(sd.get("is_player", false))
	s.manned = bool(sd.get("manned", true))
	s.crew_assigned = int(sd.get("crew_assigned", 0))
	# Marine garrison: absent in pre-garrison saves, so default to 0 for backward compat.
	s.marine_garrison = max(0, int(sd.get("marine_garrison", 0)))
	s.max_hull = float(sd.get("max_hull", s.max_hull))
	s.hull = float(sd.get("hull", s.hull))
	s.max_shield = float(sd.get("max_shield", s.max_shield))
	s.shield = float(sd.get("shield", s.shield))
	s.max_energy = float(sd.get("max_energy", s.max_energy))
	s.energy = float(sd.get("energy", s.energy))
	s.disabled = bool(sd.get("disabled", false))
	s.destroyed = bool(sd.get("destroyed", false))
	s.ai_state = String(sd.get("ai_state", "engage"))
	# Subsystem health: defaults to 1.0 so v1 saves (no subsystem fields) load intact.
	s.sub_engine = clamp(float(sd.get("sub_engine", 1.0)), 0.0, 1.0)
	s.sub_weapon = clamp(float(sd.get("sub_weapon", 1.0)), 0.0, 1.0)
	s.sub_shield = clamp(float(sd.get("sub_shield", 1.0)), 0.0, 1.0)
	var pos: Array = sd["pos"]
	s.position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var rot: Array = sd["rot"]
	s.rotation = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
	# Turret state: optional/backward-compatible. Only restored on ships that have turrets.
	if s.has_turrets():
		var turret_state: Variant = sd.get("turrets", [])
		if typeof(turret_state) == TYPE_ARRAY:
			s.restore_turret_state(turret_state)
	ships.append(s)
	if s.is_player:
		player = s
	return s

func _clear_transient_nodes() -> void:
	for p in projectiles:
		var pd: Dictionary = p
		if is_instance_valid(pd.get("node")):
			pd["node"].queue_free()
	projectiles.clear()
	for b in beams:
		var bd: Dictionary = b
		if is_instance_valid(bd.get("node")):
			bd["node"].queue_free()
	beams.clear()
	for e in explosions:
		var ed: Dictionary = e
		if is_instance_valid(ed.get("node")):
			ed["node"].queue_free()
	explosions.clear()

func _find_ship_by_name(nm: String) -> Node3D:
	if nm == "":
		return null
	for s in ships:
		if is_instance_valid(s) and String(s.ship_name) == nm:
			return s
	return null

func _nearest_hostile() -> Node3D:
	# Nearest live hostile (including disabled, which the player may still want to board).
	var best: Node3D = null
	var bd: float = 1e9
	for s in ships:
		if not is_instance_valid(s) or s.destroyed or s.faction != "hostile":
			continue
		var d: float = _pdist(s)
		if d < bd:
			bd = d
			best = s
	return best

func _pick_station_ref() -> Node3D:
	# Prefer the neutral recruit/shipyard hub; fall back to an owned, then any non-hostile,
	# then any station so service/shipyard prompts still resolve after a load.
	var neutral_st: Node3D = null
	var owned_st: Node3D = null
	var nonhostile_st: Node3D = null
	var any_st: Node3D = null
	for s in ships:
		if not is_instance_valid(s) or s.ship_class != "station":
			continue
		if any_st == null:
			any_st = s
		if s.faction == "neutral" and neutral_st == null:
			neutral_st = s
		elif s.faction == "player" and owned_st == null:
			owned_st = s
		if s.faction != "hostile" and nonhostile_st == null:
			nonhostile_st = s
	if neutral_st != null:
		return neutral_st
	if owned_st != null:
		return owned_st
	if nonhostile_st != null:
		return nonhostile_st
	return any_st

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
	var avail: Array = Game.available_crew()
	var p_count: int = 0
	var e_count: int = 0
	var g_count: int = 0
	for c in avail:
		var role: String = String(c.get("role", ""))
		match role:
			"pilot": p_count += 1
			"engineer": e_count += 1
			"gunner": g_count += 1
	d["crew_roles"] = "(P%d E%d G%d)" % [p_count, e_count, g_count]
	d["fleet_count"] = _count_fleet()
	d["fleet_order"] = fleet_order
	if fleet_order == "attack" and is_instance_valid(fleet_attack_target):
		d["fleet_attack_target"] = fleet_attack_target.ship_name
	d["captured"] = Game.captured_count
	d["shipyard_class"] = _shipyard_class()
	d["shipyard_cost"] = _shipyard_cost()
	d["objective"] = objective
	d["messages"] = messages.duplicate()
	d["capture_demo"] = auto_demo
	d["mouse_aim"] = mouse_aim
	d["control_scheme"] = control_scheme
	d["settings_open"] = settings_open

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
			"sub_engine": target.sub_engine,
			"sub_weapon": target.sub_weapon,
			"sub_shield": target.sub_shield,
			"sub_focus": subsystem_focus,
		}
	# Boarding block: squad combat state for the HUD bar + ATK/DEF readout.
	if boarding_active and is_instance_valid(boarding_target):
		d["boarding"] = {
			"active": true,
			"name": boarding_target.ship_name,
			"progress": boarding_progress,
			"attacker": boarding_attacker_strength,
			"defender": boarding_defender_strength,
		}

	# Prompt based on context.
	d["prompt"] = _context_prompt()

	# Station repair/refit hint for the economy panel (only while docked in range).
	var svc_est: Dictionary = _service_estimate()
	if not svc_est.is_empty():
		d["service"] = svc_est

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
		return "STATION: [G] %s %dcr  [Y] buy  [R] crew  [M] marine  [H] repair  [C] deck  [V]save [L]load" % [_shipyard_class().to_upper(), _shipyard_cost()]
	var svc: Node3D = _service_station()
	if svc != null:
		return "DOCKED %s: [H] repair/refit  [Tab] target  [F] order  [V]save [L]load" % svc.ship_name
	var sub_label: String = subsystem_focus if subsystem_focus != "" else "none"
	if is_instance_valid(target) and target.disabled and target.faction != "player":
		return "[B] board %s with marines   [Z] sub: %s   [V]save [L]load" % [target.ship_name, sub_label]
	var order_label: String = fleet_order.to_upper()
	if fleet_order == "attack" and is_instance_valid(fleet_attack_target):
		order_label = "ATTACK %s" % fleet_attack_target.ship_name
	return "[Tab] target  [T] attack  [Z] sub:%s  [F] %s  [C] deck  [V]save [L]load  (order: %s)" % [sub_label, ("HOLD" if fleet_order == "follow" else "FOLLOW"), order_label]

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
			"attack": s == fleet_attack_target,
		})
	return blips

# Public hook used by the capture autoload to force the crew deck view for a screenshot.
func force_deck(on: bool) -> void:
	_set_deck_mode(on)
