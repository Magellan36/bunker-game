extends RefCounted
class_name NPCBrain
const NPC_METRICS: GDScript = preload("res://scripts/npc/NPCMetrics.gd")
## NPCBrain.gd  (NPC Pass 2, Part 2)
## The Utility-AI decision loop. One instance per NPC (created in NPC._ready).
## Every THINK_INTERVAL (staggered per-NPC so all NPCs never think the same
## frame) it scores all candidate activities and switches when a challenger
## meaningfully beats the incumbent. The incumbent owns its switch margin:
## passive activities yield readily while purposeful work keeps more inertia.
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
const PLAYER_INTERACTION_RESUME_GRACE: float = 5.0
const CRITICAL_NEED_THRESHOLD: float = 25.0
## Last-resort lifecycle watchdog. Times are REAL seconds, not simulation
## seconds, so 20x speed cannot collapse the safety margins into a few frames.
const WATCHDOG_SAMPLE_INTERVAL: float = 0.5
const WATCHDOG_BROKEN_ROUTE_TIMEOUT: float = 3.0
const WATCHDOG_TRAVEL_NO_PROGRESS_TIMEOUT: float = 10.0
const WATCHDOG_ACTIVITY_NO_PROGRESS_TIMEOUT: float = 45.0
const WATCHDOG_POSITION_PROGRESS: float = 0.08
const WATCHDOG_ROUTE_PROGRESS: float = 0.12
const WATCHDOG_REPEAT_WINDOW: float = 30.0
const WATCHDOG_REPEAT_QUARANTINE: float = 3.0
const WATCHDOG_LOOP_WINDOW: float = 45.0
const WATCHDOG_LOOP_REPEATS: int = 3
const WATCHDOG_LOOP_MAX_PATTERN: int = 4
const WATCHDOG_LOOP_HISTORY_CAPACITY: int = 24
const WATCHDOG_LOOP_QUARANTINE: float = 8.0
const WATCHDOG_LOOP_KEYS: Array[String] = [
	"activity", "phase", "mode", "task", "job_id", "target", "tray", "cell",
	"item", "destination", "source", "carrying", "current_generator",
	"last_failure_reason",
]
var _npc: NPC = null
var _think_timer: float = 0.0
var _current: NPCActivity = null
var _navigation_recovery: NPCClearPathActivity = null
var _candidates: Array[NPCActivity] = []
var _deferred_intent: Dictionary = {}
var _behavior_clock_hours: float = 0.0
var _player_interaction_active: bool = false
var _player_interaction_resume_grace: float = 0.0
var _watchdog_sample_elapsed: float = 0.0
var _watchdog_no_progress_elapsed: float = 0.0
var _watchdog_broken_route_elapsed: float = 0.0
var _watchdog_last_position: Vector3 = Vector3.INF
var _watchdog_last_remaining: float = INF
var _watchdog_last_token: String = ""
var _watchdog_activity_id: int = 0
var _watchdog_travel_intent: bool = false
var _watchdog_last_reset_type: String = ""
var _watchdog_since_last_reset: float = INF
var _watchdog_repeat_count: int = 0
var _watchdog_quarantine_left: float = 0.0
var _watchdog_real_clock: float = 0.0
var _watchdog_loop_history: Array[Dictionary] = []
var _watchdog_last_loop_signature: String = ""
var _watchdog_loop_quarantines: Dictionary = {}
var _watchdog_loop_context: Array[Dictionary] = []
const RESUME_INTENT_LIFETIME_HOURS: float = 2.0

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
		CookingActivity.new(),
	]

func current_label() -> String:
	if _player_interaction_active:
		return "Talking to player"
	if _navigation_recovery != null:
		return _navigation_recovery.label()
	return _current.label() if _current != null else "Idle"

func has_current_activity() -> bool:
	return _current != null

## Seeds a newly-started capture with the activity already in progress. This
## does not re-enter or otherwise touch gameplay state.
func sync_metrics_capture() -> void:
	if NPC_METRICS.enabled and _current != null:
		NPC_METRICS.begin_activity(_npc, _current, "capture_started_mid_activity", {
			"activity_info": _current.debug_info(),
		})

