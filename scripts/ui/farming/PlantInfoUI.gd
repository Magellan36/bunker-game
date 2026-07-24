extends CanvasLayer
## PlantInfoUI.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §9.2. Opened by E on a not-yet-ready FarmPlant (a READY
## plant harvests immediately instead — see FarmPlant.on_interact()). Small,
## 3-line panel — sized like GeneratorInspectUI.gd, NEUTRAL UIKit domain.
##
## Signals:
##   closed — player dismissed the panel (Escape / E / close button)

signal closed

var _theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.NEUTRAL)

const PANEL_W: float = 320.0
const PANEL_H: float = 180.0

var _plant_name: String = "Plant"
var _health: float = 100.0
var _is_ready: bool = false
var _is_open: bool = false

var _canvas:    Control = null
var _close_btn: Button  = null

func _ready() -> void:
	layer   = 60
	visible = false
	set_process(false)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.name = "PlantInfoCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.focus_mode   = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

func open(plant_name: String, health: float, is_ready: bool) -> void:
	_plant_name = plant_name
	_health     = clampf(health, 0.0, 100.0)
	_is_ready   = is_ready
	_is_open    = true
	visible     = true
	set_process(true)
	_close_btn.visible = true
	_reposition_controls()
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible = false
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
	_reposition_controls()

func _reposition_controls() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5
	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

func _on_draw() -> void:
	if not _is_open:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	UIKit.draw_backdrop(_canvas, vp, 0.60)
	var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
	UIKit.draw_panel(_canvas, panel, _theme)
	UIKit.draw_close_button(_canvas, panel, _theme)

	var cx: float = px + 24.0
	var cy: float = py + 24.0

	UIKit.draw_header(_canvas, Vector2(cx, cy), _plant_name.to_upper(), _theme, PANEL_W - 48.0, 16)
	cy += 46.0

	## Health.
	UIKit.draw_shadowed_text(_canvas, Vector2(cx, cy), "HEALTH", 10, _theme.dim)
	var health_col: Color = _theme.ok if _health >= 60.0 else (_theme.warn if _health >= 25.0 else _theme.crit)
	UIKit.draw_shadowed_text(_canvas, Vector2(cx, cy + 16.0), "%d%%" % int(round(_health)), 15, health_col)
	cy += 42.0

	var bar_w: float = PANEL_W - 48.0
	var bar_h: float = 12.0
	UIKit.draw_bar(_canvas, Rect2(cx, cy, bar_w, bar_h), _health / 100.0, _theme, health_col)
	cy += bar_h + 22.0

	## Ready / Not Ready — a plant showing READY here would only ever happen
	## if the harvest-priority behavior in FarmPlant.on_interact() gets
	## flipped in the future (see that file's own comment); built for
	## correctness anyway per plan §9.2.
	var ready_str: String = "READY" if _is_ready else "NOT READY"
	var ready_col: Color  = _theme.ok if _is_ready else _theme.crit
	var rsz: Vector2 = UIKit.font().get_string_size(ready_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	UIKit.draw_shadowed_text(_canvas, Vector2(px + PANEL_W * 0.5 - rsz.x * 0.5, cy), ready_str, 18, ready_col)
