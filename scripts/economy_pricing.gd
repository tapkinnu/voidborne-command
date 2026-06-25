extends RefCounted
# EconomyPricing: stateless economy math (commodity prices and combat credit rewards).
#
# Extracted from main.gd so the pricing/reward formulas live in one focused, deterministic
# module instead of being scattered through the god-script. Every function is pure: prices
# are seeded from string hashes (so a station always offers the same prices) and reward
# values come from ship class value plus the shared GameConstants knobs. main.gd keeps thin
# _commodity_price_mult / _commodity_prices / _ship_credit_value / _capture_credit_reward /
# _destroy_salvage_reward forwarders so the public API (and tests) are unchanged.
#
# No class_name (avoids circular-import pitfalls); called via preload from main.gd.

const GC: GDScript = preload("res://scripts/game_constants.gd")

# Deterministic per-station/per-system/per-commodity price multiplier in ~0.6x..1.8x.
static func price_mult(station_name: String, sys_index: int, comm_id: String) -> float:
	var seed_val: int = (station_name.hash() ^ (sys_index * 7919) ^ comm_id.hash()) & 0x7FFFFFFF
	var rng_c: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_c.seed = seed_val
	return rng_c.randf_range(0.6, 1.8)

# Returns {commodity_id: {"buy": int, "sell": int}} for every entry in `commodities`. Buy is
# what the player pays per unit; sell is what the station pays to take one (buy >= sell so the
# spread discourages instant round-trip profit at a single station).
static func commodity_prices(station_name: String, sys_index: int, commodities: Array) -> Dictionary:
	var out: Dictionary = {}
	for comm in commodities:
		var cid: String = String(comm.get("id", ""))
		var base_price: int = int(comm.get("base_price", 0))
		var mult: float = price_mult(station_name, sys_index, cid)
		var buy_price: int = max(1, int(round(float(base_price) * mult)))
		var sell_price: int = max(1, int(round(float(buy_price) * 0.85)))
		out[cid] = {"buy": buy_price, "sell": sell_price}
	return out

# Base credit value of a ship class (from the shared ship stat table).
static func ship_credit_value(ship_class: String) -> int:
	return int(Game.class_stat(ship_class, "value"))

# Credit reward for capturing a hostile asset (floored, scales with its value).
static func capture_credit_reward(ship_class: String) -> int:
	return max(GC.MIN_CAPTURE_BOUNTY, int(ceil(float(ship_credit_value(ship_class)) * GC.CAPTURE_BOUNTY_RATE)))

# Credit reward for destroying (salvaging) a hostile asset (floored, scales with its value).
static func destroy_salvage_reward(ship_class: String) -> int:
	return max(GC.MIN_DESTROY_SALVAGE, int(ceil(float(ship_credit_value(ship_class)) * GC.DESTROY_SALVAGE_RATE)))
