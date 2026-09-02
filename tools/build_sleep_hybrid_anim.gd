extends SceneTree
## build_sleep_hybrid_anim.gd — bakes the gender-specific sleeping hybrid clips.
## Same recipe as build_sit_hybrid_anim.gd but for the bed's lying_down ->
## sleeping transition: the legs + pelvis are held STATIC at the lying_down
## clip's FINAL pose (the fully-lying pose the game drives the recline/turn/
## slide to), and only the upper body (Spine and up, incl. arms/hands/fingers)
## animates the sleeping loop. The sleeping clip loops until the player exits.
##
## Run: godot --headless --path <project> --script res://tools/build_sleep_hybrid_anim.gd

const GENDERS: Dictionary = {
	"male": {
		"lying_down_lib": "res://assets/models/player/anims/lying_down_male_lib.res",
		"sleep_fbx": "res://assets/models/player/sleeping_male.fbx",
		"out": "res://assets/models/player/anims/sleep_hybrid_male_lib.res",
	},
	"female": {
		"lying_down_lib": "res://assets/models/player/anims/lying_down_female_lib.res",
		"sleep_fbx": "res://assets/models/player/sleeping_female.fbx",
		"out": "res://assets/models/player/anims/sleep_hybrid_female_lib.res",
	},
}

func _is_leg_bone(bone: String) -> bool:
	return bone == "Hips" or bone.contains("Leg") or bone.contains("Foot") or bone.contains("Toe")

func _bone_of(path: NodePath) -> String:
	var sub: String = path.get_concatenated_subnames()
	return sub.substr(sub.rfind(":") + 1) if sub.contains(":") else sub

func _init() -> void:
	for g: String in GENDERS:
		_bake(g, GENDERS[g])
	quit(0)

func _bake(g: String, cfg: Dictionary) -> void:
	var ld_lib: AnimationLibrary = load(cfg["lying_down_lib"])
	if ld_lib == null:
		print("FAILED to load ", cfg["lying_down_lib"])
		return
	var ld: Animation = ld_lib.get_animation("lying_down")

	var ps: PackedScene = load(cfg["sleep_fbx"])
	var inst: Node = ps.instantiate()
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sleep: Animation = ap.get_animation("mixamo_com")
	var anim: Animation = sleep.duplicate()

	## Strip armature-root tracks (CharacterArmature, no subname) — root motion
	## is never consumed; the game drives position/rotation.
	for ti in range(anim.get_track_count() - 1, -1, -1):
		var p: NodePath = anim.track_get_path(ti)
		if p.get_subname_count() == 0 and p.get_name(p.get_name_count() - 1) == "CharacterArmature":
			anim.remove_track(ti)
	## Strip any Hips position track (root motion never consumed).
	for ti2 in range(anim.get_track_count() - 1, -1, -1):
		var p2: NodePath = anim.track_get_path(ti2)
		if anim.track_get_type(ti2) == Animation.TYPE_POSITION_3D \
				and "Hips" in p2.get_concatenated_subnames():
			anim.remove_track(ti2)
	## Rebase bone tracks to the runtime body prefix (same as every other clip).
	for ti3 in anim.get_track_count():
		anim.track_set_path(ti3, NodePath("MaleModel/" + str(anim.track_get_path(ti3))))

	var out := Animation.new()
	out.length = anim.length
	out.loop_mode = Animation.LOOP_LINEAR

	## Pass 1 — static legs + pelvis, frozen at lying_down's FINAL frame.
	for ti in ld.get_track_count():
		var p: NodePath = ld.track_get_path(ti)
		if not _is_leg_bone(_bone_of(p)):
			continue
		var kc: int = ld.track_get_key_count(ti)
		if kc == 0:
			continue
		var idx: int = out.add_track(ld.track_get_type(ti))
		out.track_set_path(idx, p)
		out.track_set_interpolation_type(idx, ld.track_get_interpolation_type(ti))
		out.track_insert_key(idx, 0.0, ld.track_get_key_value(ti, kc - 1), 0.0)

	## Pass 2 — animated top half from the sleeping loop.
	for ti in anim.get_track_count():
		var p: NodePath = anim.track_get_path(ti)
		if _is_leg_bone(_bone_of(p)):
			continue
		var idx: int = out.add_track(anim.track_get_type(ti))
		out.track_set_path(idx, p)
		out.track_set_interpolation_type(idx, anim.track_get_interpolation_type(ti))
		for k in anim.track_get_key_count(ti):
			out.track_insert_key(idx, anim.track_get_key_time(ti, k),
				anim.track_get_key_value(ti, k), anim.track_get_key_transition(ti, k))

	var lib := AnimationLibrary.new()
	lib.add_animation("sleeping", out)
	var err: Error = ResourceSaver.save(lib, cfg["out"])
	print("saved ", cfg["out"], " err=", err, " len=", out.length,
		" tracks=", out.get_track_count(), " loop=", out.loop_mode)
	inst.free()