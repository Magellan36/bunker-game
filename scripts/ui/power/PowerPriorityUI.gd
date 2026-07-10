extends CanvasLayer
## PowerPriorityUI.gd
## A small, reusable inspector panel for setting a powered device's POWER
## PRIORITY (1–5).  Opened when the player presses E on any powered item that
## does not already have its own complex menu (lights, the load-test box, etc.).
##
## DESIGN
##   • Header: device name
##   • Status row: live STATUS (POWERED / SHED / NO POWER / OFF) + wattage draw
##   • Priority changer: ◄  N  ►  — left lowers tier number (more critical),
##     right raises it (more luxury / first to shed)
##   • Note: explains priority 1 (critical, never shed) and priority 5 (first shed)
##   • Optional load toggle row (only shown when the device supplies a toggle)
##
## LIFECYCLE
##   Spawned once by the calling device on first interact, reused on subsequent
##   opens.  Never freed — hidden via close().  The device wires itself to the
##   panel's signals each time it opens (open() rebinds the active target).
##
## SIGNALS
##   closed                       — player dismissed the panel
##   priority_changed(id, value)  — player changed the priority for device `id`
##   load_toggled(id, on)         — player flipped the optional load switch
##
## USAGE (from a device's on_interact):
##   if _prio_ui == null or not is_instance_valid(_prio_ui):
##       _prio_ui = CanvasLayer.new()
##       _prio_ui.set_script(load("res://scripts/ui/power/PowerPriorityUI.gd"))
##       get_tree().get_root().add_child(_prio_ui)
##       _prio_ui.closed.connect(_on_prio_closed)
##       _prio_ui.priority_changed.connect(_on_prio_changed)
##   _prio_ui.open(str(get_instance_id()), "Wall Light")   # show_load_toggle off
##
## The panel pulls live status straight from PowerManager every frame, so the
## device only needs to tell it WHICH consumer id to inspect.

signal closed
signal priority_changed(id: String, value: int)
signal load_toggled(id: String, on: bool)

# ─── Palette (matches bunker military/brutalist theme) ────────────────────────
const BG_COLOR:       Color = Color(0.07, 0.08, 0.07, 0.97)
const BORDER_COLOR:   Color = Color(0.38, 0.85, 0.40, 0.80)
const HEADER_COLOR:   Color = Color(0.32, 0.90, 0.38, 1.00)
const TEXT_COLOR:     Color = Color(0.82, 0.95, 0.84, 0.95)
const DIM_COLOR:      Color = Color(0.45, 0.55, 0.46, 0.80)
const WARN_COLOR:     Color = Color(1.00, 0.72, 0.10, 1.00)
const CRIT_COLOR:     Color = Color(1.00, 0.28, 0.18, 1.00)
const OK_COLOR:       Color = Color(0.30, 1.00, 0.46, 1.00)
const SHED_COLOR:     Color = Color(1.00, 0.55, 0.10, 1.00)   ## orange = shed
const OFF_COLOR:      Color = Color(0.55, 0.55, 0.55, 1.00)   ## grey = switched off
const ACCENT_TOGGLE:  Color = Color(0.30, 0.68, 1.00, 1.00)

## Priority tier accent colours — green (safe/critical) → red (luxury/shed first).
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
const PANEL_W: float = 440.0
## Base height; grows when the load toggle row is shown.
const PANEL_H_BASE:   float = 360.0
const PANEL_H_TOGGLE: float = 420.0

# ─── Live data (set by open(), refreshed each frame from PowerManager) ─────────
var _device_id:      String = ""
var _display_name:   String = "Device"
var _show_toggle:    bool   = false   ## show the load on/off row
var _priority:       int    = 3
var _watts:          float  = 0.0
var _status_str:     String = "NO POWER"
var _active:         bool   = true    ## player switch state (for toggle row)

# ─── Node refs ────────────────────────────────────────────────────────────────
var _canvas:     Control = null
var _font:       Font    = null
var _dec_btn:    Button  = null   ## ◄  lower tier number (toward critical)
var _inc_btn:    Button  = null   ## ►  raise tier number (toward luxury)
var _toggle_btn: Button  = null   ## optional load on/off
var _close_btn:  Button  = null
var _is_open:    bool    = false

# Cached layout anchors filled during draw, used to position buttons.
var _arrow_row_y: float = 0.0
var _toggle_row_y: float = 0.0

# ─────────────────────────────────────────────────────────────────────────────
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
	_canvas.name = "PowerPriorityCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_build_controls()


