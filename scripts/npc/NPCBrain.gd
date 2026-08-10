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

# ═══════════════════════════════════════════════════════════════════════════
# Built-in activities (Part 2 set)
# ═══════════════════════════════════════════════════════════════════════════

class WanderActivity extends NPCActivity:
	var _idle_left: float = 0.0
	var _walking: bool = false

	func score(npc: NPC) -> float:
		return 5.0 * npc.get_work_ethic_passive_mult()   ## constant baseline — always available, loses to any need

	func label() -> String:
		return "Wandering"

	func enter(npc: NPC) -> void:
		_idle_left = randf_range(npc.idle_time_min, npc.idle_time_max)
		_walking = false

	func tick(npc: NPC, delta: float) -> void:
		if _walking:
			npc.nav_steer(delta)
			if npc.nav_finished():
				_walking = false
				_idle_left = randf_range(npc.idle_time_min, npc.idle_time_max)
		else:
			npc.halt_movement(delta)
			_idle_left -= delta
			if _idle_left <= 0.0:
				var world: Node = npc.get_tree().get_first_node_in_group("main_world")
				if world != null and world.has_method("get_random_cleared_cell_center"):
					npc.set_nav_target(world.get_random_cleared_cell_center())
					_walking = true

	func done(_npc: NPC) -> bool:
		return false   ## endless; only ends by interruption

	func exit(npc: NPC) -> void:
		npc.halt_movement(1.0)


class RelaxActivity extends NPCActivity:
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


