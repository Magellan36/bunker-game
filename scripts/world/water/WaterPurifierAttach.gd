extends RefCounted
class_name WaterPurifierAttach
## WaterPurifierAttach.gd
## ─────────────────────────────────────────────────────────────────────────────
## Purifier placement math — candidate-finding + graph insertion for
## TILE_WATER_PURIFIER. DELIBERATELY duplicates WaterPipeDrawMode's
## _closest_point_on_segment_xz() / _split_candidate_for_segment() /
## _find_split_candidate() / _split_pipe_at() shape rather than modifying or
## parameterizing that file — WaterPipeDrawMode.gd has a documented history
## of subtle, hard-won bug fixes (grid-snap artifacts, ghost-preview feedback
## loops) and stays untouched. The one real difference from the pipe split:
## NO grid-snap on the found point — a purifier is placed freely, wherever
## it lands on the pipe's line, no _grid_snap_split_point() call.
##
## Static-only — no state. Called by both GhostPreview._update_ghost()
## (validity + position preview) and BuildModeController._spawn_placed_object()
## (actual insertion on confirm), so there's exactly one copy of this logic
## inside the water system, even though it's independent of WaterPipeDrawMode.

## Reuses WaterPipeDrawMode's own tuning constants by value (independent
## constants, same numbers — water system convention, see WaterPipeDrawMode's
## own header for why constants are duplicated rather than shared here).
const SPLIT_SNAP_RADIUS: float = 0.6
const SPLIT_ENDPOINT_EXCLUDE: float = 0.2
const MIN_POINT_GAP: float = 0.05

## Closest point to `p` on line segment [a, b], compared in the XZ plane only
## (Y taken from `a`) — identical shape to WaterPipeDrawMode._closest_point_
## on_segment_xz().
static func _closest_point_on_segment_xz(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var az: Vector2 = Vector2(a.x, a.z)
	var bz: Vector2 = Vector2(b.x, b.z)
	var pz: Vector2 = Vector2(p.x, p.z)
	var ab: Vector2 = bz - az
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return a
	var t: float = clampf((pz - az).dot(ab) / len_sq, 0.0, 1.0)
	var closest_xz: Vector2 = az + ab * t
	return Vector3(closest_xz.x, a.y, closest_xz.y)

## Builds the {"pos","edge_id","seg_node","key_a","key_b"} shape
## insert_purifier_at() needs, from an already-known segment + point on it.
static func _split_candidate_for_segment(wm: WaterManager, seg: WaterPipeSegment, pos: Vector3) -> Dictionary:
	if seg.edge_id.is_empty() or not wm.has_edge(seg.edge_id):
		return {}
	var edge_data: Dictionary = wm.get_edges().get(seg.edge_id, {})
	if edge_data.is_empty():
		return {}
	return {
		"pos":      pos,
		"edge_id":  seg.edge_id,
		"seg_node": seg,
		"key_a":    edge_data.get("a", ""),
		"key_b":    edge_data.get("b", ""),
	}

## Searches every live WaterPipeSegment (via "water_pipe_visual" group) for
## the closest mid-span point to `cursor_pos` within SPLIT_SNAP_RADIUS,
## excluding points too close to either endpoint. Only horizontal
## (ceiling-height) segments are considered. Returns {} if none found —
## the signal to hide the ghost / reject placement. READ-ONLY.
static func find_purifier_candidate(tree: SceneTree, wm: WaterManager, cursor_pos: Vector3) -> Dictionary:
	if wm == null:
		return {}
	var cursor_xz: Vector2 = Vector2(cursor_pos.x, cursor_pos.z)
	var best_dist: float = SPLIT_SNAP_RADIUS
	var best: Dictionary = {}
	for node: Node in tree.get_nodes_in_group("water_pipe_visual"):
		if not is_instance_valid(node) or not (node is WaterPipeSegment):
			continue
		var seg: WaterPipeSegment = node as WaterPipeSegment
		if absf(seg.point_a.y - seg.point_b.y) > MIN_POINT_GAP:
			continue
		var closest: Vector3 = _closest_point_on_segment_xz(cursor_pos, seg.point_a, seg.point_b)
		var d: float = Vector2(closest.x, closest.z).distance_to(cursor_xz)
		if d >= best_dist:
			continue
		if closest.distance_to(seg.point_a) < SPLIT_ENDPOINT_EXCLUDE:
			continue
		if closest.distance_to(seg.point_b) < SPLIT_ENDPOINT_EXCLUDE:
			continue
		var candidate: Dictionary = _split_candidate_for_segment(wm, seg, closest)
		if candidate.is_empty():
			continue
		best_dist = d
		best = candidate
	return best

## MUTATES the graph: splits the candidate's existing pipe edge at
## candidate["pos"], registers a "purifier" node there, spawns the
## WaterPurifier visual + two new WaterPipeSegments (old_a<->purifier,
## purifier<->old_b). Returns the spawned WaterPurifier node, or null on
## failure (candidate stale / nodes missing).
static func insert_purifier_at(scene_root: Node, wm: WaterManager, candidate: Dictionary) -> WaterPurifier:
	var old_edge_id: String  = candidate.get("edge_id", "")
	var key_a:       String  = candidate.get("key_a", "")
	var key_b:       String  = candidate.get("key_b", "")
	var seg_node:    WaterPipeSegment = candidate.get("seg_node", null)
	var split_pos:   Vector3 = candidate.get("pos", Vector3.ZERO)

	if not (wm.has_water_node(key_a) and wm.has_water_node(key_b)):
		return null

	var pos_a: Vector3 = wm.get_node_data(key_a).get("pos", Vector3.ZERO)
	var pos_b: Vector3 = wm.get_node_data(key_b).get("pos", Vector3.ZERO)

	wm.unregister_edge(old_edge_id)
	if seg_node != null and is_instance_valid(seg_node):
		seg_node.queue_free()

	var new_key: String = wm.register_node(split_pos, "purifier")

	var purifier: WaterPurifier = WaterPurifier.new()
	scene_root.add_child(purifier)
	purifier.global_position = split_pos
	purifier.node_key = new_key
	purifier.orient_along(pos_a, pos_b)
	## Purifier Filter plan (Jul 2026) — two fresh starting filters, dropped
	## nearby (see WaterPurifier.spawn_starting_filters()'s own comment).
	purifier.spawn_starting_filters()

	var edge_a: String = wm.register_edge(key_a, new_key)
	if not edge_a.is_empty():
		var seg_a: WaterPipeSegment = WaterPipeSegment.new()
		scene_root.add_child(seg_a)
		seg_a.edge_id = edge_a
		seg_a.set_endpoints(pos_a, split_pos)

	var edge_b: String = wm.register_edge(new_key, key_b)
	if not edge_b.is_empty():
		var seg_b: WaterPipeSegment = WaterPipeSegment.new()
		scene_root.add_child(seg_b)
		seg_b.edge_id = edge_b
		seg_b.set_endpoints(split_pos, pos_b)

	wm.recompute_flow_directions()
	return purifier
