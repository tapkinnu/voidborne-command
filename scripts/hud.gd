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
	# Keep redrawing even if the tree is ever paused (main gates game logic with its own
	# `paused` bool, not get_tree().paused, but this is harmless and future-proof).
	process_mode = Node.PROCESS_MODE_ALWAYS

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

func _sub_status(frac: float) -> Array:
	# Returns [label, color] for a subsystem health fraction (mirrors ship.gd thresholds).
	if frac <= 0.0:
		return ["OFF", Color(1.0, 0.35, 0.3)]
	if frac < 0.4:
		return ["DMG", Color(1.0, 0.78, 0.3)]
	return ["OK", Color(0.45, 1.0, 0.6)]

func _draw_subsystems(x: float, y: float, tgt: Dictionary) -> void:
	# Compact ENG/WPN/SHD strip. The currently focused subsystem gets a '>' marker and
	# a brighter tag so the player can see where their fire is being routed.
	var focus: String = String(tgt.get("sub_focus", ""))
	var defs: Array = [
		["ENG", "engines", float(tgt.get("sub_engine", 1.0))],
		["WPN", "weapons", float(tgt.get("sub_weapon", 1.0))],
		["SHD", "shields", float(tgt.get("sub_shield", 1.0))],
	]
	var col_w: float = 72.0
	for i in range(defs.size()):
		var entry: Array = defs[i]
		var tag: String = String(entry[0])
		var key: String = String(entry[1])
		var frac: float = float(entry[2])
		var st: Array = _sub_status(frac)
		var cx: float = x + float(i) * col_w
		var focused: bool = key == focus
		var tag_col: Color = Color(1.0, 0.95, 0.5) if focused else C_DIM
		var prefix: String = ">" if focused else " "
		_txt(Vector2(cx, y), "%s%s" % [prefix, tag], tag_col, 11)
		_txt(Vector2(cx + 2, y + 13), String(st[0]), Color(st[1]), 11)

