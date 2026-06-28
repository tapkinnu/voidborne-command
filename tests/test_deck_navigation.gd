extends SceneTree
# Regression test: Deck navigation across multiple rooms / multiple owned ships.
# Usage: godot --headless --path . -s tests/test_deck_navigation.gd
# Prints DECK_NAV_TEST_PASS and exits 0 on success.

var failed: bool = false
var main: Node = null
var deck: Node = null

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _finish() -> void:
	if is_instance_valid(main):
		main.queue_free()
	if not failed:
		print("DECK_NAV_TEST_PASS")
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

	# Enter deck mode
	main.force_deck(true)
	await process_frame

	if not deck.active:
		_fail("deck not active after force_deck(true)")
		_finish()
		return

	# 1. Verify current_room_name returns a non-empty string
	var room_name: String = deck.current_room_name()
	if room_name == "":
		_fail("current_room_name is empty")
		_finish()
		return
	print("Room name: ", room_name)

	# 2. Verify current_ship_label returns non-empty string containing flagship class
	var ship_label: String = deck.current_ship_label()
	if ship_label == "":
		_fail("current_ship_label is empty")
		_finish()
		return
	print("Ship label: ", ship_label)
	if not "corvette" in ship_label.to_lower():
		_fail("ship_label does not contain flagship class 'corvette': " + ship_label)
		_finish()
		return

	# 3. Call cycle_ship (should not crash)
	var idx_before: int = deck.current_ship_index
	deck.cycle_ship()
	print("Cycle ship OK, index: %d -> %d" % [idx_before, deck.current_ship_index])

	# Interiors are now class-specific (card t_32c3321c): a fighter wing has a
	# single-room cockpit, so goto_room(1)/(2) below would be out of range on it.
	# Return to the flagship (index 0, a 3-room corvette) for the room-nav checks.
	var guard: int = 0
	while deck.current_ship_index != 0 and guard < 16:
		deck.cycle_ship()
		guard += 1
	print("Back on flagship: %s (%d rooms)" % [deck.current_ship_label(), deck.ROOM_NAMES.size()])

	# 4. Call goto_room(1) and verify current_room_index changes
	deck.goto_room(1)
	if deck.current_room_index != 1:
		_fail("goto_room(1) did not change room")
		_finish()
		return
	print("Goto room 1 OK - current room: ", deck.current_room_name())

	# 5. Return to room 0
	deck.goto_room(0)
	if deck.current_room_index != 0:
		_fail("goto_room(0) did not return to room 0")
		_finish()
		return
	print("Goto room 0 OK - current room: ", deck.current_room_name())

	# 6. Verify crew nodes exist in current room after room change
	var st: Dictionary = deck.status()
	var crew_count: int = int(st.get("crew_total", 0))
	print("Crew count in current room: ", crew_count)

	# 7. Test goto_room(2) for Marine Barracks
	deck.goto_room(2)
	if deck.current_room_index != 2:
		_fail("goto_room(2) did not change to barracks")
		_finish()
		return
	print("Goto room 2 OK - room: ", deck.current_room_name())
	var st2: Dictionary = deck.status()
	print("Crew count in barracks: ", int(st2.get("crew_total", 0)))

	_finish()
