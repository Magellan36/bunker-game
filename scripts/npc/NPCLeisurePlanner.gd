extends RefCounted
class_name NPCLeisurePlanner
## A deliberately small two-timescale planner. Utility AI still chooses the
## activity; this helper holds a coherent leisure preference long enough for
## the resident to look intentional instead of re-rolling every think tick.

const PLAN_MIN_HOURS: float = 0.75
const PLAN_MAX_HOURS: float = 2.0
const PREFERRED_SCORE_BONUS: float = 2.25
const OTHER_SCORE_PENALTY: float = 0.35
const BEHAVIOR_PROFILE: GDScript = preload("res://scripts/npc/NPCBehaviorProfile.gd")

var profile: RefCounted = null
var _rng := RandomNumberGenerator.new()
var _preferred_mode: StringName = &"wander"
var _plan_hours_left: float = 0.0


func setup(npc: NPC) -> void:
	profile = BEHAVIOR_PROFILE.new()
	profile.setup(npc.generation_seed, npc.personality)
	_rng.seed = npc.generation_seed ^ 0x4C454953
	_roll_plan()


func tick(game_hours: float) -> void:
	_plan_hours_left -= maxf(0.0, game_hours)
	if _plan_hours_left <= 0.0:
		_roll_plan()


func score(mode: StringName, base_score: float) -> float:
	return maxf(0.0, base_score + (PREFERRED_SCORE_BONUS if mode == _preferred_mode else -OTHER_SCORE_PENALTY))


func sitting_session_hours() -> float:
	## 45–120 game minutes: long enough to read as actually sitting around.
	## Patient/high-affinity residents tend toward the long end.
	var tendency: float = clampf((profile.patience + profile.sitting_affinity) * 0.5, 0.0, 1.0)
	return lerpf(0.75, 2.0, clampf(tendency + _rng.randf_range(-0.15, 0.15), 0.0, 1.0))


func agenda_beat_count() -> int:
	return _rng.randi_range(profile.agenda_min_beats, profile.agenda_max_beats)


func observation_seconds(base_min: float, base_max: float) -> float:
	var patience_scale: float = lerpf(0.8, 1.8, profile.patience)
	return _rng.randf_range(base_min, base_max) * patience_scale


func preferred_mode() -> StringName:
	return _preferred_mode


func debug_info() -> Dictionary:
	return {
		"preferred_mode": String(_preferred_mode),
		"plan_hours_left": _plan_hours_left,
		"profile": profile.debug_info() if profile != null else {},
	}


func _roll_plan() -> void:
	var sit_chance: float = lerpf(0.2, 0.72, profile.sitting_affinity)
	_preferred_mode = &"sit" if _rng.randf() < sit_chance else &"wander"
	_plan_hours_left = _rng.randf_range(PLAN_MIN_HOURS, PLAN_MAX_HOURS)
