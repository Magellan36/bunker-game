extends CanvasLayer
## SleepOverlay.gd — Sims-style accelerated sleep (Aug 2026 rework).
##
## Replaces the old "fade to black + instantly simulate 8 hours" sleep. Now the
## player sleeps in a bed and the WHOLE WORLD speeds up around them via
## Engine.time_scale, exactly like a Sims sleep: the clock, NPCs, food/water,
## water purification and crop growth all run at SLEEP_TIME_SCALE because every
## system already derives game-time from the real per-frame delta. The sleep
## need RECOVERS while asleep (PlayerStats.sleeping, see
## SLEEP_RECOVERY_PER_GAME_HOUR), and the instant it reaches its cap the session
## ends and normal time is restored. E (request_wake) ends it early.
##
## The timescale is tuned DOWN from the F12 dev warp (Engine.time_scale = 50),
## which destabilizes physics and sends NPCs/bodies flying. At 4x each physics
## step stays around 1/15s, keeping CharacterBody + rigid-body simulation
## stable. If any jitter ever shows up, lower this (3.0 is very safe) — the
## alternative (raising physics_ticks_per_second proportionally) is heavier and
## riskier to change at runtime.

const SLEEP_TIME_SCALE: float = 4.0

## TEMP DEBUG (Aug 2026) — the time speed-up is UNWIRED while the sleep
## lie-down animation is being built, so the animation can be debugged at
## normal game speed. Flip to `true` to re-enable the Sims-style accelerated
## sleep exactly as-is (this is the ONLY knob to touch when re-wiring; the
## begin/end guards below read it). Everything else in the sleep session —
## sleep-need recovery, fully-rested auto-end, E wake, Zzz hint — still runs
## regardless.
const ENABLE_SLEEP_TIME_SCALE: bool = false

# ─── Node refs ────────────────────────────────────────────────────────────────
@onready var zzz_root: Control = $ZzzRoot
@onready var z1: Label = $ZzzRoot/Z1
@onready var z2: Label = $ZzzRoot/Z2
@onready var z3: Label = $ZzzRoot/Z3

# ─── Signals ─────────────────────────────────────────────────────────────────
signal sleep_started()
signal sleep_ended()

# ─── State ────────────────────────────────────────────────────────────────────
## Set by MainWorld
var player_stats: Node = null
var bed: Node = null

var _sleep_active: bool = false
var _sleep_t: float = 0.0
var _saved_time_scale: float = 1.0   ## restored on wake — preserves the F12 dev warp if it was on

## Sep 2026 quiet pass: a soft dim over the world while asleep, calmer
## ivory Z's, and a small centred readout (eyebrow, slim sleep meter, wake
## hint) that fades in and out with the session.
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
var _dim: ColorRect = null
var _readout: VBoxContainer = null
var _meter: ProgressBar = null
var _fade_tween: Tween = null

