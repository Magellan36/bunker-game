extends SceneTree
## build_dying_anim.gd
## Bakes the gender-specific Dying clips into AnimationLibraries, same
## pipeline as build_lying_down_anim.gd: rebase track paths to "MaleModel/",
## strip the armature-root position/rotation tracks (root motion is never
## consumed), strip any Hips position track. The FBX sources are imported
## with bone_map_maximo.tres so their skeleton/bones are renamed to the
## runtime GeneralSkeleton convention (their track paths then resolve onto
## the player body).
##
## LOOP_NONE — the dying clip is a one-shot; the engine holds the LAST frame
## once it finishes, which is exactly the "frozen dead body" state a dead
## NPC stays in.
##
## Run: godot --headless --path <project> --script res://tools/build_dying_anim.gd

const CLIPS: Dictionary = {
	"dying_male":   "res://assets/models/player/dying_male.fbx",
	"dying_female": "res://assets/models/player/dying_female.fbx",
}
const ANIMS_DIR: String = "res://assets/models/player/anims"

## Maximo finger-joint names (Index1.L etc.) don't exist on the runtime
## Adventurer skeleton, which uses LeftIndexProximal etc. The Maximo clip
## animates only the root knuckle per finger, so remap to the runtime
## Proximal bone (the other phalanges follow through the hierarchy).
const FINGER_REMAP: Dictionary = {
	"Index1.L": "LeftIndexProximal",
	"Middle1.L": "LeftMiddleProximal",
	"Ring1.L": "LeftRingProximal",
	"Pinky1.L": "LeftPinkyProximal",
	"Thumb1.L": "LeftThumbProximal",
	"Index1.R": "RightIndexProximal",
	"Middle1.R": "RightMiddleProximal",
	"Ring1.R": "RightRingProximal",
	"Pinky1.R": "RightPinkyProximal",
	"Thumb1.R": "RightThumbProximal",
}

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ANIMS_DIR))
	for key: String in CLIPS:
		var ps: PackedScene = load(CLIPS[key])
		var inst: Node = ps.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var anim_name: String = "mixamo_com" if ap.has_animation("mixamo_com") else "Scene"
		var anim: Animation = ap.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_NONE   ## one-shot — holds the last frame (dead pose)

		## Rebase to the runtime body prefix (same as every other clip) and
		## remap Maximo finger-joint names to the runtime Adventurer names.
		for ti in anim.get_track_count():
			var tp: NodePath = anim.track_get_path(ti)
			var new_path: String = "MaleModel/" + str(tp)
			if tp.get_subname_count() > 0:
				var bone: String = str(tp.get_subname(tp.get_subname_count() - 1))
				if FINGER_REMAP.has(bone):
					new_path = new_path.replace(":" + bone, ":" + str(FINGER_REMAP[bone]))
			anim.track_set_path(ti, NodePath(new_path))

		## Strip any Hips position track (root motion never consumed).
		for ti2 in range(anim.get_track_count() - 1, -1, -1):
			var track_path: NodePath = anim.track_get_path(ti2)
			if anim.track_get_type(ti2) == Animation.TYPE_POSITION_3D \
					and "Hips" in track_path.get_concatenated_subnames():
				anim.remove_track(ti2)

		## Rewrite the armature-root tracks (CharacterArmature, no bone subname)
		## to the runtime `MaleModel` root and REBASE them to the runtime base.
		## For the death clip the armature IS the fall (it tips ~86° about X,
		## upright → lying), but its RAW transform is in FBX space: unit-scaled
		## (scale 100), offset near the origin, and pre-tipped (~86° at frame 0).
		## Baking it raw snaps the body up ~0.88 m, scales it 100×, and pre-tips
		## it on the first frame — the "player disappears" bug. Rebase instead:
		##   • position: runtime base (0,-0.9,0) + armature delta from frame 0
		##   • rotation: delta quat from frame 0 (frame 0 → identity, no snap)
		##   • scale: constant (1,1,1) — the Maximo unit scale is already baked
		##     into the imported model, so the clip must not re-apply 100×
		const MALE_BASE_POS: Vector3 = Vector3(0.0, -0.9, 0.0)   ## MaleModel origin = the feet
		for ti3 in range(anim.get_track_count() - 1, -1, -1):
			var p3: NodePath = anim.track_get_path(ti3)
			if p3.get_subname_count() == 0:
				var tt3: Animation.TrackType = anim.track_get_type(ti3)
				if tt3 == Animation.TYPE_POSITION_3D:
					var npos: int = anim.track_get_key_count(ti3)
					var p0: Vector3 = anim.track_get_key_value(ti3, 0) if npos > 0 else MALE_BASE_POS
					for kp in npos:
						var v: Vector3 = anim.track_get_key_value(ti3, kp)
						anim.track_set_key_value(ti3, kp, MALE_BASE_POS + (v - p0))
				elif tt3 == Animation.TYPE_ROTATION_3D:
					var nrot: int = anim.track_get_key_count(ti3)
					var r0: Quaternion = anim.track_get_key_value(ti3, 0) if nrot > 0 else Quaternion.IDENTITY
					for kr in nrot:
						var q: Quaternion = anim.track_get_key_value(ti3, kr)
						anim.track_set_key_value(ti3, kr, r0.inverse() * q)
				elif tt3 == Animation.TYPE_SCALE_3D:
					for ks in anim.track_get_key_count(ti3):
						anim.track_set_key_value(ti3, ks, Vector3.ONE)
				anim.track_set_path(ti3, NodePath("MaleModel"))

		var lib := AnimationLibrary.new()
		lib.add_animation("dying", anim)
		var path: String = ANIMS_DIR + "/" + key + "_lib.res"
		var err: Error = ResourceSaver.save(lib, path)
		print("saved ", path, " err=", err, " anim len=", anim.length, " tracks=", anim.get_track_count())
		inst.free()
	quit(0)