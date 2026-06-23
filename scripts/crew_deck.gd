extends Node3D
# CrewDeck: walkable ship-interior view with procedural humanoid crew/marines.
# Captain (player avatar) can approach a crew member and order them to follow.
# No class_name. Toggled active by main.gd.

var active: bool = false
var camera: Camera3D
var captain: Node3D
var crew_nodes: Array = []      # Array of dicts {node, name, role, following, home}
var move_speed: float = 6.0
var rng: RandomNumberGenerator
var _nearest_idx: int = -1
var _follow_count: int = 0

func _build_humanoid(col: Color) -> Node3D:
	var h: Node3D = Node3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.1
	mat.roughness = 0.7
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.7, 0.6)
	# torso
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.name = "Torso"
	var tm: CapsuleMesh = CapsuleMesh.new()
	tm.radius = 0.32
	tm.height = 1.18
	torso.mesh = tm
	torso.material_override = mat
	torso.position = Vector3(0, 0.95, 0)
	h.add_child(torso)
	# head
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = "Head"
	var hm: SphereMesh = SphereMesh.new()
	hm.radius = 0.23
	hm.height = 0.46
	head.mesh = hm
	head.material_override = skin
	head.position = Vector3(0, 1.68, 0)
	h.add_child(head)
	# bright face visor so the humanoid reads as a character from the capture camera
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
	# legs
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
	# arms
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
	# small backpack/oxygen block gives the silhouette a readable front/back cue.
	var pack: MeshInstance3D = MeshInstance3D.new()
	pack.name = "LifeSupportPack"
	var pm: BoxMesh = BoxMesh.new()
	pm.size = Vector3(0.34, 0.42, 0.16)
	pack.mesh = pm
	pack.material_override = mat
	pack.position = Vector3(0, 1.04, 0.23)
	h.add_child(pack)
	return h

func build(p_rng: RandomNumberGenerator) -> void:
	rng = p_rng
	# Room: floor + walls + ceiling lights
	var floor_mi: MeshInstance3D = MeshInstance3D.new()
	var fm: BoxMesh = BoxMesh.new()
	fm.size = Vector3(30, 0.4, 22)
	floor_mi.mesh = fm
	var fmat: StandardMaterial3D = StandardMaterial3D.new()
	fmat.albedo_color = Color(0.12, 0.14, 0.18)
	fmat.metallic = 0.3
	fmat.roughness = 0.6
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(0, -0.2, 0)
	add_child(floor_mi)

	var wmat: StandardMaterial3D = StandardMaterial3D.new()
	wmat.albedo_color = Color(0.16, 0.2, 0.26)
	wmat.metallic = 0.4
	wmat.roughness = 0.5
	var walls := [
		[Vector3(30, 4, 0.4), Vector3(0, 1.8, -11)],
		[Vector3(30, 4, 0.4), Vector3(0, 1.8, 11)],
		[Vector3(0.4, 4, 22), Vector3(-15, 1.8, 0)],
		[Vector3(0.4, 4, 22), Vector3(15, 1.8, 0)],
	]
	for w in walls:
		var wmi: MeshInstance3D = MeshInstance3D.new()
		var wbm: BoxMesh = BoxMesh.new()
		wbm.size = w[0]
		wmi.mesh = wbm
		wmi.material_override = wmat
		wmi.position = w[1]
		add_child(wmi)

	# Console greebles for interior flavor
	var cmat: StandardMaterial3D = StandardMaterial3D.new()
	cmat.albedo_color = Color(0.1, 0.3, 0.4)
	cmat.emission_enabled = true
	cmat.emission = Color(0.2, 0.8, 1.0)
	cmat.emission_energy_multiplier = 1.2
	for cx in [-12, -6, 6, 12]:
		var con: MeshInstance3D = MeshInstance3D.new()
		var cbm: BoxMesh = BoxMesh.new()
		cbm.size = Vector3(1.6, 1.0, 0.8)
		con.mesh = cbm
		con.material_override = cmat
		con.position = Vector3(cx, 0.5, -10.0)
		add_child(con)

	# Lighting
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, -30, 0)
	sun.light_energy = 0.8
	add_child(sun)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.position = Vector3(0, 3.5, 0)
	lamp.omni_range = 24
	lamp.light_energy = 1.5
	add_child(lamp)

	# Captain avatar
	captain = _build_humanoid(Color(0.4, 1.0, 0.6))
	captain.scale = Vector3(1.35, 1.35, 1.35)
	captain.position = Vector3(0, 0, 6)
	add_child(captain)
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

	# Camera (angled third-person)
	camera = Camera3D.new()
	camera.position = Vector3(0, 6, 13)
	camera.rotation_degrees = Vector3(-19, 0, 0)
	camera.fov = 58.0
	add_child(camera)

	refresh_roster()

func refresh_roster() -> void:
	# Rebuild crew/marine humanoids from current Game pools (capped for visibility).
	for c in crew_nodes:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	crew_nodes.clear()
	var n_crew: int = clampi(Game.crew_pool, 0, 6)
	var n_mar: int = clampi(Game.marine_pool, 0, 6)
	var total: int = max(1, n_crew + n_mar)
	var idx: int = 0
	for i in range(n_crew):
		_spawn_crew("crew", idx, total)
		idx += 1
	for i in range(n_mar):
		_spawn_crew("marine", idx, total)
		idx += 1

func _spawn_crew(role: String, idx: int, total: int) -> void:
	var col: Color = Color(0.42, 0.72, 1.0) if role == "crew" else Color(1.0, 0.5, 0.35)
	var hh: Node3D = _build_humanoid(col)
	hh.scale = Vector3(1.28, 1.28, 1.28)
	var ang: float = float(idx) / float(total) * TAU
	var home: Vector3 = Vector3(sin(ang) * 7.0, 0, -2.0 + cos(ang) * 4.0)
	hh.position = home
	add_child(hh)
	crew_nodes.append({
		"node": hh,
		"name": Game.random_name(rng),
		"role": role,
		"following": false,
		"home": home,
	})

func set_active(a: bool) -> void:
	active = a
	visible = a
	if camera and a:
		camera.current = true

func process_deck(delta: float, input_vec: Vector2, follow_pressed: bool) -> void:
	if not active or captain == null:
		return
	# Move captain on XZ plane
	var move: Vector3 = Vector3(input_vec.x, 0, input_vec.y) * move_speed * delta
	captain.position += move
	captain.position.x = clamp(captain.position.x, -14, 14)
	captain.position.z = clamp(captain.position.z, -10, 10)
	if move.length() > 0.01:
		captain.rotation.y = atan2(move.x, move.z)

	# Find nearest crew
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

	# Update follow / idle motion
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
