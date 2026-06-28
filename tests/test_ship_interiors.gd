extends SceneTree
# Regression test: ship-type-specific crew-deck interiors (card t_32c3321c).
# Usage: godot --headless --path . -s tests/test_ship_interiors.gd
# Prints SHIP_INTERIORS_TEST_PASS and exits 0 on success.
#
# Covers:
#   AC2     — every interior <id>.repacked.glb exists on disk.
#   AC4-AC8 — switching ship class yields the expected room count + ROOM_W/ROOM_D.

var failed: bool = false
var main: Node = null
var deck: Node = null

# class -> [expected_room_count, expected_ROOM_W, expected_ROOM_D]
const EXPECTED: Dictionary = {
	"fighter":  [1, 6.0,  9.0],
	"corvette": [3, 10.0, 15.0],
	"frigate":  [5, 14.0, 21.0],
	"capital":  [7, 18.0, 27.0],
	"station":  [9, 22.0, 33.0],
}

func _fail(msg: String) -> void:
	push_error(msg)
	print("FAIL: ", msg)
	failed = true

func _finish() -> void:
	if is_instance_valid(main):
		main.queue_free()
	if not failed:
		print("SHIP_INTERIORS_TEST_PASS")
	quit(1 if failed else 0)

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_fail("main.tscn failed to load")
		quit(1)
		return
	main = packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	deck = main.find_child("CrewDeck", true, false)
	if deck == null:
		_fail("CrewDeck node not found")
		_finish()
		return

	main.force_deck(true)
	await process_frame

	# --- AC2: every interior GLB exists on disk ---------------------------
	var missing: Array = []
	for cls in deck.MESHY_INTERIOR_GLB.keys():
		for basename in deck.MESHY_INTERIOR_GLB[cls]:
			var path: String = "res://assets/models/meshy_visual_upgrade/%s.repacked.glb" % String(basename)
			if not FileAccess.file_exists(path):
				missing.append(String(basename))
	if missing.is_empty():
		print("AC2 OK: all %d interior GLBs present on disk" % _total_glb_count())
	else:
		_fail("AC2: missing %d interior GLB(s): %s" % [missing.size(), ", ".join(missing)])

	# --- AC4-AC8: per-class room counts + dimensions ----------------------
	for cls in EXPECTED.keys():
		var spec: Array = EXPECTED[cls]
		var want_count: int = int(spec[0])
		var want_w: float = float(spec[1])
		var want_d: float = float(spec[2])
		# Drive the real switch path used by the game.
		deck.set_ship_list([{"name": "TestShip", "class": cls}])
		await process_frame

		if deck.current_class != cls:
			_fail("%s: current_class is '%s', expected '%s'" % [cls, deck.current_class, cls])
			continue
		var got_count: int = deck.ROOM_NAMES.size()
		if got_count != want_count:
			_fail("%s: room count is %d, expected %d" % [cls, got_count, want_count])
			continue
		if deck.ROOM_CENTERS.size() != want_count:
			_fail("%s: ROOM_CENTERS size %d != %d" % [cls, deck.ROOM_CENTERS.size(), want_count])
			continue
		if deck.ROOM_BOUNDARIES.size() != max(0, want_count - 1):
			_fail("%s: ROOM_BOUNDARIES size %d != %d" % [cls, deck.ROOM_BOUNDARIES.size(), want_count - 1])
			continue
		if not is_equal_approx(deck.ROOM_W, want_w):
			_fail("%s: ROOM_W is %f, expected %f" % [cls, deck.ROOM_W, want_w])
			continue
		if not is_equal_approx(deck.ROOM_D, want_d):
			_fail("%s: ROOM_D is %f, expected %f" % [cls, deck.ROOM_D, want_d])
			continue
		# Geometry must actually be built (Meshy holders and/or procedural rooms).
		var room_children: int = deck._room_container.get_child_count()
		if room_children <= 0:
			_fail("%s: no room geometry built" % cls)
			continue
		print("AC ok: %s -> %d rooms, ROOM_W=%.0f ROOM_D=%.0f (room nodes=%d)" % [
			cls, got_count, deck.ROOM_W, deck.ROOM_D, room_children])

	_finish()

func _total_glb_count() -> int:
	var n: int = 0
	for cls in deck.MESHY_INTERIOR_GLB.keys():
		n += deck.MESHY_INTERIOR_GLB[cls].size()
	return n
