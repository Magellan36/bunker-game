extends SceneTree
## build_sit_animations.gd
## Aug 2026 — extracts the 3 sit-sequence clips (stand_to_sit/sitting/
## sit_to_stand) into AnimationLibrary .res files, mirroring
## build_player_model.gd's proven pattern exactly (same track-path
## rebase, same Hips-position-track removal — see that file's own doc
## comment for why: the player never consumes root motion, so a Hips
## position track only pins the body to wherever it happened to be
## authored, sinking/offsetting the animated body during playback).
##
## Run via: godot --headless --script res://tools/build_sit_animations.gd
##
## Prerequisite — Blender-side fix already applied (see
## docs/systems/player-model/README.md "Sit animation root-offset fix"):
## the source stand_to_sit.fbx/sitting.fbx/sit_to_stand.fbx were
## re-exported with their Hips position tracks recentered so the seated
## pose lands at the skeleton's own rest position, consistently across
## all three clips — verified directly in Blender (sub-micron residual
## at the seated frame, in a fresh reimport from the exported files).
## This script's own track removal below is a second, independent
## guarantee on top of that fix, not a replacement for it: the Blender
## fix keeps whatever position-track data DOES matter (fine-grained
## relative motion within a clip) already correctly centered, while this
## removal step matches the same "root motion never played, so don't
## ship a Hips position track at all" rule the other 6 clips already
## follow.

const CLIP_PATHS := {
	"stand_to_sit": "res://assets/models/player/stand_to_sit.fbx",
	"sit": "res://assets/models/player/sitting.fbx",
	"sit_to_stand": "res://assets/models/player/sit_to_stand.fbx",
}
const LIB_NAMES := {
	"stand_to_sit": "stand_to_sit_lib",
	"sit": "sit_lib",
	"sit_to_stand": "sit_to_stand_lib",
}
const LOOPING := {
	"stand_to_sit": false,
	"sit": true,
	"sit_to_stand": false,
}

func _init():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/player/anims"))
	for key in CLIP_PATHS:
		var ps: PackedScene = load(CLIP_PATHS[key])
		var inst: Node = ps.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		## Aug 2026 — these 3 clips were re-exported from Blender (see the
		## Hips root-offset fix in docs/systems/player-model/README.md),
		## and Blender's FBX exporter named the resulting take "Scene"
		## rather than preserving the original "mixamo_com" clip name the
		## other 6 (untouched-source) animation files use. Confirmed
		## directly: ap.get_animation_list() on all 3 returns ["Scene"].
		var anim_name: String = "Scene" if ap.has_animation("Scene") else "mixamo_com"
		var anim: Animation = ap.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if LOOPING[key] else Animation.LOOP_NONE

		## Same rebase as build_player_model.gd — AnimationMixer resolves
		## track paths relative to root_node (the AnimationPlayer's
		## parent), not the AnimationPlayer itself, so "MaleModel/" is
		## the correct prefix, matching every other clip in this project.
		for ti in anim.get_track_count():
			var tp: NodePath = anim.track_get_path(ti)
			anim.track_set_path(ti, NodePath("MaleModel/" + str(tp)))

		## Same Hips-position-track removal as build_player_model.gd —
		## see this script's own top-of-file comment for why this is a
		## second, independent guarantee on top of the Blender-side fix,
		## not a replacement for it.
		for ti2 in range(anim.get_track_count() - 1, -1, -1):
			var track_path: NodePath = anim.track_get_path(ti2)
			if anim.track_get_type(ti2) == Animation.TYPE_POSITION_3D \
					and "Hips" in track_path.get_concatenated_subnames():
				anim.remove_track(ti2)

		## Armature-root root-motion tracks (ANIMATIONS.md pipeline step) —
		## tracks whose path is the armature root node itself (no ":" subname;
		## the last node name is the armature, e.g. "CharacterArmature" for
		## Maximo-rig sources) are unresolvable at runtime and root motion is
		## never consumed, so strip them (Aug 2026, added for the Maximo-rig
		## "Sitting Idle NEW" sit loop; Mixamo sources' "Armature" roots were
		## already trackless on import).
		for ti3 in range(anim.get_track_count() - 1, -1, -1):
			var p3: NodePath = anim.track_get_path(ti3)
			if p3.get_subname_count() == 0 \
					and p3.get_name(p3.get_name_count() - 1) == "CharacterArmature":
				anim.remove_track(ti3)

		var lib := AnimationLibrary.new()
		lib.add_animation(key, anim)
		var path: String = "res://assets/models/player/anims/" + LIB_NAMES[key] + ".res"
		var err := ResourceSaver.save(lib, path)
		print("saved ", path, " err=", err, " anim len=", anim.length, " tracks=", anim.get_track_count())
		inst.free()
	quit(0)
