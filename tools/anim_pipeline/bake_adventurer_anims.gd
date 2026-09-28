extends SceneTree
## bake_adventurer_anims.gd — the ONE import step for Adventurer body clips.
##
## Turns the imported human-made source clips (Mixamo / Maximo FBX mocap under
## assets/models/player/) into one AnimationLibrary per body gender:
##   assets/models/player/anims/adventurer_male_lib.res
##   assets/models/player/anims/adventurer_female_lib.res
##
## PROVENANCE RULE (Steam AI disclosure): this tool never authors motion. Every
## keyframe it writes is a source keyframe, re-expressed losslessly:
##   * bone tracks are copied verbatim (path rebased to the runtime body);
##   * Maximo armature root motion is re-expressed in the runtime armature's
##     frame (A(t) · A_rest⁻¹) — a change of basis, not new motion;
##   * locomotion loops have their constant forward travel removed ("in place",
##     the same thing Mixamo's own In-Place export does) — bob and sway stay.
## Anything that adapts motion to the game (speed matching, blending, alignment
## to furniture, IK) happens at RUNTIME in AdventurerModelController.gd.
##
## The tool also measures each clip on the real runtime body and stores the
## measurements as Animation metadata (stride length, gait phase, hip/feet
## trajectories). Those are analysis numbers the controller reads — not keys.
##
## Adding a clip: add a row to CLIPS (and optionally a per-gender override in
## GENDER_OVERRIDES), import the FBX with the right bone map (see
## docs/systems/player-model/ANIMATIONS.md), then run:
##   godot --headless --path <project> --script res://tools/anim_pipeline/bake_adventurer_anims.gd

const OUT_DIR: String = "res://assets/models/player/anims"
const SRC_DIR: String = "res://assets/models/player/"

const BODIES: Dictionary = {
	"male": "res://assets/models/player/adventurer/Adventurer_Male.fbx",
	"female": "res://assets/models/player/adventurer/Adventurer_Female.fbx",
}

## Clip key -> source + handling. "kind":
##   "loop"   looping clip, played free-running (idle, seated/sleep loops)
##   "gait"   looping locomotion: made in-place, stride + phase measured
##   "action" one-shot: hip/feet trajectories measured for runtime alignment
##   "lean"   looping wall lean: also measures where the body's back surface
##            is (the wall plane the pose was performed against)
const CLIPS: Dictionary = {
	"idle":         {"src": "male_locomotion/idle.fbx", "kind": "loop"},
	"walk":         {"src": "walk.fbx",                 "kind": "gait"},
	"run":          {"src": "run.fbx",                  "kind": "gait"},
	## Carrying layers idle_carry's ARMS over the normal gait at runtime (the
	## walk_carry/run_carry sources hold two gait cycles per loop, so they
	## can't share the walk/run phase).
	"idle_carry":   {"src": "idle_carry.fbx",           "kind": "loop"},
	## The Maximo sit set carries clean armature root motion and shares the rig
	## family of the lie/sleep/idle clips, so both bodies use it.
	"stand_to_sit": {"src": "stand_to_sit_female.fbx",  "kind": "action"},
	"sit":          {"src": "sitting.fbx",              "kind": "loop"},
	"sit_to_stand": {"src": "sit_to_stand_female.fbx",  "kind": "action"},
	"lie_down":     {"src": "lying_down_male.fbx",      "kind": "action"},
	"sleep":        {"src": "sleeping_male.fbx",        "kind": "loop"},
	"dying":        {"src": "dying_male.fbx",           "kind": "action"},
	## NPC-only wall lean (back to the wall, one sole up on it).
	"lean":         {"src": "leaning_male.fbx",         "kind": "lean"},
}

const GENDER_OVERRIDES: Dictionary = {
	"female": {
		"idle":     {"src": "female_locomotion/idle.fbx", "kind": "loop"},
		"lie_down": {"src": "lying_down_female.fbx",      "kind": "action"},
		"sleep":    {"src": "sleeping_female.fbx",        "kind": "loop"},
		"dying":    {"src": "dying_female.fbx",           "kind": "action"},
	},
}

## The Maximo FBX armature node's original transform (Z-up → Y-up, cm → m).
## The importer's rest fixer bakes it into the skeleton but leaves the
## armature's own animation tracks relative to it — verified: the in-place
## idle re-expresses to ≈ identity.
static func armature_rest() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * 100.0), Vector3.ZERO)

