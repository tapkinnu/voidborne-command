extends SceneTree
# Regression test for the ship upgrade system: the five upgrade categories, the per-ship
# upgrade levels and apply_upgrades() stat scaling, the _buy_upgrade purchase flow, the
# UPGRADES dock-screen tab (navigation/confirm/build data), and backward-compatible
# save/load. Prints SHIP_UPGRADES_TEST_PASS on success.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _approx(a: float, b: float) -> bool:
	return abs(a - b) < 0.01

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

	var player: Node3D = main.get("player")
	if not is_instance_valid(player):
		_fail("player flagship missing")
		quit(1)
		return
	var pclass: String = String(player.ship_class)
	var ci: Dictionary = Game.class_info(pclass)
	var class_wdmg: float = float(ci.get("weapon_dmg", 7.0))
	var class_fr: float = float(ci.get("fire_rate", 0.2))
	var class_hull: float = float(ci.get("hull", 60.0))

	# --- 1. UPGRADE_CATEGORIES has 5 entries with required fields -------------
	var cats: Array = main.get("UPGRADE_CATEGORIES")
	if cats.size() != 5:
		_fail("UPGRADE_CATEGORIES should have 5 entries, got %d" % cats.size())
	for c in cats:
		var cd: Dictionary = c
		for key in ["id", "name", "stat", "bonus_per_level", "base_cost"]:
			if not cd.has(key):
				_fail("upgrade category missing %s: %s" % [key, str(cd)])
		if float(cd.get("bonus_per_level", 0.0)) <= 0.0:
			_fail("bonus_per_level should be > 0: %s" % str(cd))
		if int(cd.get("base_cost", 0)) <= 0:
			_fail("base_cost should be > 0: %s" % str(cd))

	# --- 2. UPGRADE_MAX_LEVEL is 5 -------------------------------------------
	if int(main.get("UPGRADE_MAX_LEVEL")) != 5:
		_fail("UPGRADE_MAX_LEVEL should be 5, got %d" % int(main.get("UPGRADE_MAX_LEVEL")))

	# --- 3. DOCK_SCREEN_TAB_COUNT is 7 (bounties added); UPGRADES at index 5 ---
	if int(main.get("DOCK_SCREEN_TAB_COUNT")) != 7:
		_fail("DOCK_SCREEN_TAB_COUNT should be 7, got %d" % int(main.get("DOCK_SCREEN_TAB_COUNT")))
	var tab_names: Array = main.get("DOCK_SCREEN_TAB_NAMES")
	if tab_names.size() != 7:
		_fail("DOCK_SCREEN_TAB_NAMES should have 7 entries, got %d" % tab_names.size())
	elif String(tab_names[5]) != "UPGRADES":
		_fail("dock tab 5 should be UPGRADES, got %s" % String(tab_names[5]))

	# --- 4. _dock_screen_row_count(5) returns 5 ------------------------------
	if int(main.call("_dock_screen_row_count", 5)) != 5:
		_fail("upgrades tab row count should be 5")

	# --- 5. Flagship starts at all upgrades level 0 --------------------------
	if int(player.upg_weapons) != 0 or int(player.upg_shields) != 0 or int(player.upg_hull) != 0 \
			or int(player.upg_engines) != 0 or int(player.upg_reactor) != 0:
		_fail("flagship should start with all upgrades at level 0")

	# --- 6. apply_upgrades at level 0 leaves base stats at class defaults -----
	if not failed:
		player.apply_upgrades()
		if not _approx(float(player.base_weapon_dmg), class_wdmg):
			_fail("base_weapon_dmg should equal class default at level 0: %f vs %f" % [float(player.base_weapon_dmg), class_wdmg])

	# --- 7. upg_weapons = 3 scales damage up and fire interval down -----------
	if not failed:
		player.upg_weapons = 3
		player.apply_upgrades()
		var expected_wdmg: float = class_wdmg * (1.0 + 3.0 * 0.15)
		if not _approx(float(player.base_weapon_dmg), expected_wdmg):
			_fail("base_weapon_dmg wrong after 3 weapon upgrades: %f vs %f" % [float(player.base_weapon_dmg), expected_wdmg])
		if float(player.weapon_dmg) < float(player.base_weapon_dmg) - 0.01:
			_fail("weapon_dmg should be >= base_weapon_dmg (crew may add)")
		if float(player.base_fire_rate) >= class_fr:
			_fail("base_fire_rate should drop (faster) after weapon upgrades: %f vs %f" % [float(player.base_fire_rate), class_fr])

	# --- 8. upg_hull = 2 scales max_hull and preserves full HP ----------------
	if not failed:
		player.upg_hull = 2
		player.hull = player.max_hull   # full HP before the upgrade
		player.apply_upgrades()
		var expected_hull: float = class_hull * (1.0 + 2.0 * 0.12)
		if not _approx(float(player.max_hull), expected_hull):
			_fail("max_hull wrong after 2 hull upgrades: %f vs %f" % [float(player.max_hull), expected_hull])
		if not _approx(float(player.hull), float(player.max_hull)):
			_fail("hull should remain full after hull upgrade: %f vs %f" % [float(player.hull), float(player.max_hull)])

	# Position the flagship at a friendly station so _buy_upgrade's range gate passes.
	var station: Node3D = main.get("station")
	if not is_instance_valid(station):
		_fail("neutral station missing for buy tests")
	else:
		player.global_position = station.global_position + Vector3(0, 0, 20)

	# --- 9. _buy_upgrade success path ----------------------------------------
	if not failed:
		player.upg_weapons = 0
		player.apply_upgrades()
		Game.credits = 100000
		var cred_before: int = Game.credits
		main.set("dock_screen_cursor", 0)
		main.call("_buy_upgrade", 0)
		if int(player.upg_weapons) != 1:
			_fail("upg_weapons should be 1 after buy, got %d" % int(player.upg_weapons))
		if Game.credits != cred_before - 800:
			_fail("credits should drop by 800 after first weapons upgrade, got %d" % (cred_before - Game.credits))
		var msgs: Array = main.get("messages")
		if msgs.is_empty():
			_fail("a HUD message should be emitted on upgrade")
		else:
			var last_msg: String = String(msgs[msgs.size() - 1])
			if not (last_msg.findn("upgrade") >= 0 or last_msg.findn("weapons") >= 0):
				_fail("upgrade message should mention upgrade/weapons, got %s" % last_msg)

	# --- 10. _buy_upgrade refuses when maxed ---------------------------------
	if not failed:
		player.upg_weapons = 5
		Game.credits = 100000
		var cred_max: int = Game.credits
		main.call("_buy_upgrade", 0)
		if Game.credits != cred_max:
			_fail("buy at max level should not spend credits")
		if int(player.upg_weapons) != 5:
			_fail("upg_weapons should stay at 5 when maxed")

	# --- 11. _buy_upgrade refuses when broke ---------------------------------
	if not failed:
		player.upg_weapons = 0
		Game.credits = 0
		main.call("_buy_upgrade", 0)
		if Game.credits != 0:
			_fail("buy while broke should not change credits")
		if int(player.upg_weapons) != 0:
			_fail("upg_weapons should stay 0 when broke")

	# --- 12. KEY_6 jumps to the UPGRADES tab ---------------------------------
	if not failed:
		main.set("dock_screen_open", true)
		main.set("dock_screen_tab", 0)
		main.set("dock_screen_cursor", 0)
		main.call("_handle_dock_screen_key", KEY_6)
		if int(main.get("dock_screen_tab")) != 5:
			_fail("KEY_6 should jump to tab 5, got %d" % int(main.get("dock_screen_tab")))
		if int(main.call("_dock_screen_row_count", 5)) != 5:
			_fail("upgrades tab row count should be 5")

	# --- 13. _dock_screen_confirm on upgrades tab buys an upgrade -------------
	if not failed:
		main.set("dock_screen_tab", 5)
		main.set("dock_screen_cursor", 0)
		Game.credits = 100000
		player.upg_weapons = 0
		main.call("_dock_screen_confirm")
		if int(player.upg_weapons) != 1:
			_fail("confirm on upgrades tab should route to _buy_upgrade, upg_weapons=%d" % int(player.upg_weapons))

	# --- 14. _build_dock_screen includes upgrades rows -----------------------
	if not failed:
		main.set("dock_screen_open", true)
		main.set("dock_screen_tab", 5)
		var dsd: Dictionary = main.call("_build_dock_screen")
		if not dsd.has("upgrades"):
			_fail("_build_dock_screen should include an upgrades key")
		else:
			var ud: Dictionary = dsd["upgrades"]
			var urows: Array = ud.get("rows", [])
			if urows.size() != 5:
				_fail("upgrades rows should be size 5, got %d" % urows.size())
			for r in urows:
				var rd: Dictionary = r
				for k in ["name", "level", "max_level", "cost", "maxed"]:
					if not rd.has(k):
						_fail("upgrade row missing %s: %s" % [k, str(rd)])

	# --- 15. Save/load round-trip preserves upgrade levels -------------------
	if not failed:
		player.upg_weapons = 3
		player.upg_shields = 2
		player.apply_upgrades()
		var save_dict: Dictionary = main.call("_build_save_dict")
		var ships_arr: Array = save_dict.get("ships", [])
		var found_player: bool = false
		for entry in ships_arr:
			var ed: Dictionary = entry
			if bool(ed.get("is_player", false)):
				found_player = true
				if not ed.has("upgrades"):
					_fail("player ship dict should include upgrades")
				else:
					var up: Dictionary = ed["upgrades"]
					if int(up.get("weapons", 0)) != 3 or int(up.get("shields", 0)) != 2:
						_fail("saved upgrades wrong: %s" % str(up))
		if not found_player:
			_fail("no player ship found in save dict")
		# Reset, then restore from save.
		player.upg_weapons = 0
		player.upg_shields = 0
		player.apply_upgrades()
		main.call("_apply_save", save_dict)
		var player2: Node3D = main.get("player")
		if not is_instance_valid(player2):
			_fail("player missing after load")
		elif int(player2.upg_weapons) != 3 or int(player2.upg_shields) != 2:
			_fail("upgrades not preserved across save/load: w=%d s=%d" % [int(player2.upg_weapons), int(player2.upg_shields)])

	# --- 16. Old save without upgrades loads at level 0 ----------------------
	if not failed:
		var save_dict2: Dictionary = main.call("_build_save_dict")
		var ships2: Array = save_dict2.get("ships", [])
		for entry in ships2:
			var ed2: Dictionary = entry
			if bool(ed2.get("is_player", false)):
				ed2.erase("upgrades")
		var p_mod: Node3D = main.get("player")
		if is_instance_valid(p_mod):
			p_mod.upg_weapons = 3
		main.call("_apply_save", save_dict2)
		var player3: Node3D = main.get("player")
		if is_instance_valid(player3) and int(player3.upg_weapons) != 0:
			_fail("old save without upgrades should load at level 0, got %d" % int(player3.upg_weapons))

	# --- 17. HUD data includes upgrades while dock screen open on tab 5 -------
	if not failed:
		main.set("dock_screen_open", true)
		main.set("dock_screen_tab", 5)
		main.call("_update_hud")
		var hud_node: Node = main.get("hud")
		if hud_node != null:
			var hd: Dictionary = hud_node.get("data")
			if not hd.has("dock_screen"):
				_fail("HUD data should include dock_screen while open")
			else:
				var ds: Dictionary = hd.get("dock_screen", {})
				if not ds.has("upgrades"):
					_fail("dock_screen data should include upgrades on tab 5")
				else:
					var ud2: Dictionary = ds.get("upgrades", {})
					if not ud2.has("rows"):
						_fail("upgrades data should include rows")

	if not failed:
		print("SHIP_UPGRADES_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
