extends SceneTree
# Regression test for the mission-giver UI overlay and chained/branching missions.
#
# Verifies:
# 1. _init_missions defines at least one mission with a "next" chain pointer and
#    at least one mission that starts in the "locked" state (a branching unlock).
# 2. Completing a chained mission activates its "next" mission (locked → active).
# 3. The mission-giver overlay opens/closes via the toggle function and exposes
#    a navigable list with cursor + accept/abandon actions.
# 4. Abandoning an active mission marks it "failed" and is reflected in the list.
# 5. Chained mission state round-trips through _missions_to_save / _missions_from_save.
# 6. The overlay state is transient (not part of the save dict).

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

	# --- 1. Chained + locked missions exist ----------------------------------
	if not failed:
		var missions: Array = main.get("missions")
		var has_chain: bool = false
		var has_locked: bool = false
		for m in missions:
			var md: Dictionary = m
			if String(md.get("next", "")) != "":
				has_chain = true
			if String(md.get("state", "")) == "locked":
				has_locked = true
		if not has_chain:
			_fail("no mission with a 'next' chain pointer found")
		if not has_locked:
			_fail("no mission starting in 'locked' state found (branching unlock)")

	# --- 2. Completing a chained mission unlocks its next --------------------
	if not failed:
		var missions: Array = main.get("missions")
		# Find the first chained mission and its next target.
		var chain_id: String = ""
		var next_id: String = ""
		for m in missions:
			var md: Dictionary = m
			next_id = String(md.get("next", ""))
			if next_id != "":
				chain_id = String(md.get("id", ""))
				break
		if chain_id == "":
			_fail("could not find a chained mission to test unlock")
		else:
			# Force-complete the chained mission by marking its objective done.
			var cm: Dictionary = _find_mission(main.get("missions"), chain_id)
			var objs: Array = cm.get("objectives", [])
			for o in objs:
				var od: Dictionary = o
				od["done"] = true
			main.call("_check_missions")
			await process_frame
			# The next mission should now be active (unlocked).
			var nm2: Dictionary = _find_mission(main.get("missions"), next_id)
			if nm2.is_empty():
				_fail("chained 'next' mission '%s' not found after unlock" % next_id)
			elif String(nm2.get("state", "")) != "active":
				_fail("chained next mission '%s' is %s, expected active" % [next_id, String(nm2.get("state", ""))])

	# --- 3. Mission-giver overlay toggle + cursor + list ---------------------
	if not failed:
		main.set("mission_giver_open", false)
		main.call("_toggle_mission_giver")
		if not bool(main.get("mission_giver_open")):
			_fail("_toggle_mission_giver did not open the overlay")
		# The overlay should expose a list of missions with a cursor.
		var mg_list: Array = main.call("_build_mission_giver_list")
		if mg_list.size() < 1:
			_fail("_build_mission_giver_list returned empty list")
		# Cursor navigation: move down then up.
		var cursor_before: int = int(main.get("mission_giver_cursor"))
		main.call("_handle_mission_giver_key", KEY_DOWN)
		var cursor_after_down: int = int(main.get("mission_giver_cursor"))
		if cursor_after_down == cursor_before:
			_fail("KEY_DOWN did not move the mission-giver cursor")
		main.call("_handle_mission_giver_key", KEY_UP)
		var cursor_after_up: int = int(main.get("mission_giver_cursor"))
		# Up should move it back (or wrap); just verify it changed or returned.
		if cursor_after_up == cursor_after_down and mg_list.size() > 1:
			_fail("KEY_UP did not move the mission-giver cursor back")
		# Close with Esc.
		main.call("_handle_mission_giver_key", KEY_ESCAPE)
		if bool(main.get("mission_giver_open")):
			_fail("KEY_ESCAPE did not close the mission-giver overlay")

	# --- 4. Abandon marks active mission as failed ---------------------------
	if not failed:
		main.call("_toggle_mission_giver")
		# Find an active mission to abandon.
		var missions: Array = main.get("missions")
		var abandon_id: String = ""
		var abandon_idx: int = 0
		var idx: int = 0
		for m in missions:
			var md: Dictionary = m
			if String(md.get("state", "")) == "active":
				abandon_id = String(md.get("id", ""))
				abandon_idx = idx
				break
			idx += 1
		if abandon_id == "":
			_fail("no active mission found to test abandon")
		else:
			# Position cursor on that mission and press the abandon key.
			main.set("mission_giver_cursor", abandon_idx)
			main.call("_handle_mission_giver_key", KEY_A)
			var am: Dictionary = _find_mission(main.get("missions"), abandon_id)
			if String(am.get("state", "")) != "failed":
				_fail("abandon did not mark mission '%s' as failed (state=%s)" % [abandon_id, String(am.get("state", ""))])

	# --- 5. Chained mission state round-trips save/load ----------------------
	if not failed:
		# Re-initialise a fresh main to test load.
		var save_data: Array = main.call("_missions_to_save")
		# Build a minimal parsed dict with just the missions section.
		var parsed: Dictionary = {"missions": save_data}
		# Free current main and create a new one.
		if is_instance_valid(main):
			main.queue_free()
			await process_frame
			await process_frame
		var packed2: PackedScene = load("res://scenes/main.tscn")
		var main2: Node = packed2.instantiate()
		root.add_child(main2)
		await process_frame
		await process_frame
		var audio2: Node = main2.get("audio")
		if audio2 != null:
			audio2.set("enabled", false)
		main2.call("_missions_from_save", parsed)
		await process_frame
		# Verify the failed state we set in step 4 survived the round trip.
		var missions2: Array = main2.get("missions")
		# Find the mission we abandoned (by id) and check it is still failed.
		# We need the abandon_id from step 4 — re-derive from save data.
		var found_failed: bool = false
		for entry in save_data:
			var ed: Dictionary = entry
			if String(ed.get("state", "")) == "failed":
				var mid: String = String(ed.get("id", ""))
				var rm: Dictionary = _find_mission(missions2, mid)
				if String(rm.get("state", "")) == "failed":
					found_failed = true
				break
		if not found_failed:
			_fail("failed/abandoned mission state did not round-trip through save/load")

		# --- 6. Overlay state is NOT in the save dict -------------------------
		# mission_giver_open is transient and must not appear in _missions_to_save.
		var save2: Array = main2.call("_missions_to_save")
		var has_overlay_state: bool = false
		for entry in save2:
			var ed: Dictionary = entry
			if ed.has("mission_giver_open") or ed.has("mission_giver_cursor"):
				has_overlay_state = true
		# The overlay state lives on main, not in mission entries. This is a light
		# check — the key point is that _missions_to_save only stores per-mission
		# state (id, state, objectives_done, and optionally next_unlocked).
		if has_overlay_state:
			_fail("overlay state leaked into _missions_to_save mission entries")

		if is_instance_valid(main2):
			main2.queue_free()
			await process_frame

	if not failed:
		print("MISSION_GIVER_TEST_PASS")
	quit(1 if failed else 0)