#!/usr/bin/env python3
"""verify_save_load.py — producer-side schema policy check for Voidborne Command saves.

This mirrors the GDScript `_validate_save` policy in `scripts/main.gd` independently so
schema drift is caught even when the engine is not run. It validates a versioned JSON
save payload and, with no arguments, runs a built-in battery of accept/reject cases.

Usage:
    python3 tools/verify_save_load.py              # run the self-test battery
    python3 tools/verify_save_load.py SAVE.json    # validate a single save file

Pure stdlib; no dependencies. Prints `VOIDBORNE_SAVE_LOAD_VERIFY: PASS` and exits 0 when
every expected case behaves correctly; otherwise prints a FAIL line and exits non-zero.
"""

import json
import sys

GAME_ID = "voidborne_command"
CURRENT_VERSION = 2
SHIP_CLASSES = {"fighter", "corvette", "frigate", "capital", "station"}
ECONOMY_KEYS = ("credits", "crew_pool", "marine_pool", "captured_count", "purchased_count")
SHIP_REQUIRED = ("ship_name", "ship_class", "faction")


def _validate_vec3(v):
    if not isinstance(v, list):
        return "not an array"
    if len(v) != 3:
        return "needs 3 elements"
    for n in v:
        # bool is a subclass of int in Python; reject it explicitly as non-numeric.
        if isinstance(n, bool) or not isinstance(n, (int, float)):
            return "non-numeric"
    return ""


def validate(data):
    """Return "" when the payload is acceptable, else a human-readable reason."""
    if not isinstance(data, dict):
        return "corrupt or non-object save"
    if data.get("game_id") != GAME_ID:
        return "not a Voidborne save"
    if "version" not in data:
        return "missing version"
    ver = data["version"]
    if isinstance(ver, bool) or not isinstance(ver, (int, float)):
        return "invalid version"
    if float(ver) != float(int(ver)):
        return "invalid version"
    ver = int(ver)
    if ver < 1:
        return "invalid version"
    if ver > CURRENT_VERSION:
        return "future version (v%d > v%d) - update the game" % (ver, CURRENT_VERSION)
    econ = data.get("economy")
    if not isinstance(econ, dict):
        return "missing economy section"
    for key in ECONOMY_KEYS:
        if key not in econ:
            return "missing economy.%s" % key
    ships = data.get("ships")
    if not isinstance(ships, list):
        return "missing ships section"
    player_count = 0
    for entry in ships:
        if not isinstance(entry, dict):
            return "invalid ship entry"
        for key in SHIP_REQUIRED:
            if key not in entry:
                return "ship missing %s" % key
        if entry["ship_class"] not in SHIP_CLASSES:
            return "unknown ship_class '%s'" % entry["ship_class"]
        perr = _validate_vec3(entry.get("pos"))
        if perr:
            return "ship %s pos %s" % (entry.get("ship_name", "?"), perr)
        rerr = _validate_vec3(entry.get("rot"))
        if rerr:
            return "ship %s rot %s" % (entry.get("ship_name", "?"), rerr)
        # Subsystem health is optional (backward compatible with v1 saves). When present
        # each value must be a 0..1 float; absent values default to 1.0 on load.
        for sub_key in ("sub_engine", "sub_weapon", "sub_shield"):
            if sub_key in entry:
                val = entry[sub_key]
                if isinstance(val, bool) or not isinstance(val, (int, float)):
                    return "ship %s %s non-numeric" % (entry.get("ship_name", "?"), sub_key)
                if val < 0.0 or val > 1.0:
                    return "ship %s %s out of range" % (entry.get("ship_name", "?"), sub_key)
        # Marine garrison is optional (backward compatible). When present it must be a
        # non-negative number; absent values default to 0 on load.
        if "marine_garrison" in entry:
            garr = entry["marine_garrison"]
            if isinstance(garr, bool) or not isinstance(garr, (int, float)):
                return "ship %s marine_garrison non-numeric" % (entry.get("ship_name", "?"))
            if garr < 0:
                return "ship %s marine_garrison negative" % (entry.get("ship_name", "?"))
        if entry.get("is_player"):
            player_count += 1
    if player_count == 0:
        return "no player flagship in save"
    return ""


