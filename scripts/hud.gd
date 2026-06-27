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

# Marine count line, annotated with the wounded count when any marine is injured.
func _marines_str(data: Dictionary) -> String:
	var pool: int = int(data.get("marine_pool", 0))
	var wounded: int = int(data.get("marine_wounded", 0))
	if wounded > 0:
		return "Marines: %d (W:%d)" % [pool, wounded]
	return "Marines: %d" % pool

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
	var panel_h: float = (148.0 if not service.is_empty() else 130.0) + 16.0
	draw_rect(Rect2(Vector2(8, 8), Vector2(250, panel_h)), C_BG, true)
	_txt(Vector2(16, 28), "VOIDBORNE COMMAND", C_LINE, 14)
	_txt(Vector2(16, 48), "Credits: %d   Cargo: %d/%d" % [int(data.get("credits", 0)), int(data.get("cargo_used", 0)), int(data.get("cargo_capacity", 0))], Color(1, 0.85, 0.4), 13)
	var role_str: String = String(data.get("crew_roles", ""))
	if role_str != "":
		_txt(Vector2(16, 64), "Crew: %d %s   %s" % [int(data.get("crew_pool", 0)), role_str, _marines_str(data)], C_DIM, 13)
	else:
		_txt(Vector2(16, 64), "Crew: %d   %s" % [int(data.get("crew_pool", 0)), _marines_str(data)], C_DIM, 13)
	var wing_counts: String = String(data.get("wing_counts", ""))
	var fleet_line: String = "Fleet: %d   Captured: %d" % [int(data.get("fleet_count", 0)), int(data.get("captured", 0))]
	if wing_counts != "":
		fleet_line += "   Wings: %s" % wing_counts
	_txt(Vector2(16, 80), fleet_line, C_DIM, 13)
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
		"patrol":
			var wp_count: int = int(data.get("patrol_waypoint_count", 0))
			order_txt = "PATROL (%d wp)" % wp_count
			order_col = Color(0.75, 0.6, 1.0)
		"guard_station":
			var gst_name: String = String(data.get("fleet_guard_station_name", ""))
			order_txt = "GUARD STN %s" % gst_name if gst_name != "" else "GUARD STN"
			order_col = Color(0.6, 0.85, 1.0)
	_txt(Vector2(16, 96), "Order: %s" % order_txt, order_col, 12)
	var crew_mor: int = int(round(float(data.get("crew_morale", 1.0)) * 100.0))
	var mar_mor: int = int(round(float(data.get("marine_morale", 1.0)) * 100.0))
	var mor_col: Color = Color(0.5, 1.0, 0.5) if crew_mor >= 70 else (Color(1.0, 0.85, 0.3) if crew_mor >= 40 else Color(1.0, 0.4, 0.3))
	_txt(Vector2(16, 112), "Morale: C%d%%  M%d%%" % [crew_mor, mar_mor], mor_col, 12)
	_txt(Vector2(16, 128), "Shipyard: %s %dcr   Mode: %s" % [String(data.get("shipyard_class", "corvette")).to_upper(), int(data.get("shipyard_cost", 0)), mode.to_upper()], C_DIM, 12)
	if not service.is_empty():
		var svc_cost: int = int(service.get("cost", 0))
		var svc_txt: String = "[H] Repair/refit: %d cr" % svc_cost if svc_cost > 0 else "[H] Repair/refit: nominal"
		_txt(Vector2(16, 144), svc_txt, Color(0.55, 1.0, 0.72), 12)
	# Mouse-aim + control-scheme indicator (bottom of the economy panel).
	var ma_y: float = (160.0 if not service.is_empty() else 144.0)
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
		if bool(data.get("tutorial_open", false)):
			_draw_tutorial_overlay(vp)
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
		# Guard against an unknown/invalid distance (-1.0 or the _pdist 1e9 sentinel):
		# render a safe placeholder instead of "DIST 1000000000".
		var dval: float = float(tgt.get("dist", -1.0))
		var status: String = ("DIST —" if (dval < 0.0 or dval >= 1e8) else "DIST %d" % int(dval))
		if tgt.has("garrison"):
			status += "  GAR %d/%d" % [int(tgt.get("garrison", 0)), int(tgt.get("garrison_cap", 0))]
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
	# Station market / dock screen sits on top of everything when open (J key).
	if bool(data.get("dock_screen_open", false)):
		_draw_dock_screen(vp)
	# Save/load slot menu sits on top of the HUD when open (F5 key).
	if bool(data.get("save_menu_open", false)):
		_draw_save_menu(vp)
	# Mission-giver overlay sits on top when open (U key).
	if bool(data.get("mission_giver_open", false)):
		_draw_mission_giver(vp)
	# Opening-ceasefire banner (top center, just under the objective) while the grace timer runs.
	var grace: float = float(data.get("combat_grace", 0.0))
	if grace > 0.0 and not bool(data.get("tutorial_open", false)) and mode == "space":
		var btxt: String = "CEASEFIRE  %ds  —  enemies holding fire  (fire weapons to engage · F3 tutorial)" % int(ceil(grace))
		var bw: float = float(btxt.length()) * 7.2 + 24.0
		var bx: float = vp.x * 0.5 - bw * 0.5
		draw_rect(Rect2(Vector2(bx, 40), Vector2(bw, 24)), Color(0.10, 0.07, 0.0, 0.82), true)
		draw_rect(Rect2(Vector2(bx, 40), Vector2(bw, 24)), Color(1.0, 0.8, 0.3, 0.9), false, 1.5)
		_txt(Vector2(bx + 12, 57), btxt, Color(1.0, 0.9, 0.5), 13)
	# Tutorial / intro overlay sits on top of everything when open (F3 key).
	if bool(data.get("tutorial_open", false)):
		_draw_tutorial_overlay(vp)

