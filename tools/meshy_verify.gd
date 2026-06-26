extends SceneTree
# tools/meshy_verify.gd — runs under `godot --headless --path . -s tools/meshy_verify.gd`
# Inspects each repacked GLB under res://assets/models/meshy_visual_upgrade/ and
# prints a one-line summary per asset: triangle count, AABB, embedded texture
# count, (rigged) skeleton bone count. Exits non-zero if any required field
# is missing or out of bounds.
#
# Mirrored by tools/meshy_verify.py (the Python wrapper that invokes Godot
# headlessly and parses the per-asset lines).

const ROOT := "res://assets/models/meshy_visual_upgrade/"

# Required asset basenames. Crew captain is rigged; the others are static.
const STATIC_ASSETS := ["player_corvette", "capital_ship", "friendly_station", "hostile_fighter"]
const RIGGED_ASSETS := ["crew_captain"]
const ALL_ASSETS := STATIC_ASSETS + RIGGED_ASSETS

# Hard ceilings — keep these loose enough to allow future regen without false fails.
const MAX_TRIANGLES := 30000
const MIN_TEXTURES := 1

var failed: bool = false

func _reset_per_asset() -> void:
	# SceneTree-level 'failed' is intentionally latched across all assets
	# so MESHY_VERIFY_OVERALL reflects the whole run. Per-asset verdicts use
	# a separate local check via the captured errors list.
	pass

func _fail(msg: String, errors: Array) -> void:
	push_error(msg)
	errors.append(msg)

func _classify_root(node: Node) -> String:
	# Meshy GLBs instantiate as a Node3D whose direct children are MeshInstance3D
	# (static) or a Skeleton3D (rigged). Distinguish so the triangle-count
	# walk uses MeshInstance3D for statics and skips Skeleton3D bones for rigs.
	# Recurse into child nodes because some GLBs (e.g. the merged rig+anim
	# captain) wrap the skeleton under an intermediate Node3D ("Armature").
	if node == null:
		return "empty"
	var has_skel: bool = false
	var has_mesh: bool = false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			has_skel = true
		if n is MeshInstance3D:
			has_mesh = true
		for c in n.get_children():
			stack.push_back(c)
	if has_skel:
		return "rigged"
	if has_mesh:
		return "static"
	return "unknown"

func _count_triangles(root: Node) -> int:
	# Sum of (mesh.get_faces().size() / 3) for every MeshInstance3D. Skinned
	# meshes report surface count via mesh.get_faces() (ArrayMesh surfaces).
	var total: int = 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var faces: PackedVector3Array = n.mesh.get_faces()
			total += faces.size() / 3
		for c in n.get_children():
			stack.push_back(c)
	return total

func _count_textures(node: Node) -> int:
	# Walk MeshInstance3D surface materials and count unique textures. Meshy
	# outputs StandardMaterial3D-or-glTF-PBR materials with albedo + normal +
	# metallic/roughness typically embedded as separate images.
	var seen: Dictionary = {}
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var surf_count: int = n.mesh.get_surface_count()
			for i in range(surf_count):
				var mat: Material = n.get_active_material(i)
				if mat == null:
					mat = n.mesh.surface_get_material(i)
				if mat == null:
					continue
				# Walk every property that might be a Texture2D.
				var prop_names: PackedStringArray = mat.get_property_list().map(
					func(p): return String(p.name)
				) if mat.has_method("get_property_list") else PackedStringArray()
				for pn in prop_names:
					var v: Variant = mat.get(pn)
					if v is Texture2D:
						var path: String = v.resource_path
						seen[path] = true
		for c in n.get_children():
			stack.push_back(c)
	return seen.size()

func _count_bones(root: Node) -> int:
	# Sum Skeleton3D.get_bone_count() for any skeleton in the tree. Rigged GLBs
	# normally have exactly one root Skeleton3D.
	var total: int = 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			total += n.get_bone_count()
		for c in n.get_children():
			stack.push_back(c)
	return total

func _aabb(root: Node) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var nb: AABB = n.get_aabb()
			if first:
				box = nb
				first = false
			else:
				box = box.merge(nb)
		for c in n.get_children():
			stack.push_back(c)
	return box

func _check(asset_id: String) -> void:
	var path: String = ROOT + asset_id + ".repacked.glb"
	var errors: Array = []
	var packed: PackedScene = load(path)
	if packed == null:
		_fail("%s: load() returned null — Godot failed to import the GLB" % path, errors)
		failed = true
		print("MESHY_VERIFY %s status=FAIL reason=load_failed" % asset_id)
		return
	var inst: Node = packed.instantiate()
	if inst == null:
		_fail("%s: instantiate() returned null" % path, errors)
		failed = true
		print("MESHY_VERIFY %s status=FAIL reason=instantiate_failed" % asset_id)
		return
	root.add_child(inst)
	await process_frame
	var kind: String = _classify_root(inst)
	var tris: int = _count_triangles(inst)
	var tex: int = _count_textures(inst)
	var box: AABB = _aabb(inst)
	var aabb_str: String = "min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)" % [
		box.position.x, box.position.y, box.position.z,
		box.position.x + box.size.x, box.position.y + box.size.y, box.position.z + box.size.z,
	]
	var extra: String = ""
	if asset_id in RIGGED_ASSETS:
		var bones: int = _count_bones(inst)
		extra = " bones=%d" % bones
		if kind != "rigged":
			_fail("%s: classified as '%s' but expected 'rigged'" % [asset_id, kind], errors)
		if bones < 5:
			_fail("%s: only %d bones (expected >= 5 for humanoid)" % [asset_id, bones], errors)
	else:
		if kind != "static":
			_fail("%s: classified as '%s' but expected 'static'" % [asset_id, kind], errors)
	if tris > MAX_TRIANGLES:
		_fail("%s: triangle count %d exceeds budget %d" % [asset_id, tris, MAX_TRIANGLES], errors)
	if tex < MIN_TEXTURES:
		_fail("%s: texture count %d below minimum %d (GLB likely missing embedded textures)" % [asset_id, tex, MIN_TEXTURES], errors)
	var asset_ok: bool = errors.is_empty()
	if not asset_ok:
		failed = true
	print("MESHY_VERIFY %s kind=%s triangles=%d textures=%d aabb=%s%s status=%s" % [
		asset_id, kind, tris, tex, aabb_str, extra,
		("OK" if asset_ok else "FAIL"),
	])
	inst.queue_free()

func _initialize() -> void:
	for a in ALL_ASSETS:
		_check(a)
	if failed:
		print("MESHY_VERIFY_OVERALL=FAIL")
		quit(1)
		return
	print("MESHY_VERIFY_OVERALL=OK")
	quit(0)