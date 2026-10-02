extends RefCounted
class_name NPCClock
## NPCClock.gd (Sep 2026) — the single game-time source for the NPC system.
##
## Before this, NPC code mixed three clocks: game-hours (needs/mood),
## physics delta (short actions) and WALL-CLOCK msec (talk/snatch/gift
## cooldowns, action-log ages, the cleaning idle gate). Wall-clock time
## ignores pause, the sleep fast-forward (Engine.time_scale) and the F12
## time multiplier, and restarts from zero on every launch — so a "60 s"
## cooldown could last four minutes of game time, and nothing that used it
## could be saved. Everything durable now uses NPCClock.now() (total game
## hours since day 1, 00:00), which PlayerStats already persists.

static var _stats: Node = null

static func _get_stats() -> Node:
	if _stats != null and is_instance_valid(_stats):
		return _stats
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_stats = tree.get_first_node_in_group("player_stats")
	return _stats

static func seconds_per_game_hour() -> float:
	var s: Node = _get_stats()
	if s == null or float(s._seconds_per_game_hour) <= 0.0:
		return 60.0
	return float(s._seconds_per_game_hour)

## Scaled frame delta → game hours. Includes PlayerStats.time_multiplier
## (the F12 dev tool) so NPC needs advance at the same rate as the clock.
## A stopped clock (BunkerPhase preparation, Oct 2026: time stands still
## before the seal) is zero: needs, mood, budgets and rolls all hold.
static func game_hours(delta: float) -> float:
	var s: Node = _get_stats()
	if s == null or float(s._seconds_per_game_hour) <= 0.0:
		return 0.0
	if not bool(s.get("clock_running") if "clock_running" in s else true):
		return 0.0
	return delta * float(s.time_multiplier) / float(s._seconds_per_game_hour)

## Total game hours since day 1, 00:00.
static func now() -> float:
	var s: Node = _get_stats()
	if s == null or float(s._seconds_per_game_hour) <= 0.0:
		return 0.0
	return float(s._elapsed) / float(s._seconds_per_game_hour)

## 0.0 .. 24.0
static func hour_of_day() -> float:
	return fmod(now(), 24.0)

static func day() -> int:
	return int(floor(now() / 24.0)) + 1

## True if `hour` lies inside [start, end) on a 24 h clock, wrapping midnight.
static func hour_in(hour: float, start: float, end: float) -> bool:
	hour = fposmod(hour, 24.0)
	start = fposmod(start, 24.0)
	end = fposmod(end, 24.0)
	if start <= end:
		return hour >= start and hour < end
	return hour >= start or hour < end

static func time_string() -> String:
	var s: Node = _get_stats()
	if s != null and s.has_method("get_time_display"):
		return "Day %d, %s" % [day(), s.get_time_display()]
	return "?"

## "3m ago" / "2h ago" / "yesterday" for a timestamp taken from now().
static func format_age(stamp_hours: float) -> String:
	var mins: int = maxi(0, int((now() - stamp_hours) * 60.0))
	if mins < 1:
		return "just now"
	if mins < 60:
		return "%dm ago" % mins
	var hrs: int = int(mins / 60.0)
	if hrs < 24:
		return "%dh ago" % hrs
	var days: int = int(hrs / 24.0)
	return "yesterday" if days == 1 else "%d days ago" % days
