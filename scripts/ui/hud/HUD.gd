extends CanvasLayer
## HUD.gd
## Main HUD controller.

# ─── Node refs ────────────────────────────────────────────────────────────────
## HUDRoot is a full-screen Control that wraps all HUD children.
## We fade this instead of the CanvasLayer (CanvasLayer has no modulate).
@onready var _root: Control          = $HUDRoot
@onready var needs_gauge: NeedsGauge = $HUDRoot/NeedsGauge
@onready var status_effects: StatusEffectsContainer = $HUDRoot/StatusEffects
@onready var medical_effects: StatusEffectsContainer = $HUDRoot/MedicalEffects
@onready var cash_panel: PanelContainer = $HUDRoot/TopRight
@onready var cash_label: Label       = $HUDRoot/TopRight/CashLabel
@onready var clock_icon: TextureRect = $HUDRoot/TopCenter/ClockPanel/ClockRow/ClockIcon
@onready var clock_label: Label      = $HUDRoot/TopCenter/ClockPanel/ClockRow/TimeStack/ClockLabel
@onready var day_label: Label        = $HUDRoot/TopCenter/ClockPanel/ClockRow/TimeStack/DayLabel
@onready var time_accent: ColorRect  = $HUDRoot/TopCenter/TimeAccent
@onready var vignette: ColorRect     = $HUDRoot/CriticalVignette
@onready var inventory_hud: Control  = $HUDRoot/InventoryHUD

const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")

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
var _day_initialized: bool = false
var _day_accent_tween: Tween = null

func _ready() -> void:
	# Fade in via HUDRoot — CanvasLayer itself has no modulate property
	_root.modulate.a = 0.0
	# Reuses the project's native, code-rendered icon system. No imported or
	# generated image asset is introduced for this HUD polish pass.
	clock_icon.texture = S.icon("clock")

	# Lets NotificationManager (a global autoload, outside this scene's own
	# node path) find the inventory bar's global rect to anchor toasts above
	# it, without hardcoding a scene path (Jul 2026 toast-format rework).
	add_to_group("hud")

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
	needs_gauge.set_health(_health_pct)
	_update_critical()

func set_stamina(value: float) -> void:
	needs_gauge.set_stamina(value / 100.0)

func set_food(value: float) -> void:
	_food_pct = value / 100.0
	needs_gauge.set_food(_food_pct)
	_update_critical()

func set_water(value: float) -> void:
	_water_pct = value / 100.0
	needs_gauge.set_water(_water_pct)
	_update_critical()

func set_sleep(value: float) -> void:
	_sleep_pct = value / 100.0
	needs_gauge.set_sleep(_sleep_pct)
	_update_critical()

## Need-cap pass-through (Aug 2026, Medical system) — called from
## MainWorld.gd whenever PlayerStats.food_cap_changed/water_cap_changed/
## sleep_cap_changed fires. `value` is 0-100 like every other setter here;
## NeedsGauge wants a 0.0-1.0 fraction, same conversion as set_food() etc.
func set_food_cap(value: float) -> void:
	needs_gauge.set_food_cap(value / 100.0)

func set_water_cap(value: float) -> void:
	needs_gauge.set_water_cap(value / 100.0)

func set_sleep_cap(value: float) -> void:
	needs_gauge.set_sleep_cap(value / 100.0)

func set_cash(amount: int) -> void:
	cash_label.text = "$%s" % _format_cash(amount)

func set_clock(display: String) -> void:
	clock_label.text = display

func set_day(day: int) -> void:
	var next_text: String = "DAY %d" % day
	var changed: bool = day_label.text != next_text
	day_label.text = next_text
	if changed and _day_initialized:
		_pulse_day_accent()
	_day_initialized = true


## Rare, state-driven feedback only: the signal-blue notch brightens once
## when the day rolls over, then settles back. The always-on clock does not
## pulse, bounce, scan, or otherwise animate continuously.
func _pulse_day_accent() -> void:
	if _day_accent_tween != null and _day_accent_tween.is_valid():
		_day_accent_tween.kill()
	time_accent.modulate.a = 1.0
	_day_accent_tween = create_tween()
	_day_accent_tween.tween_property(time_accent, "modulate:a", 0.74, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ─── Build mode visibility ────────────────────────────────────────────────────
var _in_build_mode: bool = false

## Called by MainWorld when build mode is toggled.
## Hides the inventory bar while in build mode and keeps it hidden.
func set_build_mode(enabled: bool) -> void:
	_in_build_mode = enabled
	inventory_hud.visible = not enabled
	if not enabled and inventory_hud.has_method("refresh_previews"):
		inventory_hud.refresh_previews()


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
	lbl.add_theme_font_size_override("font_size", UIKit.theme_font_size("HUD", "float_label", 18))
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
	lbl.add_theme_font_size_override("font_size", UIKit.theme_font_size("HUD", "cash_delta", 12))
	var col: Color = Color(0.30, 0.95, 0.35, 1.0) if positive else Color(0.95, 0.28, 0.22, 1.0)
	lbl.add_theme_color_override("font_color", col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(lbl)

	# Position it just below the bordered balance plate and retain right-edge
	# alignment now that the cash HUD intentionally has no icon or eyebrow.
	var cash_rect: Rect2 = cash_panel.get_global_rect()
	lbl.custom_minimum_size.x = cash_rect.size.x
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.set_position(Vector2(cash_rect.position.x, cash_rect.end.y + 2.0))
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
