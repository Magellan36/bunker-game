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
		if _current.done(_npc):
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
	if best is JobActivity and randf() < _npc.get_forgetfulness_chance():
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

	func score(_npc: NPC) -> float:
		return 5.0   ## constant baseline — always available, loses to any need

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
		return (100.0 - npc.energy)   ## 40..100 as energy falls 60→0

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

	func label() -> String:
		return "Drinking" if _drinking > 0.0 else "Getting water"

	func score(npc: NPC) -> float:
		if npc.thirst >= 55.0:
			return 0.0
		if _pick_target(npc).is_empty():
			return 0.0
		return (100.0 - npc.thirst) * 1.2   ## thirst outranks equal-level energy

	func _pick_target(npc: NPC) -> Dictionary:
		var best_d: float = INF
		var out: Dictionary = {}
		for d: Node in npc.get_tree().get_nodes_in_group("water_dispenser"):
			if not is_instance_valid(d) or d.current_fill_mL < DRINK_ML:
				continue
			var dist: float = (d as Node3D).global_position.distance_to(npc.global_position)
			if dist < best_d:
				best_d = dist
				out = {"mode": "dispenser", "node": d}
		var bottle: RigidBody3D = NPCItemUser.find_loose_item(npc,
			Callable(NPCItemUser, "is_drinkable_bottle"))
		if bottle != null:
			var dist_b: float = bottle.global_position.distance_to(npc.global_position)
			if dist_b < best_d:
				out = {"mode": "bottle", "node": bottle}
		return out

	func enter(npc: NPC) -> void:
		_drinking = 0.0
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
		if npc.global_position.distance_to((_target as Node3D).global_position) <= USE_RANGE:
			npc.velocity = Vector3.ZERO
			_drinking = CONSUME_TIME

	func _finish_dispenser(npc: NPC) -> void:
		var d: Node = _target
		var ml: float = minf(DRINK_ML, d.current_fill_mL)
		if ml > 0.0:
			d.current_fill_mL -= ml                       ## REAL deduction
			if d.has_method("_update_fill_visual"):
				d._update_fill_visual()
			npc.thirst = minf(100.0, npc.thirst + HYDRATION * (ml / DRINK_ML))
		_target = null

	func _tick_bottle(npc: NPC, delta: float) -> void:
		if _drinking > 0.0:
			npc.halt_movement(delta)
			_drinking -= delta
			if _drinking <= 0.0:
				_finish_bottle(npc)
			return
		if npc.held_item == _target:
			## Grabbed — start the visible holding/drinking wait.
			npc.velocity = Vector3.ZERO
			_drinking = CONSUME_TIME
			return
		npc.nav_steer(delta)
		if npc.global_position.distance_to((_target as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
			if not NPCItemUser.grab_loose(npc, _target):
				NPCItemUser.release_item(_target)
				_target = null   ## grab failed — give up cleanly, rescore next think

	func _finish_bottle(npc: NPC) -> void:
		var b: Node = _target
		if b != null and is_instance_valid(b) and npc.held_item == b:
			npc.thirst = minf(100.0, npc.thirst + b.take_drink())   ## REAL deduction
			NPCItemUser.release_item(b)
			NPCItemUser.drop_held(npc)
		_target = null

	func done(npc: NPC) -> bool:
		return _target == null or npc.thirst >= 90.0

	func interruptible() -> bool:
		return _drinking <= 0.0

	func exit(npc: NPC) -> void:
		if _target != null:
			NPCItemUser.release_item(_target)
		if npc.held_item != null:
			NPCItemUser.release_item(npc.held_item)
			NPCItemUser.drop_held(npc)
		_target = null
		_drinking = 0.0


class EatActivity extends NPCActivity:
	## Hunger-driven. Nearest edible: cooked Dish / produce / FoodCan-with-
	## bites, loose in the world OR on a shelf (via Shelving.npc_retrieve).
	const CONSUME_TIME: float = 2.0
	const USE_RANGE:    float = 1.2

	var _loose: RigidBody3D = null
	var _shelf_pick: Dictionary = {}
	var _eating: float = 0.0

	func label() -> String:
		return "Eating" if _eating > 0.0 else "Getting food"

	func score(npc: NPC) -> float:
		if npc.hunger >= 55.0:
			return 0.0
		if _find(npc) == null and _find_shelf(npc).is_empty():
			return 0.0
		return (100.0 - npc.hunger) * 1.15

	func _find(npc: NPC) -> RigidBody3D:
		return NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_edible"))

	func _find_shelf(npc: NPC) -> Dictionary:
		return NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_edible"))

	func enter(npc: NPC) -> void:
		_eating = 0.0
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
		if _eating > 0.0:
			npc.halt_movement(delta)
			_eating -= delta
			if _eating <= 0.0:
				if NPCItemUser.eat_held_step(npc):
					pass          ## finished — done() ends us
				else:
					_eating = CONSUME_TIME   ## next bite of the same can
			return

		if npc.held_item != null:
			npc.velocity = Vector3.ZERO
			_eating = CONSUME_TIME
			return

		if _loose != null and is_instance_valid(_loose):
			npc.nav_steer(delta)
			if npc.global_position.distance_to(_loose.global_position) <= USE_RANGE:
				if NPCItemUser.grab_loose(npc, _loose):
					_loose = null
			return
		_loose = null

		if not _shelf_pick.is_empty():
			var shelf: Node3D = _shelf_pick.get("shelf")
			if shelf == null or not is_instance_valid(shelf):
				_shelf_pick = {}
				return
			npc.nav_steer(delta)
			if npc.global_position.distance_to(shelf.global_position) <= NPCItemUser.SHELF_RANGE:
				if NPCItemUser.grab_from_shelf(npc, shelf, int(_shelf_pick.get("slot", -1))):
					_shelf_pick = {}
				else:
					_shelf_pick = {}   ## slot emptied under us — rescore
			return

	func done(npc: NPC) -> bool:
		return _eating <= 0.0 and npc.held_item == null \
			and _loose == null and _shelf_pick.is_empty()

	func interruptible() -> bool:
		return _eating <= 0.0

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
		var dist: float = (target as Node3D).global_position.distance_to(npc.global_position)
		return float(conf["base"]) * skill / (1.0 + dist * 0.08)

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

	func _start_travel(npc: NPC) -> void:
		_phase = "travel"
		var target: Node3D = _job.get("target") as Node3D
		if target != null and is_instance_valid(target):
			npc.set_nav_target(target.global_position)

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
				if npc.global_position.distance_to(target.global_position) <= WORK_RANGE:
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
			npc.nav_steer(delta)
			if npc.global_position.distance_to(_fetch_loose.global_position) \
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
			if npc.global_position.distance_to(shelf.global_position) \
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
		return (100.0 - npc.energy)

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