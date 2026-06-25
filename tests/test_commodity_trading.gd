extends SceneTree
# Regression test for the commodity trading system: commodity defs, deterministic per-station
# prices, the flagship cargo hold, buy/sell flow, the MARKET dock-screen tab, and
# backward-compatible save/load. Prints COMMODITY_TRADING_TEST_PASS on success.

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
		# Autoload accessed via the singleton name in script scope; fetch from the tree.
		Game = root.get_node_or_null("/root/Game")

	# --- 1. COMMODITIES has 5 entries with required fields ---------------------
	var commodities: Array = main.get("COMMODITIES")
	if commodities.size() != 5:
		_fail("COMMODITIES should have 5 entries, got %d" % commodities.size())
	for c in commodities:
		var cd: Dictionary = c
		if not cd.has("id") or not cd.has("name") or not cd.has("base_price"):
			_fail("commodity missing required field: %s" % str(cd))
		if int(cd.get("base_price", 0)) <= 0:
			_fail("commodity base_price should be > 0: %s" % str(cd))

	# --- 2. cargo starts empty, CARGO_CAPACITY is 50 --------------------------
	var cargo0: Dictionary = main.get("cargo")
	if not cargo0.is_empty():
		_fail("cargo should start empty, got %s" % str(cargo0))
	if int(main.get("CARGO_CAPACITY")) != 50:
		_fail("CARGO_CAPACITY should be 50, got %d" % int(main.get("CARGO_CAPACITY")))

	# --- 3. _cargo_used() returns 0 initially ---------------------------------
	if int(main.call("_cargo_used")) != 0:
		_fail("_cargo_used should be 0 initially")

	# --- 4. _commodity_prices returns 5 entries, buy>0 sell>0 buy>=sell --------
	var prices: Dictionary = main.call("_commodity_prices", "Halcyon", 0)
	if prices.size() != 5:
		_fail("_commodity_prices should return 5 entries, got %d" % prices.size())
	for cid in prices.keys():
		var pr: Dictionary = prices[cid]
		var buy: int = int(pr.get("buy", 0))
		var sell: int = int(pr.get("sell", 0))
		if buy <= 0:
			_fail("buy price for %s should be > 0" % String(cid))
		if sell <= 0:
			_fail("sell price for %s should be > 0" % String(cid))
		if buy < sell:
			_fail("buy (%d) should be >= sell (%d) for %s" % [buy, sell, String(cid)])

	# --- 5. Prices deterministic: twice returns identical values --------------
	var prices_again: Dictionary = main.call("_commodity_prices", "Halcyon", 0)
	for cid in prices.keys():
		var a: Dictionary = prices[cid]
		var b: Dictionary = prices_again[cid]
		if int(a.get("buy", 0)) != int(b.get("buy", 0)) or int(a.get("sell", 0)) != int(b.get("sell", 0)):
			_fail("prices not deterministic for %s" % String(cid))

	# --- 6. Different stations have different prices --------------------------
	var prices_aurora: Dictionary = main.call("_commodity_prices", "Aurora Station", 0)
	var any_diff: bool = false
	for cid in prices.keys():
		var ha: Dictionary = prices[cid]
		var au: Dictionary = prices_aurora[cid]
		if int(ha.get("buy", 0)) != int(au.get("buy", 0)):
			any_diff = true
			break
	if not any_diff:
		_fail("Halcyon and Aurora Station should differ on at least one commodity")

	# --- 7. Buy commodity: credits down, cargo up -----------------------------
	if not failed:
		Game.credits = 100000
		var cred_before: int = Game.credits
		main.call("_buy_commodity", 0, "Halcyon")
		if Game.credits >= cred_before:
			_fail("credits should decrease after buy")
		var cargo_after: Dictionary = main.get("cargo")
		var ore_id: String = String((commodities[0] as Dictionary).get("id", ""))
		if int(cargo_after.get(ore_id, 0)) != 1:
			_fail("cargo should hold 1 %s after buy" % ore_id)
		if int(main.call("_cargo_used")) != 1:
			_fail("_cargo_used should be 1 after buy")

	# --- 8. Buy when full cargo: refuses, credits unchanged -------------------
	if not failed:
		var ore_id2: String = String((commodities[0] as Dictionary).get("id", ""))
		# Fill the hold to capacity directly.
		main.set("cargo", {ore_id2: 50})
		Game.credits = 100000
		var cred_full: int = Game.credits
		main.call("_buy_commodity", 1, "Halcyon")
		if Game.credits != cred_full:
			_fail("buy on full cargo should not spend credits")
		if int(main.call("_cargo_used")) != 50:
			_fail("cargo should stay at 50 when full")

	# --- 9. Buy when broke: refuses, cargo unchanged --------------------------
	if not failed:
		main.set("cargo", {})
		Game.credits = 0
		main.call("_buy_commodity", 4, "Halcyon")  # tech parts, most expensive
		var cargo_broke: Dictionary = main.get("cargo")
		if not cargo_broke.is_empty():
			_fail("buy while broke should not add cargo")

	# --- 10. Sell commodity: credits up, cargo down ---------------------------
	if not failed:
		var ore_id3: String = String((commodities[0] as Dictionary).get("id", ""))
		main.set("cargo", {ore_id3: 3})
		Game.credits = 0
		main.call("_sell_commodity", 0, "Halcyon")
		if Game.credits <= 0:
			_fail("credits should increase after sell")
		var cargo_sold: Dictionary = main.get("cargo")
		if int(cargo_sold.get(ore_id3, 0)) != 2:
			_fail("cargo should drop to 2 after selling 1")

	# --- 11. Sell when empty: refuses, credits unchanged ----------------------
	if not failed:
		main.set("cargo", {})
		Game.credits = 500
		main.call("_sell_commodity", 2, "Halcyon")
		if Game.credits != 500:
			_fail("sell with empty cargo should not change credits")

	# --- 12. MARKET tab navigation: KEY_5 jumps to tab 4, row count 5 ---------
	if not failed:
		main.set("dock_screen_open", true)
		main.set("dock_screen_tab", 0)
		main.set("dock_screen_cursor", 0)
		main.call("_handle_dock_screen_key", KEY_5)
		if int(main.get("dock_screen_tab")) != 4:
			_fail("KEY_5 should jump to tab 4, got %d" % int(main.get("dock_screen_tab")))
		if int(main.call("_dock_screen_row_count", 4)) != 5:
			_fail("market tab row count should be 5")

	# --- 13. Save/load round-trip preserves cargo -----------------------------
	if not failed:
		main.set("cargo", {"ore": 4, "tech": 1})
		var save_dict: Dictionary = main.call("_build_save_dict")
		var econ: Dictionary = save_dict.get("economy", {})
		if not econ.has("cargo"):
			_fail("save dict economy should include cargo")
		# Mutate cargo, then restore from the saved dict.
		main.set("cargo", {})
		main.call("_apply_save", save_dict)
		var restored: Dictionary = main.get("cargo")
		if int(restored.get("ore", 0)) != 4 or int(restored.get("tech", 0)) != 1:
			_fail("cargo not preserved across save/load: %s" % str(restored))

	# --- 14. Old save without cargo: loads with empty cargo -------------------
	if not failed:
		var save_dict2: Dictionary = main.call("_build_save_dict")
		var econ2: Dictionary = save_dict2.get("economy", {})
		econ2.erase("cargo")
		save_dict2["economy"] = econ2
		main.set("cargo", {"ore": 9})
		main.call("_apply_save", save_dict2)
		var restored2: Dictionary = main.get("cargo")
		if not restored2.is_empty():
			_fail("missing cargo in save should load as empty, got %s" % str(restored2))

	# --- 15. market_sell_mode toggles with KEY_S on the market tab ------------
	if not failed:
		main.set("dock_screen_open", true)
		main.set("dock_screen_tab", 4)
		main.set("market_sell_mode", false)
		main.call("_handle_dock_screen_key", KEY_S)
		if not bool(main.get("market_sell_mode")):
			_fail("KEY_S on market tab should toggle sell mode on")
		main.call("_handle_dock_screen_key", KEY_S)
		if bool(main.get("market_sell_mode")):
			_fail("KEY_S again should toggle sell mode off")

	# --- 16. KEY_M bulk-buys max affordable units on the market tab -----------
	if not failed:
		var player_node: Node3D = main.get("player")
		var station_node: Node3D = main.get("station")
		if not is_instance_valid(player_node) or not is_instance_valid(station_node):
			_fail("player/station missing for bulk trade test")
		else:
			player_node.global_position = station_node.global_position + Vector3(0, 0, 20)
			var st_name: String = String(station_node.ship_name)
			var bulk_prices: Dictionary = main.call("_commodity_prices", st_name, int(main.get("current_system_index")))
			var ore_id4: String = String((commodities[0] as Dictionary).get("id", ""))
			var ore_price: int = int((bulk_prices.get(ore_id4, {}) as Dictionary).get("buy", 0))
			main.set("cargo", {})
			Game.credits = ore_price * 3 + 1
			main.set("dock_screen_open", true)
			main.set("dock_screen_tab", 4)
			main.set("dock_screen_cursor", 0)
			main.set("market_sell_mode", false)
			main.call("_handle_dock_screen_key", KEY_M)
			var cargo_bulk: Dictionary = main.get("cargo")
			if int(cargo_bulk.get(ore_id4, 0)) != 3:
				_fail("KEY_M bulk buy should buy exactly 3 affordable ore units, got %s" % str(cargo_bulk))
			if Game.credits != 1:
				_fail("KEY_M bulk buy should leave 1 credit, got %d" % Game.credits)

	# --- 17. KEY_M bulk-buy respects remaining cargo capacity -----------------
	if not failed:
		var alloy_id: String = String((commodities[1] as Dictionary).get("id", ""))
		var ore_id5: String = String((commodities[0] as Dictionary).get("id", ""))
		main.set("cargo", {ore_id5: 49})
		Game.credits = 100000
		main.set("dock_screen_cursor", 1)
		main.set("market_sell_mode", false)
		main.call("_handle_dock_screen_key", KEY_M)
		var cargo_cap: Dictionary = main.get("cargo")
		if int(cargo_cap.get(alloy_id, 0)) != 1:
			_fail("KEY_M bulk buy should fill only 1 remaining cargo slot, got %s" % str(cargo_cap))
		if int(main.call("_cargo_used")) != 50:
			_fail("KEY_M bulk buy should stop at cargo capacity 50")

	# --- 18. KEY_M bulk-sells all held units in SELL mode ---------------------
	if not failed:
		var ore_id6: String = String((commodities[0] as Dictionary).get("id", ""))
		var sell_prices: Dictionary = main.call("_commodity_prices", String((main.get("station") as Node3D).ship_name), int(main.get("current_system_index")))
		var ore_sell: int = int((sell_prices.get(ore_id6, {}) as Dictionary).get("sell", 0))
		main.set("cargo", {ore_id6: 4})
		Game.credits = 10
		main.set("dock_screen_cursor", 0)
		main.set("market_sell_mode", true)
		main.call("_handle_dock_screen_key", KEY_M)
		var cargo_sell_bulk: Dictionary = main.get("cargo")
		if cargo_sell_bulk.has(ore_id6):
			_fail("KEY_M bulk sell should sell all held ore, got %s" % str(cargo_sell_bulk))
		if Game.credits != 10 + ore_sell * 4:
			_fail("KEY_M bulk sell should pay for all 4 units, got credits %d" % Game.credits)

	# --- 19. _update_hud while dock screen open includes market data ----------
	if not failed:
		main.set("dock_screen_open", true)
		main.set("dock_screen_tab", 4)
		main.call("_update_hud")
		var hud_node: Node = main.get("hud")
		if hud_node != null:
			var hd: Dictionary = hud_node.get("data")
			if not hd.has("dock_screen"):
				_fail("HUD data should include dock_screen while open")
			else:
				var ds: Dictionary = hd.get("dock_screen", {})
				if not ds.has("market"):
					_fail("dock_screen data should include market while on market tab")

	if not failed:
		print("COMMODITY_TRADING_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
