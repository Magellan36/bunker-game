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

## Jul 2026 fix (notch/step skip bug) — adjacency used to be pure Euclidean
## proximity (see ADJACENCY_RADIUS below, kept only as a historical
## reference/fallback constant, no longer used to build _adjacency). That
## let two wall-face segments on OPPOSITE sides of a multi-corner notch/step
## get linked directly whenever they happened to end up close together in
## world space once pulled inward — a false "shortcut" edge that doesn't
## correspond to any real, unobstructed wall path. find_path_along_wall()'s
## BFS would then jump straight across the notch in one hop, skipping every
## real corner inside it (confirmed symptom: ghost pipe ran a single
## straight leg past a 3-corner notch as if that wall section didn't exist).
##
## Fixed by deriving adjacency from the SAME cleared-cell topology
## WireGraphBuilder already walks to build `boundary_edges`, instead of
## post-hoc distance between the resulting world positions — two wall-face
## entries are real neighbors only if they belong to the same cleared cell
## (a real corner turn within one cell) or to cells that are themselves
## grid-adjacent along the perimeter walk in a way that corresponds to an
## actual wall run or turn. See _cells_are_wall_adjacent() below. A notch's
## two sides are NOT grid-adjacent cells no matter how close they end up in
## world space once pulled inward, so this can't produce a shortcut across
## one.
##
## Each segment entry (set via set_all(), from WireGraphBuilder's
## boundary_edges) now carries, in addition to "pos"/"angle":
##   "cell": Vector2i  — the cleared-cell coordinate this wall face belongs to
##   "dir":  Vector2i  — that face's outward-normal cell-step offset (matches
##                        WireGraphBuilder's own DIRS table: left=(-1,0),
##                        right=(1,0), top=(0,-1), bottom=(0,1))
## Older callers that only ever pass "pos"/"angle" (there are none left in
## this codebase, but defensively) simply produce zero adjacency for that
## segment rather than crashing — see _rebuild_adjacency()'s `has()` guards.


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
		if not (_segments[key_a].has("cell") and _segments[key_a].has("dir")):
			continue   ## defensive — see field-shape comment above _adjacency
		var cell_a: Vector2i = _segments[key_a]["cell"]
		var dir_a:  Vector2i = _segments[key_a]["dir"]
		for key_b: String in keys:
			if key_a == key_b:
				continue
			if not (_segments[key_b].has("cell") and _segments[key_b].has("dir")):
				continue
			var cell_b: Vector2i = _segments[key_b]["cell"]
			var dir_b:  Vector2i = _segments[key_b]["dir"]
			if _cells_are_wall_adjacent(cell_a, dir_a, cell_b, dir_b):
				_adjacency[key_a].append(key_b)


## True if two cell-face entries correspond to a real, unobstructed wall
## connection — see the design comment above _adjacency for the full
## rationale. `dir_a`/`dir_b` are outward-normal cell-step offsets (each is
## one of (-1,0)/(1,0)/(0,-1)/(0,1)); `dot()` between two such offsets is
## 1 for the same direction, 0 for perpendicular, -1 for opposite.
func _cells_are_wall_adjacent(cell_a: Vector2i, dir_a: Vector2i, cell_b: Vector2i, dir_b: Vector2i) -> bool:
	var dot: int = dir_a.x * dir_b.x + dir_a.y * dir_b.y

	if cell_a == cell_b:
		## Same cell, two different exposed faces. Only a real corner turn
		## when the two faces are PERPENDICULAR (e.g. top+left on a convex
		## corner cell) — opposite faces on the same cell (left+right,
		## top+bottom) are two walls facing each other across a single-cell-
		## wide corridor/pocket, never a real direct connection.
		return dot == 0

	if dir_a == dir_b:
		## Same exposed direction on two different cells — only a real
		## straight-wall-run continuation when the other cell is exactly one
		## step away ALONG the wall (perpendicular to the shared outward
		## normal). For a top/bottom face (normal along Z) the run continues
		## along X; for a left/right face (normal along X) the run continues
		## along Z.
		var along: Vector2i
		if dir_a.x != 0:
			along = Vector2i(0, 1)   ## left/right face -> run continues along Z
		else:
			along = Vector2i(1, 0)   ## top/bottom face -> run continues along X
		var delta: Vector2i = cell_b - cell_a
		return delta == along or delta == -along

	if dot == 0:
		## Perpendicular faces on two DIFFERENT cells — only a real corner
		## when the two cells are diagonal neighbors reached by stepping in
		## cell_a's own outward-normal direction and AGAINST cell_b's outward-
		## normal direction (cell_b == cell_a + dir_a - dir_b) — verified by
		## hand against two independent concrete examples (a peninsula's two
		## side corners): e.g. cell_a exposes "top" (dir_a=(0,-1)) at column 9,
		## cell_b is the peninsula cell one column over exposing "left"
		## (dir_b=(-1,0)) — the two face positions sit ~0.707m apart (a real
		## corner gap) and satisfy cell_b - cell_a == dir_a - dir_b == (1,-1).
		## (`dir_a + dir_b` — the first version of this fix — computes the
		## WRONG diagonal cell entirely and silently produces zero adjacency
		## for every real notch/peninsula corner, which is exactly the
		## "route skips the whole notch" symptom this fix targets — a sign
		## bug, not a logic-shape bug.) Any other diagonal or cardinal offset
		## is coincidental proximity, not a real connection.
		return cell_b == cell_a + dir_a - dir_b

	## dot == -1 (opposite directions, different cells) — two parallel walls
	## facing each other across open floor (e.g. a corridor's far side one
	## cell over). Never a real direct connection.
	return false


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


## All segment keys within `radius` of `pos` (XZ plane), nearest first.
## Added Jul 2026 alongside the backward-jog entry-leg fix — a caller
## anchoring onto the wall from an arbitrary point (e.g. a hookup sitting
## almost equidistant between two consecutive segments) needs more than
## just the single absolute-nearest key: picking nearest in isolation can
## land on the segment BEHIND the caller relative to where it actually
## wants to go, forcing a backward hop before find_path_along_wall() turns
## around (see WaterPipeDrawMode._trace_wall_locked_path()'s use of this).
## Returning the small nearby set lets the caller pick whichever candidate
## actually shortens the real path, instead of guessing from position
## alone.
func get_nearby_segment_keys(pos: Vector3, radius: float) -> Array:
	var flat_pos: Vector2 = Vector2(pos.x, pos.z)
	var candidates: Array = []
	for key: String in _segments:
		var seg_pos: Vector3 = _segments[key]["pos"]
		var d: float = flat_pos.distance_to(Vector2(seg_pos.x, seg_pos.z))
		if d <= radius:
			candidates.append({ "key": key, "dist": d })
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var out: Array = []
	for c in candidates:
		out.append(c["key"])
	return out


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
