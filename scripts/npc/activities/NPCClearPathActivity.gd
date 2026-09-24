extends NPCActivity
class_name NPCClearPathActivity
## Short locomotion-recovery overlay. NPCBrain pauses the live utility activity
## without exiting it, lets this action move one verified corridor blocker to a
## verified clear drop point, then resumes the exact original activity object.

const NPC_DYNAMIC_OBSTACLE_MAP: GDScript = preload("res://scripts/npc/NPCDynamicObstacleMap.gd")
const GRAB_BEAT: float = 0.25
const SHOVE_BEAT: float = 0.4
const SETTLE_BEAT: float = 0.55
const MAX_DURATION: float = 10.0

enum Phase { PREPARE, GRAB, CARRY, SHOVE, SETTLE, DONE, FAILED }

var _item: RigidBody3D = null
var _resume_target: Vector3 = Vector3.ZERO
var _resume_distance: float = NPC.NAV_DEFAULT_TARGET_DISTANCE
var _corridor_start: Vector3 = Vector3.ZERO
var _corridor_finish: Vector3 = Vector3.ZERO
var _drop_position: Vector3 = Vector3.INF
var _phase: int = Phase.PREPARE
var _timer: float = 0.0
var _elapsed: float = 0.0
var _claimed: bool = false


func _init(item: RigidBody3D, resume_target: Vector3, resume_distance: float,
		corridor_finish: Vector3) -> void:
	_item = item
	_resume_target = resume_target
	_resume_distance = resume_distance
	_corridor_finish = corridor_finish


func label() -> String:
	return "Clearing the way"


func attention_target(_npc: NPC) -> Node3D:
	return _item if _item != null and is_instance_valid(_item) else null


func interruptible() -> bool:
	return false


func enter(npc: NPC) -> void:
	_corridor_start = npc.global_position
	if _item == null or not is_instance_valid(_item) or npc.held_item != null \
			or (("is_held" in _item) and _item.is_held) or _item.is_in_group("shelved"):
		_phase = Phase.FAILED
		return
	if not NPCItemUser.claim_item(_item, npc):
		_phase = Phase.FAILED
		return
	_claimed = true
	_drop_position = NPC_DYNAMIC_OBSTACLE_MAP.choose_drop_position(
		npc, _item, _corridor_start, _corridor_finish)
	if _drop_position == Vector3.INF:
		_phase = Phase.FAILED
		return
	if NPCItemUser.flat_distance(npc.global_position, _item.global_position) \
			> NPCItemUser.SNATCH_RANGE:
		_phase = Phase.FAILED
		return
	npc.suspend_navigation_for_overlay()
	npc.lock_movement()
	_timer = GRAB_BEAT
	_phase = Phase.GRAB


func tick(npc: NPC, delta: float) -> void:
	_elapsed += delta
	if _elapsed >= MAX_DURATION:
		_phase = Phase.FAILED
	if _phase == Phase.GRAB:
		npc.halt_movement(delta)
		_timer -= delta
		if _timer <= 0.0:
			_grab(npc)
		return
	if _phase == Phase.CARRY:
		if _item == null or not is_instance_valid(_item) or npc.held_item != _item:
			_phase = Phase.FAILED
			return
		npc.nav_steer(delta)
		if npc.nav_failed():
			_phase = Phase.FAILED
			return
		if NPCItemUser.flat_distance(npc.global_position, _drop_position) \
				<= NPCItemUser.SNATCH_RANGE or npc.nav_finished():
			_drop_at_verified_position(npc)
		return
	if _phase == Phase.SHOVE:
		npc.halt_movement(delta)
		npc.face_world_position(_drop_position)
		_timer -= delta
		if _timer <= 0.0:
			_shove_toward_verified_position(npc)
		return
	if _phase == Phase.SETTLE:
		npc.halt_movement(delta)
		_timer -= delta
		if _timer <= 0.0:
			npc.set_nav_target(_resume_target, _resume_distance)
			_phase = Phase.DONE


func _grab(npc: NPC) -> void:
	if _item == null or not is_instance_valid(_item) or npc.held_item != null \
			or (("is_held" in _item) and _item.is_held) \
			or NPCItemUser.flat_distance(npc.global_position, _item.global_position) \
			> NPCItemUser.SNATCH_RANGE:
		_phase = Phase.FAILED
		return
	_item.pickup(npc.hold_point)
	npc.held_item = _item
	## When other clutter also blocks the carrying route, attempting to walk
	## while holding this item recreates the same RVO deadlock until timeout.
	## Make the visible grab deliberate, then physically shove this one object
	## toward the verified empty pocket. Ordinary clear routes still carry it.
	if not NPC_DYNAMIC_OBSTACLE_MAP.corridor_blockers(
			npc, npc.global_position, _drop_position, _item).is_empty():
		_timer = SHOVE_BEAT
		_phase = Phase.SHOVE
		return
	if not npc.set_nav_target(_drop_position, NPC.NAV_PRECISE_TARGET_DISTANCE):
		_phase = Phase.FAILED
		return
	_phase = Phase.CARRY


func _shove_toward_verified_position(npc: NPC) -> void:
	if _item == null or not is_instance_valid(_item) or npc.held_item != _item:
		_phase = Phase.FAILED
		return
	var direction: Vector3 = _drop_position - npc.hold_point.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		_phase = Phase.FAILED
		return
	direction = direction.normalized()
	var release_position: Vector3 = npc.hold_point.global_position \
		+ direction * 0.35 + Vector3.UP * 0.1
	var parent: Node3D = npc.get_tree().get_first_node_in_group("main_world") as Node3D
	if parent == null:
		parent = npc.get_parent() as Node3D
	npc.held_item = null
	_item.drop(parent, release_position)
	_item.apply_central_impulse((direction * 1.65 + Vector3.UP * 0.12) \
		* maxf(1.0, _item.mass))
	NPCItemUser.release_item(_item)
	_claimed = false
	_timer = 0.9
	_phase = Phase.SETTLE


func _drop_at_verified_position(npc: NPC) -> void:
	var parent: Node3D = npc.get_tree().get_first_node_in_group("main_world") as Node3D
	if parent == null:
		parent = npc.get_parent() as Node3D
	npc.held_item = null
	_item.drop(parent, _drop_position)
	NPCItemUser.release_item(_item)
	_claimed = false
	_timer = SETTLE_BEAT
	_phase = Phase.SETTLE


func done(_npc: NPC) -> bool:
	return _phase == Phase.DONE or _phase == Phase.FAILED


func succeeded() -> bool:
	return _phase == Phase.DONE


func obstruction_id() -> int:
	return _item.get_instance_id() if _item != null and is_instance_valid(_item) else -1


func exit(npc: NPC) -> void:
	if _item != null and is_instance_valid(_item):
		if npc.held_item == _item:
			NPCItemUser.drop_held(npc)
		if _claimed:
			NPCItemUser.release_item(_item)
	_claimed = false
	npc.set_nav_target(_resume_target, _resume_distance)


func debug_info() -> Dictionary:
	return {
		"activity": "path_clear",
		"phase": Phase.keys()[_phase],
		"item": _item.name if _item != null and is_instance_valid(_item) else "",
		"drop_position": _drop_position,
		"resume_target": _resume_target,
		"elapsed": _elapsed,
	}