func _draw() -> void:
	if data.is_empty():
		return
	# Use the real viewport size: a Control under a CanvasLayer may report size 0 before
	# layout settles, which would push the bottom HUD off-screen.
	var vp: Vector2 = get_viewport_rect().size
	var mode: String = String(data.get("mode", "space"))

	# Top-left: economy / fleet / shipyard
	var service: Dictionary = data.get("service", {})
	var panel_h: float = (132.0 if not service.is_empty() else 114.0) + 16.0
	draw_rect(Rect2(Vector2(8, 8), Vector2(250, panel_h)), C_BG, true)
	_txt(Vector2(16, 28), "VOIDBORNE COMMAND", C_LINE, 14)
	_txt(Vector2(16, 48), "Credits: %d" % int(data.get("credits", 0)), Color(1, 0.85, 0.4), 13)
	var role_str: String = String(data.get("crew_roles", ""))
	if role_str != "":
		_txt(Vector2(16, 64), "Crew: %d %s   Marines: %d" % [int(data.get("crew_pool", 0)), role_str, int(data.get("marine_pool", 0))], C_DIM, 13)
	else:
		_txt(Vector2(16, 64), "Crew: %d   Marines: %d" % [int(data.get("crew_pool", 0)), int(data.get("marine_pool", 0))], C_DIM, 13)
	_txt(Vector2(16, 80), "Fleet: %d   Captured: %d" % [int(data.get("fleet_count", 0)), int(data.get("captured", 0))], C_DIM, 13)
	var order_key: String = String(data.get("fleet_order", "follow"))
	var order_txt: String = order_key.to_upper()
	var order_col: Color = Color(0.56, 1.0, 0.82)
	match order_key:
		"attack":
			order_txt = "ATTACK %s" % String(data.get("fleet_attack_target", "?"))
			order_col = Color(1.0, 0.55, 0.42)
		"defend":
			order_txt = "DEFEND %s" % String(data.get("fleet_defend_target", "?"))
			order_col = Color(0.5, 0.82, 1.0)
		"escort":
			order_col = Color(0.55, 1.0, 0.7)
		"dock":
			order_col = Color(1.0, 0.85, 0.4)
	_txt(Vector2(16, 96), "Order: %s" % order_txt, order_col, 12)
	_txt(Vector2(16, 112), "Shipyard: %s %dcr   Mode: %s" % [String(data.get("shipyard_class", "corvette")).to_upper(), int(data.get("shipyard_cost", 0)), mode.to_upper()], C_DIM, 12)
	if not service.is_empty():
		var svc_cost: int = int(service.get("cost", 0))
		var svc_txt: String = "[H] Repair/refit: %d cr" % svc_cost if svc_cost > 0 else "[H] Repair/refit: nominal"
		_txt(Vector2(16, 128), svc_txt, Color(0.55, 1.0, 0.72), 12)
	# Mouse-aim + control-scheme indicator (bottom of the economy panel).
	var ma_y: float = (144.0 if not service.is_empty() else 128.0)
	var ma_on: bool = bool(data.get("mouse_aim", false))
	var scheme: String = String(data.get("control_scheme", "auto")).to_upper()
	var ma_col: Color = Color(0.5, 1.0, 0.72) if ma_on else C_DIM
	_txt(Vector2(16, ma_y), "MOUSE AIM: %s   [%s]" % ["ON" if ma_on else "OFF", scheme], ma_col, 12)

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
		if bool(data.get("settings_open", false)):
			_draw_settings_overlay(vp)
		elif bool(data.get("paused", false)):
			_draw_pause_overlay(vp)
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
	draw_rect(Rect2(Vector2(tx, 8), Vector2(242, 124)), C_BG, true)
	if tgt.is_empty():
		_txt(Vector2(tx + 12, 30), "NO TARGET  [Tab]", C_DIM, 13)
	else:
		var fcol: Color = FACTION_COL.get(String(tgt.get("faction", "neutral")), Color.WHITE)
		_txt(Vector2(tx + 12, 28), "TGT: %s" % String(tgt.get("name", "?")), fcol, 13)
		_txt(Vector2(tx + 12, 44), "%s  %s" % [String(tgt.get("class", "")).to_upper(), String(tgt.get("faction", "")).to_upper()], C_DIM, 12)
		_bar(Vector2(tx + 12, 52), 218, 12, float(tgt.get("hull_frac", 0.0)), Color(1.0, 0.45, 0.4), "HULL")
		_bar(Vector2(tx + 12, 68), 218, 12, float(tgt.get("shield_frac", 0.0)), Color(0.4, 0.7, 1.0), "SHIELD")
		# Subsystem strip: ENG / WPN / SHD, colored by status, focused one marked with '>'.
		_draw_subsystems(tx + 12, 86, tgt)
		var status: String = "DIST %d" % int(float(tgt.get("dist", 0.0)))
		if bool(tgt.get("disabled", false)):
			status += "  *DISABLED - BOARD [B]*"
		_txt(Vector2(tx + 12, 124), status, Color(1, 0.9, 0.5), 12)

	# Mission panel (top-right, below the target panel)
	_draw_mission_panel(vp)

	# Radar (bottom-right circle)
	_draw_radar(vp)

	# Boarding progress
	var board: Dictionary = data.get("boarding", {})
	if bool(board.get("active", false)):
		var pw: float = 360.0
		var px: float = vp.x * 0.5 - pw * 0.5
		var py: float = vp.y * 0.5 + 40.0
		draw_rect(Rect2(Vector2(px - 8, py - 26), Vector2(pw + 16, 56)), C_BG, true)
		var atk: int = int(board.get("attacker", 0))
		var def: int = int(board.get("defender", 0))
		_txt(Vector2(px, py - 6), "BOARDING %s   ATK: %d  DEF: %d" % [String(board.get("name", "")), atk, def], Color(1, 0.8, 0.4), 14)
		_bar(Vector2(px, py), pw, 18, float(board.get("progress", 0.0)), Color(1.0, 0.6, 0.3), "CAPTURE")

	# Reticle (center)
	draw_arc(vp * 0.5, 12, 0, TAU, 24, Color(0.4, 1.0, 0.7, 0.8), 1.5)
	draw_line(vp * 0.5 - Vector2(20, 0), vp * 0.5 - Vector2(8, 0), C_LINE, 1.0)
	draw_line(vp * 0.5 + Vector2(8, 0), vp * 0.5 + Vector2(20, 0), C_LINE, 1.0)
	if bool(data.get("capture_demo", false)):
		_draw_combat_overlay(vp)

	_draw_messages(vp)
	_draw_prompt(vp)
	if bool(data.get("fleet_menu_open", false)):
		_draw_fleet_menu(vp)
	if bool(data.get("settings_open", false)):
		_draw_settings_overlay(vp)
	elif bool(data.get("paused", false)):
		# Pause banner only when the settings menu isn't open (it shows pause state itself).
		_draw_pause_overlay(vp)
	# System map overlay sits on top of the whole HUD when toggled on (M key).
	if bool(data.get("system_map_open", false)):
		_draw_system_map(vp)

