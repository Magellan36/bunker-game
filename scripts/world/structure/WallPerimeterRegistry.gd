extends Node
class_name WallPerimeterRegistry
## WallPerimeterRegistry.gd  —  Part C (wall-locked pipe routing, Jul 2026)
## ─────────────────────────────────────────────────────────────────────────────
## Sibling to PillarRegistry.gd (Part A structure refactor), same ownership
## shape: MainWorld instances one, adds it to the scene tree tagged group
## "wall_perimeter_registry" BEFORE add_child(), any consumer finds it via
## `get_tree().get_first_node_in_group("wall_perimeter_registry")`.
##
## Kept as its own file rather than merged into PillarRegistry — pillars are
## point corners, wall segments carry position AND orientation/adjacency,
## different enough data shape to keep separate (matches Part A's own stated
## principle of narrow scope per registry).
##
## Populated by WireGraphBuilder.gd every time it recomputes `boundary_edges`
## (initial pregen solve + every incremental chunk dig/restore) — the exact
## same trigger points PillarRegistry already uses. `boundary_edges` was
## already being computed there for the electrical auto-wire perimeter; this
## just also records it here so a wall-locked pipe router can query it,
## instead of re-deriving wall topology from scratch.
##
## Consumer: WaterPipeDrawMode.gd's wall-locked routing default (see
## WALL_LOCKED_ROUTING_ENABLED in that file) — used only when a pipe run's
## destination resolves to open floor space (no existing node/pipe nearby);
## an anchored destination (existing node, mid-span split) keeps using the
## pre-existing direct-leg routing, since it's already a real connection
## point, not open space.

## key ("wx_key,wz_key", same string format WireGraphBuilder/PillarRegistry
## use) -> Vector3 world position. Y here is WireGraphBuilder's own
## electrical PLACEMENT_Y (2.0) — NOT water's ceiling height. Consumers must
## re-project to their own working height (WaterPipeDrawMode.WATER_CEILING_Y)
## before using a returned position; this registry only stores wall-segment
## XZ topology, not a height convention of its own.
var _segments: Dictionary = {}

## key -> Array[String] of adjacent segment keys, rebuilt fully on every
## set_all() (segment count is small — one entry per perimeter cell-face —
## so an O(n^2) full rebuild is cheap and simplest to reason about; no
## incremental adjacency bookkeeping needed).
var _adjacency: Dictionary = {}

## WireGraphBuilder places one boundary-edge entry per cleared-cell face at
## that cell's own center ± 0.5 — i.e. consecutive segments along a straight
## wall run are exactly 1.0m apart, and the two segments meeting at a convex
## corner are ~0.707m apart (0.5 diagonal). 1.1 catches both real-adjacency
## cases with margin, while staying well under 2.0 (the minimum possible gap
## between two unrelated, non-adjacent walls e.g. opposite sides of a
## single-cell-wide corridor), so it can never wrongly bridge across open
## floor space.
const ADJACENCY_RADIUS: float = 1.1


## Replaces the full wall-segment set. Called by WireGraphBuilder.gd right
## after it finishes computing `boundary_edges` for a given solve pass (same
## call site as _push_pillar_registry(), see that function's own comment).
func set_all(segments: Dictionary) -> void:
	_segments = segments.duplicate()
	_rebuild_adjacency()


func _rebuild_adjacency() -> void:
	_adjacency.clear()
	var keys: Array = _segments.keys()
	for key_a: String in keys:
		_adjacency[key_a] = []
		var pos_a: Vector3 = _segments[key_a]["pos"]
		for key_b: String in keys:
			if key_a == key_b:
				continue
			var pos_b: Vector3 = _segments[key_b]["pos"]
			if pos_a.distance_to(pos_b) <= ADJACENCY_RADIUS:
				_adjacency[key_a].append(key_b)


## Nearest registered wall-segment key to an arbitrary world position
## (compared in the XZ plane only, mirroring every other water-tool snap
## check in this system) — used to anchor a route's start (near the pipe's
## current source point) and end (near wherever the cursor/destination
## currently resolves to).
func get_nearest_segment_key(pos: Vector3) -> String:
	var best_key: String = ""
	var best_dist: float = INF
	var flat_pos: Vector2 = Vector2(pos.x, pos.z)
	for key: String in _segments:
		var seg_pos: Vector3 = _segments[key]["pos"]
		var d: float = flat_pos.distance_to(Vector2(seg_pos.x, seg_pos.z))
		if d < best_dist:
			best_dist = d
			best_key = key
	return best_key


func get_segment_pos(key: String) -> Vector3:
	return _segments.get(key, {}).get("pos", Vector3.ZERO)


## Wall face's outward-facing orientation in degrees, straight from
## WireGraphBuilder's DIRS table (left->180, right->0, top->90, bottom->270).
## Used by wall-locked pipe routing to pull segments inward off the wall
## face (see WaterPipeDrawMode._trace_wall_locked_path()) — electrical wires
## sit flush on the wall so never needed this, pipes do.
func get_segment_angle(key: String) -> float:
	return _segments.get(key, {}).get("angle", 0.0)


func is_empty() -> bool:
	return _segments.is_empty()


## BFS shortest path (by hop count) along the wall perimeter, from_key to
## to_key. Returns Array[String] of ordered segment KEYS (changed from raw
## positions, Jul 2026 wall-embedding fix — callers need both position AND
## angle per waypoint to pull pipes inward off the wall face, so handing
## back keys lets them call get_segment_pos()/get_segment_angle() per point
## instead of this function baking in position-only output). Empty array if
## no path exists — shouldn't happen for a single connected perimeter, but a
## disconnected/degenerate boundary_edges state should fail safely (caller
## falls back to direct-leg routing), not crash.
func find_path_along_wall(from_key: String, to_key: String) -> Array:
	if from_key.is_empty() or to_key.is_empty():
		return []
	if not _adjacency.has(from_key) or not _adjacency.has(to_key):
		return []
	if from_key == to_key:
		return [from_key]

	var came_from: Dictionary = {}
	var visited: Dictionary = {from_key: true}
	var queue: Array = [from_key]
	var found: bool = false
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == to_key:
			found = true
			break
		for neighbor: String in _adjacency.get(current, []):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			came_from[neighbor] = current
			queue.append(neighbor)

	if not found:
		return []

	var path_keys: Array = [to_key]
	var walk: String = to_key
	while walk != from_key:
		walk = came_from[walk]
		path_keys.push_front(walk)

	return path_keys