## Maximo clips key only each finger's root knuckle, under Maximo names the
## bone map leaves unmapped. Map them onto the runtime Humanoid names.
const FINGER_REMAP: Dictionary = {
	"Index1.L": "LeftIndexProximal", "Middle1.L": "LeftMiddleProximal",
	"Ring1.L": "LeftRingProximal", "Pinky1.L": "LeftPinkyProximal",
	"Thumb1.L": "LeftThumbProximal",
	"Index1.R": "RightIndexProximal", "Middle1.R": "RightMiddleProximal",
	"Ring1.R": "RightRingProximal", "Pinky1.R": "RightPinkyProximal",
	"Thumb1.R": "RightThumbProximal",
}

const BODY_PREFIX: String = "MaleModel/"   ## load-bearing: the runtime body root name
const ARMATURE_PATH: String = "MaleModel/CharacterArmature"
const RESAMPLE_FPS: float = 30.0
const ANALYSIS_SAMPLES: int = 61

var _frame: int = 0

func _process(_delta: float) -> bool:
	## Analysis needs nodes inside the tree, so work on the first idle frame.
	_frame += 1
	if _frame == 2:
		for gender: String in BODIES:
			_bake_gender(gender)
		quit(0)
	return false

func _bake_gender(gender: String) -> void:
	var body_scene: PackedScene = load(BODIES[gender])
	var probe_body: Node3D = body_scene.instantiate()
	var skeleton: Skeleton3D = probe_body.find_child("GeneralSkeleton", true, false)
	var lib := AnimationLibrary.new()
	var clips: Dictionary = CLIPS.duplicate(true)
	clips.merge(GENDER_OVERRIDES.get(gender, {}), true)
	for key: String in clips:
		var spec: Dictionary = clips[key]
		var anim: Animation = _convert(SRC_DIR + String(spec["src"]), skeleton, spec["kind"] != "action")
		if anim == null:
			continue
		lib.add_animation(key, anim)
	probe_body.free()

	## Analysis pass on a live runtime body (same holder layout as runtime).
	var rig := _make_rig(body_scene, lib)
	for key: String in clips:
		if not lib.has_animation(key):
			continue
		_analyse(rig, key, String(clips[key]["kind"]), String(clips[key]["src"]))
	## Gaits are stored in-place; convert now that their stride is measured.
	for key: String in clips:
		if clips[key]["kind"] == "gait" and lib.has_animation(key):
			_make_in_place(lib.get_animation(key))
	rig.queue_free()

	var out_path: String = "%s/adventurer_%s_lib.res" % [OUT_DIR, gender]
	var err: Error = ResourceSaver.save(lib, out_path)
	print("[bake] %s -> %s (err=%d, %d clips)" % [gender, out_path, err, lib.get_animation_list().size()])

## Source clip -> runtime-body clip (see PROVENANCE RULE above).
func _convert(src_path: String, skeleton: Skeleton3D, loop: bool) -> Animation:
	var ps: PackedScene = load(src_path)
	if ps == null:
		push_error("[bake] missing source %s" % src_path)
		return null
	var inst: Node = ps.instantiate()
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var src: Animation = ap.get_animation(ap.get_animation_list()[0])
	var out := Animation.new()
	out.length = src.length
	out.step = src.step
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var arm_pos: int = -1
	var arm_rot: int = -1
	var arm_scl: int = -1
	var skipped: PackedStringArray = []
	for ti: int in src.get_track_count():
		var path: NodePath = src.track_get_path(ti)
		var type: Animation.TrackType = src.track_get_type(ti)
		if path.get_subname_count() == 0:
			if str(path).ends_with("Armature"):
				match type:
					Animation.TYPE_POSITION_3D: arm_pos = ti
					Animation.TYPE_ROTATION_3D: arm_rot = ti
					Animation.TYPE_SCALE_3D: arm_scl = ti
			continue
		var bone: String = str(path.get_subname(path.get_subname_count() - 1))
		bone = FINGER_REMAP.get(bone, bone)
		if skeleton.find_bone(bone) == -1:
			skipped.append(bone)
			continue
		if type == Animation.TYPE_SCALE_3D:
			continue   ## the bodies never scale bones; source scale keys are noise
		var oi: int = out.add_track(type)
		out.track_set_path(oi, NodePath(BODY_PREFIX + "%GeneralSkeleton:" + bone))
		out.track_set_interpolation_type(oi, src.track_get_interpolation_type(ti))
		out.track_set_interpolation_loop_wrap(oi, src.track_get_interpolation_loop_wrap(ti))
		for k: int in src.track_get_key_count(ti):
			out.track_insert_key(oi, src.track_get_key_time(ti, k),
				src.track_get_key_value(ti, k), src.track_get_key_transition(ti, k))
	if arm_rot != -1:
		_convert_armature(src, out, arm_pos, arm_rot, arm_scl)
	if not skipped.is_empty():
		print("[bake]   %s: dropped tracks for bones absent on the body: %s" % [src_path.get_file(), ", ".join(skipped)])
	inst.free()
	return out

