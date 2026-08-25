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

# ─── Palette + geometry (sourced from BunkerTheme — the UI design catalog,
## see assets/fonts/BunkerTheme.tres). Loaded in _load_theme() (from _ready);
## these defaults are fallbacks if the theme resource is missing.
var BG_COLOR:       Color = Color(0.08, 0.08, 0.09, 0.97)
## Shared backdrop dim — read from UI/backdrop_alpha_permille (Aug 2026).
var _backdrop_alpha: float = 0.60
var BORDER_COLOR:   Color = Color(0.55, 0.58, 0.62, 0.70)
var HEADER_COLOR:   Color = Color(0.80, 0.82, 0.86, 1.00)
var TEXT_COLOR:     Color = Color(0.85, 0.86, 0.88, 0.95)
var DIM_COLOR:      Color = Color(0.50, 0.52, 0.55, 0.80)
var WARN_COLOR:     Color = Color(1.00, 0.72, 0.10, 1.00)
var CRIT_COLOR:     Color = Color(1.00, 0.35, 0.30, 1.00)
var OK_COLOR:       Color = Color(0.35, 0.85, 1.00, 1.00)
var ACCENT_BACKUP:  Color = Color(0.30, 0.68, 1.00, 1.00)   ## unchanged, functional not identity
var ACCENT_COLOR:   Color = Color(0.90, 0.80, 0.20, 1.00)   ## Jul 2026 — yellow (was green), this panel's top-stripe color
var BTN_ON_COLOR:   Color = Color(0.14, 0.72, 0.30, 1.00)
var BTN_OFF_COLOR:  Color = Color(0.55, 0.14, 0.10, 1.00)
var TRIPPED_COLOR:  Color = Color(0.95, 0.60, 0.08, 1.00)
var OFFLINE_COLOR:  Color = Color(0.60, 0.60, 0.60, 1.00)   ## Grey for OFFLINE grid
var OVERLOADED_COLOR: Color = Color(1.00, 0.85, 0.20, 1.00)   ## Yellow for OVERLOADED

# ─── Layout ───────────────────────────────────────────────────────────────────
var PANEL_W: float = 480.0
var PANEL_H: float = 490.0   ## Extra height for grid state row

## Component geometry / colors read from BunkerTheme's GeneratorUI section.
var _bar_h: float = 14.0
var _fuel_warn: float = 50.0
var _fuel_crit: float = 20.0
var _health_warn: float = 50.0
var _health_crit: float = 25.0
var _power_btn_w: float = 160.0
var _power_btn_h: float = 44.0
var _toggle_btn_h: float = 50.0
var _pill_w: float = 50.0
var _pill_h: float = 26.0
var _start_bg: Color = Color(0.08, 0.28, 0.12, 1.0)
var _running_bg: Color = Color(0.42, 0.08, 0.06, 1.0)
var _standby_bg: Color = Color(0.06, 0.30, 0.12, 1.0)
var _pill_on: Color = Color(0.30, 0.68, 1.00, 1.00)
var _pill_off: Color = Color(0.20, 0.22, 0.20, 1.0)
var _pill_knob: Color = Color(0.92, 0.95, 0.92, 1.0)
var _bar_groove: Color = Color(0.12, 0.14, 0.12, 0.90)
var _bar_border: Color = Color(0.28, 0.35, 0.28, 0.50)
## Cached BunkerTheme reference (set in _load_theme) — used for the
## ActionButton stylebox lookups (START / SHUT DOWN power button).
var _theme: Theme = null