func _draw_system_map(vp: Vector2) -> void:
	# Centered top-down map of the system: stations as labelled squares, other ships as
	# faction-coloured dots, the player as a heading arrow, plus a distance-scale bar.
	var m: Dictionary = data.get("system_map", {})
	var size: float = 600.0
	var origin: Vector2 = Vector2(vp.x * 0.5 - size * 0.5, vp.y * 0.5 - size * 0.5)
	var rect: Rect2 = Rect2(origin, Vector2(size, size))
	draw_rect(rect, Color(0.0, 0.03, 0.06, 0.92), true)
	draw_rect(rect, C_LINE, false, 1.5)
	_txt(origin + Vector2(14, 24), "SYSTEM MAP  (M to close)", C_LINE, 16)

	var stations: Array = m.get("stations", [])
	var pl: Dictionary = m.get("player", {})
	var ships_arr: Array = m.get("ships", [])

	# World-space bounds over every station plus the player, so the whole system fits.
	var minx: float = INF
	var maxx: float = -INF
	var minz: float = INF
	var maxz: float = -INF
	var pts: Array = []
	for st in stations:
		pts.append(Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0))))
	if not pl.is_empty():
		pts.append(Vector2(float(pl.get("x", 0.0)), float(pl.get("z", 0.0))))
	for p in pts:
		var pv: Vector2 = p
		minx = min(minx, pv.x); maxx = max(maxx, pv.x)
		minz = min(minz, pv.y); maxz = max(maxz, pv.y)
	if pts.is_empty():
		minx = -100.0; maxx = 100.0; minz = -100.0; maxz = 100.0
	var cx: float = (minx + maxx) * 0.5
	var cz: float = (minz + maxz) * 0.5
	var spanx: float = max(maxx - minx, 1.0)
	var spanz: float = max(maxz - minz, 1.0)
	var margin: float = 70.0
	var usable: float = size - margin * 2.0
	var scale: float = min(usable / spanx, usable / spanz)
	var center: Vector2 = origin + Vector2(size * 0.5, size * 0.5 + 8.0)

	# Faint grid + center crosshair for orientation.
	draw_line(center - Vector2(usable * 0.5, 0), center + Vector2(usable * 0.5, 0), Color(0.3, 0.7, 0.8, 0.18), 1.0)
	draw_line(center - Vector2(0, usable * 0.5), center + Vector2(0, usable * 0.5), Color(0.3, 0.7, 0.8, 0.18), 1.0)

	# Other ships as small dots.
	for sh in ships_arr:
		var sd: Dictionary = sh
		var wp: Vector2 = (Vector2(float(sd.get("x", 0.0)), float(sd.get("z", 0.0))) - Vector2(cx, cz)) * scale + center
		var scol: Color = FACTION_COL.get(String(sd.get("faction", "neutral")), Color.WHITE)
		draw_circle(wp, 2.5, scol)

	# Stations as labelled squares.
	for st2 in stations:
		var std: Dictionary = st2
		var sp: Vector2 = (Vector2(float(std.get("x", 0.0)), float(std.get("z", 0.0))) - Vector2(cx, cz)) * scale + center
		var fcol: Color = FACTION_COL.get(String(std.get("faction", "neutral")), Color.WHITE)
		var hs: float = 6.0
		draw_rect(Rect2(sp - Vector2(hs, hs), Vector2(hs * 2.0, hs * 2.0)), fcol, true)
		draw_rect(Rect2(sp - Vector2(hs, hs), Vector2(hs * 2.0, hs * 2.0)), fcol.darkened(0.3), false, 1.0)
		_txt(sp + Vector2(10, 4), String(std.get("name", "")), Color(0.85, 0.95, 1.0), 12)

	# Player as a heading arrow (triangle).
	if not pl.is_empty():
		var pp: Vector2 = (Vector2(float(pl.get("x", 0.0)), float(pl.get("z", 0.0))) - Vector2(cx, cz)) * scale + center
		var fwd: Vector2 = Vector2(float(pl.get("fx", 0.0)), float(pl.get("fz", 1.0)))
		if fwd.length() < 0.001:
			fwd = Vector2(0, 1)
		fwd = fwd.normalized()
		var side: Vector2 = Vector2(-fwd.y, fwd.x)
		var pcol: Color = FACTION_COL.get("player", Color(0.4, 1.0, 0.62))
		var tri: PackedVector2Array = PackedVector2Array([
			pp + fwd * 11.0,
			pp - fwd * 7.0 + side * 7.0,
			pp - fwd * 7.0 - side * 7.0,
		])
		draw_colored_polygon(tri, pcol)
		draw_line(pp, pp + fwd * 11.0, pcol.lightened(0.3), 1.0)

	# Distance scale bar (100 world units), drawn bottom-left of the panel.
	var bar_world: float = 100.0
	var bar_px: float = bar_world * scale
	var bar_y: float = origin.y + size - 24.0
	var bar_x: float = origin.x + 24.0
	draw_line(Vector2(bar_x, bar_y), Vector2(bar_x + bar_px, bar_y), C_DIM, 2.0)
	draw_line(Vector2(bar_x, bar_y - 4), Vector2(bar_x, bar_y + 4), C_DIM, 2.0)
	draw_line(Vector2(bar_x + bar_px, bar_y - 4), Vector2(bar_x + bar_px, bar_y + 4), C_DIM, 2.0)
	_txt(Vector2(bar_x, bar_y - 8), "%d u" % int(bar_world), C_DIM, 11)

