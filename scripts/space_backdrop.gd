extends RefCounted
# SpaceBackdrop: builders for the procedural, non-interactive space backdrop -- the
# WorldEnvironment + key/rim lights and the starfield (MultiMesh stars, nebula billboards,
# and the distant galaxy band).
#
# Extracted from main.gd to move ~120 lines of one-shot scene-construction out of the
# god-script. The builders attach their nodes to the supplied parent and return the handles
# main.gd still tracks (the WorldEnvironment for graphics-quality tweaks, the nebula meshes
# for the slow drift rotation in _process). main.gd keeps thin _build_environment /
# _build_stars forwarders so behaviour and the field set are unchanged.
#
# No class_name (avoids circular-import pitfalls); called via preload from main.gd.

# Build the environment + lights under `parent`. Returns the WorldEnvironment node.
static func build_environment(parent: Node) -> WorldEnvironment:
	var world_env: WorldEnvironment = WorldEnvironment.new()
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
	parent.add_child(world_env)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.9)
	parent.add_child(sun)

	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(30, 140, 0)
	rim.light_energy = 0.35
	rim.light_color = Color(0.5, 0.6, 1.0)
	parent.add_child(rim)
	return world_env

# Build the starfield, nebula clouds and galaxy band under `parent`, using `rng` for the
# deterministic scatter. Returns the array of nebula MeshInstance3Ds (main rotates these).
static func build_stars(parent: Node, rng: RandomNumberGenerator) -> Array:
	# Procedural starfield: a MultiMesh shell of tiny unshaded emissive points, plus a
	# couple of nebula billboards so the backdrop is never a flat black frame.
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var qm: QuadMesh = QuadMesh.new()
	qm.size = Vector2(2.2, 2.2)
	mm.mesh = qm
	var count: int = 1500
	var near_count: int = 65   # brighter, larger foreground stars (last `near_count` instances)
	mm.instance_count = count
	for i in range(count):
		var dir: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var pos: Vector3 = dir * rng.randf_range(800.0, 1200.0)
		var t: Transform3D = Transform3D(Basis(), pos)
		# Billboard-ish: face origin.
		t = t.looking_at(Vector3.ZERO, Vector3.UP)
		var is_near: bool = i >= count - near_count
		var s: float = rng.randf_range(2.0, 3.5) if is_near else rng.randf_range(0.4, 1.8)
		t = t.scaled_local(Vector3(s, s, s))
		mm.set_instance_transform(i, t)
		# Color-temperature variation: most white-blue, some yellow-orange, a few red.
		var b: float = rng.randf_range(0.5, 1.0)
		var roll: float = rng.randf()
		var tint: Color
		if roll < 0.18:
			tint = Color(b, b * 0.78, b * 0.55)          # yellow-orange
		elif roll < 0.26:
			tint = Color(b, b * 0.5, b * 0.42)           # red
		elif roll < 0.46:
			tint = Color(b * 0.75, b * 0.85, b)          # blue-white
		else:
			tint = Color(b, b, b * rng.randf_range(0.88, 1.0))  # white
		if is_near:
			tint = tint.lightened(0.15)
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
	parent.add_child(mmi)

	# Layered nebula clouds (large unshaded transparent spheres, different hues/positions).
	# Each [position, color, radius]. Returned so main can slow-drift rotate them.
	var nebula_nodes: Array = []
	var clouds: Array = [
		[Vector3(-320, 130, -430), Color(0.30, 0.10, 0.45, 0.11), 230.0],  # deep purple
		[Vector3(360, -90, -320), Color(0.08, 0.28, 0.40, 0.10), 210.0],   # teal
		[Vector3(120, 180, -520), Color(0.42, 0.22, 0.08, 0.09), 250.0],   # warm orange
		[Vector3(-150, -160, -300), Color(0.16, 0.10, 0.34, 0.08), 200.0], # dim violet
	]
	for nb in clouds:
		var neb: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		var nr: float = float(nb[2])
		sm.radius = nr
		sm.height = nr * 2.0
		neb.mesh = sm
		var nmat: StandardMaterial3D = StandardMaterial3D.new()
		nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		nmat.albedo_color = nb[1]
		nmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		neb.mesh.surface_set_material(0, nmat)
		neb.position = nb[0]
		parent.add_child(neb)
		nebula_nodes.append(neb)

	# Faint distant galaxy band: a large flattened sphere with a low-alpha milky tint.
	var galaxy: MeshInstance3D = MeshInstance3D.new()
	var gsm: SphereMesh = SphereMesh.new()
	gsm.radius = 600.0
	gsm.height = 1200.0
	galaxy.mesh = gsm
	var gmat: StandardMaterial3D = StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.55, 0.58, 0.70, 0.05)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	galaxy.mesh.surface_set_material(0, gmat)
	galaxy.position = Vector3(0, -120, -900)
	galaxy.scale = Vector3(1.0, 0.15, 1.0)
	galaxy.rotation.z = deg_to_rad(18.0)
	parent.add_child(galaxy)
	return nebula_nodes
