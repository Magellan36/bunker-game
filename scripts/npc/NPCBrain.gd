extends RefCounted
class_name NPCBrain
## NPCBrain.gd  (NPC Pass 2, Part 2)
## The Utility-AI decision loop. One instance per NPC (created in NPC._ready).
## Every THINK_INTERVAL (staggered per-NPC so all NPCs never think the same
## frame) it scores all candidate activities and switches when a challenger
## meaningfully beats the incumbent (hysteresis via SWITCH_MARGIN, so NPCs
## don't flip-flop between near-tied options).
##
## Parts 3 and 4 extend ONLY the _candidates array (and add activity classes)
## — the loop itself never changes. When Part 4 lands, job candidates are
## injected via JobBoard; needs candidates here stay as-is.
##
## Scoring philosophy: 0–100-ish scale.
##   Wander  — constant low baseline (5).
##   Sit     — scales with missing Energy; requires a free chair.
## Needs-driven scores use (100 - need) so "emptier need = higher urgency".

const THINK_INTERVAL: float = 1.0
const SWITCH_MARGIN:  float = 8.0   ## challenger must beat incumbent by this

var _npc: NPC = null
var _think_timer: float = 0.0
var _current: NPCActivity = null
var _candidates: Array[NPCActivity] = []

func setup(npc: NPC) -> void:
	_npc = npc
	_think_timer = randf() * THINK_INTERVAL   ## stagger
	_candidates = [
		WanderActivity.new(),
		SitActivity.new(),
		LieActivity.new(),
		DrinkActivity.new(),
		EatActivity.new(),
		RelaxActivity.new(),
		TalkActivity.new(),
		GiveToFriendActivity.new(),
		CleaningActivity.new(),
		RefuelActivity.new(),
		PutAwayHeldItemActivity.new(),
		GardeningActivity.new(),
	]

func current_label() -> String:
	return _current.label() if _current != null else "Idle"

## Aug 2026 — structured debug snapshot of whatever the NPC is currently
## doing, for NPCDebug.dump_cleaning_state(). Empty Dictionary if idle or
## the current activity doesn't implement debug_info().
func get_current_activity_debug_info() -> Dictionary:
	return _current.debug_info() if _current != null else {}

func is_relaxing() -> bool:
	return _current is RelaxActivity

func is_talking() -> bool:
	return _current is TalkActivity

func is_current_interruptible() -> bool:
	return _current == null or _current.interruptible()

## Reaches into the current TalkActivity instance directly — same-file
## access, no privacy concern; used by NPC.end_talk_session().
func get_talk_partner_name() -> String:
	if _current is TalkActivity:
		var t: TalkActivity = _current as TalkActivity
		if t._partner != null and is_instance_valid(t._partner) and ("npc_name" in t._partner):
			return String(t._partner.npc_name)
	return "someone"

func get_talk_partner_id() -> String:
	if _current is TalkActivity:
		var t: TalkActivity = _current as TalkActivity
		if t._partner != null and is_instance_valid(t._partner) and ("npc_id" in t._partner):
			return String(t._partner.npc_id)
	return ""

func end_talk_if_talking() -> void:
	if _current is TalkActivity:
		(_current as TalkActivity)._partner = null

## Player-issued command (Part 19) — force-starts the given activity
## immediately, exiting whatever's currently running via its own exit()
## (releases jobs/items/seats exactly like any other interruption, so this
## is always safe regardless of what the NPC was doing). Bypasses normal
## scoring entirely — only Part 14's pass-out override (checked every frame
## ahead of everything else) can still preempt a command.
func force_command(activity: NPCActivity) -> void:
	if _current != null:
		NPCDebug.log_activity(_npc, _current.label(), "Commanded: " + activity.label())
		_current.exit(_npc)
	_current = activity
	_current.enter(_npc)
	_think_timer = THINK_INTERVAL   ## don't immediately re-think and override the command