func _draw_mission_panel(vp: Vector2) -> void:
	# Compact current-mission tracker under the target panel (top-right): title + reward,
	# a state badge, and each objective with a [x]/[ ] checkbox.
	var m: Dictionary = data.get("mission", {})
	if m.is_empty():
		return
	var objs: Array = m.get("objectives", [])
	var w: float = 220.0
	var x: float = vp.x - w - 8.0
	var y: float = 140.0
	var h: float = 50.0 + float(objs.size()) * 16.0
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_BG, true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 1.0)
	_txt(Vector2(x + 10, y + 18), "MISSION  +%d cr" % int(m.get("reward", 0)), C_LINE, 12)
	# State badge.
	var state: String = String(m.get("state", "active"))
	var badge: String = "ACTIVE"
	var badge_col: Color = Color(0.45, 1.0, 0.6)
	match state:
		"complete":
			badge = "COMPLETE"
			badge_col = Color(1.0, 0.85, 0.35)
		"failed":
			badge = "FAILED"
			badge_col = Color(1.0, 0.4, 0.34)
	_txt(Vector2(x + w - 78.0, y + 18), badge, badge_col, 11)
	_txt(Vector2(x + 10, y + 34), String(m.get("title", "")), C_DIM, 12)
	for i in range(objs.size()):
		var od: Dictionary = objs[i]
		var done: bool = bool(od.get("done", false))
		var box: String = "[x]" if done else "[ ]"
		var col: Color = Color(0.45, 1.0, 0.6) if done else C_DIM.darkened(0.15)
		_txt(Vector2(x + 10, y + 50.0 + float(i) * 16.0), "%s %s" % [box, String(od.get("text", ""))], col, 11)

func _draw_fleet_menu(vp: Vector2) -> void:
	# Centered fleet order menu: lists the six orders with their number keys and highlights
	# the standing order in the accent color. Opened/closed with [F]; picked with 1-6 / Esc.
	var rows: Array = [
		["1", "follow", "Follow", "ring formation on flagship"],
		["2", "hold", "Hold", "hold current position"],
		["3", "escort", "Escort", "tight defensive ring, engage threats to flagship"],
		["4", "defend", "Defend tgt", "guard current target"],
		["5", "dock", "Dock", "navigate to station for auto-repair (50% cost)"],
		["6", "attack", "Attack tgt", "focus-fire current target"],
	]
	var w: float = 460.0
	var h: float = 56.0 + float(rows.size()) * 22.0
	var x: float = vp.x * 0.5 - w * 0.5
	var y: float = vp.y * 0.5 - h * 0.5
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.04, 0.07, 0.9), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 1.5)
	_txt(Vector2(x + 16, y + 26), "FLEET ORDERS  (F/Esc to close)", C_LINE, 15)
	var current: String = String(data.get("fleet_order", "follow"))
	for i in range(rows.size()):
		var row: Array = rows[i]
		var key: String = String(row[1])
		var ry: float = y + 50.0 + float(i) * 22.0
		var is_current: bool = key == current
		var col: Color = Color(1.0, 0.85, 0.35) if is_current else C_DIM
		var marker: String = ">" if is_current else " "
		_txt(Vector2(x + 16, ry), "%s[%s] %-11s — %s" % [marker, String(row[0]), String(row[2]), String(row[3])], col, 12)