func _draw_tutorial_overlay(vp: Vector2) -> void:
	# Paginated intro/help panel. main.gd feeds the current page content via tutorial_content
	# ({title, lines}); navigation happens in main._input. Dims the scene behind it.
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55), true)
	var w: float = 640.0
	var h: float = 380.0
	var x: float = vp.x * 0.5 - w * 0.5
	var y: float = vp.y * 0.5 - h * 0.5
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.05, 0.09, 0.96), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 2.0)

	var content: Dictionary = data.get("tutorial_content", {})
	var title: String = String(content.get("title", "TUTORIAL"))
	var page: int = int(data.get("tutorial_page", 0))
	var count: int = int(data.get("tutorial_page_count", 1))
	_txt(Vector2(x + 22, y + 32), title, Color(0.5, 1.0, 0.85), 19)
	_txt(Vector2(x + w - 96, y + 30), "%d / %d" % [page + 1, count], Color(0.6, 0.82, 0.95), 14)
	draw_line(Vector2(x + 20, y + 44), Vector2(x + w - 20, y + 44), C_LINE.darkened(0.2), 1.0)

	var lines: Array = content.get("lines", [])
	var ly: float = y + 74.0
	for ln in lines:
		_txt(Vector2(x + 28, ly), String(ln), Color(0.82, 0.92, 1.0), 14)
		ly += 22.0

	# Footer nav hints.
	draw_line(Vector2(x + 20, y + h - 36), Vector2(x + w - 20, y + h - 36), C_LINE.darkened(0.4), 1.0)
	var nav: String = "←/→  page      Enter/Space  next      Esc  close & launch"
	if page >= count - 1:
		nav = "←  back      Enter/Space/Esc  close & launch"
	_txt(Vector2(x + 24, y + h - 16), nav, Color(0.7, 0.88, 1.0, 0.95), 13)

