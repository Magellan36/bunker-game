extends RefCounted
class_name NPCDoorCoordinator
## Short-range arbitration for true navigation bottlenecks.
##
## Godot avoidance still owns local collision-free velocity. This coordinator
## only prevents opposite-direction residents from entering the same narrow
## doorway at once. It never reserves a route, room, or distant path.

const MAX_SAME_DIRECTION_BATCH: int = 2
const BATCH_WINDOW_MSEC: int = 1100
const LEASE_MSEC: int = 8000

static var _states: Dictionary = {} ## door instance id -> state Dictionary
static var _next_serial: int = 1


static func request(npc: Node3D, door: Node3D, direction: int) -> Dictionary:
	if npc == null or door == null or direction == 0:
		return {}
	_cleanup()
	var door_id: int = door.get_instance_id()
	var state: Dictionary = _states.get(door_id, {
		"door_ref": weakref(door),
		"direction": 0,
		"batch_started": 0,
		"holders": {},
		"queue": [],
	})
	var holders: Dictionary = state["holders"]
	var npc_id: int = npc.get_instance_id()
	if holders.has(npc_id):
		return holders[npc_id]
	var queue: Array = state["queue"]
	var queued: bool = false
	for entry: Dictionary in queue:
		if int(entry.get("npc_id", 0)) == npc_id:
			queued = true
			break
	if not queued:
		queue.append({
			"npc_id": npc_id,
			"npc_ref": weakref(npc),
			"direction": direction,
			"since": Time.get_ticks_msec(),
		})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("since", 0)) < int(b.get("since", 0)))
	var now: int = Time.get_ticks_msec()
	var can_join_batch: bool = int(state["direction"]) == direction \
		and holders.size() < MAX_SAME_DIRECTION_BATCH \
		and now - int(state["batch_started"]) <= BATCH_WINDOW_MSEC
	var is_oldest: bool = not queue.is_empty() and int(queue[0].get("npc_id", 0)) == npc_id
	if holders.is_empty():
		## The oldest waiter selects the next direction. This prevents a stream
		## from one side from starving a resident on the other side.
		if not is_oldest:
			_states[door_id] = state
			return {}
		state["direction"] = direction
		state["batch_started"] = now
		can_join_batch = true
	if not can_join_batch:
		_states[door_id] = state
		return {}
	var serial: int = _next_serial
	_next_serial += 1
	var lease: Dictionary = {
		"door_id": door_id,
		"door_ref": weakref(door),
		"npc_id": npc_id,
		"npc_ref": weakref(npc),
		"direction": direction,
		"serial": serial,
		"expires": now + LEASE_MSEC,
	}
	holders[npc_id] = lease
	for index: int in range(queue.size() - 1, -1, -1):
		if int((queue[index] as Dictionary).get("npc_id", 0)) == npc_id:
			queue.remove_at(index)
	state["holders"] = holders
	state["queue"] = queue
	_states[door_id] = state
	return lease


static func release(lease: Dictionary, npc: Node3D) -> void:
	if lease.is_empty() or npc == null:
		return
	var door_id: int = int(lease.get("door_id", 0))
	var state: Dictionary = _states.get(door_id, {})
	if state.is_empty():
		return
	var holders: Dictionary = state["holders"]
	var live: Dictionary = holders.get(npc.get_instance_id(), {})
	if int(live.get("serial", -1)) == int(lease.get("serial", -2)):
		holders.erase(npc.get_instance_id())
	state["holders"] = holders
	if holders.is_empty() and (state["queue"] as Array).is_empty():
		_states.erase(door_id)
	else:
		_states[door_id] = state


static func release_owner(npc: Node3D) -> void:
	if npc == null:
		return
	var npc_id: int = npc.get_instance_id()
	for door_id: Variant in _states.keys():
		var state: Dictionary = _states.get(door_id, {})
		var holders: Dictionary = state.get("holders", {})
		holders.erase(npc_id)
		var queue: Array = state.get("queue", [])
		for index: int in range(queue.size() - 1, -1, -1):
			if int((queue[index] as Dictionary).get("npc_id", 0)) == npc_id:
				queue.remove_at(index)
		state["holders"] = holders
		state["queue"] = queue
		if holders.is_empty() and queue.is_empty():
			_states.erase(door_id)
		else:
			_states[door_id] = state


static func _cleanup() -> void:
	for door_id: Variant in _states.keys():
		var state: Dictionary = _states.get(door_id, {})
		var door_ref: WeakRef = state.get("door_ref") as WeakRef
		if door_ref == null or door_ref.get_ref() == null:
			_states.erase(door_id)
			continue
		var holders: Dictionary = state.get("holders", {})
		for npc_id: Variant in holders.keys():
			var lease: Dictionary = holders.get(npc_id, {})
			var npc_ref: WeakRef = lease.get("npc_ref") as WeakRef
			if npc_ref == null or npc_ref.get_ref() == null \
					or Time.get_ticks_msec() >= int(lease.get("expires", 0)):
				holders.erase(npc_id)
		var queue: Array = state.get("queue", [])
		for index: int in range(queue.size() - 1, -1, -1):
			var queued_ref: WeakRef = (queue[index] as Dictionary).get("npc_ref") as WeakRef
			if queued_ref == null or queued_ref.get_ref() == null:
				queue.remove_at(index)
		state["holders"] = holders
		state["queue"] = queue
		_states[door_id] = state