## Aug 2026 — structured debug snapshot of whatever the NPC is currently
## doing, for NPCDebug.dump_cleaning_state(). Empty Dictionary if idle or
## the current activity doesn't implement debug_info().
func get_current_activity_debug_info() -> Dictionary:
	if _navigation_recovery != null:
		var recovery_info: Dictionary = _navigation_recovery.debug_info()
		recovery_info["paused_activity"] = _current.label() if _current != null else "Idle"
		return recovery_info
	var info: Dictionary = _current.debug_info() if _current != null else {}
	if _current != null:
		info["watchdog"] = get_watchdog_debug_info()
	if not _deferred_intent.is_empty():
		info["deferred_intent"] = _deferred_intent.duplicate(true)
	return info


func get_watchdog_debug_info() -> Dictionary:
	return {
		"no_progress_real_sec": _watchdog_no_progress_elapsed,
		"broken_route_real_sec": _watchdog_broken_route_elapsed,
		"expects_movement": _watchdog_travel_intent,
		"repeat_resets": _watchdog_repeat_count,
		"quarantined_type": _watchdog_last_reset_type if _watchdog_quarantine_left > 0.0 else "",
		"quarantine_real_sec": _watchdog_quarantine_left,
		"loop_state_count": _watchdog_loop_history.size(),
		"loop_quarantines": _watchdog_loop_quarantines.duplicate(),
		"recent_loop_states": _watchdog_loop_history.slice(
			maxi(0, _watchdog_loop_history.size() - 8)),
	}

func get_attention_target() -> Node3D:
	if _player_interaction_active and _npc != null and _npc.is_inside_tree():
		return _npc.get_tree().get_first_node_in_group("player") as Node3D
	if _navigation_recovery != null:
		return _navigation_recovery.attention_target(_npc)
	return _current.attention_target(_npc) if _current != null else null


func is_player_interacting() -> bool:
	return _player_interaction_active


## This is a true pause, not an activity transition. The live activity object,
## its phase/timers/claims/held-item state, and the NavigationAgent route all
## remain untouched until end_player_interaction().
func begin_player_interaction() -> void:
	if _player_interaction_active:
		return
	_player_interaction_active = true
	_player_interaction_resume_grace = 0.0
	NPC_METRICS.increment(&"player_npc_interactions")
	NPC_METRICS.record_event(&"player_interaction_started", _npc, {
		"paused_activity": _current.label() if _current != null else "Idle",
	})


func end_player_interaction() -> void:
	if not _player_interaction_active:
		return
	_player_interaction_active = false
	_player_interaction_resume_grace = PLAYER_INTERACTION_RESUME_GRACE
	# Preserve the incumbent for a few readable seconds after a harmless UI
	# check. Critical needs may re-score immediately instead.
	_think_timer = 0.0 if _has_critical_need() else maxf(
		_think_timer, PLAYER_INTERACTION_RESUME_GRACE)
	NPC_METRICS.record_event(&"player_interaction_ended", _npc, {
		"resuming_activity": _current.label() if _current != null else "Idle",
	})

func is_relaxing() -> bool:
	return _current is RelaxActivity

func is_talking() -> bool:
	return _current is TalkActivity

func is_current_interruptible() -> bool:
	return _navigation_recovery == null and (_current == null or _current.interruptible())


func begin_navigation_recovery(item: RigidBody3D, resume_target: Vector3,
		resume_distance: float, corridor_finish: Vector3) -> bool:
	if _navigation_recovery != null or item == null or not is_instance_valid(item):
		return false
	_navigation_recovery = NPCClearPathActivity.new(
		item, resume_target, resume_distance, corridor_finish)
	_navigation_recovery.enter(_npc)
	if _navigation_recovery.done(_npc):
		var failed_item_id: int = _navigation_recovery.obstruction_id()
		_navigation_recovery.exit(_npc)
		_navigation_recovery = null
		if failed_item_id >= 0:
			_npc.note_navigation_clear_result(failed_item_id, false)
		return false
	NPC_METRICS.increment(&"navigation_clear_attempts")
	NPC_METRICS.record_event(&"navigation_clear_started", _npc, {
		"item_id": item.get_instance_id(),
		"paused_activity": _current.label() if _current != null else "Idle",
	})
	return true


func has_navigation_recovery() -> bool:
	return _navigation_recovery != null


func _stop_navigation_recovery() -> void:
	if _navigation_recovery == null:
		return
	_navigation_recovery.exit(_npc)
	_navigation_recovery = null

## Companionship is a lightweight overlay, not a conversation command. It may
## coexist with nearby leisure and the two jobs that naturally make sense to
## share (gardening/cleaning), even when the current job is non-interruptible.
func is_companionship_compatible() -> bool:
	return _activity_allows_companionship(_current)

