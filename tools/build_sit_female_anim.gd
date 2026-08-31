extends SceneTree
## build_sit_female_anim.gd — Aug 2026.
## Bakes the FEMALE-specific sit transition libraries (the shared stand_to_sit /
## sit_to_stand are male/Mixamo-rigged and stretch on the female rig):
##   stand_to_sit_female_lib.res  (clip "stand_to_sit")
##   sit_to_stand_female_lib.res  (clip "sit_to_stand")
## and a female hybrid seated clip (frozen legs from the FEMALE stand_to_sit's
## end pose + upper body from the shared sit loop):
##   sit_hybrid_female_lib.res    (clip "sit_hybrid")
## Same pipeline as build_sit_animations.gd / build_sit_hybrid_anim.gd:
## rebase tracks to MaleModel/, strip Hips position tracks. The one
## difference: the female clips' VERTICAL descent lives on the armature-root
## POSITION track, so it is RETAINED (X/Z zeroed, the game owns horizontal)
## and the armature's rotation/scale are stripped (the game controls facing).

const STS_FEMALE_FBX := "res://assets/models/player/stand_to_sit_female.fbx"
const S2S_FEMALE_FBX := "res://assets/models/player/sit_to_stand_female.fbx"
const STS_FEMALE_LIB := "res://assets/models/player/anims/stand_to_sit_female_lib.res"
const S2S_FEMALE_LIB := "res://assets/models/player/anims/sit_to_stand_female_lib.res"
const SIT_LIB := "res://assets/models/player/anims/sit_lib.res"
const HYBRID_FEMALE_LIB := "res://assets/models/player/anims/sit_hybrid_female_lib.res"

func _is_leg_bone(bone: String) -> bool:
	return bone == "Hips" or bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toe")

func _bone_of(path: NodePath) -> String:
	var sub: String = path.get_concatenated_subnames()
	return sub.substr(sub.rfind(":") + 1) if sub.contains(":") else sub

func _bake_transition(fbx_path: String, clip_name: String, out_path: String) -> void:
	var ps: PackedScene = load(fbx_path)
	var inst: Node = ps.instantiate()
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var anim_name: String = "Scene" if ap.has_animation("Scene") else "mixamo_com"
	var anim: Animation = ap.get_animation(anim_name)
	anim.loop_mode = Animation.LOOP_NONE
	for ti in anim.get_track_count():
		anim.track_set_path(ti, NodePath("MaleModel/" + str(anim.track_get_path(ti))))
	for ti2 in range(anim.get_track_count() - 1, -1, -1):
		var tp: NodePath = anim.track_get_path(ti2)
		if anim.track_get_type(ti2) == Animation.TYPE_POSITION_3D \
				and "Hips" in tp.get_concatenated_subnames():
			anim.remove_track(ti2)
	for ti3 in range(anim.get_track_count() - 1, -1, -1):
		var p3: NodePath = anim.track_get_path(ti3)
		## Keep the armature-root POSITION track — the female clips' VERTICAL
		## descent lives there and must stay so the clip drives the body down
		## (instead of a game-side curve). Strip its rotation/scale (the game
		## controls facing), and ZERO its X/Z (the game's X/Z slide owns the
		## horizontal — the clip's own X/Z would double-move the character).
		if p3.get_subname_count() == 0 and p3.get_name(p3.get_name_count() - 1) == "CharacterArmature":
			if anim.track_get_type(ti3) == Animation.TYPE_POSITION_3D:
				for k in anim.track_get_key_count(ti3):
					var v: Vector3 = anim.track_get_key_value(ti3, k)
					anim.track_set_key_value(ti3, k, Vector3(0.0, v.y, 0.0))
			else:
				anim.remove_track(ti3)
	var lib := AnimationLibrary.new()
	lib.add_animation(clip_name, anim)
	var err := ResourceSaver.save(lib, out_path)
	print("saved ", out_path, " err=", err, " len=", anim.length, " tracks=", anim.get_track_count())
	inst.free()

func _bake_hybrid() -> void:
	var sts_lib: AnimationLibrary = load(STS_FEMALE_LIB)
	var sit_lib: AnimationLibrary = load(SIT_LIB)
	if sts_lib == null or sit_lib == null:
		print("FAILED to load hybrid sources")
		return
	var sts: Animation = sts_lib.get_animation("stand_to_sit")
	var sit: Animation = sit_lib.get_animation("sit")
	var out := Animation.new()
	out.length = sit.length
	out.loop_mode = Animation.LOOP_LINEAR
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
	## Hold the skeleton DOWN during the seated loop: freeze the armature-root
	## Y at the seated value (the transition clip drives the descent, so the
	## loop must keep the skeleton at that lowered height — X/Z zeroed).
	for ti in sts.get_track_count():
		var p: NodePath = sts.track_get_path(ti)
		if p.get_subname_count() != 0:
			continue
		if p.get_name(p.get_name_count() - 1) != "CharacterArmature":
			continue
		if sts.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		var kc: int = sts.track_get_key_count(ti)
		if kc == 0:
			continue
		var idx: int = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(idx, p)
		out.track_set_interpolation_type(idx, sts.track_get_interpolation_type(ti))
		var last: Vector3 = sts.track_get_key_value(ti, kc - 1)
		out.track_insert_key(idx, 0.0, Vector3(0.0, last.y, 0.0), 0.0)
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
	lib.add_animation("sit_hybrid", out)
	var err := ResourceSaver.save(lib, HYBRID_FEMALE_LIB)
	print("saved ", HYBRID_FEMALE_LIB, " err=", err, " len=", out.length, " tracks=", out.get_track_count())

func _init() -> void:
	_bake_transition(STS_FEMALE_FBX, "stand_to_sit", STS_FEMALE_LIB)
	_bake_transition(S2S_FEMALE_FBX, "sit_to_stand", S2S_FEMALE_LIB)
	_bake_hybrid()
	quit(0)