extends SceneTree
# Regression test for explicit fleet command orders. The vertical slice must let the
# player command manned purchased/captured ships, not only passively follow.

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

	var escort: Node = null
	for s in main.ships:
		if is_instance_valid(s) and String(s.faction) == "player" and not bool(s.is_player):
			escort = s
			break
	if escort == null:
		_fail("no player escort available for fleet-order test")

	if not failed:
		if str(main.get("fleet_order")) != "follow":
			_fail("fleet should start in follow order")
		main.call("_set_fleet_order", "hold")
		await process_frame
		if str(main.get("fleet_order")) != "hold":
			_fail("hold order should switch fleet_order to hold")
		if str(escort.get("ai_state")) != "hold":
			_fail("manned escort did not receive hold ai_state")
		var holds: Dictionary = main.get("fleet_hold_positions")
		if not holds.has(escort.get_instance_id()):
			_fail("hold order did not record escort hold position")

	if not failed:
		main.call("_set_fleet_order", "follow")
		await process_frame
		if str(main.get("fleet_order")) != "follow":
			_fail("follow order should switch fleet_order back to follow")
		if str(escort.get("ai_state")) != "follow":
			_fail("manned escort did not return to follow ai_state")

	if not failed:
		print("FLEET_ORDER_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