func _activity_allows_companionship(activity: NPCActivity) -> bool:
	return activity == null \
		or activity is WanderActivity \
		or activity is SitActivity \
		or activity is LieActivity \
		or activity is RelaxActivity \
		or activity is GardeningActivity \
		or activity is CleaningActivity

func _prepare_companionship_for(activity: NPCActivity) -> void:
	if not _activity_allows_companionship(activity):
		_npc.end_companionship()

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
	_stop_navigation_recovery()
	_clear_loop_history()
	var previous_label: String = _current.label() if _current != null else "Idle"
	NPC_METRICS.record_decision(_npc, _make_decision_receipt(
		"forced", "external_command", activity, 0.0, 0.0, 0.0, []))
	if _current != null:
		NPCDebug.log_activity(_npc, _current.label(), "Commanded: " + activity.label())
		NPC_METRICS.end_activity(_npc, "forced_command", {
			"successor": activity.debug_type(),
		})
		_current.exit(_npc)
		_npc.cancel_navigation()
	_prepare_companionship_for(activity)
	_current = activity
	_current.enter(_npc)
	NPC_METRICS.begin_activity(_npc, _current, "forced_command")
	NPC_METRICS.increment(&"activity_forced_commands")
	_record_activity_event(&"activity_forced", previous_label, _current.label())
	_think_timer = THINK_INTERVAL   ## don't immediately re-think and override the command

## Called by NPC._physics_process every frame.
func tick(delta: float) -> void:
	_behavior_clock_hours += _npc.game_hours(delta)
	var real_delta: float = minf(delta / maxf(float(Engine.time_scale), 0.001), 0.25)
	_watchdog_real_clock += real_delta
	_watchdog_since_last_reset += real_delta
	_watchdog_quarantine_left = maxf(0.0, _watchdog_quarantine_left - real_delta)
	_tick_loop_quarantines(real_delta)
	## Pass-out (Part 14) preempts everything, checked every frame — an
	## empty energy bar collapses the NPC immediately, not on the next
	## think-cycle, and can't be interrupted by anything else.
	if _npc.is_passed_out() and _player_interaction_active:
		_player_interaction_active = false
		_npc.call_deferred("close_talk_menu_for_critical_state")
	if _npc.is_passed_out() and not (_current is PassedOutActivity):
		_stop_navigation_recovery()
		_clear_loop_history()
		var passed_out_activity := PassedOutActivity.new()
		NPC_METRICS.record_decision(_npc, _make_decision_receipt(
			"passout", "energy_depleted", passed_out_activity, 0.0, 0.0, 0.0, []))
		if _current != null:
			NPCDebug.log_activity(_npc, _current.label(), "Passed Out")
			NPC_METRICS.end_activity(_npc, "passed_out")
			_current.exit(_npc)
			_npc.cancel_navigation()
		_current = passed_out_activity
		_prepare_companionship_for(_current)
		_current.enter(_npc)
		NPC_METRICS.begin_activity(_npc, _current, "passed_out")

	if _player_interaction_active:
		_reset_watchdog_tracking()
		_npc.lock_movement()
		var player: Node3D = _npc.get_tree().get_first_node_in_group("player") as Node3D
		if player != null:
			_npc.face_world_position(player.global_position)
		return

	if _navigation_recovery != null:
		_reset_watchdog_tracking()
		if _has_critical_need():
			_stop_navigation_recovery()
			_think_timer = 0.0
		else:
			_navigation_recovery.tick(_npc, delta)
			if _navigation_recovery.done(_npc):
				var succeeded: bool = _navigation_recovery.succeeded()
				var item_id: int = _navigation_recovery.obstruction_id()
				_navigation_recovery.exit(_npc)
				_navigation_recovery = null
				if item_id >= 0:
					_npc.note_navigation_clear_result(item_id, succeeded)
				var metric_name: StringName = &"navigation_clear_succeeded" if succeeded \
					else &"navigation_clear_failed"
				NPC_METRICS.increment(metric_name)
				NPC_METRICS.record_event(&"navigation_clear_finished", _npc, {
					"succeeded": succeeded,
					"resuming_activity": _current.label() if _current != null else "Idle",
				})
				if not succeeded:
					NPC_METRICS.record_anomaly(&"navigation_clear_failed", _npc, {
						"item_id": item_id,
					}, _npc.get_navigation_debug_info())
			return

	if _current != null:
		if _tick_behavior_watchdog(real_delta):
			return
		_current.tick(_npc, delta)
		## Part 30 — explicit handoff to a SPECIFIC successor. Calling
		## force_command() reentrantly from inside an activity's own
		## tick() is unsafe (this same block would immediately stomp
		## whatever force_command() had just set, at the `_current = null`
		## line below) — take_handoff() exists so an activity can request
		## an exact successor safely, from out here in the outer scope.
		var handoff: NPCActivity = _current.take_handoff()
		if handoff != null:
			var handoff_from: String = _current.label()
			NPC_METRICS.record_decision(_npc, _make_decision_receipt(
				"handoff", "activity_requested_successor", handoff, 0.0, 0.0, 0.0, []))
			NPC_METRICS.end_activity(_npc, "handoff", {
				"successor": handoff.debug_type(),
			})
			_current.exit(_npc)
			_npc.cancel_navigation()
			_prepare_companionship_for(handoff)
			_current = handoff
			_current.enter(_npc)
			_current.begin_with_item(_npc, _npc.held_item)   ## no-op unless the successor implements it
			NPC_METRICS.begin_activity(_npc, _current, "handoff")
			NPC_METRICS.increment(&"activity_handoffs")
			_record_activity_event(&"activity_handoff", handoff_from, _current.label())
			_record_watchdog_loop_state(_current, _npc.get_navigation_watchdog_state(), true)
			_think_timer = THINK_INTERVAL   ## same reasoning as force_command() — don't immediately override this
		elif _current.done(_npc):
			var completed_label: String = _current.label()
			NPC_METRICS.record_decision(_npc, _make_decision_receipt(
				"completed", "activity_reported_done", null, 0.0, 0.0, 0.0, []))
			NPC_METRICS.end_activity(_npc, "completed", {
				"activity_info": _current.debug_info(),
			})
			_current.exit(_npc)
			_npc.cancel_navigation()
			_current = null
			NPC_METRICS.increment(&"activity_completed")
			_record_activity_event(&"activity_completed", completed_label, "Idle")

	_player_interaction_resume_grace = maxf(0.0, _player_interaction_resume_grace - delta)
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = THINK_INTERVAL
	_think()

