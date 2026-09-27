extends RefCounted
class_name WallSnapHelpers
## Shared surface snapping for wall fixtures and drawn-wall junctions. Cardinal
## rays cover pre-generated geometry; perpendicular rays cover player walls.
## The surface normal determines rotation and offset. Local wall end caps are
## rejected, and original perimeter walls retain their interior-only bounds test.
## Electrical connections are handled separately by the devices.

var _owner: BuildModeController = null

const WALL_RUN_SNAP_RANGE: float = 0.65
const WALL_RUN_JUNCTION_EPSILON: float = 0.02

func _init(owner: BuildModeController) -> void:
	_owner = owner


## Resolve a wall-draw anchor against the centre line of the nearest registered
## wall run. Unlike fixture snapping this is registry based: drawn walls need
## exact, deterministic junction geometry at both ends, not a physics ray whose
## result can change with collider import order. The returned `walls` array
## includes adjacent one-metre perimeter segments that share the same junction,
## allowing a new wall to meet cleanly on a seam between generated segments.
func _snap_wall_run_point(base_pos: Vector3,
		snap_range: float = WALL_RUN_SNAP_RANGE) -> Dictionary:
	var cursor := Vector2(base_pos.x, base_pos.z)
	var best_distance: float = snap_range
	var best_node: Node3D = null
	var best_pos := Vector2.ZERO
	var best_at_cap: bool = false
	var best_normal := Vector2.ZERO
	var best_is_pillar: bool = false
	var best_run_start := Vector2.ZERO
	var best_run_end := Vector2.ZERO

	for entry: Dictionary in _owner._placed_objects:
		var tile_id: int = int(entry.get("tile_id", -1))
		if tile_id not in _owner.WALL_DRAW_TILES:
			continue
		var wall: Node3D = entry.get("node") as Node3D
		if not is_instance_valid(wall):
			continue
		var center3: Vector3 = entry.get("world_pos", wall.global_position)
		var center := Vector2(center3.x, center3.z)
		var half_extent: Vector2 = entry.get("footprint", _owner._tile_half_extents(tile_id))
		var angle_rad: float = deg_to_rad(float(entry.get("angle_deg", wall.rotation_degrees.y)))
		var width_axis := Vector2(cos(angle_rad), -sin(angle_rad))
		var run_axis := Vector2(sin(angle_rad), cos(angle_rad))
		var along: float = clampf((cursor - center).dot(run_axis), -half_extent.y, half_extent.y)
		var candidate: Vector2 = center + run_axis * along
		var distance: float = cursor.distance_to(candidate)
		if distance <= best_distance:
			best_distance = distance
			best_node = wall
			best_pos = candidate
			best_at_cap = absf(along) >= half_extent.y - WALL_RUN_JUNCTION_EPSILON
			var side: float = signf((cursor - center).dot(width_axis))
			if is_zero_approx(side):
				var plus_inside: bool = _owner._is_inside_bunker(Vector3(
					center.x + width_axis.x * 0.35, base_pos.y,
					center.y + width_axis.y * 0.35))
				var minus_inside: bool = _owner._is_inside_bunker(Vector3(
					center.x - width_axis.x * 0.35, base_pos.y,
					center.y - width_axis.y * 0.35))
				if plus_inside != minus_inside:
					side = 1.0 if plus_inside else -1.0
				elif is_instance_valid(_owner.camera):
					var camera_xz := Vector2(_owner.camera.global_position.x, _owner.camera.global_position.z)
					side = 1.0 if (camera_xz - center).dot(width_axis) >= 0.0 else -1.0
				else:
					side = 1.0
			best_normal = width_axis * side
			best_is_pillar = false
			best_run_start = center - run_axis * half_extent.y
			best_run_end = center + run_axis * half_extent.y

	## Pillars expose four discrete wall sockets: the centre of each outer side.
	## They deliberately compete in the same nearest-candidate pass as walls so
	## corners feel identical regardless of which structural target is hovered.
	for entry: Dictionary in _owner._placed_objects:
		if int(entry.get("tile_id", -1)) != _owner.TILE_PILLAR:
			continue
		var pillar: Node3D = entry.get("node") as Node3D
		if not is_instance_valid(pillar):
			continue
		var center3: Vector3 = entry.get("world_pos", pillar.global_position)
		var center := Vector2(center3.x, center3.z)
		var half_extent: Vector2 = entry.get("footprint",
			_owner._tile_half_extents(_owner.TILE_PILLAR))
		var angle_rad: float = deg_to_rad(float(entry.get("angle_deg", pillar.rotation_degrees.y)))
		var x_axis := Vector2(cos(angle_rad), -sin(angle_rad))
		var z_axis := Vector2(sin(angle_rad), cos(angle_rad))
		for side_data: Dictionary in [
			{"normal": x_axis, "extent": half_extent.x},
			{"normal": -x_axis, "extent": half_extent.x},
			{"normal": z_axis, "extent": half_extent.y},
			{"normal": -z_axis, "extent": half_extent.y},
		]:
			var normal: Vector2 = side_data["normal"]
			var candidate: Vector2 = center + normal * float(side_data["extent"])
			var distance: float = cursor.distance_to(candidate)
			if distance <= best_distance:
				best_distance = distance
				best_node = pillar
				best_pos = candidate
				best_at_cap = true
				best_normal = normal
				best_is_pillar = true
				best_run_start = candidate
				best_run_end = candidate

	if best_node == null:
		return {}

	var supporting_walls: Array[Node3D] = []
	for entry: Dictionary in _owner._placed_objects:
		var tile_id: int = int(entry.get("tile_id", -1))
		if tile_id not in _owner.WALL_DRAW_TILES and tile_id != _owner.TILE_PILLAR:
			continue
		var wall: Node3D = entry.get("node") as Node3D
		if not is_instance_valid(wall):
			continue
		var center3: Vector3 = entry.get("world_pos", wall.global_position)
		var center := Vector2(center3.x, center3.z)
		var half_extent: Vector2 = entry.get("footprint", _owner._tile_half_extents(tile_id))
		var angle_rad: float = deg_to_rad(float(entry.get("angle_deg", wall.rotation_degrees.y)))
		if tile_id == _owner.TILE_PILLAR:
			var x_axis := Vector2(cos(angle_rad), -sin(angle_rad))
			var z_axis := Vector2(sin(angle_rad), cos(angle_rad))
			var touches_socket: bool = false
			for socket: Vector2 in [
				center + x_axis * half_extent.x,
				center - x_axis * half_extent.x,
				center + z_axis * half_extent.y,
				center - z_axis * half_extent.y,
			]:
				if socket.distance_to(best_pos) <= WALL_RUN_JUNCTION_EPSILON:
					touches_socket = true
					break
			if touches_socket:
				supporting_walls.append(wall)
			continue
		var run_axis := Vector2(sin(angle_rad), cos(angle_rad))
		var along: float = clampf((best_pos - center).dot(run_axis), -half_extent.y, half_extent.y)
		var nearest: Vector2 = center + run_axis * along
		if nearest.distance_to(best_pos) <= WALL_RUN_JUNCTION_EPSILON:
			supporting_walls.append(wall)

	return {
		"pos": Vector3(best_pos.x, base_pos.y, best_pos.y),
		"wall": best_node,
		"walls": supporting_walls,
		"at_cap": best_at_cap,
		"normal": Vector3(best_normal.x, 0.0, best_normal.y),
		"target_kind": "pillar" if best_is_pillar else "wall",
		"run_start": Vector3(best_run_start.x, base_pos.y, best_run_start.y),
		"run_end": Vector3(best_run_end.x, base_pos.y, best_run_end.y),
	}


