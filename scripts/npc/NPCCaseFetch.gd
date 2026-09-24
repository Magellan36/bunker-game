extends RefCounted
class_name NPCCaseFetch
## Shared final-resort case access for EatActivity and DrinkActivity.
## The case remains exactly where it was found (loose or shelved): the NPC
## approaches it, removes one item, and immediately gives that item the normal
## PickupableItem held target. The item's existing follow physics provides the
## visible case-to-hand movement; consumption and trash handling remain owned
## by the calling activity.

enum Phase { LOCATE, TRAVEL, EXTRACT, DONE, FAILED }

const CASE_RANGE: float = 1.8
const EXTRACT_TIME: float = 0.45

var phase: int = Phase.LOCATE

var _case_filter: Callable
var _case: RigidBody3D = null
var _origin_shelf: Node = null
var _origin_slot: int = -1
var _from_shelf: bool = false
var _dispensed: RigidBody3D = null
var _extract_timer: float = 0.0


func _init(case_filter: Callable) -> void:
	_case_filter = case_filter


func is_done() -> bool:
	return phase == Phase.DONE or phase == Phase.FAILED


func failed() -> bool:
	return phase == Phase.FAILED


func get_dispensed_item() -> RigidBody3D:
	return _dispensed


func get_case_target() -> Node3D:
	if _case != null and is_instance_valid(_case):
		return _case
	return null


func tick(npc: NPC, delta: float) -> void:
	match phase:
		Phase.LOCATE:
			_locate(npc)
		Phase.TRAVEL:
			_tick_travel(npc, delta)
		Phase.EXTRACT:
			_tick_extract(npc, delta)


func _locate(npc: NPC) -> void:
	if npc.held_item != null:
		phase = Phase.FAILED
		return
	var pick: Dictionary = NPCItemUser.find_fetch_target(npc, _case_filter)
	if pick.is_empty():
		phase = Phase.FAILED
		return
	if pick.has("loose"):
		_case = pick["loose"]
		_from_shelf = false
	else:
		var shelf_pick: Dictionary = pick["shelf"]
		_origin_shelf = shelf_pick.get("shelf")
		_origin_slot = int(shelf_pick.get("slot", -1))
		_case = shelf_pick.get("item")
		_from_shelf = true
	if _case == null or not NPCItemUser.claim_item(_case, npc):
		_case = null
		phase = Phase.FAILED
		return
	var approach: Node3D = _origin_shelf as Node3D if _from_shelf else _case
	if approach == null or not is_instance_valid(approach):
		_fail()
		return
	npc.set_nav_target(approach.global_position)
	phase = Phase.TRAVEL


func _tick_travel(npc: NPC, delta: float) -> void:
	if not _case_is_available():
		_fail()
		return
	var approach: Node3D = _origin_shelf as Node3D if _from_shelf else _case
	if approach == null or not is_instance_valid(approach):
		_fail()
		return
	if not _from_shelf:
		NPCItemUser.track_fetch_target(npc, _case)
	npc.nav_steer(delta)
	var use_range: float = NPCItemUser.SHELF_RANGE if _from_shelf else CASE_RANGE
	if NPCItemUser.flat_distance(npc.global_position, approach.global_position) <= use_range:
		npc.cancel_navigation()
		npc.lock_movement()
		_extract_timer = EXTRACT_TIME
		phase = Phase.EXTRACT


func _tick_extract(npc: NPC, delta: float) -> void:
	npc.halt_movement(delta)
	if npc.held_item != null or not _case_is_available():
		_fail()
		return
	_extract_timer -= delta
	if _extract_timer > 0.0:
		return
	if not _case.has_method("npc_take_one"):
		_fail()
		return
	_dispensed = _case.npc_take_one(npc) as RigidBody3D
	if _dispensed == null or not is_instance_valid(_dispensed) \
			or not _dispensed.has_method("pickup") \
			or not NPCItemUser.claim_item(_dispensed, npc):
		if _dispensed != null:
			NPCItemUser.release_item(_dispensed)
		_dispensed = null
		_fail()
		return
	_dispensed.pickup(npc.hold_point)
	npc.held_item = _dispensed
	NPCItemUser.release_item(_case)
	_case = null
	phase = Phase.DONE


func _case_is_available() -> bool:
	if _case == null or not is_instance_valid(_case) or not _case_filter.call(_case):
		return false
	if "is_held" in _case and _case.is_held:
		return false
	if not _from_shelf:
		return not _case.is_in_group("shelved")
	if _origin_shelf == null or not is_instance_valid(_origin_shelf) \
			or not ("slots" in _origin_shelf) \
			or _origin_slot < 0 or _origin_slot >= _origin_shelf.slots.size():
		return false
	var stack: Array = _origin_shelf.slots[_origin_slot]
	return not stack.is_empty() and stack.back() == _case and _case.is_in_group("shelved")


func _fail() -> void:
	if _case != null:
		NPCItemUser.release_item(_case)
	_case = null
	phase = Phase.FAILED


func cleanup(_npc: NPC) -> void:
	if _case != null:
		NPCItemUser.release_item(_case)
	if _dispensed != null:
		NPCItemUser.release_item(_dispensed)
	_case = null
