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

# Room system
var current_room_index: int = 0
var _room_container: Node3D
var _crew_container: Node3D
const ROOM_NAMES: Array = ["Bridge", "Crew Quarters", "Marine Barracks"]
const ROOM_W: float = 10.0
const ROOM_D: float = 18.0
const ROOM_CENTERS: Array = [-10.0, 0.0, 10.0]

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
	_build_current_room()

func _build_current_room() -> void:
	_clear_room()
	_build_room_geometry(current_room_index)
	refresh_roster()

func _clear_room() -> void:
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
		Color(0.10, 0.14, 0.20),
		Color(0.18, 0.15, 0.12),
		Color(0.16, 0.10, 0.10),
	]
	fmat.albedo_color = Color(floor_colors[idx])
	fmat.metallic = 0.3
	fmat.roughness = 0.6
	floor_mi.material_override = fmat
	floor_mi.position = Vector3(cx, -0.2, 0)
	_room_container.add_child(floor_mi)

	var wall_colors: Array = [
		Color(0.15, 0.22, 0.30),
		Color(0.30, 0.22, 0.14),
		Color(0.30, 0.14, 0.14),
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
	sun.light_energy = 0.8
	_room_container.add_child(sun)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.position = Vector3(cx, 3.5, 0)
	lamp.omni_range = 18
	lamp.light_energy = 1.5
	_room_container.add_child(lamp)

func refresh_roster() -> void:
	for c in crew_nodes:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	crew_nodes.clear()
	var avail: Array = Game.available_crew()
	var idx: int = 0
	var total: int = 0
	match current_room_index:
		0:
			var bridge_crew: Array = []
			for c in avail:
				var role: String = String(c.get("role", ""))
				if role == "pilot" or role == "engineer":
					bridge_crew.append(c)
			total = max(1, bridge_crew.size())
			for c in bridge_crew:
				_spawn_crew_detail(c, idx, total)
				idx += 1
			if bridge_crew.is_empty():
				for c in avail:
					_spawn_crew_detail(c, idx, total)
					idx += 1
		1:
			var quarters_crew: Array = []
			for c in avail:
				var role: String = String(c.get("role", ""))
				if role == "gunner":
					quarters_crew.append(c)
			if quarters_crew.is_empty():
				quarters_crew = avail.duplicate()
			total = max(1, quarters_crew.size())
			for c in quarters_crew:
				_spawn_crew_detail(c, idx, total)
				idx += 1
		2:
			var marines: Array = Game.available_marines()
			total = max(1, marines.size())
			var mi: int = 0
			for m in marines:
				_spawn_crew_marine_named(m, mi, total)
				mi += 1
			if marines.is_empty():
				# No available marines — show the crew instead so the room isn't empty.
				idx = 0
				total = max(1, avail.size())
				for c in avail:
					_spawn_crew_detail(c, idx, total)
					idx += 1

func _spawn_crew_detail(crew_dict: Dictionary, idx: int, total: int) -> void:
	var role: String = String(crew_dict.get("role", ""))
	var col: Color = Color(0.42, 0.72, 1.0)
	match role:
		"engineer": col = Color(0.3, 0.85, 0.4)
		"gunner": col = Color(1.0, 0.55, 0.15)
	var hh: Node3D = _build_humanoid(col)
	hh.scale = Vector3(1.28, 1.28, 1.28)
	var cx: float = float(ROOM_CENTERS[current_room_index])
	var ang: float = float(idx) / float(total) * TAU
	var home: Vector3 = Vector3(cx + sin(ang) * 3.0, 0, cos(ang) * 4.0)
	hh.position = home
	_crew_container.add_child(hh)
	var label: Label3D = Label3D.new()
	label.text = "%s [%s] S%d" % [String(crew_dict.get("name", "?")), Game.ROLE_ABBR.get(role, "?"), int(crew_dict.get("skill", 1))]
	label.font_size = 48
	label.pixel_size = 0.01
	label.no_depth_test = true
	label.position = Vector3(0, 2.4, 0)
	label.modulate = Color(1, 1, 1)
	hh.add_child(label)
	crew_nodes.append({
		"node": hh,
		"name": String(crew_dict.get("name", "Crew")),
		"role": role,
		"following": false,
		"home": home,
	})

func _spawn_crew_marine_named(marine_dict: Dictionary, idx: int, total: int) -> void:
	var col: Color = Color(1.0, 0.5, 0.35)
	var hh: Node3D = _build_humanoid(col)
	hh.scale = Vector3(1.28, 1.28, 1.28)
	var cx: float = float(ROOM_CENTERS[current_room_index])
	var ang: float = float(idx) / float(total) * TAU
	var home: Vector3 = Vector3(cx + sin(ang) * 3.0, 0, cos(ang) * 4.0)
	hh.position = home
	_crew_container.add_child(hh)
	var mname: String = String(marine_dict.get("name", "Marine"))
	var skill: int = int(marine_dict.get("skill", 1))
	var wounds: int = int(marine_dict.get("wounds", 0))
	var label: Label3D = Label3D.new()
	if wounds > 0:
		label.text = "%s [MAR] S%d W%d" % [mname, skill, wounds]
	else:
		label.text = "%s [MAR] S%d" % [mname, skill]
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
	_build_current_room()
	captain.position = Vector3(float(ROOM_CENTERS[0]), 0, 6)

func goto_room(idx: int) -> void:
	if idx < 0 or idx >= ROOM_NAMES.size():
		return
	if idx == current_room_index:
		return
	current_room_index = idx
	_build_current_room()
	captain.position = Vector3(float(ROOM_CENTERS[idx]), 0, 6)

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
	if camera and a:
		camera.current = true

func process_deck(delta: float, input_vec: Vector2, follow_pressed: bool) -> void:
	if not active or captain == null:
		return
	var cx: float = float(ROOM_CENTERS[current_room_index])
	var hw: float = ROOM_W * 0.5
	var hd: float = ROOM_D * 0.5
	var move: Vector3 = Vector3(input_vec.x, 0, input_vec.y) * move_speed * delta
	var new_pos: Vector3 = captain.position + move
	var room_changed: bool = false
	if current_room_index > 0 and new_pos.x < cx - hw:
		current_room_index -= 1
		new_pos.x = float(ROOM_CENTERS[current_room_index]) + hw - 0.5
		new_pos.z = clamp(new_pos.z, -hd, hd)
		room_changed = true
	elif current_room_index < ROOM_NAMES.size() - 1 and new_pos.x > cx + hw:
		current_room_index += 1
		new_pos.x = float(ROOM_CENTERS[current_room_index]) - hw + 0.5
		new_pos.z = clamp(new_pos.z, -hd, hd)
		room_changed = true
	else:
		new_pos.x = clamp(new_pos.x, cx - hw, cx + hw)
		new_pos.z = clamp(new_pos.z, -hd, hd)
	if room_changed:
		_build_current_room()
	captain.position = new_pos
	if move.length() > 0.01:
		captain.rotation.y = atan2(move.x, move.z)
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
