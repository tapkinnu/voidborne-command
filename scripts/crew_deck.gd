extends Node3D
# CrewDeck: walkable ship-interior view with procedural humanoid crew/marines.
# Supports multiple rooms (Bridge, Crew Quarters, Marine Barracks) and
# multiple owned ships. No class_name.

var active: bool = false
var camera: Camera3D
var captain: Node3D
var crew_nodes: Array = []
var move_speed: float = 6.0
var rng: RandomNumberGenerator
var _nearest_idx: int = -1
var _follow_count: int = 0

# View mode: first-person (walk-around FPS) vs the original overhead chase view.
var first_person: bool = true
var _cam_pitch: float = 0.0          # FP look pitch, radians (clamped)
const EYE_HEIGHT: float = 2.0        # camera height above the captain's feet in FP
const LOOK_SENS: float = 0.0032      # mouse look sensitivity (radians per pixel)
const BODY_R: float = 0.4            # captain "radius" for wall clearance

# Room system. All rooms are built at once and laid out contiguously along X so the
# deck is a single seamless walkable space (no per-room reload). current_room_index is
# derived from the captain's X for the HUD label only — it never triggers a rebuild.
var current_room_index: int = 0
var _room_container: Node3D
var _crew_container: Node3D
const ROOM_NAMES: Array = ["Bridge", "Crew Quarters", "Marine Barracks"]
const ROOM_W: float = 10.0
const ROOM_D: float = 18.0
const ROOM_CENTERS: Array = [-10.0, 0.0, 10.0]
const DOOR_HALF: float = 0.6         # half-width of the passable doorway gap between rooms
# Inter-room wall X positions (boundaries between adjacent room centers).
const ROOM_BOUNDARIES: Array = [-5.0, 5.0]

# Ship system
var current_ship_index: int = 0
var ship_list: Array = []

func _build_humanoid(col: Color) -> Node3D:
	var h: Node3D = Node3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.1
	mat.roughness = 0.7
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.7, 0.6)
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.name = "Torso"
	var tm: CapsuleMesh = CapsuleMesh.new()
	tm.radius = 0.32
	tm.height = 1.18
	torso.mesh = tm
	torso.material_override = mat
	torso.position = Vector3(0, 0.95, 0)
	h.add_child(torso)
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = "Head"
	var hm: SphereMesh = SphereMesh.new()
	hm.radius = 0.23
	hm.height = 0.46
	head.mesh = hm
	head.material_override = skin
	head.position = Vector3(0, 1.68, 0)
	h.add_child(head)
	var visor: MeshInstance3D = MeshInstance3D.new()
	visor.name = "Visor"
	var vm: BoxMesh = BoxMesh.new()
	vm.size = Vector3(0.32, 0.08, 0.04)
	visor.mesh = vm
	var vmat: StandardMaterial3D = StandardMaterial3D.new()
	vmat.albedo_color = Color(0.25, 0.95, 1.0)
	vmat.emission_enabled = true
	vmat.emission = Color(0.25, 0.95, 1.0)
	vmat.emission_energy_multiplier = 2.5
	visor.material_override = vmat
	visor.position = Vector3(0, 1.70, -0.20)
	h.add_child(visor)
	for spec in [["LeftLeg", -0.17], ["RightLeg", 0.17]]:
		var sx: float = float(spec[1])
		var leg: MeshInstance3D = MeshInstance3D.new()
		leg.name = String(spec[0])
		var lm: CapsuleMesh = CapsuleMesh.new()
		lm.radius = 0.115
		lm.height = 0.86
		leg.mesh = lm
		leg.material_override = mat
		leg.position = Vector3(sx, 0.4, 0)
		h.add_child(leg)
		var boot: MeshInstance3D = MeshInstance3D.new()
		boot.name = "%sBoot" % String(spec[0])
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(0.18, 0.10, 0.36)
		boot.mesh = bm
		boot.material_override = mat
		boot.position = Vector3(sx, 0.05, -0.10)
		h.add_child(boot)
	for spec2 in [["LeftArm", -0.42, 11.0], ["RightArm", 0.42, -11.0]]:
		var sx2: float = float(spec2[1])
		var arm: MeshInstance3D = MeshInstance3D.new()
		arm.name = String(spec2[0])
		var am: CapsuleMesh = CapsuleMesh.new()
		am.radius = 0.09
		am.height = 0.78
		arm.mesh = am
		arm.material_override = mat
		arm.position = Vector3(sx2, 0.98, -0.02)
		arm.rotation_degrees.z = float(spec2[2])
		h.add_child(arm)
	var pack: MeshInstance3D = MeshInstance3D.new()
	pack.name = "LifeSupportPack"
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(0.34, 0.42, 0.16)
	pack.mesh = pm
	pack.material_override = mat
	pack.position = Vector3(0, 1.04, 0.23)
	h.add_child(pack)
	return h

