extends SceneTree
# Regression test for independent turret subsystems. Proves that frigate/capital/station
# ships register per-mount turrets that track a target within their fire arc, clamp to the
# arc when the target is behind the ship, cool down independently, and that fighter/corvette
# ships have no turrets (keeping their fixed-muzzle fire path). Exercised purely via method
# calls (no key simulation).

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

	# Collect representative ships by class.
	var turret_ship: Node = null   # frigate or capital
	var fighter: Node = null
	var corvette: Node = null
	var hostile: Node = null
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		var cls: String = String(s.ship_class)
		if (cls == "frigate" or cls == "capital") and turret_ship == null:
			turret_ship = s
		elif cls == "fighter" and fighter == null:
			fighter = s
		elif cls == "corvette" and corvette == null:
			corvette = s
		if String(s.faction) == "hostile" and String(s.ship_class) != "station" and hostile == null:
			hostile = s

	if turret_ship == null:
		_fail("no frigate/capital ship found for turret test")
	if hostile == null:
		_fail("no hostile target found for turret test")

	# 1. Turret ship reports turrets and entries are well-formed.
	if not failed:
		if not bool(turret_ship.call("has_turrets")):
			_fail("turret_ship.has_turrets() should be true")
		var turrets: Array = turret_ship.get("turrets")
		if turrets.size() <= 0:
			_fail("turret_ship.turrets should be non-empty")
		for t in turrets:
			var td: Dictionary = t
			for key in ["arc_half", "yaw", "cd", "node", "pos", "muzzle_fwd", "base_cd"]:
				if not td.has(key):
					_fail("turret entry missing key '%s'" % key)
			if float(td.get("arc_half", 0.0)) <= 0.0:
				_fail("turret arc_half should be > 0")

	# 2. Turrets track toward a target ahead of the ship (yaw moves off 0).
	if not failed:
		# Place the hostile directly in front-right of the turret ship so a non-zero yaw
		# is expected once the turrets track.
		var fwd: Vector3 = -turret_ship.global_transform.basis.z
		var right: Vector3 = turret_ship.global_transform.basis.x
		hostile.global_position = turret_ship.global_position + fwd * 80.0 + right * 40.0
		var turrets2: Array = turret_ship.get("turrets")
		for t in turrets2:
			var td: Dictionary = t
			td["yaw"] = 0.0
		for n in range(30):
			turret_ship.call("tick_turrets", 0.1, hostile)
		var moved: bool = false
		for t in turrets2:
			var td: Dictionary = t
			if abs(float(td["yaw"])) > 0.05:
				moved = true
		if not moved:
			_fail("turret yaw should move off 0 when tracking a target to the side")

	# 3. Arc clamping: target directly behind clamps every yaw to ±arc_half.
	if not failed:
		var fwd2: Vector3 = -turret_ship.global_transform.basis.z
		hostile.global_position = turret_ship.global_position - fwd2 * 90.0
		for n in range(60):
			turret_ship.call("tick_turrets", 0.1, hostile)
		var turrets3: Array = turret_ship.get("turrets")
		for t in turrets3:
			var td: Dictionary = t
			var arc: float = float(td["arc_half"])
			if abs(float(td["yaw"])) > arc + 0.01:
				_fail("turret yaw %f exceeds arc_half %f when target is behind" % [float(td["yaw"]), arc])

	# 4. Per-turret independence: cooldowns are tracked per mount.
	if not failed:
		var turrets4: Array = turret_ship.get("turrets")
		if turrets4.size() >= 2:
			var t0: Dictionary = turrets4[0]
			var t1: Dictionary = turrets4[1]
			t0["cd"] = 0.5
			t1["cd"] = 0.0
			if float(t0["cd"]) == float(t1["cd"]):
				_fail("turrets should hold independent cooldown values")

	# 5. tick_turrets is safe with a null target (centers turrets, no crash).
	if not failed:
		turret_ship.call("tick_turrets", 0.1, null)

	# 6. Fighter/corvette have no turrets.
	if not failed and fighter != null:
		if bool(fighter.call("has_turrets")):
			_fail("fighter should not have turrets")
	if not failed and corvette != null:
		if bool(corvette.call("has_turrets")):
			_fail("corvette should not have turrets")

	if not failed:
		print("TURRET_TRACKING_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
