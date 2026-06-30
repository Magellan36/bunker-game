extends CanvasLayer
## PowerTerminalUI.gd
## Full-screen power dashboard opened by interacting with PowerTerminal.
## Reads live data from PowerManager every frame.
##
## PERSISTENCE: History arrays survive close/reopen because this node is NEVER
## queue_free()d. PowerTerminal.gd keeps it alive and calls open()/close() to
## show/hide it. close() sets visible=false and stops _process; open() resumes.
##
## Panels:
##   • Header — grid state + total draw/capacity
##   • Generators — id, tier, running, fuel%, health%
##   • Batteries  — id, charge%
##   • Consumers  — id (truncated), watts, powered, shed
##   • Wire graph — node count, edge count, overloaded edges
##   • Breakers   — per-zone state

signal closed

# ─── Layout constants ─────────────────────────────────────────────────────────
const BG_COLOR:     Color = Color(0.04, 0.07, 0.04, 0.97)
const BORDER_COLOR: Color = Color(0.28, 0.85, 0.32, 0.80)
const HEADER_COLOR: Color = Color(0.22, 0.75, 0.28, 1.0)
const TEXT_COLOR:   Color = Color(0.80, 0.95, 0.82, 0.95)
const DIM_COLOR:    Color = Color(0.45, 0.55, 0.45, 0.85)
const WARN_COLOR:   Color = Color(1.0,  0.72, 0.10, 1.0)
const CRIT_COLOR:   Color = Color(1.0,  0.25, 0.18, 1.0)
const OK_COLOR:     Color = Color(0.30, 1.0,  0.45, 1.0)
const ACCENT_BACKUP: Color = Color(0.30, 0.68, 1.00, 1.0)  ## Blue — backup generator rows

const FONT_SIZE_H:  int = 14
const FONT_SIZE_N:  int = 11
const FONT_SIZE_S:  int = 10

const PANEL_W:      float = 780.0
const PANEL_H:      float = 560.0
const SECTION_PAD:  float = 12.0
const COL_GAP:      float = 16.0

# ─── History graph — PERSISTS across open/close ───────────────────────────────
## These are intentionally NOT cleared on close() so the graph retains its
## history when the player reopens the terminal.
var _draw_history: PackedFloat32Array = PackedFloat32Array()
var _cap_history:  PackedFloat32Array = PackedFloat32Array()
const HISTORY_LEN: int   = 60    ## samples — ~60 seconds at 1 sample/s
var _sample_timer: float = 0.0
const SAMPLE_INTERVAL: float = 1.0

# ─── State ────────────────────────────────────────────────────────────────────
var _is_open: bool = false
var _canvas:  Control = null
var _font:    Font = null

## Per-grid scoping — set by PowerTerminal before calling open().
## When non-empty, only generators/batteries/consumers reachable from this
## wire-node key are shown.  Empty string = show everything (legacy/debug).
var connected_grid_key: String = ""

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer   = 50
	visible = false
	## Always process — background sampling runs even when closed.
	## _on_draw is only triggered when open (via queue_redraw in open()).
	set_process(true)
	_font   = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.name = "PowerTerminalCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

func open() -> void:
	_is_open = true
	visible  = true
	_canvas.queue_redraw()

## close() hides the panel but does NOT free this node.
## History arrays survive; background sampling continues via _process().
func close() -> void:
	_is_open = false
	visible  = false
	closed.emit()
	## DO NOT call queue_free() here — PowerTerminal keeps us alive.

# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_F1, KEY_TAB:
				close()
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# Check close button hit rect
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var px: float   = (vp.x - PANEL_W) * 0.5
		var py: float   = (vp.y - PANEL_H) * 0.5
		var close_rect: Rect2 = Rect2(px + PANEL_W - 36.0, py + 8.0, 28.0, 28.0)
		if close_rect.has_point(event.position):
			close()
			get_viewport().set_input_as_handled()
			return
		# Eat all clicks inside panel
		var panel_rect: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
		if panel_rect.has_point(event.position):
			get_viewport().set_input_as_handled()