class SitActivity extends NPCActivity:
	## Walk to the nearest free chair, sit, recover Energy, stand when rested.
	const SIT_UNTIL_ENERGY: float = 90.0
	const ENERGY_REGEN_PER_GAME_HOUR: float = 25.0

	var _chair: Node = null
	var _seated: bool = false

	func label() -> String:
		return "Resting" if _seated else "Finding a seat"

	func score(npc: NPC) -> float:
		if npc.energy >= 60.0:
			return 0.0
		if _find_free_chair(npc) == null:
			return 0.0
		return (100.0 - npc.energy) * npc.get_work_ethic_passive_mult()   ## 40..100 as energy falls 60→0

	func interruptible() -> bool:
		return not _seated   ## once seated, finish resting (Part 4 jobs can
		                     ## still out-wait it; nothing urgent exists yet)

	func enter(npc: NPC) -> void:
		_chair = _find_free_chair(npc)
		_seated = false
		if _chair == null:
			return
		npc.set_nav_target((_chair as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _chair == null or not is_instance_valid(_chair):
			_chair = null
			return
		if _seated:
			npc.energy = minf(100.0, npc.energy
				+ ENERGY_REGEN_PER_GAME_HOUR * npc.game_hours(delta))
			return
		npc.nav_steer(delta)
		var chair_pos: Vector3 = (_chair as Node3D).global_position
		var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
			.distance_to(Vector2(chair_pos.x, chair_pos.z))
		if npc.nav_finished() or flat_dist < 0.9:
			## Claim + snap onto the seat (mirrors the player seat flow in
			## MainWorld._wire_chair, minus the physics-process freeze —
			## the NPC just parks with zero velocity).
			if _chair.has_method("npc_try_sit") and _chair.npc_try_sit(npc):
				_seated = true
				var t: Transform3D = _chair.get_seat_transform()
				npc.global_position = t.origin
				npc.rotation.y = t.basis.get_euler().y
				npc.lock_movement()
			else:
				_chair = null   ## someone took it — done() ends us; rescore

	func done(npc: NPC) -> bool:
		if _chair == null:
			return true
		return _seated and npc.energy >= SIT_UNTIL_ENERGY

	func exit(npc: NPC) -> void:
		if _seated and _chair != null and is_instance_valid(_chair):
			if _chair.has_method("npc_stand"):
				_chair.npc_stand(npc)
			npc.global_position = _chair.get_stand_position()
		_seated = false
		_chair = null

	func _find_free_chair(npc: NPC) -> Node:
		var best: Node = null
		var best_d: float = INF
		for c: Node in npc.get_tree().get_nodes_in_group("chair"):
			if not is_instance_valid(c):
				continue
			if c.has_method("is_seat_free") and not c.is_seat_free():
				continue
			var c_pos: Vector3 = (c as Node3D).global_position
			var d: float = Vector2(c_pos.x, c_pos.z) \
				.distance_to(Vector2(npc.global_position.x, npc.global_position.z))
			if d < best_d:
				best_d = d
				best = c
		return best


class RelaxSitActivity extends SitActivity:
	## Relaxing in a chair (Aug 2026) — delegation-only, never auto-
	## selected. Unlike SitActivity, does NOT end just because energy
	## reached SIT_UNTIL_ENERGY — without this override, an NPC already
	## at/above that energy would sit down, have done()==true the instant
	## _seated flips, stand right back up, and loop with RelaxActivity
	## re-selecting the same chair every think-cycle. RelaxActivity's own
	## session-length timer is what ends this instead. Energy still
	## regenerates, just at 1/4 the normal rate — a break, not full rest.
	const RELAX_ENERGY_REGEN_MULT: float = 0.25

	func label() -> String:
		return "Relaxing (Sitting)" if _seated else "Finding a seat"

	func score(_npc: NPC) -> float:
		return 0.0   ## delegation-only

	func tick(npc: NPC, delta: float) -> void:
		if _chair == null or not is_instance_valid(_chair):
			_chair = null
			return
		if _seated:
			npc.energy = minf(100.0, npc.energy
				+ ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))
			return
		npc.nav_steer(delta)
		var chair_pos: Vector3 = (_chair as Node3D).global_position
		var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
			.distance_to(Vector2(chair_pos.x, chair_pos.z))
		if npc.nav_finished() or flat_dist < 0.9:
			if _chair.has_method("npc_try_sit") and _chair.npc_try_sit(npc):
				_seated = true
				var t: Transform3D = _chair.get_seat_transform()
				npc.global_position = t.origin
				npc.rotation.y = t.basis.get_euler().y
				npc.lock_movement()
			else:
				_chair = null   ## someone took it

	func done(npc: NPC) -> bool:
		return _chair == null   ## energy is NOT a completion condition here


class DrinkActivity extends NPCActivity:
	## Thirst-driven. Priority: Dispenser with water → loose Water Bottle.
	## FUTURE WORK: pulling a fresh bottle out of a WaterCase.
	##
	## Bottle handling (Part 12): grabs the bottle FIRST, holds it through
	## the full CONSUME_TIME wait, then drinks+drops — mirroring
	## EatActivity's order. The previous version grabbed and dropped inside
	## the same call at the END of the wait, with zero visible holding
	## duration — looked exactly like the bottle teleporting into the hand
	## and immediately falling, because that's functionally what happened.
	## Also claims its bottle target (NPCItemUser, Part 12) so two NPCs
	## can't converge on the same one.
	const DRINK_ML:        float = 375.0   ## == WaterBottle.STANDARD_DRINK_ML
	const HYDRATION:       float = 21.5    ## == WaterBottle.STANDARD_HYDRATION
	const CONSUME_TIME:    float = 2.0
	const USE_RANGE:       float = 1.4

	var _mode: String = ""        ## "dispenser" | "bottle"
	var _target: Node = null
	var _drinking: float = 0.0
	var _pending_snatch: Node = null   ## Part 30
	var _handoff: NPCActivity = null

	func label() -> String:
		return "Drinking" if _drinking > 0.0 else "Getting water"

	func score(npc: NPC) -> float:
		if npc.thirst >= 55.0:
			return 0.0
		if _pick_target(npc).is_empty() \
				and not npc.is_npc_snatch_eligible(Callable(NPCItemUser, "is_drinkable_bottle")):
			return 0.0
		return (100.0 - npc.thirst) * 1.2 * npc.get_work_ethic_passive_mult()   ## thirst outranks equal-level energy

	func _pick_target(npc: NPC) -> Dictionary:
		var best_d: float = INF
		var out: Dictionary = {}
		for d: Node in npc.get_tree().get_nodes_in_group("water_dispenser"):
			if not is_instance_valid(d) or d.current_fill_mL < DRINK_ML:
				continue
			var dist: float = NPCItemUser.flat_distance((d as Node3D).global_position, npc.global_position)
			if dist < best_d:
				best_d = dist
				out = {"mode": "dispenser", "node": d}
		var bottle: RigidBody3D = NPCItemUser.find_loose_item(npc,
			Callable(NPCItemUser, "is_drinkable_bottle"))
		if bottle != null:
			var dist_b: float = NPCItemUser.flat_distance(bottle.global_position, npc.global_position)
			if dist_b < best_d:
				out = {"mode": "bottle", "node": bottle}
		return out

	func enter(npc: NPC) -> void:
		_drinking = 0.0
		_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
		if _pending_snatch != null:
			return   ## handled on first tick() below
		var pick: Dictionary = _pick_target(npc)
		_mode = pick.get("mode", "")
		_target = pick.get("node", null)
		if _mode == "bottle" and _target != null:
			if not NPCItemUser.claim_item(_target, npc):
				_target = null   ## lost the race between scoring and entering
				return
		if _target != null:
			npc.set_nav_target((_target as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _pending_snatch != null:
			_handoff = NPCBrain.SnatchActivity.new(_pending_snatch, Callable(NPCItemUser, "is_drinkable_bottle"), false)
			_pending_snatch = null
			return
		if _target == null or not is_instance_valid(_target):
			_target = null
			return
		if _mode == "bottle":
			_tick_bottle(npc, delta)
		else:
			_tick_dispenser(npc, delta)

	func _tick_dispenser(npc: NPC, delta: float) -> void:
		if _drinking > 0.0:
			npc.halt_movement(delta)
			_drinking -= delta
			if _drinking <= 0.0:
				_finish_dispenser(npc)
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_target as Node3D).global_position) <= USE_RANGE:
			npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO, which Part 13's
			                     ## movement-lock never protected from a late avoidance callback
			_drinking = CONSUME_TIME

	func _finish_dispenser(npc: NPC) -> void:
		var d: Node = _target
		var ml: float = minf(DRINK_ML, d.current_fill_mL)
		if ml > 0.0:
			d.current_fill_mL -= ml                       ## REAL deduction
			if d.has_method("_update_fill_visual"):
				d._update_fill_visual()
			npc.thirst = minf(100.0, npc.thirst + HYDRATION * (ml / DRINK_ML))
		_reacquire_or_finish(npc)

	func _tick_bottle(npc: NPC, delta: float) -> void:
		if _drinking > 0.0:
			npc.halt_movement(delta)
			_drinking -= delta
			if _drinking <= 0.0:
				_finish_bottle(npc)
			return
		if npc.held_item == _target:
			## Grabbed — start the visible holding/drinking wait.
			npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO (see 3b note)
			_drinking = CONSUME_TIME
			return
		if "is_held" in _target and _target.is_held:
			NPCItemUser.release_item(_target)
			_target = null
			return
		npc.nav_steer(delta)
		## Part 16 — this was the exact bug from the water-bottle report: raw 3D
		## distance against PICKUP_RANGE(1.2), with a loose bottle's ~0.9 vertical
		## offset from the NPC's capsule-center origin eating most of that budget.
		if NPCItemUser.flat_distance(npc.global_position, (_target as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
			if not NPCItemUser.grab_loose(npc, _target):
				NPCItemUser.release_item(_target)
				_target = null   ## grab failed — give up cleanly, rescore next think

	func _finish_bottle(npc: NPC) -> void:
		var b: Node = _target
		if b != null and is_instance_valid(b) and npc.held_item == b:
			npc.thirst = minf(100.0, npc.thirst + b.take_drink())   ## REAL deduction
			NPCItemUser.release_item(b)
			NPCItemUser.drop_held(npc)
		_reacquire_or_finish(npc)

	## Part 17 — shared by both finish paths. This is the actual fix: one sip
	## (HYDRATION=21.5) essentially never satisfies thirst on its own, so
	## setting _target=null unconditionally here (the old behavior) made
	## done() end the activity after every single sip, forcing a full
	## restart-from-scratch for the next one. Now, if thirst is still low,
	## immediately look for a new target and keep going within this SAME
	## activity run — only truly finish when satisfied or nothing is left.
	func _reacquire_or_finish(npc: NPC) -> void:
		_target = null
		_mode = ""
		_pending_snatch = null
		if npc.thirst >= 90.0:
			return   ## satisfied — done() ends us next tick
		_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
		if _pending_snatch != null:
			return   ## picked up by tick() next frame
		var pick: Dictionary = _pick_target(npc)
		if pick.is_empty():
			return   ## nothing left to try — done() ends us (target stays null)
		_mode = pick.get("mode", "")
		_target = pick.get("node", null)
		if _mode == "bottle" and _target != null:
			if not NPCItemUser.claim_item(_target, npc):
				_target = null
				_mode = ""
				return
		if _target != null:
			npc.set_nav_target((_target as Node3D).global_position)

	func done(npc: NPC) -> bool:
		return (_target == null or npc.thirst >= 90.0) and _pending_snatch == null

	func interruptible() -> bool:
		return _drinking <= 0.0

	func take_handoff() -> NPCActivity:
		var h: NPCActivity = _handoff
		_handoff = null
		return h

	func exit(npc: NPC) -> void:
		if _target != null:
			NPCItemUser.release_item(_target)
		if npc.held_item != null:
			NPCItemUser.release_item(npc.held_item)
			NPCItemUser.drop_held(npc)
		_target = null
		_drinking = 0.0


class GivenDrinkActivity extends DrinkActivity:
	## Same reasoning as GivenEatActivity, but DrinkActivity's tick()
	## checks `_target` (not held_item) first — begin_with_item() has to
	## populate that explicitly.
	func score(_npc: NPC) -> float:
		return 0.0
	func enter(_npc: NPC) -> void:
		_drinking = 0.0
		_mode = ""
		_target = null
	func begin_with_item(_npc: NPC, item: Node) -> void:
		_mode = "bottle"
		_target = item


class TalkActivity extends NPCActivity:
	## NPC↔NPC Talking (Aug 2026). One reusable instance lives in
	## _candidates (constructed with defaults — partner=null,
	## is_initiator=true) for the normal scored/organic path; a SEPARATE
	## one-shot instance gets force_command()'d onto the partner side
	## (partner=initiator, is_initiator=false) via start_talk_session().
	## No travel phase — only ever matched between NPCs already within
	## TALK_RANGE, so both lock in place immediately. Non-interruptible
	## once a partner's actually locked in, same "commit once started"
	## reasoning as every other multi-step activity in this file.
	## FUTURE WORK: relationship-based random conversation OUTCOMES —
	## deliberately not built yet. This pass is groundwork only: both
	## NPCs occupied, facing each other, logged.
	const SESSION_MIN: float = 8.0    ## seconds, real-time — a quick social beat, not a game-hours-scale session like Relaxing
	const SESSION_MAX: float = 20.0

	var _partner: Node = null
	var _elapsed: float = 0.0
	var _duration: float = 0.0
	var _is_initiator: bool = true
	var _self_npc: NPC = null   ## interruptible() has no npc parameter in this codebase's activity interface — stored here at enter() so it can check this NPC's own needs

	func _init(partner: Node = null, is_initiator: bool = true) -> void:
		_partner = partner
		_is_initiator = is_initiator

	func label() -> String:
		return "Talking" if _partner != null else "Idle"

	func score(npc: NPC) -> float:
		if not _is_initiator:
			return 0.0
		if npc.has_method("is_talk_on_cooldown") and npc.is_talk_on_cooldown():
			return 0.0
		var partner: Node = npc.find_talk_partner()
		if partner == null:
			return 0.0
		var mult: float = npc.get_talk_score_mult(partner) if npc.has_method("get_talk_score_mult") else 1.0
		return NPC.TALK_BASE_SCORE * npc.get_work_ethic_passive_mult() * mult

	func interruptible() -> bool:
		if _partner == null:
			return true   ## brief instant before a partner locks in
		## Needs take priority over an ongoing conversation — same 55%
		## threshold Eat/DrinkActivity themselves auto-trigger on, so
		## "hungry enough to interrupt" means the same thing everywhere.
		if _self_npc != null and (float(_self_npc.hunger) < 55.0 or float(_self_npc.thirst) < 55.0):
			return true
		return false

	func enter(npc: NPC) -> void:
		_self_npc = npc
		if _is_initiator:
			_partner = npc.find_talk_partner()
			if _partner == null:
				return
			if not _partner.has_method("start_talk_session") or not _partner.start_talk_session(npc):
				_partner = null
				return
			_duration = randf_range(SESSION_MIN, SESSION_MAX)
			_elapsed = 0.0
		if _partner != null and is_instance_valid(_partner):
			npc.lock_movement()
			var target_pos: Vector3 = (_partner as Node3D).global_position
			target_pos.y = npc.global_position.y
			npc.look_at(target_pos, Vector3.UP)

	func tick(npc: NPC, delta: float) -> void:
		if _partner == null or not is_instance_valid(_partner):
			_partner = null
			return
		npc.halt_movement(delta)
		if not _is_initiator:
			return   ## partner just waits — end_talk_if_talking() (called via the initiator's own end-of-session) clears _partner externally
		_elapsed += delta
		if _elapsed >= _duration:
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session(true)
			npc.log_action("Talked to %s" % _partner.npc_name)
			if npc.has_method("apply_talk_relationship_swing") and ("npc_id" in _partner):
				npc.apply_talk_relationship_swing(_partner.npc_id, _partner.npc_name)
			_partner = null

	func done(npc: NPC) -> bool:
		return _partner == null

	func exit(npc: NPC) -> void:
		if _partner != null and is_instance_valid(_partner) and _is_initiator:
			## interrupted some other way (including a low-needs abort) —
			## don't leave the partner stuck waiting forever; natural=false
			## since this path only ever fires when the conversation did
			## NOT reach its normal duration-elapsed ending (that path
			## already nulls _partner before exit() runs, so this branch
			## is exclusively the "cut short" case).
			if _partner.has_method("end_talk_session"):
				_partner.end_talk_session(false)
		if _duration > 0.0 and npc.has_method("start_talk_cooldown"):
			npc.start_talk_cooldown()   ## covers both natural completion and any interrupt/abort path
		_partner = null


class SnatchActivity extends NPCActivity:
	## Relationship Snatch — player or another NPC (Aug 2026), target-
	## force_command(), never scored/auto-selected.
	##
	## Continuously re-aims at the target every tick while the item is
	## still in their hands — the previous version only set the nav
	## target once, at enter(), so it just walked to wherever the player
	## happened to be standing when the attempt started and never
	## adjusted if they moved.
	##
	## If the target drops the tracked item (still that same item, now
	## loose) rather than putting it away/using it/giving it away, this
	## switches to chasing the dropped item on the ground instead of
	## giving up.
	##
	## MAX_CHASE_TIME is a safety valve beyond what was asked —
	## without it, a victim who simply keeps walking away would leave
	## this NPC stuck chasing forever (interruptible() is false, so
	## nothing else could ever interrupt it either). Remove this if
	## indefinite pursuit is actually what you want.
	const MAX_CHASE_TIME: float = 20.0

	var _target: Node = null
	var _need_filter: Callable
	var _is_edible: bool = false
	var _handoff: NPCActivity = null
	var _outcome_label: String = "Hostile"
	var _tracked_item: Node = null
	var _chase_timer: float = 0.0

	func _init(target: Node, need_filter: Callable, is_edible: bool) -> void:
		_target = target
		_need_filter = need_filter
		_is_edible = is_edible

	func label() -> String:
		return _outcome_label

	func score(_npc: NPC) -> float:
		return 0.0

	func interruptible() -> bool:
		return false

	func enter(npc: NPC) -> void:
		NPCDebug.log_snatch(npc, "started",
			"targeting %s, relationship=%.1f" % [
				"player" if _target != null and _target.is_in_group("player") else (_target.npc_name if _target != null and ("npc_name" in _target) else "unknown"),
				npc.get_relationship("player" if _target != null and _target.is_in_group("player") else (_target.npc_id if _target != null and "npc_id" in _target else "player"))])
		if npc.has_method("start_hostile_log"):
			npc.start_hostile_log()
		_tracked_item = _target.get_held_item() if _target != null and _target.has_method("get_held_item") else null
		if _target != null and is_instance_valid(_target):
			npc.set_nav_target((_target as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		_chase_timer += delta
		if _target != null and is_instance_valid(_target):
			var target_id: String = "player" if _target.is_in_group("player") else _target.npc_id
			if npc.has_method("start_snatch_cooldown_against"):
				npc.start_snatch_cooldown_against(target_id)
			if npc.has_method("update_hostile_log"):
				npc.update_hostile_log()
			if not _target.is_in_group("player"):
				if npc.has_method("start_npc_snatch_pair_cooldown"):
					npc.start_npc_snatch_pair_cooldown(target_id)
				if _target.has_method("start_npc_snatch_pair_cooldown"):
					_target.start_npc_snatch_pair_cooldown(npc.npc_id)   ## bidirectional
		if _chase_timer > MAX_CHASE_TIME:
			NPCDebug.log_snatch(npc, "aborted", "gave up after %.0fs of pursuit" % MAX_CHASE_TIME)
			_target = null
			_tracked_item = null
			return

		## Still in the target's hands — chase them, re-aiming every
		## tick since they can move.
		if _target != null and is_instance_valid(_target):
			var held: Node = _target.get_held_item() if _target.has_method("get_held_item") else null
			if held != null and is_instance_valid(held) and _need_filter.call(held):
				_tracked_item = held
				npc.set_nav_target((_target as Node3D).global_position)
				npc.nav_steer(delta)
				if NPCItemUser.flat_distance(npc.global_position, (_target as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
					if NPCItemUser.snatch_from(npc, _target):
						NPCDebug.log_snatch(npc, "success", "grabbed item, handing off to consume")
						var target_desc: String = "the player" if _target.is_in_group("player") else _target.npc_name
						npc.log_action("Snatched an item from %s" % target_desc)
						_handoff = NPCBrain.GivenEatActivity.new() if _is_edible else NPCBrain.GivenDrinkActivity.new()
						_outcome_label = "Snatched!"
						_target = null
						_tracked_item = null
					## else: still out of range this frame — keep chasing, no abort
				return

		## Target no longer holding a matching item. If it's the SAME item
		## we were tracking and it's now loose nearby (dropped, not used/
		## stored/given away), chase it down on the ground instead of
		## giving up.
		## Only chase it if it's GENUINELY loose in the world
		## (collision_layer 1, set by an actual drop) — not just
		## "not is_held", which is also true for an item the target
		## swapped away to a different inventory slot (deactivate_item()
		## sets is_held=false too, but leaves it frozen/hidden in
		## storage, collision_layer 0). Without this distinction the NPC
		## would walk to the stored item's stale last position and grab
		## it straight out of the inventory slot array.
		if _tracked_item != null and is_instance_valid(_tracked_item) \
				and "is_held" in _tracked_item and not _tracked_item.is_held \
				and "collision_layer" in _tracked_item and _tracked_item.collision_layer == 1 \
				and _need_filter.call(_tracked_item):
			npc.set_nav_target((_tracked_item as Node3D).global_position)
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, (_tracked_item as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _tracked_item):
					NPCDebug.log_snatch(npc, "success", "picked up the dropped item, handing off to consume")
					_handoff = NPCBrain.GivenEatActivity.new() if _is_edible else NPCBrain.GivenDrinkActivity.new()
					_outcome_label = "Snatched!"
				else:
					NPCDebug.log_snatch(npc, "failed", "dropped item grab rejected at range")
				_tracked_item = null
				_target = null
			return

		NPCDebug.log_snatch(npc, "aborted", "item is gone — not held by the target, not sitting loose nearby")
		_tracked_item = null
		_target = null

	func take_handoff() -> NPCActivity:
		var h: NPCActivity = _handoff
		_handoff = null
		return h

	func done(npc: NPC) -> bool:
		return _target == null and _tracked_item == null and _handoff == null

	func exit(npc: NPC) -> void:
		if npc.has_method("end_hostile_log"):
			npc.end_hostile_log()
		_target = null
		_tracked_item = null
		_handoff = null


class GiveToFriendActivity extends NPCActivity:
	## NPC→NPC Give (Aug 2026). Fetch phase mirrors JobActivity's fetch
	## exactly (find/claim/grab a loose item); travel phase mirrors
	## SnatchActivity's continuous re-aim at a moving target; hand-off
	## reuses can_receive_item()/on_item_given() unchanged in spirit
	## (just told who the giver actually is). Interruptible throughout —
	## unlike Snatch, this is a low-stakes altruistic errand, fine to
	## abandon if something more pressing comes up.
	var _friend: Node = null
	var _loose: RigidBody3D = null

	func label() -> String:
		return "Bringing %s something" % _friend.npc_name if _friend != null and _loose == null and npc_holds_nothing() else "Getting an item for a friend"

	## Small helper avoiding a direct `npc` reference in label() (label()
	## has no npc param) — see note below if your NPCActivity base differs;
	## simplest fallback if this causes issues is just a flat "Helping a friend" label.
	func npc_holds_nothing() -> bool:
		return true

	func score(npc: NPC) -> float:
		if not npc.has_needy_friend():
			return 0.0
		return NPC.GIVE_TO_FRIEND_BASE_SCORE * npc.get_work_ethic_passive_mult()

	func interruptible() -> bool:
		return true

	func enter(npc: NPC) -> void:
		var result: Dictionary = npc.find_friend_to_help()
		if result.is_empty():
			return
		_friend = result.get("friend")
		_loose = result.get("item")
		if not NPCItemUser.claim_item(_loose, npc):
			_friend = null
			_loose = null
			return
		npc.set_nav_target(_loose.global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _friend == null or not is_instance_valid(_friend):
			_friend = null
			_loose = null
			return

		if npc.held_item == null:
			## Fetch phase
			if _loose == null or not is_instance_valid(_loose):
				_friend = null
				_loose = null
				return
			if "is_held" in _loose and _loose.is_held:
				NPCItemUser.release_item(_loose)
				_friend = null
				_loose = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _loose.global_position) <= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _loose):
					_loose = null   ## fetched — travel phase starts next tick
				else:
					NPCItemUser.release_item(_loose)
					_friend = null
					_loose = null
			return

		## Travel phase — friend may have moved, or no longer needs it
		if not (float(_friend.hunger) < 90.0 or float(_friend.thirst) < 90.0):
			_friend = null   ## already fed some other way — no longer needed
			return
		npc.set_nav_target((_friend as Node3D).global_position)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_friend as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
			if _friend.has_method("can_receive_item") and _friend.can_receive_item(npc.held_item, npc.npc_id):
				var item: Node = npc.held_item
				var friend_name: String = _friend.npc_name
				npc.held_item = null
				item.pickup((_friend as Node3D).hold_point)
				_friend.held_item = item
				_friend.on_item_given(item, npc.npc_id, npc.npc_name)
				npc.log_action("Gave %s to %s" % [item.get_display_name(), friend_name])
			_friend = null

	func done(npc: NPC) -> bool:
		return _friend == null and _loose == null and npc.held_item == null

	func exit(npc: NPC) -> void:
		if _loose != null:
			NPCItemUser.release_item(_loose)
			_loose = null
		if npc.held_item != null:
			## Interrupted mid-errand while actually carrying the item —
			## just let them keep it; they'll finish delivering (or eat it
			## themselves if truly needed) next time this activity re-enters,
			## since held_item persisting is harmless and re-searching from
			## scratch would waste a perfectly good fetched item.
			pass
		_friend = null


class CleaningActivity extends NPCActivity:
	## Cleaning (Aug 2026, sustained session). Trash disposal + shelf
	## organizing under one job, mirroring GiveToFriendActivity's
	## fetch→travel→deliver shape per item — but now loops through
	## multiple items for 20-40 real seconds (or until nothing's left to
	## clean) instead of stopping after one. Counts as a JOB for Work
	## Ethic AND the Job Priority system (get_work_ethic_job_mult() *
	## get_job_priority_weight()).
	##
	## forced_item (stuck-recovery path) is always exactly ONE grab, never
	## a full session — an emergency unstick, not a deliberate shift.
	const SESSION_MIN_SEC: float = 20.0
	const SESSION_MAX_SEC: float = 40.0

	var _item: RigidBody3D = null
	var _destination: Node = null
	var _is_trash: bool = false
	var _forced_item: RigidBody3D = null
	var _is_forced_session: bool = false
	var _session_elapsed: float = 0.0
	var _session_duration: float = 0.0
	var _finished: bool = false
	var _skipped_ids: Dictionary = {}         ## item instance_id -> true, this session — confirmed no destination, never retry
	var _no_storage_categories: Dictionary = {}   ## "light"/"heavy" -> true, this session — every viable destination for the category is gone/full/nonexistent

	func _init(forced_item: RigidBody3D = null) -> void:
		_forced_item = forced_item
		_is_forced_session = forced_item != null

	func label() -> String:
		if _item == null:
			return "Cleaning"
		return "Cleaning (carrying)" if _destination != null else "Cleaning (fetching)"

	func score(npc: NPC) -> float:
		if _is_forced_session:
			return 0.0
		if not npc.has_cleaning_target_available():
			return 0.0
		## Aug 2026 — escalating urgency: the more clutter sits around,
		## the more Cleaning outcompetes Wander/Relax/etc. See
		## NPC.CLUTTER_URGENCY_STEP's own comment for the derivation.
		var urgency_mult: float = 1.0 + float(JobBoard.get_total_clutter_count()) * NPC.CLUTTER_URGENCY_STEP
		return NPC.CLEANING_BASE_SCORE * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight("CLEANING") * urgency_mult

	func interruptible() -> bool:
		return _item == null   ## between items (or before the first), fine to interrupt; mid-carry, commit

	func enter(npc: NPC) -> void:
		_session_duration = randf_range(SESSION_MIN_SEC, SESSION_MAX_SEC)
		_session_elapsed = 0.0
		_finished = false
		_skipped_ids = {}
		_no_storage_categories = {}
		if NPCDebug.enabled and not _is_forced_session:
			NPCDebug.log_cleaning(npc, "session started", "target duration=%.0fs" % _session_duration)
		_pick_next_target(npc)

	## Called at session start and after each delivery (success or
	## failure) — this is what makes the NPC keep working through the
	## bunker's clutter instead of stopping after one item.
	##
	## Aug 2026 — destination-first. Previously this only set _item and
	## walked toward it; find_cleaning_destination() was checked AFTER
	## grab_loose() succeeded, in tick()'s fetch phase. That meant an
	## item with genuinely nowhere to go (e.g. a Test Crate with only an
	## End Table/Dresser in range, neither able to take it) got walked
	## to, picked up, and dropped again — then immediately re-selected as
	## "nearest" and repeated, every tick, for the entire session. Now:
	## for organizable (non-trash) items, confirm a destination exists
	## BEFORE claiming or moving toward it at all. If none exists for
	## this SPECIFIC item but the category (light/heavy) still has
	## SOME viable destination elsewhere, just try the next candidate. If
	## the category has NO viable destination anywhere, remember that
	## (_no_storage_categories) so every future item of that category is
	## skipped on sight for the rest of the session instead of being
	## retried. Trash is unchanged — it's a single flat group with its
	## own pre-existing "no receptacle" handling, worth revisiting
	## together once trash_receptacle actually exists.
	func _pick_next_target(npc: NPC) -> void:
		_destination = null
		if _is_forced_session:
			_item = _forced_item
			_forced_item = null
			if _item == null or not is_instance_valid(_item):
				_item = null
				_finished = true
				return
			_is_trash = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "forced grab", "%s (stuck-recovery, is_trash=%s)" % [
					_display_name(_item), _is_trash])
		else:
			while true:
				var result: Dictionary = npc.find_cleaning_target(_skipped_ids)
				if result.is_empty():
					_finished = true
					_item = null
					if NPCDebug.enabled:
						var reason: String = "nothing left to clean"
						if not _no_storage_categories.is_empty():
							reason = "nothing left to clean — no storage for: %s" % ", ".join(_no_storage_categories.keys())
						NPCDebug.log_cleaning(npc, "session ended", reason)
					return
				_item = result.get("item")
				_is_trash = result.get("is_trash", false)
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "target picked", "%s (%s) dist=%.1f" % [
						_display_name(_item), "trash" if _is_trash else "organizable",
						NPCItemUser.flat_distance(npc.global_position, (_item as Node3D).global_position)])
				if _is_trash:
					break   ## trash keeps its existing post-pickup handling — commit and go
				var category: String = npc._classify_organizable_item(_item)
				if npc.find_cleaning_destination(false, _item) != null:
					break   ## viable destination confirmed for THIS item — commit and go fetch it
				_skipped_ids[_item.get_instance_id()] = true
				if not npc.has_viable_destination_for_category(category):
					_no_storage_categories[category] = true
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "no storage for category", "%s (%s) — no viable destination exists anywhere; skipping all %s items this session" \
							% [_display_name(_item), category, category])
				elif NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "no destination (retrying)", "%s (%s) has nowhere to go right now — trying next item" \
						% [_display_name(_item), category])
				## loop again — try the next nearest candidate, never having walked to this one at all
		if not NPCItemUser.claim_item(_item, npc):
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "claim failed", "%s already claimed by another NPC — retrying next tick" % _display_name(_item))
			_item = null   ## momentary claim clash — try again next tick, don't end the session over it
			return
		if _item.has_method("set_nav_obstacle_enabled"):
			_item.set_nav_obstacle_enabled(false)
		npc.set_nav_target(_item.global_position)

	## Shared display-name helper so every log line above uses the same
	## fallback (get_display_name() when available, raw node name otherwise).
	static func _display_name(item: Node) -> String:
		if item == null:
			return "?"
		return item.get_display_name() if item.has_method("get_display_name") else str(item.name)

	func tick(npc: NPC, delta: float) -> void:
		if not _is_forced_session:
			_session_elapsed += delta
			if _session_elapsed >= _session_duration and _item == null:
				_finished = true
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "session ended", "time's up (%.0fs)" % _session_duration)
				return

		if _item == null or not is_instance_valid(_item):
			_item = null
			if not _finished:
				_pick_next_target(npc)
			return

		if npc.held_item == null:
			## Fetch phase
			if "is_held" in _item and _item.is_held:
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "target lost", "%s became held by someone else before pickup" % _display_name(_item))
				NPCItemUser.release_item(_item)
				_item = null
				return
			if _item.is_in_group("shelved"):
				## Became unavailable (someone shelved it, or a stale
				## reference pointed at something already stored) — give
				## up on THIS item immediately rather than walking the
				## full distance for nothing (grab_loose() would refuse
				## it anyway, per Part A above).
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "target lost", "%s became shelved before pickup" % _display_name(_item))
				NPCItemUser.release_item(_item)
				_item = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _item.global_position) <= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _item):
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "picked up", _display_name(_item))
					_destination = npc.find_cleaning_destination(_is_trash, _item)
					if _destination == null:
						if NPCDebug.enabled:
							NPCDebug.log_cleaning(npc, "no destination", "%s has nowhere to go (is_trash=%s) — setting back down" % [
								_display_name(_item), _is_trash])
						NPCItemUser.drop_held(npc)
						_item = null
						if _is_forced_session:
							_finished = true
					elif NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "destination chosen", "%s -> %s" % [_display_name(_item), _destination.name])
				else:
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "pickup failed", "grab_loose() refused %s" % _display_name(_item))
					NPCItemUser.release_item(_item)
					_item = null
			return

		## Travel phase
		if _destination == null or not is_instance_valid(_destination):
			_item = null
			return
		npc.set_nav_target((_destination as Node3D).global_position)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_destination as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
			var item_name: String = _item.get_display_name() if _item.has_method("get_display_name") else "an item"
			if _is_trash:
				if _destination.has_method("npc_deposit_trash"):
					_destination.npc_deposit_trash(npc, _item)
				npc.log_action("Threw away %s" % item_name)
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "delivered", "threw away %s at %s" % [item_name, _destination.name])
			else:
				if _destination.has_method("npc_try_place_item") and _destination.npc_try_place_item(npc, _item):
					npc.log_action("Put away %s" % item_name)
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "delivered", "stored %s in %s" % [item_name, _destination.name])
				else:
					## Placement failed (shelf filled between selection and
					## arrival) — item goes back on the ground and MUST be
					## released here, or it stays permanently claimed by
					## this NPC and invisible to every other NPC's cleaning
					## scans for the rest of the session.
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "delivery failed", "%s no longer had room for %s — dropping it" % [_destination.name, item_name])
					NPCItemUser.release_item(_item)
					NPCItemUser.drop_held(npc)
			_item = null
			if _is_forced_session:
				_finished = true   ## stuck-recovery grab is always exactly one item

	func done(npc: NPC) -> bool:
		return _finished and _item == null

	func exit(npc: NPC) -> void:
		if _item != null:
			if _item.has_method("set_nav_obstacle_enabled") and "is_held" in _item and not _item.is_held:
				_item.set_nav_obstacle_enabled(true)
			NPCItemUser.release_item(_item)
		_item = null

	## Aug 2026 — structured snapshot for NPCDebug.dump_cleaning_state().
	## "activity" key lets the dump filter to cleaning-only, since
	## RefuelActivity doesn't implement this and would otherwise show up
	## under the same generic getter.
	func debug_info() -> Dictionary:
		var phase: String = "idle"
		if _item != null:
			phase = "carrying" if _destination != null else "fetching"
		return {
			"activity": "cleaning",
			"item": _display_name(_item) if _item != null else "",
			"is_trash": _is_trash,
			"phase": phase,
			"destination": (_destination.name if _destination != null and is_instance_valid(_destination) else ""),
			"session_elapsed": _session_elapsed,
			"session_duration": _session_duration,
			"forced": _is_forced_session,
			"no_storage_categories": _no_storage_categories.keys(),
		}


