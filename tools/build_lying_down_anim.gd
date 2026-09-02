extends SceneTree
## build_lying_down_anim.gd
## Bakes the gender-specific Lying Down clips into AnimationLibraries, same
## pipeline as build_sit_animations.gd: rebase track paths to "MaleModel/",
## strip the armature-root position/rotation tracks (root motion is never
## consumed — the game drives position and the 90° side turn), strip any Hips
## position track. The FBX sources are imported with bone_map_maximo.tres so
## their skeleton/bones are renamed to the runtime GeneralSkeleton convention
## (their track paths then resolve onto the player body).
##
## Run: godot --headless --path <project> --script res://tools/build_lying_down_anim.gd

const CLIPS: Dictionary = {
	"lying_down_male":   "res://assets/models/player/lying_down_male.fbx",
	"lying_down_female": "res://assets/models/player/lying_down_female.fbx",
}
const ANIMS_DIR: String = "res://assets/models/player/anims"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ANIMS_DIR))
	for key: String in CLIPS:
		var ps: PackedScene = load(CLIPS[key])
		var inst: Node = ps.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var anim_name: String = "mixamo_com" if ap.has_animation("mixamo_com") else "Scene"
		var anim: Animation = ap.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_NONE   ## one-shot — holds the last frame

		## Rebase to the runtime body prefix (same as every other clip).
		for ti in anim.get_track_count():
			var tp: NodePath = anim.track_get_path(ti)
			anim.track_set_path(ti, NodePath("MaleModel/" + str(tp)))

		## Strip any Hips position track (root motion never consumed).
		for ti2 in range(anim.get_track_count() - 1, -1, -1):
			var track_path: NodePath = anim.track_get_path(ti2)
			if anim.track_get_type(ti2) == Animation.TYPE_POSITION_3D \
					and "Hips" in track_path.get_concatenated_subnames():
				anim.remove_track(ti2)

		## Strip armature-root tracks (CharacterArmature, no bone subname) — the
		## root's position AND rotation, since the game owns both (the 90° turn).
		for ti3 in range(anim.get_track_count() - 1, -1, -1):
			var p3: NodePath = anim.track_get_path(ti3)
			if p3.get_subname_count() == 0 \
					and p3.get_name(p3.get_name_count() - 1) == "CharacterArmature":
				anim.remove_track(ti3)

		var lib := AnimationLibrary.new()
		lib.add_animation("lying_down", anim)
		var path: String = ANIMS_DIR + "/" + key + "_lib.res"
		var err: Error = ResourceSaver.save(lib, path)
		print("saved ", path, " err=", err, " anim len=", anim.length, " tracks=", anim.get_track_count())
		inst.free()
	quit(0)