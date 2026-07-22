extends CanvasLayer
## WaterDispenserUI.gd
## ─────────────────────────────────────────────────────────────────────────────
## Restyled Jul 2026 to match the rest of the water/power system's UI language
## — a Control + _on_draw() hand-drawn panel (same shape as WaterInfoUI.gd /
## PowerPriorityUI.gd), NOT a stock Panel/VBoxContainer/CheckBox tree. The
## previous version used Godot's default theme end to end and read like the
## pause menu instead of this game's custom brutalist panels. Interactive
## bits (rate slider, on/off pill, priority ◄►, close ×) are still real
## Button/HSlider nodes — same "draw the background/text, overlay real
## controls positioned each frame" pattern PowerPriorityUI.gd already uses —
## just themed/styled to match instead of left at Godot defaults.
##
## Lifecycle: spawned once by WaterDispenser.on_interact(), reused on
## subsequent opens — same spawn-once-reuse pattern as every other water/
## power device panel in this project.
##
## Everything is pulled live every frame while open (no caching) — the slider
## max (dynamic ceiling, see WaterManager.get_dynamic_max_mL_per_day()) and
## the actual effective rate both need to react instantly to any OTHER
## device's priority/on-off/slider changing anywhere in the network.
##
## Signals:
##   closed — player dismissed the panel (Escape / E / close button)

signal closed

# ─── Palette (matches WaterInfoUI's blue accent — same system, same theme) ───
const BG_COLOR:     Color = Color(0.06, 0.08, 0.10, 0.97)
const BORDER_COLOR: Color = Color(0.35, 0.70, 0.95, 0.80)
const HEADER_COLOR: Color = Color(0.40, 0.75, 1.00, 1.00)
const TEXT_COLOR:   Color = Color(0.85, 0.92, 0.97, 0.95)
const DIM_COLOR:    Color = Color(0.50, 0.58, 0.62, 0.80)
const OK_COLOR:     Color = Color(0.35, 0.85, 1.00, 1.00)
const WARN_COLOR:   Color = Color(1.00, 0.72, 0.10, 1.00)
const CRIT_COLOR:   Color = Color(1.00, 0.35, 0.30, 1.00)

## Water QUALITY red/yellow/green scheme (Jul 2026, Brannon's explicit spec)
## — mirrored verbatim from WaterInfoUI.gd's own QUALITY_GOOD_COLOR/
## _draw_quality_row() (this water UI system duplicates small per-file
## helpers rather than sharing a base class; neither panel script has a
## class_name). Deliberately separate from OK_COLOR above (blue, used for
## the RECEIVING rate's "on target" state — a different meaning).
## Thresholds (inclusive boundaries): 0-50% red, 50.01-75% yellow,
## 75.01-100% green.
const QUALITY_GOOD_COLOR: Color = Color(0.30, 0.85, 0.35, 1.00)

## Delegates to WaterQualityColor.get_color() (Jul 2026, extracted shared
## helper — was a local copy of the same thresholds duplicated from
## WaterInfoUI.gd before).
func _quality_color(quality: float) -> Color:
	return WaterQualityColor.get_color(quality)
const OFF_COLOR:    Color = Color(0.55, 0.55, 0.55, 1.00)
const ACCENT_TOGGLE: Color = Color(0.30, 0.68, 1.00, 1.00)

## Same universal green→red priority legend as PowerPriorityUI.gd /
## WaterInfoUI.gd's sink panel — reused verbatim, not re-themed.
const PRIO_COLORS: Array[Color] = [
	Color(0.30, 1.00, 0.46, 1.00),
	Color(0.62, 0.92, 0.32, 1.00),
	Color(0.98, 0.85, 0.20, 1.00),
	Color(1.00, 0.58, 0.16, 1.00),
	Color(1.00, 0.30, 0.20, 1.00),
]
const PRIORITY_MIN: int = 1
const PRIORITY_MAX: int = 5

# ─── Layout ───────────────────────────────────────────────────────────────────
const PANEL_W: float = 400.0
const PANEL_H: float = 430.0

var _dispenser: WaterDispenser = null
var _is_open: bool = false

# Cached layout anchors filled during draw, used to position live controls.
var _slider_row_y: float = 0.0
var _toggle_row_y: float = 0.0
var _arrow_row_y:  float = 0.0

