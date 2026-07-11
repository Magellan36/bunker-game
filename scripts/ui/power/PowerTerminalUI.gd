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
##   • Wire graph — node count, edge count, brownout edges
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

## Zone-level scoping — set by PowerTerminal via get_zone_index_for_key().
## When >= 0, the UI filters ALL data (gens, batteries, consumers, zones section)
## to only the single zone at this index. Reset button acts on this zone only.
## When -1, falls back to connected_grid_key BFS (or shows all if that too is empty).
var connected_zone_index: int = -1

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
	## Simple fade-in (graphics plan Section 6/Phase 5, standing convention
	## July 2026 — see UIFade.gd) — purely additive, doesn't touch _on_draw's
	## layout/content logic at all.
	UIFade.fade_in(_canvas)
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
		var mpos: Vector2 = (event as InputEventMouseButton).position
		# Check close button hit rect
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var px: float   = (vp.x - PANEL_W) * 0.5
		var py: float   = (vp.y - PANEL_H) * 0.5
		var close_rect: Rect2 = Rect2(px + PANEL_W - 36.0, py + 8.0, 28.0, 28.0)
		if close_rect.has_point(mpos):
			close()
			get_viewport().set_input_as_handled()
			return
		## Reset Grid / Zone button
		if _reset_grid_rect.size.x > 0 and _reset_grid_rect.has_point(mpos):
			var pm: PowerManager = _get_pm()
			if pm != null:
				if connected_zone_index >= 0:
					pm.reset_zone_by_index(connected_zone_index)
				else:
					pm.reset_main_breaker()
			get_viewport().set_input_as_handled()
			return
		## Rename Zone button — only live when scoped to this terminal's own zone.
		if _rename_zone_rect.size.x > 0 and _rename_zone_rect.has_point(mpos):
			_open_zone_rename()
			get_viewport().set_input_as_handled()
			return
		## Color Zone button — same scoping.
		if _recolor_zone_rect.size.x > 0 and _recolor_zone_rect.has_point(mpos):
			_open_zone_color_picker()
			get_viewport().set_input_as_handled()
			return
		## Per-consumer priority arrows (◄ / ►). Adjust then re-solve grid.
		for hit: Dictionary in _priority_hit_rects:
			var hr: Rect2 = hit.get("rect", Rect2())
			if hr.size.x > 0 and hr.has_point(mpos):
				var cid: String = str(hit.get("id", ""))
				var delta: int  = int(hit.get("delta", 0))
				var pm2: PowerManager = _get_pm()
				if pm2 != null:
					var cur: int = int(pm2.get_consumer_priority(cid))
					pm2.set_consumer_priority(cid, cur + delta)
					_canvas.queue_redraw()
				get_viewport().set_input_as_handled()
				return

		# Eat all clicks inside panel
		var panel_rect: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
		if panel_rect.has_point(mpos):
			get_viewport().set_input_as_handled()

