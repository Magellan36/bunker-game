extends NPCActivity
class_name RelaxActivity
## Relaxing (Aug 2026) — scheduled break, distinct from Wander/Idle.
## Delegates entirely to SitActivity/LieActivity for the actual
## arrival/seating mechanics (same composition CommandRestActivity
## already uses) — falls back to just standing in place if neither a
## chair nor a bed is free. Self-limiting via a daily time budget
## (NPC.get_relax_time_remaining_today()) rather than precise
## scheduling — see NPC.gd's Relaxing section for the budget/reset
## logic and Work Ethic's effect on it.
const BASE_SCORE: float = 6.0   ## edges out Wander's flat 5.0 when both are otherwise idle
const SESSION_MIN: float = 0.33   ## game-hours (~20 min)
const SESSION_MAX: float = 0.67   ## game-hours (~40 min)

var _inner: NPCActivity = null
var _session_length: float = 0.0
var _session_elapsed: float = 0.0

func label() -> String:
	return "Relaxing" if _inner == null else "Relaxing (%s)" % _inner.label()

func score(npc: NPC) -> float:
	if npc.get_relax_time_remaining_today() <= 0.0:
		return 0.0
	if npc.is_relax_on_cooldown():
		return 0.0
	return BASE_SCORE * npc.get_work_ethic_passive_mult()

func interruptible() -> bool:
	return _inner == null or _inner.interruptible()

func enter(npc: NPC) -> void:
	npc.reset_relax_job_requests()
	_session_length = randf_range(SESSION_MIN, SESSION_MAX)
	_session_elapsed = 0.0
	_inner = RelaxSitActivity.new()
	_inner.enter(npc)
	if _inner.done(npc):   ## no free chair — try a bed instead
		_inner.exit(npc)
		_inner = RelaxLieActivity.new()
		_inner.enter(npc)
		if _inner.done(npc):   ## no free bed either — just stand in place
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
	if _session_elapsed >= _session_length:
		return true
	if _inner != null:
		return _inner.done(npc)
	return false

func exit(npc: NPC) -> void:
	if _session_elapsed > 0.01:   ## skip logging a session that never actually started
		npc.log_action("Relaxed for %d min" % int(round(_session_elapsed * 60.0)))
		npc.start_relax_cooldown()   ## spaces sessions apart — see NPC.gd's Relaxing section
	if _inner != null:
		_inner.exit(npc)
		_inner = null