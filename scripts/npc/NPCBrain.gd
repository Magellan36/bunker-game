extends RefCounted
class_name NPCBrain
## NPCBrain.gd — the Utility-AI decision loop. One instance per NPC.
##
## Every THINK_INTERVAL (staggered per NPC) it scores every candidate
## activity and switches when a challenger meaningfully beats the incumbent.
##
## Sep 2026 rework — every activity change now goes through ONE function,
## _switch_to(), which is where the guarantees that used to be scattered
## (and regularly forgotten) across ~20 activity files now live:
##
##   • Reservations: NPCItemUser.release_all_for() after every exit, so no
##     item/cell/stove reservation can outlive the activity that made it.
##   • Hands: an activity that can't use what the NPC is carrying never
##     inherits it (see NPCActivity.accepts_held_item()). The item is set
##     down first — no more "Eating" a basket forever, no more gardening
##     with a food can, no more second item stacked onto a full hand.
##   • No idle gaps: when an activity finishes, the next one is chosen the
##     same frame instead of standing frozen until the next think tick.
##   • Futility backoff: an activity that ends almost immediately without
##     accomplishing anything (its availability check said "yes", its
##     enter() found nothing to do) is benched for a growing cooldown.
##     This is the generic cure for the flicker/"frozen" loop class where an
##     NPC re-enters the same dead activity every second forever.
##   • Urgent needs can pull an NPC out of a long job session, but only at
##     a safe point (hands empty) — see NPCActivity.can_yield_to_need().
##
## Hysteresis is RELATIVE (a challenger must beat the incumbent by
## SWITCH_MARGIN_REL and SWITCH_MARGIN_ABS) plus a short commitment bonus
## right after starting, so NPCs don't flip-flop between near-tied options
## on any score scale.

const THINK_INTERVAL: float = 1.0
const SWITCH_MARGIN_ABS: float = 4.0
const SWITCH_MARGIN_REL: float = 0.20
const COMMIT_TIME: float = 6.0           ## seconds after starting during which the incumbent defends harder
const COMMIT_BONUS_REL: float = 0.25
## A need scoring at/above this may interrupt a non-interruptible activity
## at a safe point (see can_yield_to_need()).
const URGENT_NEED_SCORE: float = 70.0

## Futility backoff — an activity that ends (by itself, not interrupted)
## within FUTILE_SEC of starting is considered to have found nothing to do.
const FUTILE_SEC: float = 1.25
const BACKOFF_BASE: float = 4.0
const BACKOFF_MAX: float = 90.0

var _npc: NPC = null
var _think_timer: float = 0.0
var _current: NPCActivity = null
var _candidates: Array[NPCActivity] = []

var _clock: float = 0.0                  ## brain-local seconds (scaled physics time)
var _current_started: float = 0.0
var _backoff: Dictionary = {}            ## activity key -> {"until": float, "streak": int}
var last_switch_reason: String = ""      ## surfaced by debug tooling / the talk menu

func setup(npc: NPC) -> void:
	_npc = npc
	_think_timer = randf() * THINK_INTERVAL   ## stagger
	_candidates = [
		CrashOutActivity.new(),
		FleeActivity.new(),
		WanderActivity.new(),
		LeanActivity.new(),
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
		CookingActivity.new(),
	]

func current_label() -> String:
	return _current.label() if _current != null else "Idle"

func current_activity() -> NPCActivity:
	return _current

## Structured debug snapshot of whatever the NPC is currently doing.
func get_current_activity_debug_info() -> Dictionary:
	return _current.debug_info() if _current != null else {}

func is_relaxing() -> bool:
	return _current is RelaxActivity

func is_talking() -> bool:
	return _current is TalkActivity

func is_sleeping() -> bool:
	return _current is LieActivity and (_current as LieActivity).is_asleep()

func is_current_interruptible() -> bool:
	return _current == null or _current.interruptible()

func get_talk_partner_name() -> String:
	if _current is TalkActivity:
		var p: Node = (_current as TalkActivity).get_partner()
		if p != null and ("npc_name" in p):
			return String(p.npc_name)
	return "someone"

func get_talk_partner_id() -> String:
	if _current is TalkActivity:
		var p: Node = (_current as TalkActivity).get_partner()
		if p != null and ("npc_id" in p):
			return String(p.npc_id)
	return ""

func end_talk_if_talking() -> void:
	if _current is TalkActivity:
		(_current as TalkActivity).end_session()

## Player-issued command (Part 19) — force-starts the given activity
## immediately. Bypasses scoring entirely; only pass-out can preempt it.
func force_command(activity: NPCActivity) -> void:
	_switch_to(activity, "command")
	_think_timer = THINK_INTERVAL   ## don't immediately re-think and override the command

## Force-stop whatever is running (save/load, stuck recovery). Safe any time.
func stop_current() -> void:
	if _current != null:
		_exit_current(false)
	_current = null

## Abandons the current activity (stuck, fell out of the world...) and
## benches that activity type so the NPC doesn't walk straight back into
## the same failure.
func abandon_current(reason: String, bench_seconds: float) -> void:
	if _current == null:
		return
	var key: String = _key(_current)
	if bench_seconds > 0.0 and _current.backoff_on_futile():
		_backoff[key] = {"until": _clock + bench_seconds, "streak": int(_backoff.get(key, {}).get("streak", 0))}
	last_switch_reason = "abandoned %s: %s" % [_current.label(), reason]
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(_npc, "abandoned activity", last_switch_reason)
	_exit_current(false)
	_current = null
	_think_timer = 0.0