func _try_load_meshy_humanoid(procedural_node: Node3D, glb_basename: String, node_name: String) -> void:
	# Generic helper: load a rigged Meshy humanoid GLB, reparent it under the
	# procedural node (which stays in the tree for its Label3D and metadata),
	# hide the procedural VisualInstance3D children, and play Idle animation.
	if not Game.MESHY_VISUAL_UPGRADE_ENABLED:
		return
	var path: String = "res://assets/models/meshy_visual_upgrade/%s.repacked.glb" % glb_basename
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("[meshy] %s: GLB missing or failed to import — keeping procedural" % path)
		return
	var glb_root: Node = packed.instantiate()
	if glb_root == null:
		push_warning("[meshy] %s: GLB instantiate() returned null — keeping procedural" % path)
		return
	var rig: Node3D = Node3D.new()
	rig.name = node_name
	# Meshy rigged humanoids come out in centimeters; scale down by 100x.
	rig.scale = Vector3(0.01, 0.01, 0.01)
	# Add the rig to the tree BEFORE setting global_transform so it resolves
	# inside the scene tree (avoids y=-500 off-screen parenting).
	procedural_node.add_child(rig)
	var stack: Array = [glb_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		# Clear owner before add_child to avoid editor/scene-ownership warnings.
		n.owner = null
		rig.add_child(n)
		for c in n.get_children():
			stack.push_back(c)
	# Match the procedural node's world transform.
	rig.global_transform = procedural_node.global_transform
	# Hide the procedural visual children so only the Meshy mesh is visible.
	for c in procedural_node.get_children():
		if c is VisualInstance3D and c != rig:
			(c as VisualInstance3D).visible = false
	# Retarget AnimationPlayer for the new scene root.
	var ap: AnimationPlayer = rig.get_node_or_null("AnimationPlayer")
	if ap != null:
		var lib: PackedStringArray = ap.get_animation_list()
		var chosen: String = ""
		var preferred: Array[String] = ["Idle", "Walking_Woman", "clip0"]
		for name in preferred:
			if lib.has(name):
				chosen = name
				break
		if chosen == "" and lib.size() > 0:
			chosen = lib[0]
		if chosen != "":
			var anim: Animation = ap.get_animation(chosen)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			var arm_node: Node = rig.get_node_or_null("Armature")
			if arm_node != null:
				var new_root: NodePath = rig.get_path_to(arm_node)
				# Only retarget when the root_node actually changes to stop editor spam.
				if ap.root_node != new_root:
					ap.root_node = new_root
			# Stop any existing playback before starting to avoid track-conflict warnings.
			ap.stop()
			ap.play(chosen)

func _try_load_meshy_captain() -> void:
	_try_load_meshy_humanoid(captain, String(Game.MESHY_CAPTAIN_GLB), "CrewCaptainMeshy")

func build(p_rng: RandomNumberGenerator) -> void:
	rng = p_rng
	_room_container = Node3D.new()
	_room_container.name = "RoomGeometry"
	add_child(_room_container)
	_crew_container = Node3D.new()
	_crew_container.name = "CrewContainer"
	add_child(_crew_container)
	captain = _build_humanoid(Color(0.4, 1.0, 0.6))
	captain.scale = Vector3(1.35, 1.35, 1.35)
	captain.position = Vector3(float(ROOM_CENTERS[0]), 0, 6)
	add_child(captain)
	_try_load_meshy_captain()
	var beacon: MeshInstance3D = MeshInstance3D.new()
	var bm: SphereMesh = SphereMesh.new()
	bm.radius = 0.12
	bm.height = 0.24
	beacon.mesh = bm
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.emission_enabled = true
	bmat.emission = Color(0.4, 1.0, 0.6)
	bmat.emission_energy_multiplier = 3.0
	bmat.albedo_color = Color(0.4, 1.0, 0.6)
	beacon.material_override = bmat
	beacon.position = Vector3(0, 2.0, 0)
	captain.add_child(beacon)
	camera = Camera3D.new()
	camera.position = Vector3(0, 6, 13)
	camera.rotation_degrees = Vector3(-19, 0, 0)
	camera.fov = 58.0
	add_child(camera)
	_build_all_rooms()
	_update_camera()

func _build_all_rooms() -> void:
	# Build every room's geometry once, contiguously along X, then populate all rosters.
	_clear_deck()
	for idx in range(ROOM_NAMES.size()):
		_build_room_geometry(idx)
	refresh_roster()

func _update_camera() -> void:
	# First-person: camera at the captain's eyes, oriented by yaw (body) + pitch (look).
	# Overhead: the original chase angle, now following the captain across the seamless deck.
	if camera == null or captain == null:
		return
	if first_person:
		camera.position = captain.position + Vector3(0, EYE_HEIGHT, 0)
		camera.rotation = Vector3(_cam_pitch, captain.rotation.y, 0)
		camera.fov = 72.0
	else:
		camera.position = Vector3(captain.position.x, 6, captain.position.z + 13)
		camera.rotation_degrees = Vector3(-19, 0, 0)
		camera.fov = 58.0

func _clear_deck() -> void:
	for c in _room_container.get_children():
		c.queue_free()
	for c in _crew_container.get_children():
		c.queue_free()
	crew_nodes.clear()
	_nearest_idx = -1
	_follow_count = 0

func _build_room_geometry(idx: int) -> void:
	var cx: float = float(ROOM_CENTERS[idx])
	var hw: float = ROOM_W * 0.5
	var hd: float = ROOM_D * 0.5
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	var fm: BoxMesh = BoxMesh.new()
	fm.size = Vector3(ROOM_W, 0.4, ROOM_D)
	floor_mi.mesh = fm
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	var floor_colors: Array = [
		Color(0.18, 0.24, 0.32),
		Color(0.28, 0.22, 0.16),
		Color(0.26, 0.16, 0.16),
	]
	fmat.albedo_color = Color(floor_colors[idx])
	fmat.metallic = 0.3
	fmat.roughness = 0.6
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(cx, -0.2, 0)
	_room_container.add_child(floor_mi)

	var wall_colors: Array = [
		Color(0.22, 0.32, 0.42),
		Color(0.38, 0.28, 0.18),
		Color(0.38, 0.18, 0.18),
	]
	var wcol: Color = Color(wall_colors[idx])
	var wmat: StandardMaterial3D = StandardMaterial3D.new()
	wmat.albedo_color = wcol
	wmat.metallic = 0.4
	wmat.roughness = 0.5

	for zpos in [-hd, hd]:
		var wmi: MeshInstance3D = MeshInstance3D.new()
		var wbm: BoxMesh = BoxMesh.new()
		wbm.size = Vector3(ROOM_W, 4, 0.4)
		wmi.mesh = wbm
		wmi.material_override = wmat
		wmi.position = Vector3(cx, 1.8, zpos)
		_room_container.add_child(wmi)

	var is_leftmost: bool = idx == 0
	var is_rightmost: bool = idx == ROOM_NAMES.size() - 1
	if is_leftmost:
		var wmi: MeshInstance3D = MeshInstance3D.new()
		var wbm: BoxMesh = BoxMesh.new()
		wbm.size = Vector3(0.4, 4, ROOM_D)
		wmi.mesh = wbm
		wmi.material_override = wmat
		wmi.position = Vector3(cx - hw, 1.8, 0)
		_room_container.add_child(wmi)
	else:
		var door_gap: float = 1.6
		var side_h: float = (ROOM_D - door_gap) * 0.5
		var df1: MeshInstance3D = MeshInstance3D.new()
		var dfm1: BoxMesh = BoxMesh.new()
		dfm1.size = Vector3(0.4, 4, side_h)
		df1.mesh = dfm1
		df1.material_override = wmat
		df1.position = Vector3(cx - hw, 1.8, -(hd + side_h) * 0.5)
		_room_container.add_child(df1)
		var df2: MeshInstance3D = MeshInstance3D.new()
		var dfm2: BoxMesh = BoxMesh.new()
		dfm2.size = Vector3(0.4, 4, side_h)
		df2.mesh = dfm2
		df2.material_override = wmat
		df2.position = Vector3(cx - hw, 1.8, (hd + side_h) * 0.5)
		_room_container.add_child(df2)

	if is_rightmost:
		var wmi: MeshInstance3D = MeshInstance3D.new()
		var wbm: BoxMesh = BoxMesh.new()
		wbm.size = Vector3(0.4, 4, ROOM_D)
		wmi.mesh = wbm
		wmi.material_override = wmat
		wmi.position = Vector3(cx + hw, 1.8, 0)
		_room_container.add_child(wmi)
	else:
		var door_gap: float = 1.6
		var side_h: float = (ROOM_D - door_gap) * 0.5
		var df1: MeshInstance3D = MeshInstance3D.new()
		var dfm1: BoxMesh = BoxMesh.new()
		dfm1.size = Vector3(0.4, 4, side_h)
		df1.mesh = dfm1
		df1.material_override = wmat
		df1.position = Vector3(cx + hw, 1.8, -(hd + side_h) * 0.5)
		_room_container.add_child(df1)
		var df2: MeshInstance3D = MeshInstance3D.new()
		var dfm2: BoxMesh = BoxMesh.new()
		dfm2.size = Vector3(0.4, 4, side_h)
		df2.mesh = dfm2
		df2.material_override = wmat
		df2.position = Vector3(cx + hw, 1.8, (hd + side_h) * 0.5)
		_room_container.add_child(df2)

	var gmat: StandardMaterial3D = StandardMaterial3D.new()
	gmat.emission_enabled = true
	gmat.emission_energy_multiplier = 1.2
	match idx:
		0:
			gmat.albedo_color = Color(0.1, 0.3, 0.4)
			gmat.emission = Color(0.2, 0.8, 1.0)
			for xoff in [-3, -1, 1, 3]:
				var con: MeshInstance3D = MeshInstance3D.new()
				var cbm: BoxMesh = BoxMesh.new()
				cbm.size = Vector3(1.4, 0.8, 0.8)
				con.mesh = cbm
				con.material_override = gmat
				con.position = Vector3(cx + xoff, 0.4, -hd + 1.0)
				_room_container.add_child(con)
				var con2: MeshInstance3D = MeshInstance3D.new()
				var cbm2: BoxMesh = BoxMesh.new()
				cbm2.size = Vector3(1.4, 0.8, 0.8)
				con2.mesh = cbm2
				con2.material_override = gmat
				con2.position = Vector3(cx + xoff, 0.4, hd - 1.0)
				_room_container.add_child(con2)
		1:
			gmat.albedo_color = Color(0.3, 0.25, 0.15)
			gmat.emission = Color(0.3, 0.2, 0.1)
			for xoff in [-3, 3]:
				var bunk: MeshInstance3D = MeshInstance3D.new()
				var bbm: BoxMesh = BoxMesh.new()
				bbm.size = Vector3(2.0, 0.6, 0.8)
				bunk.mesh = bbm
				bunk.material_override = gmat
				bunk.position = Vector3(cx + xoff, 0.3, -hd + 2.0)
				_room_container.add_child(bunk)
				var bunk2: MeshInstance3D = MeshInstance3D.new()
				var bbm2: BoxMesh = BoxMesh.new()
				bbm2.size = Vector3(2.0, 0.6, 0.8)
				bunk2.mesh = bbm2
				bunk2.material_override = gmat
				bunk2.position = Vector3(cx + xoff, 1.2, -hd + 2.0)
				_room_container.add_child(bunk2)
		2:
			gmat.albedo_color = Color(0.4, 0.15, 0.15)
			gmat.emission = Color(0.6, 0.2, 0.2)
			for xoff in [-3, 3]:
				for zoff in [-4, 0, 4]:
					var rack: MeshInstance3D = MeshInstance3D.new()
					var rbm: BoxMesh = BoxMesh.new()
					rbm.size = Vector3(0.5, 2.4, 0.5)
					rack.mesh = rbm
					rack.material_override = gmat
					rack.position = Vector3(cx + xoff, 1.2, zoff)
					_room_container.add_child(rack)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, -30, 0)
	sun.light_energy = 2.5
	sun.light_color = Color(1.0, 0.95, 0.85, 1.0)
	_room_container.add_child(sun)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.position = Vector3(cx, 3.5, 0)
	lamp.omni_range = 22
	lamp.light_energy = 3.0
	lamp.light_color = Color(0.9, 0.92, 1.0, 1.0)
	_room_container.add_child(lamp)
	# Fill light from the opposite side to avoid harsh shadows on humanoids.
	var fill: OmniLight3D = OmniLight3D.new()
	fill.position = Vector3(cx, 2.5, -6)
	fill.omni_range = 20
	fill.light_energy = 1.5
	fill.light_color = Color(0.85, 0.9, 1.0, 1.0)
	_room_container.add_child(fill)
	# Ambient environment is handled by the main scene's WorldEnvironment swap
	# in _set_deck_mode() — no local WorldEnvironment needed.

