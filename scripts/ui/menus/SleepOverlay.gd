extends CanvasLayer
## SleepOverlay.gd
## Fade-to-black for 2 real seconds, animate Zzz, then fade back out.
## Time skip happens instantly when fully black.

# ─── Tuning ───────────────────────────────────────────────────────────────────
const FADE_DURATION: float  = 0.8   ## Seconds to fade in / fade out
const SLEEP_DURATION: float = 2.0   ## Seconds spent fully black (with Zzz)
const WAKE_THRESHOLD: float = 5.0   ## Food/water level that cuts sleep short

# ─── Node refs ────────────────────────────────────────────────────────────────
@onready var overlay: ColorRect = $Overlay
@onready var zzz_root: Control  = $ZzzRoot

# Zzz labels — big → medium → small, staggered
@onready var z1: Label = $ZzzRoot/Z1
@onready var z2: Label = $ZzzRoot/Z2
@onready var z3: Label = $ZzzRoot/Z3

# ─── Signals ─────────────────────────────────────────────────────────────────
signal sleep_started()
signal sleep_ended()

# ─── State ───────────────────────────────────────────────────────────────────
enum Phase { IDLE, FADING_IN, SLEEPING, FADING_OUT }
var _phase: Phase  = Phase.IDLE
var _fade_t: float = 0.0
var _sleep_t: float = 0.0   ## Time spent in the SLEEPING phase

## Set by MainWorld
var player_stats: Node = null
var bed: Node          = null

func _ready() -> void:
	overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zzz_root.visible = false
	zzz_root.modulate.a = 0.0

func _process(delta: float) -> void:
	match _phase:
		Phase.FADING_IN:
			_fade_t = minf(_fade_t + delta / FADE_DURATION, 1.0)
			overlay.color.a = _fade_t
			if _fade_t >= 1.0:
				_phase = Phase.SLEEPING
				_sleep_t = 0.0
				_do_time_skip()         # Skip time instantly once black
				sleep_started.emit()
				zzz_root.visible = true

		Phase.SLEEPING:
			_sleep_t += delta
			_animate_zzz(_sleep_t)
			if _sleep_t >= SLEEP_DURATION:
				_start_fade_out()

		Phase.FADING_OUT:
			_fade_t = maxf(_fade_t - delta / FADE_DURATION, 0.0)
			overlay.color.a = _fade_t
			zzz_root.modulate.a = _fade_t   # Zzz fades out with screen
			if _fade_t <= 0.0:
				_phase = Phase.IDLE
				overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
				zzz_root.visible = false
				sleep_ended.emit()

# ─── Public API ───────────────────────────────────────────────────────────────
func begin_sleep() -> void:
	if _phase != Phase.IDLE:
		return
	_fade_t = 0.0
	_phase  = Phase.FADING_IN
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP

func request_wake() -> void:
	if _phase == Phase.SLEEPING:
		_start_fade_out()

# ─── Time skip ────────────────────────────────────────────────────────────────
## Instantly advance stats to simulate a full night's sleep.
func _do_time_skip() -> void:
	if player_stats == null:
		return

	# Advance clock by 8 game-hours
	var skip_hours: float  = 8.0
	var skip_real: float   = skip_hours * player_stats._seconds_per_game_hour
	player_stats._elapsed += skip_real

	var drain_scale: float = skip_real / player_stats._seconds_per_game_hour

	# Fill sleep fully
	player_stats.sleep = 100.0

	# Drain food & water for 8 hours
	player_stats.food  = maxf(0.0, player_stats.food  -
		player_stats.food_drain_per_game_hour  * drain_scale)
	player_stats.water = maxf(0.0, player_stats.water -
		player_stats.water_drain_per_game_hour * drain_scale)

	# Emit signals so HUD reflects the jump immediately
	player_stats.food_changed.emit(player_stats.food)
	player_stats.water_changed.emit(player_stats.water)
	player_stats.sleep_changed.emit(player_stats.sleep)
	player_stats._tick_clock()

# ─── Zzz animation ────────────────────────────────────────────────────────────
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

func _start_fade_out() -> void:
	_phase = Phase.FADING_OUT
	if bed != null:
		bed.set_sleeping(false)
