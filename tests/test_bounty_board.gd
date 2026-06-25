extends SceneTree
# Regression test for the bounty board: procedural generation, the per-class hostile-kill
# counter, accept/progress/complete/claim lifecycle, the BOUNTIES dock-screen tab, and
# backward-compatible save/load. Prints BOUNTY_BOARD_TEST_PASS on success.

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

	var Game: Object = main.get("Game")
	if Game == null:
		Game = root.get_node_or_null("/root/Game")

	var allowed_classes: Array = ["fighter", "corvette", "frigate", "capital"]
	var max_active: int = int(main.get("BOUNTY_MAX_ACTIVE"))
	var min_reward: int = int(main.get("BOUNTY_MIN_REWARD"))

	# --- 1. bounties is an Array of size BOUNTY_MAX_ACTIVE after init -----------
	var bounties: Array = main.get("bounties")
	if bounties.size() != max_active:
		_fail("bounties should have %d entries after init, got %d" % [max_active, bounties.size()])

	# --- 2. Each bounty has the required fields --------------------------------
	for b in bounties:
		var bd: Dictionary = b
		for key in ["id", "title", "target_class", "kill_target", "reward", "state"]:
			if not bd.has(key):
				_fail("bounty missing required field '%s': %s" % [key, str(bd)])

	# --- 3. target_class is one of the 4 mobile classes (never station) --------
	for b in bounties:
		var bd: Dictionary = b
		var tc: String = String(bd.get("target_class", ""))
		if not allowed_classes.has(tc):
			_fail("bounty target_class '%s' not a valid mobile class" % tc)
		if tc == "station":
			_fail("bounty target_class must never be 'station'")

	# --- 4. kill_target in [2,6]; reward >= BOUNTY_MIN_REWARD -------------------
	for b in bounties:
		var bd: Dictionary = b
		var kt: int = int(bd.get("kill_target", 0))
		if kt < 2 or kt > 6:
			_fail("kill_target %d out of [2,6]" % kt)
		if int(bd.get("reward", 0)) < min_reward:
			_fail("reward %d below BOUNTY_MIN_REWARD %d" % [int(bd.get("reward", 0)), min_reward])

	# --- 5. _hostile_kills_by_class exists and starts at 0 for all 4 classes ----
	var kills: Dictionary = main.get("_hostile_kills_by_class")
	for cls in allowed_classes:
		if int(kills.get(cls, -1)) != 0:
			_fail("_hostile_kills_by_class[%s] should start at 0, got %s" % [String(cls), str(kills.get(cls))])

	# --- 6. Accept a bounty: state -> active, kill_baseline recorded ------------
	# Pick (or force) a fighter bounty so the kill simulation is deterministic.
	var fighter_idx: int = -1
	for i in range(bounties.size()):
		if String((bounties[i] as Dictionary).get("target_class", "")) == "fighter":
			fighter_idx = i
			break
	if fighter_idx < 0:
		# None generated as fighter — coerce the first bounty to a fighter contract.
		var b0: Dictionary = bounties[0]
		b0["target_class"] = "fighter"
		b0["kill_target"] = 3
		b0["kills_so_far"] = 0
		fighter_idx = 0
	var fb: Dictionary = bounties[fighter_idx]
	var fb_target: int = int(fb.get("kill_target", 0))
	main.call("_dock_screen_bounty_action", fighter_idx)
	if String(fb.get("state", "")) != "active":
		_fail("accepted bounty should be 'active', got '%s'" % String(fb.get("state", "")))
	if not fb.has("kill_baseline"):
		_fail("accepted bounty should record kill_baseline")
	# Board refilled back to max after accept.
	if main.get("bounties").size() != max_active:
		_fail("board should refill to %d after accept, got %d" % [max_active, main.get("bounties").size()])

	# --- 7. Simulate kills: progress advances, completes at target -------------
	if not failed:
		var baseline: int = int(fb.get("kill_baseline", 0))
		for n in range(fb_target):
			kills["fighter"] = baseline + n + 1
			main.call("_check_bounties")
		if int(fb.get("kills_so_far", 0)) != fb_target:
			_fail("kills_so_far should reach %d, got %d" % [fb_target, int(fb.get("kills_so_far", 0))])
		if String(fb.get("state", "")) != "complete":
			_fail("bounty should be 'complete' at target, got '%s'" % String(fb.get("state", "")))

	# --- 8. Claim a complete bounty: credits up, removed, board refilled --------
	if not failed:
		Game.credits = 1000
		var reward: int = int(fb.get("reward", 0))
		var fb_id: String = String(fb.get("id", ""))
		# Find current index of the completed bounty (board may have reshuffled on refill).
		var claim_idx: int = -1
		var cur_bounties: Array = main.get("bounties")
		for i in range(cur_bounties.size()):
			if String((cur_bounties[i] as Dictionary).get("id", "")) == fb_id:
				claim_idx = i
				break
		if claim_idx < 0:
			_fail("completed bounty not found on board before claim")
		else:
			main.call("_dock_screen_bounty_action", claim_idx)
			if Game.credits != 1000 + reward:
				_fail("claim should add reward %d, credits now %d" % [reward, Game.credits])
			# Bounty removed (id gone) and board refilled.
			var after: Array = main.get("bounties")
			for b in after:
				if String((b as Dictionary).get("id", "")) == fb_id:
					_fail("claimed bounty should be removed from the board")
			if after.size() != max_active:
				_fail("board should refill to %d after claim, got %d" % [max_active, after.size()])

	# --- 9. Dock screen integration -------------------------------------------
	if not failed:
		if int(main.get("DOCK_SCREEN_TAB_COUNT")) != 7:
			_fail("DOCK_SCREEN_TAB_COUNT should be 7, got %d" % int(main.get("DOCK_SCREEN_TAB_COUNT")))
		var rc: int = int(main.call("_dock_screen_row_count", 6))
		if rc != main.get("bounties").size():
			_fail("tab 6 row count %d should equal bounties.size() %d" % [rc, main.get("bounties").size()])
		var dock: Dictionary = main.call("_build_dock_screen")
		if not dock.has("bounties"):
			_fail("_build_dock_screen should include a 'bounties' key")
		else:
			var bdata: Dictionary = dock.get("bounties", {})
			if not bdata.has("rows"):
				_fail("dock_screen bounties should include 'rows'")

	# --- 10. KEY_7 jumps to the bounties tab -----------------------------------
	if not failed:
		main.set("dock_screen_open", true)
		main.set("dock_screen_tab", 0)
		main.set("dock_screen_cursor", 0)
		main.call("_handle_dock_screen_key", KEY_7)
		if int(main.get("dock_screen_tab")) != 6:
			_fail("KEY_7 should jump to tab 6, got %d" % int(main.get("dock_screen_tab")))

	# --- 11. Save/load round-trip preserves bounties/kills/seq -----------------
	if not failed:
		kills["corvette"] = 7
		main.set("_bounty_seq", 42)
		var save_dict: Dictionary = main.call("_build_save_dict")
		if not save_dict.has("bounties"):
			_fail("save dict should include bounties")
		if not save_dict.has("hostile_kills_by_class"):
			_fail("save dict should include hostile_kills_by_class")
		if not save_dict.has("bounty_seq"):
			_fail("save dict should include bounty_seq")
		var saved_ids: Array = []
		for b in main.get("bounties"):
			saved_ids.append(String((b as Dictionary).get("id", "")))
		# Mutate live state, then restore.
		main.set("bounties", [])
		main.set("_bounty_seq", 0)
		kills["corvette"] = 0
		main.call("_apply_save", save_dict)
		var restored: Array = main.get("bounties")
		if restored.size() != max_active:
			_fail("bounties not restored to %d, got %d" % [max_active, restored.size()])
		var restored_kills: Dictionary = main.get("_hostile_kills_by_class")
		if int(restored_kills.get("corvette", 0)) != 7:
			_fail("corvette kills not restored: %d" % int(restored_kills.get("corvette", 0)))
		if int(main.get("_bounty_seq")) != 42:
			_fail("bounty_seq not restored, got %d" % int(main.get("_bounty_seq")))

	# --- 12. Backward compat: save WITHOUT bounties loads cleanly --------------
	if not failed:
		var save_dict2: Dictionary = main.call("_build_save_dict")
		save_dict2.erase("bounties")
		save_dict2.erase("hostile_kills_by_class")
		save_dict2.erase("bounty_seq")
		var before_size: int = main.get("bounties").size()
		main.call("_apply_save", save_dict2)
		# Board left as-is (still populated; old save did not clear it).
		if main.get("bounties").size() != before_size:
			_fail("missing bounties in save should leave the board untouched")

	if not failed:
		print("BOUNTY_BOARD_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