class PutAwayHeldItemActivity extends NPCActivity:
	## Aug 2026 — safety net for a held item left over with nothing
	## actually using it. Concretely: _recover_from_stuck() can
	## stop_current() a CleaningActivity that's already mid-carry (e.g.
	## a second stuck event fires while still holding the item) —
	## CleaningActivity.exit() only releases the item's CLAIM, since a
	## claim release was always meant to mean "never picked it up," not
	## "was holding it and gave up." Without this, that item stays in
	## the NPC's hand through Wander/Relax/Sit/Lie/Talk indefinitely,
	## since none of those have any concept of held items.
	##
	## Deliberately a flat, modest score — comfortably above Wander/
	## Relax/Sit/Lie/Talk's own ranges plus the interrupt margin, but far
	## below any activity with a genuine, real hold on the item (Drink/
	## Eat/GiveToFriend/Cleaning/Refuel all score based on real urgency
	## while they're the ones holding something, and none of those are
	## ever _current at the same time this activity would be scored
	## against them anyway — this only ever competes against activities
	## that don't hold anything).
	const SCORE: float = 20.0

	var _item: RigidBody3D = null
	var _destination: Node = null
	var _settled: bool = false   ## delivered, dropped, or lost — done() flips true

	func label() -> String:
		return "Putting away %s" % (_item.get_display_name() if _item != null and _item.has_method("get_display_name") else "an item")

	func score(npc: NPC) -> float:
		return SCORE if npc.held_item != null else 0.0

	func interruptible() -> bool:
		return false   ## short and self-contained — always let it finish rather than get preempted mid-delivery

	func enter(npc: NPC) -> void:
		_item = npc.held_item
		_settled = false
		if _item == null or not is_instance_valid(_item):
			_settled = true
			return
		var is_trash: bool = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
		_destination = npc.find_cleaning_destination(is_trash, _item)
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "put away held item", "%s -> %s" % [
				(_item.get_display_name() if _item.has_method("get_display_name") else str(_item.name)),
				(_destination.name if _destination != null else "(no destination — dropping in place)")])
		if _destination == null:
			NPCItemUser.drop_held(npc)
			_settled = true
			return
		npc.set_nav_target((_destination as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _settled:
			return
		if _item == null or not is_instance_valid(_item) or npc.held_item != _item:
			_settled = true   ## lost it somehow (dropped elsewhere, freed) — nothing left to do
			return
		if _destination == null or not is_instance_valid(_destination):
			NPCItemUser.drop_held(npc)
			_settled = true
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_destination as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
			var is_trash: bool = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
			if is_trash and _destination.has_method("npc_deposit_trash"):
				_destination.npc_deposit_trash(npc, _item)
			elif not is_trash and _destination.has_method("npc_try_place_item") and _destination.npc_try_place_item(npc, _item):
				pass   ## stored successfully
			else:
				NPCItemUser.drop_held(npc)   ## destination filled/changed since the initial check — just set it down rather than loop
			_settled = true

	func done(_npc: NPC) -> bool:
		return _settled

	func exit(_npc: NPC) -> void:
		pass   ## nothing claimed via NPCItemUser — this only ever acts on what's already physically held, never a JobBoard/claim-tracked target


class RefuelActivity extends NPCActivity:
	## Refuel (Aug 2026, sustained session) — fetch ONE fuel can, then
	## visit every generator below 100% in turn, refueling each until
	## full (or the can runs dry) before moving to the next. Mirrors
	## CleaningActivity's fetch→travel→[loop] shape exactly — multi-
	## location work doesn't fit JobBoard's single-target claim system,
	## see JobBoard.gd's own header comment. Ends when the can empties or
	## no generator remains below 100%. Never revisits a generator
	## already topped off THIS session (_refueled_ids) — that's what
	## prevents an infinite loop once the first generator it fills is
	## still nearest again.
	const APPROACH_DISTANCE: float = 1.0
	const WORK_RANGE: float = 1.6

	var _can: RigidBody3D = null
	var _fetch_loose: RigidBody3D = null
	var _fetch_shelf: Dictionary = {}
	var _current_gen: Node = null
	var _refueled_ids: Dictionary = {}   ## generator instance_id -> true, this session only
	var _phase: String = "fetch"         ## fetch -> travel -> refuel
	var _finished: bool = false

	func label() -> String:
		match _phase:
			"fetch": return "Fetching fuel can"
			"travel": return "Heading to generator"
			_: return "Refueling"

	func score(npc: NPC) -> float:
		if not npc.has_refuel_target_available():
			return 0.0
		return NPC.REFUEL_BASE_SCORE * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight("REFUEL")

	func interruptible() -> bool:
		return _phase != "refuel"   ## mid-pour, commit; between generators/fetching, fine to interrupt

	func enter(npc: NPC) -> void:
		_refueled_ids = {}
		_finished = false
		if npc.held_item != null and npc.held_item.has_method("refuel_tick"):
			_can = npc.held_item
			_pick_next_generator(npc)
			return
		_phase = "fetch"
		_start_fetch(npc)

	func _start_fetch(npc: NPC) -> void:
		var filt: Callable = Callable(NPCItemUser, "is_spare_fuel_can")
		var loose: RigidBody3D = NPCItemUser.find_loose_item(npc, filt)
		var shelf_pick: Dictionary = {} if loose != null else NPCItemUser.find_shelved_item(npc, filt)
		var tgt: Node3D = loose if loose != null \
			else (shelf_pick.get("shelf") as Node3D if not shelf_pick.is_empty() else null)
		if tgt == null:
			_finished = true   ## no spare can anywhere — nothing to do
			return
		if loose != null:
			if not NPCItemUser.claim_item(loose, npc):
				_finished = true   ## momentary claim clash — try again next think-cycle
				return
			_fetch_loose = loose
		else:
			if not NPCItemUser.claim_item(shelf_pick.get("item"), npc):
				_finished = true
				return
			_fetch_shelf = shelf_pick
		npc.set_nav_target(tgt.global_position)

	func _tick_fetch(npc: NPC, delta: float) -> void:
		if npc.held_item != null:
			_can = npc.held_item
			_pick_next_generator(npc)
			return
		if _fetch_loose != null and is_instance_valid(_fetch_loose):
			if "is_held" in _fetch_loose and _fetch_loose.is_held:
				_fetch_loose = null
				_finished = true
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) <= NPCItemUser.PICKUP_RANGE:
				if not NPCItemUser.grab_loose(npc, _fetch_loose):
					_finished = true
			return
		if not _fetch_shelf.is_empty():
			var shelf: Node3D = _fetch_shelf.get("shelf")
			if shelf == null or not is_instance_valid(shelf):
				_finished = true
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) <= NPCItemUser.SHELF_RANGE:
				if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
					_finished = true
			return
		_finished = true   ## nothing left to fetch — spare can vanished between scan and now

	func _pick_next_generator(npc: NPC) -> void:
		_current_gen = npc.find_next_refuel_target(_refueled_ids)
		if _current_gen == null:
			_finished = true   ## every generator full — session complete
			return
		npc.set_nav_target(_approach_point(npc, _current_gen))
		_phase = "travel"

	func _approach_point(npc: NPC, target: Node) -> Vector3:
		var t3: Node3D = target as Node3D
		var to_npc: Vector3 = npc.global_position - t3.global_position
		to_npc.y = 0.0
		if to_npc.length() < 0.01:
			to_npc = Vector3(0.0, 0.0, 1.0)   ## degenerate case: npc exactly at center
		return t3.global_position + to_npc.normalized() * APPROACH_DISTANCE

	func tick(npc: NPC, delta: float) -> void:
		match _phase:
			"fetch":
				_tick_fetch(npc, delta)
			"travel":
				if _current_gen == null or not is_instance_valid(_current_gen):
					_pick_next_generator(npc)
					return
				npc.nav_steer(delta)
				var t_pos: Vector3 = (_current_gen as Node3D).global_position
				var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
					.distance_to(Vector2(t_pos.x, t_pos.z))
				if flat_dist <= WORK_RANGE:
					npc.velocity = Vector3.ZERO
					_phase = "refuel"
					npc.show_work_banner()
			"refuel":
				npc.halt_movement(delta)
				if _can == null or not is_instance_valid(_can) \
						or _current_gen == null or not is_instance_valid(_current_gen):
					npc.hide_work_banner()
					_pick_next_generator(npc)
					return
				var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
				if pm == null:
					_finished = true
					return
				var gid: String = str(_current_gen.get_instance_id())
				npc.update_work_banner("REFUELING", pm.get_generator_fuel(gid) / 100.0)
				_can.refuel_tick(delta)   ## REAL continuous pour, same mechanic as before
				var fuel_after: float = pm.get_generator_fuel(gid)
				var can_empty: bool = ("_fuel_remaining" in _can) and float(_can._fuel_remaining) <= 0.0
				if fuel_after >= 100.0 or can_empty:
					npc.hide_work_banner()
					_refueled_ids[_current_gen.get_instance_id()] = true
					NotificationManager.notify(UIKit.Domain.POWER, NotificationManager.Severity.INFO,
						"%s refueled the generator" % npc.npc_name)
					npc.log_action("Refueled a generator")
					npc.gain_skill("electrical")
					if can_empty:
						_finished = true   ## can is dry — session ends even if generators remain
					else:
						_pick_next_generator(npc)

	func done(_npc: NPC) -> bool:
		return _finished

	func exit(npc: NPC) -> void:
		npc.hide_work_banner()
		if _fetch_loose != null:
			NPCItemUser.release_item(_fetch_loose)
		if not _fetch_shelf.is_empty():
			NPCItemUser.release_item(_fetch_shelf.get("item"))
		if _finished and npc.held_item != null and npc.held_item == _can:
			NPCItemUser.drop_held(npc)   ## session truly over — set the (empty or spare) can down


