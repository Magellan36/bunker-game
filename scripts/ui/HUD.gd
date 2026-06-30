extends CanvasLayer
## HUD.gd
## Main HUD controller.

# ─── Node refs ────────────────────────────────────────────────────────────────
## HUDRoot is a full-screen Control that wraps all HUD children.
## We fade this instead of the CanvasLayer (CanvasLayer has no modulate).
@onready var _root: Control          = $HUDRoot
@onready var bars: Control           = $HUDRoot/BottomLeft/Bars
@onready var food_circle: Control    = $HUDRoot/LeftIcons/FoodCircle
@onready var water_circle: Control   = $HUDRoot/LeftIcons/WaterCircle
@onready var sleep_circle: Control   = $HUDRoot/LeftIcons/SleepCircle
@onready var cash_label: Label       = $HUDRoot/TopRight/CashLabel
@onready var clock_label: Label      = $HUDRoot/TopCenter/ClockPanel/ClockLabel
@onready var day_label: Label        = $HUDRoot/TopCenter/DayLabel
@onready var vignette: ColorRect     = $HUDRoot/CriticalVignette
@onready var inventory_hud: Control  = $HUDRoot/InventoryHUD

# ─── Fade-in ──────────────────────────────────────────────────────────────────
const FADE_IN_DURATION: float = 0.6
var _fade_t: float = 0.0
var _fading_in: bool = true

# ─── Critical vignette ────────────────────────────────────────────────────────
## Pulses a red edge vignette when any stat is critical (< 20%)
var _vignette_t: float  = 0.0
var _any_critical: bool = false

# ─── Stat tracking for critical check ────────────────────────────────────────
var _food_pct:  float = 1.0
var _water_pct: float = 1.0
var _sleep_pct: float = 1.0
var _health_pct: float = 1.0

func _ready() -> void:
	# Fade in via HUDRoot — CanvasLayer itself has no modulate property
	_root.modulate.a = 0.0

func _process(delta: float) -> void:
	# ── Fade in on load ──
	if _fading_in:
		_fade_t += delta / FADE_IN_DURATION
		_root.modulate.a = minf(_fade_t, 1.0)
		if _fade_t >= 1.0:
			_fading_in = false
			_root.modulate.a = 1.0

	# ── Critical vignette pulse (drives shader 'strength' uniform) ──
	var mat: ShaderMaterial = vignette.material as ShaderMaterial
	if mat == null:
		return
	if _any_critical:
		_vignette_t += delta * 2.5
		mat.set_shader_parameter("strength", 0.35 + sin(_vignette_t) * 0.25)
	else:
		var cur: float = mat.get_shader_parameter("strength")
		if cur > 0.0:
			mat.set_shader_parameter("strength", maxf(0.0, cur - delta * 1.5))

# ─── Public update API ────────────────────────────────────────────────────────
func set_health(value: float) -> void:
	_health_pct = value / 100.0
	bars.set_health(_health_pct)
	_update_critical()

func set_stamina(value: float) -> void:
	bars.set_stamina(value / 100.0)

func set_food(value: float) -> void:
	_food_pct = value / 100.0
	food_circle.set_fill(_food_pct)
	_update_critical()

func set_water(value: float) -> void:
	_water_pct = value / 100.0
	water_circle.set_fill(_water_pct)
	_update_critical()

func set_sleep(value: float) -> void:
	_sleep_pct = value / 100.0
	sleep_circle.set_fill(_sleep_pct)
	_update_critical()

func set_cash(amount: int) -> void:
	cash_label.text = "$%s" % _format_cash(amount)

func set_clock(display: String) -> void:
	clock_label.text = display

func set_day(day: int) -> void:
	day_label.text = "Day %d" % day

# ─── Build mode visibility ────────────────────────────────────────────────────
var _in_build_mode: bool = false

## Called by MainWorld when build mode is toggled.
## Hides the inventory bar while in build mode and keeps it hidden.
func set_build_mode(enabled: bool) -> void:
	_in_build_mode = enabled
	inventory_hud.visible = not enabled


# ─── Critical check ───────────────────────────────────────────────────────────
func _update_critical() -> void:
	_any_critical = _food_pct < 0.2 or _water_pct < 0.2 or \
					_sleep_pct < 0.2 or _health_pct < 0.2
	if not _any_critical:
		_vignette_t = 0.0

