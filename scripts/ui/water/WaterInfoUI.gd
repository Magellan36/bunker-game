extends CanvasLayer
## WaterInfoUI.gd
## ─────────────────────────────────────────────────────────────────────────────
## Step 2 (July 2026) — the water system's first real UI panel
## (docs/systems/water/README.md's scripts/ui/water/ subfolder was
## intentionally empty until now). ONE shared panel for both WaterHookup and
## WaterTestSink, distinguished by `is_source` — matches the plan's explicit
## instruction not to duplicate a near-identical panel for each device.
## Sized/complexity-matched to GeneratorInspectUI.gd (a lightweight info
## popup), NOT the full multi-section PowerTerminalUI dashboard — a 2-4
## number display doesn't need that much panel.
##
## Lifecycle: spawned once by whichever device (hookup or sink) is
## interacted with first, reused on subsequent opens — same
## spawn-once-reuse pattern as GeneratorInspectUI/PowerTerminalUI.
##
## All stats are recomputed live every redraw (no caching) — matches this
## system's existing "compute on demand, no persistence, no ticking" pattern
## from Phase 1 (see docs/systems/water/README.md).
##
## Signals:
##   closed — player dismissed the panel (Escape / E / close button)

signal closed

# ─── Palette (blue accent — distinct from the power system's green theme) ────
const BG_COLOR:     Color = Color(0.06, 0.08, 0.10, 0.97)
const BORDER_COLOR: Color = Color(0.35, 0.70, 0.95, 0.80)
const HEADER_COLOR: Color = Color(0.40, 0.75, 1.00, 1.00)
const TEXT_COLOR:   Color = Color(0.85, 0.92, 0.97, 0.95)
const DIM_COLOR:    Color = Color(0.50, 0.58, 0.62, 0.80)
const OK_COLOR:     Color = Color(0.35, 0.85, 1.00, 1.00)
const WARN_COLOR:   Color = Color(1.00, 0.72, 0.10, 1.00)
const CRIT_COLOR:   Color = Color(1.00, 0.35, 0.30, 1.00)

## Priority tier accent colours (Jul 2026 — demand-priority wiring) — same
## green→red universal tier legend as PowerPriorityUI.gd's PRIO_COLORS; this
## isn't a "power vs water" palette, it's a cross-system meaning (1=critical,
## 5=luxury/first-starved), so it's intentionally reused verbatim rather than
## re-themed blue.
const PRIO_COLORS: Array[Color] = [
	Color(0.30, 1.00, 0.46, 1.00),  ## 1 — critical (green)
	Color(0.62, 0.92, 0.32, 1.00),  ## 2 — important (lime)
	Color(0.98, 0.85, 0.20, 1.00),  ## 3 — standard (yellow)
	Color(1.00, 0.58, 0.16, 1.00),  ## 4 — low (orange)
	Color(1.00, 0.30, 0.20, 1.00),  ## 5 — luxury (red)
]
const PRIORITY_MIN: int = 1
const PRIORITY_MAX: int = 5

# ─── Layout ───────────────────────────────────────────────────────────────────
const PANEL_W: float = 380.0
## Hookup panel has no priority row; sink panel grows to fit the ◄ N ► tier
## changer added Jul 2026 — see _panel_height().
const PANEL_H_SOURCE: float = 230.0
const PANEL_H_SINK:   float = 350.0

# ─── Live data (set by open()) ────────────────────────────────────────────────
var _display_name: String = "Water Device"
var _is_source:    bool   = false   ## true = hookup, false = sink
var _device_ref:   Node   = null

# ─── Node refs ────────────────────────────────────────────────────────────────
var _canvas:   Control = null
var _font:     Font    = null
var _close_btn: Button = null
var _dec_btn:  Button  = null   ## ◄ lower priority tier (sink only)
var _inc_btn:  Button  = null   ## ► raise priority tier (sink only)
var _is_open:  bool    = false
var _arrow_row_y: float = 0.0   ## filled during draw, used to position dec/inc

func _ready() -> void:
	layer   = 60
	visible = false
	set_process(false)

	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.name = "WaterInfoCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

	_dec_btn = Button.new()
	_dec_btn.flat         = false
	_dec_btn.clip_text    = false
	_dec_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_dec_btn.focus_mode   = Control.FOCUS_NONE
	_dec_btn.text         = "◄"
	_dec_btn.visible      = false
	_dec_btn.pressed.connect(_on_dec_pressed)
	add_child(_dec_btn)

	_inc_btn = Button.new()
	_inc_btn.flat         = false
	_inc_btn.clip_text    = false
	_inc_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_inc_btn.focus_mode   = Control.FOCUS_NONE
	_inc_btn.text         = "►"
	_inc_btn.visible      = false
	_inc_btn.pressed.connect(_on_inc_pressed)
	add_child(_inc_btn)

