class_name WireRoute
extends RefCounted
## Shared deterministic path for preview, placement and cost; never mutates the grid.
const EPSILON: float = 0.001

static func points(a: Vector3, b: Vector3) -> PackedVector3Array:
	var path := PackedVector3Array([a])
	if not is_equal_approx(a.y, b.y):
		var corner := Vector3(b.x, a.y, b.z) if a.y > b.y else Vector3(a.x, b.y, a.z)
		if a.distance_to(corner) > EPSILON and b.distance_to(corner) > EPSILON:
			path.append(corner)
	if a.distance_to(b) > EPSILON:
		path.append(b)
	return path

static func length(path: PackedVector3Array) -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total

static func edge_id(a: String, b: String) -> String:
	return "e_%s__%s" % [a, b] if a < b else "e_%s__%s" % [b, a]

## True only for shared length, not a crossing or an endpoint touch.
static func overlaps(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> bool:
	var axis: Vector3 = b - a
	var span: float = axis.length()
	if span <= EPSILON:
		return false
	axis /= span
	var c_offset: Vector3 = c - a
	var d_offset: Vector3 = d - a
	if (c_offset - axis * c_offset.dot(axis)).length() > EPSILON or (d_offset - axis * d_offset.dot(axis)).length() > EPSILON:
		return false
	var lo: float = minf(c_offset.dot(axis), d_offset.dot(axis))
	var hi: float = maxf(c_offset.dot(axis), d_offset.dot(axis))
	return minf(span, hi) - maxf(0.0, lo) > EPSILON