# ─── Floating cash labels ─────────────────────────────────────────────────────
## Called by BuildModeController (via helper) after construct/deconstruct.
## screen_pos  — 2-D position to spawn the label (world tile projected to screen)
## amount      — dollar value (no sign prefix, we add it)
## positive    — true = refund (green "+$X"), false = spend (red "-$X")
func spawn_float_label(screen_pos: Vector2, amount: int, positive: bool) -> void:
	if amount == 0:
		return

	var lbl: Label = Label.new()
	lbl.text = ("+$%d" if positive else "-$%d") % amount
	lbl.add_theme_font_size_override("font_size", 18)
	var col: Color = Color(0.30, 0.95, 0.35, 1.0) if positive else Color(0.95, 0.28, 0.22, 1.0)
	lbl.add_theme_color_override("font_color", col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(lbl)

	# Center the label on the tile position
	lbl.set_position(screen_pos - Vector2(30.0, 12.0))

	# Animate: float upward with a gentle sine-wave X drift, fade out
	var tween: Tween = create_tween()
	tween.set_parallel(true)

	var start_pos: Vector2 = lbl.position
	var end_pos:   Vector2 = start_pos + Vector2(0.0, -70.0)

	# Y: linear upward over 1.1 s
	tween.tween_property(lbl, "position:y", end_pos.y, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# X: small sine-like wiggle — move right then back via two sequential tweens
	var wiggle: float = 18.0 if positive else -18.0
	var seq_tween: Tween = create_tween()
	seq_tween.tween_property(lbl, "position:x", start_pos.x + wiggle, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	seq_tween.tween_property(lbl, "position:x", start_pos.x, 0.40) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	seq_tween.tween_property(lbl, "position:x", start_pos.x - wiggle * 0.4, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Alpha: hold 0.6 s then fade out over 0.5 s
	tween.tween_interval(0.55)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Also show the delta indicator under the cash label
	show_cash_delta(amount, positive)

	# Free label when animation ends
	tween.tween_callback(lbl.queue_free).set_delay(1.1)

## Shows a brief "+$X" / "-$X" delta indicator just below the cash label in the HUD corner.
## Fades out after ~1.2 s. Replaces any previous delta still visible.
var _cash_delta_label: Label = null
var _cash_delta_tween: Tween = null

func show_cash_delta(amount: int, positive: bool) -> void:
	if amount == 0:
		return

	# Kill previous delta label if still alive
	if _cash_delta_label != null and is_instance_valid(_cash_delta_label):
		_cash_delta_label.queue_free()
	if _cash_delta_tween != null and _cash_delta_tween.is_valid():
		_cash_delta_tween.kill()

	var lbl: Label = Label.new()
	lbl.text = ("+$%d" if positive else "-$%d") % amount
	lbl.add_theme_font_size_override("font_size", 12)
	var col: Color = Color(0.30, 0.95, 0.35, 1.0) if positive else Color(0.95, 0.28, 0.22, 1.0)
	lbl.add_theme_color_override("font_color", col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(lbl)

	# Position it just below the cash label
	var cash_rect: Rect2 = cash_label.get_global_rect()
	lbl.set_position(Vector2(cash_rect.position.x, cash_rect.position.y + cash_rect.size.y + 2.0))
	_cash_delta_label = lbl

	# Fade in fast, hold, fade out
	lbl.modulate.a = 0.0
	var tw: Tween = create_tween()
	_cash_delta_tween = tw
	tw.tween_property(lbl, "modulate:a", 1.0, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.85)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(lbl.queue_free)
	tw.tween_callback(func() -> void: _cash_delta_label = null)

# ─── Soft warning toast ───────────────────────────────────────────────────────
## Displays a short message above the inventory bar for ~2 s then fades out.
## Calling again while a previous warning is visible replaces it instantly.
var _warning_label: Label = null
var _warning_tween: Tween = null

func show_soft_warning(text: String) -> void:
	# Kill any existing warning
	if _warning_label != null and is_instance_valid(_warning_label):
		_warning_label.queue_free()
		_warning_label = null
	if _warning_tween != null and _warning_tween.is_valid():
		_warning_tween.kill()
		_warning_tween = null

	# Build the label
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.78, 0.55, 1.0))  # warm amber — military style
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Dark semi-transparent panel backing
	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color            = Color(0.08, 0.07, 0.06, 0.82)
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(lbl)
	_root.add_child(panel)
	_warning_label = lbl

	# Wait one frame so the panel measures its size before we position it
	await get_tree().process_frame

	if not is_instance_valid(panel):
		return

	# Position: horizontally centred, just above the inventory bar
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var inv_rect: Rect2        = inventory_hud.get_global_rect()
	var panel_size: Vector2    = panel.size
	var target_x: float = (viewport_size.x - panel_size.x) * 0.5
	var target_y: float = inv_rect.position.y - panel_size.y - 12.0
	panel.position = Vector2(target_x, target_y + 8.0)  # start 8 px below final pos

	# Animate: slide up + fade in, hold, fade out
	var tw: Tween = create_tween()
	_warning_tween = tw
	tw.set_parallel(true)
	tw.tween_property(panel, "position:y", target_y,        0.15).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0,             0.15).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_interval(1.80)
	tw.tween_property(panel, "modulate:a", 0.0,             0.40).set_ease(Tween.EASE_IN)
	tw.tween_callback(panel.queue_free)
	tw.tween_callback(func() -> void: _warning_label = null)

	panel.modulate.a = 0.0  # start invisible

# ─── Helpers ──────────────────────────────────────────────────────────────────
func _format_cash(amount: int) -> String:
	var s: String = str(amount)
	var result: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
