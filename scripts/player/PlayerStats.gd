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
## Emitted whenever Medical writes new need-cap values (see food_cap/
## water_cap/sleep_cap below and set_needs_caps()) — NeedsGauge listens via
## HUD.gd to render the reduced ceiling as a greyed-out portion of each
## ring, per docs/systems/medical/README.md's "Needs cap reduction."
signal food_cap_changed(value: float)
signal water_cap_changed(value: float)
signal sleep_cap_changed(value: float)

# ─── State ───────────────────────────────────────────────────────────────────
var food:   float = 100.0
var water:  float = 100.0
var sleep:  float = 100.0
var health: float = 100.0

## Dynamic per-need ceilings (Aug 2026, Medical system Pass 2) — default
## 100.0 (no effect). PlayerMedical.gd writes to these directly each tick
## based on the worst active condition affecting that need (currently only
## Infection uses this — see docs/systems/medical/README.md's "Needs cap
## reduction"). Health's cap is deliberately NEVER reduced by Medical —
## see that doc's "Planned future extensions" for why (HP is meant to only
## regenerate when a need is at its true, uncapped 100, so a reduced need
## cap already blocks that path as a natural consequence).
var food_cap:  float = 100.0
var water_cap: float = 100.0
var sleep_cap: float = 100.0

## The only way Medical (or anything else) should change the caps above —
## writing the vars directly would skip the *_cap_changed signals the HUD
## depends on to redraw. Values are 0-100, same scale as food/water/sleep
## themselves.
func set_needs_caps(new_food_cap: float, new_water_cap: float, new_sleep_cap: float) -> void:
	food_cap  = new_food_cap
	water_cap = new_water_cap
	sleep_cap = new_sleep_cap
	food_cap_changed.emit(food_cap)
	water_cap_changed.emit(water_cap)
	sleep_cap_changed.emit(sleep_cap)

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
	food = minf(food_cap, food + amount)
	food_changed.emit(food)

func replenish_water(amount: float) -> void:
	water = minf(water_cap, water + amount)
	water_changed.emit(water)

func replenish_sleep(amount: float) -> void:
	sleep = minf(sleep_cap, sleep + amount)
	sleep_changed.emit(sleep)

func replenish_health(amount: float) -> void:
	health = minf(100.0, health + amount)
	health_changed.emit(health)

## Recomputes and returns the current "H:MM AM/PM" display string on demand —
## does not rely on the cached _last_hour/_last_minute guard used by
## _tick_clock(), so it's safe to call anytime (e.g. for save-slot metadata)
## without disturbing the signal-emit cache.
func get_time_display() -> String:
	var total_game_minutes: int = int(_elapsed / (day_duration_seconds / 1440.0)) % 1440
	var game_hour:   int = total_game_minutes / 60
	var game_minute: int = total_game_minutes % 60
	var is_pm:   bool   = game_hour >= 12
	var hour_12: int    = game_hour % 12
	if hour_12 == 0:
		hour_12 = 12
	var suffix: String = "PM" if is_pm else "AM"
	return "%d:%02d %s" % [hour_12, game_minute, suffix]

# ─── Save/Load support ────────────────────────────────────────────────────────
## Returns raw elapsed real-seconds since game start — the single source of
## truth _tick_clock()/_tick_needs() derive hour/minute/day from. Saving this
## one float is sufficient to restore the exact game-clock moment; day/hour/
## minute are recomputed automatically next frame.
func get_elapsed() -> float:
	return _elapsed

## Advances time by `hours` game-hours, drains food/water for that duration,
## and fully restores sleep. NOT currently used by SleepOverlay (it calls
## skip_time_with_drain() instead, which also drains sleep rather than
## refilling it) — kept as a distinct, real option for anything that wants
## a genuine "woke up rested" skip rather than "time passed while asleep."
func skip_time(hours: float) -> void:
	var skip_real: float = hours * _seconds_per_game_hour
	_elapsed += skip_real
	var drain_scale: float = skip_real / _seconds_per_game_hour

	sleep = sleep_cap

	food  = maxf(0.0, food  - food_drain_per_game_hour  * drain_scale)
	water = maxf(0.0, water - water_drain_per_game_hour * drain_scale)

	food_changed.emit(food)
	water_changed.emit(water)
	sleep_changed.emit(sleep)
	_tick_clock()

## Restores elapsed time (e.g. from a save file) and immediately recomputes the
## cached clock/day so the HUD updates on the same frame instead of waiting for
## the next _process tick to notice the jump.
## Advances the clock by `hours` game-hours AND applies the same food/
## water/sleep/health drain that would happen if that time had actually
## passed in real-time (see _tick_needs()). Distinct from skip_time() (the
## sleep-to-morning skip), which deliberately refills sleep instead of
## draining it — this one is for the admin "Fast-Forward" cheat, which
## should behave like a day actually passed.
func skip_time_with_drain(hours: float) -> void:
	var scaled: float = hours * _seconds_per_game_hour
	_elapsed += scaled
	_tick_needs(scaled)
	_tick_clock()

func set_elapsed(value: float) -> void:
	_elapsed = maxf(0.0, value)
	## Force the cached-clock guard to recompute even if hour/minute happen to
	## match what they were before the load.
	_last_hour   = -1
	_last_minute = -1
	_last_day    = -1
	_tick_clock()
