extends SceneTree

func _initialize() -> void:
    var n_pass := 0
    var n_fail := 0
    var total := 0

    var asset_files := [
        "concord_fighter_a.repacked.glb",
        "concord_fighter_b.repacked.glb",
        "concord_shuttle.repacked.glb",
        "concord_station_module.repacked.glb",
        "sundered_scout.repacked.glb",
        "sundered_flyer.repacked.glb",
        "sundered_mech_light.repacked.glb",
        "sundered_mech_heavy.repacked.glb",
        "sundered_brute.repacked.glb",
        "asteroid_rock_a.repacked.glb",
        "asteroid_rock_b.repacked.glb",
        "asteroid_rock_small.repacked.glb",
        "asteroid_cluster.repacked.glb",
        "planet_gas_giant.repacked.glb",
        "planet_terran.repacked.glb",
        "planet_lava.repacked.glb",
        "planet_ice.repacked.glb",
        "planet_desert.repacked.glb",
        "planet_ocean.repacked.glb",
        "planet_toxic.repacked.glb",
        "planet_ringed.repacked.glb",
        "planet_crystal.repacked.glb",
        "planet_dead.repacked.glb",
        "debris_solar_panel.repacked.glb",
        "debris_structure.repacked.glb",
        "debris_antenna.repacked.glb",
        "debris_rover.repacked.glb",
        "crew_astronaut_a.repacked.glb",
        "crew_astronaut_b.repacked.glb",
        "crew_astronaut_c.repacked.glb",
        "building_house.repacked.glb",
        "building_long.repacked.glb",
        "building_l_shape.repacked.glb",
        "building_dome.repacked.glb",
        "building_pod.repacked.glb",
    ]

    for fname in asset_files:
        total += 1
        var path = "res://assets/models/quaternius_modular/" + fname
        var scene = load(path)
        if scene == null:
            printerr("FAIL: %s -> load returned null" % path)
            n_fail += 1
        else:
            print("PASS: %s -> OK" % fname)
            n_pass += 1

    print('')
    print("============================================================")
    print("QUATERNIUS_ASSETS_TEST_PASS: %d/%d loaded" % [n_pass, total])
    if n_fail > 0:
        printerr("QUATERNIUS_ASSETS_TEST_FAIL: %d failures" % n_fail)
        quit(1)
    else:
        print("QUATERNIUS_ASSETS_TEST_PASS")
        quit(0)
