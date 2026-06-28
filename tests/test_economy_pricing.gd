extends SceneTree
# Unit tests for scripts/economy_pricing.gd — deterministic commodity pricing
# and combat credit reward formulas. Exercises price_mult, commodity_prices,
# ship_credit_value, capture_credit_reward, and destroy_salvage_reward.
# Prints ECONOMY_PRICING_TEST_PASS on success.

const EconomyPricing: GDScript = preload("res://scripts/economy_pricing.gd")
const GC: GDScript = preload("res://scripts/game_constants.gd")

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _approx(a: float, b: float, eps: float = 0.01) -> bool:
	return abs(a - b) <= eps

func _initialize() -> void:
	# --- 1. price_mult is deterministic (same inputs -> same output) ----------
	var m1: float = EconomyPricing.price_mult("Halcyon", 0, "ore")
	var m2: float = EconomyPricing.price_mult("Halcyon", 0, "ore")
	if not _approx(m1, m2, 0.0001):
		_fail("price_mult not deterministic: %f vs %f" % [m1, m2])

	# --- 2. price_mult is in range [0.6, 1.8] --------------------------------
	if m1 < 0.6 or m1 > 1.8:
		_fail("price_mult out of range: %f" % m1)

	# --- 3. price_mult varies by station/system/commodity --------------------
	var m3: float = EconomyPricing.price_mult("Aurora Station", 0, "ore")
	var m4: float = EconomyPricing.price_mult("Halcyon", 1, "ore")
	var m5: float = EconomyPricing.price_mult("Halcyon", 0, "alloy")
	# At least one of these should differ from m1 (deterministic hash)
	var all_same: bool = _approx(m1, m3, 0.001) and _approx(m1, m4, 0.001) and _approx(m1, m5, 0.001)
	if all_same:
		_fail("price_mult returns identical values for all input combos")

	# --- 4. commodity_prices returns correct structure ------------------------
	var commodities: Array = [
		{"id": "ore", "name": "Ore", "base_price": 50},
		{"id": "alloy", "name": "Alloy", "base_price": 120},
		{"id": "cells", "name": "Energy Cells", "base_price": 90},
		{"id": "meds", "name": "Med-Supplies", "base_price": 180},
		{"id": "tech", "name": "Tech Parts", "base_price": 350},
	]
	var prices: Dictionary = EconomyPricing.commodity_prices("Halcyon", 0, commodities)
	if prices.size() != 5:
		_fail("commodity_prices should return 5 entries, got %d" % prices.size())

	for cid in prices.keys():
		var pr: Dictionary = prices[cid]
		var buy: int = int(pr.get("buy", 0))
		var sell: int = int(pr.get("sell", 0))
		if buy < 1:
			_fail("commodity %s buy price < 1: %d" % [cid, buy])
		if sell < 1:
			_fail("commodity %s sell price < 1: %d" % [cid, sell])
		if buy < sell:
			_fail("commodity %s buy < sell (%d < %d) — spread violated" % [cid, buy, sell])

	# --- 5. commodity_prices is deterministic --------------------------------
	var prices2: Dictionary = EconomyPricing.commodity_prices("Halcyon", 0, commodities)
	for cid in prices.keys():
		var a: Dictionary = prices[cid]
		var b: Dictionary = prices2[cid]
		if int(a["buy"]) != int(b["buy"]) or int(a["sell"]) != int(b["sell"]):
			_fail("commodity_prices not deterministic for %s" % cid)

	# --- 6. commodity_prices differ between stations -------------------------
	var prices_aurora: Dictionary = EconomyPricing.commodity_prices("Aurora Station", 0, commodities)
	var any_diff: bool = false
	for cid in prices.keys():
		if int(prices[cid]["buy"]) != int(prices_aurora[cid]["buy"]):
			any_diff = true
			break
	if not any_diff:
		_fail("commodity_prices identical between Halcyon and Aurora — no station differentiation")

	# --- 7. sell price is ~85% of buy price ----------------------------------
	for cid in prices.keys():
		var pr: Dictionary = prices[cid]
		var buy: float = float(pr["buy"])
		var sell: float = float(pr["sell"])
		var ratio: float = sell / buy
		if ratio < 0.75 or ratio > 0.95:
			_fail("commodity %s sell/buy ratio %.2f out of expected ~0.85 range" % [cid, ratio])

	# --- 8. empty commodity list returns empty dict --------------------------
	var empty_prices: Dictionary = EconomyPricing.commodity_prices("Halcyon", 0, [])
	if not empty_prices.is_empty():
		_fail("commodity_prices with empty list should return empty dict")

	# --- 9. ship_credit_value returns positive for known classes -------------
	for cls in ["fighter", "corvette", "frigate", "capital", "station"]:
		var val: int = EconomyPricing.ship_credit_value(cls)
		if val <= 0:
			_fail("ship_credit_value('%s') should be positive, got %d" % [cls, val])

	# --- 10. ship values scale with ship size/power --------------------------
	var fighter_val: int = EconomyPricing.ship_credit_value("fighter")
	var corvette_val: int = EconomyPricing.ship_credit_value("corvette")
	var frigate_val: int = EconomyPricing.ship_credit_value("frigate")
	var capital_val: int = EconomyPricing.ship_credit_value("capital")
	if not (fighter_val < corvette_val and corvette_val < frigate_val and frigate_val < capital_val):
		_fail("ship values should scale: fighter < corvette < frigate < capital")

	# --- 11. capture_credit_reward >= MIN_CAPTURE_BOUNTY ---------------------
	for cls in ["fighter", "corvette", "frigate", "capital", "station"]:
		var reward: int = EconomyPricing.capture_credit_reward(cls)
		if reward < GC.MIN_CAPTURE_BOUNTY:
			_fail("capture_credit_reward('%s') %d < MIN_CAPTURE_BOUNTY %d" % [cls, reward, GC.MIN_CAPTURE_BOUNTY])

	# --- 12. capture reward scales with ship value ---------------------------
	var cap_fighter: int = EconomyPricing.capture_credit_reward("fighter")
	var cap_capital: int = EconomyPricing.capture_credit_reward("capital")
	if cap_capital <= cap_fighter:
		_fail("capital capture reward should exceed fighter capture reward")

	# --- 13. capture_credit_reward ~= value * CAPTURE_BOUNTY_RATE ------------
	for cls in ["corvette", "frigate", "capital"]:
		var val: int = EconomyPricing.ship_credit_value(cls)
		var reward: int = EconomyPricing.capture_credit_reward(cls)
		var expected: int = max(GC.MIN_CAPTURE_BOUNTY, int(ceil(float(val) * GC.CAPTURE_BOUNTY_RATE)))
		if reward != expected:
			_fail("capture_credit_reward('%s') %d != expected %d" % [cls, reward, expected])

	# --- 14. destroy_salvage_reward >= MIN_DESTROY_SALVAGE -------------------
	for cls in ["fighter", "corvette", "frigate", "capital", "station"]:
		var salvage: int = EconomyPricing.destroy_salvage_reward(cls)
		if salvage < GC.MIN_DESTROY_SALVAGE:
			_fail("destroy_salvage_reward('%s') %d < MIN_DESTROY_SALVAGE %d" % [cls, salvage, GC.MIN_DESTROY_SALVAGE])

	# --- 15. destroy reward < capture reward for same class ------------------
	for cls in ["corvette", "frigate", "capital"]:
		var cap: int = EconomyPricing.capture_credit_reward(cls)
		var sal: int = EconomyPricing.destroy_salvage_reward(cls)
		if sal >= cap:
			_fail("destroy salvage (%d) >= capture bounty (%d) for '%s'" % [sal, cap, cls])

	# --- 16. destroy_salvage_reward ~= value * DESTROY_SALVAGE_RATE ----------
	for cls in ["corvette", "frigate", "capital"]:
		var val: int = EconomyPricing.ship_credit_value(cls)
		var salvage: int = EconomyPricing.destroy_salvage_reward(cls)
		var expected: int = max(GC.MIN_DESTROY_SALVAGE, int(ceil(float(val) * GC.DESTROY_SALVAGE_RATE)))
		if salvage != expected:
			_fail("destroy_salvage_reward('%s') %d != expected %d" % [cls, salvage, expected])

	# Done
	if not failed:
		print("ECONOMY_PRICING_TEST_PASS")
	quit(1 if failed else 0)
