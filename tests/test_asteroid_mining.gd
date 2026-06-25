extends SceneTree
# Regression test for asteroid fields and mining. Proves asteroids spawn per system,
# each rock carries a well-formed record, destroying an asteroid yields Ore into cargo,
# cargo capacity is respected (overflow ore is lost, not over-filled), ship-asteroid
# collision resolves (hull damage and/or push-out), and the field re-spawns after a clear.
# Exercised via direct method calls only (no rendered input).

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

	# 1. A field spawned for the booted system.
	if main.asteroids.size() <= 0:
		_fail("expected asteroids to spawn for the starting system")

	# 2. Each asteroid record is well-formed.
	if not failed:
		for a in main.asteroids:
			var ad: Dictionary = a
			if not is_instance_valid(ad.get("node")):
				_fail("asteroid node should be a valid instance")
				break
			if not (ad["node"] is MeshInstance3D):
				_fail("asteroid node should be a MeshInstance3D")
				break
			if typeof(ad.get("pos")) != TYPE_VECTOR3:
				_fail("asteroid pos should be a Vector3")
				break
			if float(ad.get("radius", 0.0)) <= 0.0:
				_fail("asteroid radius should be > 0")
				break
			if float(ad.get("hull", 0.0)) <= 0.0:
				_fail("asteroid hull should be > 0")
				break
			if float(ad.get("max_hull", 0.0)) <= 0.0:
				_fail("asteroid max_hull should be > 0")
				break
			if int(ad.get("ore_yield", 0)) < 1:
				_fail("asteroid ore_yield should be >= 1")
				break

	# 3. Destroying an asteroid yields its ore_yield into cargo and removes it from the array.
	if not failed:
		var first: Dictionary = main.asteroids[0]
		var yld: int = int(first["ore_yield"])
		var before_ore: int = int(main.cargo.get("ore", 0))
		var before_count: int = main.asteroids.size()
		main._destroy_asteroid(first)
		if main.asteroids.size() != before_count - 1:
			_fail("destroyed asteroid should be removed from the array")
		if main.asteroids.has(first):
			_fail("destroyed asteroid dict should no longer be in asteroids")
		var after_ore: int = int(main.cargo.get("ore", 0))
		if after_ore != before_ore + yld:
			_fail("cargo ore should increase by ore_yield (%d -> %d, yield %d)" % [before_ore, after_ore, yld])

	# 4. Cargo capacity is respected: fill to the cap, then destroy one more rock and confirm
	#    no overflow (ore clamps to CARGO_CAPACITY, surplus is lost, no error thrown).
	if not failed:
		var guard: int = 0
		while main._cargo_used() < main.CARGO_CAPACITY and guard < 200:
			main._make_asteroid(Vector3(900, 900, 900), 8.0)   # ore_yield = 4
			main._destroy_asteroid(main.asteroids[main.asteroids.size() - 1])
			guard += 1
		if main._cargo_used() != main.CARGO_CAPACITY:
			_fail("could not fill cargo to capacity (used %d / %d)" % [main._cargo_used(), main.CARGO_CAPACITY])
		var capped_before: int = int(main.cargo.get("ore", 0))
		main._make_asteroid(Vector3(900, 900, 900), 8.0)
		main._destroy_asteroid(main.asteroids[main.asteroids.size() - 1])
		var capped_after: int = int(main.cargo.get("ore", 0))
		if capped_after != capped_before:
			_fail("ore should not exceed capacity (overflow lost): %d -> %d" % [capped_before, capped_after])
		if main._cargo_used() > main.CARGO_CAPACITY:
			_fail("cargo used should never exceed CARGO_CAPACITY")

	# 5. Ship-asteroid collision resolves: place the player ship overlapping an asteroid, then
	#    integrate one motion step. The collision must EITHER hurt the ship OR push it clear.
	if not failed:
		var ply: Node3D = main.get("player")
		if not is_instance_valid(ply):
			_fail("no player flagship for collision test")
		else:
			main._clear_asteroids()
			main._make_asteroid(ply.global_position, 6.0)
			var coll: Dictionary = main.asteroids[0]
			var ap: Vector3 = Vector3(coll["pos"])
			ply.global_position = ap   # dead-center overlap
			ply.velocity = Vector3(0, 0, 5)
			var hull_before: float = float(ply.hull)
			main._integrate_motion(0.016)
			var hull_after: float = float(ply.hull)
			var moved_clear: bool = ply.global_position.distance_to(ap) > float(coll["radius"])
			if not (hull_after < hull_before or moved_clear):
				_fail("ship-asteroid collision should damage the ship or push it clear")

	# 6. Field re-spawns from data after a clear (deterministic stable range, not over the cap).
	if not failed:
		main._clear_asteroids()
		if main.asteroids.size() != 0:
			_fail("asteroids should be empty after _clear_asteroids")
		main._spawn_asteroids(0)
		if main.asteroids.size() <= 0:
			_fail("re-spawned field should contain asteroids")
		if main.asteroids.size() > 20:
			_fail("asteroid count should be capped at 20 (got %d)" % main.asteroids.size())
		for a2 in main.asteroids:
			var ad2: Dictionary = a2
			if not is_instance_valid(ad2.get("node")):
				_fail("re-spawned asteroid node should be valid")
				break
			if int(ad2.get("ore_yield", 0)) < 1:
				_fail("re-spawned asteroid ore_yield should be >= 1")
				break

	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	if not failed:
		print("ASTEROID_MINING_TEST_PASS")
	quit(1 if failed else 0)
