extends SceneTree

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

func _init():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/player/anims"))
	for key in CLIP_PATHS:
		var ps: PackedScene = load(CLIP_PATHS[key])
		var inst: Node = ps.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		var anim: Animation = ap.get_animation("mixamo_com")
		anim.loop_mode = Animation.LOOP_LINEAR
		## The clip tracks were authored relative to the FBX scene's own
		## AnimationPlayer (Skeleton3D as a direct sibling). PlayerModel.tscn
		## plays them via its own wrapper AnimationPlayer, whose sibling is
		## the instanced MaleModel — so every track path must be rebased.
		## AnimationMixer resolves track paths relative to root_node (the
		## AnimationPlayer's parent), NOT the AnimationPlayer itself, so the
		## prefix is "MaleModel/" (no leading "..").
		for ti in anim.get_track_count():
			var tp: NodePath = anim.track_get_path(ti)
			anim.track_set_path(ti, NodePath("MaleModel/" + str(tp)))
		var lib := AnimationLibrary.new()
		lib.add_animation(key, anim)
		var path: String = "res://assets/models/player/anims/" + LIB_NAMES[key] + ".res"
		var err := ResourceSaver.save(lib, path)
		print("saved ", path, " err=", err, " anim len=", anim.length, " tracks=", anim.get_track_count())
		inst.free()
	quit(0)