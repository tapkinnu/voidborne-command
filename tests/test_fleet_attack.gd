extends SceneTree
# Regression test for the explicit fleet ATTACK command. Proves the player can order
# manned escorts to focus-fire a chosen hostile, and that the order self-clears when the
# target stops being a valid hostile. Exercised purely via method calls (no key simulation).

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

	# Find a manned player escort (not the flagship) and a hostile target.
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
		_fail("no manned player escort available for fleet-attack test")
	if hostile == null:
		_fail("no hostile target available for fleet-attack test")

	if not failed:
		main.set("target", hostile)
		main.call("_order_fleet_attack")
		if str(main.get("fleet_order")) != "attack":
			_fail("fleet_order should be 'attack' after _order_fleet_attack")
		if main.get("fleet_attack_target") != hostile:
			_fail("fleet_attack_target should be the ordered hostile")
		await process_frame
		if str(escort.get("ai_state")) != "attack":
			_fail("escort ai_state should be 'attack' after order")
		if escort.get("target") != hostile:
			_fail("escort target should be the ordered hostile after a tick")

	# Order must reject a friendly/invalid target.
	if not failed:
		main.set("target", escort)   # escort is player-owned -> invalid attack target
		main.call("_order_fleet_attack")
		if str(main.get("fleet_order")) != "attack" or main.get("fleet_attack_target") != hostile:
			_fail("ordering attack on a friendly target must not change the standing order")

	# Capturing/neutralizing the target (faction flips to player) must auto-clear attack.
	if not failed:
		hostile.call("set_faction", "player")
		await process_frame   # _validate_fleet_attack runs in _process_space
		if str(main.get("fleet_order")) != "follow":
			_fail("fleet_order should fall back to 'follow' once target turns friendly")
		if main.get("fleet_attack_target") != null:
			_fail("fleet_attack_target should be cleared once target is no longer hostile")
		if str(escort.get("ai_state")) != "follow":
			_fail("escort should return to 'follow' after attack order clears")

	if not failed:
		print("FLEET_ATTACK_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
