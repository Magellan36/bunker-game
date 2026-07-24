extends CanvasLayer
## FarmingTrayUI.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §9.1. Opened by bare-handed E on a fully-soiled
## FarmingTray. Same UIKit-based hand-drawn panel convention as
## WaterDispenserUI.gd/GeneratorInspectUI.gd — NEUTRAL domain (steel-gray),
## since Farming is its own system, not Water or Power.
##
## Priority ◄► widget copied from WaterDispenserUI.gd's own verbatim.
##
## Signals:
##   closed — player dismissed the panel (Escape / E / close button)

signal closed

var _theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)

## Same universal green→red priority legend as WaterDispenserUI.gd/PowerPriorityUI.gd.
const PRIO_COLORS: Array[Color] = [
	Color(0.30, 1.00, 0.46, 1.00),
	Color(0.62, 0.92, 0.32, 1.00),
	Color(0.98, 0.85, 0.20, 1.00),
	Color(1.00, 0.58, 0.16, 1.00),
	Color(1.00, 0.30, 0.20, 1.00),
]
const PRIORITY_MIN: int = 1
const PRIORITY_MAX: int = 5

const PANEL_W: float = 380.0
const PANEL_H: float = 300.0

var _tray: FarmingTray = null
var _is_open: bool = false

var _arrow_row_y: float = 0.0

var _canvas:    Control = null
var _close_btn: Button  = null
var _dec_btn:   Button  = null
var _inc_btn:   Button  = null

func _ready() -> void:
	layer   = 60
	visible = false
	set_process(false)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.name = "FarmingTrayCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_build_controls()

func _build_controls() -> void:
	_dec_btn = Button.new()
	_dec_btn.clip_text    = false
	_dec_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_dec_btn.focus_mode   = Control.FOCUS_NONE
	_dec_btn.text         = "◄"
	_dec_btn.pressed.connect(_on_dec_pressed)
	add_child(_dec_btn)

	_inc_btn = Button.new()
	_inc_btn.clip_text    = false
	_inc_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_inc_btn.focus_mode   = Control.FOCUS_NONE
	_inc_btn.text         = "►"
	_inc_btn.pressed.connect(_on_inc_pressed)
	add_child(_inc_btn)

	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.focus_mode   = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

func open(tray: FarmingTray) -> void:
	_tray    = tray
	_is_open = true
	visible  = true
	set_process(true)
	_close_btn.visible = true
	_dec_btn.visible   = true
	_inc_btn.visible   = true
	_reposition_controls()
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

func is_open() -> bool:
	return _is_open

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventKey and event.pressed:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_E:
			close()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		var vp: Vector2  = get_viewport().get_visible_rect().size
		var px: float    = (vp.x - PANEL_W) * 0.5
		var py: float    = (vp.y - PANEL_H) * 0.5
		if Rect2(px, py, PANEL_W, PANEL_H).has_point((event as InputEventMouseButton).position):
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _tray == null or not is_instance_valid(_tray):
		close()
		return
	_reposition_controls()
	_canvas.queue_redraw()

func _on_dec_pressed() -> void:
	_apply_priority(-1)

func _on_inc_pressed() -> void:
	_apply_priority(1)

func _apply_priority(delta: int) -> void:
	if _tray == null or not is_instance_valid(_tray):
		return
	_tray.priority = clampi(_tray.priority + delta, PRIORITY_MIN, PRIORITY_MAX)
	_canvas.queue_redraw()

func _reposition_controls() -> void:
	if _tray == null or not is_instance_valid(_tray):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

	var arrow_y: float = _arrow_row_y if _arrow_row_y > 0.0 else (py + 240.0)
	var arrow_sz: Vector2 = Vector2(48.0, 48.0)
	_dec_btn.size = arrow_sz
	_inc_btn.size = arrow_sz
	_dec_btn.position = Vector2(px + 36.0, arrow_y)
	_inc_btn.position = Vector2(px + PANEL_W - 36.0 - arrow_sz.x, arrow_y)
	_style_arrow_btn(_dec_btn, _tray.priority > PRIORITY_MIN)
	_style_arrow_btn(_inc_btn, _tray.priority < PRIORITY_MAX)

func _style_arrow_btn(btn: Button, enabled: bool) -> void:
	btn.disabled = not enabled
	btn.add_theme_font_override("font", UIKit.font())
	btn.add_theme_font_size_override("font_size", 22)
	var fg: Color = _theme.header if enabled else Color(0.30, 0.34, 0.36, 1.0)
	for sname: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(sname, UIKit.button_stylebox(_theme, enabled, sname == "hover"))
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_disabled_color", fg)

func _on_draw() -> void:
	if not _is_open:
		return
	var t: FarmingTray = _tray
	if t == null or not is_instance_valid(t):
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	UIKit.draw_backdrop(_canvas, vp, 0.60)
	var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
	UIKit.draw_panel(_canvas, panel, _theme)
	UIKit.draw_close_button(_canvas, panel, _theme)

	var cx: float = px + 24.0
	var cy: float = py + 20.0

	var tray_name: String = "TRAY (SINGLE)" if t.cell_count == 1 else "TRAY (DOUBLE)"
	UIKit.draw_header(_canvas, Vector2(cx, cy), tray_name, _theme, PANEL_W - 48.0, 16)
	cy += 44.0

	## Connection status.
	var connected: bool = t.is_connected_to_water()
	_draw_str("CONNECTION", Vector2(cx, cy), _theme.dim, 10)
	var conn_str: String = "CONNECTED" if connected else "DISCONNECTED"
	var conn_col: Color  = _theme.ok if connected else _theme.crit
	_draw_str(conn_str, Vector2(cx, cy + 14.0), conn_col, 13)
	cy += 40.0

	## Demand vs received.
	var demand: float = t.get_current_demand_mL_per_day()
	var received: float = t.get_water_fraction() * demand
	_draw_str("WATER (RECEIVED / DEMAND)", Vector2(cx, cy), _theme.dim, 10)
	_draw_str("%.0f / %.0f mL/day" % [received, demand], Vector2(cx, cy + 14.0), _theme.text, 13)
	cy += 32.0

	var bar_w: float = PANEL_W - 48.0
	var bar_h: float = 14.0
	UIKit.draw_bar(_canvas, Rect2(cx, cy, bar_w, bar_h), t.get_water_fraction(), _theme)
	cy += bar_h + 24.0

	## Priority.
	_draw_str("PRIORITY", Vector2(cx, cy), _theme.dim, 10)
	_arrow_row_y = cy + 16.0
	var prio_col: Color = PRIO_COLORS[clampi(t.priority - 1, 0, 4)]
	var prio_label: String = "%d" % t.priority
	var lsz: Vector2 = UIKit.font().get_string_size(prio_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	_canvas.draw_string(UIKit.font(), Vector2(px + PANEL_W * 0.5 - lsz.x * 0.5, _arrow_row_y + 34.0),
		prio_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, prio_col)

func _draw_str(text: String, pos: Vector2, color: Color, size: int) -> void:
	UIKit.draw_shadowed_text(_canvas, pos, text, size, color)