func _draw_system_map(vp: Vector2) -> void:
	# Centered top-down map of the system: stations as labelled squares, other ships as
	# faction-coloured dots, the player as a heading arrow, plus a distance-scale bar.
	var m: Dictionary = data.get("system_map", {})
	var size: float = 600.0
	var origin: Vector2 = Vector2(vp.x * 0.5 - size * 0.5, vp.y * 0.5 - size * 0.5)
	var rect: Rect2 = Rect2(origin, Vector2(size, size))
	draw_rect(rect, Color(0.0, 0.03, 0.06, 0.92), true)
	draw_rect(rect, C_LINE, false, 1.5)
	var cur_sys: String = String(m.get("current_system", ""))
	var title: String = "SYSTEM MAP — %s  (M to close)" % cur_sys if cur_sys != "" else "SYSTEM MAP  (M to close)"
	_txt(origin + Vector2(14, 24), title, C_LINE, 16)

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

	# Jump-gate roster along the bottom-right of the panel: every reachable system, the
	# current one boxed/highlighted. [K] cycles to the next gate in flight.
	var gates: Array = m.get("jump_gates", [])
	if not gates.is_empty():
		var gx: float = origin.x + size * 0.42
		var gy: float = origin.y + size - 24.0 - float(gates.size()) * 16.0
		_txt(Vector2(gx, gy), "JUMP GATES  [K] next", C_LINE, 12)
		gy += 16.0
		for g in gates:
			var gd: Dictionary = g
			var gname: String = String(gd.get("name", ""))
			var is_cur: bool = bool(gd.get("current", false))
			var label: String = "%s %s" % ["▶" if is_cur else "  ", gname]
			var gcol: Color = Color(0.55, 1.0, 0.7) if is_cur else Color(0.7, 0.85, 0.95)
			if is_cur:
				draw_rect(Rect2(Vector2(gx - 2, gy - 11), Vector2(150, 15)), Color(0.1, 0.35, 0.25, 0.5), true)
			_txt(Vector2(gx, gy), label, gcol, 12)
			gy += 16.0

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
		["7", "patrol", "Patrol", "cycle waypoints (drop with P, [7] again clears)"],
		["8", "guard_station", "Guard stn", "orbit & screen current station target"],
	]
	var w: float = 460.0
	var h: float = 56.0 + float(rows.size()) * 22.0
	var x: float = vp.x * 0.5 - w * 0.5
	var y: float = vp.y * 0.5 - h * 0.5
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.04, 0.07, 0.9), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 1.5)
	_txt(Vector2(x + 16, y + 26), "FLEET ORDERS  (F/Esc close, W wings)", C_LINE, 15)
	var current: String = String(data.get("fleet_order", "follow"))
	for i in range(rows.size()):
		var row: Array = rows[i]
		var key: String = String(row[1])
		var ry: float = y + 50.0 + float(i) * 22.0
		var is_current: bool = key == current
		var col: Color = Color(1.0, 0.85, 0.35) if is_current else C_DIM
		var marker: String = ">" if is_current else " "
		_txt(Vector2(x + 16, ry), "%s[%s] %-11s — %s" % [marker, String(row[0]), String(row[2]), String(row[3])], col, 12)
	if bool(data.get("wing_menu_open", false)):
		_draw_wing_menu(x, y + h + 8.0, w)

func _draw_wing_menu(x: float, y: float, w: float) -> void:
	# Wing-order sub-panel drawn below the fleet menu: one row per wing with its current order
	# and (for attack/defend) the target name. The selected wing is marked with a cursor.
	var summary: Array = data.get("wing_summary", [])
	var cursor: int = int(data.get("wing_menu_cursor", 0))
	var rows: int = maxi(summary.size(), 1)
	var h: float = 62.0 + float(rows) * 18.0
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.04, 0.07, 0.92), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 1.5)
	_txt(Vector2(x + 16, y + 24), "WING ORDERS  (W/Esc back, ↑↓ select wing)", C_LINE, 14)
	for i in range(summary.size()):
		var entry: Dictionary = summary[i]
		var wid: String = String(entry.get("id", ""))
		var order: String = String(entry.get("order", ""))
		var tname: String = String(entry.get("target", ""))
		var label: String = order.to_upper() if order != "" else "(unassigned)"
		if tname != "":
			label += " " + tname
		var selected: bool = i == cursor
		var marker: String = "►" if selected else " "
		var col: Color = Color(1.0, 0.85, 0.35) if selected else C_DIM
		_txt(Vector2(x + 16, y + 44.0 + float(i) * 18.0), "%s %-7s %s" % [marker, wid.capitalize() + ":", label], col, 12)
	_txt(Vector2(x + 16, y + 48.0 + float(summary.size()) * 18.0), "[1-7] set order for selected wing", C_DIM, 11)

