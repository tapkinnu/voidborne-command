extends SceneTree
# Performance budget regression test. Boots the real main scene headless and asserts two
# things: the live entity registries stay within sane caps (so the slice can't silently
# balloon into an unbounded spawn storm), and a 60-frame run stays under a generous average
# frame-time budget. Frame timing is loose because headless xvfb uses software rendering;
# a real GPU would be far faster. Follows the tests/test_*.gd SceneTree pattern.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _check_cap(label: String, count: int, cap: int) -> void:
	print("  %-16s %d (cap %d)" % [label, count, cap])
	if count > cap:
		_fail("%s count %d exceeds budget %d" % [label, count, cap])

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

	# --- Entity count budget ---
	print("entity counts:")
	var ships: Array = main.get("ships")
	var projectiles: Array = main.get("projectiles")
	var beams: Array = main.get("beams")
	var explosions: Array = main.get("explosions")
	var muzzle_flashes: Array = main.get("_muzzle_flashes")
	var shield_impacts: Array = main.get("_shield_impacts")
	var debris: Array = main.get("_debris")

	if ships == null or projectiles == null or beams == null or explosions == null \
			or muzzle_flashes == null or shield_impacts == null or debris == null:
		_fail("one or more entity registries missing on main")
	else:
		_check_cap("ships", ships.size(), 20)
		_check_cap("projectiles", projectiles.size(), 50)
		_check_cap("beams", beams.size(), 20)
		_check_cap("explosions", explosions.size(), 30)
		_check_cap("muzzle_flashes", muzzle_flashes.size(), 30)
		_check_cap("shield_impacts", shield_impacts.size(), 20)
		_check_cap("debris", debris.size(), 60)

	# --- Frame timing budget ---
	if not failed:
		var frames: int = 60
		var start_ms: int = Time.get_ticks_msec()
		for _i in range(frames):
			await process_frame
		var end_ms: int = Time.get_ticks_msec()
		var avg_ms: float = float(end_ms - start_ms) / float(frames)
		print("avg frame time: %.3f ms over %d frames" % [avg_ms, frames])
		if avg_ms >= 50.0:
			_fail("average frame time %.3f ms exceeds 50.0 ms budget" % avg_ms)

	if not failed:
		print("PERF_BUDGET_TEST_PASS")
	else:
		print("PERF_BUDGET_TEST_FAIL")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
