extends NPCActivity
class_name PutAwayHeldItemActivity
## Safety net for a held item left over after its original activity ended.
## Delivery deliberately mirrors CleaningActivity: approach a claimed side of
## storage, retain the item across transient contention/route failures, and
## only drop after confirming that no compatible storage has capacity.

const SCORE: float = 20.0
const APPROACH_REFRESH_DISTANCE: float = 0.35
const STORAGE_APPROACH_DISTANCE: float = NPCItemUser.SNATCH_RANGE - 0.20
const STORAGE_RETRY_INTERVAL_SEC: float = 0.45
const NO_STORAGE_CONFIRM_SEC: float = 3.0

var _item: RigidBody3D = null
var _destination: Node = null
var _is_trash: bool = false
var _settled: bool = false
var _waiting_for_storage: bool = false
var _storage_retry_left: float = 0.0
var _no_storage_elapsed: float = 0.0
var _storage_retry_count: int = 0
var _storage_attempt_excludes: Dictionary = {}
var _approach_target_id: int = 0
var _approach_target_origin: Vector3 = Vector3.INF
var _approach_position: Vector3 = Vector3.INF


func label() -> String:
	return "Putting away %s" % (_item.get_display_name() \
		if _item != null and is_instance_valid(_item) and _item.has_method("get_display_name") \
		else "an item")


func attention_target(_npc: NPC) -> Node3D:
	return _destination as Node3D if _destination is Node3D \
		and is_instance_valid(_destination) else null


func score(npc: NPC) -> float:
	return SCORE if npc.held_item != null else 0.0


func debug_score_reason(_npc: NPC, computed_score: float) -> StringName:
	return &"holding_unassigned_item" if computed_score > 0.0 else &"hands_empty"


func interruptible() -> bool:
	return false


func debug_info() -> Dictionary:
	var phase: String = "settled" if _settled else (
		"waiting_for_storage" if _waiting_for_storage else "deliver")
	return {
		"activity": "put_away",
		"phase": phase,
		"item": String(_item.name) if _item != null and is_instance_valid(_item) else "",
		"destination": String(_destination.name) \
			if _destination != null and is_instance_valid(_destination) else "",
		"storage_retry_count": _storage_retry_count,
		"no_storage_elapsed": _no_storage_elapsed,
		"approach_position": _approach_position,
	}


func enter(npc: NPC) -> void:
	_item = npc.held_item
	_destination = null
	_settled = false
	_waiting_for_storage = false
	_storage_retry_left = 0.0
	_no_storage_elapsed = 0.0
	_storage_retry_count = 0
	_storage_attempt_excludes = {}
	_clear_approach(npc)
	if _item == null or not is_instance_valid(_item):
		_settled = true
		return
	_is_trash = NPCJobQueries.is_trash_item(npc, _item)
	_destination = NPCJobQueries.find_cleaning_destination(npc, _is_trash, _item)
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "put away held item", "%s -> %s" % [
			_display_name(),
			(_destination.name if _destination != null else "(searching for storage)")])
	if _destination == null:
		_begin_storage_retry(npc, "no compatible destination immediately available")
		return
	if not _set_storage_approach(npc, _destination as Node3D):
		_begin_storage_retry(npc, "initial storage side unavailable", true)


func tick(npc: NPC, delta: float) -> void:
	if _settled:
		return
	if _item == null or not is_instance_valid(_item) or npc.held_item != _item:
		_settled = true
		_clear_approach(npc)
		return
	if _waiting_for_storage:
		_tick_storage_retry(npc, delta)
		return
	if _destination == null or not is_instance_valid(_destination):
		_begin_storage_retry(npc, "storage destination disappeared")
		return
	if not _set_storage_approach(npc, _destination as Node3D):
		_begin_storage_retry(npc, "storage side became unavailable", true)
		return
	npc.nav_steer(delta)
	if npc.nav_failed():
		_begin_storage_retry(npc, "storage route failed", true)
		return
	if not npc.nav_finished():
		return
	npc.face_interaction_slot()
	var destination_name: String = String(_destination.name)
	if _destination.has_method("npc_try_place_item") \
			and _destination.npc_try_place_item(npc, _item):
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "put away delivered", "%s stored in %s (held_item_after=%s)" % [
				_display_name(), destination_name,
				(npc.held_item.get_display_name() if npc.held_item != null \
					and npc.held_item.has_method("get_display_name") else "none")])
		_settled = true
		_clear_approach(npc)
		return
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "put away redirected", "%s retained — %s could not accept it" % [
			_display_name(), destination_name])
	_begin_storage_retry(npc, "destination filled before placement", true)