func _draw_mission_giver(vp: Vector2) -> void:
	var mission_list: Array = data.get("mission_giver_list", [])
	if mission_list.is_empty():
		return
	var cursor: int = int(data.get("mission_giver_cursor", 0))
	var w: float = 580.0
	var h: float = 90.0 + float(mission_list.size()) * 20.0
	var x: float = vp.x * 0.5 - w * 0.5
	var y: float = vp.y * 0.5 - h * 0.5
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.04, 0.07, 0.94), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 1.5)
	_txt(Vector2(x + 16, y + 26), "MISSIONS (U/Esc to close, \u2191\u2193 navigate, A abandon, Enter track)", C_LINE, 13)
	var bright: Color = Color(1.0, 0.95, 0.5)
	var dim: Color = Color(0.6, 0.78, 0.9)
	var row_y: float = y + 52.0
	for i in range(mission_list.size()):
		var entry: Dictionary = mission_list[i]
		var selected: bool = i == cursor
		var marker: String = "\u25ba" if selected else " "
		var state: String = String(entry.get("state", ""))
		var badge: String = ""
		var badge_col: Color = dim
		match state:
			"active":
				badge = "ACTIVE"
				badge_col = Color(0.45, 1.0, 0.6)
			"complete":
				badge = "COMPLETE"
				badge_col = Color(1.0, 0.85, 0.35)
			"failed":
				badge = "FAILED"
				badge_col = Color(1.0, 0.4, 0.34)
			"locked":
				badge = "LOCKED"
				badge_col = Color(0.5, 0.55, 0.62)
		if selected:
			draw_rect(Rect2(Vector2(x + 2, row_y - 11), Vector2(w - 4, 18)), Color(0.1, 0.35, 0.25, 0.5), true)
		var title: String = String(entry.get("title", ""))
		var reward: int = int(entry.get("reward", 0))
		_txt(Vector2(x + 16, row_y), "%s %s" % [marker, title], bright if selected else dim, 12)
		var badge_x: float = x + w - 130.0
		_txt(Vector2(badge_x, row_y), badge, badge_col, 11)
		_txt(Vector2(badge_x + 62.0, row_y), "+%d cr" % reward, dim, 11)
		row_y += 20.0

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

func _draw_save_menu(vp: Vector2) -> void:
	# Centered save/load slot panel. main.gd feeds the 6-entry slot meta array, the cursor
	# row, the mode ("save"/"load"), and a pending-delete flag; navigation happens in
	# main._input. The highlighted row gets a '►' marker and a bright color.
	var w: float = 500.0
	var h: float = 400.0
	var x: float = vp.x * 0.5 - w * 0.5
	var y: float = vp.y * 0.5 - h * 0.5
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.04, 0.07, 0.94), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 1.5)
	_txt(Vector2(x + 16, y + 26), "SAVE / LOAD  (F5/Esc to close)", C_LINE, 15)

	var mode: String = String(data.get("save_menu_mode", "save"))
	var cursor: int = int(data.get("save_menu_cursor", 0))
	var confirm: bool = bool(data.get("save_menu_confirm_delete", false))
	var slots: Array = data.get("save_slots", [])
	var bright: Color = Color(1.0, 0.95, 0.5)
	var dim: Color = Color(0.6, 0.78, 0.9)
	var empty_col: Color = Color(0.5, 0.55, 0.62)

	var mode_label: String = "MODE: SAVE (S to save, Enter to write)" if mode == "save" else "MODE: LOAD (D to load, Enter to read)"
	_txt(Vector2(x + 16, y + 50), mode_label, bright, 13)

	var row_y: float = y + 84.0
	for i in range(slots.size()):
		var entry: Dictionary = slots[i]
		var selected: bool = i == cursor
		var marker: String = "►" if selected else " "
		var exists: bool = bool(entry.get("exists", false))
		var label: String = ""
		if exists:
			label = "%s [%d] %s — %d cr  fleet %d  %s  %s" % [
				marker,
				int(entry.get("index", i + 1)),
				String(entry.get("name", "Slot %d" % (i + 1))),
				int(entry.get("credits", 0)),
				int(entry.get("fleet", 0)),
				String(entry.get("system", "")),
				String(entry.get("timestamp", "")),
			]
		else:
			label = "%s [%d] %s — --- empty ---" % [marker, int(entry.get("index", i + 1)), String(entry.get("name", "Slot %d" % (i + 1)))]
		var row_col: Color = bright if selected else (dim if exists else empty_col)
		_txt(Vector2(x + 18, row_y), label, row_col, 13)
		row_y += 30.0

	if confirm:
		_txt(Vector2(x + 16, y + h - 44.0), "PRESS ENTER TO CONFIRM DELETE / Esc to cancel", Color(1.0, 0.4, 0.34), 13)
	_txt(Vector2(x + 16, y + h - 18.0), "↑↓ select   S=Save   D=Load   Enter=Confirm   X=Delete   F5/Esc=Close", Color(0.62, 0.82, 0.94, 0.85), 11)

