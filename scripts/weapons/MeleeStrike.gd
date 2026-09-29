extends RefCounted
## Shared melee target query (weapons and fists): everything inside `reach`,
## within `half_angle` of `direction`, with clear line of sight, once each.
## Returns ray hit dictionaries (position, normal, collider).

static func find(world: World3D, origin: Vector3, direction: Vector3, reach: float,
		half_angle: float, exclude: Array[RID], mask: int) -> Array[Dictionary]:
	var shape := SphereShape3D.new()
	shape.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = origin
	query.collision_mask = mask
	query.exclude = exclude
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var hits: Array[Dictionary] = []
	var seen: Dictionary = {}
	for candidate: Dictionary in space.intersect_shape(query, 32):
		var body: Node3D = candidate.collider as Node3D
		if body == null or seen.has(body.get_instance_id()):
			continue
		var target: Vector3 = body.global_position
		if body is CharacterBody3D:
			target.y = origin.y
		var offset: Vector3 = target - origin
		if offset.length_squared() < 0.001 or offset.length() > reach:
			continue
		if direction.dot(offset.normalized()) < cos(deg_to_rad(half_angle)):
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, target, mask, exclude)
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty() or hit.collider != body:
			continue
		seen[body.get_instance_id()] = true
		hits.append(hit)
	return hits

## Walks up from the collider to the first node implementing receive_weapon_hit.
static func deliver(context: Dictionary) -> Node:
	var receiver: Node = context.collider as Node
	while receiver != null and not receiver.has_method("receive_weapon_hit"):
		receiver = receiver.get_parent()
	if receiver != null:
		receiver.call("receive_weapon_hit", context)
	return receiver
