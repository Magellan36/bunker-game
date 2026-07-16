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

# ─── Layout ───────────────────────────────────────────────────────────────────
const PANEL_W: float = 380.0
const PANEL_H: float = 230.0

# ─── Live data (set by open()) ────────────────────────────────────────────────
var _display_name: String = "Water Device"
var _is_source:    bool   = false   ## true = hookup, false = sink
var _device_ref:   Node   = null

# ─── Node refs ────────────────────────────────────────────────────────────────
var _canvas:   Control = null
var _font:     Font    = null
var _close_btn: Button = null
var _is_open:  bool    = false

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

func _reposition_controls() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5
	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

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
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible = false
	closed.emit()

# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_E:
			close()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		var vp: Vector2  = get_viewport().get_visible_rect().size
		var px: float    = (vp.x - PANEL_W) * 0.5
		var py: float    = (vp.y - PANEL_H) * 0.5
		var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
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
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.60), true)

	var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
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

	_draw_str("[ESC / E]  Close", Vector2(cx, py + PANEL_H - 18.0), DIM_COLOR, 9)

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
		return cy + 40.0

	var info: Dictionary = wm.get_received_rate_mL(node_key) if wm != null else {}
	var mL_day: float = info.get("mL_per_day", 0.0)
	var mL_min: float = info.get("mL_per_minute", 0.0)
	var quality: float = info.get("quality", 0.0)

	_draw_str("RECEIVING", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str("%.0f mL/day  (%.2f mL/min)" % [mL_day, mL_min], Vector2(cx, cy + 14.0), OK_COLOR, 13)
	cy += 40.0

	cy = _draw_quality_row(quality, cx, cy)
	return cy

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
