extends SceneTree
# Static in-engine contract for crew/marine avatars: the deck must build actual
# multi-part humanoids with named anatomy, not anonymous pill markers.

var failed: bool = false

func _fail(msg: String) -> void:
	push_error(msg)
	failed = true

func _initialize() -> void:
	var deck_script: Script = load("res://scripts/crew_deck.gd")
	if deck_script == null:
		_fail("crew_deck.gd failed to load")
		quit(1)
		return
	var deck: Node = deck_script.new()
	var humanoid: Node3D = deck.call("_build_humanoid", Color(0.4, 0.8, 1.0))
	root.add_child(humanoid)

	for required in ["Torso", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]:
		if humanoid.get_node_or_null(required) == null:
			_fail("humanoid missing named anatomy node: %s" % required)

	if not failed:
		var left_arm: Node3D = humanoid.get_node("LeftArm")
		var right_arm: Node3D = humanoid.get_node("RightArm")
		var left_leg: Node3D = humanoid.get_node("LeftLeg")
		var right_leg: Node3D = humanoid.get_node("RightLeg")
		if left_arm.position.x >= -0.25 or right_arm.position.x <= 0.25:
			_fail("arms are not visibly separated from torso")
		if left_leg.position.x >= -0.08 or right_leg.position.x <= 0.08:
			_fail("legs are not visibly separated from torso")
		if humanoid.get_child_count() < 8:
			_fail("humanoid needs at least 8 mesh/detail parts for screenshot readability")

	if not failed:
		print("CREW_HUMANOID_TEST_PASS")
	if is_instance_valid(humanoid):
		root.remove_child(humanoid)
		humanoid.free()
	if is_instance_valid(deck):
		deck.free()
	quit(1 if failed else 0)
