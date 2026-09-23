extends RefCounted
class_name NPCInteractionSlots
## Shared interaction-space arbitration for resident NPCs.
##
## Activities claim a short-lived slot before travelling to a stationary
## target. A slot is a stable world transform plus a claim group. Different
## slots may be used concurrently; candidates with the same claim group are
## alternate approaches to one exclusive interaction (for example either side
## of a one-person bed). Claims are runtime-only weak leases and never persist.

const MAX_PROJECTION_DRIFT: float = 0.9

static var _leases: Dictionary = {} ## String key -> lease Dictionary
static var _next_serial: int = 1


static func claim_best(owner: Node3D, target: Node3D, action: StringName,
		distance: float = 1.0, authored: Array[Dictionary] = []) -> Dictionary:
	if owner == null or target == null or not is_instance_valid(owner) \
			or not is_instance_valid(target):
		return {}
	_cleanup_stale()
	release_owner(owner)
	var candidates: Array[Dictionary] = authored
	if candidates.is_empty() and target.has_method("get_npc_interaction_slots"):
		var provided: Variant = target.call("get_npc_interaction_slots", action)
		if provided is Array:
			for candidate: Variant in provided:
				if candidate is Dictionary:
					candidates.append(candidate as Dictionary)
	if candidates.is_empty():
		candidates = _generated_candidates(target, distance)
	var best: Dictionary = {}
	var best_cost: float = INF
	for candidate: Dictionary in candidates:
		var slot_id: StringName = StringName(candidate.get("slot_id", &"slot"))
		var claim_group: StringName = StringName(candidate.get("claim_group", slot_id))
		var key: String = _key(target, action, claim_group)
		if _claimed_by_other(key, owner):
			continue
		var transform: Transform3D = candidate.get("transform", Transform3D.IDENTITY)
		var requested: Vector3 = transform.origin
		var projected: Vector3 = requested
		if owner.has_method("project_navigation_point"):
			projected = owner.project_navigation_point(requested)
		var drift: float = _flat_distance(requested, projected)
		if drift > float(candidate.get("max_projection_drift", MAX_PROJECTION_DRIFT)):
			continue
		# A point can be on the navmesh while a movable crate, chair, or other
		# live physics body currently occupies the actual standing space.  The
		# navigation map intentionally lags those transient objects; let the
		# actor reject such slots before committing to an approach it can never
		# physically complete.
		if owner.has_method("is_interaction_position_clear") \
				and not bool(owner.call("is_interaction_position_clear", projected, target)):
			continue
		transform.origin = projected
		var travel_cost: float = _flat_distance(owner.global_position, projected)
		if owner.has_method("get_navigation_route_cost"):
			travel_cost = float(owner.call("get_navigation_route_cost", projected))
			if is_inf(travel_cost):
				continue
		var cost: float = travel_cost + drift * 2.0
		if cost < best_cost:
			best_cost = cost
			best = {
				"slot_id": slot_id,
				"claim_group": claim_group,
				"key": key,
				"transform": transform,
			}
	if best.is_empty():
		return {}
	var serial: int = _next_serial
	_next_serial += 1
	var lease: Dictionary = {
		"key": best["key"],
		"serial": serial,
		"slot_id": best["slot_id"],
		"claim_group": best["claim_group"],
		"action": action,
		"transform": best["transform"],
		"owner_id": owner.get_instance_id(),
		"owner_ref": weakref(owner),
		"target_id": target.get_instance_id(),
		"target_ref": weakref(target),
	}
	_leases[best["key"]] = lease
	return lease


static func release(lease: Dictionary, owner: Node3D) -> void:
	if lease.is_empty() or owner == null:
		return
	var key: String = String(lease.get("key", ""))
	var live: Dictionary = _leases.get(key, {})
	if not live.is_empty() and int(live.get("serial", -1)) == int(lease.get("serial", -2)) \
			and int(live.get("owner_id", 0)) == owner.get_instance_id():
		_leases.erase(key)


static func release_owner(owner: Node3D) -> void:
	if owner == null:
		return
	var owner_id: int = owner.get_instance_id()
	for key: Variant in _leases.keys():
		var lease: Dictionary = _leases.get(key, {})
		if int(lease.get("owner_id", 0)) == owner_id:
			_leases.erase(key)


static func is_claimed_by_other(target: Node3D, action: StringName,
		claim_group: StringName, owner: Node3D) -> bool:
	_cleanup_stale()
	return _claimed_by_other(_key(target, action, claim_group), owner)


static func lease_is_valid(lease: Dictionary, owner: Node3D) -> bool:
	if lease.is_empty() or owner == null:
		return false
	_cleanup_stale()
	var live: Dictionary = _leases.get(String(lease.get("key", "")), {})
	return not live.is_empty() \
		and int(live.get("serial", -1)) == int(lease.get("serial", -2)) \
		and int(live.get("owner_id", 0)) == owner.get_instance_id()


static func _generated_candidates(target: Node3D, distance: float) -> Array[Dictionary]:
	var basis: Basis = target.global_transform.basis.orthonormalized()
	var directions: Array[Vector3] = [basis.z, -basis.z, basis.x, -basis.x]
	var ids: Array[StringName] = [&"front", &"back", &"right", &"left"]
	var result: Array[Dictionary] = []
	for index: int in directions.size():
		var direction: Vector3 = directions[index]
		direction.y = 0.0
		if direction.length_squared() < 0.01:
			continue
		var position: Vector3 = target.global_position + direction.normalized() * distance
		var transform := Transform3D(Basis.IDENTITY, position)
		var look_target: Vector3 = target.global_position
		look_target.y = position.y
		if position.distance_squared_to(look_target) > 0.01:
			transform = transform.looking_at(look_target, Vector3.UP)
		result.append({
			"slot_id": ids[index],
			"claim_group": ids[index],
			"transform": transform,
		})
	return result


static func _claimed_by_other(key: String, owner: Node3D) -> bool:
	var lease: Dictionary = _leases.get(key, {})
	return not lease.is_empty() and int(lease.get("owner_id", 0)) != owner.get_instance_id()


static func _key(target: Node3D, action: StringName, claim_group: StringName) -> String:
	return "%d:%s:%s" % [target.get_instance_id(), String(action), String(claim_group)]


static func _cleanup_stale() -> void:
	for key: Variant in _leases.keys():
		var lease: Dictionary = _leases.get(key, {})
		var owner_ref: WeakRef = lease.get("owner_ref") as WeakRef
		var target_ref: WeakRef = lease.get("target_ref") as WeakRef
		if owner_ref == null or owner_ref.get_ref() == null \
				or target_ref == null or target_ref.get_ref() == null:
			_leases.erase(key)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
