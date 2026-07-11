extends CanvasLayer
## DebugOverlay.gd
## F11 toggle — detailed power debug panel + engine stats.
##
## Wire-up (MainWorld.gd):
##   var _debug_overlay: CanvasLayer = DebugOverlay instance
##   Inject: player_ref, world_ref, power_manager_ref

# ─── Injected refs ────────────────────────────────────────────────────────────
var player_ref:       Node3D = null   ## Player node — for position display
var world_ref:        Node   = null   ## MainWorld — get_cash()
var power_manager_ref: PowerManager  = null   ## PowerManager node

# ─── Internal ─────────────────────────────────────────────────────────────────
var _visible_state: bool   = false
var _canvas:        Control = null
var _font:          Font    = null

var _fps_samples: PackedFloat32Array = PackedFloat32Array()
const FPS_SAMPLE_COUNT: int = 30

const BG:    Color = Color(0.04, 0.06, 0.04, 0.93)
const BORD:  Color = Color(0.28, 0.85, 0.32, 0.70)
const H_COL: Color = Color(0.22, 0.90, 0.35, 1.0)
const T_COL: Color = Color(0.78, 0.95, 0.80, 0.95)
const D_COL: Color = Color(0.45, 0.55, 0.45, 0.85)
const W_COL: Color = Color(1.0,  0.72, 0.12, 1.0)
const C_COL: Color = Color(1.0,  0.25, 0.18, 1.0)
const G_COL: Color = Color(0.30, 1.0,  0.45, 1.0)

const FONT_H: int = 12
const FONT_N: int = 11
const FONT_S: int = 10

