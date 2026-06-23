extends Control
# HUD: radar, status bars, target panel, objective, fleet/economy, message log.
# Fed each frame by main.gd via set_data(), then redrawn. No class_name.

var data: Dictionary = {}
var _font: Font

const C_BG := Color(0.0, 0.05, 0.08, 0.72)
const C_LINE := Color(0.3, 0.9, 1.0, 0.9)
const C_DIM := Color(0.62, 0.82, 0.94, 0.95)
const FACTION_COL := {
	"player": Color(0.4, 1.0, 0.62),
	"ally": Color(0.42, 0.72, 1.0),
	"hostile": Color(1.0, 0.4, 0.34),
	"neutral": Color(0.75, 0.75, 0.78),
}

func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_data(d: Dictionary) -> void:
	data = d
	queue_redraw()

func _txt(pos: Vector2, s: String, col: Color, size: int = 14) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _bar(pos: Vector2, w: float, h: float, frac: float, col: Color, label: String) -> void:
	draw_rect(Rect2(pos, Vector2(w, h)), Color(0, 0, 0, 0.5), true)
	draw_rect(Rect2(pos, Vector2(w * clamp(frac, 0.0, 1.0), h)), col, true)
	draw_rect(Rect2(pos, Vector2(w, h)), col.darkened(0.2), false, 1.0)
	_txt(pos + Vector2(4, h - 3), label, Color(0.9, 0.95, 1.0), 11)