## Called by NPC._physics_process every frame.
func tick(delta: float) -> void:
	## Pass-out (Part 14) preempts everything, checked every frame — an
	## empty energy bar collapses the NPC immediately, not on the next
	## think-cycle, and can't be interrupted by anything else.
	if _npc.is_passed_out() and not (_current is PassedOutActivity):
		if _current != null:
			NPCDebug.log_activity(_npc, _current.label(), "Passed Out")
			_current.exit(_npc)
		_current = PassedOutActivity.new()
		_current.enter(_npc)

	if _current != null:
		_current.tick(_npc, delta)
		## Part 30 — explicit handoff to a SPECIFIC successor. Calling
		## force_command() reentrantly from inside an activity's own
		## tick() is unsafe (this same block would immediately stomp
		## whatever force_command() had just set, at the `_current = null`
		## line below) — take_handoff() exists so an activity can request
		## an exact successor safely, from out here in the outer scope.
		var handoff: NPCActivity = _current.take_handoff()
		if handoff != null:
			_current.exit(_npc)
			_current = handoff
			_current.enter(_npc)
			_current.begin_with_item(_npc, _npc.held_item)   ## no-op unless the successor implements it
			_think_timer = THINK_INTERVAL   ## same reasoning as force_command() — don't immediately override this
		elif _current.done(_npc):
			_current.exit(_npc)
			_current = null

	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = THINK_INTERVAL
	_think()

func _think() -> void:
	var best: NPCActivity = null
	var best_score: float = 0.0

	## Job candidates (Part 4): one throwaway JobActivity per open job. Only
	## unclaimed jobs are offered; claiming happens in JobActivity.enter().
	var scan: Array[NPCActivity] = _candidates.duplicate()
	for job: Dictionary in JobBoard.get_open_jobs():
		scan.append(JobActivity.new(job))

	for cand: NPCActivity in scan:
		if cand == _current:
			continue
		var s: float = cand.score(_npc)
		if s > best_score:
			best_score = s
			best = cand

	if best == null:
		return

	## Forgetfulness (Part 14) — only ever second-guesses a JOB about to be
	## started, never Wander/Eat/Drink/Sit/Lie (those are the NPC's own
	## needs, not "work"). Rolled once right here, not per-frame, so a
	## triggered diversion commits to a full 20s wander instead of
	## re-rolling every think-tick.
	if best is JobActivity:
		var forget_chance: float = _npc.get_forgetfulness_chance()
		var triggered: bool = randf() < forget_chance
		NPCDebug.log_forgetfulness_roll(_npc, forget_chance, triggered)
		if triggered:
			best = ForgetfulWanderActivity.new()

	if _current == null:
		NPCDebug.log_activity(_npc, "Idle", best.label())
		_start(best)
		return

	## Incumbent defends its seat: challenger needs margin AND permission.
	if _current.interruptible() and best_score > _current.score(_npc) + SWITCH_MARGIN:
		## Aug 2026 — this is the exact moment an activity gets
		## preempted, and previously the ONLY thing logged was the bare
		## "X -> Y" label transition, with no indication of WHY —
		## whether it was a natural score win, by how much, or what the
		## incumbent's own score was. This was the missing piece when
		## diagnosing a session getting dropped for no visible reason.
		if NPCDebug.enabled:
			NPCDebug.log_interrupt(_npc, _current.label(), _current.score(_npc), best.label(), best_score, SWITCH_MARGIN)
			## Aug 2026 — canary: this exact combination (interruptible
			## while still physically holding something) is what let the
			## trash-delivery bug's stale _item==null state produce a
			## normal, unremarkable-looking interrupt every time.
			if _npc.held_item != null:
				NPCDebug.log_suspicious_interrupt(_npc, _current.label(), best.label())
		NPCDebug.log_activity(_npc, _current.label(), best.label())
		_current.exit(_npc)
		_start(best)

func _start(activity: NPCActivity) -> void:
	_current = activity
	_current.enter(_npc)

## Force-stop whatever is running (used by save/load in Part 6 and by
## external interrupts later). Safe to call any time.
func stop_current() -> void:
	if _current != null:
		_current.exit(_npc)
		_current = null