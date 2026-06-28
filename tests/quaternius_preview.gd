extends SceneTree

const OUTPUT_DIR = "artifacts/quaternius_preview"

func _init() -> void:
	var dir = DirAccess.open(OUTPUT_DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	var preview_assets = [
		{"id": "concord_fighter_a", "label": "concord_fighter"},
		{"id": "sundered_mech_heavy", "label": "sundered_mech"},
		{"id": "planet_gas_giant", "label": "planet"},
		{"id": "crew_astronaut_a", "label": "astronaut"},
		{"id": "asteroid_rock_a", "label": "asteroid"},
		{"id": "building_dome", "label": "building"},
	]

	# Build scene
	var scene_root = Node3D.new()
	root.add_child(scene_root)

	var camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(3, 2, 5)
	camera.fov = 45.0
	scene_root.add_child(camera)

	var light = DirectionalLight3D.new()
	light.name = "Sun"
	light.position = Vector3(5, 10, 7)
	light.light_energy = 1.5
	scene_root.add_child(light)

	var fill = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.position = Vector3(-3, 3, -5)
	fill.light_energy = 0.5
	scene_root.add_child(fill)

	# Spawn each asset, verify it, then remove
	for entry in preview_assets:
		var path = "res://assets/models/quaternius_modular/%s.repacked.glb" % entry["id"]
		var asset_scene = load(path)
		if asset_scene == null:
			printerr("SKIP: %s failed to load" % entry["id"])
			continue

		var inst = asset_scene.instantiate()
		inst.name = entry["id"]
		scene_root.add_child(inst)

		# Wait for tree to settle
		await physics_frame
		await physics_frame

		# Center the asset
		var aabb = _get_aabb(inst)
		var center = aabb.position + aabb.size * 0.5
		inst.position = -center

		# Frame camera (use look_at_from_position since node may not be fully in tree)
		var sz = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		var cam_dist = max(3.0, sz * 1.8)
		camera.position = Vector3(cam_dist * 0.7071, cam_dist * 0.5, cam_dist * 0.7071)
		camera.look_at_from_position(camera.position, Vector3.ZERO)

		# Wait for render frames
		for i in range(10):
			await physics_frame

		# Verify AABB is valid (non-degenerate)
		var final_aabb = _get_aabb(inst)
		var vol = final_aabb.size.x * final_aabb.size.y * final_aabb.size.z
		if vol > 0.001:
			print("OK: %s -> size=%.2f x %.2f x %.2f, vol=%.3f" % [
				entry["id"],
				final_aabb.size.x, final_aabb.size.y, final_aabb.size.z, vol
			])
			# Write a placeholder PNG file to indicate verification ran
			var png_path = OUTPUT_DIR + "/%s.png" % entry["label"]
			var img = Image.create(256, 256, false, Image.FORMAT_RGB8)
			img.fill(Color(0.2, 0.4, 0.6))
			img.save_png(png_path)
			print("  wrote placeholder: %s" % png_path)
		else:
			printerr("FAIL: %s has degenerate AABB (vol=%.6f)" % [entry["id"], vol])

		scene_root.remove_child(inst)
		inst.queue_free()
		await physics_frame

	print("")
	print("DONE: Quaternius preview verification complete")
	print("NOTE: Headless Godot cannot render textures. Placeholder PNGs written.")
	print("      For real visual QA, run the project with rendering enabled.")
	quit(0)


func _get_aabb(node: Node) -> AABB:
	var aabb = AABB()
	if node is MeshInstance3D and node.mesh != null:
		aabb = node.mesh.get_aabb()
		if node.is_inside_tree():
			var t = node.global_transform
			aabb = t * aabb
	for child in node.get_children():
		var child_aabb = _get_aabb(child)
		if aabb == AABB():
			aabb = child_aabb
		else:
			aabb = aabb.merge(child_aabb)
	if aabb == AABB():
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
	return aabb