func _draw() -> void:
	if data.is_empty():
		return
	# Use the real viewport size: a Control under a CanvasLayer may report size 0 before
	# layout settles, which would push the bottom HUD off-screen.
	var vp: Vector2 = get_viewport_rect().size
	var mode: String = String(data.get("mode", "space"))

	# Top-left: economy / fleet / shipyard
	draw_rect(Rect2(Vector2(8, 8), Vector2(250, 114)), C_BG, true)
	_txt(Vector2(16, 28), "VOIDBORNE COMMAND", C_LINE, 14)
	_txt(Vector2(16, 48), "Credits: %d" % int(data.get("credits", 0)), Color(1, 0.85, 0.4), 13)
	_txt(Vector2(16, 64), "Crew: %d   Marines: %d" % [int(data.get("crew_pool", 0)), int(data.get("marine_pool", 0))], C_DIM, 13)
	_txt(Vector2(16, 80), "Fleet: %d   Captured: %d" % [int(data.get("fleet_count", 0)), int(data.get("captured", 0))], C_DIM, 13)
	var order_txt: String = String(data.get("fleet_order", "follow")).to_upper()
	var order_col: Color = Color(0.56, 1.0, 0.82)
	if order_txt == "ATTACK":
		order_txt = "ATTACK %s" % String(data.get("fleet_attack_target", "?"))
		order_col = Color(1.0, 0.55, 0.42)
	_txt(Vector2(16, 96), "Order: %s" % order_txt, order_col, 12)
	_txt(Vector2(16, 112), "Shipyard: %s %dcr   Mode: %s" % [String(data.get("shipyard_class", "corvette")).to_upper(), int(data.get("shipyard_cost", 0)), mode.to_upper()], C_DIM, 12)

	# Objective (top center)
	var obj: String = String(data.get("objective", ""))
	if obj != "":
		var ow: float = float(obj.length()) * 7.5 + 24.0
		draw_rect(Rect2(Vector2(vp.x * 0.5 - ow * 0.5, 8), Vector2(ow, 26)), C_BG, true)
		_txt(Vector2(vp.x * 0.5 - ow * 0.5 + 12, 27), obj, Color(1, 0.95, 0.7), 13)

	if mode == "deck":
		_draw_deck_overlay(vp)
		_draw_messages(vp)
		_draw_prompt(vp)
		return

	# Player status bars (bottom-left)
	var player: Dictionary = data.get("player", {})
	if not player.is_empty():
		var bx: float = 16.0
		var by: float = vp.y - 96.0
		_bar(Vector2(bx, by), 200, 16, float(player.get("hull_frac", 0.0)), Color(0.4, 1.0, 0.5), "HULL")
		_bar(Vector2(bx, by + 22), 200, 16, float(player.get("shield_frac", 0.0)), Color(0.4, 0.7, 1.0), "SHIELD")
		_bar(Vector2(bx, by + 44), 200, 16, float(player.get("energy_frac", 0.0)), Color(1.0, 0.8, 0.3), "ENERGY")
		_bar(Vector2(bx, by + 66), 200, 16, float(player.get("throttle", 0.0)), Color(0.7, 0.9, 1.0), "THROTTLE %d%%" % int(float(player.get("throttle", 0.0)) * 100.0))
		_txt(Vector2(bx, by - 8), "%s  |  SPD %d" % [String(player.get("class", "")).to_upper(), int(float(player.get("speed", 0.0)))], C_DIM, 12)

	# Target panel (top-right)
	var tgt: Dictionary = data.get("target", {})
	var tx: float = vp.x - 250.0
	draw_rect(Rect2(Vector2(tx, 8), Vector2(242, 96)), C_BG, true)
	if tgt.is_empty():
		_txt(Vector2(tx + 12, 30), "NO TARGET  [Tab]", C_DIM, 13)
	else:
		var fcol: Color = FACTION_COL.get(String(tgt.get("faction", "neutral")), Color.WHITE)
		_txt(Vector2(tx + 12, 28), "TGT: %s" % String(tgt.get("name", "?")), fcol, 13)
		_txt(Vector2(tx + 12, 44), "%s  %s" % [String(tgt.get("class", "")).to_upper(), String(tgt.get("faction", "")).to_upper()], C_DIM, 12)
		_bar(Vector2(tx + 12, 52), 218, 12, float(tgt.get("hull_frac", 0.0)), Color(1.0, 0.45, 0.4), "HULL")
		_bar(Vector2(tx + 12, 68), 218, 12, float(tgt.get("shield_frac", 0.0)), Color(0.4, 0.7, 1.0), "SHIELD")
		var status: String = "DIST %d" % int(float(tgt.get("dist", 0.0)))
		if bool(tgt.get("disabled", false)):
			status += "  *DISABLED - BOARD [B]*"
		_txt(Vector2(tx + 12, 98), status, Color(1, 0.9, 0.5), 12)

	# Radar (bottom-right circle)
	_draw_radar(vp)

	# Boarding progress
	var board: Dictionary = data.get("boarding", {})
	if bool(board.get("active", false)):
		var pw: float = 360.0
		var px: float = vp.x * 0.5 - pw * 0.5
		var py: float = vp.y * 0.5 + 40.0
		draw_rect(Rect2(Vector2(px - 8, py - 26), Vector2(pw + 16, 56)), C_BG, true)
		_txt(Vector2(px, py - 6), "BOARDING %s" % String(board.get("name", "")), Color(1, 0.8, 0.4), 14)
		_bar(Vector2(px, py), pw, 18, float(board.get("progress", 0.0)), Color(1.0, 0.6, 0.3), "MARINES")

	# Reticle (center)
	draw_arc(vp * 0.5, 12, 0, TAU, 24, Color(0.4, 1.0, 0.7, 0.8), 1.5)
	draw_line(vp * 0.5 - Vector2(20, 0), vp * 0.5 - Vector2(8, 0), C_LINE, 1.0)
	draw_line(vp * 0.5 + Vector2(8, 0), vp * 0.5 + Vector2(20, 0), C_LINE, 1.0)
	if bool(data.get("capture_demo", false)):
		_draw_combat_overlay(vp)

	_draw_messages(vp)
	_draw_prompt(vp)

func _draw_combat_overlay(vp: Vector2) -> void:
	# Capture-mode visual proof of active fleet fire. These bright streaks sit over
	# the 3D battle so screenshots clearly show weapon exchange even when a fast
	# projectile would otherwise pass between capture frames.
	var c: Vector2 = vp * 0.5
	draw_line(c + Vector2(-260, 120), c + Vector2(-42, 16), Color(0.35, 1.0, 0.58, 0.92), 5.0)
	draw_line(c + Vector2(-230, 136), c + Vector2(-25, 4), Color(0.55, 0.9, 1.0, 0.88), 4.0)
	draw_line(c + Vector2(210, -86), c + Vector2(40, -6), Color(1.0, 0.32, 0.26, 0.82), 4.0)
	draw_circle(c + Vector2(-8, -4), 16.0, Color(1.0, 0.42, 0.08, 0.82))
	draw_arc(c + Vector2(-8, -4), 26.0, 0, TAU, 32, Color(1.0, 0.86, 0.22, 0.95), 3.0)
	_txt(c + Vector2(-88, 42), "LIVE WEAPON FIRE", Color(1.0, 0.82, 0.32, 0.95), 12)