func refresh_roster() -> void:
	# Populate every room at once (the deck is seamless), distributing crew/marines by role:
	# Bridge -> pilots/engineers, Crew Quarters -> gunners, Marine Barracks -> marines.
	for c in crew_nodes:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	crew_nodes.clear()
	var avail: Array = Game.available_crew()
	# Bridge (room 0): pilots + engineers (fallback to all crew so it never sits empty).
	var bridge_crew: Array = []
	for c in avail:
		var role: String = String(c.get("role", ""))
		if role == "pilot" or role == "engineer":
			bridge_crew.append(c)
	if bridge_crew.is_empty():
		bridge_crew = avail.duplicate()
	var bt: int = max(1, bridge_crew.size())
	for i in range(bridge_crew.size()):
		_spawn_crew_detail(bridge_crew[i], i, bt, 0)
	# Crew Quarters (room 1): gunners.
	var quarters_crew: Array = []
	for c in avail:
		if String(c.get("role", "")) == "gunner":
			quarters_crew.append(c)
	var qt: int = max(1, quarters_crew.size())
	for i in range(quarters_crew.size()):
		_spawn_crew_detail(quarters_crew[i], i, qt, 1)
	# Marine Barracks (room 2): marines.
	var marines: Array = Game.available_marines()
	var mt: int = max(1, marines.size())
	for i in range(marines.size()):
		_spawn_crew_marine_named(marines[i], i, mt, 2)