## Maximo root motion: runtime armature transform = A(t) · A_rest⁻¹.
func _convert_armature(src: Animation, out: Animation, pi_: int, ri: int, si: int) -> void:
	var rest_inv: Transform3D = armature_rest().affine_inverse()
	var pt: int = out.add_track(Animation.TYPE_POSITION_3D)
	var rt: int = out.add_track(Animation.TYPE_ROTATION_3D)
	out.track_set_path(pt, NodePath(ARMATURE_PATH))
	out.track_set_path(rt, NodePath(ARMATURE_PATH))
	var steps: int = maxi(1, int(ceil(src.length * RESAMPLE_FPS)))
	var prev_q := Quaternion.IDENTITY
	for i: int in steps + 1:
		var t: float = minf(src.length, float(i) / RESAMPLE_FPS)
		var p: Vector3 = src.position_track_interpolate(pi_, t) if pi_ != -1 else Vector3.ZERO
		var q: Quaternion = src.rotation_track_interpolate(ri, t)
		var s: Vector3 = src.scale_track_interpolate(si, t) if si != -1 else Vector3.ONE * 100.0
		var m: Transform3D = Transform3D(Basis(q).scaled(s), p) * rest_inv
		var rq: Quaternion = m.basis.get_rotation_quaternion()
		if i > 0 and prev_q.dot(rq) < 0.0:
			rq = -rq   ## keep the hemisphere continuous for clean interpolation
		prev_q = rq
		out.track_insert_key(pt, t, m.origin)
		out.track_insert_key(rt, t, rq)

## Removes the constant horizontal travel of the Hips position track so the
## loop plays in place; vertical bob and lateral sway are kept.
func _make_in_place(anim: Animation) -> void:
	for ti: int in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(ti)).ends_with(":Hips"):
			continue
		var n: int = anim.track_get_key_count(ti)
		if n < 2:
			return
		var p0: Vector3 = anim.track_get_key_value(ti, 0)
		var travel: Vector3 = anim.track_get_key_value(ti, n - 1) - p0
		travel.y = 0.0
		for k: int in n:
			var frac: float = anim.track_get_key_time(ti, k) / anim.length
			anim.track_set_key_value(ti, k, anim.track_get_key_value(ti, k) - travel * frac)
		return

## Runtime-identical holder: Holder -> MaleModel (rotated PI, as the controller does).
func _make_rig(body_scene: PackedScene, lib: AnimationLibrary) -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	var body: Node3D = body_scene.instantiate()
	body.name = "MaleModel"
	body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	holder.add_child(body)
	var ap := AnimationPlayer.new()
	ap.name = "AP"
	holder.add_child(ap)
	ap.add_animation_library("", lib)
	return holder

func _pose(rig: Node3D, key: String, t: float) -> Skeleton3D:
	var ap: AnimationPlayer = rig.get_node("AP")
	## Reset first so tracks absent from this clip never inherit another pose.
	var sk: Skeleton3D = rig.find_child("GeneralSkeleton", true, false)
	sk.reset_bone_poses()
	(rig.get_node("MaleModel/CharacterArmature") as Node3D).transform = Transform3D.IDENTITY
	ap.play(key)
	ap.seek(t, true)
	return sk

func _bone_holder(rig: Node3D, sk: Skeleton3D, bone: String) -> Transform3D:
	return rig.global_transform.affine_inverse() * sk.global_transform \
		* sk.get_bone_global_pose(sk.find_bone(bone))