# ─── Process — collect history samples (always runs, even when closed) ────────
func _process(delta: float) -> void:
	## Sample the power manager every SAMPLE_INTERVAL regardless of visibility.
	## This keeps load history continuous so the graph isn't flat after a reopen.
	_sample_timer += delta
	if _sample_timer >= SAMPLE_INTERVAL:
		_sample_timer = 0.0
		var pm: PowerManager = _get_pm()
		if pm != null:
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

	var pm: PowerManager = _get_pm()
	if pm == null:
		_draw_string_at("POWER MANAGER NOT FOUND", Vector2(px + 20.0, py + 40.0), CRIT_COLOR, FONT_SIZE_H)
		return

	var snap: Dictionary = pm.get_debug_snapshot()

	## ── Zone-scoped filtering ────────────────────────────────────────────────
	## If we have a valid zone index, narrow everything to that zone using
	## get_zone_snapshot() — this is the proper zone-aware path that respects
	## breaker boundaries. Falls back to the legacy BFS key path when zone_index=-1.
	if connected_zone_index >= 0:
		var all_zones: Array = pm.get_zone_snapshot()
		## Find the matching zone entry.
		var my_zone: Dictionary = {}
		for zd: Dictionary in all_zones:
			if int(zd.get("zone_index", -1)) == connected_zone_index:
				my_zone = zd
				break

		if not my_zone.is_empty():
			var zone_consumer_set: Dictionary = {}
			for cid: String in my_zone.get("consumer_ids", []):
				zone_consumer_set[cid] = true
			var zone_gen_set: Dictionary = {}
			for gid: String in my_zone.get("generator_ids", []):
				zone_gen_set[gid] = true
			var zone_bat_set: Dictionary = {}
			for bid: String in my_zone.get("battery_ids", []):
				zone_bat_set[bid] = true

			## Filter generators
			var filtered_gens: Array = []
			for g: Dictionary in snap.get("generators", []):
				if zone_gen_set.has(g.get("id", "")):
					filtered_gens.append(g)
			snap["generators"] = filtered_gens

			## Filter batteries
			var filtered_batts: Array = []
			for b: Dictionary in snap.get("batteries", []):
				if zone_bat_set.has(b.get("id", "")):
					filtered_batts.append(b)
			snap["batteries"] = filtered_batts

			## Filter consumers
			var filtered_cons: Array = []
			for c: Dictionary in snap.get("consumers", []):
				if zone_consumer_set.has(c.get("id", "")):
					filtered_cons.append(c)
			snap["consumers"] = filtered_cons

			## Recompute aggregate draw/capacity from zone data only.
			var filtered_draw: float = 0.0
			var filtered_cap:  float = 0.0
			for g2: Dictionary in filtered_gens:
				if g2.get("running", false):
					filtered_cap += float(g2.get("watts", 0.0))
			for c2: Dictionary in filtered_cons:
				if c2.get("powered", false):
					filtered_draw += float(c2.get("watts", 0.0))
			snap["total_draw_watts"]     = filtered_draw
			snap["total_capacity_watts"] = filtered_cap

			## Stamp the zone state string into snap so the header shows it.
			snap["_zone_state_str"] = my_zone.get("state_str", "ONLINE")

	elif not connected_grid_key.is_empty():
		## Legacy fallback: BFS through breakers (shows wider scope than a zone).
		var reachable: Array = pm.get_reachable_device_ids(connected_grid_key)
		var reachable_set: Dictionary = {}
		for rid: String in reachable:
			reachable_set[rid] = true

		var filtered_gens: Array = []
		for g: Dictionary in snap.get("generators", []):
			if reachable_set.has(g.get("id", "")):
				filtered_gens.append(g)
		snap["generators"] = filtered_gens

		var filtered_batts: Array = []
		for b: Dictionary in snap.get("batteries", []):
			if reachable_set.has(b.get("id", "")):
				filtered_batts.append(b)
		snap["batteries"] = filtered_batts

		var filtered_cons: Array = []
		for c: Dictionary in snap.get("consumers", []):
			if reachable_set.has(c.get("id", "")):
				filtered_cons.append(c)
		snap["consumers"] = filtered_cons

		var filtered_draw: float = 0.0
		var filtered_cap:  float = 0.0
		for g2: Dictionary in filtered_gens:
			if g2.get("running", false):
				filtered_cap += float(g2.get("watts", 0.0))
		for c2: Dictionary in filtered_cons:
			if c2.get("powered", false):
				filtered_draw += float(c2.get("watts", 0.0))
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

	## "STATE: ONLINE" removed per user feedback — confusing since it read as
	## the terminal itself being online/powered, when it actually reflected
	## overall grid_state. The per-zone state is still shown further down in
	## the WIRE ZONES / THIS ZONE section, which is the meaningful signal.

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

	## Helper: draw one battery row.
	var _draw_bat_row: Callable = func(batt: Dictionary, indent: String, label_col: Color) -> void:
		var cap: float     = batt.get("capacity_wh", 0.0)
		var charge: float  = batt.get("charge_wh", 0.0)
		var pct: float     = (charge / max(cap, 1.0)) * 100.0
		var discharging: bool = batt.get("discharging", false)
		var charging: bool    = batt.get("charging", false)
		var status_tag: String = " ↓DIS" if discharging else (" ↑CHG" if charging else "")

		var batt_col: Color = label_col
		if pct < 15.0:
			batt_col = CRIT_COLOR
		elif pct < 40.0:
			batt_col = WARN_COLOR

		var line: String = "%sBattery %s %.0f/%.0f Wh (%d%%)" % [
			indent, status_tag, charge, cap, int(pct)]
		_draw_string_at(line, Vector2(x, y), batt_col, FONT_SIZE_S)

		var bar_x: float = x + w - 64.0
		var bar_h: float = 7.0
		_canvas.draw_rect(Rect2(bar_x, y - 10.0, 60.0, bar_h),
			Color(0.15, 0.15, 0.15, 0.9), true)
		_canvas.draw_rect(Rect2(bar_x, y - 10.0, 60.0 * pct / 100.0, bar_h),
			batt_col, true)
		y += 16.0

	## ── Local batteries ───────────────────────────────────────────────────────
	if batts.is_empty():
		_draw_string_at("  (none)", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
		y += 14.0
	else:
		## Build local id set.
		var local_bat_set: Dictionary = {}
		for b: Dictionary in batts:
			local_bat_set[b.get("id", "")] = true
			_draw_bat_row.call(b, "  ", TEXT_COLOR)

	## ── Cross-zone batteries (pass_battery=true links) ────────────────────────
	## Only shown when scoped to a zone. Shows batteries in other zones that are
	## BFS-reachable via pass_battery=true breakers — i.e. this zone can pull
	## from them (or charge them) across the breaker boundary.
	if connected_zone_index >= 0:
		var pm: PowerManager = _get_pm()
		if pm != null:
			var all_zones: Array = pm.get_zone_snapshot()
			var cross_bat_ids: Array = []
			for zd: Dictionary in all_zones:
				if int(zd.get("zone_index", -1)) == connected_zone_index:
					cross_bat_ids = zd.get("cross_battery_ids", [])
					break

			## Build a lookup of all battery data by id.
			var pm_snap: Dictionary = pm.get_debug_snapshot()
			var all_bats_by_id: Dictionary = {}
			for b2: Dictionary in pm_snap.get("batteries", []):
				all_bats_by_id[b2.get("id", "")] = b2

			## Collect cross batteries not already shown locally.
			var local_bat_set2: Dictionary = {}
			for b3: Dictionary in batts:
				local_bat_set2[b3.get("id", "")] = true

			var remote_bats: Array = []
			## Track which zone each battery belongs to (for color).
			## Also build zone_index → color_index for correct palette lookup.
			var bat_to_zone_idx: Dictionary = {}
			var bat_zi_to_ci: Dictionary    = {}
			var bat_zi_to_zk: Dictionary    = {}
			for zd2: Dictionary in all_zones:
				var other_zi: int = int(zd2.get("zone_index", -1))
				bat_zi_to_ci[other_zi] = int(zd2.get("color_index", other_zi))
				bat_zi_to_zk[other_zi] = String(zd2.get("zone_key", ""))
				if other_zi == connected_zone_index:
					continue
				for bid2: String in (zd2.get("battery_ids", []) as Array):
					bat_to_zone_idx[bid2] = other_zi

			for cbid: String in cross_bat_ids:
				if not local_bat_set2.has(cbid) and all_bats_by_id.has(cbid):
					remote_bats.append(all_bats_by_id[cbid])

			if not remote_bats.is_empty():
				y += 4.0
				_canvas.draw_line(Vector2(x, y), Vector2(x + w - 16.0, y),
					Color(0.30, 0.68, 1.00, 0.30), 1.0)
				y += 5.0
				_draw_string_at("  ─ SHARED (via pass-battery breaker) ─",
					Vector2(x, y), Color(0.30, 0.68, 1.00, 0.85), FONT_SIZE_S)
				y += 13.0

				for rb: Dictionary in remote_bats:
					var rbid: String  = rb.get("id", "")
					var rb_zi: int    = int(bat_to_zone_idx.get(rbid, -1))
					var rb_cidx: int  = bat_zi_to_ci.get(rb_zi, rb_zi)
					var rb_zk: String = String(bat_zi_to_zk.get(rb_zi, ""))
					var rb_col: Color = _zone_col(rb_zk, rb_cidx) \
						if rb_zi >= 0 else Color(0.30, 0.68, 1.00, 1.0)
					_draw_bat_row.call(rb, "    ", rb_col)

	return y + 4.0

# ─── Wire graph section ───────────────────────────────────────────────────────
func _draw_wire_section(snap: Dictionary, x: float, y: float, _w: float) -> float:
	_draw_section_header("WIRE GRAPH", x, y)
	y += 20.0

	var node_count: int = snap.get("wire_node_count", 0)
	var edge_count: int = snap.get("wire_edge_count", 0)
	var reach_size: int = snap.get("reachable_node_count", 0)
	var brownout: Array = snap.get("brownout_edges", [])

	_draw_string_at("  Nodes: %d    Edges: %d    Reachable: %d" % [
		node_count, edge_count, reach_size], Vector2(x, y), TEXT_COLOR, FONT_SIZE_S)
	y += 16.0

	if brownout.is_empty():
		_draw_string_at("  No brownout edges", Vector2(x, y), OK_COLOR, FONT_SIZE_S)
	else:
		_draw_string_at("  Brownout edges: %d" % brownout.size(), Vector2(x, y), CRIT_COLOR, FONT_SIZE_S)
	y += 16.0

	## ── Cross-zone power flow ─────────────────────────────────────────────────
	## Show which zones are importing or exporting watts to their neighbors.
	## Data comes from get_zone_snapshot() surplus_w + neighbor_zones fields.
	_draw_string_at("  ZONE FLOW", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
	y += 14.0
	var pm: PowerManager = _get_pm()
	if pm != null:
		var zones: Array = pm.get_zone_snapshot()
		if zones.size() >= 2:
			## Build zone_index → snapshot dict and zone_index → color_index/
			## zone_key/zone_name maps.
			var zone_map: Dictionary = {}
			var zi_to_ci_wg: Dictionary = {}
			var zi_to_zk_wg: Dictionary = {}
			var zi_to_name_wg: Dictionary = {}
			for z: Dictionary in zones:
				var zi: int = z.get("zone_index", -1)
				zone_map[zi] = z
				zi_to_ci_wg[zi] = int(z.get("color_index", zi))
				zi_to_zk_wg[zi] = String(z.get("zone_key", ""))
				zi_to_name_wg[zi] = String(z.get("zone_name", "Z%d" % zi))

			var any_flow: bool = false
			for z: Dictionary in zones:
				var z_idx: int     = z.get("zone_index", 0)
				var surplus: float = z.get("surplus_w", 0.0)
				var neighbors: Array = z.get("neighbor_zones", [])
				if neighbors.is_empty():
					continue

				var z_col: Color = _zone_col(zi_to_zk_wg.get(z_idx, ""), zi_to_ci_wg.get(z_idx, z_idx))

				for nb_idx: int in neighbors:
					## Only draw each pair once (lower index draws the line).
					if nb_idx <= z_idx:
						continue
					any_flow = true

					var nb: Dictionary = zone_map.get(nb_idx, {})
					var nb_surplus: float = nb.get("surplus_w", 0.0)
					var nb_col: Color     = _zone_col(zi_to_zk_wg.get(nb_idx, ""), zi_to_ci_wg.get(nb_idx, nb_idx))

					## Determine direction: who is exporting to whom.
					## If both have surplus or both have deficit, no net flow.
					var flow_w: float
					var arrow: String
					var from_col: Color
					var to_col: Color

					if surplus > 0.0 and nb_surplus <= 0.0:
						## Zone z exports to nb
						flow_w   = minf(surplus, absf(nb_surplus))
						arrow    = "→"
						from_col = z_col
						to_col   = nb_col
					elif nb_surplus > 0.0 and surplus <= 0.0:
						## Zone nb exports to z
						flow_w   = minf(nb_surplus, absf(surplus))
						arrow    = "←"
						from_col = nb_col
						to_col   = z_col
					else:
						## Both surplus or both deficit — no net cross-zone flow
						flow_w   = 0.0
						arrow    = "—"
						from_col = DIM_COLOR
						to_col   = DIM_COLOR

					## Draw zone display-name labels in zone colors; arrow+watts in flow color.
					## Truncated to 6 chars here (this is a tight one-line layout) —
					## the full name is always shown in the zone list below.
					var flow_col: Color = OK_COLOR if flow_w > 0.0 else DIM_COLOR
					var indent: float = x + 8.0
					var cx: float = indent
					var z_label: String  = String(zi_to_name_wg.get(z_idx, "Z%d" % z_idx)).substr(0, 6)
					var nb_label: String = String(zi_to_name_wg.get(nb_idx, "Z%d" % nb_idx)).substr(0, 6)
					_draw_string_at(z_label, Vector2(cx, y), from_col, FONT_SIZE_S)
					cx += maxf(20.0, z_label.length() * 6.5)
					## arrow in flow_col
					_draw_string_at(arrow, Vector2(cx, y), flow_col, FONT_SIZE_S)
					cx += 14.0
					_draw_string_at(nb_label, Vector2(cx, y), to_col, FONT_SIZE_S)
					cx += maxf(22.0, nb_label.length() * 6.5)
					## watts or balanced
					if flow_w > 0.0:
						_draw_string_at("%.0fW" % flow_w, Vector2(cx, y), flow_col, FONT_SIZE_S)
					else:
						_draw_string_at("(balanced)", Vector2(cx, y), DIM_COLOR, FONT_SIZE_S)
					y += 14.0

			if not any_flow:
				_draw_string_at("  No cross-zone links", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
				y += 14.0
		elif zones.size() == 1:
			_draw_string_at("  Single zone — no cross-zone flow", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
			y += 14.0

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

	## Build a set of local consumer IDs for fast lookup.
	var local_con_set: Dictionary = {}
	for con: Dictionary in consumers:
		local_con_set[con.get("id", "")] = true

	## Draw local consumers. Each row gets editable priority arrows ◄ N ►
	## wired (via _unhandled_input hit-test) to pm.set_consumer_priority().
	## These are SAME-ZONE consumers only — snap["consumers"] is already
	## zone-filtered by the terminal before being handed to the UI.
	_priority_hit_rects.clear()
	_draw_string_at("  (◄ N ► sets shed priority: 1=critical, 5=first shed)",
		Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
	y += 14.0

	const MAX_ROWS: int = 8
	var shown: int = 0
	for con: Dictionary in consumers:
		if shown >= MAX_ROWS:
			_draw_string_at("  … +%d more" % (consumers.size() - shown),
				Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
			y += 14.0
			break

		var con_id: String    = str(con.get("id", ""))
		var con_type: String  = str(con.get("type", "?")).substr(0, 9)
		var watts: float      = con.get("watts", 0.0)
		var powered: bool     = con.get("powered", false)
		var shed: bool        = con.get("shed", false)
		var prio: int         = int(con.get("priority", 3))

		var col: Color = OK_COLOR if powered else (WARN_COLOR if shed else DIM_COLOR)
		var status: String = "ON" if powered else ("SHED" if shed else "OFF")
		var line: String = "  %-10s %5.0fW [%-4s]" % [con_type, watts, status]
		_draw_string_at(line, Vector2(x, y), col, FONT_SIZE_S)

		## ── Priority arrows on the right edge of the row ──────────────────
		## Layout: [◄] P# [►]   (◄ lowers priority number, ► raises it)
		var arrow_w: float = 14.0
		var arrow_h: float = 13.0
		var right_x: float = x + w - SECTION_PAD - (arrow_w * 2.0 + 26.0)
		var row_top: float = y - 9.0

		## Left arrow ◄ — decrease priority number (toward 1 = critical)
		var dec_rect: Rect2 = Rect2(right_x, row_top, arrow_w, arrow_h)
		var dec_enabled: bool = prio > 1
		var dec_col: Color = TEXT_COLOR if dec_enabled else DIM_COLOR
		_canvas.draw_rect(dec_rect, Color(0.10, 0.16, 0.10, 0.85), true)
		_canvas.draw_rect(dec_rect, dec_col * Color(1,1,1,0.6), false, 1.0)
		_draw_string_at("◄", Vector2(right_x + 3.0, y), dec_col, FONT_SIZE_S)
		if dec_enabled:
			_priority_hit_rects.append({"rect": dec_rect, "id": con_id, "delta": -1})

		## Priority number readout, tinted by tier.
		var prio_col: Color = OK_COLOR if prio <= 1 else (WARN_COLOR if prio >= 5 else TEXT_COLOR)
		_draw_string_at("P%d" % prio, Vector2(right_x + arrow_w + 5.0, y), prio_col, FONT_SIZE_S)

		## Right arrow ► — increase priority number (toward 5 = first shed)
		var inc_x: float = right_x + arrow_w + 24.0
		var inc_rect: Rect2 = Rect2(inc_x, row_top, arrow_w, arrow_h)
		var inc_enabled: bool = prio < 5
		var inc_col: Color = TEXT_COLOR if inc_enabled else DIM_COLOR
		_canvas.draw_rect(inc_rect, Color(0.10, 0.16, 0.10, 0.85), true)
		_canvas.draw_rect(inc_rect, inc_col * Color(1,1,1,0.6), false, 1.0)
		_draw_string_at("►", Vector2(inc_x + 3.0, y), inc_col, FONT_SIZE_S)
		if inc_enabled:
			_priority_hit_rects.append({"rect": inc_rect, "id": con_id, "delta": 1})

		y += 16.0
		shown += 1

	## ── Remote consumers powered by this zone's generator surplus ─────────────
	## Only shown when this terminal is scoped to a zone AND that zone exports
	## gen power to other zones (pass_generator=true breaker links).
	if connected_zone_index >= 0:
		var pm: PowerManager = _get_pm()
		if pm != null:
			var all_zones: Array = pm.get_zone_snapshot()
			## Find our zone's cross_consumer_ids.
			var cross_con_ids: Array = []
			for zd: Dictionary in all_zones:
				if int(zd.get("zone_index", -1)) == connected_zone_index:
					cross_con_ids = zd.get("cross_consumer_ids", [])
					break

			## Build a lookup of all consumer data keyed by id.
			var pm_snap: Dictionary = pm.get_debug_snapshot()
			var all_cons_by_id: Dictionary = {}
			for c2: Dictionary in pm_snap.get("consumers", []):
				all_cons_by_id[c2.get("id", "")] = c2

			## Remove any that are already in this zone's local list.
			var remote_cons: Array = []
			for rcid: String in cross_con_ids:
				if not local_con_set.has(rcid) and all_cons_by_id.has(rcid):
					remote_cons.append(all_cons_by_id[rcid])

			if not remote_cons.is_empty():
				## Build zone_index → color_index/zone_key map from snapshot.
				var zi_to_ci_rc: Dictionary = {}
				var zi_to_zk_rc: Dictionary = {}
				for zd_rc: Dictionary in all_zones:
					var rc_zi: int = int(zd_rc.get("zone_index", 0))
					zi_to_ci_rc[rc_zi] = int(zd_rc.get("color_index", rc_zi))
					zi_to_zk_rc[rc_zi] = String(zd_rc.get("zone_key", ""))

				## Find source zone index color for each remote consumer.
				## They live in the zones listed in this zone's export_to array.
				var export_to_zones: Array = []
				for zd2: Dictionary in all_zones:
					if int(zd2.get("zone_index", -1)) == connected_zone_index:
						export_to_zones = zd2.get("export_to", [])
						break

				var remote_col: Color = WARN_COLOR
				if export_to_zones.size() > 0:
					var dst_zi: int = int(export_to_zones[0])
					var dst_cidx: int = zi_to_ci_rc.get(dst_zi, dst_zi)
					var dst_zk: String = String(zi_to_zk_rc.get(dst_zi, ""))
					remote_col = _zone_col(dst_zk, dst_cidx)

				## Sub-header.
				y += 4.0
				_canvas.draw_line(Vector2(x, y), Vector2(x + w - 16.0, y),
					remote_col * Color(1, 1, 1, 0.30), 1.0)
				y += 5.0
				_draw_string_at("  ─ REMOTE (powered by this zone) ─",
					Vector2(x, y), remote_col * Color(1, 1, 1, 0.85), FONT_SIZE_S)
				y += 13.0

				var remote_shown: int = 0
				const MAX_REMOTE: int = 5
				for rc: Dictionary in remote_cons:
					if remote_shown >= MAX_REMOTE:
						_draw_string_at("    … +%d more" % (remote_cons.size() - remote_shown),
							Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
						y += 13.0
						break
					var rtype: String  = str(rc.get("type", "?")).substr(0, 9)
					var rwatts: float  = rc.get("watts", 0.0)
					var rpow: bool     = rc.get("powered", false)
					var rshed: bool    = rc.get("shed", false)
					var rcol: Color    = remote_col * Color(1, 1, 1, 0.80)
					var rstatus: String = "ON" if rpow else ("SHED" if rshed else "OFF")
					_draw_string_at("    %-10s %5.0fW [%s]" % [rtype, rwatts, rstatus],
						Vector2(x, y), rcol, FONT_SIZE_S)
					y += 13.0
					remote_shown += 1

	return y + 4.0

## Zone colour palette — matches BuildModeController + BreakerBox + DebugOverlay.
## Order MUST match PowerManager.ZONE_COLORS exactly so debug UI swatches
## show the same hue as the in-world wire tubes.
## Alpha is 1.0 here (UI) vs 0.60 in PM (world geometry).
##
## SINGLE SOURCE OF TRUTH: the real palette lives in PowerManager.ZONE_COLORS.
## Use _zone_col(index) below — it pulls from PowerManager at alpha 1.0 so this
## UI can never desync from the world wires.  The const below is ONLY a fallback
## mirror used if PowerManager isn't reachable; keep it identical to PM's RGB.
const ZONE_PALETTE: Array[Color] = [
	Color(0.35, 0.80, 1.00, 1.0),   ## 0 light blue  (default zone)
	Color(0.10, 0.95, 0.35, 1.0),   ## 1 green
	Color(0.95, 0.18, 0.10, 1.0),   ## 2 red
	Color(0.95, 0.90, 0.10, 1.0),   ## 3 yellow
	Color(0.90, 0.10, 0.95, 1.0),   ## 4 magenta
	Color(0.95, 0.55, 0.10, 1.0),   ## 5 orange
]

## Canonical zone colour at alpha 1.0, sourced from PowerManager.
## Checks the player's per-zone color override first (zone_display_color())
## so a recolored zone's swatches/labels update everywhere in this UI
## instantly — falls back to the local ZONE_PALETTE mirror only if PM is
## unreachable (zone_key is meaningless without PM anyway in that case).
func _zone_col(zone_key: String, color_index: int) -> Color:
	var pm: PowerManager = _get_pm()
	if pm != null:
		return pm.zone_display_color(zone_key, color_index, 1.0)
	return ZONE_PALETTE[color_index % ZONE_PALETTE.size()]

## Hit rect for the Reset Grid button (built during draw, used in input).
var _reset_grid_rect: Rect2 = Rect2()

## Hit rects for the RENAME / COLOR zone buttons — only non-empty (size.x > 0)
## while this terminal is scoped to its own zone (see _draw_breakers_section).
var _rename_zone_rect:  Rect2 = Rect2()
var _recolor_zone_rect: Rect2 = Rect2()

## Lazily-created reusable popup for the rename/recolor UIs (see
## ZoneCustomizeUI.gd). Spawned once, added to the scene root, never freed.
var _zone_customize_ui: CanvasLayer = null

## Hit rects for per-consumer priority arrows, rebuilt every draw.
## Each entry: { "rect": Rect2, "id": String, "delta": int (+1 or -1) }
var _priority_hit_rects: Array[Dictionary] = []

# ─── Zones section (replaces old ZONE BREAKERS) ───────────────────────────────
func _draw_breakers_section(snap: Dictionary, x: float, y: float, w: float) -> float:
	var pm: PowerManager = _get_pm()

	## ── Fetch + filter zone data up front (also needed for the Reset button's
	## label and the new RENAME/COLOR buttons below, not just the list). ──────
	var zone_snap: Array = []
	if pm != null:
		zone_snap = pm.get_zone_snapshot()

	var my_zone: Dictionary = {}   ## this terminal's own zone dict, if scoped.
	if connected_zone_index >= 0:
		var filtered_zones: Array = []
		for zd2: Dictionary in zone_snap:
			if int(zd2.get("zone_index", -1)) == connected_zone_index:
				filtered_zones.append(zd2)
				my_zone = zd2
				break
		zone_snap = filtered_zones

	var my_zone_key:  String = String(my_zone.get("zone_key", ""))
	var my_zone_name: String = String(my_zone.get("zone_name", "Z%d" % connected_zone_index))

	## ── Reset button ─────────────────────────────────────────────────────────
	var btn_w: float  = w - SECTION_PAD
	var btn_h: float  = 22.0
	_reset_grid_rect = Rect2(x, y, btn_w, btn_h)
	var grid_state: int = snap.get("grid_state", 0)

	## Determine if reset is relevant — zone-scoped: check zone state, not grid state.
	var zone_state_for_btn: String = snap.get("_zone_state_str", "")
	var btn_active: bool
	if connected_zone_index >= 0 and zone_state_for_btn != "":
		## Zone mode: active when zone is OFFLINE or OVERLOADED (breakers may be tripped).
		btn_active = (zone_state_for_btn == "OFFLINE")
	else:
		btn_active = (grid_state == 3)   ## 3 = TRIPPED (grid-wide fallback)

	var btn_col: Color = CRIT_COLOR if btn_active else DIM_COLOR
	var btn_bg:  Color = Color(0.25, 0.05, 0.05, 0.90) if btn_active \
		else Color(0.14, 0.14, 0.14, 0.80)
	_canvas.draw_rect(_reset_grid_rect, btn_bg, true)
	_canvas.draw_rect(_reset_grid_rect, btn_col * Color(1,1,1,0.70), false, 1.5)
	var btn_label: String
	if connected_zone_index >= 0:
		btn_label = "⟳  RESET %s" % my_zone_name if btn_active \
			else "RESET %s  (OK)" % my_zone_name
	else:
		btn_label = "⟳  RESET GRID" if btn_active else "RESET GRID  (grid OK)"
	_draw_string_at(btn_label, Vector2(x + 8.0, y + 14.0), btn_col, FONT_SIZE_S)
	y += btn_h + 8.0

	## ── Rename / Color buttons — ONLY for this terminal's OWN zone ──────────
	## Player can only customize the zone this specific terminal is wired
	## into (see PowerTerminal.gd's connected_zone_index scoping) — there is
	## no path to open these for any other zone from this UI.
	_rename_zone_rect = Rect2()
	_recolor_zone_rect = Rect2()
	if connected_zone_index >= 0 and not my_zone_key.is_empty():
		var half_w: float = (btn_w - 6.0) * 0.5
		_rename_zone_rect  = Rect2(x, y, half_w, btn_h)
		_recolor_zone_rect = Rect2(x + half_w + 6.0, y, half_w, btn_h)

		_canvas.draw_rect(_rename_zone_rect, Color(0.10, 0.16, 0.10, 0.85), true)
		_canvas.draw_rect(_rename_zone_rect, TEXT_COLOR * Color(1,1,1,0.6), false, 1.5)
		_draw_string_at("✎  RENAME", Vector2(_rename_zone_rect.position.x + 8.0, y + 14.0), TEXT_COLOR, FONT_SIZE_S)

		_canvas.draw_rect(_recolor_zone_rect, Color(0.10, 0.16, 0.10, 0.85), true)
		_canvas.draw_rect(_recolor_zone_rect, TEXT_COLOR * Color(1,1,1,0.6), false, 1.5)
		_draw_string_at("◍  COLOR", Vector2(_recolor_zone_rect.position.x + 8.0, y + 14.0), TEXT_COLOR, FONT_SIZE_S)

		y += btn_h + 8.0

	## ── Wire Zones ────────────────────────────────────────────────────────────
	## If zone-scoped, only show this terminal's own zone. Otherwise show all.
	var section_title: String = "THIS ZONE" if connected_zone_index >= 0 else "WIRE ZONES"
	_draw_section_header(section_title, x, y)
	y += 20.0

	if zone_snap.is_empty():
		_draw_string_at("  No zone data", Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
		_draw_string_at("  (wire this terminal into an enclosed zone)", Vector2(x, y + 12.0), DIM_COLOR, FONT_SIZE_S)
		return y + 30.0

	## Build zone_index → color_index/zone_key/zone_name maps so UI swatches
	## and labels match in-world wire hues + names. color_index is assigned
	## by PowerManager and may differ from zone_index (e.g. zone 0 might have
	## color_index 2 if colors were shuffled by merges).
	var zi_to_ci:   Dictionary = {}
	var zi_to_zk:   Dictionary = {}
	var zi_to_name: Dictionary = {}
	for zd_all: Dictionary in zone_snap:
		var zi: int = int(zd_all.get("zone_index", 0))
		zi_to_ci[zi]   = int(zd_all.get("color_index", zi))
		zi_to_zk[zi]   = String(zd_all.get("zone_key", ""))
		zi_to_name[zi] = String(zd_all.get("zone_name", "Z%d" % zi))

	for zd: Dictionary in zone_snap:
		var z_idx:   int    = int(zd.get("zone_index", 0))
		var z_cidx:  int    = zi_to_ci.get(z_idx, z_idx)
		var z_key:   String = String(zi_to_zk.get(z_idx, ""))
		var z_name:  String = String(zi_to_name.get(z_idx, "Z%d" % z_idx))
		var z_state: String = zd.get("state_str", "ONLINE")
		var z_cons:  Array  = zd.get("consumer_ids", [])
		var z_gens:  Array  = zd.get("generator_ids", [])
		var z_bats:  Array  = zd.get("battery_ids", [])

		var z_col: Color = _zone_col(z_key, z_cidx)
		var z_state_col: Color
		match z_state:
			"ONLINE":   z_state_col = z_col
			"OVERLOADED": z_state_col = WARN_COLOR
			_:          z_state_col = CRIT_COLOR

		## Zone header row with colour swatch.
		var swatch_rect: Rect2 = Rect2(x, y - 9.0, 10.0, 10.0)
		_canvas.draw_rect(swatch_rect, z_col, true)
		_canvas.draw_rect(swatch_rect, z_col * Color(1,1,1,0.6), false, 1.0)
		_draw_string_at("  %s  [%s]" % [z_name, z_state],
			Vector2(x + 12.0, y), z_state_col, FONT_SIZE_S)
		y += 13.0

		## Device counts on second line.
		var detail: String = "    gen:%d  bat:%d  consumers:%d" % [
			z_gens.size(), z_bats.size(), z_cons.size()]
		_draw_string_at(detail, Vector2(x, y), DIM_COLOR, FONT_SIZE_S)
		y += 11.0

		## ── Import / Export flow banners ──────────────────────────────────
		## Show which neighboring zones supply or receive power via
		## pass_generator=true breakers. Colors match the neighbor zone.
		var import_from: Array = zd.get("import_from", [])
		var export_to:   Array = zd.get("export_to",   [])
		var imported_w: float  = float(zd.get("imported_w", 0.0))
		var exported_w: float  = float(zd.get("exported_w", 0.0))

		if not import_from.is_empty() and imported_w > 0.0:
			## Show one "← from <name>" line per source zone.
			var per_zone_import: float = imported_w / float(import_from.size())
			for src_zi: int in import_from:
				var src_cidx: int  = zi_to_ci.get(src_zi, src_zi)
				var src_key: String = String(zi_to_zk.get(src_zi, ""))
				var src_col: Color = _zone_col(src_key, src_cidx)
				var src_name: String = String(zi_to_name.get(src_zi, "Z%d" % src_zi))
				_draw_string_at(
					"    ← %.0fW  from %s" % [per_zone_import, src_name],
					Vector2(x, y), src_col, FONT_SIZE_S)
				y += 11.0

		if not export_to.is_empty() and exported_w > 0.0:
			## Show one "→ to <name>" line per destination zone.
			var per_zone_export: float = exported_w / float(export_to.size())
			for dst_zi: int in export_to:
				var dst_cidx: int  = zi_to_ci.get(dst_zi, dst_zi)
				var dst_key: String = String(zi_to_zk.get(dst_zi, ""))
				var dst_col: Color = _zone_col(dst_key, dst_cidx)
				var dst_name: String = String(zi_to_name.get(dst_zi, "Z%d" % dst_zi))
				_draw_string_at(
					"    → %.0fW  to %s" % [per_zone_export, dst_name],
					Vector2(x, y), dst_col, FONT_SIZE_S)
				y += 11.0

		## Separator between zones.
		_canvas.draw_line(Vector2(x, y), Vector2(x + w - SECTION_PAD, y),
			z_col * Color(1, 1, 1, 0.20), 1.0)
		y += 5.0

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
		1: return "OVERLOADED"
		2: return "BROWNOUT"
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

func _get_pm() -> PowerManager:
	return get_tree().get_first_node_in_group("power_manager") as PowerManager

# ─── Zone rename / recolor (July 2026) ────────────────────────────────────────
## Lazily creates the reusable ZoneCustomizeUI popup (spawn-once/reuse pattern,
## same as PowerPriorityUI/GeneratorInspectUI). Only ever opened for THIS
## terminal's own connected_zone_index — the RENAME/COLOR buttons themselves
## only exist (non-empty hit rects) while connected_zone_index >= 0, so there
## is no code path here that can target any other zone.
func _ensure_zone_customize_ui() -> CanvasLayer:
	if _zone_customize_ui != null and is_instance_valid(_zone_customize_ui):
		return _zone_customize_ui

	var ui_script: GDScript = load("res://scripts/ui/power/ZoneCustomizeUI.gd")
	if ui_script == null:
		push_warning("[PowerTerminalUI] ZoneCustomizeUI.gd not found")
		return null

	_zone_customize_ui = CanvasLayer.new()
	_zone_customize_ui.set_script(ui_script)
	_zone_customize_ui.name = "ZoneCustomizeUI"
	get_tree().get_root().add_child(_zone_customize_ui)

	if _zone_customize_ui.has_signal("name_changed"):
		_zone_customize_ui.name_changed.connect(_on_zone_name_changed)
	if _zone_customize_ui.has_signal("color_changed"):
		_zone_customize_ui.color_changed.connect(_on_zone_color_changed)

	return _zone_customize_ui


func _open_zone_rename() -> void:
	var pm: PowerManager = _get_pm()
	if pm == null:
		return
	var zone_key: String = _current_zone_key(pm)
	if zone_key.is_empty():
		return
	var ui: CanvasLayer = _ensure_zone_customize_ui()
	if ui == null:
		return
	var current_name: String = pm.get_zone_display_name(zone_key, "Z%d" % connected_zone_index)
	ui.call("open_rename", zone_key, current_name)


func _open_zone_color_picker() -> void:
	var pm: PowerManager = _get_pm()
	if pm == null:
		return
	var zone_key: String = _current_zone_key(pm)
	if zone_key.is_empty():
		return
	var ui: CanvasLayer = _ensure_zone_customize_ui()
	if ui == null:
		return
	## Look up this zone's current color_index so we can find its displayed
	## color at alpha 1.0 (matching the ZONE_PLAYER_COLOR_CHOICES alpha) for
	## the picker's "highlight the currently-active swatch" behavior.
	var zones: Array = pm.get_zone_snapshot()
	var color_index: int = 0
	for zd: Dictionary in zones:
		if int(zd.get("zone_index", -1)) == connected_zone_index:
			color_index = int(zd.get("color_index", 0))
			break
	var current_color: Color = pm.zone_display_color(zone_key, color_index, 1.0)
	ui.call("open_color", zone_key, current_color)


## Resolves connected_zone_index → its zone_key via get_zone_snapshot(). Both
## RENAME and COLOR only ever act on connected_zone_index — this is the single
## place that does the lookup so they can't drift out of sync with each other.
func _current_zone_key(pm: PowerManager) -> String:
	if connected_zone_index < 0:
		return ""
	var zones: Array = pm.get_zone_snapshot()
	for zd: Dictionary in zones:
		if int(zd.get("zone_index", -1)) == connected_zone_index:
			return String(zd.get("zone_key", ""))
	return ""


func _on_zone_name_changed(zone_key: String, new_name: String) -> void:
	var pm: PowerManager = _get_pm()
	if pm != null:
		pm.set_zone_name(zone_key, new_name)
	## Instant visual refresh — no need to wait for the next _process tick.
	_canvas.queue_redraw()


func _on_zone_color_changed(zone_key: String, new_color: Color) -> void:
	var pm: PowerManager = _get_pm()
	if pm != null:
		## Emits PowerManager.zone_color_changed, which BuildModeController is
		## connected to (see its _ready()) and repaints world wire tubes from —
		## so this single call updates the terminal UI, world wires, and every
		## other zone-color display (BreakerBox, DebugOverlay) all at once,
		## since they all read live from PowerManager on their own next redraw.
		pm.set_zone_color_override(zone_key, new_color)
	_canvas.queue_redraw()