## Called by NPC._physics_process every frame.
func tick(delta: float) -> void:
	_clock += delta
	## Pass-out (Part 14) preempts everything, checked every frame.
	if _npc.is_passed_out() and not (_current is PassedOutActivity):
		_switch_to(PassedOutActivity.new(), "passed out")

	## Blocked doorway (flagged by NPC.nav_steer): abandon here, between
	## activity ticks — never re-entrantly from inside the activity's tick.
	if _npc.door_blocked:
		_npc.door_blocked = false
		if _current != null:
			abandon_current("door won't open", 20.0)
	if _current != null:
		_current.tick(_npc, delta)
		## Part 30 — explicit hand-off to a specific successor (Snatch →
		## GivenEat etc.), taken out here rather than re-entrantly.
		var handoff: NPCActivity = _current.take_handoff() if _current != null else null
		if handoff != null:
			_switch_to(handoff, "handoff")
			_current.begin_with_item(_npc, _npc.held_item)
			_think_timer = THINK_INTERVAL
		elif _current != null and _current.done(_npc):
			_exit_current(true)
			_current = null
			_think_timer = 0.0   ## choose the next thing THIS frame — no frozen idle gap

	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = THINK_INTERVAL
	_think()

## Score of a candidate with futility backoff applied.
func _score(cand: NPCActivity) -> float:
	var key: String = _key(cand)
	if _backoff.has(key) and _clock < float(_backoff[key]["until"]):
		return 0.0
	return cand.score(_npc)

func _think() -> void:
	var best: NPCActivity = null
	var best_score: float = 0.0

	## Job candidates (Part 4): one throwaway JobActivity per open job.
	var scan: Array[NPCActivity] = _candidates.duplicate()
	for job: Dictionary in JobBoard.get_open_jobs():
		scan.append(JobActivity.new(job))

	for cand: NPCActivity in scan:
		if cand == _current:
			continue
		var s: float = _score(cand)
		if s > best_score:
			best_score = s
			best = cand

	if best == null:
		return

	## Forgetfulness (Part 14) — only ever second-guesses a JOB about to be
	## started, never the NPC's own needs. Rolled once, here.
	if best.is_work():
		var forget_chance: float = _npc.get_forgetfulness_chance()
		var triggered: bool = randf() < forget_chance
		NPCDebug.log_forgetfulness_roll(_npc, forget_chance, triggered)
		if triggered:
			best = ForgetfulWanderActivity.new()

	if _current == null:
		_start_fresh(best, "idle → %s (%.1f)" % [best.label(), best_score])
		return

	var incumbent: float = _current.score(_npc)
	var defend: float = incumbent
	if _clock - _current_started < COMMIT_TIME:
		defend *= 1.0 + COMMIT_BONUS_REL
	var needed: float = maxf(maxf(defend * (1.0 + SWITCH_MARGIN_REL), defend + SWITCH_MARGIN_ABS),
		_current.min_challenger_score())
	if best_score <= needed:
		return

	var allowed: bool = _current.interruptible()
	if not allowed and best.is_need() and best_score >= URGENT_NEED_SCORE:
		allowed = _current.can_yield_to_need(_npc)
	if not allowed:
		return

	if NPCDebug.enabled:
		NPCDebug.log_interrupt(_npc, _current.label(), incumbent, best.label(), best_score, needed - incumbent)
	_switch_to(best, "%s beat %s (%.1f > %.1f)" % [best.label(), _current.label(), best_score, incumbent])

## Swap the candidate instance out for a fresh one so per-activity state is
## never shared between two runs (candidates are reused only for scoring).
func _start_fresh(proto: NPCActivity, reason: String) -> void:
	var act: NPCActivity = proto
	if proto in _candidates:
		act = proto.get_script().new()
	_switch_to(act, reason)

## THE single activity-change path. See the header for what it guarantees.
func _switch_to(activity: NPCActivity, reason: String) -> void:
	if _current != null:
		NPCDebug.log_activity(_npc, _current.label(), activity.label())
		_exit_current(false)
	elif NPCDebug.enabled:
		NPCDebug.log_activity(_npc, "Idle", activity.label())
	last_switch_reason = reason
	_current = activity
	_current_started = _clock
	## Hands policy — never let an activity inherit an item it can't use.
	if NPCItemUser.hands_full(_npc) and not activity.accepts_held_item(_npc, _npc.held_item):
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(_npc, "set down held item", "%s can't use %s" % [activity.label(), NPCSessionActivity.display_name(_npc.held_item)])
		NPCItemUser.drop_held(_npc)
	_current.enter(_npc)

## Exit bookkeeping shared by every path. `finished_naturally` = the
## activity reported done() itself (as opposed to being interrupted).
func _exit_current(finished_naturally: bool) -> void:
	var act: NPCActivity = _current
	act.exit(_npc)
	NPCItemUser.release_all_for(_npc)
	_npc.hide_work_banner()
	var ran: float = _clock - _current_started
	var key: String = _key(act)
	if finished_naturally and ran < FUTILE_SEC and act.backoff_on_futile():
		var streak: int = int(_backoff.get(key, {}).get("streak", 0)) + 1
		var wait: float = minf(BACKOFF_MAX, BACKOFF_BASE * pow(2.0, float(streak - 1)))
		_backoff[key] = {"until": _clock + wait, "streak": streak}
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(_npc, "futile activity benched", "%s ended after %.2fs — benched %.0fs (streak %d)" % [key, ran, wait, streak])
	elif ran >= FUTILE_SEC * 4.0 and _backoff.has(key):
		_backoff.erase(key)   ## it accomplished something — forgive

func _key(act: NPCActivity) -> String:
	var s: Script = act.get_script()
	return s.get_global_name() if s != null else "?"