func _set_storage_approach(npc: NPC, target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var target_id: int = target.get_instance_id()
	if target_id == _approach_target_id \
			and NPCItemUser.flat_distance(target.global_position, _approach_target_origin) \
				< APPROACH_REFRESH_DISTANCE \
			and _approach_position != Vector3.INF:
		return npc.set_nav_target(_approach_position, NPC.NAV_PRECISE_TARGET_DISTANCE)
	var lease: Dictionary = npc.claim_interaction_slot(
		target, &"clean_store", STORAGE_APPROACH_DISTANCE)
	if lease.is_empty():
		_clear_approach(npc)
		return false
	_approach_target_id = target_id
	_approach_target_origin = target.global_position
	_approach_position = npc.get_interaction_slot_position()
	if npc.set_nav_target(_approach_position, NPC.NAV_PRECISE_TARGET_DISTANCE):
		return true
	_clear_approach(npc)
	return false


func _clear_approach(npc: NPC) -> void:
	npc.release_interaction_slot()
	_approach_target_id = 0
	_approach_target_origin = Vector3.INF
	_approach_position = Vector3.INF


func _begin_storage_retry(npc: NPC, reason: String, reject_current: bool = false) -> void:
	if reject_current and _destination != null and is_instance_valid(_destination):
		_storage_attempt_excludes[_destination.get_instance_id()] = true
	var first_wait: bool = not _waiting_for_storage
	_waiting_for_storage = true
	_storage_retry_left = STORAGE_RETRY_INTERVAL_SEC
	_destination = null
	_clear_approach(npc)
	npc.halt_movement(1.0)
	if first_wait and NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "put away retry", "%s — %s; keeping item in hand" % [
			_display_name(), reason])


func _tick_storage_retry(npc: NPC, delta: float) -> void:
	npc.halt_movement(delta)
	_storage_retry_left = maxf(0.0, _storage_retry_left - delta)
	if _storage_retry_left > 0.0:
		return
	_storage_retry_count += 1
	var destination: Node = NPCJobQueries.find_cleaning_destination(
		npc, _is_trash, _item, _storage_attempt_excludes)
	if destination == null and not _storage_attempt_excludes.is_empty():
		_storage_attempt_excludes.clear()
		destination = NPCJobQueries.find_cleaning_destination(npc, _is_trash, _item)
	if destination == null:
		_no_storage_elapsed += STORAGE_RETRY_INTERVAL_SEC
		_storage_retry_left = STORAGE_RETRY_INTERVAL_SEC
		if _no_storage_elapsed < NO_STORAGE_CONFIRM_SEC:
			return
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "put away no storage confirmed", "%s had no compatible capacity for %.1fs — dropping once" % [
				_display_name(), _no_storage_elapsed])
		NPCItemUser.drop_held(npc)
		_settled = true
		_waiting_for_storage = false
		_clear_approach(npc)
		return
	_no_storage_elapsed = 0.0
	_destination = destination
	if not _set_storage_approach(npc, _destination as Node3D):
		_storage_attempt_excludes[_destination.get_instance_id()] = true
		_destination = null
		_storage_retry_left = STORAGE_RETRY_INTERVAL_SEC
		return
	_waiting_for_storage = false
	_storage_attempt_excludes.clear()
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "put away resumed", "%s -> %s after %d retries" % [
			_display_name(), _destination.name, _storage_retry_count])


func _display_name() -> String:
	if _item != null and is_instance_valid(_item):
		return _item.get_display_name() if _item.has_method("get_display_name") else String(_item.name)
	return "an item"


func done(_npc: NPC) -> bool:
	return _settled


func exit(npc: NPC) -> void:
	_clear_approach(npc)


func watchdog_expects_movement(_npc: NPC) -> bool:
	return not _settled and not _waiting_for_storage


func watchdog_allows_long_stationary(_npc: NPC) -> bool:
	return _waiting_for_storage
