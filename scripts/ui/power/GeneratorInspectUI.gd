extends CanvasLayer
## GeneratorInspectUI.gd
## Full-screen inspector panel opened when the player interacts (E) with a
## GeneratorObject. Shows generator name, wattage, HP, fuel bar, backup toggle,
## grid state, and an On/Off power button.
##
## Lifecycle: spawned once by GeneratorObject on first interact, reused on
## subsequent opens. Never freed — hidden via close().
##
## Signals:
##   closed               — player dismissed the panel
##   backup_toggled(bool) — player flipped the backup switch; value = new state
##   power_toggled(bool)  — player pressed On/Off; value = desired running state

signal closed
signal backup_toggled(enabled: bool)
signal power_toggled(running: bool)

# ─── Palette (matches bunker military/brutalist theme) ────────────────────────
const BG_COLOR:       Color = Color(0.07, 0.08, 0.07, 0.97)
const BORDER_COLOR:   Color = Color(0.38, 0.85, 0.40, 0.80)
const HEADER_COLOR:   Color = Color(0.32, 0.90, 0.38, 1.00)
const TEXT_COLOR:     Color = Color(0.82, 0.95, 0.84, 0.95)
const DIM_COLOR:      Color = Color(0.45, 0.55, 0.46, 0.80)
const WARN_COLOR:     Color = Color(1.00, 0.72, 0.10, 1.00)
const CRIT_COLOR:     Color = Color(1.00, 0.28, 0.18, 1.00)
const OK_COLOR:       Color = Color(0.30, 1.00, 0.46, 1.00)
const ACCENT_BACKUP:  Color = Color(0.30, 0.68, 1.00, 1.00)
const BTN_ON_COLOR:   Color = Color(0.14, 0.72, 0.30, 1.00)
const BTN_OFF_COLOR:  Color = Color(0.55, 0.14, 0.10, 1.00)
const TRIPPED_COLOR:  Color = Color(0.95, 0.60, 0.08, 1.00)
const OFFLINE_COLOR:  Color = Color(0.60, 0.60, 0.60, 1.00)   ## Grey for OFFLINE grid
const OVERLOADED_COLOR: Color = Color(1.00, 0.85, 0.20, 1.00)   ## Yellow for OVERLOADED

# ─── Layout ───────────────────────────────────────────────────────────────────
const PANEL_W: float = 480.0
const PANEL_H: float = 490.0   ## Extra height for grid state row

# ─── Live data (set by open()) ────────────────────────────────────────────────
var _display_name:  String = "Generator"
var _watts:         float  = 0.0
var _fuel:          float  = 100.0
var _health:        float  = 100.0
var _is_backup:     bool   = false
var _is_running:    bool   = false
var _grid_tripped:  bool   = false
var _grid_state_str: String = "ONLINE"   ## raw string from PM.get_grid_state_string()

# ─── Node refs ────────────────────────────────────────────────────────────────
var _canvas:          Control  = null
var _font:            Font     = null
var _toggle_btn:      Button   = null
var _power_btn:       Button   = null
var _close_btn:       Button   = null
var _is_open:         bool     = false

var _toggle_btn_y:    float    = 0.0
var _power_btn_y:     float    = 0.0

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
	_canvas.name = "GeneratorInspectCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

	_build_controls()

# ─── Control nodes ────────────────────────────────────────────────────────────
func _build_controls() -> void:
	_toggle_btn = Button.new()
	_toggle_btn.flat         = true
	_toggle_btn.clip_text    = false
	_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	add_child(_toggle_btn)

	_power_btn = Button.new()
	_power_btn.flat         = false
	_power_btn.clip_text    = false
	_power_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_power_btn.pressed.connect(_on_power_pressed)
	add_child(_power_btn)

	_close_btn = Button.new()
	_close_btn.flat         = true
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