## Pulls every palette + component value from BunkerTheme so the theme is the
## single source of truth (tweak there, this panel follows).
func _load_theme() -> void:
	var t: Theme = load("res://assets/fonts/BunkerTheme.tres") as Theme
	if t == null:
		return
	_theme = t
	BG_COLOR = t.get_color("bg", "UI")
	BORDER_COLOR = t.get_color("border", "UI")
	HEADER_COLOR = t.get_color("header", "UI")
	TEXT_COLOR = t.get_color("text", "UI")
	DIM_COLOR = t.get_color("dim", "UI")
	OK_COLOR = t.get_color("ok", "UI")
	WARN_COLOR = t.get_color("warn", "UI")
	CRIT_COLOR = t.get_color("crit", "UI")
	ACCENT_COLOR = t.get_color("power_accent", "UI")
	ACCENT_BACKUP = t.get_color("accent_backup", "UI")
	BTN_ON_COLOR = t.get_color("btn_on", "GeneratorUI")
	BTN_OFF_COLOR = t.get_color("btn_off", "GeneratorUI")
	TRIPPED_COLOR = t.get_color("tripped", "GeneratorUI")
	OFFLINE_COLOR = t.get_color("offline", "GeneratorUI")
	OVERLOADED_COLOR = t.get_color("overloaded", "GeneratorUI")
	_start_bg = t.get_color("start_bg", "GeneratorUI")
	_running_bg = t.get_color("running_bg", "GeneratorUI")
	_standby_bg = t.get_color("standby_bg", "GeneratorUI")
	_pill_on = t.get_color("backup_pill_on", "GeneratorUI")
	_pill_off = t.get_color("backup_pill_off", "GeneratorUI")
	_pill_knob = t.get_color("pill_knob", "GeneratorUI")
	_bar_groove = t.get_color("bar_groove", "GeneratorUI")
	_bar_border = t.get_color("bar_border", "GeneratorUI")
	PANEL_W = t.get_constant("panel_w", "GeneratorUI")
	PANEL_H = t.get_constant("panel_h", "GeneratorUI")
	_bar_h = t.get_constant("bar_h", "GeneratorUI")
	_fuel_warn = t.get_constant("fuel_warn_thresh", "GeneratorUI")
	_fuel_crit = t.get_constant("fuel_crit_thresh", "GeneratorUI")
	_health_warn = t.get_constant("health_warn_thresh", "GeneratorUI")
	_health_crit = t.get_constant("health_crit_thresh", "GeneratorUI")
	_power_btn_w = t.get_constant("power_btn_w", "GeneratorUI")
	_power_btn_h = t.get_constant("power_btn_h", "GeneratorUI")
	_toggle_btn_h = t.get_constant("toggle_btn_h", "GeneratorUI")
	_pill_w = t.get_constant("backup_pill_w", "GeneratorUI")
	_pill_h = t.get_constant("backup_pill_h", "GeneratorUI")
	_backdrop_alpha = float(UIKit.theme_constant("UI", "backdrop_alpha_permille", 600)) / 1000.0

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
	_load_theme()
	layer   = 60
	visible = false
	## Controller navigation (Aug 2026) — d-pad + left stick drive focus,
	## B closes this UI. See scripts/ui/common/ControllerUINavigation.gd.
	var controller_nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	controller_nav.ui_root = self
	add_child(controller_nav)
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
	_toggle_btn.size     = Vector2(PANEL_W - 40.0, _toggle_btn_h)

	var btn_w: float = _power_btn_w
	var btn_h: float = _power_btn_h
	var btn_x: float = px + (PANEL_W - btn_w) * 0.5
	var btn_y: float = _power_btn_y if _power_btn_y > 0.0 else (toggle_y + 70.0)
	_power_btn.position = Vector2(btn_x, btn_y)
	_power_btn.size     = Vector2(btn_w, btn_h)
	_style_power_btn()

	_close_btn.position = Vector2(px + PANEL_W - 40.0, py + 16.0)   ## Jul 2026 — +6px top-padding pass, must match the drawn X above
	_close_btn.size     = Vector2(30.0, 30.0)

func _style_power_btn() -> void:
	if _power_btn == null:
		return
	var style: StyleBoxFlat = null
	var label: String
	var text_col: Color
	if _grid_tripped and not _is_running:
		## Grid is tripped — show START button so player can reset+restart manually.
		## Pressing it calls GeneratorObject._on_power_toggled(true) which calls
		## pm.reset_main_breaker() then starts this generator.
		style = _action_style("start_tripped")
		label = "START"
		text_col = _action_text_color("text_tripped", BTN_ON_COLOR)
	elif _is_running:
		style = _action_style("shutdown")
		label = "SHUT DOWN"
		text_col = _action_text_color("text_shutdown", CRIT_COLOR)
	else:
		style = _action_style("start")
		label = "START"
		text_col = _action_text_color("text_start", OK_COLOR)
	_power_btn.text     = label
	_power_btn.disabled = false
	_power_btn.add_theme_color_override("font_color", text_col)
	_power_btn.add_theme_stylebox_override("normal",   style)
	_power_btn.add_theme_stylebox_override("hover",    style)
	_power_btn.add_theme_stylebox_override("pressed",  style)
	_power_btn.add_theme_stylebox_override("disabled", style)
	_power_btn.add_theme_font_size_override("font_size",
		_theme.get_font_size("font_size", "ActionButton") if _theme != null else 14)

## Returns the ActionButton stylebox from BunkerTheme (the source of truth for
## the START / SHUT DOWN element), falling back to a locally-built StyleBoxFlat
## from the theme-sourced vars if the theme resource is missing.
func _action_style(name: String) -> StyleBoxFlat:
	if _theme != null:
		var sb := _theme.get_stylebox(name, "ActionButton") as StyleBoxFlat
		if sb != null:
			return sb
	var sb2 := StyleBoxFlat.new()
	sb2.corner_radius_top_left     = 6
	sb2.corner_radius_top_right    = 6
	sb2.corner_radius_bottom_left  = 6
	sb2.corner_radius_bottom_right = 6
	sb2.set_border_width_all(2)
	match name:
		"start":
			sb2.bg_color = _standby_bg
			sb2.border_color = OK_COLOR
		"start_tripped":
			sb2.bg_color = _start_bg
			sb2.border_color = TRIPPED_COLOR
		"shutdown":
			sb2.bg_color = _running_bg
			sb2.border_color = CRIT_COLOR
	return sb2