func _think() -> void:
	if _player_interaction_resume_grace > 0.0 and not _has_critical_need():
		NPC_METRICS.record_decision(_npc, _make_decision_receipt(
			"held", "player_interaction_resume_grace", null, 0.0, 0.0, 0.0, []))
		return
	## A non-interruptible activity cannot act on any challenger score. Avoid
	## running every world/resource query merely to reject the winner below;
	## completion and pass-out handling still run every physics tick in tick().
	if _current != null and not _current.interruptible():
		return
	NPC_METRICS.increment(&"utility_think_cycles")
	_prune_deferred_intent()
	var best: NPCActivity = null
	var best_score: float = 0.0
	var evaluations: Array[Dictionary] = []

	## Job candidates (Part 4): one throwaway JobActivity per open job. Only
	## unclaimed jobs are offered; claiming happens in JobActivity.enter().
	var scan: Array[NPCActivity] = _candidates.duplicate()
	for job: Dictionary in JobBoard.get_open_jobs():
		scan.append(JobActivity.new(job))
	## Resume only at an idle boundary, never by preempting the need/work that
	## caused the interruption. The normal score scan may still prefer a real
	## job or urgent need over this bounded continuity bonus.
	if _current == null and not _deferred_intent.is_empty():
		var resumed := WanderActivity.new()
		resumed.configure_resume(_deferred_intent)
		scan.append(resumed)

	for cand: NPCActivity in scan:
		if cand == _current:
			continue
		var candidate_type: String = cand.debug_type()
		var quarantined: bool = (_watchdog_quarantine_left > 0.0 \
			and candidate_type == _watchdog_last_reset_type) \
			or float(_watchdog_loop_quarantines.get(candidate_type, 0.0)) > 0.0
		var s: float = 0.0 if quarantined else cand.score(_npc)
		if NPC_METRICS.enabled:
			evaluations.append({
				"activity_type": cand.debug_type(),
				"label": cand.label(),
				"score": s,
				"reason": "watchdog_loop_or_repeat_cooldown" if quarantined \
					else String(cand.debug_score_reason(_npc, s)),
			})
		if s > best_score:
			best_score = s
			best = cand
	NPC_METRICS.observe(&"utility_candidate_count", float(scan.size()), [5.0, 10.0, 15.0, 20.0, 30.0])
	NPC_METRICS.observe(&"utility_best_score", best_score, [0.0, 5.0, 10.0, 20.0, 40.0, 60.0, 80.0, 100.0])

	if best == null:
		NPC_METRICS.record_decision(_npc, _make_decision_receipt(
			"held", "no_eligible_candidate", null, 0.0, 0.0, 0.0, evaluations))
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
		NPC_METRICS.record_decision(_npc, _make_decision_receipt(
			"started", "highest_score", best, best_score, 0.0, 0.0, evaluations))
		if best.is_resume_candidate():
			_deferred_intent.clear()
		_start(best, "utility_selection")
		return

	## Incumbent defends its seat: challenger needs its activity-specific
	## margin AND permission. A single global margin made endless Wander
	## suppress low-scored but meaningful work indefinitely.
	var current_score: float = _current.score(_npc)
	var margin: float = _current.switch_margin()
	if _current.interruptible() and best_score > current_score + margin:
		## Aug 2026 — this is the exact moment an activity gets
		## preempted, and previously the ONLY thing logged was the bare
		## "X -> Y" label transition, with no indication of WHY —
		## whether it was a natural score win, by how much, or what the
		## incumbent's own score was. This was the missing piece when
		## diagnosing a session getting dropped for no visible reason.
		if NPCDebug.enabled:
			NPCDebug.log_interrupt(_npc, _current.label(), current_score, best.label(), best_score, margin)
			## Aug 2026 — canary: this exact combination (interruptible
			## while still physically holding something) is what let the
			## trash-delivery bug's stale _item==null state produce a
			## normal, unremarkable-looking interrupt every time.
			if _npc.held_item != null:
				NPCDebug.log_suspicious_interrupt(_npc, _current.label(), best.label())
		NPCDebug.log_activity(_npc, _current.label(), best.label())
		var interrupted_label: String = _current.label()
		NPC_METRICS.record_decision(_npc, _make_decision_receipt(
			"interrupted", "challenger_exceeded_margin", best, best_score,
			current_score, margin, evaluations))
		_capture_resume_intent()
		NPC_METRICS.end_activity(_npc, "interrupted", {
			"successor": best.debug_type(), "current_score": current_score,
			"challenger_score": best_score, "margin": margin,
		})
		_current.exit(_npc)
		_npc.cancel_navigation()
		_start(best, "utility_interrupt")
		NPC_METRICS.increment(&"activity_interruptions")
		NPC_METRICS.observe(&"utility_interrupt_score_advantage", best_score - current_score,
			[0.0, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0])
		_record_activity_event(&"activity_interrupted", interrupted_label, best.label(), {
			"current_score": current_score, "challenger_score": best_score, "margin": margin,
		})
	elif not _current.interruptible():
		NPC_METRICS.increment(&"utility_rejected_not_interruptible")
		NPC_METRICS.record_decision(_npc, _make_decision_receipt(
			"held", "current_not_interruptible", best, best_score,
			current_score, margin, evaluations))
	elif best_score <= current_score + margin:
		NPC_METRICS.increment(&"utility_rejected_switch_margin")
		NPC_METRICS.record_decision(_npc, _make_decision_receipt(
			"held", "switch_margin_not_met", best, best_score,
			current_score, margin, evaluations))