func _draw_settings_overlay(vp: Vector2) -> void:
	# Interactive settings panel. main.gd feeds the highlighted row via settings_cursor and
	# the current values; navigation (arrows/Enter/digits) happens in main._input. The
	# highlighted row gets a '►' marker and a bright color; other rows are dimmed.
	var w: float = 440.0
	var h: float = 250.0
	var x: float = vp.x * 0.5 - w * 0.5
	var y: float = vp.y * 0.5 - h * 0.5
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.04, 0.07, 0.92), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 1.5)
	_txt(Vector2(x + 16, y + 26), "SETTINGS  (F1/Esc to close)", C_LINE, 15)

	var cursor: int = int(data.get("settings_cursor", 0))
	var ma_on: bool = bool(data.get("mouse_aim", false))
	var paused: bool = bool(data.get("paused", false))
	var scheme: String = String(data.get("control_scheme", "auto"))
	var vol: int = int(data.get("master_volume", 80))
	var graphics: String = String(data.get("graphics_quality", "high"))
	var res_label: String = String(data.get("resolution_label", ""))

	var rows: Array = [
		["Resolution", res_label],
		["Volume", ""],   # custom bar rendered below
		["Graphics", graphics.capitalize()],
		["Pause", ("ON  (P to toggle)" if paused else "OFF  (P to toggle)")],
		["Mouse Aim", ("ON  (` to toggle)" if ma_on else "OFF  (` to toggle)")],
		["Scheme", "%s  (F2 to cycle)" % scheme.to_upper()],
	]
	var lx: float = x + 18.0
	var vx: float = x + 150.0
	var row_y: float = y + 58.0
	var bright: Color = Color(1.0, 0.95, 0.5)
	var dim: Color = Color(0.6, 0.78, 0.9)
	for i in range(rows.size()):
		var entry: Array = rows[i]
		var selected: bool = i == cursor
		var label_col: Color = bright if selected else dim
		var marker: String = "►" if selected else " "
		_txt(Vector2(lx, row_y), "%s %s:" % [marker, String(entry[0])], label_col, 14)
		if i == 1:
			# Volume bar with a numeric percent.
			var bw: float = 160.0
			var bh: float = 12.0
			var bx: float = vx
			var by: float = row_y - 11.0
			draw_rect(Rect2(Vector2(bx, by), Vector2(bw, bh)), Color(0, 0, 0, 0.5), true)
			draw_rect(Rect2(Vector2(bx, by), Vector2(bw * (float(vol) / 100.0), bh)), (bright if selected else Color(0.4, 0.8, 1.0)), true)
			draw_rect(Rect2(Vector2(bx, by), Vector2(bw, bh)), label_col.darkened(0.2), false, 1.0)
			_txt(Vector2(bx + bw + 10.0, row_y), "%d%%" % vol, label_col, 13)
		else:
			_txt(Vector2(vx, row_y), String(entry[1]), label_col, 13)
		row_y += 26.0
	_txt(Vector2(x + 16, y + h - 18.0), "↑↓ select   ←→ change   F1/Esc close", Color(0.62, 0.82, 0.94, 0.85), 12)

func _draw_pause_overlay(vp: Vector2) -> void:
	# Centered banner shown while paused and the settings menu is closed.
	var w: float = 360.0
	var h: float = 60.0
	var x: float = vp.x * 0.5 - w * 0.5
	var y: float = vp.y * 0.5 - h * 0.5
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.03, 0.06, 0.85), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(1.0, 0.85, 0.35, 0.9), false, 2.0)
	_txt(Vector2(x + 60.0, y + 38.0), "PAUSED — press P to resume", Color(1.0, 0.9, 0.5), 18)

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
		var msg: String = String(msgs[i])
		# Failed-assault lines are tinted red so the player can't miss losing their marines.
		var col: Color = Color(0.78, 0.97, 1.0, clamp(alpha, 0.55, 1.0))
		if msg.begins_with("BOARDING FAILED"):
			col = Color(1.0, 0.4, 0.34, clamp(alpha, 0.6, 1.0))
		_txt(Vector2(x, y - float(rows - 1 - i) * 16.0), msg, col, 12)

func _draw_prompt(vp: Vector2) -> void:
	var prompt: String = String(data.get("prompt", ""))
	if prompt == "":
		return
	var w: float = float(prompt.length()) * 7.0 + 24.0
	draw_rect(Rect2(Vector2(vp.x * 0.5 - w * 0.5, vp.y - 60.0), Vector2(w, 24)), C_BG, true)
	_txt(Vector2(vp.x * 0.5 - w * 0.5 + 12, vp.y - 43.0), prompt, Color(0.5, 1.0, 0.7), 13)

func _draw_deck_overlay(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2(vp.x - 300, vp.y - 80), Vector2(292, 72)), C_BG, true)
	_txt(Vector2(vp.x - 290, vp.y - 58), "DECK: %s" % String(data.get("deck_ship", "Corvette [Flagship]")), C_LINE, 14)
	_txt(Vector2(vp.x - 290, vp.y - 40), "Room: %s" % String(data.get("deck_room", "Bridge")), C_DIM, 12)
	_txt(Vector2(vp.x - 290, vp.y - 22), "WASD move  F follow  C exit  R next ship", C_DIM, 12)