func _reposition_controls() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	var toggle_y: float = _toggle_btn_y if _toggle_btn_y > 0.0 else (py + 260.0)
	_toggle_btn.position = Vector2(px + 20.0, toggle_y - 4.0)
	_toggle_btn.size     = Vector2(PANEL_W - 40.0, 50.0)

	var btn_w: float = 160.0
	var btn_h: float = 44.0
	var btn_x: float = px + (PANEL_W - btn_w) * 0.5
	var btn_y: float = _power_btn_y if _power_btn_y > 0.0 else (toggle_y + 70.0)
	_power_btn.position = Vector2(btn_x, btn_y)
	_power_btn.size     = Vector2(btn_w, btn_h)
	_style_power_btn()

	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 10.0)
	_close_btn.size     = Vector2(30.0, 30.0)

func _style_power_btn() -> void:
	if _power_btn == null:
		return
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6

	if _grid_tripped and not _is_running:
		## Grid is tripped — show START button so player can reset+restart manually.
		## Pressing it calls GeneratorObject._on_power_toggled(true) which calls
		## pm.reset_main_breaker() then starts this generator.
		style.bg_color     = Color(0.08, 0.28, 0.12, 1.0)
		style.border_color = TRIPPED_COLOR
		style.border_width_top    = 2
		style.border_width_bottom = 2
		style.border_width_left   = 2
		style.border_width_right  = 2
		_power_btn.text        = "START"
		_power_btn.disabled    = false
		_power_btn.add_theme_color_override("font_color", BTN_ON_COLOR)
	elif _is_running:
		style.bg_color     = Color(0.42, 0.08, 0.06, 1.0)
		style.border_color = CRIT_COLOR
		style.border_width_top    = 2
		style.border_width_bottom = 2
		style.border_width_left   = 2
		style.border_width_right  = 2
		_power_btn.text     = "SHUT DOWN"
		_power_btn.disabled = false
		_power_btn.add_theme_color_override("font_color", CRIT_COLOR)
	else:
		style.bg_color     = Color(0.06, 0.30, 0.12, 1.0)
		style.border_color = OK_COLOR
		style.border_width_top    = 2
		style.border_width_bottom = 2
		style.border_width_left   = 2
		style.border_width_right  = 2
		_power_btn.text     = "START"
		_power_btn.disabled = false
		_power_btn.add_theme_color_override("font_color", OK_COLOR)

	_power_btn.add_theme_stylebox_override("normal",   style)
	_power_btn.add_theme_stylebox_override("hover",    style)
	_power_btn.add_theme_stylebox_override("pressed",  style)
	_power_btn.add_theme_stylebox_override("disabled", style)
	_power_btn.add_theme_font_size_override("font_size", 14)

# ─── Open / Close ─────────────────────────────────────────────────────────────

## Open the panel. grid_state_str is the human-readable string from
## PowerManager.get_grid_state_string() — e.g. "ONLINE", "OVERLOADED", "TRIPPED".
func open(display_name: String, watts: float, fuel: float,
		health: float, is_backup: bool, is_running: bool,
		grid_tripped: bool = false,
		grid_state_str: String = "ONLINE") -> void:
	_display_name    = display_name
	_watts           = watts
	_fuel            = clampf(fuel,   0.0, 100.0)
	_health          = clampf(health, 0.0, 100.0)
	_is_backup       = is_backup
	_is_running      = is_running
	_grid_tripped    = grid_tripped
	_grid_state_str  = grid_state_str

	_is_open = true
	visible  = true
	set_process(true)
	_reposition_controls()
	_toggle_btn.visible = true
	_power_btn.visible  = true
	_close_btn.visible  = true
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

## Refresh live state without closing/reopening the panel.
## grid_state_str from PowerManager.get_grid_state_string().
func refresh(fuel: float, health: float, is_backup: bool, is_running: bool,
		grid_tripped: bool = false,
		grid_state_str: String = "ONLINE") -> void:
	_fuel           = clampf(fuel,   0.0, 100.0)
	_health         = clampf(health, 0.0, 100.0)
	_is_backup      = is_backup
	_is_running     = is_running
	_grid_tripped   = grid_tripped
	_grid_state_str = grid_state_str
	_style_power_btn()
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false
	set_process(false)
	_toggle_btn.visible = false
	_power_btn.visible  = false
	_close_btn.visible  = false
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