func _has_critical_need() -> bool:
	return _npc != null and (_npc.hunger < CRITICAL_NEED_THRESHOLD \
		or _npc.thirst < CRITICAL_NEED_THRESHOLD or _npc.energy <= 0.0)

func _start(activity: NPCActivity, reason: String = "utility_selection") -> void:
	_reset_watchdog_tracking()
	_prepare_companionship_for(activity)
	_current = activity
	_current.enter(_npc)
	NPC_METRICS.begin_activity(_npc, _current, reason)
	NPC_METRICS.increment(&"activity_started")
	_record_activity_event(&"activity_started", "Idle", _current.label())
	_record_watchdog_loop_state(_current, _npc.get_navigation_watchdog_state(), true)

## Force-stop whatever is running (used by save/load in Part 6 and by
## external interrupts later). Safe to call any time.
func stop_current() -> void:
	_stop_navigation_recovery()
	if _current != null:
		NPC_METRICS.end_activity(_npc, "external_stop")
		_current.exit(_npc)
		_npc.cancel_navigation()
		_current = null
	_deferred_intent.clear()
	_reset_watchdog_tracking()
	_clear_loop_history()


func _tick_behavior_watchdog(real_delta: float) -> bool:
	if _current == null or _npc == null:
		_reset_watchdog_tracking()
		return false
	_watchdog_sample_elapsed += real_delta
	## Loop states can be shorter than the half-second progress sample at high
	## simulation speed, so capture semantic transitions every physics frame.
	## Identical signatures allocate nothing into the bounded history.
	var nav: Dictionary = _npc.get_navigation_watchdog_state()
	if _record_watchdog_loop_state(_current, nav):
		return true
	if _watchdog_sample_elapsed < WATCHDOG_SAMPLE_INTERVAL:
		return false
	var sample_delta: float = _watchdog_sample_elapsed
	_watchdog_sample_elapsed = 0.0
	var activity_id: int = _current.get_instance_id()
	var position: Vector3 = _npc.global_position
	var remaining: float = float(nav.get("remaining_distance", INF))
	var token: String = _current.watchdog_progress_token(_npc)
	if activity_id != _watchdog_activity_id:
		_watchdog_activity_id = activity_id
		_watchdog_last_position = position
		_watchdog_last_remaining = remaining
		_watchdog_last_token = token
		_watchdog_no_progress_elapsed = 0.0
		_watchdog_broken_route_elapsed = 0.0
		_watchdog_travel_intent = _current.watchdog_expects_movement(_npc) \
			or (not bool(nav.get("movement_locked", true)) \
				and float(nav.get("requested_speed", 0.0)) > 0.05)
		return false

	var moved: float = Vector2(position.x, position.z).distance_to(
		Vector2(_watchdog_last_position.x, _watchdog_last_position.z))
	var route_progress: float = 0.0
	if not is_inf(remaining) and not is_inf(_watchdog_last_remaining):
		route_progress = _watchdog_last_remaining - remaining
	var semantic_progress: bool = token != _watchdog_last_token
	var made_progress: bool = moved >= WATCHDOG_POSITION_PROGRESS \
		or route_progress >= WATCHDOG_ROUTE_PROGRESS or semantic_progress
	var currently_requesting_movement: bool = not bool(nav.get("movement_locked", true)) \
		and float(nav.get("requested_speed", 0.0)) > 0.05
	if semantic_progress:
		_watchdog_travel_intent = _current.watchdog_expects_movement(_npc) \
			or currently_requesting_movement
	elif currently_requesting_movement or _current.watchdog_expects_movement(_npc):
		_watchdog_travel_intent = true

	if made_progress:
		_watchdog_no_progress_elapsed = 0.0
		_watchdog_broken_route_elapsed = 0.0
	else:
		_watchdog_no_progress_elapsed += sample_delta
		var route_broken: bool = bool(nav.get("route_failed", false)) \
			or (not bool(nav.get("route_valid", false)) \
				and bool(nav.get("movement_locked", true)))
		if _watchdog_travel_intent and route_broken:
			_watchdog_broken_route_elapsed += sample_delta
		else:
			_watchdog_broken_route_elapsed = 0.0

	_watchdog_last_position = position
	_watchdog_last_remaining = remaining
	_watchdog_last_token = token

	if _watchdog_broken_route_elapsed >= WATCHDOG_BROKEN_ROUTE_TIMEOUT:
		return _recover_broken_activity("route_failed_or_abandoned",
			_watchdog_broken_route_elapsed, nav)
	if _watchdog_travel_intent \
			and _watchdog_no_progress_elapsed >= WATCHDOG_TRAVEL_NO_PROGRESS_TIMEOUT:
		return _recover_broken_activity("travel_without_progress",
			_watchdog_no_progress_elapsed, nav)
	if not _current.watchdog_allows_long_stationary(_npc) \
			and _watchdog_no_progress_elapsed >= WATCHDOG_ACTIVITY_NO_PROGRESS_TIMEOUT:
		return _recover_broken_activity("activity_lifecycle_without_progress",
			_watchdog_no_progress_elapsed, nav)
	return false


