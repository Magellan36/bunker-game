@tool
extends EditorScript

## Aug 2026 native-rig rebuild — editor-side twin of tools/build_player_model.gd.
## Run in the editor: open this file in the script editor and press Ctrl+Shift+X.
## Rebuilds the six AnimationLibrary .res files from the RETARGETED clip imports
## (after retarget the clip bones are humanoid-profile names and the skeleton
## node is "GeneralSkeleton", so track paths become MaleModel/GeneralSkeleton:*).
## Also prints the idle clip's track list so a single glance verifies the
## retarget actually took (bone subnames should be Hips/Spine/... not mixamorig:*).

const CLIP_PATHS := {
	"idle": "res://assets/models/player/idle.fbx",
	"walk": "res://assets/models/player/walk.fbx",
	"run": "res://assets/models/player/run.fbx",
	"idle_carry": "res://assets/models/player/idle_carry.fbx",
	"walk_carry": "res://assets/models/player/walk_carry.fbx",
	"run_carry": "res://assets/models/player/run_carry.fbx",
}
const LIB_NAMES := {
	"idle": "idle_lib",
	"walk": "walk_lib",
	"run": "run_lib",
	"idle_carry": "idle_carry_lib",
	"walk_carry": "walk_carry_lib",
	"run_carry": "run_carry_lib",
}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/player/anims"))
	for key in CLIP_PATHS:
		var ps: PackedScene = load(CLIP_PATHS[key])
		if ps == null:
			push_error("[build_player_model_editor] cannot load " + CLIP_PATHS[key])
			continue
		var inst: Node = ps.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		if ap == null:
			push_error("[build_player_model_editor] no AnimationPlayer in " + CLIP_PATHS[key])
			inst.free()
			continue
		if not ap.has_animation("mixamo_com"):
			push_error("[build_player_model_editor] no 'mixamo_com' in " + CLIP_PATHS[key]
				+ "; available: " + str(ap.get_animation_list()))
			inst.free()
			continue
		var anim: Animation = ap.get_animation("mixamo_com")
		anim.loop_mode = Animation.LOOP_LINEAR
		## Same rebase as tools/build_player_model.gd: clip tracks are relative
		## to the clip scene's own root, but PlayerModel.tscn plays them through
		## its wrapper AnimationPlayer whose sibling is the instanced MaleModel.
		for ti in anim.get_track_count():
			anim.track_set_path(ti, NodePath("MaleModel/" + str(anim.track_get_path(ti))))
		## Same sink fix as the CLI tool: drop Hips' POSITION track (the player
		## doesn't use root motion; the clip's pinned Hips height sinks the body).
		for ti2 in range(anim.get_track_count() - 1, -1, -1):
			var track_path: NodePath = anim.track_get_path(ti2)
			if anim.track_get_type(ti2) == Animation.TYPE_POSITION_3D \
					and "Hips" in track_path.get_concatenated_subnames():
				anim.remove_track(ti2)
		var lib := AnimationLibrary.new()
		lib.add_animation(key, anim)
		var path := "res://assets/models/player/anims/" + LIB_NAMES[key] + ".res"
		var err := ResourceSaver.save(lib, path)
		print("[build_player_model_editor] saved ", path, " err=", err,
			" len=", anim.length, " tracks=", anim.get_track_count())
		if key == "idle":
			for ti in anim.get_track_count():
				print("  track[", ti, "] ", anim.track_get_path(ti),
					" type=", anim.track_get_type(ti))
		inst.free()
	print("[build_player_model_editor] done")