func _spawn_crew_detail(crew_dict: Dictionary, idx: int, total: int, room_idx: int) -> void:
	var role: String = String(crew_dict.get("role", ""))
	var col: Color = Color(0.42, 0.72, 1.0)
	match role:
		"engineer": col = Color(0.3, 0.85, 0.4)
		"gunner": col = Color(1.0, 0.55, 0.15)
	var hh: Node3D = _build_humanoid(col)
	hh.scale = Vector3(1.28, 1.28, 1.28)
	var cx: float = float(ROOM_CENTERS[room_idx])
	var ang: float = float(idx) / float(total) * TAU
	var home: Vector3 = Vector3(cx + sin(ang) * 3.0, 0, cos(ang) * 4.0)
	hh.position = home
	_crew_container.add_child(hh)
	var label: Label3D = Label3D.new()
	var morale: int = int(round(float(crew_dict.get("morale", 1.0)) * 100.0))
	label.text = "%s [%s] S%d M%d%%" % [String(crew_dict.get("name", "?")), Game.ROLE_ABBR.get(role, "?"), int(crew_dict.get("skill", 1)), morale]
	label.font_size = 48
	label.pixel_size = 0.01
	label.no_depth_test = true
	label.position = Vector3(0, 2.4, 0)
	label.modulate = Color(1, 1, 1)
	hh.add_child(label)
	_try_load_meshy_humanoid(hh, String(Game.MESHY_CREW_GLB), "CrewMeshy")
	crew_nodes.append({
		"node": hh,
		"name": String(crew_dict.get("name", "Crew")),
		"role": role,
		"following": false,
		"home": home,
	})