## ActionButton text color from BunkerTheme, falling back to the given color.
func _action_text_color(name: String, fallback: Color) -> Color:
	if _theme != null:
		var c := _theme.get_color(name, "ActionButton")
		if c.a > 0.0:
			return c
	return fallback

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
## Redraw throttle (Aug 2026 optimization) — live readouts don't need 60Hz.
const REDRAW_INTERVAL: float = 0.1
var _redraw_accum: float = 0.0

func _process(_delta: float) -> void:
	if not _is_open:
		return
	_redraw_accum += _delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		_canvas.queue_redraw()

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _on_draw() -> void:
	if not _is_open:
		return

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var px: float   = (vp.x - PANEL_W) * 0.5
	var py: float   = (vp.y - PANEL_H) * 0.5

	_canvas.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, _backdrop_alpha), true)

	var panel: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)
	var border_col: Color = TRIPPED_COLOR if _grid_tripped else BORDER_COLOR
	UIKit.draw_rounded_rect(_canvas, panel, BG_COLOR, border_col, 2.0)
	UIKit.draw_domain_stripe(_canvas, panel, ACCENT_COLOR)

	## Close button ×
	var close_rect: Rect2 = Rect2(px + PANEL_W - 40.0, py + 16.0, 30.0, 30.0)
	UIKit.draw_rounded_rect(_canvas, close_rect, Color(0.10, 0.06, 0.06, 0.90), CRIT_COLOR, 1.5)
	UIKit.draw_close_icon(_canvas, close_rect)

	var cx: float = px + 24.0
	var cy: float = py + 26.0   ## Jul 2026 — +6px top-padding pass

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
		Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.45), 1.0, true)
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
		OK_COLOR, WARN_COLOR, CRIT_COLOR, _fuel_warn, _fuel_crit)
	cy += 10.0

	# ── HP bar ────────────────────────────────────────────────────────────────
	cy = _draw_bar("CONDITION", _health, cx, cy, PANEL_W - 48.0,
		OK_COLOR, WARN_COLOR, CRIT_COLOR, _health_warn, _health_crit)
	cy += 20.0

	# ── Backup toggle row ─────────────────────────────────────────────────────
	_toggle_btn_y = cy

	var row_rect: Rect2 = Rect2(cx - 4.0, cy - 4.0, PANEL_W - 40.0, 46.0)
	_canvas.draw_rect(row_rect, Color(0.10, 0.12, 0.10, 0.70), true)
	_canvas.draw_rect(row_rect, Color(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.30), false, 1.0)

	_draw_str("BACKUP GENERATOR", Vector2(cx + 4.0, cy + 4.0), TEXT_COLOR, 11)
	_draw_str("When enabled, this generator idles until grid power fails.",
		Vector2(cx + 4.0, cy + 20.0), DIM_COLOR, 9)

	var pill_w: float   = _pill_w
	var pill_h: float   = _pill_h
	var pill_x: float   = px + PANEL_W - 24.0 - pill_w
	var pill_y: float   = cy + 10.0
	var pill_r: float   = pill_h * 0.5
	var pill_col: Color = _pill_on if _is_backup else _pill_off
	_canvas.draw_rect(Rect2(pill_x + pill_r, pill_y, pill_w - pill_r * 2.0, pill_h),
		pill_col, true)
	_canvas.draw_circle(Vector2(pill_x + pill_r, pill_y + pill_r), pill_r, pill_col)
	_canvas.draw_circle(Vector2(pill_x + pill_w - pill_r, pill_y + pill_r), pill_r, pill_col)
	var knob_cx: float = pill_x + (pill_w - pill_r) if _is_backup else (pill_x + pill_r)
	_canvas.draw_circle(Vector2(knob_cx, pill_y + pill_r), pill_r - 3.0, _pill_knob)

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

	_canvas.draw_rect(Rect2(x, y, bar_w, _bar_h), _bar_groove, true)
	_canvas.draw_rect(Rect2(x, y, bar_w, _bar_h), _bar_border, false, 1.0)

	var fill_w: float = bar_w * clampf(value, 0.0, 100.0) / 100.0
	var fill_col: Color = col_ok
	if value <= crit_thresh:
		fill_col = col_crit
	elif value <= warn_thresh:
		fill_col = col_warn
	if fill_w > 2.0:
		_canvas.draw_rect(Rect2(x, y, fill_w, _bar_h), fill_col, true)

	for pct: float in [25.0, 50.0, 75.0]:
		var tx: float = x + bar_w * pct / 100.0
		_canvas.draw_line(Vector2(tx, y), Vector2(tx, y + _bar_h),
			Color(0.0, 0.0, 0.0, 0.30), 1.0, true)

	return y + _bar_h + 4.0

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
