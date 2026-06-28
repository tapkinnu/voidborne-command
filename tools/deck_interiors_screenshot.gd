extends SceneTree
# tools/deck_interiors_screenshot.gd — runs under
#   xvfb-run -a godot --path . --script tools/deck_interiors_screenshot.gd
# Captures one crew-deck screenshot per ship class so the per-class interiors
# (card t_32c3321c) can be compared side by side. Saves
#   artifacts/screenshots/deck_<class>.png  for fighter..station
# and exits 0.

const CLASSES: Array = ["fighter", "corvette", "frigate", "capital", "station"]
const OUT_DIR: String = "res://artifacts/screenshots"

func _wait_frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		push_error("deck_screenshot: main.tscn failed to load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	root.add_child(main)
	await _wait_frames(3)

	var deck: Node = main.find_child("CrewDeck", true, false)
	if deck == null:
		push_error("deck_screenshot: CrewDeck not found")
		quit(1)
		return

	main.force_deck(true)
	await _wait_frames(2)
	# Use the overhead view so the whole room reads in frame, not the FP eye view.
	if deck.has_method("set_first_person"):
		deck.set_first_person(false)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var saved: int = 0
	for cls in CLASSES:
		deck.set_ship_list([{"name": "Preview", "class": cls}])
		await _wait_frames(2)
		# Frame the entire deck from an elevated 3/4 angle scaled to the class.
		var n: int = deck.ROOM_NAMES.size()
		var length: float = float(deck.ROOM_W) * float(n)
		var depth: float = float(deck.ROOM_D)
		var cam: Camera3D = deck.camera
		if cam == null:
			continue
		cam.position = Vector3(length * 0.18, max(9.0, depth * 1.05), depth * 0.55 + length * 0.45)
		cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
		cam.fov = 60.0
		cam.current = true
		await _wait_frames(3)
		await RenderingServer.frame_post_draw
		var img: Image = cam.get_viewport().get_texture().get_image()
		if img == null or img.is_empty():
			push_warning("deck_screenshot: empty image for %s" % cls)
			continue
		var out_abs: String = ProjectSettings.globalize_path(OUT_DIR.path_join("deck_%s.png" % cls))
		if img.save_png(out_abs) == OK:
			saved += 1
			print("DECK_SHOT saved=%s rooms=%d ROOM_W=%.0f ROOM_D=%.0f" % [out_abs, n, deck.ROOM_W, deck.ROOM_D])
		else:
			push_warning("deck_screenshot: save_png failed for %s" % cls)

	print("DECK_SHOTS_DONE saved=%d" % saved)
	quit(0 if saved == CLASSES.size() else 1)