func _spawn_crew_marine_named(marine_dict: Dictionary, idx: int, total: int, room_idx: int) -> void:
	var col: Color = Color(1.0, 0.5, 0.35)
	var hh: Node3D = _build_humanoid(col)
	hh.scale = Vector3(1.28, 1.28, 1.28)
	var cx: float = float(ROOM_CENTERS[room_idx])
	var ang: float = float(idx) / float(total) * TAU
	var home: Vector3 = Vector3(cx + sin(ang) * 3.0, 0, cos(ang) * 4.0)
	hh.position = home
	_crew_container.add_child(hh)
	var mname: String = String(marine_dict.get("name", "Marine"))
	var skill: int = int(marine_dict.get("skill", 1))
	var wounds: int = int(marine_dict.get("wounds", 0))
	var morale: int = int(round(float(marine_dict.get("morale", 1.0)) * 100.0))
	var label: Label3D = Label3D.new()
	if wounds > 0:
		label.text = "%s [MAR] S%d W%d M%d%%" % [mname, skill, wounds, morale]
	else:
		label.text = "%s [MAR] S%d M%d%%" % [mname, skill, morale]
	label.font_size = 48
	label.pixel_size = 0.01
	label.no_depth_test = true
	label.position = Vector3(0, 2.4, 0)
	# Tint by injury severity so wounded marines read at a glance on the crew deck.
	var tint: Color = Color(1, 1, 1)
	match wounds:
		1: tint = Color(1, 0.9, 0.3)
		2: tint = Color(1, 0.6, 0.2)
		3: tint = Color(1, 0.3, 0.2)
	label.modulate = tint
	hh.add_child(label)
	_try_load_meshy_humanoid(hh, String(Game.MESHY_MARINE_GLB), "MarineMeshy")
	crew_nodes.append({
		"node": hh,
		"name": mname,
		"role": "marine",
		"following": false,
		"home": home,
	})

