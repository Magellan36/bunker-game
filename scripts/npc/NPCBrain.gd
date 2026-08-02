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
	]

func current_label() -> String:
	return _current.label() if _current != null else "Idle"

## Called by NPC._physics_process every frame.
func tick(delta: float) -> void:
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
	for cand: NPCActivity in _candidates:
		if cand == _current:
			continue
		var s: float = cand.score(_npc)
		if s > best_score:
			best_score = s
			best = cand

	if best == null:
		return

	if _current == null:
		_start(best)
		return

	## Incumbent defends its seat: challenger needs margin AND permission.
	if _current.interruptible() and best_score > _current.score(_npc) + SWITCH_MARGIN:
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
		if npc.nav_finished() or npc.global_position.distance_to(
				(_chair as Node3D).global_position) < 0.9:
			## Claim + snap onto the seat (mirrors the player seat flow in
			## MainWorld._wire_chair, minus the physics-process freeze —
			## the NPC just parks with zero velocity).
			if _chair.has_method("npc_try_sit") and _chair.npc_try_sit(npc):
				_seated = true
				var t: Transform3D = _chair.get_seat_transform()
				npc.global_position = t.origin
				npc.rotation.y = t.basis.get_euler().y
				npc.velocity = Vector3.ZERO
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
			var d: float = (c as Node3D).global_position.distance_to(npc.global_position)
			if d < best_d:
				best_d = d
				best = c
		return best