func _recover_broken_activity(reason: String, elapsed: float, nav: Dictionary) -> bool:
	if _current == null:
		return false
	var broken: NPCActivity = _current
	var broken_type: String = broken.debug_type()
	var broken_label: String = broken.label()
	var broken_info: Dictionary = broken.debug_info().duplicate(true)
	NPCDebug.log_watchdog_reset(_npc, broken_label, reason, elapsed)
	NPC_METRICS.increment(&"behavior_watchdog_resets")
	NPC_METRICS.increment(StringName("behavior_watchdog_%s" % reason))
	NPC_METRICS.record_anomaly(&"behavior_watchdog_reset", _npc, {
		"reason": reason,
		"elapsed_real_sec": elapsed,
		"activity_type": broken_type,
		"activity_label": broken_label,
		"activity_info_before_reset": broken_info,
		"navigation_watchdog": nav.duplicate(true),
		"loop_context": _watchdog_loop_context.duplicate(true),
	}, _npc.get_navigation_debug_info())
	NPC_METRICS.end_activity(_npc, "watchdog_reset", {
		"reason": reason, "activity_info": broken_info,
	})
	broken.exit(_npc)
	if reason == "repeated_state_loop" and _npc.held_item != null \
			and is_instance_valid(_npc.held_item):
		## A carried item is often the shared state linking two looping jobs.
		## Put it back into the world so the fresh utility pass starts cleanly.
		NPCItemUser.drop_held(_npc)
	_npc.cancel_navigation()
	_npc.reset_navigation_recovery_state()
	_current = null
	_deferred_intent.clear()
	if broken_type == _watchdog_last_reset_type \
			and _watchdog_since_last_reset <= WATCHDOG_REPEAT_WINDOW:
		_watchdog_repeat_count += 1
	else:
		_watchdog_repeat_count = 1
	_watchdog_last_reset_type = broken_type
	_watchdog_since_last_reset = 0.0
	# First failure retries the still-valid world job immediately. A repeated
	# failure gets a tiny type-specific breathing window so another intention
	# can separate the NPC from the same bad geometry/traffic arrangement.
	if reason == "repeated_state_loop":
		_watchdog_loop_quarantines[broken_type] = WATCHDOG_LOOP_QUARANTINE
		_watchdog_quarantine_left = 0.0
	else:
		_watchdog_quarantine_left = WATCHDOG_REPEAT_QUARANTINE \
			if _watchdog_repeat_count >= 2 else 0.0
	_think_timer = 0.0
	_record_activity_event(&"activity_watchdog_reset", broken_label, "Idle", {
		"reason": reason, "elapsed_real_sec": elapsed,
	})
	_reset_watchdog_tracking()
	_clear_loop_history()
	return true