func set_ship_list(owned_ships: Array) -> void:
	ship_list = owned_ships.duplicate()
	if current_ship_index >= ship_list.size():
		current_ship_index = 0

func cycle_ship() -> void:
	if ship_list.size() <= 1:
		return
	current_ship_index = (current_ship_index + 1) % ship_list.size()
	current_room_index = 0
	refresh_roster()
	captain.position = Vector3(float(ROOM_CENTERS[0]), 0, 6)
	_update_camera()

func goto_room(idx: int) -> void:
	if idx < 0 or idx >= ROOM_NAMES.size():
		return
	current_room_index = idx
	captain.position = Vector3(float(ROOM_CENTERS[idx]), 0, 6)
	_update_camera()

func set_first_person(on: bool) -> void:
	first_person = on
	_cam_pitch = 0.0
	# Hide the captain's own body in first-person so the camera isn't inside the mesh.
	if captain != null:
		captain.visible = not on
	_update_camera()

func look(mouse_delta: Vector2) -> void:
	# Mouse-look (first-person only): horizontal turns the body, vertical pitches the view.
	if not first_person or captain == null:
		return
	if mouse_delta == Vector2.ZERO:
		return
	captain.rotation.y -= mouse_delta.x * LOOK_SENS
	_cam_pitch = clamp(_cam_pitch - mouse_delta.y * LOOK_SENS, -1.45, 1.45)
	_update_camera()

func current_room_name() -> String:
	return String(ROOM_NAMES[current_room_index % ROOM_NAMES.size()])

func current_ship_label() -> String:
	if ship_list.is_empty():
		return "Corvette [Flagship]"
	var sd: Dictionary = ship_list[current_ship_index % ship_list.size()]
	var cls: String = String(sd.get("class", "Corvette"))
	var nm: String = String(sd.get("name", "Flagship"))
	return "%s [%s]" % [cls.capitalize(), nm]

