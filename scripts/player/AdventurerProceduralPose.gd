class_name AdventurerProceduralPose
extends SkeletonModifier3D
## AdventurerProceduralPose.gd — small runtime pose adjustments layered on top
## of the animated (human-made) clips. Pure code: nothing here is baked into an
## animation, and every adjustment is a weighted correction the controller
## eases in and out.
##
##   foot locking  a foot that touches the floor and stops moving (in world
##                 space) is pinned where it landed; a two-bone leg IK keeps it
##                 there until the animation lifts it again. Removes the last
##                 bit of skating on starts, stops, turns and blends.
##   head_support  nods the neck/head up onto a pillow while lying on a bed.
##                 The sleep clip was performed flat, so without it the head
##                 sinks into the pillow.
##   look          turns neck + head toward a world point (the thing the
##                 character is about to use / talking to), clamped to a
##                 natural range and eased by look_weight.
##   lean_roll     banks the spine into a turn (centripetal lean), radians.
##   lean_pitch    tips the spine forward on acceleration / back on braking.
##
## Added as a child of the body's Skeleton3D by AdventurerModelController,
## which writes the inputs every frame.

## Neck + head nod at full head_support, degrees (split across both bones).
const NECK_SUPPORT_DEG: float = 9.0
const HEAD_SUPPORT_DEG: float = 9.0
## Look-at: largest head turn (radians) and the neck/head split.
const LOOK_MAX_ANGLE: float = 1.05
const LOOK_GIVE_UP_ANGLE: float = 1.9
const LOOK_NECK_SHARE: float = 0.4
## Share of the lean each spine bone takes (bottom to top).
const SPINE_SHARE: Dictionary = {"Spine": 0.4, "Chest": 0.35, "UpperChest": 0.25}

## Foot locking (world metres / seconds).
const LOCK_HEIGHT: float = 0.075        ## ankle within this of the floor = touching
const LOCK_MAX_SPEED: float = 2.2       ## animated ankle slower than this = planted
const LOCK_RELEASE_DIST: float = 0.28   ## animation moved this far away = step
const LOCK_BLEND_IN: float = 0.05
const LOCK_BLEND_OUT: float = 0.14
## Standing still with a foot pinned away from where the idle wants it: after
## SETTLE_DELAY it takes a small lifted recovery step (SETTLE_STEP_TIME long,
## SETTLE_LIFT high) into the idle stance.
const SETTLE_OFFSET: float = 0.12
const SETTLE_DELAY: float = 0.35
const SETTLE_STEP_TIME: float = 0.28
const SETTLE_LIFT: float = 0.07

var head_support: float = 0.0
var look_weight: float = 0.0
var look_at_world: Vector3 = Vector3.ZERO
var lean_roll: float = 0.0
var lean_pitch: float = 0.0
var foot_lock_enabled: bool = false
var floor_y: float = 0.0
## Horizontal speed of the character; below ~0.05 m/s it is standing still.
var body_speed: float = 0.0

class Leg:
	var upper: int = -1
	var lower: int = -1
	var foot: int = -1
	var locked: bool = false
	var lock_pos: Vector3            ## world
	var lock_yaw: float = 0.0        ## world heading of the planted foot
	var weight: float = 0.0
	var settle_timer: float = 0.0
	var stepping: bool = false       ## releasing via a lifted recovery step
	var prev: Vector3
	var has_prev: bool = false

var _neck: int = -1
var _head: int = -1
var _spine: Dictionary = {}   ## bone index -> share
var _legs: Array[Leg] = []

func _skeleton_changed(_old: Skeleton3D, new_skeleton: Skeleton3D) -> void:
	_cache(new_skeleton)

func _cache(sk: Skeleton3D) -> void:
	_spine.clear()
	_legs.clear()
	if sk == null:
		return
	_neck = sk.find_bone("Neck")
	_head = sk.find_bone("Head")
	for bone: String in SPINE_SHARE:
		var i: int = sk.find_bone(bone)
		if i != -1:
			_spine[i] = SPINE_SHARE[bone]
	for side: String in ["Left", "Right"]:
		var leg := Leg.new()
		leg.upper = sk.find_bone(side + "UpperLeg")
		leg.lower = sk.find_bone(side + "LowerLeg")
		leg.foot = sk.find_bone(side + "Foot")
		if leg.upper != -1 and leg.lower != -1 and leg.foot != -1:
			_legs.append(leg)