func _analyse(rig: Node3D, key: String, kind: String, src: String) -> void:
	var ap: AnimationPlayer = rig.get_node("AP")
	var anim: Animation = ap.get_animation(key)
	var hips := PackedVector3Array()
	var fwd := PackedVector3Array()
	var feet := PackedVector3Array()
	var feet_low := PackedFloat32Array()
	var head := PackedVector3Array()
	var lfoot_ahead := PackedFloat32Array()
	for i: int in ANALYSIS_SAMPLES:
		## Stop just short of the end: seeking a looping clip to its exact
		## length wraps back to frame 0.
		var t: float = minf(anim.length * float(i) / float(ANALYSIS_SAMPLES - 1), anim.length - 0.0005)
		var sk: Skeleton3D = _pose(rig, key, t)
		var h: Transform3D = _bone_holder(rig, sk, "Hips")
		var lf: Vector3 = _bone_holder(rig, sk, "LeftFoot").origin
		var rf: Vector3 = _bone_holder(rig, sk, "RightFoot").origin
		hips.append(h.origin)
		head.append(_bone_holder(rig, sk, "Head").origin)
		fwd.append(h.basis.z.normalized())   ## Humanoid bones face +Z
		feet.append((lf + rf) * 0.5)
		feet_low.append(minf(lf.y, rf.y))
		## Holder forward is -Z (body rotated PI); positive = left foot ahead.
		lfoot_ahead.append(rf.z - lf.z)
	anim.set_meta("source", src)
	anim.set_meta("hips", hips)
	anim.set_meta("hips_forward", fwd)
	anim.set_meta("head", head)
	anim.set_meta("feet", feet)
	anim.set_meta("feet_low", feet_low)
	if kind == "lean":
		## The wall the pose leans on = the rear-most point of the SKINNED body
		## (back, backpack or raised sole), averaged over the loop. Holder
		## space faces -Z, so "rear" is +Z.
		var rear: float = 0.0
		for t: float in [0.0, 0.25, 0.5, 0.75]:
			var sk: Skeleton3D = _pose(rig, key, anim.length * t)
			rear += _rear_extent(rig, sk)
		anim.set_meta("wall_back", rear / 4.0)
		print("[bake]   %-12s lean   len=%.3fs wall_back=%.3fm (holder)" % [key, anim.length, rear / 4.0])
		return
	if kind == "gait":
		var travel: Vector3 = hips[hips.size() - 1] - hips[0]
		travel.y = 0.0
		var best: int = 0
		for i: int in lfoot_ahead.size():
			if lfoot_ahead[i] > lfoot_ahead[best]:
				best = i
		var phase_offset: float = anim.length * float(best) / float(ANALYSIS_SAMPLES - 1)
		anim.set_meta("stride_length", travel.length())       ## holder metres per full cycle
		anim.set_meta("phase_offset", phase_offset)           ## seconds: left-heel-strike
		print("[bake]   %-12s gait  len=%.3fs stride=%.3fm native=%.2fm/s phase=%.2fs" % [
			key, anim.length, travel.length(), travel.length() / anim.length, phase_offset])
	else:
		print("[bake]   %-12s %-6s len=%.3fs hips %s -> %s  feet_low %.3f -> %.3f" % [
			key, kind, anim.length, hips[0], hips[hips.size() - 1], feet_low[0], feet_low[feet_low.size() - 1]])

## Rear-most (+Z, holder space) point of the visible skinned meshes in the
## current pose. Evaluates linear-blend skinning on the CPU from the mesh's
## bone indices/weights and the skin binds — measurement only.
func _rear_extent(rig: Node3D, sk: Skeleton3D) -> float:
	var to_holder: Transform3D = rig.global_transform.affine_inverse() * sk.global_transform
	var rear: float = -INF
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.skin == null or mi.mesh == null or mi.name.to_lower() == "backpack":
			continue   ## the male backpack piece is hidden at runtime
		var binds: Array[Transform3D] = []
		for b: int in mi.skin.get_bind_count():
			var bone: int = mi.skin.get_bind_bone(b)
			if bone == -1:
				bone = sk.find_bone(mi.skin.get_bind_name(b))
			binds.append(sk.get_bone_global_pose(bone) * mi.skin.get_bind_pose(b))
		for surf: int in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty():
				continue
			var per: int = bones.size() / verts.size()
			for v: int in verts.size():
				var p := Vector3.ZERO
				for k: int in per:
					var w: float = weights[v * per + k]
					if w > 0.0:
						p += (binds[bones[v * per + k]] * verts[v]) * w
				rear = maxf(rear, (to_holder * p).z)
	return rear

