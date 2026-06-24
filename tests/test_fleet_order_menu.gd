extends SceneTree
# Regression test for the fleet ORDER MENU and its new orders (escort, defend, dock).
# Proves the [F] menu toggles open/closed and that each order can be set, validated, and
# self-clears when its required focus/station is missing. Exercised via method calls only.

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

	# Find a manned player escort (not the flagship) and a hostile.
	var escort: Node = null
	var hostile: Node = null
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		if String(s.faction) == "player" and not bool(s.is_player) and bool(s.manned):
			if escort == null:
				escort = s
		elif String(s.faction) == "hostile" and String(s.ship_class) != "station":
			if hostile == null:
				hostile = s
	if escort == null:
		_fail("no manned player escort available for fleet-order-menu test")
	if hostile == null:
		_fail("no hostile available for fleet-order-menu test")

	# 4. Follow is the default standing order.
	if not failed:
		if str(main.get("fleet_order")) != "follow":
			_fail("fleet should start in follow order")

	# 5. Menu toggle: F opens, F closes.
	if not failed:
		main.call("_toggle_fleet_menu")
		if not bool(main.get("fleet_menu_open")):
			_fail("first _toggle_fleet_menu should open the menu")
		main.call("_toggle_fleet_menu")
		if bool(main.get("fleet_menu_open")):
			_fail("second _toggle_fleet_menu should close the menu")

	# 6. Escort order: fleet_order + every manned escort ai_state become 'escort'.
	if not failed:
		main.call("_set_fleet_order", "escort")
		await process_frame
		if str(main.get("fleet_order")) != "escort":
			_fail("fleet_order should be 'escort' after _set_fleet_order('escort')")
		if str(escort.get("ai_state")) != "escort":
			_fail("manned escort ai_state should be 'escort' after order")

	# 7. Defend order against a player-owned target.
	if not failed:
		main.set("target", escort)   # escort is player-owned -> a valid defend target
		main.call("_set_fleet_order", "defend")
		if str(main.get("fleet_order")) != "defend":
			_fail("fleet_order should be 'defend' after _set_fleet_order('defend')")
		if main.get("fleet_defend_target") != escort:
			_fail("fleet_defend_target should be the ordered target")

	# 8. Defend fallback: clearing the defend target reverts the order to follow.
	if not failed:
		main.set("fleet_defend_target", null)
		main.call("_validate_fleet_defend")
		if str(main.get("fleet_order")) != "follow":
			_fail("defend order should revert to follow once the target is invalid")

	# 9. Dock order is accepted while a friendly station is in range.
	if not failed:
		main.call("_set_fleet_order", "dock")
		if str(main.get("fleet_order")) != "dock":
			_fail("fleet_order should be 'dock' while a friendly station is reachable")
		if str(escort.get("ai_state")) != "dock":
			_fail("manned escort ai_state should be 'dock' after dock order")

	# 10. Dock fallback: with no reachable station, dock reverts to follow.
	if not failed:
		for s in main.ships:
			if is_instance_valid(s) and String(s.ship_class) == "station":
				s.set("destroyed", true)
		main.call("_set_fleet_order", "dock")
		if str(main.get("fleet_order")) != "follow":
			_fail("dock order should revert to follow when no station is reachable")

	if not failed:
		print("FLEET_ORDER_MENU_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