func _reset_watchdog_tracking() -> void:
	_watchdog_sample_elapsed = 0.0
	_watchdog_no_progress_elapsed = 0.0
	_watchdog_broken_route_elapsed = 0.0
	_watchdog_last_position = Vector3.INF
	_watchdog_last_remaining = INF
	_watchdog_last_token = ""
	_watchdog_activity_id = 0
	_watchdog_travel_intent = false


func _tick_loop_quarantines(real_delta: float) -> void:
	for activity_type: String in _watchdog_loop_quarantines.keys().duplicate():
		var left: float = float(_watchdog_loop_quarantines[activity_type]) - real_delta
		if left <= 0.0:
			_watchdog_loop_quarantines.erase(activity_type)
		else:
			_watchdog_loop_quarantines[activity_type] = left


func _loop_guard_enabled(activity: NPCActivity) -> bool:
	## Passive/open-ended states are intentionally excluded. Everything here
	## represents a bounded intention that should change world or need state.
	return activity is GardeningActivity or activity is JobActivity \
		or activity is CleaningActivity or activity is RefuelActivity \
		or activity is PutAwayHeldItemActivity or activity is CookingActivity \
		or activity is GiveToFriendActivity


func _loop_signature(activity: NPCActivity) -> String:
	var info: Dictionary = activity.debug_info()
	var parts: Array[String] = [activity.debug_type()]
	for key: String in WATCHDOG_LOOP_KEYS:
		if info.has(key):
			parts.append("%s=%s" % [key, str(info[key])])
	var attention: Node3D = activity.attention_target(_npc)
	if attention != null and is_instance_valid(attention):
		parts.append("attention_id=%d" % attention.get_instance_id())
	if _npc.held_item != null and is_instance_valid(_npc.held_item):
		parts.append("held_id=%d" % _npc.held_item.get_instance_id())
	return "|".join(parts)


