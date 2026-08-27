extends SceneTree
## build_sit_male_anim.gd — Aug 2026.
## Bakes the male-only hybrid seated clip: the legs + pelvis are held STATIC
## at stand_to_sit's final (seated) pose, and only the upper body (Spine and
## up, incl. arms/hands/fingers) animates the sit loop. Females keep the full
## sit_lib loop (selected via the existing gender override in the controller).

const SIT_LIB := "res://assets/models/player/anims/sit_lib.res"
const STAND_TO_SIT_LIB := "res://assets/models/player/anims/stand_to_sit_lib.res"
const OUT := "res://assets/models/player/anims/sit_male_lib.res"

func _is_leg_bone(bone: String) -> bool:
	return bone == "Hips" or bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toe")

func _bone_of(path: NodePath) -> String:
	var sub: String = path.get_concatenated_subnames()
	return sub.substr(sub.rfind(":") + 1) if sub.contains(":") else sub

func _init() -> void:
	var sit_lib: AnimationLibrary = load(SIT_LIB)
	var sts_lib: AnimationLibrary = load(STAND_TO_SIT_LIB)
	if sit_lib == null or sts_lib == null:
		print("FAILED to load source libs")
		quit(1)
		return
	var sit: Animation = sit_lib.get_animation("sit")
	var sts: Animation = sts_lib.get_animation("stand_to_sit")

	var out := Animation.new()
	out.length = sit.length
	out.loop_mode = Animation.LOOP_LINEAR

	## Pass 1 — static legs + pelvis, frozen at stand_to_sit's final frame.
	for ti in sts.get_track_count():
		var p: NodePath = sts.track_get_path(ti)
		if not _is_leg_bone(_bone_of(p)):
			continue
		var kc: int = sts.track_get_key_count(ti)
		if kc == 0:
			continue
		var idx: int = out.add_track(sts.track_get_type(ti))
		out.track_set_path(idx, p)
		out.track_set_interpolation_type(idx, sts.track_get_interpolation_type(ti))
		out.track_insert_key(idx, 0.0, sts.track_get_key_value(ti, kc - 1), 0.0)

	## Pass 2 — animated top half from the sit loop.
	for ti in sit.get_track_count():
		var p: NodePath = sit.track_get_path(ti)
		if _is_leg_bone(_bone_of(p)):
			continue
		var idx: int = out.add_track(sit.track_get_type(ti))
		out.track_set_path(idx, p)
		out.track_set_interpolation_type(idx, sit.track_get_interpolation_type(ti))
		for k in sit.track_get_key_count(ti):
			out.track_insert_key(idx, sit.track_get_key_time(ti, k), sit.track_get_key_value(ti, k), sit.track_get_key_transition(ti, k))

	var lib := AnimationLibrary.new()
	lib.add_animation("sit_male", out)
	var err := ResourceSaver.save(lib, OUT)
	print("saved ", OUT, " err=", err, " len=", out.length, " tracks=", out.get_track_count(), " loop=", out.loop_mode)
	quit(0)