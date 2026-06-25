extends SceneTree
# Regression test for crew-deck capture/readability framing.
# The deck camera must center on the active room so visible crew/marine humanoids are
# actually in the screenshot, not hidden off-screen by a static x=0 camera.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _camera_has_room_actor(deck: Node) -> bool:
	var cam: Camera3D = deck.get("camera")
	if cam == null:
		return false
	var crew_nodes: Array = deck.get("crew_nodes")
	for entry in crew_nodes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var ed: Dictionary = entry
		var actor: Node3D = ed.get("node")
		if is_instance_valid(actor) and abs(actor.position.x - cam.position.x) <= 4.5:
			return true
	return false

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

	main.call("force_deck", true)
	await process_frame
	await process_frame
	var deck: Node = main.get("deck")
	if deck == null:
		_fail("deck node missing")
	else:
		var cam: Camera3D = deck.get("camera")
		if cam == null:
			_fail("deck camera missing")
		elif abs(cam.position.x + 10.0) > 0.5:
			_fail("bridge camera should center on Bridge room x=-10 (got %.2f)" % cam.position.x)
		if not _camera_has_room_actor(deck):
			_fail("bridge camera does not frame any crew humanoid")

		# Marine Barracks should also reframe when the active room changes.
		deck.call("goto_room", 2)
		await process_frame
		var cam2: Camera3D = deck.get("camera")
		if abs(cam2.position.x - 10.0) > 0.5:
			_fail("barracks camera should center on Marine Barracks room x=10 (got %.2f)" % cam2.position.x)
		if not _camera_has_room_actor(deck):
			_fail("barracks camera does not frame any marine humanoid")

	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	if not failed:
		print("CREW_DECK_CAMERA_TEST_PASS")
	quit(1 if failed else 0)
