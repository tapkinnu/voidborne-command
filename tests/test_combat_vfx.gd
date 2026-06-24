extends SceneTree
# Regression test for combat VFX: muzzle flashes, shield impacts, hit decals, and debris.
# Drives the spawn/update paths directly via method calls (no key simulation) and asserts the
# VFX registries grow on the triggering events and are culled when their TTL expires.

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

	# Collect references up front. The destroy test consumes a throwaway hostile so the
	# shield/decal hostile stays valid for the earlier checks.
	var player: Node = main.get("player")
	var hostile: Node = null
	var throwaway: Node = null
	for s in main.ships:
		if not is_instance_valid(s) or s.is_player:
			continue
		if String(s.faction) == "hostile" and String(s.ship_class) != "station":
			if hostile == null:
				hostile = s
			elif throwaway == null:
				throwaway = s
	if player == null:
		_fail("no player ship found")
	if hostile == null:
		_fail("no hostile ship found")

	# 6. All four VFX registries exist on main.
	if not failed:
		if main.get("_muzzle_flashes") == null:
			_fail("_muzzle_flashes array missing on main")
		if main.get("_shield_impacts") == null:
			_fail("_shield_impacts array missing on main")
		if main.get("_debris") == null:
			_fail("_debris array missing on main")

	# 1. Muzzle flashes spawn on fire.
	if not failed:
		main._muzzle_flashes.clear()
		main._fire_projectile(player, hostile)
		if main._muzzle_flashes.size() <= 0:
			_fail("muzzle flashes not spawned on fire")

	# 2. Shield impact spawns on a shielded hit at a precise impact position.
	if not failed:
		hostile.shield = max(float(hostile.shield), 10.0)
		main._shield_impacts.clear()
		main._deal_damage(hostile, 5.0, "", hostile.global_position + Vector3(0, 0, 5))
		if main._shield_impacts.size() <= 0:
			_fail("shield impact not spawned on shield hit")

	# 3. Hit decals spawn on hull damage (shields down).
	if not failed:
		hostile.shield = 0.0
		hostile.set_meta("decal_count", 0)
		main._deal_damage(hostile, 5.0, "", hostile.global_position + Vector3(0, 0, 5))
		if int(hostile.get_meta("decal_count", 0)) <= 0:
			_fail("hit decal not spawned on hull damage")

	# 4. Debris spawns on destroy.
	if not failed:
		var target_ship: Node = throwaway if (throwaway != null and is_instance_valid(throwaway)) else hostile
		var before: int = main._debris.size()
		main._destroy_ship(target_ship)
		if main._debris.size() <= before:
			_fail("debris not spawned on destroy")

	# 5. VFX arrays are culled once TTLs expire (nodes queue_free, arrays drop them).
	if not failed:
		main._update_muzzle_flashes(0.2)
		if main._muzzle_flashes.size() != 0:
			_fail("muzzle flashes not culled after TTL expiry")
		main._update_shield_impacts(0.5)
		if main._shield_impacts.size() != 0:
			_fail("shield impacts not culled after TTL expiry")
		main._update_debris(2.0)
		if main._debris.size() != 0:
			_fail("debris not culled after TTL expiry")

	if not failed:
		print("COMBAT_VFX_TEST_PASS")
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
	quit(1 if failed else 0)
