extends "res://tools/anim_pipeline/bake_adventurer_anims.gd"
## Reuses the canonical retarget/conversion/measurement pipeline, without
## rebaking or modifying the shared locomotion/furniture libraries.
const PISTOL_CLIPS: Array[String] = ["idle", "walk", "run", "walk_backward", "run_backward", "strafe_left", "strafe_right"]
## The FEMALE pack's FBX export dropped every leaf bone's rotation (the rig has
## no *_end bones, so Head and Foot are identity in the source files). Both
## packs are the same mocap with identical timing, so those tracks are restored
## from the matching male clip: still human-authored keys, never generated.
## Without this her head is rigid and her feet never roll. (The female body has
## no distal finger bones, so the matching finger leaves need no restore.)
const LEAF_RESTORE: Array[String] = ["Head", "LeftFoot", "RightFoot"]
var _pistol_frame: int = 0
var _male_library: AnimationLibrary

func _process(_delta: float) -> bool:
	_pistol_frame += 1
	if _pistol_frame == 2:
		for gender: String in BODIES:
			_bake_pistol(gender)
		quit()
	return false

func _bake_pistol(gender: String) -> void:
	var body_scene: PackedScene = load(BODIES[gender])
	var body: Node3D = body_scene.instantiate()
	var skeleton: Skeleton3D = body.find_child("GeneralSkeleton", true, false)
	var library := AnimationLibrary.new()
	for key: String in PISTOL_CLIPS:
		var anim: Animation = _convert("res://assets/models/player/pistol/%s/%s.fbx" % [gender, key], skeleton, true)
		if anim == null:
			quit(1)
			return
		if gender == "female" and _male_library != null:
			_restore_leaf_tracks(anim, _male_library.get_animation(key), key, skeleton)
		library.add_animation(key, anim)
	body.free()
	var rig: Node3D = _make_rig(body_scene, library)
	for key: String in PISTOL_CLIPS:
		_analyse(rig, key, "loop" if key == "idle" else "gait", "pistol/%s/%s.fbx" % [gender, key])
		var animation: Animation = library.get_animation(key)
		if key != "idle":
			# Maximo travel lives on the armature node, not necessarily on Hips.
			# Remove constant horizontal travel there as well (bob/sway preserved).
			_make_in_place(animation)
			_remove_armature_travel(animation)
			_measure_contact_phase(rig, key)
		else:
			var sk: Skeleton3D = _pose(rig, key, 0.0)
			var hand: Transform3D = _bone_holder(rig, sk, "RightHand")
			# Neutral -Z gun forward in holder space, converted into hand space.
			# Runtime uses the animated hand transform, keeping recoil/motion attached.
			animation.set_meta("grip_basis", hand.basis.orthonormalized().inverse())
			print("[pistol] %s idle hand=%s left=%s" % [gender, hand.origin, _bone_holder(rig, sk, "LeftHand").origin])
	var path: String = "res://assets/models/player/pistol/pistol_%s_lib.res" % gender
	if gender == "male":
		_male_library = library
	var result: Error = ResourceSaver.save(library, path)
	print("[pistol] saved %s: %s" % [path, result])
	rig.queue_free()

func _restore_leaf_tracks(anim: Animation, male: Animation, key: String, skeleton: Skeleton3D) -> void:
	var present: Dictionary = {}
	for track: int in anim.get_track_count():
		present[str(anim.track_get_path(track))] = true
	var restored: PackedStringArray = []
	for track: int in male.get_track_count():
		var path: String = str(male.track_get_path(track))
		if male.track_get_type(track) != Animation.TYPE_ROTATION_3D or present.has(path):
			continue
		var bone: String = path.get_slice(":", 1)
		if not LEAF_RESTORE.has(bone) or skeleton.find_bone(bone) == -1:
			continue
		var copy: int = anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(copy, NodePath(path))
		anim.track_set_interpolation_type(copy, male.track_get_interpolation_type(track))
		anim.track_set_interpolation_loop_wrap(copy, male.track_get_interpolation_loop_wrap(track))
		for k: int in male.track_get_key_count(track):
			anim.track_insert_key(copy, male.track_get_key_time(track, k), male.track_get_key_value(track, k), male.track_get_key_transition(track, k))
		restored.append(bone)
	print("[pistol] female %s: restored leaf tracks from male clip: %s" % [key, ", ".join(restored)])

func _remove_armature_travel(animation: Animation) -> void:
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D or str(animation.track_get_path(track)) != ARMATURE_PATH:
			continue
		var count: int = animation.track_get_key_count(track)
		if count < 2:
			continue
		var first: Vector3 = animation.track_get_key_value(track, 0)
		var travel: Vector3 = animation.track_get_key_value(track, count - 1) - first
		travel.y = 0.0
		for i: int in count:
			animation.track_set_key_value(track, i, animation.track_get_key_value(track, i) - travel * animation.track_get_key_time(track, i) / animation.length)

func _measure_contact_phase(rig: Node3D, key: String) -> void:
	var animation: Animation = (rig.get_node("AP") as AnimationPlayer).get_animation(key)
	var heights := PackedFloat32Array()
	for i: int in ANALYSIS_SAMPLES:
		var sk: Skeleton3D = _pose(rig, key, animation.length * float(i) / ANALYSIS_SAMPLES)
		heights.append(_bone_holder(rig, sk, "LeftFoot").origin.y)
	# Use the landing side of left-foot contact for every travel direction.
	var best: int = 0
	var lowest: float = INF
	for i: int in ANALYSIS_SAMPLES:
		var previous: int = (i + ANALYSIS_SAMPLES - 1) % ANALYSIS_SAMPLES
		if heights[i] <= heights[previous] and heights[i] < lowest:
			lowest = heights[i]
			best = i
	animation.set_meta("phase_offset", animation.length * float(best) / ANALYSIS_SAMPLES)