func _ready() -> void:
	zzz_root.visible = false
	zzz_root.modulate.a = 0.0
	for z: Label in [z1, z2, z3]:
		z.add_theme_color_override("font_color", Color(Q.TEXT, 0.7))
		z.add_theme_font_override("font", load("res://assets/fonts/IosevkaCharon-Light.ttf"))
	_dim = ColorRect.new()
	_dim.name = "SleepDim"
	_dim.color = Color(0.0, 0.0, 0.0, 0.42)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	_dim.visible = false
	add_child(_dim)
	move_child(_dim, 0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_readout = VBoxContainer.new()
	_readout.name = "SleepReadout"
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.alignment = BoxContainer.ALIGNMENT_CENTER
	_readout.add_theme_constant_override("separation", 10)
	_readout.modulate.a = 0.0
	_readout.visible = false
	add_child(_readout)
	BunkerUIComponents.apply_theme(_readout)
	var eyebrow: Label = Q.eyebrow("Sleeping", 12)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout.add_child(eyebrow)
	_meter = BunkerSmoothProgressBar.new()
	_meter.custom_minimum_size.x = 220.0
	_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Q.meter(_meter)
	_readout.add_child(_meter)
	var hints := HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.add_child(hints)
	BunkerUIComponents.key_hint(hints, "E", "Wake up", "E", "A")
	get_viewport().size_changed.connect(_place_readout)
	_place_readout()

func _place_readout() -> void:
	if _readout == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	var width := maxf(320.0, _readout.get_combined_minimum_size().x)
	_readout.size = Vector2(width, _readout.get_combined_minimum_size().y)
	_readout.position = Vector2((viewport.x - width) * 0.5, viewport.y * 0.68)

func _fade_session(show: bool) -> void:
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()
	if show:
		_dim.visible = true
		_readout.visible = true
	_fade_tween = create_tween().set_parallel(true)
	var target := 1.0 if show else 0.0
	_fade_tween.tween_property(_dim, "modulate:a", target, UIMotion.duration(0.8 if show else 0.4))
	_fade_tween.tween_property(_readout, "modulate:a", target, UIMotion.duration(0.6 if show else 0.3))
	if not show:
		_fade_tween.chain().tween_callback(func() -> void:
			_dim.visible = false
			_readout.visible = false)

func _update_meter() -> void:
	if _meter == null or player_stats == null:
		return
	var cap: float = maxf(float(player_stats.get("sleep_cap")), 1.0)
	_meter.max_value = cap
	_meter.call("set_target_value", float(player_stats.get("sleep")))

func _process(delta: float) -> void:
	if not _sleep_active:
		return
	_sleep_t += delta
	_animate_zzz(_sleep_t)
	_update_meter()
	## Fully rested — the sleep need climbed to its cap (PlayerStats clamps
	## there, so this is an exact hit). End the accelerated sleep.
	if player_stats != null and player_stats.sleep >= player_stats.sleep_cap:
		_end_sleep()

# ─── Public API ───────────────────────────────────────────────────────────────
func begin_sleep() -> void:
	if _sleep_active:
		return
	_sleep_active = true
	_sleep_t = 0.0
	## Unwired for animation debugging — see ENABLE_SLEEP_TIME_SCALE.
	if ENABLE_SLEEP_TIME_SCALE:
		_saved_time_scale = Engine.time_scale
		Engine.time_scale = SLEEP_TIME_SCALE
	if player_stats != null:
		player_stats.set("sleeping", true)
	zzz_root.visible = true
	_update_meter()
	_fade_session(true)
	sleep_started.emit()

func request_wake() -> void:
	if _sleep_active:
		_end_sleep()

func _end_sleep() -> void:
	if not _sleep_active:
		return
	_sleep_active = false
	## Unwired for animation debugging — see ENABLE_SLEEP_TIME_SCALE.
	if ENABLE_SLEEP_TIME_SCALE:
		Engine.time_scale = _saved_time_scale
	if player_stats != null:
		player_stats.set("sleeping", false)
	if bed != null and is_instance_valid(bed):
		bed.set_sleeping(false)
	zzz_root.visible = false
	_fade_session(false)
	sleep_ended.emit()

# ─── Zzz animation (sleeping indicator over the sped-up world) ───────────────
## Three labels pulse in a staggered wave — big, medium, small.
## Each cycles: invisible → fade in → drift up → fade out.
const ZZZ_CYCLE: float  = 1.2   ## Seconds per full Z cycle
const ZZZ_OFFSET: float = 0.4   ## Stagger between each Z (seconds)

func _animate_zzz(t: float) -> void:
	zzz_root.modulate.a = 1.0
	_tick_z(z1, t,                   0)
	_tick_z(z2, t - ZZZ_OFFSET,      1)
	_tick_z(z3, t - ZZZ_OFFSET * 2,  2)

func _tick_z(label: Label, t: float, index: int) -> void:
	# Wrap time into [0, ZZZ_CYCLE]
	var local_t: float = fmod(t, ZZZ_CYCLE)
	if local_t < 0.0:
		label.modulate.a = 0.0
		return

	# Alpha: fade in first half, fade out second half
	var alpha: float
	if local_t < ZZZ_CYCLE * 0.5:
		alpha = local_t / (ZZZ_CYCLE * 0.5)
	else:
		alpha = 1.0 - (local_t - ZZZ_CYCLE * 0.5) / (ZZZ_CYCLE * 0.5)
	label.modulate.a = alpha

	# Drift upward over the cycle
	var base_y: float  = [0.0, 28.0, 52.0][index]   ## Stagger vertical start
	var drift_y: float = local_t / ZZZ_CYCLE * -30.0 ## Floats 30px upward
	label.position.y   = base_y + drift_y