# ─── Process — keep redrawing while open ──────────────────────────────────────
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

	var border_col: Color = TRIPPED_COLOR if _grid_tripped else BORDER_COLOR
	_canvas.draw_rect(panel, border_col, false, 2.0)

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

	# ── Header ────────────────────────────────────────────────────────────────
	_draw_str(_display_name.to_upper(), Vector2(cx, cy), HEADER_COLOR, 16)
	cy += 28.0

	if _grid_tripped:
		_draw_str("! GRID TRIPPED — START GENERATOR TO RESET GRID",
			Vector2(cx, cy), TRIPPED_COLOR, 10)
		cy += 18.0
	elif _is_backup:
		var badge_text: String = "BACKUP GENERATOR — STANDBY" if not _is_running \
				else "BACKUP GENERATOR — ACTIVE"
		_draw_str(badge_text, Vector2(cx, cy), ACCENT_BACKUP, 11)
		cy += 20.0
	cy += 4.0

	## Separator
	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45), 1.0)
	cy += 12.0

	# ── Stats row ─────────────────────────────────────────────────────────────
	## Output wattage
	_draw_str("OUTPUT", Vector2(cx, cy), DIM_COLOR, 10)
	_draw_str("%.0f W" % _watts, Vector2(cx, cy + 14.0), TEXT_COLOR, 13)

	## Generator status
	var status_str: String
	var status_col: Color
	if _grid_tripped and not _is_running:
		status_str = "OFFLINE"
		status_col = TRIPPED_COLOR
	elif _is_backup and not _is_running:
		status_str = "STANDBY"
		status_col = ACCENT_BACKUP
	elif _is_running:
		status_str = "RUNNING"
		status_col = OK_COLOR
	else:
		status_str = "STOPPED"
		status_col = CRIT_COLOR
	_draw_str("STATUS", Vector2(cx + 140.0, cy), DIM_COLOR, 10)
	_draw_str(status_str, Vector2(cx + 140.0, cy + 14.0), status_col, 13)

	## Grid state — right column
	var gs_col: Color = _grid_state_color(_grid_state_str)
	_draw_str("GRID", Vector2(cx + 280.0, cy), DIM_COLOR, 10)
	_draw_str(_grid_state_str, Vector2(cx + 280.0, cy + 14.0), gs_col, 13)

	cy += 44.0

	# ── Fuel bar ──────────────────────────────────────────────────────────────
	cy = _draw_bar("FUEL", _fuel, cx, cy, PANEL_W - 48.0,
		OK_COLOR, WARN_COLOR, CRIT_COLOR, 50.0, 20.0)
	cy += 10.0

	# ── HP bar ────────────────────────────────────────────────────────────────
	cy = _draw_bar("CONDITION", _health, cx, cy, PANEL_W - 48.0,
		OK_COLOR, WARN_COLOR, CRIT_COLOR, 50.0, 25.0)
	cy += 20.0

	# ── Backup toggle row ─────────────────────────────────────────────────────
	_toggle_btn_y = cy

	var row_rect: Rect2 = Rect2(cx - 4.0, cy - 4.0, PANEL_W - 40.0, 46.0)
	_canvas.draw_rect(row_rect, Color(0.10, 0.12, 0.10, 0.70), true)
	_canvas.draw_rect(row_rect, Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.30), false, 1.0)

	_draw_str("BACKUP GENERATOR", Vector2(cx + 4.0, cy + 4.0), TEXT_COLOR, 11)
	_draw_str("When enabled, this generator idles until grid power fails.",
		Vector2(cx + 4.0, cy + 20.0), DIM_COLOR, 9)

	var pill_w: float   = 50.0
	var pill_h: float   = 26.0
	var pill_x: float   = px + PANEL_W - 24.0 - pill_w
	var pill_y: float   = cy + 10.0
	var pill_r: float   = pill_h * 0.5
	var pill_col: Color = ACCENT_BACKUP if _is_backup else Color(0.20, 0.22, 0.20, 1.0)
	_canvas.draw_rect(Rect2(pill_x + pill_r, pill_y, pill_w - pill_r * 2.0, pill_h),
		pill_col, true)
	_canvas.draw_circle(Vector2(pill_x + pill_r, pill_y + pill_r), pill_r, pill_col)
	_canvas.draw_circle(Vector2(pill_x + pill_w - pill_r, pill_y + pill_r), pill_r, pill_col)
	var knob_cx: float = pill_x + (pill_w - pill_r) if _is_backup else (pill_x + pill_r)
	_canvas.draw_circle(Vector2(knob_cx, pill_y + pill_r), pill_r - 3.0, Color(0.92, 0.95, 0.92, 1.0))

	cy += 46.0
	cy += 12.0

	## Separator before power button
	_canvas.draw_line(Vector2(cx, cy), Vector2(px + PANEL_W - 24.0, cy),
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.25), 1.0)
	cy += 10.0

	# ── On/Off hint ───────────────────────────────────────────────────────────
	var hint: String
	if _grid_tripped and not _is_running:
		hint = "Grid tripped. Press START to reset the grid and restart this generator."
	elif _is_running:
		hint = "Shuts this generator down. Consumers will lose power."
	else:
		hint = "Starts this generator and feeds power to the grid."
	_draw_str(hint, Vector2(cx, cy), DIM_COLOR, 9)
	cy += 16.0

	_power_btn_y = cy
	_reposition_controls()

	_draw_str("[ESC / E]  Close", Vector2(cx, py + PANEL_H - 18.0), DIM_COLOR, 9)