class EatActivity extends NPCActivity:
	## Hunger-driven. Nearest edible: cooked Dish / produce / FoodCan-with-
	## bites, loose in the world OR on a shelf (via Shelving.npc_retrieve).
	const CONSUME_TIME: float = 2.0
	const USE_RANGE:    float = 1.2

	var _loose: RigidBody3D = null
	var _shelf_pick: Dictionary = {}
	var _eating: float = 0.0
	var _pending_snatch: Node = null   ## Part 30 — set in enter()/_reacquire_or_finish(), consumed on first tick()
	var _handoff: NPCActivity = null

	func label() -> String:
		return "Eating" if _eating > 0.0 else "Getting food"

	func score(npc: NPC) -> float:
		if npc.hunger >= 55.0:
			return 0.0
		if _find(npc) == null and _find_shelf(npc).is_empty() \
				and not npc.is_npc_snatch_eligible(Callable(NPCItemUser, "is_edible")):
			return 0.0
		return (100.0 - npc.hunger) * 1.15 * npc.get_work_ethic_passive_mult()

	func _find(npc: NPC) -> RigidBody3D:
		return NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_edible"))

	func _find_shelf(npc: NPC) -> Dictionary:
		return NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_edible"))

	func enter(npc: NPC) -> void:
		_eating = 0.0
		_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_edible"))
		if _pending_snatch != null:
			return   ## handled on first tick() below, via take_handoff()
		_loose = _find(npc)
		if _loose != null and not NPCItemUser.claim_item(_loose, npc):
			_loose = null   ## lost the race between scoring and entering
		_shelf_pick = {}
		if _loose == null:
			_shelf_pick = _find_shelf(npc)
			if not _shelf_pick.is_empty() and not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
				_shelf_pick = {}
		var tgt: Node3D = _loose if _loose != null \
			else (_shelf_pick.get("shelf") as Node3D if not _shelf_pick.is_empty() else null)
		if tgt != null:
			npc.set_nav_target(tgt.global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _pending_snatch != null:
			_handoff = NPCBrain.SnatchActivity.new(_pending_snatch, Callable(NPCItemUser, "is_edible"), true)
			_pending_snatch = null
			return
		if _eating > 0.0:
			npc.halt_movement(delta)
			_eating -= delta
			if _eating <= 0.0:
				if NPCItemUser.eat_held_step(npc):
					_reacquire_or_finish(npc)   ## Part 17 — see DrinkActivity for the same fix
				else:
					_eating = CONSUME_TIME   ## next bite of the same can
			return

		if npc.held_item != null:
			npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO (see DrinkActivity 3b note)
			_eating = CONSUME_TIME
			return

		if _loose != null and is_instance_valid(_loose):
			if "is_held" in _loose and _loose.is_held:
				NPCItemUser.release_item(_loose)
				_loose = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _loose.global_position) <= USE_RANGE:
				if NPCItemUser.grab_loose(npc, _loose):
					_loose = null
				else:
					NPCItemUser.release_item(_loose)
					_loose = null
			return
		_loose = null

		if not _shelf_pick.is_empty():
			var shelf: Node3D = _shelf_pick.get("shelf")
			if shelf == null or not is_instance_valid(shelf):
				_shelf_pick = {}
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) <= NPCItemUser.SHELF_RANGE:
				if NPCItemUser.grab_from_shelf(npc, shelf, int(_shelf_pick.get("slot", -1))):
					_shelf_pick = {}
				else:
					_shelf_pick = {}   ## slot emptied under us — rescore
			return

	func done(npc: NPC) -> bool:
		return _eating <= 0.0 and npc.held_item == null \
			and _loose == null and _shelf_pick.is_empty() and _pending_snatch == null

	## Part 17 — mirrors DrinkActivity's. Finishing one item (a full can, or
	## a single-bite item) no longer ends the activity outright if hunger is
	## still low — it looks for another item and continues within the same
	## run, only truly finishing once satisfied or nothing is left to eat.
	func _reacquire_or_finish(npc: NPC) -> void:
		_loose = null
		_shelf_pick = {}
		_pending_snatch = null
		if npc.hunger >= 55.0:
			return
		_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_edible"))
		if _pending_snatch != null:
			return   ## picked up by tick() next frame
		_loose = _find(npc)
		if _loose != null and not NPCItemUser.claim_item(_loose, npc):
			_loose = null
		if _loose == null:
			_shelf_pick = _find_shelf(npc)
			if not _shelf_pick.is_empty() and not NPCItemUser.claim_item(_shelf_pick.get("item"), npc):
				_shelf_pick = {}
		var tgt: Node3D = _loose if _loose != null \
			else (_shelf_pick.get("shelf") as Node3D if not _shelf_pick.is_empty() else null)
		if tgt != null:
			npc.set_nav_target(tgt.global_position)

	func interruptible() -> bool:
		return _eating <= 0.0

	func take_handoff() -> NPCActivity:
		var h: NPCActivity = _handoff
		_handoff = null
		return h

	func exit(npc: NPC) -> void:
		if _loose != null:
			NPCItemUser.release_item(_loose)
		if not _shelf_pick.is_empty():
			NPCItemUser.release_item(_shelf_pick.get("item"))
		if npc.held_item != null:
			NPCItemUser.release_item(npc.held_item)
			NPCItemUser.drop_held(npc)
		_loose = null
		_shelf_pick = {}
		_eating = 0.0


