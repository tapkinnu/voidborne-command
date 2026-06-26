extends SceneTree
# tools/visual_upgrade_screenshot.gd — runs under
#   xvfb-run -a godot --path . --script tools/visual_upgrade_screenshot.gd
# Captures a single image showing the 5 Meshy-swapped hero entities:
#   player corvette, capital ship, friendly station, hostile fighter, captain.
# Saves to artifacts/visual_upgrade.png and exits.
#
# Strategy: load the real main.tscn so we get the canonical player + battle
# spawn (which already picks up the Meshy corvette swap from scripts/ship.gd).
# Then we spawn one extra capital + one extra station + one extra enemy
# fighter + one Meshy captain GLB positioned so they all appear in frame.
# Force a clean chase camera; wait a few frames for materials/shaders to
# settle; render to viewport; save PNG.

const OUTPUT_PNG := "res://artifacts/visual_upgrade.png"

var _capture_node: Node
var _image: Image

func _wait_frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _add_extra_ship(parent: Node, klass: String, faction: String, name: String, pos: Vector3) -> Node:
	# Use the same ShipScript path main.gd uses so the Meshy swap fires.
	var ShipScript: GDScript = load("res://scripts/ship.gd")
	var s: Node3D = ShipScript.new()
	s.name = "Extra_%s_%s" % [faction, name]
	parent.add_child(s)
	s.setup(klass, faction, name)
	s.global_position = pos
	return s

func _add_meshy_captain_preview(parent: Node, pos: Vector3) -> void:
	# The captain only appears inside crew_deck.gd in normal play. For the
	# screenshot we want one visible in the world, so instantiate the GLB
	# directly at the desired world position. The Meshy rigged output is in
	# centimeters, so scale by 0.01 so the 1.8m-tall captain matches scale.
	var packed: PackedScene = load("res://assets/models/meshy_visual_upgrade/crew_captain.repacked.glb")
	if packed == null:
		push_warning("[visual_upgrade] crew_captain GLB missing — skipping captain preview")
		return
	var glb: Node = packed.instantiate()
	if glb == null:
		push_warning("[visual_upgrade] crew_captain instantiate() returned null")
		return
	glb.name = "PreviewCaptain"
	glb.scale = Vector3(0.01, 0.01, 0.01)
	# Reparent everything to a flat Node3D so scale applies uniformly.
	var flat: Node3D = Node3D.new()
	flat.name = "PreviewCaptain"
	var stack: Array = [glb]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		flat.add_child(n)
		n.owner = flat
		for c in n.get_children():
			stack.push_back(c)
	parent.add_child(flat)
	flat.global_position = pos
	# Meshy rigged meshes face -Z (glTF forward); rotate so the captain
	# faces the camera at +Z roughly.
	flat.rotation.y = deg_to_rad(180.0)

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		push_error("visual_upgrade: main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	# Disable autopilot combat so enemies don't drift into the framing during
	# the screenshot window. Also keep the player stationary and invulnerable
	# via the same flag the capture harness uses.
	main.set("VOIDBORNE_CAPTURE", true)
	if main.has_method("_build_battle"):
		main._build_battle()
	# Wait two frames so spawn / Meshy load / materials settle.
	await _wait_frames(3)

	# Spawn three extra hero-class entities positioned in frame alongside the
	# player corvette. Use a wide arc to avoid overlapping the existing battle
	# spawn from _build_system_battle (which is at pspawn=(0,4,80)).
	var player_pos: Vector3 = main.player.global_position if main.player != null else Vector3.ZERO
	# Capital to the right and slightly behind the player, so the long hull
	# reads in profile.
	_add_extra_ship(main, "capital", "hostile", "HeroCapital", player_pos + Vector3(28.0, -2.0, 14.0))
	# Station behind the capital, larger and further so it doesn't dominate.
	_add_extra_ship(main, "station", "neutral", "HeroStation", player_pos + Vector3(8.0, 0.0, 60.0))
	# Hostile fighter off the player's port side, smaller and angular.
	_add_extra_ship(main, "fighter", "hostile", "HeroFighter", player_pos + Vector3(-22.0, 3.0, -10.0))
	# Captain standing in front of the player corvette so the rigged GLB is
	# visible at the chase camera's eye height.
	_add_meshy_captain_preview(main, player_pos + Vector3(0.0, 0.0, -16.0))

	# Lock player position so nothing drifts mid-capture.
	if main.player != null:
		main.player.invulnerable = true
		main.player.throttle = 0.0
		main.player.boosting = false
		# Recenter camera without input jitter.
		main._update_camera(0.001, true)
		var cam: Camera3D = main.space_camera
		if cam != null:
			cam.current = true

	await _wait_frames(4)

	var cam: Camera3D = main.space_camera
	if cam == null:
		push_error("visual_upgrade: space_camera missing after _build_battle")
		quit(1)
		return

	var img: Image = cam.get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("visual_upgrade: viewport image is empty")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var out_abs: String = ProjectSettings.globalize_path(OUTPUT_PNG)
	var err: int = img.save_png(out_abs)
	if err != OK:
		push_error("visual_upgrade: save_png('%s') failed err=%d" % [out_abs, err])
		quit(1)
		return
	print("MESHY_SCREENSHOT saved=%s size=%dx%d" % [out_abs, img.get_width(), img.get_height()])
	quit(0)