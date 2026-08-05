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
	]

func current_label() -> String:
	return _current.label() if _current != null else "Idle"

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
				and not npc.is_player_snatch_eligible(Callable(NPCItemUser, "is_drinkable_bottle")):
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
		_pending_snatch = npc.find_player_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
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
		_pending_snatch = npc.find_player_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
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


class SnatchActivity extends NPCActivity:
	## Player Relationship Snatch. Dedicated, non-interruptible activity,
	## entered via force_command(), never scored/auto-selected.
	##
	## Continuously re-aims at the player every tick while the item is
	## still in their hands — the previous version only set the nav
	## target once, at enter(), so it just walked to wherever the player
	## happened to be standing when the attempt started and never
	## adjusted if they moved.
	##
	## If the player drops the tracked item (still that same item, now
	## loose) rather than putting it away/using it/giving it away, this
	## switches to chasing the dropped item on the ground instead of
	## giving up.
	##
	## MAX_CHASE_TIME is a safety valve I added beyond what was asked —
	## without it, a player who simply keeps walking away would leave
	## this NPC stuck chasing forever (interruptible() is false, so
	## nothing else could ever interrupt it either). Remove this if
	## indefinite pursuit is actually what you want.
	const MAX_CHASE_TIME: float = 20.0

	var _player: Node = null
	var _need_filter: Callable
	var _is_edible: bool = false
	var _handoff: NPCActivity = null
	var _outcome_label: String = "Hostile"
	var _tracked_item: Node = null
	var _chase_timer: float = 0.0

	func _init(player: Node, need_filter: Callable, is_edible: bool) -> void:
		_player = player
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
			"targeting player, relationship=%.1f" % npc.get_relationship("player"))
		_tracked_item = _player.get_held_item() if _player != null and _player.has_method("get_held_item") else null
		if _player != null and is_instance_valid(_player):
			npc.set_nav_target((_player as Node3D).global_position)

	func tick(npc: NPC, delta: float) -> void:
		_chase_timer += delta
		if _chase_timer > MAX_CHASE_TIME:
			NPCDebug.log_snatch(npc, "aborted", "gave up after %.0fs of pursuit" % MAX_CHASE_TIME)
			_player = null
			_tracked_item = null
			return

		## Still in the player's hands — chase the player, re-aiming every
		## tick since they can move.
		if _player != null and is_instance_valid(_player):
			var held: Node = _player.get_held_item() if _player.has_method("get_held_item") else null
			if held != null and is_instance_valid(held) and _need_filter.call(held):
				_tracked_item = held
				npc.set_nav_target((_player as Node3D).global_position)
				npc.nav_steer(delta)
				if NPCItemUser.flat_distance(npc.global_position, (_player as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
					if NPCItemUser.snatch_from_player(npc, _player):
						NPCDebug.log_snatch(npc, "success", "grabbed item from player's hands, handing off to consume")
						_handoff = NPCBrain.GivenEatActivity.new() if _is_edible else NPCBrain.GivenDrinkActivity.new()
						_outcome_label = "Snatched!"
						_player = null
						_tracked_item = null
					## else: still out of range this frame — keep chasing, no abort
				return

		## Player no longer holding a matching item. If it's the SAME item
		## we were tracking and it's now loose nearby (dropped, not used/
		## stored/given away), chase it down on the ground instead of
		## giving up.
		## Only chase it if it's GENUINELY loose in the world
		## (collision_layer 1, set by an actual drop) — not just
		## "not is_held", which is also true for an item the player
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
				_player = null
			return

		NPCDebug.log_snatch(npc, "aborted", "item is gone — not held by the player, not sitting loose nearby")
		_tracked_item = null
		_player = null

	func take_handoff() -> NPCActivity:
		var h: NPCActivity = _handoff
		_handoff = null
		return h

	func done(npc: NPC) -> bool:
		return _player == null and _tracked_item == null and _handoff == null

	func exit(_npc: NPC) -> void:
		_player = null
		_tracked_item = null
		_handoff = null


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
				and not npc.is_player_snatch_eligible(Callable(NPCItemUser, "is_edible")):
			return 0.0
		return (100.0 - npc.hunger) * 1.15 * npc.get_work_ethic_passive_mult()

	func _find(npc: NPC) -> RigidBody3D:
		return NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_edible"))

	func _find_shelf(npc: NPC) -> Dictionary:
		return NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_edible"))

	func enter(npc: NPC) -> void:
		_eating = 0.0
		_pending_snatch = npc.find_player_snatch_target(Callable(NPCItemUser, "is_edible"))
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
		_pending_snatch = npc.find_player_snatch_target(Callable(NPCItemUser, "is_edible"))
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
		"REFUEL":         {"time": 6.0, "skill": "electrical", "base": 60.0, "verb": "REFUELING"},
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
		return base_score * willingness * npc.get_work_ethic_job_mult()

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
				## FuelCan.gd declares no class_name — duck-type via has_method.
				if _job["type"] == "REFUEL" and npc.held_item != null \
						and npc.held_item.has_method("refuel_tick"):
					npc.held_item.refuel_tick(delta)   ## REAL continuous pour
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
				for plant in target.plant_refs:
					if plant != null and is_instance_valid(plant) and plant.is_ready():
						plant.harvest()   ## spawns real produce, clears cell
				NotificationManager.notify(UIKit.Domain.NEUTRAL,
					NotificationManager.Severity.INFO,
					"%s harvested the crops" % npc.npc_name)
			"REPLACE_FILTER":
				if npc.held_item is PurifierFilterItem:
					var filt: PurifierFilterItem = npc.held_item
					npc.held_item = null      ## replace_filter consumes/frees it
					target.replace_filter(filt)
					NotificationManager.notify(UIKit.Domain.WATER,
						NotificationManager.Severity.INFO,
						"%s replaced the purifier filter" % npc.npc_name)
			"REFUEL":
				## Pouring already happened continuously during "work".
				if npc.held_item != null:
					NPCItemUser.drop_held(npc)   ## set the can back down
				NotificationManager.notify(UIKit.Domain.POWER,
					NotificationManager.Severity.INFO,
					"%s refueled the generator" % npc.npc_name)
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

	func tick(npc: NPC, delta: float) -> void:
		npc.energy = minf(100.0, npc.energy + REGEN_PER_GAME_HOUR * npc.game_hours(delta))

	func done(npc: NPC) -> bool:
		return npc.energy >= 100.0

	func exit(npc: NPC) -> void:
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