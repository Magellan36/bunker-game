extends Node
class_name PlayerStats
## PlayerStats.gd
## Owns food, water, sleep, health, and the game clock.
## Drain rates are tied to game-time hours so tweaking timescale adjusts everything.
##
## Timescale: 24 game-hours = 24 real-minutes
##   → 1 real second = 1 game minute
##   → 1 real minute  = 1 game hour

# ─── Timescale ────────────────────────────────────────────────────────────────
## Real seconds per full 24-hour game day (default: 1440s = 24 min)
@export var day_duration_seconds: float = 1440.0

# ─── Starting clock time ──────────────────────────────────────────────────────
@export var start_hour: int   = 6
@export var start_minute: int = 0

# ─── Drain rates (units lost per GAME hour, 0–100 scale) ─────────────────────
## Food depletes over ~3 game days  (72 hrs)
@export var food_drain_per_game_hour: float  = 1.39
## Water depletes over ~2 game days (48 hrs)
@export var water_drain_per_game_hour: float = 2.08
## Sleep depletes over ~1.5 game days (36 hrs)
@export var sleep_drain_per_game_hour: float = 2.78

## Health lost per game hour when food OR water is at 0
## ~8hrs to die from one deprivation, ~4hrs if both are 0
@export var starvation_drain_per_game_hour: float = 12.5

# ─── Signals ─────────────────────────────────────────────────────────────────
signal food_changed(value: float)
signal water_changed(value: float)
signal sleep_changed(value: float)
signal health_changed(value: float)
signal time_changed(hour: int, minute: int, is_pm: bool, display: String)
signal day_changed(day: int)

# ─── State ───────────────────────────────────────────────────────────────────
var food:   float = 100.0
var water:  float = 100.0
var sleep:  float = 100.0
var health: float = 100.0

## Time multiplier — set by dev tools (F12). Only affects stats/clock, not physics.
var time_multiplier: float = 1.0

## Total elapsed real seconds since game start
var _elapsed: float = 0.0

## Pre-computed: real seconds per game hour (exposed for SleepOverlay)
var _seconds_per_game_hour: float = 0.0

## Cached clock to avoid string alloc every frame
var _last_hour:   int = -1
var _last_minute: int = -1
var _last_day:    int = -1

## Current in-game day (starts at 1)
var current_day: int = 1

func _ready() -> void:
	add_to_group("player_stats")  # Allows any node to find us via get_first_node_in_group()
	_seconds_per_game_hour = day_duration_seconds / 24.0
	# Seed elapsed so clock starts at start_hour:start_minute
	_elapsed = (start_hour * 60 + start_minute) * (day_duration_seconds / 1440.0)

func _process(delta: float) -> void:
	var scaled: float = delta * time_multiplier
	_elapsed += scaled
	_tick_needs(scaled)
	_tick_clock()

# ─── Needs ────────────────────────────────────────────────────────────────────
func _tick_needs(delta: float) -> void:
	var drain_scale: float = delta / _seconds_per_game_hour

	food  = maxf(0.0, food  - food_drain_per_game_hour  * drain_scale)
	water = maxf(0.0, water - water_drain_per_game_hour * drain_scale)
	sleep = maxf(0.0, sleep - sleep_drain_per_game_hour * drain_scale)

	# Starvation / dehydration health drain
	var deprivation_count: int = (1 if food == 0.0 else 0) + (1 if water == 0.0 else 0)
	if deprivation_count > 0:
		var drain: float = starvation_drain_per_game_hour * deprivation_count * drain_scale
		health = maxf(0.0, health - drain)
		health_changed.emit(health)

	food_changed.emit(food)
	water_changed.emit(water)
	sleep_changed.emit(sleep)

# ─── Clock (public so SleepOverlay can call it during time-skip) ──────────────
func _tick_clock() -> void:
	var total_game_minutes: int = int(_elapsed / (day_duration_seconds / 1440.0)) % 1440
	var game_hour:   int = total_game_minutes / 60
	var game_minute: int = total_game_minutes % 60

	if game_hour == _last_hour and game_minute == _last_minute:
		return
	_last_hour   = game_hour
	_last_minute = game_minute

	var is_pm:   bool   = game_hour >= 12
	var hour_12: int    = game_hour % 12
	if hour_12 == 0:
		hour_12 = 12
	var suffix:  String = "PM" if is_pm else "AM"
	var display: String = "%d:%02d %s" % [hour_12, game_minute, suffix]
	time_changed.emit(game_hour, game_minute, is_pm, display)

	# ── Day counter ──
	var day: int = int(_elapsed / day_duration_seconds) + 1
	if day != _last_day:
		_last_day   = day
		current_day = day
		day_changed.emit(day)

# ─── Replenish ────────────────────────────────────────────────────────────────
## Each replenish emits its signal immediately so the HUD updates on the same frame.
func replenish_food(amount: float) -> void:
	food = minf(100.0, food + amount)
	food_changed.emit(food)

func replenish_water(amount: float) -> void:
	water = minf(100.0, water + amount)
	water_changed.emit(water)

func replenish_sleep(amount: float) -> void:
	sleep = minf(100.0, sleep + amount)
	sleep_changed.emit(sleep)

func replenish_health(amount: float) -> void:
	health = minf(100.0, health + amount)
	health_changed.emit(health)