## Drops any held foot locks (call after a teleport).
func reset_locks() -> void:
	for leg: Leg in _legs:
		leg.locked = false
		leg.weight = 0.0
		leg.has_prev = false
		leg.stepping = false

func _process_modification_with_delta(delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	if _legs.is_empty() and _spine.is_empty():
		_cache(sk)
	if head_support > 0.001:
		## Humanoid bones: local +X rotation lifts the chin (nod up).
		_rotate_local(sk, _neck, Vector3.RIGHT, deg_to_rad(NECK_SUPPORT_DEG) * head_support)
		_rotate_local(sk, _head, Vector3.RIGHT, deg_to_rad(HEAD_SUPPORT_DEG) * head_support)
	if absf(lean_roll) > 0.0001 or absf(lean_pitch) > 0.0001:
		for i: int in _spine:
			var share: float = _spine[i]
			_rotate_local(sk, i, Vector3.BACK, lean_roll * share)
			_rotate_local(sk, i, Vector3.RIGHT, lean_pitch * share)
	if look_weight > 0.001:
		_look(sk)
	for leg: Leg in _legs:
		_foot_lock(sk, leg, delta)

## Humanoid head bones face +Z. Rotate neck then head (skeleton space) by a
## clamped fraction of the arc from the current face direction to the target.
func _look(sk: Skeleton3D) -> void:
	if _head == -1:
		return
	var head_g: Transform3D = sk.get_bone_global_pose(_head)
	var target: Vector3 = sk.global_transform.affine_inverse() * look_at_world
	var face: Vector3 = head_g.basis.z.normalized()
	var want: Vector3 = (target - head_g.origin).normalized()
	var angle: float = face.angle_to(want)
	if angle < 0.001 or angle > LOOK_GIVE_UP_ANGLE:
		return
	var arc := Quaternion(face, want)
	var amount: float = minf(1.0, LOOK_MAX_ANGLE / angle) * look_weight
	if _neck != -1:
		_rotate_skeleton(sk, _neck, Quaternion.IDENTITY.slerp(arc, amount * LOOK_NECK_SHARE))
	_rotate_skeleton(sk, _head, Quaternion.IDENTITY.slerp(arc, amount * (1.0 - LOOK_NECK_SHARE)))

func _foot_lock(sk: Skeleton3D, leg: Leg, delta: float) -> void:
	var xf: Transform3D = sk.global_transform
	var foot_g: Transform3D = xf * sk.get_bone_global_pose(leg.foot)
	var p: Vector3 = foot_g.origin
	var speed: float = p.distance_to(leg.prev) / delta if leg.has_prev and delta > 0.0 else INF
	leg.prev = p
	leg.has_prev = true
	var planted: bool = foot_lock_enabled and p.y - floor_y < LOCK_HEIGHT and speed < LOCK_MAX_SPEED
	var offset: float = Vector2(p.x - leg.lock_pos.x, p.z - leg.lock_pos.z).length()
	if planted and not leg.locked and not leg.stepping:
		leg.locked = true
		leg.lock_pos = p
		leg.lock_yaw = _heading(foot_g.basis)
		leg.settle_timer = 0.0
	elif leg.locked:
		if not planted or offset > LOCK_RELEASE_DIST:
			leg.locked = false
		elif body_speed < 0.05 and offset > SETTLE_OFFSET:
			leg.settle_timer += delta
			if leg.settle_timer > SETTLE_DELAY:
				leg.locked = false
				leg.stepping = true
		else:
			leg.settle_timer = 0.0
	var rate: float = LOCK_BLEND_IN if leg.locked else (SETTLE_STEP_TIME if leg.stepping else LOCK_BLEND_OUT)
	leg.weight = move_toward(leg.weight, 1.0 if leg.locked else 0.0, delta / rate)
	if leg.weight <= 0.001:
		leg.stepping = false
		return
	## Pin horizontally only: height keeps following the clip (heel-toe roll,
	## settling), so a foot caught just before touchdown never hovers. A
	## recovery step lifts the foot on an arc while it travels.
	var pinned := Vector3(leg.lock_pos.x, p.y, leg.lock_pos.z)
	var target: Vector3 = p.lerp(pinned, leg.weight)
	if leg.stepping:
		target.y += SETTLE_LIFT * sin(PI * leg.weight)
	_two_bone_ik(sk, leg, xf.affine_inverse() * target)
	## Keep the foot's heading where it was planted; pitch/roll follow the clip
	## so it still rolls heel-to-toe and settles flat.
	var world_rot: Quaternion = xf.basis.orthonormalized().get_rotation_quaternion()
	var anim_rot: Quaternion = foot_g.basis.orthonormalized().get_rotation_quaternion()
	var yaw_fix: float = 0.0
	if not is_nan(leg.lock_yaw) and not is_nan(_heading(foot_g.basis)):
		yaw_fix = wrapf(leg.lock_yaw - _heading(foot_g.basis), -PI, PI) * leg.weight
	_set_skeleton_rot(sk, leg.foot, world_rot.inverse() * Quaternion(Vector3.UP, yaw_fix) * anim_rot)

## Horizontal heading of the toes (Humanoid foot bones point +Y at the toes).
## NAN while the foot points almost straight down/up (heading undefined).
static func _heading(b: Basis) -> float:
	var toe: Vector3 = b.orthonormalized().y
	if Vector2(toe.x, toe.z).length() < 0.35:
		return NAN
	return atan2(toe.x, toe.z)

## Analytic two-bone IK in skeleton space: bend the knee to the length the
## target needs (in the animated knee's own bend plane), then swing the thigh
## so the ankle points at the target.
static func _two_bone_ik(sk: Skeleton3D, leg: Leg, target: Vector3) -> void:
	var a_pos: Vector3 = sk.get_bone_global_pose(leg.upper).origin
	var b_pos: Vector3 = sk.get_bone_global_pose(leg.lower).origin
	var c_pos: Vector3 = sk.get_bone_global_pose(leg.foot).origin
	var la: float = a_pos.distance_to(b_pos)
	var lb: float = b_pos.distance_to(c_pos)
	var d: float = clampf(a_pos.distance_to(target), absf(la - lb) + 0.001, (la + lb) * 0.999)
	var axis: Vector3 = (a_pos - b_pos).cross(c_pos - b_pos)
	if axis.length_squared() < 1e-10:
		axis = sk.get_bone_global_pose(leg.upper).basis.x
	axis = axis.normalized()
	var current: float = (a_pos - b_pos).angle_to(c_pos - b_pos)
	var wanted: float = acos(clampf((la * la + lb * lb - d * d) / (2.0 * la * lb), -1.0, 1.0))
	_rotate_skeleton(sk, leg.lower, Quaternion(axis, wanted - current))
	var c2: Vector3 = sk.get_bone_global_pose(leg.foot).origin
	var from: Vector3 = (c2 - a_pos).normalized()
	var to: Vector3 = (target - a_pos).normalized()
	if from.dot(to) < 0.99999:
		_rotate_skeleton(sk, leg.upper, Quaternion(from, to))

## Applies a skeleton-space rotation delta to a bone (pre-multiplied).
static func _rotate_skeleton(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var parent: int = sk.get_bone_parent(bone)
	var pr: Quaternion = sk.get_bone_global_pose(parent).basis.get_rotation_quaternion() \
		if parent != -1 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(bone, (pr.inverse() * q * pr * sk.get_bone_pose_rotation(bone)).normalized())

## Sets a bone's skeleton-space rotation.
static func _set_skeleton_rot(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var parent: int = sk.get_bone_parent(bone)
	var pr: Quaternion = sk.get_bone_global_pose(parent).basis.get_rotation_quaternion() \
		if parent != -1 else Quaternion.IDENTITY
	sk.set_bone_pose_rotation(bone, (pr.inverse() * q).normalized())

static func _rotate_local(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone == -1 or absf(angle) < 0.00001:
		return
	sk.set_bone_pose_rotation(bone, sk.get_bone_pose_rotation(bone) * Quaternion(axis, angle))
