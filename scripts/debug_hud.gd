extends Node
# DebugHud: developer overlay toggled with F11. Shows ship state at a glance.
# Autoload singleton, creates its own Control node at runtime.

var _visible: bool = false
var _control: Control
var _label: Label
var _background: ColorRect
var _smoothed_fps: float = 0.0
const BG_COLOR := Color(0.0, 0.0, 0.0, 0.9)
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)

func _ready() -> void:
	# Create the Control node for rendering
	_control = Control.new()
	_control.process_mode = Node.PROCESS_MODE_ALWAYS
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Background panel
	_background = ColorRect.new()
	_background.color = BG_COLOR
	_background.position = Vector2(12, 12)
	_background.size = Vector2(240, 130)
	_control.add_child(_background)
	
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_font_size_override("font_size", 14)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_control.add_child(_label)
	
	# Add the control to the viewport scene tree
	get_tree().root.add_child(_control)
	_control.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_F11:
			_toggle_visibility()

func _toggle_visibility() -> void:
	_visible = not _visible
	if _visible:
		_control.show()
	else:
		_control.hide()

func _process(delta: float) -> void:
	if not _visible:
		return
	
	# Smooth FPS update
	var current_fps: float = Engine.get_frames_per_second()
	_smoothed_fps = _smoothed_fps * 0.9 + current_fps * 0.1
	
	_update_display()

func _update_display() -> void:
	var lines: Array = []
	
	# Ship: <class name> - <ship display name>
	var player_ship: Node3D = get_tree().get_root().get_node_or_null("Main/player")
	if is_instance_valid(player_ship):
		var ship_class: String = ""
		var ship_name: String = ""
		if "ship_class" in player_ship:
			ship_class = str(player_ship.ship_class)
		if "ship_name" in player_ship:
			ship_name = str(player_ship.ship_name)
		lines.append("Ship:      %s - %s" % [ship_class, ship_name])
		
		# Position: (x, y, z)
		var pos: Vector3 = player_ship.global_position
		lines.append("Position:  (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z])
	else:
		lines.append("Ship:      (no player)")
		lines.append("Position:  (-, -, -)")
	
	# Room: <current crew-deck room name>
	var main_node: Node = get_tree().get_root().get_node_or_null("Main")
	var room_name: String = ""
	if is_instance_valid(main_node) and main_node.has_method("get"):
		var deck = main_node.get("deck")
		if is_instance_valid(deck) and deck.has_method("current_room_name"):
			room_name = String(deck.current_room_name())
	lines.append("Room:      %s" % (room_name if room_name != "" else "(not on deck)"))
	
	# Crew: <available crew count> / <marine count>
	var crew_count: int = Game.crew_pool
	var marine_count: int = Game.marine_pool
	lines.append("Crew:      %d / %d" % [crew_count, marine_count])
	
	# Credits: <Game.credits>
	lines.append("Credits:   %d" % Game.credits)
	
	# FPS: <smoothed FPS, 1-decimal integer>
	lines.append("FPS:       %d" % int(_smoothed_fps))
	
	_label.text = "\n".join(lines)

# Public getter for testing
func get_control_node() -> Control:
	return _control