func _build_controls() -> void:
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

	_toggle_btn = Button.new()
	_toggle_btn.flat         = true
	_toggle_btn.clip_text    = false
	_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_btn.focus_mode   = Control.FOCUS_NONE
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	add_child(_toggle_btn)

	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.focus_mode   = Control.FOCUS_NONE
	_close_btn.pressed.connect(close)
	add_child(_close_btn)


# ─── Public API ───────────────────────────────────────────────────────────────
## Open the panel for the consumer `device_id`.
##   display_name      — shown in the header
##   show_load_toggle  — true to show an on/off load switch (e.g. test box)
func open(device_id: String, display_name: String,
		show_load_toggle: bool = false) -> void:
	_device_id    = device_id
	_display_name = display_name
	_show_toggle  = show_load_toggle

	_pull_status()   ## fetch initial priority/watts/status from PowerManager

	_is_open = true
	visible  = true
	set_process(true)
	_dec_btn.visible    = true
	_inc_btn.visible    = true
	_toggle_btn.visible = show_load_toggle
	_close_btn.visible  = true
	_reposition_controls()
	## Simple fade-in (graphics plan Section 6/Phase 5 "tweened transitions")
	## — purely additive, doesn't touch _on_draw's layout/content logic at all.
	_canvas.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(_canvas, "modulate:a", 1.0, 0.15)
	_canvas.queue_redraw()


func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_dec_btn.visible    = false
	_inc_btn.visible    = false
	_toggle_btn.visible = false
	_close_btn.visible  = false
	closed.emit()


func is_open() -> bool:
	return _is_open


# ─── Live status pull ─────────────────────────────────────────────────────────
## Reads the current consumer state straight from PowerManager so the panel is
## always accurate (priority can change shedding which changes status instantly).
func _pull_status() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null or _device_id.is_empty():
		return
	var s: Dictionary = pm.get_consumer_status(_device_id)
	if not bool(s.get("registered", false)):
		return
	_priority   = int(s.get("priority", 3))
	_watts      = float(s.get("watts", 0.0))
	_status_str = String(s.get("status_str", "NO POWER"))
	_active     = bool(s.get("active", true))


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
		## Keyboard arrows mirror the on-screen ◄ ► buttons for convenience.
		if k == KEY_LEFT:
			_on_dec_pressed()
			get_viewport().set_input_as_handled()
			return
		if k == KEY_RIGHT:
			_on_inc_pressed()
			get_viewport().set_input_as_handled()
			return
	## Swallow clicks inside the panel so they don't fall through to the world.
	if event is InputEventMouseButton and event.pressed:
		var vp: Vector2  = get_viewport().get_visible_rect().size
		var ph: float    = _panel_height()
		var px: float    = (vp.x - PANEL_W) * 0.5
		var py: float    = (vp.y - ph) * 0.5
		var panel: Rect2 = Rect2(px, py, PANEL_W, ph)
		if panel.has_point((event as InputEventMouseButton).position):
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _is_open:
		return
	## Keep status live (shedding can change while the panel is open, e.g. the
	## player drops priority and the item sheds instantly).
	_pull_status()
	_canvas.queue_redraw()


# ─── Button handlers ──────────────────────────────────────────────────────────
## ◄  lowers the tier NUMBER → more critical (1 is critical, never shed).
func _on_dec_pressed() -> void:
	_apply_priority(_priority - 1)

## ►  raises the tier NUMBER → more luxury (5 sheds first).
func _on_inc_pressed() -> void:
	_apply_priority(_priority + 1)

func _apply_priority(new_value: int) -> void:
	var clamped: int = clampi(new_value, PRIORITY_MIN, PRIORITY_MAX)
	if clamped == _priority:
		return
	_priority = clamped
	## Push to PowerManager directly so behaviour is identical no matter which
	## device opened us, then also emit for any device-specific bookkeeping.
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null and not _device_id.is_empty():
		pm.set_consumer_priority(_device_id, clamped)
	priority_changed.emit(_device_id, clamped)
	_pull_status()
	_canvas.queue_redraw()

func _on_toggle_pressed() -> void:
	_active = not _active
	load_toggled.emit(_device_id, _active)
	_pull_status()
	_canvas.queue_redraw()


# ─── Control positioning ──────────────────────────────────────────────────────
func _panel_height() -> float:
	return PANEL_H_TOGGLE if _show_toggle else PANEL_H_BASE