func _record_watchdog_loop_state(activity: NPCActivity, nav: Dictionary,
		force: bool = false) -> bool:
	if activity == null or not _loop_guard_enabled(activity):
		return false
	var signature: String = _loop_signature(activity)
	if not force and signature == _watchdog_last_loop_signature:
		return false
	_watchdog_last_loop_signature = signature
	while not _watchdog_loop_history.is_empty() \
			and _watchdog_real_clock - float(_watchdog_loop_history[0].get("time", 0.0)) \
			> WATCHDOG_LOOP_WINDOW:
		_watchdog_loop_history.pop_front()
	_watchdog_loop_history.append({
		"signature": signature,
		"time": _watchdog_real_clock,
		"type": activity.debug_type(),
		"label": activity.label(),
		"info": activity.debug_info().duplicate(true),
	})
	while _watchdog_loop_history.size() > WATCHDOG_LOOP_HISTORY_CAPACITY:
		_watchdog_loop_history.pop_front()

	var history_size: int = _watchdog_loop_history.size()
	for pattern_size: int in range(1, WATCHDOG_LOOP_MAX_PATTERN + 1):
		var needed: int = pattern_size * WATCHDOG_LOOP_REPEATS
		if history_size < needed:
			continue
		var pattern_start: int = history_size - pattern_size
		var repeated: bool = true
		for repeat_index: int in range(1, WATCHDOG_LOOP_REPEATS):
			var compare_start: int = pattern_start - repeat_index * pattern_size
			for offset: int in range(pattern_size):
				if String(_watchdog_loop_history[compare_start + offset].get("signature", "")) \
						!= String(_watchdog_loop_history[pattern_start + offset].get("signature", "")):
					repeated = false
					break
			if not repeated:
				break
		if not repeated:
			continue
		var first_index: int = history_size - needed
		var elapsed: float = _watchdog_real_clock \
			- float(_watchdog_loop_history[first_index].get("time", _watchdog_real_clock))
		if elapsed > WATCHDOG_LOOP_WINDOW:
			continue
		_watchdog_loop_context = _watchdog_loop_history.slice(first_index, history_size)
		for row: Dictionary in _watchdog_loop_context:
			_watchdog_loop_quarantines[String(row.get("type", ""))] = WATCHDOG_LOOP_QUARANTINE
		return _recover_broken_activity("repeated_state_loop", elapsed, nav)
	return false


func _clear_loop_history() -> void:
	_watchdog_loop_history.clear()
	_watchdog_last_loop_signature = ""
	_watchdog_loop_context.clear()


func _capture_resume_intent() -> void:
	var intent: Dictionary = _current.make_resume_intent(_npc)
	if intent.is_empty():
		return
	intent["started_game_time"] = _behavior_clock_hours
	intent["expires_game_time"] = _behavior_clock_hours + RESUME_INTENT_LIFETIME_HOURS
	intent["resume_count"] = int(intent.get("resume_count", 0)) + 1
	_deferred_intent = intent


func _prune_deferred_intent() -> void:
	if _deferred_intent.is_empty():
		return
	if _behavior_clock_hours >= float(_deferred_intent.get("expires_game_time", -INF)) \
			or _npc.held_item != null:
		_deferred_intent.clear()


func _record_activity_event(kind: StringName, from_label: String, to_label: String,
		extra: Dictionary = {}) -> void:
	var data: Dictionary = extra.duplicate(true)
	data["from"] = from_label
	data["to"] = to_label
	NPC_METRICS.record_event(kind, _npc, data)


func _make_decision_receipt(outcome: String, reason: String, winner: NPCActivity,
		winner_score: float, current_score: float, margin: float,
		evaluations: Array[Dictionary]) -> Dictionary:
	var ranked: Array[Dictionary] = evaluations.duplicate(true)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	var top: Array[Dictionary] = []
	for index: int in range(mini(3, ranked.size())):
		top.append(ranked[index])
	return {
		"outcome": outcome,
		"reason": reason,
		"current_type": _current.debug_type() if _current != null else "Idle",
		"current_label": _current.label() if _current != null else "Idle",
		"current_score": current_score,
		"winner_type": winner.debug_type() if winner != null else "",
		"winner_label": winner.label() if winner != null else "",
		"winner_score": winner_score,
		"switch_margin": margin,
		"current_interruptible": _current.interruptible() if _current != null else true,
		"top_alternatives": top,
		"candidates": ranked,
		"needs": {
			"health": _npc.health, "energy": _npc.energy,
			"hunger": _npc.hunger, "thirst": _npc.thirst,
			"mood": _npc.mood, "irritability": _npc.irritability,
		},
		"activity_info": get_current_activity_debug_info(),
	}
