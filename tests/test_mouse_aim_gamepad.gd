extends SceneTree
# Regression test for the input/control settings increment: mouse-aim toggle,
# control-scheme cycling (auto -> keyboard -> gamepad -> auto), and the settings
# overlay toggle. Exercised purely via direct method calls (no key simulation) so
# the toggles resolve deterministically.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

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

	# --- 1) Mouse-aim toggle --------------------------------------------------
	if bool(main.get("mouse_aim")) != false:
		_fail("mouse_aim did not default to false")
	main.call("_toggle_mouse_aim")
	if bool(main.get("mouse_aim")) != true:
		_fail("mouse_aim not true after first toggle")
	main.call("_toggle_mouse_aim")
	if bool(main.get("mouse_aim")) != false:
		_fail("mouse_aim not false after second toggle")
	# Leave the cursor visible regardless of toggle parity.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# --- 2) Control scheme cycling: auto -> keyboard -> gamepad -> auto -------
	if String(main.get("control_scheme")) != "auto":
		_fail("control_scheme did not default to 'auto'")
	main.call("_cycle_control_scheme")
	if String(main.get("control_scheme")) != "keyboard":
		_fail("control_scheme not 'keyboard' after first cycle")
	main.call("_cycle_control_scheme")
	if String(main.get("control_scheme")) != "gamepad":
		_fail("control_scheme not 'gamepad' after second cycle")
	main.call("_cycle_control_scheme")
	if String(main.get("control_scheme")) != "auto":
		_fail("control_scheme not back to 'auto' after third cycle")

	# --- 3) Settings overlay toggle -------------------------------------------
	if bool(main.get("settings_open")) != false:
		_fail("settings_open did not default to false")
	main.call("_toggle_settings")
	if bool(main.get("settings_open")) != true:
		_fail("settings_open not true after first toggle")
	main.call("_toggle_settings")
	if bool(main.get("settings_open")) != false:
		_fail("settings_open not false after second toggle")

	if not failed:
		print("MOUSE_AIM_GAMEPAD_TEST_PASS")
	_finish(main)

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	quit(1 if failed else 0)
