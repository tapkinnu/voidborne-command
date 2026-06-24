extends SceneTree
# Regression test for the visual/audio fidelity pass: ship hull greebles, running lights,
# engine exhaust cones, an enriched starfield/nebula backdrop, and new audio triggers
# (ambient drone + weapon_overheat / hull_alarm / engine_hit). Loads the real main scene
# and inspects the procedurally built nodes — no key simulation.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

# Recursively count descendant MeshInstance3D nodes whose mesh matches a predicate.
func _count_meshes(node: Node, predicate: Callable) -> int:
	var n: int = 0
	if node is MeshInstance3D and node.mesh != null and predicate.call(node.mesh):
		n += 1
	for c in node.get_children():
		n += _count_meshes(c, predicate)
	return n

func _is_sphere(m: Mesh) -> bool:
	return m is SphereMesh

func _is_exhaust_cone(m: Mesh) -> bool:
	# A strongly tapered cylinder (narrow tip << wide base) is our exhaust plume.
	if not (m is CylinderMesh):
		return false
	var cm: CylinderMesh = m
	return cm.top_radius < cm.bottom_radius * 0.5

func _find_ship(main: Node, klass: String) -> Node:
	for s in main.ships:
		if is_instance_valid(s) and String(s.ship_class) == klass:
			return s
	return null

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var audio_node: Node = main.get("audio")
	if audio_node != null:
		audio_node.set("enabled", false)

	# --- Ships: greebles, running lights, exhaust cones ---
	var fighter: Node = _find_ship(main, "fighter")
	var capital: Node = _find_ship(main, "capital")
	if fighter == null:
		_fail("no fighter ship found")
	if capital == null:
		_fail("no capital ship found")

	if not failed:
		var fh: Node = fighter.get_node("Hull")
		if fh.get_child_count() <= 8:
			_fail("fighter Hull has too few children (%d, expected > 8) — greebles missing" % fh.get_child_count())
		var ch: Node = capital.get_node("Hull")
		if ch.get_child_count() <= 15:
			_fail("capital Hull has too few children (%d, expected > 15) — greebles missing" % ch.get_child_count())

	if not failed:
		var f_lights: int = _count_meshes(fighter.get_node("Hull"), _is_sphere)
		if f_lights < 2:
			_fail("fighter has %d running lights (expected >= 2)" % f_lights)
		var c_lights: int = _count_meshes(capital.get_node("Hull"), _is_sphere)
		if c_lights < 2:
			_fail("capital has %d running lights (expected >= 2)" % c_lights)

	if not failed:
		var f_ex: int = _count_meshes(fighter, _is_exhaust_cone)
		if f_ex < 1:
			_fail("fighter has %d exhaust cones (expected >= 1)" % f_ex)
		var c_ex: int = _count_meshes(capital, _is_exhaust_cone)
		if c_ex < 1:
			_fail("capital has %d exhaust cones (expected >= 1)" % c_ex)
		# tick_visuals should drive the exhaust scale without error.
		fighter.throttle = 1.0
		fighter.tick_visuals(0.1)

	# --- Audio: ambient + new SFX triggers declared ---
	if not failed:
		if audio_node == null:
			_fail("audio node missing on main")
		else:
			var streams: Dictionary = audio_node.get("_streams")
			for trig in ["ambient", "weapon_overheat", "hull_alarm", "engine_hit"]:
				if not streams.has(trig):
					_fail("audio is missing the '%s' trigger" % trig)

	# --- Starfield: >= 1500 instances ---
	if not failed:
		var mmi: MultiMeshInstance3D = null
		for c in main.get_children():
			if c is MultiMeshInstance3D:
				mmi = c
				break
		if mmi == null or mmi.multimesh == null:
			_fail("no starfield MultiMeshInstance3D found")
		elif mmi.multimesh.instance_count < 1500:
			_fail("starfield has %d instances (expected >= 1500)" % mmi.multimesh.instance_count)

	# --- Nebula: >= 3 large MeshInstance3D backdrop clouds ---
	if not failed:
		var neb_count: int = 0
		for c in main.get_children():
			if c is MeshInstance3D and c.mesh is SphereMesh and (c.mesh as SphereMesh).radius > 100.0:
				neb_count += 1
		if neb_count < 3:
			_fail("found %d large nebula clouds (expected >= 3)" % neb_count)

	if not failed:
		print("VISUAL_FIDELITY_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