func set_active(a: bool) -> void:
	active = a
	visible = a
	if captain != null:
		captain.visible = not (a and first_person)
	if a:
		_update_camera()
		if camera:
			camera.current = true

func process_deck(delta: float, input_vec: Vector2, follow_pressed: bool) -> void:
	if not active or captain == null:
		return
	# Build the world-space move vector. In first-person WASD is relative to where the
	# captain faces (forward/strafe); in overhead it stays axis-aligned to the screen.
	var move: Vector3
	if first_person:
		var b: Basis = captain.global_transform.basis
		var fwd: Vector3 = -b.z       # captain forward (-Z)
		var right: Vector3 = b.x
		move = (right * input_vec.x - fwd * input_vec.y) * move_speed * delta
	else:
		move = Vector3(input_vec.x, 0, input_vec.y) * move_speed * delta

	var pos: Vector3 = captain.position
	var new_pos: Vector3 = pos + move
	# Seamless deck bounds: the three rooms form one hall spanning X [-15,15], Z [-9,9].
	var hd: float = ROOM_D * 0.5
	var min_x: float = float(ROOM_CENTERS[0]) - ROOM_W * 0.5
	var max_x: float = float(ROOM_CENTERS[ROOM_NAMES.size() - 1]) + ROOM_W * 0.5
	new_pos.z = clamp(new_pos.z, -hd + BODY_R, hd - BODY_R)
	# Inter-room walls block movement except through the central doorway gap.
	for bx_v in ROOM_BOUNDARIES:
		var bx: float = float(bx_v)
		var crossing: bool = (pos.x - bx) * (new_pos.x - bx) < 0.0
		if crossing and abs(new_pos.z) > DOOR_HALF:
			new_pos.x = bx - BODY_R if pos.x < bx else bx + BODY_R
	new_pos.x = clamp(new_pos.x, min_x + BODY_R, max_x - BODY_R)
	captain.position = new_pos
	# Track which room the captain is in (HUD label only — no rebuild).
	current_room_index = clampi(int(round((new_pos.x - float(ROOM_CENTERS[0])) / ROOM_W)), 0, ROOM_NAMES.size() - 1)
	# In overhead the body turns to face travel; in first-person the mouse owns the heading.
	if not first_person and move.length() > 0.01:
		captain.rotation.y = atan2(move.x, move.z)
	_update_camera()
	_nearest_idx = -1
	var best: float = 3.0
	for i in range(crew_nodes.size()):
		var c: Dictionary = crew_nodes[i]
		if not is_instance_valid(c["node"]):
			continue
		var d: float = c["node"].position.distance_to(captain.position)
		if d < best:
			best = d
			_nearest_idx = i
	if follow_pressed and _nearest_idx >= 0:
		crew_nodes[_nearest_idx]["following"] = not crew_nodes[_nearest_idx]["following"]
	_follow_count = 0
	for i in range(crew_nodes.size()):
		var c2: Dictionary = crew_nodes[i]
		if not is_instance_valid(c2["node"]):
			continue
		var node: Node3D = c2["node"]
		if c2["following"]:
			_follow_count += 1
			var offset: Vector3 = Vector3(sin(float(i)) * 1.4, 0, 1.8 + float(i) * 0.5)
			var goal: Vector3 = captain.position + offset
			node.position = node.position.lerp(goal, clamp(delta * 3.0, 0.0, 1.0))
			var dirv: Vector3 = (captain.position - node.position)
			if dirv.length() > 0.05:
				node.rotation.y = atan2(dirv.x, dirv.z)
		else:
			node.position = node.position.lerp(c2["home"], clamp(delta * 1.0, 0.0, 1.0))

func status() -> Dictionary:
	var nearest: String = ""
	var nearest_following: bool = false
	if _nearest_idx >= 0 and _nearest_idx < crew_nodes.size():
		nearest = String(crew_nodes[_nearest_idx]["name"])
		nearest_following = bool(crew_nodes[_nearest_idx]["following"])
	return {
		"nearest": nearest,
		"nearest_following": nearest_following,
		"follow_count": _follow_count,
		"crew_total": crew_nodes.size(),
	}