func _panel_height() -> float:
	return PANEL_H_SOURCE if _is_source else PANEL_H_SINK

func _reposition_controls() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ph: float   = _panel_height()
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - ph) * 0.5
	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

	if not _is_source:
		var arrow_y: float = _arrow_row_y if _arrow_row_y > 0.0 else (py + 190.0)
		var arrow_sz: Vector2 = Vector2(48.0, 48.0)
		_dec_btn.size = arrow_sz
		_inc_btn.size = arrow_sz
		_dec_btn.position = Vector2(px + 36.0, arrow_y)
		_inc_btn.position = Vector2(px + PANEL_W - 36.0 - arrow_sz.x, arrow_y)
		var sink: WaterTestSink = _device_ref as WaterTestSink
		var prio: int = sink.priority if sink != null else 3
		_style_arrow_btn(_dec_btn, prio > PRIORITY_MIN)
		_style_arrow_btn(_inc_btn, prio < PRIORITY_MAX)

func _style_arrow_btn(btn: Button, enabled: bool) -> void:
	btn.disabled = not enabled
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 22)
	var base: Color = Color(0.08, 0.11, 0.13, 1.0) if enabled else Color(0.08, 0.09, 0.10, 1.0)
	var fg:   Color = HEADER_COLOR if enabled else Color(0.30, 0.34, 0.36, 1.0)
	for sname: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = base if sname != "hover" else Color(0.14, 0.20, 0.24, 1.0)
		sb.border_color = Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.55 if enabled else 0.2)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override(sname, sb)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_disabled_color", fg)

# ─── Open / Close ─────────────────────────────────────────────────────────────
## is_source = true  → hookup: shows its own tier output + live per-consumer split.
## is_source = false → sink: shows what IT is receiving (traced back to source).
func open(display_name: String, is_source: bool, device_ref: Node) -> void:
	_display_name = display_name
	_is_source    = is_source
	_device_ref   = device_ref

	_is_open = true
	visible  = true
	set_process(true)
	_reposition_controls()
	_close_btn.visible = true
	_dec_btn.visible   = not _is_source
	_inc_btn.visible   = not _is_source
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible = false
	_dec_btn.visible   = false
	_inc_btn.visible   = false
	closed.emit()

# ─── Priority handlers (sink only — Jul 2026) ────────────────────────────────
## ◄ lowers the tier NUMBER → more critical (1 is critical, never starved).
func _on_dec_pressed() -> void:
	_apply_priority(-1)

## ► raises the tier NUMBER → more luxury (5 starved first).
func _on_inc_pressed() -> void:
	_apply_priority(1)

func _apply_priority(delta: int) -> void:
	var sink: WaterTestSink = _device_ref as WaterTestSink
	if sink == null:
		return
	sink.priority = clampi(sink.priority + delta, PRIORITY_MIN, PRIORITY_MAX)
	_reposition_controls()
	_canvas.queue_redraw()

# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_E:
			close()
			get_viewport().set_input_as_handled()
			return
		if not _is_source:
			if k == KEY_LEFT:
				_on_dec_pressed()
				get_viewport().set_input_as_handled()
				return
			if k == KEY_RIGHT:
				_on_inc_pressed()
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseButton and event.pressed:
		var vp: Vector2  = get_viewport().get_visible_rect().size
		var ph: float    = _panel_height()
		var px: float    = (vp.x - PANEL_W) * 0.5
		var py: float    = (vp.y - ph) * 0.5
		var panel: Rect2 = Rect2(px, py, PANEL_W, ph)
		if panel.has_point(event.position):
			get_viewport().set_input_as_handled()