# ─── Node refs ────────────────────────────────────────────────────────────────
var _canvas:      Control = null
var _font:        Font    = null
var _close_btn:   Button  = null
var _rate_slider: HSlider = null
var _toggle_btn:  Button  = null   ## invisible hit-area over the drawn on/off pill
var _dec_btn:     Button  = null   ## ◄ lower priority tier
var _inc_btn:     Button  = null   ## ► raise priority tier


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
	_canvas.name = "WaterDispenserCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_build_controls()


func _build_controls() -> void:
	_rate_slider = HSlider.new()
	_rate_slider.min_value = 0.0
	_rate_slider.max_value = 0.0   ## set live every frame from the dynamic max
	_rate_slider.step      = 10.0
	_rate_slider.focus_mode = Control.FOCUS_NONE
	_style_slider(_rate_slider)
	_rate_slider.value_changed.connect(_on_rate_changed)
	add_child(_rate_slider)

	_toggle_btn = Button.new()
	_toggle_btn.flat         = true
	_toggle_btn.clip_text    = false
	_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_btn.focus_mode   = Control.FOCUS_NONE
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	add_child(_toggle_btn)

	_dec_btn = Button.new()
	_dec_btn.flat         = false
	_dec_btn.clip_text    = false
	_dec_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_dec_btn.focus_mode   = Control.FOCUS_NONE
	_dec_btn.text         = "◄"
	_dec_btn.pressed.connect(_on_dec_pressed)
	add_child(_dec_btn)

	_inc_btn = Button.new()
	_inc_btn.flat         = false
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


func _style_slider(slider: HSlider) -> void:
	var groove: StyleBoxFlat = StyleBoxFlat.new()
	groove.bg_color = Color(0.10, 0.13, 0.16, 1.0)
	groove.border_color = Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45)
	groove.set_border_width_all(1)
	groove.set_corner_radius_all(3)
	groove.content_margin_top    = 6.0
	groove.content_margin_bottom = 6.0
	slider.add_theme_stylebox_override("slider", groove)

	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(OK_COLOR.r, OK_COLOR.g, OK_COLOR.b, 0.55)
	fill.set_corner_radius_all(3)
	fill.content_margin_top    = 6.0
	fill.content_margin_bottom = 6.0
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)

	var grabber: Texture2D = _make_grabber_texture()
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)
	slider.add_theme_icon_override("grabber_disabled", grabber)


func _make_grabber_texture() -> Texture2D:
	var img: Image = Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in range(14):
		for x: int in range(14):
			var dx: float = float(x) - 6.5
			var dy: float = float(y) - 6.5
			if dx * dx + dy * dy <= 42.0:
				img.set_pixel(x, y, HEADER_COLOR)
	return ImageTexture.create_from_image(img)


# ─── Open / Close ─────────────────────────────────────────────────────────────
func open(dispenser: WaterDispenser) -> void:
	_dispenser = dispenser
	_is_open   = true
	visible    = true
	set_process(true)
	_close_btn.visible   = true
	_rate_slider.visible = true
	_toggle_btn.visible  = true
	_dec_btn.visible     = true
	_inc_btn.visible     = true
	_reposition_controls()
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()


func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_close_btn.visible   = false
	_rate_slider.visible = false
	_toggle_btn.visible  = false
	_dec_btn.visible     = false
	_inc_btn.visible     = false
	closed.emit()


func is_open() -> bool:
	return _is_open


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
	if event is InputEventMouseButton and event.pressed:
		var vp: Vector2  = get_viewport().get_visible_rect().size
		var px: float    = (vp.x - PANEL_W) * 0.5
		var py: float    = (vp.y - PANEL_H) * 0.5
		var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
		if panel.has_point((event as InputEventMouseButton).position):
			get_viewport().set_input_as_handled()


# ─── Live refresh ─────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _dispenser == null or not is_instance_valid(_dispenser):
		close()
		return
	_reposition_controls()
	_canvas.queue_redraw()


# ─── Handlers ─────────────────────────────────────────────────────────────────
func _on_rate_changed(value: float) -> void:
	if _dispenser == null or not is_instance_valid(_dispenser):
		return
	_dispenser.set_requested_rate(value)

func _on_toggle_pressed() -> void:
	if _dispenser == null or not is_instance_valid(_dispenser):
		return
	_dispenser.set_on(not _dispenser.is_on)

func _on_dec_pressed() -> void:
	_apply_priority(-1)

func _on_inc_pressed() -> void:
	_apply_priority(1)

