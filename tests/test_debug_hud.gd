extends SceneTree
# Test for DebugHud autoload: loads main scene, waits for frame, 
# sends KEY_F11 event, asserts visibility toggles, prints PASS and exits 0.

func _initialize() -> void:
	# Use SceneTree's _initialize() (not the _init() constructor): the constructor runs
	# during object construction, before the engine registers autoloads (Game, GameConstants,
	# Capture, DebugHud) as compile-time globals — so loading main.tscn there fails main.gd's
	# ~120 `Game.*` references with "Identifier not found: Game". _initialize() runs after the
	# autoloads are registered, so main.gd compiles cleanly.
	# Load the main scene
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		print("FAIL: Could not load main scene")
		quit(1)
		return
	
	var main_node: Node = main_scene.instantiate()
	if main_node == null:
		print("FAIL: Could not instantiate main scene")
		quit(1)
		return
	
	root.add_child(main_node)
	
	# Wait one process frame
	await process_frame
	
	# Assert DebugHud autoload exists
	if not root.has_node("/root/DebugHud"):
		print("FAIL: DebugHud autoload does not exist")
		quit(1)
		return
	
	var debug_hud: Node = root.get_node("/root/DebugHud")
	
	# Check that the control node exists in the scene tree
	var control_node: Control = debug_hud.get_control_node()
	if control_node == null:
		print("FAIL: DebugHud._control node does not exist")
		quit(1)
		return
	
	# Check initial visibility (should be hidden)
	if control_node.visible:
		print("FAIL: DebugHud._control is visible initially (should be hidden)")
		quit(1)
		return
	
	# Send synthetic KEY_F11 event
	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = KEY_F11
	key_event.pressed = true
	Input.parse_input_event(key_event)
	
	# Wait for input to be processed
	await process_frame
	
	# Assert visibility toggled to true
	if not control_node.visible:
		print("FAIL: DebugHud._control did not become visible after KEY_F11")
		quit(1)
		return
	
	# Send another KEY_F11 event to toggle back
	var key_event2: InputEventKey = InputEventKey.new()
	key_event2.keycode = KEY_F11
	key_event2.pressed = true
	Input.parse_input_event(key_event2)
	
	# Wait for input to be processed
	await process_frame
	
	# Assert visibility toggled back to false
	if control_node.visible:
		print("FAIL: DebugHud._control did not become hidden after second KEY_F11")
		quit(1)
		return
	
	print("DEBUG_HUD_TEST_PASS")
	quit(0)