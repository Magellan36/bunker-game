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
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
## Quiet HUD (QUIET_DESIGN_SYSTEM archetype C): text on a soft shadow, no plates.
const SAFE_MARGIN: float = 24.0

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
	_quiet_readouts()

	# Lets NotificationManager (a global autoload, outside this scene's own
	# node path) find the inventory bar's global rect to anchor toasts above
	# it, without hardcoding a scene path (Jul 2026 toast-format rework).
	add_to_group("hud")

## Sep 2026 quiet pass: the clock and cash sit directly over the world as
## shadowed text — day as a brass eyebrow above the time, cash top-right on
## the 24 px safe margin. Node paths are unchanged (toasts anchor under
## cash_panel; tests address the same labels).
func _quiet_readouts() -> void:
	var clock_panel: PanelContainer = $HUDRoot/TopCenter/ClockPanel
	clock_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	clock_icon.visible = false
	($HUDRoot/TopCenter/ClockPanel/ClockRow/Divider as Control).visible = false
	time_accent.visible = false
	var stack: VBoxContainer = day_label.get_parent() as VBoxContainer
	stack.move_child(day_label, 0)
	stack.add_theme_constant_override("separation", 0)
	day_label.add_theme_color_override("font_color", Q.HEADING)
	day_label.add_theme_font_size_override("font_size", 12)
	Q.tracked(day_label, 3)
	clock_label.add_theme_font_size_override("font_size", 20)
	clock_label.add_theme_color_override("font_color", Q.TEXT)
	cash_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	cash_label.add_theme_font_size_override("font_size", 21)
	cash_label.add_theme_color_override("font_color", Q.TEXT)
	for label: Label in [day_label, clock_label, cash_label]:
		_shadow(label)
	## 24 px safe margins (plates used 10–12).
	var top_center: Control = $HUDRoot/TopCenter
	top_center.offset_top = SAFE_MARGIN - 6.0
	top_center.offset_bottom = SAFE_MARGIN + 40.0
	cash_panel.offset_right = -SAFE_MARGIN
	cash_panel.offset_left = -SAFE_MARGIN - cash_panel.custom_minimum_size.x
	cash_panel.offset_top = SAFE_MARGIN - 6.0
	cash_panel.offset_bottom = SAFE_MARGIN + 34.0


## Soft shadow + faint outline so text holds over bright or busy scenes.
func _shadow(label: Label) -> void:
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 6)


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
	cash_label.text = UIFormat.money(amount)

func set_clock(display: String) -> void:
	clock_label.text = display

func set_day(day: int) -> void:
	var next_text: String = "DAY %d" % day
	var changed: bool = day_label.text != next_text
	day_label.text = next_text
	if changed and _day_initialized:
		_pulse_day_accent()
	_day_initialized = true


## Rare, state-driven feedback only: the day eyebrow brightens once when the
## day rolls over, then settles back. The always-on clock never animates.
func _pulse_day_accent() -> void:
	if _day_accent_tween != null and _day_accent_tween.is_valid():
		_day_accent_tween.kill()
	day_label.add_theme_color_override("font_color", Q.TEXT)
	_day_accent_tween = create_tween()
	_day_accent_tween.tween_method(func(t: float) -> void:
		day_label.add_theme_color_override("font_color", Q.TEXT.lerp(Q.HEADING, t)),
		0.0, 1.0, UIMotion.duration(1.2)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ─── Build mode visibility ────────────────────────────────────────────────────
var _in_build_mode: bool = false
var _yield_tween: Tween = null

## Called by MainWorld when build mode is toggled.
## Hides the inventory bar while in build mode and keeps it hidden.
func set_build_mode(enabled: bool) -> void:
	_in_build_mode = enabled
	inventory_hud.visible = not enabled
	## Quiet layout rule (plan Pass 3A): the HUD yields to the build tool's
	## catalog instead of sitting under it. Needs stay readable via the
	## critical vignette, which is unaffected.
	if _yield_tween != null and _yield_tween.is_valid():
		_yield_tween.kill()
	_yield_tween = create_tween().set_parallel(true)
	for part: CanvasItem in [needs_gauge, status_effects, medical_effects]:
		_yield_tween.tween_property(part, "modulate:a", 0.0 if enabled else 1.0, UIMotion.duration(0.18))
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
	lbl.text = ("+" if positive else "-") + UIFormat.money(absi(amount))
	lbl.add_theme_font_size_override("font_size", UIKit.theme_font_size("HUD", "float_label", 18))
	lbl.add_theme_color_override("font_color", BunkerDesign.GREEN if positive else BunkerDesign.RED)
	_shadow(lbl)
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
	lbl.text = ("+" if positive else "-") + UIFormat.money(absi(amount))
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", BunkerDesign.GREEN if positive else BunkerDesign.RED)
	_shadow(lbl)
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