func _apply_priority(delta: int) -> void:
	if _dispenser == null or not is_instance_valid(_dispenser):
		return
	_dispenser.priority = clampi(_dispenser.priority + delta, PRIORITY_MIN, PRIORITY_MAX)
	_canvas.queue_redraw()


# ─── Control positioning ──────────────────────────────────────────────────────
func _reposition_controls() -> void:
	var d: WaterDispenser = _dispenser
	if d == null or not is_instance_valid(d):
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

	## Rate slider — dynamic max reacts live to any other device's priority/
	## on-off/slider changing anywhere in the network (WaterManager delegates
	## to WaterSolver.gd).
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	var dynamic_max: float = 0.0
	if wm != null:
		dynamic_max = wm.get_dynamic_max_mL_per_day(d.get_node_key(), d.priority)
	_rate_slider.max_value = dynamic_max
	_rate_slider.value     = d.requested_rate_mL_per_day

	var slider_y: float = _slider_row_y if _slider_row_y > 0.0 else (py + 150.0)
	_rate_slider.position = Vector2(px + 24.0, slider_y)
	_rate_slider.size      = Vector2(PANEL_W - 48.0, 20.0)

	## On/off pill hit-area.
	var toggle_y: float = _toggle_row_y if _toggle_row_y > 0.0 else (py + 260.0)
	_toggle_btn.position = Vector2(px + 24.0, toggle_y - 6.0)
	_toggle_btn.size     = Vector2(PANEL_W - 48.0, 40.0)

	## Priority arrows.
	var arrow_y: float = _arrow_row_y if _arrow_row_y > 0.0 else (py + 330.0)
	var arrow_sz: Vector2 = Vector2(48.0, 48.0)
	_dec_btn.size = arrow_sz
	_inc_btn.size = arrow_sz
	_dec_btn.position = Vector2(px + 36.0, arrow_y)
	_inc_btn.position = Vector2(px + PANEL_W - 36.0 - arrow_sz.x, arrow_y)
	_style_arrow_btn(_dec_btn, d.priority > PRIORITY_MIN)
	_style_arrow_btn(_inc_btn, d.priority < PRIORITY_MAX)


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