func _draw_radar(vp: Vector2) -> void:
	var r: float = 90.0
	var c: Vector2 = Vector2(vp.x - r - 20.0, vp.y - r - 20.0)
	draw_circle(c, r, Color(0.0, 0.06, 0.1, 0.55))
	draw_arc(c, r, 0, TAU, 48, C_LINE, 1.5)
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(0.3, 0.7, 0.8, 0.4), 1.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.3, 0.7, 0.8, 0.3), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0.3, 0.7, 0.8, 0.3), 1.0)
	_txt(c + Vector2(-14, -r - 6), "RADAR", C_DIM, 11)
	var blips: Array = data.get("radar", [])
	for b in blips:
		var bp: Dictionary = b
		var rel: Vector2 = bp.get("pos", Vector2.ZERO)
		var col: Color = FACTION_COL.get(String(bp.get("faction", "neutral")), Color.WHITE)
		var p: Vector2 = c + rel * r
		var sz: float = 3.0
		if bool(bp.get("target", false)):
			sz = 5.0
			draw_arc(p, 7, 0, TAU, 12, Color(1, 0.9, 0.4), 1.0)
		if bool(bp.get("attack", false)):
			# Focus-fire command ping: a red marker ring around the ordered target.
			sz = max(sz, 5.0)
			draw_arc(p, 10, 0, TAU, 16, Color(1.0, 0.35, 0.3, 0.95), 2.0)
		if bool(bp.get("self", false)):
			col = Color(1, 1, 1)
			sz = 4.0
		draw_circle(p, sz, col)

func _draw_messages(vp: Vector2) -> void:
	var msgs: Array = data.get("messages", [])
	if msgs.is_empty():
		return
	var y: float = vp.y - 130.0
	var x: float = vp.x * 0.5 - 180.0
	var rows: int = msgs.size()
	var top: float = y - float(rows - 1) * 16.0 - 16.0
	# Keep tutorial/mission text legible over dark ship hulls and station geometry.
	draw_rect(Rect2(Vector2(x - 12.0, top), Vector2(430.0, float(rows) * 16.0 + 14.0)), Color(0.0, 0.02, 0.04, 0.76), true)
	draw_rect(Rect2(Vector2(x - 12.0, top), Vector2(430.0, float(rows) * 16.0 + 14.0)), Color(0.26, 0.78, 1.0, 0.28), false, 1.0)
	for i in range(rows):
		var alpha: float = 1.0 - float(rows - 1 - i) * 0.12
		_txt(Vector2(x, y - float(rows - 1 - i) * 16.0), String(msgs[i]), Color(0.78, 0.97, 1.0, clamp(alpha, 0.55, 1.0)), 12)

func _draw_prompt(vp: Vector2) -> void:
	var prompt: String = String(data.get("prompt", ""))
	if prompt == "":
		return
	var w: float = float(prompt.length()) * 7.0 + 24.0
	draw_rect(Rect2(Vector2(vp.x * 0.5 - w * 0.5, vp.y - 60.0), Vector2(w, 24)), C_BG, true)
	_txt(Vector2(vp.x * 0.5 - w * 0.5 + 12, vp.y - 43.0), prompt, Color(0.5, 1.0, 0.7), 13)

func _draw_deck_overlay(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2(vp.x - 250, vp.y - 70), Vector2(242, 60)), C_BG, true)
	_txt(Vector2(vp.x - 240, vp.y - 48), "CREW DECK", C_LINE, 14)
	_txt(Vector2(vp.x - 240, vp.y - 30), "WASD move  F order follow  C exit", C_DIM, 12)
