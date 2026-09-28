extends NPCActivity
class_name RelaxActivity
## RelaxActivity.gd — a proper break: sit in a chair, else lie on a bed,
## else take a slow stroll. Budgeted per day (NPC.get_relax_daily_budget(),
## Lazy residents get more) with randomized gaps between sessions so breaks
## spread through the day instead of chaining.

const BASE_SCORE: float = 9.0
const SESSION_MIN: float = 0.33   ## game-hours (~20 min)
const SESSION_MAX: float = 0.67   ## game-hours (~40 min)

var _inner: NPCActivity = null
var _session_length: float = 0.0
var _session_elapsed: float = 0.0

func label() -> String:
	if _inner is WanderActivity:
		return "Taking a stroll"
	return "Relaxing" if _inner == null else "Relaxing (%s)" % _inner.label()

func score(npc: NPC) -> float:
	if npc.get_relax_time_remaining_today() <= 0.0 or npc.is_relax_on_cooldown() or npc.is_night_for_me() \
			or npc.crash.active() or npc.social.drive() >= 0.4:
		return 0.0   ## no breaks while being pushed hard
	return BASE_SCORE * npc.get_work_ethic_passive_mult()

func interruptible() -> bool:
	return _inner == null or _inner.interruptible() or _inner is WanderActivity

func can_yield_to_need(_npc: NPC) -> bool:
	return true

## A break is a break: ordinary chores don't pull someone off it; urgent
## work (a generator about to die) or a real need does.
func min_challenger_score() -> float:
	return 35.0

func enter(npc: NPC) -> void:
	npc.reset_relax_job_requests()
	_session_length = randf_range(SESSION_MIN, SESSION_MAX)
	_session_elapsed = 0.0
	for option: NPCActivity in [RelaxSitActivity.new(), RelaxLieActivity.new()]:
		option.enter(npc)
		if not option.done(npc):
			_inner = option
			return
		option.exit(npc)
	var stroll: WanderActivity = WanderActivity.new()
	stroll.leisurely = true
	_inner = stroll
	_inner.enter(npc)

func tick(npc: NPC, delta: float) -> void:
	var h: float = npc.game_hours(delta)
	_session_elapsed += h
	npc.spend_relax_time(h)
	if _inner != null:
		_inner.tick(npc, delta)

func done(npc: NPC) -> bool:
	if _session_elapsed >= _session_length:
		return true
	return _inner != null and not (_inner is WanderActivity) and _inner.done(npc)

func exit(npc: NPC) -> void:
	if _session_elapsed > 0.1:
		npc.log_action("Relaxed for %d min" % int(round(_session_elapsed * 60.0)))
		if _session_elapsed >= _session_length * 0.8:
			npc.add_thought("relaxed")
	if _session_elapsed > 0.01:
		npc.start_relax_cooldown()
	if _inner != null:
		_inner.exit(npc)
		_inner = null