# ─── Draw ─────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	if not _is_open:
		return
	var d: WaterDispenser = _dispenser
	if d == null or not is_instance_valid(d):
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
	_draw_str("WATER DISPENSER", Vector2(cx, cy), HEADER_COLOR, 16)
	cy += 28.0
	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45), 1.0)
	cy += 16.0

	# ── Fill level ───────────────────────────────────────────────────────────
	_draw_str("STORAGE", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str("%.0f / %.0f mL" % [d.current_fill_mL, WaterDispenser.MAX_STORAGE_ML],
		Vector2(cx, cy + 14.0), TEXT_COLOR, 13)
	cy += 40.0

	# ── Water quality (Jul 2026) — same label/value styling as STORAGE above,
	## value colored via the shared red/yellow/green scheme (see
	## QUALITY_GOOD_COLOR / _quality_color() above).
	_draw_str("WATER QUALITY", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str("%.0f%%" % d.stored_water_quality,
		Vector2(cx, cy + 14.0), _quality_color(d.stored_water_quality), 13)
	cy += 40.0

	# ── Requested rate + slider ──────────────────────────────────────────────
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	var dynamic_max: float = 0.0
	if wm != null:
		dynamic_max = wm.get_dynamic_max_mL_per_day(d.get_node_key(), d.priority)

	_draw_str("FLOW RATE", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str("%.0f mL/day  (%.2f mL/min)" % [d.requested_rate_mL_per_day, d.requested_rate_mL_per_day / 1440.0],
		Vector2(px + PANEL_W - 190.0, cy), TEXT_COLOR, 11)
	cy += 16.0
	_slider_row_y = cy
	cy += 30.0
	_draw_str("Network max right now: %.0f mL/day" % dynamic_max, Vector2(cx, cy), DIM_COLOR, 9)
	cy += 24.0

	# ── Effective (actually received) rate ───────────────────────────────────
	var effective_day: float = 0.0
	if wm != null and not d.get_node_key().is_empty():
		var info: Dictionary = wm.get_received_rate_mL(d.get_node_key())
		effective_day = float(info.get("mL_per_day", 0.0))
	var eff_col: Color = OK_COLOR
	if not d.is_on:
		eff_col = OFF_COLOR
	elif effective_day < d.requested_rate_mL_per_day - 1.0:
		eff_col = WARN_COLOR
	_draw_str("RECEIVING", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str("%.0f mL/day  (%.2f mL/min)" % [effective_day, effective_day / 1440.0],
		Vector2(cx, cy + 14.0), eff_col, 13)
	cy += 40.0

	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.30), 1.0)
	cy += 14.0

	# ── On/off pill row ──────────────────────────────────────────────────────
	_toggle_row_y = cy
	var trow: Rect2 = Rect2(cx - 4.0, cy - 6.0, PANEL_W - 40.0, 40.0)
	_canvas.draw_rect(trow, Color(0.10, 0.12, 0.14, 0.70), true)
	_canvas.draw_rect(trow, Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.30), false, 1.0)
	_draw_str("DISPENSER", Vector2(cx + 6.0, cy), TEXT_COLOR, 12)
	var state_str: String = "ON" if d.is_on else "OFF"
	var state_col: Color = ACCENT_TOGGLE if d.is_on else OFF_COLOR
	## Pill switch
	var pill_w: float = 50.0
	var pill_h: float = 24.0
	var pill_x: float = px + PANEL_W - 24.0 - pill_w - 46.0
	var pill_y: float = cy - 2.0
	var pill_r: float = pill_h * 0.5
	var pill_col: Color = state_col
	_canvas.draw_rect(Rect2(pill_x + pill_r, pill_y, pill_w - pill_r * 2.0, pill_h), pill_col, true)
	_canvas.draw_circle(Vector2(pill_x + pill_r, pill_y + pill_r), pill_r, pill_col)
	_canvas.draw_circle(Vector2(pill_x + pill_w - pill_r, pill_y + pill_r), pill_r, pill_col)
	var knob_cx: float = (pill_x + pill_w - pill_r) if d.is_on else (pill_x + pill_r)
	_canvas.draw_circle(Vector2(knob_cx, pill_y + pill_r), pill_r - 3.0, Color(0.92, 0.95, 0.97, 1.0))
	_draw_str(state_str, Vector2(pill_x + pill_w + 10.0, cy), state_col, 12)
	cy += 46.0

	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.30), 1.0)
	cy += 12.0

	# ── Priority changer ─────────────────────────────────────────────────────
	_draw_str("DEMAND PRIORITY", Vector2(cx, cy), DIM_COLOR, 10)
	cy += 18.0
	_arrow_row_y = cy
	var row_h: float = 48.0
	var pcol: Color = PRIO_COLORS[clampi(d.priority - 1, 0, PRIO_COLORS.size() - 1)]
	var num_str: String = str(d.priority)
	var num_size: int = 32
	var num_w: float = _font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, num_size).x
	var num_x: float = px + (PANEL_W - num_w) * 0.5
	var num_y: float = cy + row_h * 0.5 + float(num_size) * 0.35
	var chip_w: float = 84.0
	var chip_rect: Rect2 = Rect2(px + (PANEL_W - chip_w) * 0.5, cy, chip_w, row_h)
	_canvas.draw_rect(chip_rect, Color(pcol.r, pcol.g, pcol.b, 0.14), true)
	_canvas.draw_rect(chip_rect, Color(pcol.r, pcol.g, pcol.b, 0.85), false, 2.0)
	_draw_str(num_str, Vector2(num_x, num_y), pcol, num_size)
	cy += row_h + 6.0

	var tier_name: String = _tier_name(d.priority)
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
		if i + 1 == d.priority:
			_canvas.draw_rect(rect, col, true)
		else:
			_canvas.draw_rect(rect, Color(col.r, col.g, col.b, 0.22), true)
		_canvas.draw_rect(rect, Color(col.r, col.g, col.b, 0.55), false, 1.0)
	cy += 20.0

	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.25), 1.0)
	cy += 12.0

	_draw_str("[◄ ►]  Priority    [ESC / E]  Close", Vector2(cx, py + PANEL_H - 18.0), DIM_COLOR, 9)

	_reposition_controls()


func _tier_name(p: int) -> String:
	match p:
		1: return "CRITICAL"
		2: return "IMPORTANT"
		3: return "STANDARD"
		4: return "LOW"
		5: return "LUXURY"
		_: return "STANDARD"


# ─── String helper (matches WaterInfoUI/PowerPriorityUI style) ──────────────
func _draw_str(text: String, pos: Vector2, color: Color, size: int) -> void:
	_canvas.draw_string(_font, pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	_canvas.draw_string(_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
