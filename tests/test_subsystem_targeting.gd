extends SceneTree
# Regression test for player subsystem targeting (engines/weapons/shields).
# No key simulation: it drives main.gd / ship.gd APIs directly. It verifies subsystem
# health init, the 50/50 damage split when a subsystem is focused, OFFLINE effects on
# engines/weapons, generic (hull-only) damage when no subsystem is focused, station refit
# restoring subsystems, and subsystem health round-tripping through save/load.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _approx(a: float, b: float, eps: float = 0.05) -> bool:
	return abs(a - b) <= eps

func _first_hostile(main: Node) -> Node:
	for s in main.ships:
		if is_instance_valid(s) and String(s.faction) == "hostile" and String(s.ship_class) != "station":
			return s
	return null

func _zero_subsystem(main: Node, player: Node, tgt: Node, focus: String, prop: String) -> void:
	# Drive a subsystem to 0 via the player focus-fire damage path, restoring hull each
	# step so the routing (not raw hull death) is what zeroes the subsystem.
	main.set("subsystem_focus", focus)
	var guard: int = 0
	while float(tgt.get(prop)) > 0.0 and guard < 200:
		tgt.set("shield", 0.0)
		tgt.set("hull", float(tgt.get("max_hull")))
		main.call("_apply_damage", player, tgt, float(tgt.get("max_hull")))
		guard += 1
	tgt.set("hull", float(tgt.get("max_hull")))

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
		_finish(main)
		return

	var player: Node = main.get("player")
	if player == null:
		_fail("player flagship missing")
		_finish(main)
		return

	# --- 1. All ships start with full subsystems --------------------------
	for s in main.ships:
		if not is_instance_valid(s):
			continue
		if not _approx(float(s.sub_engine), 1.0) or not _approx(float(s.sub_weapon), 1.0) or not _approx(float(s.sub_shield), 1.0):
			_fail("ship %s did not start with full subsystems" % String(s.ship_name))

	var tgt: Node = _first_hostile(main)
	if tgt == null:
		_fail("no hostile target found")
		_finish(main)
		return

	# --- 2/3. Focused damage splits 50/50 into subsystem and hull ---------
	if not failed:
		main.set("subsystem_focus", "engines")
		tgt.set("shield", 0.0)
		tgt.set("hull", float(tgt.get("max_hull")))
		var max_hull: float = float(tgt.get("max_hull"))
		var dmg: float = max_hull * 0.2
		main.call("_apply_damage", player, tgt, dmg)
		# hull should drop by half the damage; the rest goes to the engine subsystem.
		var expect_hull: float = max_hull - dmg * 0.5
		if not _approx(float(tgt.get("hull")), expect_hull, 0.5):
			_fail("focused hull damage wrong: got %f expected %f" % [float(tgt.get("hull")), expect_hull])
		var expect_sub: float = 1.0 - (dmg * 0.5) / (max_hull * 0.5)
		if not _approx(float(tgt.get("sub_engine")), expect_sub, 0.02):
			_fail("engine subsystem damage wrong: got %f expected %f" % [float(tgt.get("sub_engine")), expect_sub])
		if float(tgt.get("sub_engine")) >= 1.0:
			_fail("engine subsystem did not decrease under focus fire")

	# --- 4. Engines OFFLINE reduces effective max_speed to 20% ------------
	if not failed:
		_zero_subsystem(main, player, tgt, "engines", "sub_engine")
		if float(tgt.get("sub_engine")) > 0.0:
			_fail("could not bring sub_engine to 0")
		var base_speed: float = float(tgt.get("max_speed"))
		var eff: float = float(tgt.call("eff_max_speed"))
		if not _approx(eff, base_speed * 0.2, 0.5):
			_fail("offline engines did not cut speed to 20%% (eff %f vs %f)" % [eff, base_speed * 0.2])

	# --- 5. Weapons OFFLINE prevents firing ------------------------------
	if not failed:
		_zero_subsystem(main, player, tgt, "weapons", "sub_weapon")
		if float(tgt.get("sub_weapon")) > 0.0:
			_fail("could not bring sub_weapon to 0")
		if bool(tgt.call("can_fire")):
			_fail("weapons OFFLINE but can_fire() still true")
		tgt.set("target", player)
		tgt.set("energy", float(tgt.get("max_energy")))
		tgt.set("weapon_cd", 0.0)
		if bool(main.call("_try_fire", tgt, 0.2)):
			_fail("_try_fire succeeded with weapons OFFLINE")

	# --- 6. No focus -> 100% of post-shield damage to hull ---------------
	if not failed:
		var tgt2: Node = null
		for s in main.ships:
			if is_instance_valid(s) and String(s.faction) == "hostile" and s != tgt and String(s.ship_class) != "station":
				tgt2 = s
				break
		if tgt2 == null:
			_fail("need a second hostile for the no-focus case")
		else:
			main.set("subsystem_focus", "")
			tgt2.set("shield", 0.0)
			tgt2.set("hull", float(tgt2.get("max_hull")))
			var e0: float = float(tgt2.get("sub_engine"))
			var w0: float = float(tgt2.get("sub_weapon"))
			var s0: float = float(tgt2.get("sub_shield"))
			var dmg2: float = float(tgt2.get("max_hull")) * 0.2
			main.call("_apply_damage", player, tgt2, dmg2)
			if not _approx(float(tgt2.get("hull")), float(tgt2.get("max_hull")) - dmg2, 0.5):
				_fail("unfocused damage did not go fully to hull")
			if not _approx(float(tgt2.get("sub_engine")), e0) or not _approx(float(tgt2.get("sub_weapon")), w0) or not _approx(float(tgt2.get("sub_shield")), s0):
				_fail("unfocused damage leaked into subsystems")

	# --- 7. Station [H] repair/refit restores subsystems to 1.0 ----------
	if not failed:
		var st: Node = main.get("station")
		if st == null:
			_fail("no station for refit test")
		else:
			player.set("sub_engine", 0.3)
			player.set("sub_weapon", 0.0)
			player.set("sub_shield", 0.5)
			player.set("hull", float(player.get("max_hull")) * 0.8)
			player.global_position = st.global_position + Vector3(0, 0, 20)
			game.set("credits", 100000)
			await process_frame
			main.call("_station_service")
			if not _approx(float(player.get("sub_engine")), 1.0) or not _approx(float(player.get("sub_weapon")), 1.0) or not _approx(float(player.get("sub_shield")), 1.0):
				_fail("station refit did not restore subsystems (eng %f wpn %f shd %f)" % [float(player.get("sub_engine")), float(player.get("sub_weapon")), float(player.get("sub_shield"))])

	# --- 8. Subsystem health round-trips through save/load ----------------
	if not failed:
		main.set("save_path", "user://test_subsystem_save.json")
		if FileAccess.file_exists("user://test_subsystem_save.json"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_subsystem_save.json"))
		player.set("sub_engine", 0.31)
		player.set("sub_weapon", 0.62)
		player.set("sub_shield", 0.0)
		var saved: bool = bool(main.call("_quick_save"))
		if not saved:
			_fail("quick_save failed for subsystem round-trip")
		else:
			player.set("sub_engine", 1.0)
			player.set("sub_weapon", 1.0)
			player.set("sub_shield", 1.0)
			var ok: bool = bool(main.call("_quick_load"))
			if not ok:
				_fail("quick_load failed for subsystem round-trip")
			else:
				var rp: Node = main.get("player")
				if not _approx(float(rp.get("sub_engine")), 0.31, 0.01):
					_fail("sub_engine did not round-trip (%f)" % float(rp.get("sub_engine")))
				if not _approx(float(rp.get("sub_weapon")), 0.62, 0.01):
					_fail("sub_weapon did not round-trip (%f)" % float(rp.get("sub_weapon")))
				if not _approx(float(rp.get("sub_shield")), 0.0, 0.01):
					_fail("sub_shield did not round-trip (%f)" % float(rp.get("sub_shield")))
		if FileAccess.file_exists("user://test_subsystem_save.json"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_subsystem_save.json"))

	if not failed:
		print("SUBSYSTEM_TARGETING_TEST_PASS")
	_finish(main)

func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	quit(1 if failed else 0)