# ─── Process — collect history samples (always runs, even when closed) ────────
func _process(delta: float) -> void:
	## Sample the power manager every SAMPLE_INTERVAL regardless of visibility.
	## This keeps load history continuous so the graph isn't flat after a reopen.
	_sample_timer += delta
	if _sample_timer >= SAMPLE_INTERVAL:
		_sample_timer = 0.0
		var pm: Node = _get_pm()
		if pm != null and pm.has_method("get_debug_snapshot"):
			var s: Dictionary = pm.get_debug_snapshot()
			_draw_history.append(s.get("total_draw_watts", 0.0))
			_cap_history.append(s.get("total_capacity_watts", 0.0))
			if _draw_history.size() > HISTORY_LEN:
				_draw_history.remove_at(0)
			if _cap_history.size() > HISTORY_LEN:
				_cap_history.remove_at(0)

	## Only request a redraw while the terminal is actually visible.
	if _is_open:
		_canvas.queue_redraw()

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	var vp: Vector2  = get_viewport().get_visible_rect().size
	var px: float    = (vp.x - PANEL_W) * 0.5
	var py: float    = (vp.y - PANEL_H) * 0.5

	# Full-screen dim
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.65), true)

	# Panel background
	var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
	_canvas.draw_rect(panel, BG_COLOR, true)
	_canvas.draw_rect(panel, BORDER_COLOR, false, 2.0)

	var pm: Node = _get_pm()
	if pm == null:
		_draw_string_at("POWER MANAGER NOT FOUND", Vector2(px + 20.0, py + 40.0), CRIT_COLOR, FONT_SIZE_H)
		return

	var snap: Dictionary = {}
	if pm.has_method("get_debug_snapshot"):
		snap = pm.get_debug_snapshot()

	## Per-grid scoping: if a connected_grid_key is set, filter generators,
	## batteries, and consumers to only those reachable from that wire node.
	## This prevents a terminal wired to grid A from showing grid B's stats.
	if not connected_grid_key.is_empty() and pm.has_method("get_reachable_device_ids"):
		var reachable: Array = pm.call("get_reachable_device_ids", connected_grid_key)
		var reachable_set: Dictionary = {}
		for rid: String in reachable:
			reachable_set[rid] = true

		## Filter generators
		var all_gens: Array = snap.get("generators", [])
		var filtered_gens: Array = []
		for g: Dictionary in all_gens:
			if reachable_set.has(g.get("id", "")):
				filtered_gens.append(g)
		snap["generators"] = filtered_gens

		## Filter batteries
		var all_batts: Array = snap.get("batteries", [])
		var filtered_batts: Array = []
		for b: Dictionary in all_batts:
			if reachable_set.has(b.get("id", "")):
				filtered_batts.append(b)
		snap["batteries"] = filtered_batts

		## Filter consumers
		var all_cons: Array = snap.get("consumers", [])
		var filtered_cons: Array = []
		for c: Dictionary in all_cons:
			if reachable_set.has(c.get("id", "")):
				filtered_cons.append(c)
		snap["consumers"] = filtered_cons

		## Recompute aggregate draw/capacity from filtered data only
		var filtered_draw: float = 0.0
		var filtered_cap:  float = 0.0
		for g2: Dictionary in filtered_gens:
			if g2.get("running", false):
				filtered_cap += g2.get("watts", 0.0)
		for c2: Dictionary in filtered_cons:
			if c2.get("powered", false):
				filtered_draw += c2.get("watts", 0.0)
		snap["total_draw_watts"]     = filtered_draw
		snap["total_capacity_watts"] = filtered_cap

	# ── Close button ──────────────────────────────────────────────────────────
	var close_rect: Rect2 = Rect2(px + PANEL_W - 36.0, py + 8.0, 28.0, 28.0)
	_canvas.draw_rect(close_rect, Color(0.30, 0.06, 0.06, 0.90), true)
	_canvas.draw_rect(close_rect, CRIT_COLOR, false, 1.5)
	var cp: Vector2 = close_rect.position
	var cs: Vector2 = close_rect.size
	_canvas.draw_line(cp + Vector2(6, 6), cp + cs - Vector2(6, 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)
	_canvas.draw_line(cp + Vector2(cs.x-6, 6), cp + Vector2(6, cs.y-6), Color(1.0, 0.7, 0.7, 1.0), 2.0)

	# ── Title + grid state ────────────────────────────────────────────────────
	var title_y: float = py + 24.0
	_draw_string_at("⚡ POWER TERMINAL", Vector2(px + SECTION_PAD, title_y), HEADER_COLOR, FONT_SIZE_H)

	var grid_state: int   = snap.get("grid_state", 0)
	var state_str: String = _grid_state_name(grid_state)
	var state_col: Color  = _grid_state_color(grid_state)
	_draw_string_at("STATE: %s" % state_str, Vector2(px + 210.0, title_y), state_col, FONT_SIZE_H)

	var total_draw: float = snap.get("total_draw_watts", 0.0)
	var total_cap:  float = snap.get("total_capacity_watts", 0.0)
	_draw_string_at(
		"LOAD  %.0fW / %.0fW" % [total_draw, total_cap],
		Vector2(px + 430.0, title_y), TEXT_COLOR, FONT_SIZE_H)

	# Separator
	var sep_y: float = py + 42.0
	_canvas.draw_line(Vector2(px + SECTION_PAD, sep_y),
		Vector2(px + PANEL_W - SECTION_PAD, sep_y), BORDER_COLOR, 1.0)

	# ── Layout: two columns ───────────────────────────────────────────────────
	var col1_x: float = px + SECTION_PAD
	var col2_x: float = px + PANEL_W * 0.5 + COL_GAP
	var col_w:  float = PANEL_W * 0.5 - SECTION_PAD - COL_GAP
	var row_y:  float = sep_y + 10.0

	# Left column: generators, batteries, wire
	row_y = _draw_generators_section(snap, col1_x, row_y, col_w)
	row_y = _draw_batteries_section(snap, col1_x, row_y, col_w)
	_draw_wire_section(snap, col1_x, row_y, col_w)

	# Right column: load graph + consumers + breakers
	var right_y: float = sep_y + 10.0
	right_y = _draw_graph_section(col2_x, right_y, col_w)
	right_y = _draw_consumers_section(snap, col2_x, right_y, col_w)
	_draw_breakers_section(snap, col2_x, right_y, col_w)

	# ── Footer ────────────────────────────────────────────────────────────────
	var footer_y: float = py + PANEL_H - 18.0
	_draw_string_at("[ESC] Close   [F1] Close", Vector2(px + SECTION_PAD, footer_y),
		DIM_COLOR, FONT_SIZE_S)

# ─── Generators section ───────────────────────────────────────────────────────
func _draw_generators_section(snap: Dictionary, x: float, y: float, w: float) -> float:
	_draw_section_header("GENERATORS", x, y)
	y += 20.0

	var gens: Array = snap.get("generators", [])
	if gens.is_empty():
		_draw_string_at("  (none registered)", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
		return y + 18.0

	for gen: Dictionary in gens:
		var watts: float  = gen.get("watts", 0.0)
		var running: bool = gen.get("running", false)
		var fuel: float   = gen.get("fuel", 100.0)
		var health: float = gen.get("health", 100.0)
		var backup: bool  = gen.get("is_backup", false)

		var status_col: Color
		var status_str: String
		if backup:
			if running:
				status_str = "BACKUP — ACTIVE"
				status_col = ACCENT_BACKUP
			else:
				status_str = "BACKUP — STANDBY"
				status_col = DIM_COLOR
		else:
			status_str = "RUNNING" if running else "STOPPED"
			status_col = OK_COLOR if running else DIM_COLOR

		var fuel_col: Color = OK_COLOR
		if fuel < 25.0:
			fuel_col = CRIT_COLOR
		elif fuel < 50.0:
			fuel_col = WARN_COLOR

		var line: String = "  [%s] %.0fW  FUEL:%d%%  HP:%d%%" % [
			status_str.substr(0, 7), watts, int(fuel), int(health)]
		_draw_string_at(line, Vector2(x, y), status_col, FONT_SIZE_S)

		# Mini fuel bar
		var bar_x: float = x + w - 64.0
		var bar_w: float = 60.0
		var bar_h: float = 7.0
		_canvas.draw_rect(Rect2(bar_x, y - 10.0, bar_w, bar_h),
			Color(0.15, 0.15, 0.15, 0.9), true)
		_canvas.draw_rect(Rect2(bar_x, y - 10.0, bar_w * fuel / 100.0, bar_h),
			fuel_col, true)
		y += 16.0

	return y + 4.0

# ─── Batteries section ───────────────────────────────────────────────────────
func _draw_batteries_section(snap: Dictionary, x: float, y: float, w: float) -> float:
	_draw_section_header("BATTERIES", x, y)
	y += 20.0

	var batts: Array = snap.get("batteries", [])
	if batts.is_empty():
		_draw_string_at("  (none registered)", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
		return y + 18.0

	for batt: Dictionary in batts:
		var cap: float     = batt.get("capacity_wh", 0.0)
		var charge: float  = batt.get("charge_wh", 0.0)
		var pct: float     = (charge / max(cap, 1.0)) * 100.0

		var batt_col: Color = OK_COLOR
		if pct < 15.0:
			batt_col = CRIT_COLOR
		elif pct < 40.0:
			batt_col = WARN_COLOR

		var line: String = "  Battery  %.0f / %.0f Wh  (%d%%)" % [charge, cap, int(pct)]
		_draw_string_at(line, Vector2(x, y), batt_col, FONT_SIZE_S)

		# Mini charge bar
		var bar_x: float = x + w - 64.0
		var bar_h: float = 7.0
		_canvas.draw_rect(Rect2(bar_x, y - 10.0, 60.0, bar_h),
			Color(0.15, 0.15, 0.15, 0.9), true)
		_canvas.draw_rect(Rect2(bar_x, y - 10.0, 60.0 * pct / 100.0, bar_h),
			batt_col, true)
		y += 16.0

	return y + 4.0

# ─── Wire graph section ───────────────────────────────────────────────────────
func _draw_wire_section(snap: Dictionary, x: float, y: float, _w: float) -> float:
	_draw_section_header("WIRE GRAPH", x, y)
	y += 20.0

	var node_count: int = snap.get("wire_node_count", 0)
	var edge_count: int = snap.get("wire_edge_count", 0)
	var reach_size: int = snap.get("reachable_node_count", 0)
	var overloaded: Array = snap.get("overloaded_edges", [])

	_draw_string_at("  Nodes: %d    Edges: %d    Reachable: %d" % [
		node_count, edge_count, reach_size], Vector2(x, y), TEXT_COLOR, FONT_SIZE_S)
	y += 16.0

	if overloaded.is_empty():
		_draw_string_at("  No overloaded edges", Vector2(x, y), OK_COLOR, FONT_SIZE_S)
	else:
		_draw_string_at("  Overloaded edges: %d" % overloaded.size(), Vector2(x, y), CRIT_COLOR, FONT_SIZE_S)
	y += 16.0

	return y + 4.0

# ─── Load history graph ───────────────────────────────────────────────────────
func _draw_graph_section(x: float, y: float, w: float) -> float:
	_draw_section_header("LOAD HISTORY  (60s)", x, y)
	y += 18.0

	const GRAPH_H: float = 70.0
	var graph_rect: Rect2 = Rect2(x, y, w, GRAPH_H)
	_canvas.draw_rect(graph_rect, Color(0.06, 0.10, 0.06, 0.95), true)
	_canvas.draw_rect(graph_rect, Color(0.28, 0.50, 0.30, 0.60), false, 1.0)

	var n: int = _draw_history.size()
	if n >= 2:
		# Find max for normalisation
		var max_val: float = 1.0
		for i: int in _cap_history.size():
			max_val = maxf(max_val, _cap_history[i])
		for i: int in _draw_history.size():
			max_val = maxf(max_val, _draw_history[i])

		# Capacity line (dimmer)
		var pts_cap: PackedVector2Array = PackedVector2Array()
		for i: int in _cap_history.size():
			var fx: float = x + float(i) / float(HISTORY_LEN - 1) * w
			var fy: float = y + GRAPH_H - (_cap_history[i] / max_val) * (GRAPH_H - 4.0)
			pts_cap.append(Vector2(fx, fy))
		if pts_cap.size() >= 2:
			for i: int in pts_cap.size() - 1:
				_canvas.draw_line(pts_cap[i], pts_cap[i+1], Color(0.30, 0.60, 0.30, 0.55), 1.0)

		# Draw line (bright green)
		var pts_draw: PackedVector2Array = PackedVector2Array()
		for i: int in _draw_history.size():
			var fx: float = x + float(i) / float(HISTORY_LEN - 1) * w
			var fy: float = y + GRAPH_H - (_draw_history[i] / max_val) * (GRAPH_H - 4.0)
			pts_draw.append(Vector2(fx, fy))
		if pts_draw.size() >= 2:
			for i: int in pts_draw.size() - 1:
				_canvas.draw_line(pts_draw[i], pts_draw[i+1], OK_COLOR, 1.5)

	y += GRAPH_H + 8.0
	return y

# ─── Consumers section ────────────────────────────────────────────────────────
func _draw_consumers_section(snap: Dictionary, x: float, y: float, w: float) -> float:
	_draw_section_header("CONSUMERS", x, y)
	y += 20.0

	var consumers: Array = snap.get("consumers", [])
	if consumers.is_empty():
		_draw_string_at("  (none registered)", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
		return y + 18.0

	const MAX_ROWS: int = 10
	var shown: int = 0
	for con: Dictionary in consumers:
		if shown >= MAX_ROWS:
			_draw_string_at("  … +%d more" % (consumers.size() - shown),
				Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
			y += 14.0
			break

		var con_type: String  = str(con.get("type", "?")).substr(0, 9)
		var watts: float      = con.get("watts", 0.0)
		var powered: bool     = con.get("powered", false)
		var shed: bool        = con.get("shed", false)

		var col: Color = OK_COLOR if powered else (WARN_COLOR if shed else DIM_COLOR)
		var status: String = "ON" if powered else ("SHED" if shed else "OFF")
		var line: String = "  %-10s %5.0fW [%s]" % [con_type, watts, status]
		_draw_string_at(line, Vector2(x, y), col, FONT_SIZE_S)
		y += 14.0
		shown += 1

	return y + 4.0

# ─── Breakers section ────────────────────────────────────────────────────────
func _draw_breakers_section(snap: Dictionary, x: float, y: float, _w: float) -> float:
	_draw_section_header("ZONE BREAKERS", x, y)
	y += 20.0

	var zones: Dictionary = snap.get("zones", {})
	if zones.is_empty():
		_draw_string_at("  (no zones defined)", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
		return y + 18.0

	for zone_name: String in zones:
		var zone_data: Dictionary = zones[zone_name]
		var tripped: bool = zone_data.get("tripped", false)
		var col: Color    = CRIT_COLOR if tripped else OK_COLOR
		var status: String = "TRIPPED" if tripped else "ONLINE"
		_draw_string_at("  %-12s [%s]" % [zone_name, status], Vector2(x, y), col, FONT_SIZE_S)
		y += 14.0

	return y + 4.0

# ─── Draw helpers ─────────────────────────────────────────────────────────────
func _draw_section_header(title: String, x: float, y: float) -> void:
	_draw_string_at("▸ " + title, Vector2(x, y), HEADER_COLOR, FONT_SIZE_N)
	_canvas.draw_line(
		Vector2(x, y + 3.0),
		Vector2(x + 180.0, y + 3.0),
		Color(HEADER_COLOR.r, HEADER_COLOR.g, HEADER_COLOR.b, 0.45), 1.0)

func _draw_string_at(text: String, pos: Vector2, color: Color, size: int) -> void:
	# Shadow pass
	_canvas.draw_string(_font, pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	# Main pass
	_canvas.draw_string(_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _grid_state_name(state: int) -> String:
	match state:
		0: return "ONLINE"
		1: return "BROWNOUT"
		2: return "OVERLOADED"
		3: return "TRIPPED"
		4: return "OFFLINE"
	return "UNKNOWN"

func _grid_state_color(state: int) -> Color:
	match state:
		0: return OK_COLOR
		1: return WARN_COLOR
		2: return WARN_COLOR
		3: return CRIT_COLOR
		4: return CRIT_COLOR
	return TEXT_COLOR

func _get_pm() -> Node:
	return get_tree().get_first_node_in_group("power_manager")
