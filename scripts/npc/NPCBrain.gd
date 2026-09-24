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
var _npc: NPC = null
var _think_timer: float = 0.0
var _current: NPCActivity = null
var _navigation_recovery: NPCClearPathActivity = null
var _candidates: Array[NPCActivity] = []
var _deferred_intent: Dictionary = {}
var _behavior_clock_hours: float = 0.0
var _player_interaction_active: bool = false
var _player_interaction_resume_grace: float = 0.0
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

## Aug 2026 — structured debug snapshot of whatever the NPC is currently
## doing, for NPCDebug.dump_cleaning_state(). Empty Dictionary if idle or
## the current activity doesn't implement debug_info().
func get_current_activity_debug_info() -> Dictionary:
	if _navigation_recovery != null:
		var recovery_info: Dictionary = _navigation_recovery.debug_info()
		recovery_info["paused_activity"] = _current.label() if _current != null else "Idle"
		return recovery_info
	var info: Dictionary = _current.debug_info() if _current != null else {}
	if not _deferred_intent.is_empty():
		info["deferred_intent"] = _deferred_intent.duplicate(true)
	return info

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
	var previous_label: String = _current.label() if _current != null else "Idle"
	if _current != null:
		NPCDebug.log_activity(_npc, _current.label(), "Commanded: " + activity.label())
		_current.exit(_npc)
		_npc.cancel_navigation()
	_prepare_companionship_for(activity)
	_current = activity
	_current.enter(_npc)
	NPC_METRICS.increment(&"activity_forced_commands")
	_record_activity_event(&"activity_forced", previous_label, _current.label())
	_think_timer = THINK_INTERVAL   ## don't immediately re-think and override the command

## Called by NPC._physics_process every frame.
func tick(delta: float) -> void:
	_behavior_clock_hours += _npc.game_hours(delta)
	## Pass-out (Part 14) preempts everything, checked every frame — an
	## empty energy bar collapses the NPC immediately, not on the next
	## think-cycle, and can't be interrupted by anything else.
	if _npc.is_passed_out() and _player_interaction_active:
		_player_interaction_active = false
		_npc.call_deferred("close_talk_menu_for_critical_state")
	if _npc.is_passed_out() and not (_current is PassedOutActivity):
		_stop_navigation_recovery()
		if _current != null:
			NPCDebug.log_activity(_npc, _current.label(), "Passed Out")
			_current.exit(_npc)
			_npc.cancel_navigation()
		_current = PassedOutActivity.new()
		_prepare_companionship_for(_current)
		_current.enter(_npc)

	if _player_interaction_active:
		_npc.lock_movement()
		var player: Node3D = _npc.get_tree().get_first_node_in_group("player") as Node3D
		if player != null:
			_npc.face_world_position(player.global_position)
		return

	if _navigation_recovery != null:
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
			return

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
			var handoff_from: String = _current.label()
			_current.exit(_npc)
			_npc.cancel_navigation()
			_prepare_companionship_for(handoff)
			_current = handoff
			_current.enter(_npc)
			_current.begin_with_item(_npc, _npc.held_item)   ## no-op unless the successor implements it
			NPC_METRICS.increment(&"activity_handoffs")
			_record_activity_event(&"activity_handoff", handoff_from, _current.label())
			_think_timer = THINK_INTERVAL   ## same reasoning as force_command() — don't immediately override this
		elif _current.done(_npc):
			var completed_label: String = _current.label()
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
		return
	NPC_METRICS.increment(&"utility_think_cycles")
	_prune_deferred_intent()
	var best: NPCActivity = null
	var best_score: float = 0.0

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
		var s: float = cand.score(_npc)
		if s > best_score:
			best_score = s
			best = cand
	NPC_METRICS.observe(&"utility_candidate_count", float(scan.size()), [5.0, 10.0, 15.0, 20.0, 30.0])
	NPC_METRICS.observe(&"utility_best_score", best_score, [0.0, 5.0, 10.0, 20.0, 40.0, 60.0, 80.0, 100.0])

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
		if best.is_resume_candidate():
			_deferred_intent.clear()
		_start(best)
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
		_capture_resume_intent()
		_current.exit(_npc)
		_npc.cancel_navigation()
		_start(best)
		NPC_METRICS.increment(&"activity_interruptions")
		NPC_METRICS.observe(&"utility_interrupt_score_advantage", best_score - current_score,
			[0.0, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0])
		_record_activity_event(&"activity_interrupted", interrupted_label, best.label(), {
			"current_score": current_score, "challenger_score": best_score, "margin": margin,
		})
	elif not _current.interruptible():
		NPC_METRICS.increment(&"utility_rejected_not_interruptible")
	elif best_score <= current_score + margin:
		NPC_METRICS.increment(&"utility_rejected_switch_margin")


func _has_critical_need() -> bool:
	return _npc != null and (_npc.hunger < CRITICAL_NEED_THRESHOLD \
		or _npc.thirst < CRITICAL_NEED_THRESHOLD or _npc.energy <= 0.0)

func _start(activity: NPCActivity) -> void:
	_prepare_companionship_for(activity)
	_current = activity
	_current.enter(_npc)
	NPC_METRICS.increment(&"activity_started")
	_record_activity_event(&"activity_started", "Idle", _current.label())

## Force-stop whatever is running (used by save/load in Part 6 and by
## external interrupts later). Safe to call any time.
func stop_current() -> void:
	_stop_navigation_recovery()
	if _current != null:
		_current.exit(_npc)
		_npc.cancel_navigation()
		_current = null
	_deferred_intent.clear()


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
