extends NPCActivity
class_name RelaxActivity
## Sitting around — unstructured leisure, distinct from low-energy rest.
## Delegates to RelaxSitActivity for the actual arrival/seating mechanics.
## It is eligible only when a chair is free and is self-limiting via a daily time budget
## (NPC.get_relax_time_remaining_today()) rather than precise
## scheduling — see NPC.gd's Relaxing section for the budget/reset
## logic and Work Ethic's effect on it.
const BASE_SCORE: float = 5.2
const ACTIVE_SCORE_FLOOR: float = 7.0

var _inner: NPCActivity = null
var _session_length: float = 0.0
var _session_elapsed: float = 0.0

func label() -> String:
	return "Sitting around" if _inner == null else _inner.label()

func score(npc: NPC) -> float:
	if npc.get_relax_time_remaining_today() <= 0.0:
		return 0.0
	if npc.is_relax_on_cooldown():
		return 0.0
	if _inner == null and SitActivity.find_free_chair(npc) == null:
		return 0.0
	var utility: float = npc.get_leisure_score(&"sit", BASE_SCORE) \
		* npc.get_work_ethic_passive_mult()
	## The occupied chair is no longer "free," and the leisure plan may roll
	## from sit to wander during a long session. Neither should make wandering
	## eject a seated resident. Real needs/jobs still clear this modest floor.
	return maxf(utility, ACTIVE_SCORE_FLOOR) if _inner != null else utility

func interruptible() -> bool:
	## Sitting around is a passive commitment. Utility-selected needs and work
	## may interrupt it; exit() requests the authored stand-up transition before
	## normal locomotion resumes. Commands and pass-out retain their overrides.
	return true

func switch_margin() -> float:
	return 0.75

func enter(npc: NPC) -> void:
	npc.reset_relax_job_requests()
	_session_length = minf(npc.get_leisure_sitting_hours(), npc.get_relax_time_remaining_today())
	_session_elapsed = 0.0
	_inner = RelaxSitActivity.new()
	_inner.enter(npc)
	if _inner.done(npc):   ## chair was claimed in the score/enter race
		_inner.exit(npc)
		_inner = null

func tick(npc: NPC, delta: float) -> void:
	var h: float = npc.game_hours(delta)
	_session_elapsed += h
	npc.spend_relax_time(h)
	if _inner != null:
		_inner.tick(npc, delta)
	else:
		npc.halt_movement(delta)

func done(npc: NPC) -> bool:
	if _inner == null:
		return true
	if _session_elapsed >= _session_length:
		return true
	return _inner.done(npc)

func exit(npc: NPC) -> void:
	if _session_elapsed > 0.01:   ## skip logging a session that never actually started
		npc.log_action("Sat around for %d min" % int(round(_session_elapsed * 60.0)))
		npc.start_relax_cooldown()   ## spaces sessions apart — see NPC.gd's Relaxing section
	if _inner != null:
		_inner.exit(npc)
		_inner = null


func debug_info() -> Dictionary:
	return {
		"activity": "leisure_sitting",
		"elapsed_game_hours": _session_elapsed,
		"planned_game_hours": _session_length,
		"furniture_activity": _inner.label() if _inner != null else "Standing quietly",
	}

func attention_target(npc: NPC) -> Node3D:
	return _inner.attention_target(npc) if _inner != null else null