func _draw_dock_screen(vp: Vector2) -> void:
	# Centered multi-tab station market. main.gd feeds the active tab/cursor and a structured
	# per-tab row Dictionary (data["dock_screen"]); this renders it. The active tab is shown in
	# the accent color with a '►' marker; the highlighted body row gets a '►' marker too.
	var w: float = 540.0
	var h: float = 360.0
	var x: float = vp.x * 0.5 - w * 0.5
	var y: float = vp.y * 0.5 - h * 0.5
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), Color(0.0, 0.04, 0.07, 0.94), true)
	draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), C_LINE, false, 1.5)

	var station_name: String = String(data.get("dock_screen_station", ""))
	var title: String = "STATION MARKET — %s" % station_name if station_name != "" else "STATION MARKET"
	_txt(Vector2(x + 16, y + 26), title, C_LINE, 15)

	var tab: int = int(data.get("dock_screen_tab", 0))
	var cursor: int = int(data.get("dock_screen_cursor", 0))
	var tab_names: Array = ["SHIPYARD", "CREW", "REPAIR", "INFO", "MARKET", "UPGRADES", "BOUNTIES"]
	var bright: Color = Color(1.0, 0.95, 0.5)
	var dim: Color = Color(0.6, 0.78, 0.9)

	# Tab bar.
	var tab_y: float = y + 50.0
	var tab_x: float = x + 16.0
	for i in range(tab_names.size()):
		var active: bool = i == tab
		var tcol: Color = bright if active else dim
		var marker: String = "►" if active else " "
		var label: String = "%s%s" % [marker, String(tab_names[i])]
		_txt(Vector2(tab_x, tab_y), label, tcol, 14)
		tab_x += 74.0
	draw_line(Vector2(x + 14, tab_y + 10.0), Vector2(x + w - 14, tab_y + 10.0), C_LINE.darkened(0.3), 1.0)

	var dock: Dictionary = data.get("dock_screen", {})
	var bx: float = x + 18.0
	var by: float = tab_y + 36.0
	match tab:
		0:
			_dock_draw_shipyard(dock, bx, by, bright, dim)
		1:
			_dock_draw_crew(dock, bx, by, cursor, bright, dim)
		2:
			_dock_draw_repair(dock, bx, by, cursor, bright, dim)
		3:
			_dock_draw_info(dock, bx, by, dim)
		4:
			_dock_draw_market(dock, bx, by, cursor, bright, dim)
		5:
			_dock_draw_upgrades(dock, bx, by, cursor, bright, dim)
		6:
			_dock_draw_bounties(dock, bx, by, cursor, bright, dim)

	var hint: String = "←→ tabs  ↑↓ select  Enter confirm  J/Esc close"
	if tab == 4:
		hint = "←→ tabs  ↑↓ select  Enter buy/sell  S toggle mode  J/Esc close"
	elif tab == 5:
		hint = "←→ tabs  ↑↓ select  Enter upgrade  J/Esc close"
	elif tab == 6:
		hint = "←→ tabs  ↑↓ select  Enter accept/claim  J/Esc close"
	_txt(Vector2(x + 16, y + h - 18.0), hint, Color(0.62, 0.82, 0.94, 0.85), 12)

func _dock_draw_shipyard(dock: Dictionary, bx: float, by: float, bright: Color, dim: Color) -> void:
	var rows: Array = dock.get("shipyard", [])
	var cursor: int = int(data.get("dock_screen_cursor", 0))
	_txt(Vector2(bx, by), "Buy ship  (Enter purchases the highlighted class):", dim, 12)
	by += 24.0
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var selected: bool = i == cursor
		var rcol: Color = bright if selected else dim
		var marker: String = "►" if selected else " "
		var offered: String = ">>" if bool(row.get("selected", false)) else "  "
		var line: String = "%s%s %-9s %6d cr   H%-4d S%-4d crew %d" % [
			marker, offered, String(row.get("display", "")),
			int(row.get("cost", 0)), int(row.get("hull", 0)),
			int(row.get("shield", 0)), int(row.get("crew_needed", 0)),
		]
		_txt(Vector2(bx, by), line, rcol, 13)
		by += 22.0