class GivenEatActivity extends EatActivity:
	## Player Give hand-off (Part 28). Reuses EatActivity's tick()/done()/
	## exit()/label()/interruptible()/_reacquire_or_finish() completely
	## unchanged — they already key off npc.held_item being set, which is
	## exactly what a gift (or a successful Snatch) produces. Only
	## enter()/score() differ: no search, no claim, never auto-selected.
	func score(_npc: NPC) -> float:
		return 0.0
	func enter(_npc: NPC) -> void:
		_eating = 0.0
	func begin_with_item(_npc: NPC, _item: Node) -> void:
		pass   ## tick() already reads held_item directly — nothing else needed


class JobActivity extends NPCActivity:
	## Executes one JobBoard job: [optional fetch item] → travel → work timer
	## with overhead banner → apply the SAME world effect a player action has.
	const WORK_RANGE: float = 1.6

	## Per-type work seconds and skill key.
	const TYPE_CONF: Dictionary = {
		"HARVEST":        {"time": 4.0, "skill": "farming",    "base": 55.0, "verb": "HARVESTING"},
		"REPLACE_FILTER": {"time": 5.0, "skill": "plumbing",   "base": 65.0, "verb": "FITTING FILTER"},
	}

	var _job: Dictionary
	var _phase: String = "fetch"   ## fetch → travel → work
	var _work_left: float = 0.0
	var _work_total: float = 1.0
	var _fetch_loose: RigidBody3D = null
	var _fetch_shelf: Dictionary = {}
	var _claimed: bool = false

	func _init(job: Dictionary) -> void:
		_job = job

	func label() -> String:
		match _phase:
			"fetch": return "Fetching supplies"
			"travel": return "Heading to work"
			_: return "Working"

	func score(npc: NPC) -> float:
		var conf: Dictionary = TYPE_CONF.get(_job.get("type", ""), {})
		if conf.is_empty():
			return 0.0
		var target: Node = _job.get("target")
		if target == null or not is_instance_valid(target):
			return 0.0
		var skill: float = float(npc.skills.get(conf["skill"], 1.0))
		var dist: float = NPCItemUser.flat_distance((target as Node3D).global_position, npc.global_position)
		var base_score: float = float(conf["base"]) * skill / (1.0 + dist * 0.08)
		## Irritability reduces willingness to work (Part 20) — distinct from
		## forgetfulness, which diverts AWAY from a job already chosen. This
		## instead makes an irritable NPC less likely to be picked as a job's
		## best candidate in the first place. Halves at max irritability (100%).
		## Not separately logged — it's a continuous scoring effect evaluated
		## every think-cycle for every open job, not a discrete event.
		var willingness: float = 1.0 - (npc.irritability / 100.0) * 0.5
		return base_score * willingness * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight(_job.get("type", ""))

	func interruptible() -> bool:
		return _phase != "work"

	func enter(npc: NPC) -> void:
		_claimed = JobBoard.claim(_job, npc)
		if not _claimed:
			return
		var conf: Dictionary = TYPE_CONF[_job["type"]]
		_work_total = float(conf["time"])
		_work_left = _work_total

		var needs_fetch: bool = _job.get("fetch_filter") != null
		if needs_fetch and npc.held_item == null:
			_phase = "fetch"
			var filt: Callable = _job["fetch_filter"]
			_fetch_loose = NPCItemUser.find_loose_item(npc, filt)
			_fetch_shelf = {} if _fetch_loose != null \
				else NPCItemUser.find_shelved_item(npc, filt)
			var tgt: Node3D = _fetch_loose if _fetch_loose != null \
				else (_fetch_shelf.get("shelf") as Node3D if not _fetch_shelf.is_empty() else null)
			if tgt == null:
				_claimed = false   ## spare vanished between scan and now
				JobBoard.release(_job, npc)
				return
			npc.set_nav_target(tgt.global_position)
		else:
			_start_travel(npc)

	const APPROACH_DISTANCE: float = 1.0   ## stand-off from the object's center —
	                                       ## clear of its own collision footprint
	                                       ## and therefore actually on the navmesh

	func _start_travel(npc: NPC) -> void:
		_phase = "travel"
		var target: Node3D = _job.get("target") as Node3D
		if target != null and is_instance_valid(target):
			npc.set_nav_target(_approach_point(npc, target))

	## A reachable point APPROACH_DISTANCE from the object's center, along the
	## line from wherever the NPC currently is — not a hardcoded "front," so
	## it adapts to whichever side the NPC is already approaching from. The
	## raw center (what this replaces) sits inside the object's own collision
	## footprint and off the navmesh entirely (Part 9's bake carves out every
	## static obstacle's interior), which is why targeting it directly made
	## the NPC walk into the object and get stuck fighting its collision.
	func _approach_point(npc: NPC, target: Node3D) -> Vector3:
		var to_npc: Vector3 = npc.global_position - target.global_position
		to_npc.y = 0.0
		if to_npc.length() < 0.01:
			to_npc = Vector3(0.0, 0.0, 1.0)   ## degenerate case: npc exactly at center
		return target.global_position + to_npc.normalized() * APPROACH_DISTANCE

	func tick(npc: NPC, delta: float) -> void:
		if not _claimed:
			return
		if not JobBoard.still_valid(_job):   ## player beat us to it
			_claimed = false
			return
		var target: Node3D = _job.get("target") as Node3D
		if target == null or not is_instance_valid(target):
			_claimed = false
			return

		match _phase:
			"fetch":
				_tick_fetch(npc, delta)
			"travel":
				npc.nav_steer(delta)
				## Flattened to XZ (Part 15) — target.global_position's Y can sit
				## anywhere depending on the object's own mesh pivot, and this
				## NPC's own origin is its capsule center (~1.4) — the same raw-
				## 3D-distance mismatch already fixed for SitActivity in Part 12.
				var t_pos: Vector3 = target.global_position
				var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
					.distance_to(Vector2(t_pos.x, t_pos.z))
				if flat_dist <= WORK_RANGE:
					npc.velocity = Vector3.ZERO
					_phase = "work"
					npc.show_work_banner()
			"work":
				npc.halt_movement(delta)
				_work_left -= delta
				var conf: Dictionary = TYPE_CONF[_job["type"]]
				npc.update_work_banner(String(conf["verb"]),
					1.0 - (_work_left / _work_total))
				if _work_left <= 0.0:
					_complete(npc)

	func _tick_fetch(npc: NPC, delta: float) -> void:
		if npc.held_item != null:
			_start_travel(npc)
			return
		if _fetch_loose != null and is_instance_valid(_fetch_loose):
			if "is_held" in _fetch_loose and _fetch_loose.is_held:
				_fetch_loose = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) \
					<= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _fetch_loose):
					_start_travel(npc)
				else:
					_fetch_loose = null
			return
		if not _fetch_shelf.is_empty():
			var shelf: Node3D = _fetch_shelf.get("shelf")
			if shelf == null or not is_instance_valid(shelf):
				_claimed = false
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) \
					<= NPCItemUser.SHELF_RANGE:
				if NPCItemUser.grab_from_shelf(npc, shelf,
						int(_fetch_shelf.get("slot", -1))):
					_start_travel(npc)
				else:
					_claimed = false
			return
		_claimed = false   ## nothing left to fetch

	func _complete(npc: NPC) -> void:
		var target: Node = _job.get("target")
		var conf: Dictionary = TYPE_CONF[_job["type"]]
		match _job["type"]:
			"HARVEST":
				## target IS the plant now (Part 31 — one job per plant,
				## not per tray).
				if target != null and is_instance_valid(target) and target.has_method("is_ready") and target.is_ready():
					target.harvest()   ## spawns real produce, clears cell
				NotificationManager.notify(UIKit.Domain.NEUTRAL,
					NotificationManager.Severity.INFO,
					"%s harvested the crops" % npc.npc_name)
				npc.log_action("Job (Harvest)")
			"REPLACE_FILTER":
				if npc.held_item is PurifierFilterItem:
					var filt: PurifierFilterItem = npc.held_item
					npc.held_item = null      ## replace_filter consumes/frees it
					target.replace_filter(filt)
					NotificationManager.notify(UIKit.Domain.WATER,
						NotificationManager.Severity.INFO,
						"%s replaced the purifier filter" % npc.npc_name)
		NPCDebug.log_job("completed", _job, npc)
		npc.gain_skill(String(conf["skill"]))
		_claimed = false

	func done(_npc: NPC) -> bool:
		return not _claimed

	func exit(npc: NPC) -> void:
		npc.hide_work_banner()
		JobBoard.release(_job, npc)
		if npc.held_item != null:
			NPCItemUser.drop_held(npc)
		_claimed = false


