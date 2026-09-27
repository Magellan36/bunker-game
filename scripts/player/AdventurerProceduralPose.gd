class_name AdventurerProceduralPose
extends SkeletonModifier3D
## AdventurerProceduralPose.gd — small runtime pose adjustments layered on top
## of the animated (human-made) clips. Pure code: nothing here is baked into an
## animation, and every adjustment is a weighted rotation the controller eases
## in and out.
##
##   head_support  nods the neck/head up onto a pillow while lying on a bed.
##                 The sleep clip was performed flat, so without it the head
##                 sinks into the pillow.
##   lean_roll     banks the spine into a turn (centripetal lean), radians.
##   lean_pitch    tips the spine forward on acceleration / back on braking.
##
## Added as a child of the body's Skeleton3D by AdventurerModelController,
## which writes the three inputs every frame.

## Neck + head nod at full head_support, degrees (split across both bones).
const NECK_SUPPORT_DEG: float = 9.0
const HEAD_SUPPORT_DEG: float = 9.0
## Share of the lean each spine bone takes (bottom to top).
const SPINE_SHARE: Dictionary = {"Spine": 0.4, "Chest": 0.35, "UpperChest": 0.25}

var head_support: float = 0.0
var lean_roll: float = 0.0
var lean_pitch: float = 0.0

var _neck: int = -1
var _head: int = -1
var _spine: Dictionary = {}   ## bone index -> share

func _skeleton_changed(_old: Skeleton3D, new_skeleton: Skeleton3D) -> void:
	_cache(new_skeleton)

func _cache(sk: Skeleton3D) -> void:
	_spine.clear()
	if sk == null:
		return
	_neck = sk.find_bone("Neck")
	_head = sk.find_bone("Head")
	for bone: String in SPINE_SHARE:
		var i: int = sk.find_bone(bone)
		if i != -1:
			_spine[i] = SPINE_SHARE[bone]

func _process_modification_with_delta(_delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	if _neck == -1 and _head == -1 and _spine.is_empty():
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

static func _rotate_local(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone == -1 or absf(angle) < 0.00001:
		return
	sk.set_bone_pose_rotation(bone, sk.get_bone_pose_rotation(bone) * Quaternion(axis, angle))