# ─── Process — keep redrawing (live stats) while open ────────────────────────
func _process(_delta: float) -> void:
	if _is_open:
		_canvas.queue_redraw()

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	if not _is_open:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ph: float   = _panel_height()
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - ph) * 0.5

	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.60), true)

	var panel: Rect2 = Rect2(px, py, PANEL_W, ph)
	_canvas.draw_rect(panel, BG_COLOR, true)
	_canvas.draw_rect(panel, BORDER_COLOR, false, 2.0)

	## Close button ×
	var close_rect: Rect2 = Rect2(px + PANEL_W - 40.0, py + 10.0, 30.0, 30.0)
	_canvas.draw_rect(close_rect, Color(0.10, 0.06, 0.06, 0.90), true)
	_canvas.draw_rect(close_rect, CRIT_COLOR, false, 1.5)
	var cp: Vector2 = close_rect.position
	var cs: Vector2 = close_rect.size
	_canvas.draw_line(cp + Vector2(6, 6), cp + cs - Vector2(6, 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)
	_canvas.draw_line(cp + Vector2(cs.x - 6, 6), cp + Vector2(6, cs.y - 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)

	var cx: float = px + 24.0
	var cy: float = py + 20.0

	# ── Header ────────────────────────────────────────────────────────────────
	_draw_str(_display_name.to_upper(), Vector2(cx, cy), HEADER_COLOR, 16)
	cy += 28.0

	## Separator
	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45), 1.0)
	cy += 16.0

	if _is_source:
		cy = _draw_source_stats(cx, cy)
	else:
		cy = _draw_sink_stats(cx, cy)

	var footer_hint: String = "[ESC / E]  Close"
	if not _is_source:
		footer_hint = "[◄ ►]  Priority    [ESC / E]  Close"
	_draw_str(footer_hint, Vector2(cx, py + ph - 18.0), DIM_COLOR, 9)

	_reposition_controls()