## Panel geometry — wide enough for consumer table
const PANEL_W: float = 520.0
const ROW_H:   float = 15.0
const PAD:     float = 10.0

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer   = 99
	visible = false

	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.name = "DebugCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_visible_state = not _visible_state
			visible        = _visible_state
			if _canvas != null:
				_canvas.queue_redraw()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _visible_state:
		return
	_fps_samples.append(1.0 / maxf(delta, 0.0001))
	if _fps_samples.size() > FPS_SAMPLE_COUNT:
		_fps_samples.remove_at(0)
	_canvas.queue_redraw()

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	if not _visible_state:
		return

	var lines: Array[Dictionary] = _collect_lines()
	var row_count: int = lines.size()
	var panel_h: float = PAD * 2.0 + float(row_count) * ROW_H

	var vp: Vector2  = _canvas.get_viewport_rect().size
	var px: float    = 12.0
	var py: float    = vp.y * 0.05   ## 5% from top

	# Panel bg + border
	var panel_rect: Rect2 = Rect2(px, py, PANEL_W, panel_h)
	_canvas.draw_rect(panel_rect, BG, true)
	_canvas.draw_rect(panel_rect, BORD, false, 1.5)

	# Rows
	var ry: float = py + PAD + ROW_H * 0.75
	for line: Dictionary in lines:
		var txt: String  = line.get("text", "")
		var col: Color   = line.get("color", T_COL)
		var size: int    = line.get("size", FONT_N)
		var indent: int  = line.get("indent", 0)
		var fx: float    = px + PAD + float(indent) * 12.0
		# Shadow
		_canvas.draw_string(_font, Vector2(fx + 1, ry + 1), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.70))
		# Text
		_canvas.draw_string(_font, Vector2(fx, ry), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		ry += ROW_H

# ─── Data collection ──────────────────────────────────────────────────────────
func _collect_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	# ── Engine stats ──────────────────────────────────────────────────────────
	var avg_fps: float = 0.0
	for s: float in _fps_samples:
		avg_fps += s
	if _fps_samples.size() > 0:
		avg_fps /= float(_fps_samples.size())
	var draw_calls: int  = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var nodes:      int  = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var mem_mb:     float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1_048_576.0

	out.append(_h("── ENGINE ─────────────────────────────────"))
	out.append(_t("FPS %d (avg %d)  |  Draw calls %d  |  Nodes %d  |  RAM %.1f MB" % [
		Engine.get_frames_per_second(), roundi(avg_fps), draw_calls, nodes, mem_mb]))

	if player_ref != null and is_instance_valid(player_ref):
		var p: Vector3 = player_ref.global_position
		out.append(_t("Player (%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]))

	if world_ref != null and is_instance_valid(world_ref) and world_ref.has_method("get_cash"):
		out.append(_t("Cash  $%d" % world_ref.get_cash()))

	out.append(_t("[F11] hide  |  [F12] time warp  |  [F1] build mode"))
	out.append(_sep())

	# ── Power grid ────────────────────────────────────────────────────────────
	var pm: PowerManager = power_manager_ref
	if pm == null:
		pm = get_tree().get_first_node_in_group("power_manager") as PowerManager

	if pm == null:
		out.append(_warn("POWER MANAGER NOT FOUND"))
		return out

	# Single snapshot call — avoids accessing private PM vars directly
	var snap: Dictionary = pm.get_debug_snapshot()

	out.append(_h("── POWER GRID ──────────────────────────────"))

	var grid_state: int   = snap.get("grid_state", 0)
	var total_draw: float = snap.get("total_draw_watts", 0.0)
	var total_cap: float  = snap.get("total_capacity_watts", 0.0)
	var state_col: Color  = _gs_color(grid_state)
	out.append({"text": "State: %s   Draw: %.0fW / %.0fW" % [_gs_name(grid_state), total_draw, total_cap],
		"color": state_col, "size": FONT_N, "indent": 0})

	var node_ct: int  = snap.get("wire_node_count", 0)
	var edge_ct: int  = snap.get("wire_edge_count", 0)
	var reach:   int  = snap.get("reachable_node_count", 0)
	var ol_edges: Array = snap.get("brownout_edges", [])
	out.append(_t("Wire nodes %d | Edges %d | Reachable %d | Brownout edges %d" % [
		node_ct, edge_ct, reach, ol_edges.size()]))

	# Generators
	out.append(_sep())
	out.append(_h("── GENERATORS ──────────────────────────────"))
	var gens: Array = snap.get("generators", [])
	if gens.is_empty():
		out.append(_dim("  (none)"))
	for gen: Dictionary in gens:
		var running: bool  = gen.get("running", false)
		var fuel:    float = gen.get("fuel", 100.0)
		var watts:   float = gen.get("watts", 0.0)
		var col: Color = G_COL if running else D_COL
		if fuel < 25.0:   col = C_COL
		elif fuel < 50.0: col = W_COL
		out.append({"text": "  %s  %.0fW  fuel:%.0f%%  hp:%.0f%%  %s" % [
			"RUN" if running else "OFF", watts, fuel, gen.get("health", 100.0),
			"(backup)" if gen.get("is_backup", false) else ""],
			"color": col, "size": FONT_S, "indent": 1})

	# Batteries
	out.append(_sep())
	out.append(_h("── BATTERIES ───────────────────────────────"))
	var batts: Array = snap.get("batteries", [])
	if batts.is_empty():
		out.append(_dim("  (none)"))
	for batt: Dictionary in batts:
		var cap:    float = batt.get("capacity_wh", 1.0)
		var charge: float = batt.get("charge_wh", 0.0)
		var pct:    float = (charge / maxf(cap, 1.0)) * 100.0
		var bstate: String = batt.get("state", "IDLE")
		## Color by state: green=CHARGING, amber=DISCHARGING, red=DRAINED, dim=IDLE
		var bcol: Color
		match bstate:
			"CHARGING":    bcol = G_COL
			"DISCHARGING": bcol = W_COL if pct > 15.0 else C_COL
			"DRAINED":     bcol = C_COL
			_:             bcol = D_COL   ## IDLE or unknown
		out.append({"text": "  %.0f / %.0f Wh  (%.0f%%)  [%s]" % [charge, cap, pct, bstate],
			"color": bcol, "size": FONT_S, "indent": 1})

	# Consumers
	out.append(_sep())
	out.append(_h("── CONSUMERS (type / watts / state) ───────"))
	var cons: Array = snap.get("consumers", [])
	if cons.is_empty():
		out.append(_dim("  (none)"))
	var shown: int = 0
	for con: Dictionary in cons:
		if shown >= 16:
			out.append(_dim("  … +%d more" % (cons.size() - shown)))
			break
		var powered: bool = con.get("powered", false)
		var shed:    bool = con.get("shed", false)
		var ccol: Color = G_COL if powered else (W_COL if shed else D_COL)
		var ctype: String = str(con.get("type", "?")).substr(0, 10)
		out.append({"text": "  %-11s  %5.0fW  [%s]" % [
			ctype, con.get("watts", 0.0),
			"ON" if powered else ("SHED" if shed else "OFF")],
			"color": ccol, "size": FONT_S, "indent": 1})
		shown += 1

	# Wire zones (coloured, per-zone detail)
	out.append(_sep())
	out.append(_h("── WIRE ZONES ──────────────────────────────"))

	var pm2: PowerManager = power_manager_ref
	if pm2 == null:
		pm2 = get_tree().get_first_node_in_group("power_manager") as PowerManager
	var zone_snap: Array = []
	if pm2 != null:
		zone_snap = pm2.get_zone_snapshot()

	if zone_snap.is_empty():
		out.append(_dim("  (no enclosed wire zones — place ≥2 breakers)"))
	else:
		## Zone colour palette: matches BuildModeController + BreakerBox.
		const ZC: Array[Color] = [
			Color(0.10, 0.95, 0.35, 1.0),   ## green
			Color(0.95, 0.40, 0.40, 1.0),   ## red
			Color(0.95, 0.90, 0.10, 1.0),   ## yellow
			Color(0.10, 0.90, 0.95, 1.0),   ## cyan
			Color(0.90, 0.35, 0.95, 1.0),   ## magenta
			Color(0.95, 0.65, 0.10, 1.0),   ## orange
		]
		## Zone colour name labels for the swatch display.
		const ZC_NAMES: Array[String] = [
			"GRN", "RED", "YEL", "CYN", "MAG", "ORG",
		]
		for zd: Dictionary in zone_snap:
			var z_idx:      int    = int(zd.get("zone_index", 0))
			var z_key:      String = String(zd.get("zone_key", ""))
			## Player-set display name if set (see ZoneCustomization.gd), else "Z%d".
			var z_name:     String = String(zd.get("zone_name", "Z%d" % z_idx))
			## Use color_index from the snapshot (set by get_wire_zones_with_colors)
			## so this matches the ACTUAL painted color on the wire, not z_idx % 6.
			var z_cidx:     int    = int(zd.get("color_index", z_idx % ZC.size()))
			var z_state:    String = zd.get("state_str", "ONLINE")
			var z_cons:     int    = (zd.get("consumer_ids", []) as Array).size()
			var z_gens:     int    = (zd.get("generator_ids", []) as Array).size()
			var z_bats:     int    = (zd.get("battery_ids", []) as Array).size()
			var z_draw:     float  = float(zd.get("draw_w", 0.0))
			var z_cap:      float  = float(zd.get("capacity_w", 0.0))
			## Prefer the live override-aware color (pm2 != null here — checked above
			## to reach this branch) over the local ZC mirror, so a player-recolored
			## zone shows its real color in the debug overlay too.
			var z_col:      Color  = pm2.zone_display_color(z_key, z_cidx, 1.0) \
				if pm2 != null else ZC[z_cidx % ZC.size()]
			var z_col_name: String = ZC_NAMES[z_cidx % ZC_NAMES.size()]
			var z_state_col: Color
			match z_state:
				"ONLINE":   z_state_col = z_col
				"OVERLOADED": z_state_col = W_COL
				_:          z_state_col = C_COL
			out.append({"text": "  %s  [%s]  color:%s(ci=%d)  %.0fW/%.0fW  cons:%d  gen:%d  bat:%d" % [
				z_name, z_state, z_col_name, z_cidx, z_draw, z_cap, z_cons, z_gens, z_bats],
				"color": z_state_col, "size": FONT_S, "indent": 1})

	return out

# ─── Line factories ───────────────────────────────────────────────────────────
func _h(txt: String) -> Dictionary:
	return {"text": txt, "color": H_COL, "size": FONT_H, "indent": 0}

func _t(txt: String) -> Dictionary:
	return {"text": txt, "color": T_COL, "size": FONT_N, "indent": 0}

func _dim(txt: String) -> Dictionary:
	return {"text": txt, "color": D_COL, "size": FONT_S, "indent": 1}

func _warn(txt: String) -> Dictionary:
	return {"text": txt, "color": W_COL, "size": FONT_N, "indent": 0}

func _sep() -> Dictionary:
	return {"text": "", "color": D_COL, "size": FONT_S, "indent": 0}

func _gs_name(s: int) -> String:
	match s:
		0: return "ONLINE"
		1: return "OVERLOADED"
		2: return "BROWNOUT"
		3: return "TRIPPED"
		4: return "OFFLINE"
	return "UNKNOWN"

func _gs_color(s: int) -> Color:
	match s:
		0: return G_COL
		1: return W_COL
		2: return W_COL
		3: return C_COL
		4: return C_COL
	return T_COL