def _minimal_valid():
    return {
        "game_id": GAME_ID,
        "version": CURRENT_VERSION,
        "economy": {k: 0 for k in ECONOMY_KEYS},
        "shipyard_index": 0,
        "fleet_order": "follow",
        "fleet_attack_target": "",
        "target": "",
        "ships": [
            {
                "ship_name": "Captain",
                "ship_class": "corvette",
                "faction": "player",
                "is_player": True,
                "manned": True,
                "crew_assigned": 3,
                "hull": 160.0,
                "max_hull": 160.0,
                "shield": 90.0,
                "max_shield": 90.0,
                "energy": 140.0,
                "max_energy": 140.0,
                "disabled": False,
                "destroyed": False,
                "ai_state": "follow",
                "pos": [0.0, 4.0, 80.0],
                "rot": [0.0, 0.0, 0.0],
            }
        ],
    }


def _self_test():
    # Each case: (label, payload, expect_ok). expect_ok=True means validate must return "".
    cases = []

    cases.append(("minimal current payload", _minimal_valid(), True))

    not_dict = ["not", "a", "dict"]
    cases.append(("non-object save", not_dict, False))

    wrong_id = _minimal_valid()
    wrong_id["game_id"] = "some_other_game"
    cases.append(("wrong game id", wrong_id, False))

    future = _minimal_valid()
    future["version"] = CURRENT_VERSION + 1
    cases.append(("future version", future, False))

    integer_float = _minimal_valid()
    integer_float["version"] = float(CURRENT_VERSION)
    cases.append(("integer-valued float version", integer_float, True))

    fractional = _minimal_valid()
    fractional["version"] = CURRENT_VERSION + 0.5
    cases.append(("fractional version", fractional, False))

    no_ver = _minimal_valid()
    del no_ver["version"]
    cases.append(("missing version", no_ver, False))

    no_econ = _minimal_valid()
    del no_econ["economy"]
    cases.append(("missing economy section", no_econ, False))

    partial_econ = _minimal_valid()
    del partial_econ["economy"]["credits"]
    cases.append(("missing economy field", partial_econ, False))

    no_ships = _minimal_valid()
    del no_ships["ships"]
    cases.append(("missing ships section", no_ships, False))

    bad_ship = _minimal_valid()
    bad_ship["ships"] = ["not-a-dict"]
    cases.append(("invalid ship entry", bad_ship, False))

    missing_field = _minimal_valid()
    del missing_field["ships"][0]["faction"]
    cases.append(("ship missing field", missing_field, False))

    bad_class = _minimal_valid()
    bad_class["ships"][0]["ship_class"] = "dreadnought"
    cases.append(("unknown ship class", bad_class, False))

    bad_pos = _minimal_valid()
    bad_pos["ships"][0]["pos"] = [1.0, 2.0]
    cases.append(("malformed position array", bad_pos, False))

    bad_pos2 = _minimal_valid()
    bad_pos2["ships"][0]["pos"] = [1.0, "x", 3.0]
    cases.append(("non-numeric position", bad_pos2, False))

    no_player = _minimal_valid()
    no_player["ships"][0]["is_player"] = False
    cases.append(("no player flagship", no_player, False))

    # A richer valid payload with several ships and a captured station.
    rich = _minimal_valid()
    rich["ships"].append({
        "ship_name": "Kryos Relay",
        "ship_class": "station",
        "faction": "player",
        "is_player": False,
        "manned": False,
        "crew_assigned": 0,
        "hull": 800.0,
        "max_hull": 1600.0,
        "shield": 0.0,
        "max_shield": 600.0,
        "energy": 400.0,
        "max_energy": 800.0,
        "disabled": False,
        "destroyed": False,
        "ai_state": "guard",
        "pos": [-95.0, -10.0, -185.0],
        "rot": [0.0, 1.5, 0.0],
    })
    cases.append(("rich multi-ship payload", rich, True))

    # Subsystem health round-trip: a save WITH subsystem fields in 0..1 range is accepted.
    with_subs = _minimal_valid()
    with_subs["ships"][0]["sub_engine"] = 0.0
    with_subs["ships"][0]["sub_weapon"] = 0.55
    with_subs["ships"][0]["sub_shield"] = 1.0
    cases.append(("ship with subsystem fields", with_subs, True))

    # Backward compatibility: a v1 save WITHOUT subsystem fields is still accepted.
    without_subs = _minimal_valid()
    for k in ("sub_engine", "sub_weapon", "sub_shield"):
        without_subs["ships"][0].pop(k, None)
    cases.append(("v1 save without subsystem fields", without_subs, True))

    # Out-of-range subsystem health must be rejected.
    bad_sub = _minimal_valid()
    bad_sub["ships"][0]["sub_engine"] = 1.5
    cases.append(("subsystem health out of range", bad_sub, False))

    neg_sub = _minimal_valid()
    neg_sub["ships"][0]["sub_shield"] = -0.2
    cases.append(("negative subsystem health", neg_sub, False))

    nonnum_sub = _minimal_valid()
    nonnum_sub["ships"][0]["sub_weapon"] = "broken"
    cases.append(("non-numeric subsystem health", nonnum_sub, False))

    # Marine garrison round-trip: a save WITH a non-negative garrison is accepted.
    with_garrison = _minimal_valid()
    with_garrison["ships"][0]["marine_garrison"] = 4
    cases.append(("ship with marine garrison", with_garrison, True))

    # Backward compatibility: a save WITHOUT a garrison field is still accepted.
    without_garrison = _minimal_valid()
    without_garrison["ships"][0].pop("marine_garrison", None)
    cases.append(("save without marine garrison", without_garrison, True))

    # A negative garrison must be rejected.
    neg_garrison = _minimal_valid()
    neg_garrison["ships"][0]["marine_garrison"] = -3
    cases.append(("negative marine garrison", neg_garrison, False))

    # A non-numeric garrison must be rejected.
    nonnum_garrison = _minimal_valid()
    nonnum_garrison["ships"][0]["marine_garrison"] = "platoon"
    cases.append(("non-numeric marine garrison", nonnum_garrison, False))

    # Round-trip through JSON text to mimic the on-disk path.
    failures = []
    for label, payload, expect_ok in cases:
        try:
            text = json.dumps(payload)
            reloaded = json.loads(text)
        except (TypeError, ValueError) as exc:
            failures.append("%s: could not serialize/parse test payload (%s)" % (label, exc))
            continue
        reason = validate(reloaded)
        ok = (reason == "")
        if ok != expect_ok:
            if expect_ok:
                failures.append("%s: expected ACCEPT but rejected with '%s'" % (label, reason))
            else:
                failures.append("%s: expected REJECT but it was accepted" % label)

    # Also confirm genuinely corrupt JSON text is caught as a parse failure upstream.
    try:
        json.loads("{ this is : not json ]")
        failures.append("corrupt JSON text: expected a parse error but none was raised")
    except ValueError:
        pass

    if failures:
        for f in failures:
            print("VOIDBORNE_SAVE_LOAD_VERIFY: FAIL - %s" % f)
        return 1
    print("VOIDBORNE_SAVE_LOAD_VERIFY: PASS (%d cases)" % len(cases))
    return 0


def _validate_file(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        print("VOIDBORNE_SAVE_LOAD_VERIFY: FAIL - file not found: %s" % path)
        return 1
    except ValueError as exc:
        print("VOIDBORNE_SAVE_LOAD_VERIFY: FAIL - corrupt JSON in %s (%s)" % (path, exc))
        return 1
    reason = validate(data)
    if reason:
        print("VOIDBORNE_SAVE_LOAD_VERIFY: FAIL - %s (%s)" % (reason, path))
        return 1
    print("VOIDBORNE_SAVE_LOAD_VERIFY: PASS (%s is a valid v%d save)" % (path, data.get("version")))
    return 0


def main(argv):
    if len(argv) > 1:
        return _validate_file(argv[1])
    return _self_test()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