## Returns the colour for a given grid state string.
func _grid_state_color(state: String) -> Color:
	match state:
		"ONLINE":     return OK_COLOR
		"OVERLOADED":   return OVERLOADED_COLOR
		"BROWNOUT": return CRIT_COLOR
		"TRIPPED":    return TRIPPED_COLOR
		"OFFLINE":    return OFFLINE_COLOR
		_:            return DIM_COLOR


# ─── Bar helper ───────────────────────────────────────────────────────────────
func _draw_bar(label: String, value: float,
		x: float, y: float, bar_w: float,
		col_ok: Color, col_warn: Color, col_crit: Color,
		warn_thresh: float, crit_thresh: float) -> float:
	_draw_str(label, Vector2(x, y), DIM_COLOR, 10)
	var pct_str: String = "%d%%" % int(clampf(value, 0.0, 100.0))
	_draw_str(pct_str, Vector2(x + bar_w - 30.0, y), TEXT_COLOR, 10)
	y += 14.0

	const BAR_H: float = 14.0
	_canvas.draw_rect(Rect2(x, y, bar_w, BAR_H), Color(0.12, 0.14, 0.12, 0.90), true)
	_canvas.draw_rect(Rect2(x, y, bar_w, BAR_H), Color(0.28, 0.35, 0.28, 0.50), false, 1.0)

	var fill_w: float = bar_w * clampf(value, 0.0, 100.0) / 100.0
	var fill_col: Color = col_ok
	if value <= crit_thresh:
		fill_col = col_crit
	elif value <= warn_thresh:
		fill_col = col_warn
	if fill_w > 2.0:
		_canvas.draw_rect(Rect2(x, y, fill_w, BAR_H), fill_col, true)

	for pct: float in [25.0, 50.0, 75.0]:
		var tx: float = x + bar_w * pct / 100.0
		_canvas.draw_line(Vector2(tx, y), Vector2(tx, y + BAR_H),
			Color(0.0, 0.0, 0.0, 0.30), 1.0)

	return y + BAR_H + 4.0

# ─── String helper ────────────────────────────────────────────────────────────
func _draw_str(text: String, pos: Vector2, color: Color, size: int) -> void:
	_canvas.draw_string(_font, pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	_canvas.draw_string(_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

# ─── Button handlers ─────────────────────────────────────────────────────────
func _on_toggle_pressed() -> void:
	backup_toggled.emit(not _is_backup)

func _on_power_pressed() -> void:
	power_toggled.emit(not _is_running)