func _reposition_controls() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ph: float   = _panel_height()
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - ph) * 0.5

	## Arrow buttons flank the big priority number. Y is set during draw; until
	## the first draw runs we fall back to a sensible default.
	var arrow_y: float = _arrow_row_y if _arrow_row_y > 0.0 else (py + 150.0)
	var arrow_sz: Vector2 = Vector2(56.0, 56.0)
	_dec_btn.size = arrow_sz
	_inc_btn.size = arrow_sz
	_dec_btn.position = Vector2(px + 40.0, arrow_y)
	_inc_btn.position = Vector2(px + PANEL_W - 40.0 - arrow_sz.x, arrow_y)
	_style_arrow_btn(_dec_btn, _priority > PRIORITY_MIN)
	_style_arrow_btn(_inc_btn, _priority < PRIORITY_MAX)

	## Optional load toggle row.
	if _show_toggle:
		var ty: float = _toggle_row_y if _toggle_row_y > 0.0 else (py + ph - 110.0)
		_toggle_btn.position = Vector2(px + 20.0, ty - 4.0)
		_toggle_btn.size     = Vector2(PANEL_W - 40.0, 50.0)

	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

func _style_arrow_btn(btn: Button, enabled: bool) -> void:
	btn.disabled = not enabled
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 26)
	var base: Color = Color(0.12, 0.16, 0.12, 1.0) if enabled else Color(0.10, 0.11, 0.10, 1.0)
	var fg:   Color = HEADER_COLOR if enabled else Color(0.30, 0.34, 0.30, 1.0)
	for sname: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = base if sname != "hover" else Color(0.18, 0.24, 0.18, 1.0)
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

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var ph: float   = _panel_height()
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - ph) * 0.5

	## Dim backdrop
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.55), true)

	## Panel
	var panel: Rect2 = Rect2(px, py, PANEL_W, ph)
	_canvas.draw_rect(panel, BG_COLOR, true)
	_canvas.draw_rect(panel, BORDER_COLOR, false, 2.0)

	## Close button ×
	var close_rect: Rect2 = Rect2(px + PANEL_W - 40.0, py + 10.0, 30.0, 30.0)
	_canvas.draw_rect(close_rect, Color(0.25, 0.06, 0.06, 0.90), true)
	_canvas.draw_rect(close_rect, CRIT_COLOR, false, 1.5)
	var cp: Vector2 = close_rect.position
	var cs: Vector2 = close_rect.size
	_canvas.draw_line(cp + Vector2(6, 6), cp + cs - Vector2(6, 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)
	_canvas.draw_line(cp + Vector2(cs.x - 6, 6), cp + Vector2(6, cs.y - 6), Color(1.0, 0.7, 0.7, 1.0), 2.0)

	var cx: float = px + 24.0
	var cy: float = py + 20.0

	# ── Header ─────────────────────────────────────────────────────────────────
	_draw_str(_display_name.to_upper(), Vector2(cx, cy), HEADER_COLOR, 16)
	cy += 26.0
	_draw_str("POWER PRIORITY", Vector2(cx, cy), DIM_COLOR, 10)
	cy += 18.0

	## Separator
	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45), 1.0)
	cy += 14.0

	# ── Status + wattage row ────────────────────────────────────────────────────
	_draw_str("STATUS", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str(_status_label(), Vector2(cx, cy + 14.0), _status_color(), 14)

	_draw_str("DRAW", Vector2(px + PANEL_W - 130.0, cy), DIM_COLOR, 10)
	_draw_str("%.0f W" % _watts, Vector2(px + PANEL_W - 130.0, cy + 14.0), TEXT_COLOR, 14)
	cy += 40.0

	## Shed clarification line — make the connected-but-cut state unmistakable.
	if _status_str == "SHED":
		_draw_str("CONNECTED — NOT POWERED (shed)", Vector2(cx, cy), SHED_COLOR, 10)
		cy += 16.0
	cy += 6.0

	# ── Priority changer ────────────────────────────────────────────────────────
	_arrow_row_y = cy
	var row_h: float = 56.0

	## Big centered priority number, colour-coded by tier.
	var pcol: Color = PRIO_COLORS[clampi(_priority - 1, 0, PRIO_COLORS.size() - 1)]
	var num_str: String = str(_priority)
	var num_size: int = 40
	var num_w: float = _font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, num_size).x
	var num_x: float = px + (PANEL_W - num_w) * 0.5
	var num_y: float = cy + row_h * 0.5 + float(num_size) * 0.35
	## Tier chip background behind the number
	var chip_w: float = 96.0
	var chip_x: float = px + (PANEL_W - chip_w) * 0.5
	var chip_rect: Rect2 = Rect2(chip_x, cy, chip_w, row_h)
	_canvas.draw_rect(chip_rect, Color(pcol.r, pcol.g, pcol.b, 0.14), true)
	_canvas.draw_rect(chip_rect, Color(pcol.r, pcol.g, pcol.b, 0.85), false, 2.0)
	_draw_str(num_str, Vector2(num_x, num_y), pcol, num_size)

	## Tier name under the number
	cy += row_h + 6.0
	var tier_name: String = _tier_name(_priority)
	var tn_w: float = _font.get_string_size(tier_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_draw_str(tier_name, Vector2(px + (PANEL_W - tn_w) * 0.5, cy), pcol, 12)
	cy += 22.0

	## Tier pip strip (5 segments, current highlighted)
	var pip_total_w: float = PANEL_W - 120.0
	var pip_gap: float = 6.0
	var pip_w: float = (pip_total_w - pip_gap * 4.0) / 5.0
	var pip_x: float = px + 60.0
	for i: int in range(5):
		var tier: int = i + 1
		var col: Color = PRIO_COLORS[i]
		var rect: Rect2 = Rect2(pip_x + float(i) * (pip_w + pip_gap), cy, pip_w, 8.0)
		if tier == _priority:
			_canvas.draw_rect(rect, col, true)
		else:
			_canvas.draw_rect(rect, Color(col.r, col.g, col.b, 0.22), true)
		_canvas.draw_rect(rect, Color(col.r, col.g, col.b, 0.55), false, 1.0)
	cy += 22.0

	# ── Explanatory note ────────────────────────────────────────────────────────
	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.25), 1.0)
	cy += 12.0
	_draw_str("◄ lower number = more critical", Vector2(cx, cy), DIM_COLOR, 9)
	cy += 14.0
	_draw_str("Priority 1: CRITICAL — never shed when overloaded.",
		Vector2(cx, cy), PRIO_COLORS[0], 9)
	cy += 14.0
	_draw_str("Priority 5: LUXURY — first to be shed when overloaded.",
		Vector2(cx, cy), PRIO_COLORS[4], 9)
	cy += 16.0

	# ── Optional load toggle row ────────────────────────────────────────────────
	if _show_toggle:
		_toggle_row_y = cy
		var trow: Rect2 = Rect2(cx - 4.0, cy - 4.0, PANEL_W - 40.0, 46.0)
		_canvas.draw_rect(trow, Color(0.10, 0.12, 0.10, 0.70), true)
		_canvas.draw_rect(trow, Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.30), false, 1.0)
		_draw_str("LOAD", Vector2(cx + 4.0, cy + 4.0), TEXT_COLOR, 11)
		_draw_str("Toggle whether this device draws from the grid.",
			Vector2(cx + 4.0, cy + 20.0), DIM_COLOR, 9)
		## Pill switch
		var pill_w: float = 50.0
		var pill_h: float = 26.0
		var pill_x: float = px + PANEL_W - 24.0 - pill_w
		var pill_y: float = cy + 10.0
		var pill_r: float = pill_h * 0.5
		var pill_col: Color = ACCENT_TOGGLE if _active else Color(0.20, 0.22, 0.20, 1.0)
		_canvas.draw_rect(Rect2(pill_x + pill_r, pill_y, pill_w - pill_r * 2.0, pill_h), pill_col, true)
		_canvas.draw_circle(Vector2(pill_x + pill_r, pill_y + pill_r), pill_r, pill_col)
		_canvas.draw_circle(Vector2(pill_x + pill_w - pill_r, pill_y + pill_r), pill_r, pill_col)
		var knob_cx: float = (pill_x + pill_w - pill_r) if _active else (pill_x + pill_r)
		_canvas.draw_circle(Vector2(knob_cx, pill_y + pill_r), pill_r - 3.0, Color(0.92, 0.95, 0.92, 1.0))
		cy += 50.0

	## Footer hint
	_draw_str("[◄ ►]  Adjust    [ESC / E]  Close",
		Vector2(cx, py + ph - 18.0), DIM_COLOR, 9)

	## Keep buttons aligned with the freshly computed layout.
	_reposition_controls()


# ─── Status helpers ───────────────────────────────────────────────────────────
func _status_label() -> String:
	match _status_str:
		"POWERED":  return "POWERED"
		"SHED":     return "SHED"
		"OFF":      return "OFF"
		"UNWIRED":  return "NOT WIRED"
		_:          return "NO POWER"

func _status_color() -> Color:
	match _status_str:
		"POWERED":  return OK_COLOR
		"SHED":     return SHED_COLOR
		"OFF":      return OFF_COLOR
		"UNWIRED":  return WARN_COLOR
		_:          return CRIT_COLOR

func _tier_name(p: int) -> String:
	match p:
		1: return "CRITICAL"
		2: return "IMPORTANT"
		3: return "STANDARD"
		4: return "LOW"
		5: return "LUXURY"
		_: return "STANDARD"


# ─── Draw text helper (matches GeneratorInspectUI style) ──────────────────────
func _draw_str(text: String, pos: Vector2, color: Color, size: int) -> void:
	_canvas.draw_string(_font, pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	_canvas.draw_string(_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
