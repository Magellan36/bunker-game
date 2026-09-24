extends RefCounted
class_name NPCDynamicObstacleMap
## Local, physics-aware occupancy queries layered above the structural
## navigation mesh. The navmesh answers bunker-scale connectivity; this helper
## answers whether an NPC-sized corridor is presently usable around loose,
## settled RigidBody clutter that is deliberately absent from the bake.

const NPC_RADIUS: float = 0.4
const COMFORT_MARGIN: float = 0.12
const QUERY_RADIUS: float = 6.0


static func segment_parameter(point: Vector3, start: Vector3, finish: Vector3) -> float:
	var a := Vector2(start.x, start.z)
	var b := Vector2(finish.x, finish.z)
	var p := Vector2(point.x, point.z)
	var ab: Vector2 = b - a
	var length_sq: float = ab.length_squared()
	if length_sq <= 0.0001:
		return 0.0
	return clampf((p - a).dot(ab) / length_sq, 0.0, 1.0)


static func distance_to_segment(point: Vector3, start: Vector3, finish: Vector3) -> float:
	var t: float = segment_parameter(point, start, finish)
	var closest: Vector3 = start.lerp(finish, t)
	return Vector2(point.x - closest.x, point.z - closest.z).length()


static func footprint_radius(item: RigidBody3D) -> float:
	if item != null and item.has_method("get_navigation_footprint_radius"):
		return maxf(0.05, float(item.get_navigation_footprint_radius()))
	return 0.3


static func corridor_blockers(npc: NPC, start: Vector3, finish: Vector3,
		exclude: Node = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if npc == null or not is_instance_valid(npc):
		return result
	for node: Node in npc.get_tree().get_nodes_in_group("pickup"):
		if not node is RigidBody3D or not is_instance_valid(node) or node == exclude:
			continue
		var item := node as RigidBody3D
		if (("is_held" in item) and item.is_held) or item.is_in_group("shelved"):
			continue
		if item.has_method("is_soft_navigation_clutter") \
				and bool(item.is_soft_navigation_clutter()):
			continue
		if absf(item.global_position.y - npc.global_position.y) > 1.8:
			continue
		var radius: float = footprint_radius(item)
		var distance_from_npc: float = NPCItemUser.flat_distance(npc.global_position, item.global_position)
		if distance_from_npc > QUERY_RADIUS:
			continue
		var corridor_distance: float = distance_to_segment(item.global_position, start, finish)
		if corridor_distance > NPC_RADIUS + radius + COMFORT_MARGIN:
			continue
		result.append({
			"item": item,
			"radius": radius,
			"corridor_distance": corridor_distance,
			"along": segment_parameter(item.global_position, start, finish),
			"distance": distance_from_npc,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var along_a: float = float(a.get("along", 1.0))
		var along_b: float = float(b.get("along", 1.0))
		if not is_equal_approx(along_a, along_b):
			return along_a < along_b
		return float(a.get("distance", INF)) < float(b.get("distance", INF)))
	return result


static func choose_detour(npc: NPC, start: Vector3, finish: Vector3,
		blockers: Array[Dictionary]) -> Dictionary:
	if blockers.is_empty():
		return {}
	var travel: Vector3 = finish - start
	travel.y = 0.0
	if travel.length_squared() < 0.01:
		return {}
	travel = travel.normalized()
	var side := Vector3(-travel.z, 0.0, travel.x)
	var cluster_center := Vector3.ZERO
	var cluster_radius: float = 0.0
	var count: int = mini(blockers.size(), 6)
	for index: int in count:
		var item: RigidBody3D = blockers[index].get("item") as RigidBody3D
		if item != null:
			cluster_center += item.global_position
	cluster_center /= float(maxi(count, 1))
	for index: int in count:
		var item: RigidBody3D = blockers[index].get("item") as RigidBody3D
		if item == null:
			continue
		cluster_radius = maxf(cluster_radius,
			NPCItemUser.flat_distance(cluster_center, item.global_position)
			+ float(blockers[index].get("radius", 0.3)))
	var clearance: float = cluster_radius + NPC_RADIUS + COMFORT_MARGIN + 0.25
	var best: Dictionary = {}
	var best_cost: float = INF
	for sign_value: float in [-1.0, 1.0]:
		for scale: float in [1.0, 1.35, 1.7]:
			var requested: Vector3 = cluster_center + side * sign_value * clearance * scale
			var candidate: Vector3 = npc.project_navigation_point(requested)
			if NPCItemUser.flat_distance(candidate, requested) > 0.85:
				continue
			if not npc.is_interaction_position_clear(candidate):
				continue
			if not corridor_blockers(npc, start, candidate).is_empty():
				continue
			if not corridor_blockers(npc, candidate, finish).is_empty():
				continue
			var cost: float = npc.get_navigation_route_cost(candidate)
			if is_inf(cost):
				continue
			cost += NPCItemUser.flat_distance(candidate, finish)
			if cost < best_cost:
				best_cost = cost
				best = {"point": candidate, "cost": cost, "side": sign_value,
					"blocker_count": blockers.size()}
	return best


static func choose_clearable_blocker(npc: NPC, blockers: Array[Dictionary]) -> RigidBody3D:
	for data: Dictionary in blockers:
		var item: RigidBody3D = data.get("item") as RigidBody3D
		if item == null or not is_instance_valid(item) or item.freeze \
				or NPCItemUser.is_claimed_by_other(item, npc):
			continue
		if NPCItemUser.flat_distance(npc.global_position, item.global_position) \
				<= NPCItemUser.SNATCH_RANGE:
			return item
	return null


static func choose_drop_position(npc: NPC, item: RigidBody3D,
		corridor_start: Vector3, corridor_finish: Vector3) -> Vector3:
	if npc == null or item == null:
		return Vector3.INF
	var travel: Vector3 = corridor_finish - corridor_start
	travel.y = 0.0
	if travel.length_squared() < 0.01:
		travel = -npc.global_transform.basis.z
	travel = travel.normalized()
	var radius: float = footprint_radius(item)
	var offset: float = radius + NPC_RADIUS + 0.75
	var best: Vector3 = Vector3.INF
	var best_cost: float = INF
	## Search a full ring around the resident rather than only five positions
	## around the blocker. A boxed-in NPC may have one small free pocket that is
	## not aligned with the corridor. The target itself must be physically clear;
	## whether it can be walked to is handled separately by the clear activity.
	for angle_index: int in range(16):
		var angle: float = TAU * float(angle_index) / 16.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		for scale: float in [1.0, 1.35, 1.7, 2.1]:
			var requested: Vector3 = npc.global_position + direction * offset * scale
			var candidate: Vector3 = npc.project_navigation_point(requested)
			if NPCItemUser.flat_distance(candidate, requested) > 0.85:
				continue
			if distance_to_segment(candidate, corridor_start, corridor_finish) \
					<= radius + NPC_RADIUS + COMFORT_MARGIN:
				continue
			if not npc.is_object_placement_clear(item, candidate, radius):
				continue
			var cost: float = npc.get_navigation_route_cost(candidate)
			if is_inf(cost):
				continue
			## Prefer side/back staging pockets. A forward pocket can simply move
			## the same obstruction farther down the route.
			var forward_penalty: float = maxf(0.0, direction.dot(travel)) * 3.0
			cost += forward_penalty
			if cost < best_cost:
				best_cost = cost
				best = candidate
	return best
