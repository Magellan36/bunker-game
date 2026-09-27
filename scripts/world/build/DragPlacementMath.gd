extends RefCounted
## Shared modifier math for click-drag build tools. Holding Ctrl constrains the
## XZ bearing to one of eight 45-degree directions while preserving the target
## height. Cardinal and diagonal results remain on the caller's placement grid.

const OCTANT_RADIANS: float = PI / 4.0
const DIRECTION_EPSILON: float = 0.0001

static func octant_direction_xz(origin: Vector3, target: Vector3) -> Vector2:
	var offset := Vector2(target.x - origin.x, target.z - origin.z)
	if offset.length_squared() <= 0.000001:
		return Vector2.ZERO
	var angle: float = atan2(offset.x, offset.y)
	var snapped_angle: float = roundf(angle / OCTANT_RADIANS) * OCTANT_RADIANS
	return Vector2(sin(snapped_angle), cos(snapped_angle))

static func is_xz_octant_aligned(origin: Vector3, target: Vector3) -> bool:
	var offset := Vector2(target.x - origin.x, target.z - origin.z)
	if offset.length_squared() <= 0.000001:
		return false
	var direction: Vector2 = octant_direction_xz(origin, target)
	return absf(offset.normalized().cross(direction)) <= DIRECTION_EPSILON

## Intersects the selected Ctrl octant ray with a finite XZ target segment.
## Parallel/collinear targets use the cursor's projected point on that segment.
## Vector3.INF means the selected bearing never reaches the target run.
static func snap_xz_octant_to_segment(origin: Vector3, target: Vector3,
		segment_a: Vector3, segment_b: Vector3) -> Vector3:
	var ray_direction: Vector2 = octant_direction_xz(origin, target)
	if ray_direction == Vector2.ZERO:
		return Vector3.INF
	var p := Vector2(origin.x, origin.z)
	var q := Vector2(segment_a.x, segment_a.z)
	var segment := Vector2(segment_b.x - segment_a.x, segment_b.z - segment_a.z)
	var denominator: float = ray_direction.cross(segment)
	if absf(denominator) <= DIRECTION_EPSILON:
		if absf((q - p).cross(ray_direction)) > DIRECTION_EPSILON:
			return Vector3.INF
		var segment_length_sq: float = segment.length_squared()
		if segment_length_sq <= 0.000001:
			return Vector3.INF
		var cursor := Vector2(target.x, target.z)
		var along: float = clampf((cursor - q).dot(segment) / segment_length_sq, 0.0, 1.0)
		var collinear_point: Vector2 = q + segment * along
		if (collinear_point - p).dot(ray_direction) < -DIRECTION_EPSILON:
			return Vector3.INF
		return Vector3(collinear_point.x, target.y, collinear_point.y)
	var offset: Vector2 = q - p
	var ray_distance: float = offset.cross(segment) / denominator
	var segment_t: float = offset.cross(ray_direction) / denominator
	if ray_distance < -DIRECTION_EPSILON or segment_t < -DIRECTION_EPSILON or segment_t > 1.0 + DIRECTION_EPSILON:
		return Vector3.INF
	var intersection: Vector2 = p + ray_direction * maxf(0.0, ray_distance)
	return Vector3(intersection.x, target.y, intersection.y)

static func snap_xz_to_octant(origin: Vector3, target: Vector3,
		grid_step: float = 0.0) -> Vector3:
	var offset := Vector2(target.x - origin.x, target.z - origin.z)
	if offset.length_squared() <= 0.000001:
		return target
	var direction: Vector2 = octant_direction_xz(origin, target)
	var distance: float = maxf(0.0, offset.dot(direction))
	if grid_step > 0.0:
		## At diagonals, quantize the equal X/Z component; at cardinals,
		## quantize the sole changing component.
		var dominant: float = maxf(absf(direction.x), absf(direction.y))
		var component: float = roundf((distance * dominant) / grid_step) * grid_step
		distance = component / dominant
	return Vector3(
		origin.x + direction.x * distance,
		target.y,
		origin.z + direction.y * distance)