func _pillar_wall_snap_points(y: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for entry: Dictionary in _owner._placed_objects:
		if int(entry.get("tile_id", -1)) != _owner.TILE_PILLAR:
			continue
		var pillar: Node3D = entry.get("node") as Node3D
		if not is_instance_valid(pillar):
			continue
		var center3: Vector3 = entry.get("world_pos", pillar.global_position)
		var half_extent: Vector2 = entry.get("footprint",
			_owner._tile_half_extents(_owner.TILE_PILLAR))
		var angle_rad: float = deg_to_rad(float(entry.get("angle_deg", pillar.rotation_degrees.y)))
		var x_axis := Vector2(cos(angle_rad), -sin(angle_rad))
		var z_axis := Vector2(sin(angle_rad), cos(angle_rad))
		for offset: Vector2 in [
			x_axis * half_extent.x, -x_axis * half_extent.x,
			z_axis * half_extent.y, -z_axis * half_extent.y,
		]:
			var socket := Vector2(center3.x + offset.x, center3.z + offset.y)
			if not _pillar_socket_has_wall(socket):
				points.append(Vector3(socket.x, y, socket.y))
	return points


## A blue socket is an availability indicator, not decoration. Hide it as soon
## as any registered wall footprint covers that side point. Both pregenerated
## and player walls live in _placed_objects, so this deliberately does not
## inspect player_placed.
func _pillar_socket_has_wall(socket: Vector2) -> bool:
	const TOUCH_EPSILON: float = 0.04
	for entry: Dictionary in _owner._placed_objects:
		var tile_id: int = int(entry.get("tile_id", -1))
		if tile_id not in _owner.WALL_DRAW_TILES:
			continue
		var wall: Node3D = entry.get("node") as Node3D
		if not is_instance_valid(wall):
			continue
		var center3: Vector3 = entry.get("world_pos", wall.global_position)
		var center := Vector2(center3.x, center3.z)
		var half_extent: Vector2 = entry.get("footprint", _owner._tile_half_extents(tile_id))
		var angle_rad: float = deg_to_rad(float(entry.get("angle_deg", wall.rotation_degrees.y)))
		var width_axis := Vector2(cos(angle_rad), -sin(angle_rad))
		var run_axis := Vector2(sin(angle_rad), cos(angle_rad))
		var relative: Vector2 = socket - center
		if (absf(relative.dot(width_axis)) <= half_extent.x + TOUCH_EPSILON
				and absf(relative.dot(run_axis)) <= half_extent.y + TOUCH_EPSILON):
			return true
	return false


func _wall_run_snap_nodes(snap: Dictionary) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for value: Variant in snap.get("walls", []):
		var node: Node3D = value as Node3D
		if is_instance_valid(node) and not nodes.has(node):
			nodes.append(node)
	return nodes


## Exact support nodes may be ignored by placement occupancy only when the
## geometry is a junction, never when a proposed run would overlay the middle
## of an existing wall.
func _wall_run_junctions_are_valid(start_snap: Dictionary, end_snap: Dictionary,
		run_direction: Vector3) -> bool:
	if run_direction.length_squared() <= 0.000001:
		return false
	var start_nodes: Array[Node3D] = _wall_run_snap_nodes(start_snap)
	var end_nodes: Array[Node3D] = _wall_run_snap_nodes(end_snap)
	for node: Node3D in start_nodes:
		if end_nodes.has(node):
			return false
	var direction: Vector3 = run_direction.normalized()
	for snap: Dictionary in [start_snap, end_snap]:
		var wall: Node3D = snap.get("wall") as Node3D
		if not is_instance_valid(wall) or bool(snap.get("at_cap", false)):
			continue
		if absf(direction.dot(wall.global_basis.z.normalized())) > 0.999:
			return false
	return true


## All fixtures share face detection; breakers expose their front on local +Z.
func _snap_light_to_wall(base_pos: Vector3) -> Dictionary:
	return _snap_to_nearest_wall(base_pos, 1.5, _owner.LIGHT_WALL_HALF_THICKNESS,
		_owner.LIGHT_WALL_SNAP_RANGE)


func _snap_breaker_to_wall(base_pos: Vector3) -> Dictionary:
	var result: Dictionary = _snap_to_nearest_wall(base_pos, 0.22, 0.07,
		_owner.LIGHT_WALL_SNAP_RANGE)
	if not result.is_empty():
		result["angle_deg"] = fposmod(float(result["angle_deg"]) + 180.0, 360.0)
	return result


## Cast perpendicular to each placed wall as well as the original cardinal rays.
## This keeps the full snap range at arbitrary angles, including short wall runs.
func _wall_cast_directions() -> Array[Vector3]:
	var directions: Array[Vector3] = [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]
	for entry: Dictionary in _owner._placed_objects:
		if not int(entry.get("tile_id", -1)) in _owner.WALL_DRAW_TILES:
			continue
		var wall: Node3D = entry.get("node") as Node3D
		if not is_instance_valid(wall):
			continue
		var normal: Vector3 = wall.global_basis.x.normalized()
		if not directions.any(func(d: Vector3) -> bool: return absf(d.dot(normal)) > 0.99999):
			directions.append(normal)
			directions.append(-normal)
	return directions


## Wall runs are thin on local X and long on local Z. Only +/-X faces mount
## fixtures; +/-Z end caps and horizontal faces are never attachment surfaces.
func _is_wall_broad_face(node: Node, normal: Vector3) -> bool:
	if node is Node3D and int(node.get_meta("tile_id", -1)) in _owner.WALL_DRAW_TILES:
		return absf(normal.dot((node as Node3D).global_basis.x.normalized())) > 0.99
	return true


## Returns true if the hit point + hit normal represent a valid interior-facing
## surface of a pregen bunker boundary wall.
##
## The pregen bunker is a rectangle defined by:
##   X ∈ [OFFSET_X,  OFFSET_X + bunker_depth]
##   Z ∈ [OFFSET_Z,  OFFSET_Z + bunker_width]
##
## Each of the four boundary edges has exactly one valid inward-pointing normal:
##   Left wall   (x ≈ OFFSET_X):             normal must be ≈ +X
##   Right wall  (x ≈ OFFSET_X + depth):     normal must be ≈ -X
##   Front wall  (z ≈ OFFSET_Z):             normal must be ≈ +Z
##   Back wall   (z ≈ OFFSET_Z + width):     normal must be ≈ -Z
##
## A side face (end of a wall cell) or exterior face has a normal that won't
## match the expected inward normal for the nearest boundary — so it's rejected.
## This prevents breakers from snapping to the sides or exterior of pregen walls.
##
## _is_pregen_interior_face — only accept hits on the inward-facing face of a
## pregen boundary wall.  Corner geometry used to bleed through because a hit
## near a corner is within tolerance of TWO boundary edges simultaneously; the
## old code accepted it for whichever edge's normal matched first, which could
## be the wrong axis (e.g. Z-face of the right wall's corner pillar passing the
## back-wall Z-boundary check).
##
## Fix: find the SINGLE closest boundary, then only test that boundary's normal.
## This means a corner pillar Z-face will only be accepted if the Z-boundary is
## closer than the X-boundary — which it isn't for a right-wall corner hit.
func _is_pregen_interior_face(hit_pos: Vector3, hit_normal: Vector3) -> bool:
	if _owner.rock_surround == null:
		return true   ## No bounds data — allow

	## Tightened from 0.75 → 0.55 to reduce tolerance to just the wall thickness.
	## Must be > 0 (physics skin) but small enough that the corner pillar face on
	## one axis doesn't bleed into the adjacent boundary's tolerance zone.
	const WALL_FACE_TOL: float  = 0.55
	const NORMAL_DOT_MIN: float = 0.85   ## cos(≈32°) — must be nearly axis-aligned

	var ox: float    = _owner.rock_surround.OFFSET_X
	var oz: float    = _owner.rock_surround.OFFSET_Z
	var depth: float = float(_owner.rock_surround.bunker_depth)
	var width: float = float(_owner.rock_surround.bunker_width)

	## ── Pass 1: original four perimeter faces ─────────────────────────────
	## Compute distance from hit to each of the four boundary edge planes.
	var dist_left:  float = absf(hit_pos.x - ox)
	var dist_right: float = absf(hit_pos.x - (ox + depth))
	var dist_front: float = absf(hit_pos.z - oz)
	var dist_back:  float = absf(hit_pos.z - (oz + width))

	## Build a candidate list: only boundaries within tolerance.
	## We then pick the CLOSEST one and test only its expected inward normal.
	## This prevents a corner hit from matching the wrong axis's boundary.
	var best_dist:   float   = WALL_FACE_TOL + 1.0   ## sentinel > TOL
	var best_normal: Vector3 = Vector3.ZERO

	if dist_left <= WALL_FACE_TOL and dist_left < best_dist:
		best_dist   = dist_left
		best_normal = Vector3(1, 0, 0)   ## interior faces +X

	if dist_right <= WALL_FACE_TOL and dist_right < best_dist:
		best_dist   = dist_right
		best_normal = Vector3(-1, 0, 0)  ## interior faces -X

	if dist_front <= WALL_FACE_TOL and dist_front < best_dist:
		best_dist   = dist_front
		best_normal = Vector3(0, 0, 1)   ## interior faces +Z

	if dist_back <= WALL_FACE_TOL and dist_back < best_dist:
		best_dist   = dist_back
		best_normal = Vector3(0, 0, -1)  ## interior faces -Z

	if best_normal != Vector3.ZERO:
		## Accept only if the hit normal aligns with the inward direction.
		return hit_normal.dot(best_normal) >= NORMAL_DOT_MIN

	## No boundary within tolerance — this function is now ONLY ever called
	## for _is_true_pregen walls (the original 4 boundary walls + raw GridMap
	## geometry), which always lie exactly on one of the 4 planes above. If we
	## get here, something is wrong (or rock_surround's bunker_depth/width
	## don't match the actual pregen rectangle) — reject rather than guess.
	##
	## HISTORY: this used to fall through to a second pass here that walked
	## RockSurround's 4×4-cell chunk grid to validate autofill/expanded-area
	## walls (any wall NOT on the original 4 planes). That heuristic assumed
	## every expanded wall's solid neighbour sat exactly one chunk-width away,
	## which breaks for excavations deeper than one chunk and has the same
	## corner axis-ambiguity Pass 1 above was fixed for — producing the
	## "some expanded walls don't snap, or snap 90° rotated" bug (July 2026).
	## Fix: autofill walls no longer route through this function at all (see
	## _snap_light_to_wall/_snap_breaker_to_wall's is_true_pregen gate above,
	## and BuildModeController.spawn_structure()'s is_true_pregen param) — they
	## rely on the dig solver (WireGraphBuilder.gd) having already placed them
	## correctly, same as player-placed walls do.
	return false


## Find the nearest valid face at base_pos.y + cast_y_offset.
## Preserve base Y and pull away from the surface by the fixture's back depth.
## Return the supporting wall, position and yaw (local -Z faces into the room).
func _snap_to_nearest_wall(base_pos: Vector3, cast_y_offset: float,
		pullback_dist: float, snap_range: float) -> Dictionary:
	var origin: Vector3 = Vector3(base_pos.x, base_pos.y + cast_y_offset, base_pos.z)

	var directions: Array[Vector3] = _wall_cast_directions()

	var space: PhysicsDirectSpaceState3D = _owner.get_world_3d().direct_space_state
	var player: Node3D = _owner.get_parent()
	var best_dist: float        = snap_range
	var best_result: Dictionary = {}
	var best_is_true_pregen: bool = false

	for dir: Vector3 in directions:
		var to_pt: Vector3 = origin + dir * snap_range

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to_pt)
		query.collision_mask = 5
		if player.has_method("get_rid"):
			query.exclude = [player.get_rid()]

		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue

		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
		if hit_normal.dot(dir) >= 0.0:
			continue   ## Not an interior-facing surface — skip

		var is_wall: bool        = false
		var is_true_pregen: bool = false
		var node: Node = hit.get("collider")
		while node != null:
			if node.has_meta("tile_id"):
				var tid: int = node.get_meta("tile_id")
				if BunkerStructure.is_wall_or_pillar(tid) or tid in _owner.WALL_DRAW_TILES:
					is_wall = true
					is_true_pregen = node.has_meta("_is_true_pregen")
				break
			if node is GridMap:
				is_wall = true
				is_true_pregen = true
				break
			node = node.get_parent()
		if not is_wall:
			continue
		if not _is_wall_broad_face(node, hit_normal):
			continue

		if is_true_pregen and _owner.rock_surround != null:
			if not _is_pregen_interior_face(hit["position"], hit_normal):
				continue

		var hit_dist: float = origin.distance_to(hit["position"])
		if hit_dist < best_dist:
			best_dist = hit_dist
			var snapped_xz: Vector3 = hit["position"] + hit_normal * pullback_dist
			best_result = {
				"wall": node,
				"pos":       Vector3(snapped_xz.x, base_pos.y, snapped_xz.z),
				"angle_deg": fposmod(rad_to_deg(atan2(-hit_normal.x, -hit_normal.z)), 360.0),
			}
			best_is_true_pregen = is_true_pregen

	if not best_result.is_empty() and _owner.rock_surround != null and best_is_true_pregen:
		if not _owner._is_inside_bunker(best_result["pos"]):
			return {}

	return best_result