func _dock_draw_crew(dock: Dictionary, bx: float, by: float, cursor: int, bright: Color, dim: Color) -> void:
	var crew: Dictionary = dock.get("crew", {})
	var rows: Array = [
		"Recruit Crew — %d cr" % int(crew.get("cost_crew", 120)),
		"Recruit Marine — %d cr" % int(crew.get("cost_marine", 180)),
	]
	for i in range(rows.size()):
		var selected: bool = i == cursor
		var rcol: Color = bright if selected else dim
		var marker: String = "►" if selected else " "
		_txt(Vector2(bx, by), "%s %s" % [marker, String(rows[i])], rcol, 13)
		by += 24.0
	by += 8.0
	_txt(Vector2(bx, by), "Available crew: %d %s   Marines: %d" % [
		int(crew.get("crew_pool", 0)), String(crew.get("roles", "")), int(crew.get("marine_pool", 0))], dim, 12)

func _dock_draw_repair(dock: Dictionary, bx: float, by: float, cursor: int, bright: Color, dim: Color) -> void:
	var repair: Dictionary = dock.get("repair", {})
	var in_range: bool = bool(repair.get("in_range", false))
	var rcol: Color = bright if cursor == 0 else dim
	_txt(Vector2(bx, by), "► Repair/Refit Fleet", rcol, 13)
	by += 28.0
	if in_range:
		var cost: int = int(repair.get("cost", 0))
		var cost_str: String = "nominal — no repair needed" if cost == 0 else "%d cr" % cost
		_txt(Vector2(bx, by), "Station: %s" % String(repair.get("station", "")), dim, 12)
		by += 18.0
		_txt(Vector2(bx, by), "Estimated cost: %s" % cost_str, dim, 12)
	else:
		_txt(Vector2(bx, by), "No friendly station in range.", Color(1.0, 0.6, 0.4), 12)

func _dock_draw_info(dock: Dictionary, bx: float, by: float, dim: Color) -> void:
	var info: Dictionary = dock.get("info", {})
	var lines: Array = [
		"Station: %s" % String(info.get("station", "")),
		"Faction: %s" % String(info.get("faction", "")).to_upper(),
		"Credits: %d" % int(info.get("credits", 0)),
		"Fleet ships: %d   Captured: %d" % [int(info.get("fleet_count", 0)), int(info.get("captured", 0))],
		"Fleet order: %s" % String(info.get("order", "")),
	]
	for ln in lines:
		_txt(Vector2(bx, by), String(ln), dim, 13)
		by += 22.0

func _dock_draw_market(dock: Dictionary, bx: float, by: float, cursor: int, bright: Color, dim: Color) -> void:
	var market: Dictionary = dock.get("market", {})
	var rows: Array = market.get("rows", [])
	var sell_mode: bool = bool(market.get("sell_mode", false))
	var mode_str: String = "SELL" if sell_mode else "BUY"
	var mode_col: Color = Color(1.0, 0.6, 0.4) if sell_mode else Color(0.55, 1.0, 0.72)
	_txt(Vector2(bx, by), "Mode: ", dim, 12)
	_txt(Vector2(bx + 44.0, by), mode_str, mode_col, 13)
	_txt(Vector2(bx + 96.0, by), "(Enter trades 1, M max, S toggles BUY/SELL)", dim, 12)
	by += 22.0
	_txt(Vector2(bx, by), "%s%-13s %8s %8s %6s" % ["  ", "Commodity", "Buy", "Sell", "Held"], dim, 12)
	by += 20.0
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var selected: bool = i == cursor
		var rcol: Color = bright if selected else dim
		var marker: String = "►" if selected else " "
		var line: String = "%s %-13s %8d %8d %6d" % [
			marker, String(row.get("name", "")),
			int(row.get("buy", 0)), int(row.get("sell", 0)), int(row.get("held", 0)),
		]
		_txt(Vector2(bx, by), line, rcol, 13)
		by += 22.0
	by += 8.0
	var used: int = int(market.get("cargo_used", 0))
	var cap: int = int(market.get("cargo_capacity", 0))
	_txt(Vector2(bx, by), "Cargo: %d / %d" % [used, cap], Color(1.0, 0.85, 0.4), 13)

