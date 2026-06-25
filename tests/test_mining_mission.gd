extends SceneTree
# Regression test for the asteroid-mining mission loop.
# Proves a static mission asks the player to mine Ore, completes from mined-Ore progress
# (not just cargo bought at a market), rewards credits, and persists the mining counter.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _find_mission(arr: Array, id: String) -> Dictionary:
	for m in arr:
		var md: Dictionary = m
		if String(md.get("id", "")) == id:
			return md
	return {}

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

	var game: Node = root.get_node_or_null("Game")
	if game == null:
		_fail("Game autoload missing in test tree")
		quit(1)
		return

	# 1. A dedicated mining mission is present and active.
	var mission: Dictionary = _find_mission(main.get("missions"), "prospector_run")
	if mission.is_empty():
		_fail("prospector_run mining mission not found")
	if not failed:
		if String(mission.get("state", "")) != "active":
			_fail("prospector_run should start active")
		var objs: Array = mission.get("objectives", [])
		if objs.size() != 1:
			_fail("prospector_run should have exactly one objective")
		else:
			var od: Dictionary = objs[0]
			if String(od.get("check", "")) != "mine_ore":
				_fail("prospector_run objective should use mine_ore check")
			if int(od.get("arg", 0)) != 6:
				_fail("prospector_run should require 6 mined Ore")

	# 2. Mission does not complete before the mined-Ore counter reaches the target.
	if not failed:
		main.set("_ore_mined_count", 5)
		var credits_before: int = int(game.get("credits"))
		main.call("_check_missions")
		await process_frame
		var still_active: Dictionary = _find_mission(main.get("missions"), "prospector_run")
		if String(still_active.get("state", "")) != "active":
			_fail("prospector_run completed before 6 mined Ore")
		if int(game.get("credits")) != credits_before:
			_fail("prospector_run paid reward before completion")

	# 3. Reaching 6 mined Ore completes and pays the reward.
	if not failed:
		var reward: int = int(mission.get("reward", 0))
		var credits_before2: int = int(game.get("credits"))
		main.set("_ore_mined_count", 6)
		main.call("_check_missions")
		await process_frame
		var done_mission: Dictionary = _find_mission(main.get("missions"), "prospector_run")
		if String(done_mission.get("state", "")) != "complete":
			_fail("prospector_run did not complete at 6 mined Ore")
		if int(game.get("credits")) != credits_before2 + reward:
			_fail("prospector_run reward not paid (credits %d, expected %d)" % [int(game.get("credits")), credits_before2 + reward])

	# 4. Destroying asteroids increments the mined-Ore counter only by Ore actually added.
	if not failed:
		main.set("_ore_mined_count", 0)
		main.cargo = {}
		main.call("_clear_asteroids")
		main.call("_make_asteroid", Vector3(700, 0, 700), 8.0) # ore_yield = 4
		var first: Dictionary = main.asteroids[main.asteroids.size() - 1]
		var yld: int = int(first.get("ore_yield", 0))
		main.call("_destroy_asteroid", first)
		if int(main.get("_ore_mined_count")) != yld:
			_fail("ore_mined_count should increase by actual yield %d (got %d)" % [yld, int(main.get("_ore_mined_count"))])
		if int(main.cargo.get("ore", 0)) != yld:
			_fail("mined Ore should enter cargo")
		# With a full hold, the rock breaks but no Ore is awarded and the counter must not rise.
		main.cargo = {"ore": main.CARGO_CAPACITY}
		var before_full: int = int(main.get("_ore_mined_count"))
		main.call("_make_asteroid", Vector3(720, 0, 720), 8.0)
		var full_hit: Dictionary = main.asteroids[main.asteroids.size() - 1]
		main.call("_destroy_asteroid", full_hit)
		if int(main.get("_ore_mined_count")) != before_full:
			_fail("full cargo should not increase ore_mined_count")

	# 5. The mined-Ore counter round-trips through the save payload.
	if not failed:
		main.set("_ore_mined_count", 3)
		var save_data: Dictionary = main.call("_build_save_dict")
		if int(save_data.get("ore_mined_count", -1)) != 3:
			_fail("save payload missing ore_mined_count=3")
		else:
			main.set("_ore_mined_count", 0)
			main.call("_apply_save", save_data)
			await process_frame
			if int(main.get("_ore_mined_count")) != 3:
				_fail("ore_mined_count did not restore from save")

	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	if not failed:
		print("MINING_MISSION_TEST_PASS")
	quit(1 if failed else 0)