## Hookup's own panel: tier output + aggregate priority-tier demand + quality.
## PER-CONSUMER SPLIT wording retired (Jul 2026) — allocation is no longer
## equal, it's a priority-tier waterfall (WaterSolver.gd); a single "each
## device gets X" number no longer means anything, so this now shows total
## REQUESTED demand vs. capacity instead (color-flags oversubscription,
## which is exactly when the waterfall starts scaling/starving lower tiers).
func _draw_source_stats(cx: float, cy: float) -> float:
	var hookup: WaterHookup = _device_ref as WaterHookup
	if hookup == null:
		_draw_str("No hookup data available.", Vector2(cx, cy), WARN_COLOR, 11)
		return cy + 20.0

	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	var daily:   float = hookup.get_daily_output_mL()
	var per_min: float = hookup.get_per_minute_output_mL()
	var count:   int   = 0
	var requested_total: float = 0.0
	if wm != null:
		count           = wm.get_connected_consumer_count(hookup)
		requested_total = wm.get_total_requested_demand_mL(hookup)

	_draw_str("TIER OUTPUT", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str("%.0f mL/day  (%.2f mL/min)" % [daily, per_min], Vector2(cx, cy + 14.0), TEXT_COLOR, 13)
	cy += 40.0

	_draw_str("CONNECTED DEMAND", Vector2(cx, cy), DIM_COLOR, 10)
	if count == 0:
		_draw_str("Not connected to any pipes", Vector2(cx, cy + 14.0), WARN_COLOR, 13)
	else:
		var plural: String = "device" if count == 1 else "devices"
		var demand_col: Color = OK_COLOR if requested_total <= daily else WARN_COLOR
		_draw_str("%d %s connected — requesting %.0f / %.0f mL/day" %
			[count, plural, requested_total, daily], Vector2(cx, cy + 14.0), demand_col, 12)
	cy += 40.0

	cy = _draw_quality_row(hookup.water_quality, cx, cy)
	return cy

## Sink's panel: what it's actually receiving (traced back to the source),
## or "not connected" — reuses is_reachable_from_hookup(), same check the
## sink's own status label already uses, so this never disagrees with it.
func _draw_sink_stats(cx: float, cy: float) -> float:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	var node_key: String = ""
	if _device_ref != null and _device_ref.has_method("get_node_key"):
		node_key = _device_ref.get_node_key()

	var connected: bool = false
	if wm != null and not node_key.is_empty():
		connected = wm.is_reachable_from_hookup(node_key)

	if not connected:
		_draw_str("CONNECTION", Vector2(cx, cy), DIM_COLOR, 10)
		_draw_str("Not connected to a water source", Vector2(cx, cy + 14.0), CRIT_COLOR, 13)
		cy += 40.0
		return _draw_priority_row(cx, cy)

	var info: Dictionary = wm.get_received_rate_mL(node_key) if wm != null else {}
	var mL_day: float = info.get("mL_per_day", 0.0)
	var mL_min: float = info.get("mL_per_minute", 0.0)
	var quality: float = info.get("quality", 0.0)

	_draw_str("RECEIVING", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str("%.0f mL/day  (%.2f mL/min)" % [mL_day, mL_min], Vector2(cx, cy + 14.0), OK_COLOR, 13)
	cy += 40.0

	cy = _draw_quality_row(quality, cx, cy)
	return _draw_priority_row(cx, cy)

## Priority tier changer (Jul 2026, demand-priority wiring) — mirrors
## PowerPriorityUI.gd's chip+pips layout so both systems read identically to
## the player. ◄/► buttons are real Button nodes positioned via
## _reposition_controls(); this just draws the number/label/pips and records
## _arrow_row_y so the buttons line up with the drawn number this frame.
func _draw_priority_row(cx: float, cy: float) -> float:
	var sink: WaterTestSink = _device_ref as WaterTestSink
	var prio: int = sink.priority if sink != null else 3

	_canvas.draw_line(Vector2(cx, cy), Vector2(cx + PANEL_W - 48.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.30), 1.0)
	cy += 12.0
	_draw_str("DEMAND PRIORITY", Vector2(cx, cy), DIM_COLOR, 10)
	cy += 18.0

	_arrow_row_y = cy
	var row_h: float = 48.0
	var pcol: Color = PRIO_COLORS[clampi(prio - 1, 0, PRIO_COLORS.size() - 1)]
	var num_str: String = str(prio)
	var num_size: int = 32
	var num_w: float = _font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, num_size).x
	var px: float = cx - 24.0   ## back out to panel's left edge (cx = px+24)
	var num_x: float = px + (PANEL_W - num_w) * 0.5
	var num_y: float = cy + row_h * 0.5 + float(num_size) * 0.35
	var chip_w: float = 84.0
	var chip_rect: Rect2 = Rect2(px + (PANEL_W - chip_w) * 0.5, cy, chip_w, row_h)
	_canvas.draw_rect(chip_rect, Color(pcol.r, pcol.g, pcol.b, 0.14), true)
	_canvas.draw_rect(chip_rect, Color(pcol.r, pcol.g, pcol.b, 0.85), false, 2.0)
	_draw_str(num_str, Vector2(num_x, num_y), pcol, num_size)
	cy += row_h + 6.0

	var tier_name: String = _tier_name(prio)
	var tn_w: float = _font.get_string_size(tier_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_draw_str(tier_name, Vector2(px + (PANEL_W - tn_w) * 0.5, cy), pcol, 11)
	cy += 20.0

	var pip_total_w: float = PANEL_W - 108.0
	var pip_gap: float = 5.0
	var pip_w: float = (pip_total_w - pip_gap * 4.0) / 5.0
	var pip_x: float = px + 54.0
	for i: int in range(5):
		var col: Color = PRIO_COLORS[i]
		var rect: Rect2 = Rect2(pip_x + float(i) * (pip_w + pip_gap), cy, pip_w, 7.0)
		if i + 1 == prio:
			_canvas.draw_rect(rect, col, true)
		else:
			_canvas.draw_rect(rect, Color(col.r, col.g, col.b, 0.22), true)
		_canvas.draw_rect(rect, Color(col.r, col.g, col.b, 0.55), false, 1.0)
	cy += 18.0
	return cy

func _tier_name(p: int) -> String:
	match p:
		1: return "CRITICAL"
		2: return "IMPORTANT"
		3: return "STANDARD"
		4: return "LOW"
		5: return "LUXURY"
		_: return "STANDARD"

## Shared quality readout — used by both panels. Color-coded the same way
## the power system's fuel/HP bars are (OK/WARN/CRIT thresholds).
func _draw_quality_row(quality: float, cx: float, cy: float) -> float:
	_draw_str("WATER QUALITY", Vector2(cx, cy), DIM_COLOR, 10)
	var q_col: Color = OK_COLOR
	if quality <= 25.0:
		q_col = CRIT_COLOR
	elif quality <= 50.0:
		q_col = WARN_COLOR
	_draw_str("%.0f%%" % quality, Vector2(cx, cy + 14.0), q_col, 13)
	return cy + 40.0

# ─── String helper ────────────────────────────────────────────────────────────
func _draw_str(text: String, pos: Vector2, color: Color, size: int) -> void:
	_canvas.draw_string(_font, pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	_canvas.draw_string(_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