func _dock_draw_upgrades(dock: Dictionary, bx: float, by: float, cursor: int, bright: Color, dim: Color) -> void:
	var upg: Dictionary = dock.get("upgrades", {})
	var rows: Array = upg.get("rows", [])
	var ship_name: String = String(upg.get("ship", ""))
	var maxed_col: Color = Color(0.45, 1.0, 0.55)
	_txt(Vector2(bx, by), "Flagship upgrades — %s" % ship_name, dim, 12)
	by += 24.0
	# Static per-category effect descriptors (row order matches UPGRADE_CATEGORIES).
	var effects: Array = ["+15%/lvl damage", "+15% per level", "+12% per level", "+8% speed/turn", "+12% energy"]
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var selected: bool = i == cursor
		var maxed: bool = bool(row.get("maxed", false))
		var rcol: Color = maxed_col if maxed else (bright if selected else dim)
		var marker: String = "►" if selected else " "
		var cost_str: String = "MAX" if maxed else "%d cr" % int(row.get("cost", 0))
		var eff: String = String(effects[i]) if i < effects.size() else ""
		var line: String = "%s %-9s Lvl %d/%d  %-8s %s" % [
			marker, String(row.get("name", "")),
			int(row.get("level", 0)), int(row.get("max_level", 5)),
			cost_str, eff,
		]
		_txt(Vector2(bx, by), line, rcol, 13)
		by += 22.0

func _dock_draw_bounties(dock: Dictionary, bx: float, by: float, cursor: int, bright: Color, dim: Color) -> void:
	var bounties: Dictionary = dock.get("bounties", {})
	var rows: Array = bounties.get("rows", [])
	_txt(Vector2(bx, by), "Bounty Board — accept a contract, then claim when complete:", dim, 12)
	by += 24.0
	if rows.is_empty():
		_txt(Vector2(bx, by), "No bounties posted.", dim, 12)
		return
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var selected: bool = i == cursor
		var marker: String = "►" if selected else " "
		var state: String = String(row.get("state", "available"))
		var tag: String = "[AVAIL]"
		var tag_col: Color = Color(0.5, 0.85, 0.6)
		match state:
			"active":
				tag = "[ACTIVE]"
				tag_col = Color(1.0, 0.85, 0.4)
			"complete":
				tag = "[DONE]"
				tag_col = Color(0.45, 1.0, 0.55)
			"claimed":
				tag = "[CLAIMD]"
				tag_col = Color(0.6, 0.6, 0.6)
		var rcol: Color = bright if selected else dim
		# Tint the state tag, then the rest of the line in the row color.
		_txt(Vector2(bx, by), "%s " % marker, rcol, 13)
		_txt(Vector2(bx + 16.0, by), tag, tag_col, 13)
		_txt(Vector2(bx + 84.0, by), "%-22s %d/%d   %dcr" % [
			String(row.get("title", "")),
			int(row.get("kills_so_far", 0)), int(row.get("kill_target", 0)),
			int(row.get("reward", 0)),
		], rcol, 13)
		by += 22.0

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
	draw_rect(Rect2(Vector2(vp.x - 320, vp.y - 92), Vector2(312, 84)), C_BG, true)
	_txt(Vector2(vp.x - 310, vp.y - 70), "DECK: %s" % String(data.get("deck_ship", "Corvette [Flagship]")), C_LINE, 14)
	var view_txt: String = "first-person" if bool(data.get("deck_first_person", true)) else "overhead"
	_txt(Vector2(vp.x - 310, vp.y - 52), "Room: %s   View: %s" % [String(data.get("deck_room", "Bridge")), view_txt], C_DIM, 12)
	_txt(Vector2(vp.x - 310, vp.y - 34), "WASD move  mouse look  F4 view", C_DIM, 12)
	_txt(Vector2(vp.x - 310, vp.y - 16), "F follow  C exit  R next ship", C_DIM, 12)
