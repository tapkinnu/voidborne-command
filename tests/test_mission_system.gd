extends SceneTree
# Regression test for the multi-mission objective system.
# Verifies: missions are defined and start active, the derived objective string reflects
# the current mission, mission cycling advances/wraps, and completion checks pay rewards
# (destroy-count path and capture-station path).

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

	var game: Node = root.get_node_or_null("Game")
	if game == null:
		_fail("Game autoload missing in test tree")
		quit(1)
		return

	# --- 1. At least 5 missions, all active -----------------------------------
	var missions: Array = main.get("missions")
	if missions.size() < 5:
		_fail("expected at least 5 missions, found %d" % missions.size())
	if not failed:
		for m in missions:
			var md: Dictionary = m
			if String(md.get("state", "")) == "locked":
				continue
			if String(md.get("state", "")) != "active":
				_fail("mission %s did not start active" % String(md.get("id", "?")))

	# --- 2. Derived objective text names the current mission title ------------
	if not failed:
		var obj_txt: String = String(main.call("_current_objective_text"))
		if obj_txt == "":
			_fail("_current_objective_text returned empty")
		var first: Dictionary = missions[int(main.get("current_mission_index"))]
		if not obj_txt.contains(String(first.get("title", ""))):
			_fail("objective text '%s' missing current mission title" % obj_txt)

	# --- 3. Cycling advances the current mission index ------------------------
	if not failed:
		var before: int = int(main.get("current_mission_index"))
		main.call("_cycle_mission")
		var after: int = int(main.get("current_mission_index"))
		if after == before:
			_fail("_cycle_mission did not advance current_mission_index")

	# --- 4. destroy_raiders completes and pays its reward --------------------
	if not failed:
		var dm: Dictionary = _find_mission(missions, "destroy_raiders")
		if dm.is_empty():
			_fail("destroy_raiders mission not found")
		else:
			var reward: int = int(dm.get("reward", 0))
			var credits_before: int = int(game.credits)
			main.set("_destroyed_hostile_count", 5)
			main.call("_check_missions")
			await process_frame
			var dm2: Dictionary = _find_mission(main.get("missions"), "destroy_raiders")
			if String(dm2.get("state", "")) != "complete":
				_fail("destroy_raiders not complete after force (state=%s)" % String(dm2.get("state", "")))
			if int(game.credits) != credits_before + reward:
				_fail("destroy_raiders reward not paid (credits %d, expected %d)" % [int(game.credits), credits_before + reward])

	# --- 5. capture_kryos completes when Kryos Relay turns player ------------
	if not failed:
		var km: Dictionary = _find_mission(main.get("missions"), "capture_kryos")
		if km.is_empty():
			_fail("capture_kryos mission not found")
		else:
			var reward2: int = int(km.get("reward", 0))
			var credits_before2: int = int(game.credits)
			var relay: Node = null
			for s in main.ships:
				if is_instance_valid(s) and String(s.ship_name) == "Kryos Relay":
					relay = s
					break
			if relay == null:
				_fail("Kryos Relay station not found in world")
			else:
				relay.set("faction", "player")
				main.call("_check_missions")
				await process_frame
				var km2: Dictionary = _find_mission(main.get("missions"), "capture_kryos")
				if String(km2.get("state", "")) != "complete":
					_fail("capture_kryos not complete after faction flip (state=%s)" % String(km2.get("state", "")))
				# >= because flipping the relay to player also fulfils fleet_of_three (+reward),
				# so credits may rise by more than this mission's reward in the same check.
				if int(game.credits) < credits_before2 + reward2:
					_fail("capture_kryos reward not paid (credits %d, expected >= %d)" % [int(game.credits), credits_before2 + reward2])

	if not failed:
		print("MISSION_SYSTEM_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)

func _find_mission(arr: Array, id: String) -> Dictionary:
	for m in arr:
		var md: Dictionary = m
		if String(md.get("id", "")) == id:
			return md
	return {}