class LieActivity extends NPCActivity:
	## Walk to the nearest free bed, lie down (rotated horizontal via
	## Bed.get_lie_transform()), recover Energy faster and further than a
	## chair (proper rest vs a quick break), stand when fully rested.
	## Structurally mirrors SitActivity — see that class for the reasoning
	## behind the XZ-flattened arrival check (Part 12) and lock_movement()
	## at the transition instant (Part 13).
	const LIE_UNTIL_ENERGY: float = 100.0
	const ENERGY_REGEN_PER_GAME_HOUR: float = 45.0

	var _bed: Node = null
	var _lying: bool = false
	var _orig_rotation: Vector3 = Vector3.ZERO

	func label() -> String:
		return "Sleeping" if _lying else "Finding a bed"

	func score(npc: NPC) -> float:
		if npc.energy >= 60.0:
			return 0.0
		if _find_free_bed(npc) == null:
			return 0.0
		return (100.0 - npc.energy) * npc.get_work_ethic_passive_mult()
	func interruptible() -> bool:
		return not _lying

	func enter(npc: NPC) -> void:
		_bed = _find_free_bed(npc)
		_lying = false
		if _bed == null:
			return
		npc.set_nav_target((_bed as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		if _bed == null or not is_instance_valid(_bed):
			_bed = null
			return
		if _lying:
			npc.energy = minf(100.0, npc.energy
				+ ENERGY_REGEN_PER_GAME_HOUR * npc.game_hours(delta))
			return
		npc.nav_steer(delta)
		var bed_pos: Vector3 = (_bed as Node3D).global_position
		var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
			.distance_to(Vector2(bed_pos.x, bed_pos.z))
		if npc.nav_finished() or flat_dist < 1.1:
			if _bed.has_method("npc_try_lie") and _bed.npc_try_lie(npc):
				_lying = true
				_orig_rotation = npc.rotation
				npc.lock_movement()
				var t: Transform3D = _bed.get_lie_transform()
				npc.global_position = t.origin
				npc.rotation = t.basis.get_euler()
			else:
				_bed = null   ## someone took it — done() ends us; rescore

	func done(npc: NPC) -> bool:
		if _bed == null:
			return true
		return _lying and npc.energy >= LIE_UNTIL_ENERGY

	func exit(npc: NPC) -> void:
		if _lying and _bed != null and is_instance_valid(_bed):
			if _bed.has_method("npc_stand"):
				_bed.npc_stand(npc)
			npc.global_position = _bed.get_bed_stand_position()
			npc.rotation = _orig_rotation   ## restore upright orientation
		_lying = false
		_bed = null

	func _find_free_bed(npc: NPC) -> Node:
		var best: Node = null
		var best_d: float = INF
		for b: Node in npc.get_tree().get_nodes_in_group("bed"):
			if not is_instance_valid(b):
				continue
			if b.has_method("is_bed_free") and not b.is_bed_free():
				continue
			var b_pos: Vector3 = (b as Node3D).global_position
			var d: float = Vector2(b_pos.x, b_pos.z) \
				.distance_to(Vector2(npc.global_position.x, npc.global_position.z))
			if d < best_d:
				best_d = d
				best = b
		return best


class RelaxLieActivity extends LieActivity:
	## Relaxing in bed (Aug 2026) — same reasoning as RelaxSitActivity,
	## mirrored for beds.
	const RELAX_ENERGY_REGEN_MULT: float = 0.25

	func label() -> String:
		return "Relaxing (Lying down)" if _lying else "Finding a bed"

	func score(_npc: NPC) -> float:
		return 0.0   ## delegation-only

	func tick(npc: NPC, delta: float) -> void:
		if _bed == null or not is_instance_valid(_bed):
			_bed = null
			return
		if _lying:
			npc.energy = minf(100.0, npc.energy
				+ ENERGY_REGEN_PER_GAME_HOUR * RELAX_ENERGY_REGEN_MULT * npc.game_hours(delta))
			return
		npc.nav_steer(delta)
		var bed_pos: Vector3 = (_bed as Node3D).global_position
		var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
			.distance_to(Vector2(bed_pos.x, bed_pos.z))
		if npc.nav_finished() or flat_dist < 1.1:
			if _bed.has_method("npc_try_lie") and _bed.npc_try_lie(npc):
				_lying = true
				_orig_rotation = npc.rotation
				npc.lock_movement()
				var t: Transform3D = _bed.get_lie_transform()
				npc.global_position = t.origin
				npc.rotation = t.basis.get_euler()
			else:
				_bed = null   ## someone took it

	func done(npc: NPC) -> bool:
		return _bed == null   ## energy is NOT a completion condition here


class PassedOutActivity extends NPCActivity:
	## Forced collapse at 0 Energy (Part 14). Never chosen via normal scoring
	## — NPCBrain.tick() force-starts this directly, bypassing _think()
	## entirely, since it must preempt anything mid-activity. Regenerates
	## Energy slowly while "lying there," slower than a bed OR a chair —
	## passing out is a bad outcome, not a rest strategy. Only ends once
	## Energy is completely full again, per spec.
	##
	## FUTURE WORK: this only rotates the NPC in place as a first-pass
	## "collapsed" visual (mirrors the lie-flat trick LieActivity uses on a
	## bed) — it doesn't yet drop them to a true floor-lying Y position or
	## play any real collapse animation. Revisit once there's a proper
	## reference for what that should look like.
	const REGEN_PER_GAME_HOUR: float = 15.0   ## slower than SitActivity (25) and LieActivity (45) on purpose
	## Wakes at 15, not full — deliberately leaves them still needing real
	## rest afterward. Also the intended hook for a future "administer an
	## energy item to wake them faster" player action: something reaching
	## into this state and pushing energy toward 15 should end this the
	## same way natural regen does, no separate code path needed.
	const WAKE_ENERGY: float = 15.0

	var _orig_rotation: Vector3 = Vector3.ZERO

	func label() -> String:
		return "Passed Out"

	func score(_npc: NPC) -> float:
		return 0.0   ## never selected via normal scoring — force-started only

	func interruptible() -> bool:
		return false

	func enter(npc: NPC) -> void:
		_orig_rotation = npc.rotation
		npc.lock_movement()
		npc.rotation = Vector3(_orig_rotation.x, _orig_rotation.y,
			_orig_rotation.z + deg_to_rad(90.0))
		## Mood hit on collapse — lower bound fixed at 1%, upper bound is
		## 10% scaled by Neuroticism (baseline 10%, Neurotic 15%,
		## Easygoing 5%). One-time, applied here at the moment of
		## collapse, not repeated per-tick while passed out.
		var mood_drop: float = randf_range(1.0, 10.0 * npc.neuroticism_trait_mult())
		npc.mood = clampf(npc.mood - mood_drop, 0.0, 100.0)
		if NPCDebug.enabled:
			NPCDebug.log_mood_event(npc, -mood_drop, "passed out")
		npc.log_action("Passed out (0 energy)")

	func tick(npc: NPC, delta: float) -> void:
		npc.energy = minf(100.0, npc.energy + REGEN_PER_GAME_HOUR * npc.game_hours(delta))

	func done(npc: NPC) -> bool:
		return npc.energy >= WAKE_ENERGY

	func exit(npc: NPC) -> void:
		npc.log_action("Woke up")
		npc.rotation = _orig_rotation


class ForgetfulWanderActivity extends NPCActivity:
	## 20 seconds of ordinary wandering, forced in place of a job the brain
	## was about to start (Part 14's forgetfulness roll). Non-interruptible
	## for its full duration so the SAME job (or a new one) can't just steal
	## it right back on the next think-tick — it has to actually run its
	## course, matching "opt to wander... as opposed to working a job."
	## Delegates the actual walking behavior to a plain WanderActivity
	## instance rather than duplicating it.
	const FORGET_DURATION: float = 20.0

	var _timer: float = 0.0
	var _inner: NPCActivity = null

	func label() -> String:
		return "Wandering (forgot what they were doing)"

	func score(_npc: NPC) -> float:
		return 0.0   ## never selected via normal scoring — force-started only

	func interruptible() -> bool:
		return false

	func enter(npc: NPC) -> void:
		_timer = FORGET_DURATION
		_inner = WanderActivity.new()
		_inner.enter(npc)

	func tick(npc: NPC, delta: float) -> void:
		_timer -= delta
		_inner.tick(npc, delta)

	func done(_npc: NPC) -> bool:
		return _timer <= 0.0

	func exit(npc: NPC) -> void:
		_inner.exit(npc)


class CommandRestActivity extends NPCActivity:
	## "Take a load off" player command (Part 19). Tries a bed first
	## (better rest, per LieActivity), falls back to a chair (SitActivity)
	## if no bed is free/reachable. Delegates entirely to whichever inner
	## activity is chosen, so arrival/occupancy/energy-regen behavior is
	## identical to the needs-driven versions — this only decides which one
	## to try, and does so regardless of current Energy (a player command
	## should work even if Energy is high, unlike the automatic versions
	## which only compete for selection below 60).
	var _inner: NPCActivity = null

	func label() -> String:
		return _inner.label() if _inner != null else "Resting"

	func score(_npc: NPC) -> float:
		return 0.0   ## never selected via normal scoring — command-only

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		_inner = LieActivity.new()
		_inner.enter(npc)
		if _inner.done(npc):   ## no bed available/reachable — fall back to a chair
			_inner.exit(npc)
			_inner = SitActivity.new()
			_inner.enter(npc)

	func tick(npc: NPC, delta: float) -> void:
		if _inner != null:
			_inner.tick(npc, delta)

	func done(npc: NPC) -> bool:
		return _inner == null or _inner.done(npc)

	func exit(npc: NPC) -> void:
		if _inner != null:
			_inner.exit(npc)
		_inner = null


class CommandHarvestActivity extends NPCActivity:
	## "Harvest the plants" player command (Part 19). Finds the nearest
	## open HARVEST job (bypassing the brain's normal skill/distance-scored
	## competition among NPCs) and forces it via the SAME JobActivity the
	## automatic system uses — real produce, real progress banner, real
	## claim. If nothing is ready, done() is immediately true and does
	## nothing further; NPCTalkMenuUI shows a toast either way.
	var _inner: NPCActivity = null

	func label() -> String:
		return _inner.label() if _inner != null else "Idle"

	func score(_npc: NPC) -> float:
		return 0.0   ## never selected via normal scoring — command-only

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		for job: Dictionary in JobBoard.get_open_jobs():
			if job.get("type", "") == "HARVEST":
				_inner = JobActivity.new(job)
				_inner.enter(npc)
				return
		_inner = null   ## nothing ready to harvest

	func tick(npc: NPC, delta: float) -> void:
		if _inner != null:
			_inner.tick(npc, delta)

	func done(npc: NPC) -> bool:
		return _inner == null or _inner.done(npc)

	func exit(npc: NPC) -> void:
		if _inner != null:
			_inner.exit(npc)
		_inner = null


class CommandJobActivity extends NPCActivity:
	## Generalized "can you complete this job?" command (Aug 2026) —
	## CommandHarvestActivity's exact pattern, parameterized by job type,
	## so adding a new JobBoard-routed job type later needs no new class
	## here, just a new entry in NPCTalkMenuUI's job menu list.
	var _job_type: String = ""
	var _inner: NPCActivity = null

	func _init(job_type: String) -> void:
		_job_type = job_type

	func label() -> String:
		return _inner.label() if _inner != null else "Idle"

	func score(_npc: NPC) -> float:
		return 0.0   ## command-only, never auto-selected

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		for job: Dictionary in JobBoard.get_open_jobs():
			if job.get("type", "") == _job_type:
				_inner = JobActivity.new(job)
				_inner.enter(npc)
				return
		_inner = null

	func tick(npc: NPC, delta: float) -> void:
		if _inner != null:
			_inner.tick(npc, delta)

	func done(npc: NPC) -> bool:
		return _inner == null or _inner.done(npc)

	func exit(npc: NPC) -> void:
		if _inner != null:
			_inner.exit(npc)
		_inner = null


class CommandCleaningActivity extends NPCActivity:
	## "Can you complete this job?" → Clean the bunker (Aug 2026).
	## Delegates straight to a normal (organic-mode) CleaningActivity —
	## its own enter() already does the full find_cleaning_target() +
	## claim search; done() right after enter() tells us whether anything
	## was actually found.
	var _inner: NPCActivity = null

	func label() -> String:
		return _inner.label() if _inner != null else "Idle"

	func score(_npc: NPC) -> float:
		return 0.0

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		_inner = CleaningActivity.new()
		_inner.enter(npc)
		if _inner.done(npc):
			_inner = null

	func tick(npc: NPC, delta: float) -> void:
		if _inner != null:
			_inner.tick(npc, delta)

	func done(npc: NPC) -> bool:
		return _inner == null or _inner.done(npc)

	func exit(npc: NPC) -> void:
		if _inner != null:
			_inner.exit(npc)
		_inner = null


class CommandRefuelActivity extends NPCActivity:
	## "Can you complete this job?" → Refuel the generators (Aug 2026).
	## Delegates straight to a normal (organic-mode) RefuelActivity — its
	## own enter() already does the full fetch/target search; done()
	## right after enter() tells us whether anything was actually found.
	var _inner: NPCActivity = null

	func label() -> String:
		return _inner.label() if _inner != null else "Idle"

	func score(_npc: NPC) -> float:
		return 0.0

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		_inner = RefuelActivity.new()
		_inner.enter(npc)
		if _inner.done(npc):
			_inner = null

	func tick(npc: NPC, delta: float) -> void:
		if _inner != null:
			_inner.tick(npc, delta)

	func done(npc: NPC) -> bool:
		return _inner == null or _inner.done(npc)

	func exit(npc: NPC) -> void:
		if _inner != null:
			_inner.exit(npc)
		_inner = null