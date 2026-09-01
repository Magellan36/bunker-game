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

func _ready() -> void:
	zzz_root.visible = false
	zzz_root.modulate.a = 0.0

func _process(delta: float) -> void:
	if not _sleep_active:
		return
	_sleep_t += delta
	_animate_zzz(_sleep_t)
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
	_saved_time_scale = Engine.time_scale
	Engine.time_scale = SLEEP_TIME_SCALE
	if player_stats != null:
		player_stats.set("sleeping", true)
	zzz_root.visible = true
	sleep_started.emit()

func request_wake() -> void:
	if _sleep_active:
		_end_sleep()

func _end_sleep() -> void:
	if not _sleep_active:
		return
	_sleep_active = false
	Engine.time_scale = _saved_time_scale
	if player_stats != null:
		player_stats.set("sleeping", false)
	if bed != null and is_instance_valid(bed):
		bed.set_sleeping(false)
	zzz_root.visible = false
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