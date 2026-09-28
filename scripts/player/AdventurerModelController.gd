class_name AdventurerModelController
extends Node3D
## AdventurerModelController.gd — animation for the V1 Adventurer bodies
## (player + NPCs, both genders).
##
## Read docs/systems/player-model/ANIMATIONS.md before changing this file.
##
## Three layers, blended by one AnimationTree (deterministic, advanced manually
## at the end of _process so every weight/time below applies the same frame):
##
##   LOCOMOTION  idle / walk / run. Walk and run are baked in place and share
##               one gait PHASE that advances by ground distance / stride
##               length, so a planted foot moves at exactly the ground speed
##               (no foot sliding) at any speed; the walk↔run mix is chosen from
##               the real speed. Carrying overlays idle_carry's arms only.
##   ACTIONS     one-shots and furniture loops (sit, lie, sleep, stand, die) in
##               two cross-fading slots. Each slot owns its clip time (so clips
##               can be held, looped or played backwards) and its own WORLD
##               placement. The final body placement blends the slots with the
##               same weights as their poses, so cross-fades never slide.
##   WARPING     furniture actions keep the clip's authored full-body motion.
##               The small error between where the clip would land and where
##               the chair/bed actually is gets distributed along the clip's own
##               hip travel (translation) and its feet-in-the-air window (yaw),
##               the way modern "motion warping" does it.
##
## Every pose comes from the human-made source clips (see
## tools/anim_pipeline/bake_adventurer_anims.gd). Nothing here authors keys.
##
## Public surface (unchanged callers): is_sit_sequence_active(),
## is_animation_locked(), get_visual_yaw(), get_stand_end_position(),
## sit_animation_finished, stand_animation_finished. Furniture use is started
## by the parent setting `seated_chair` / `sleeping_bed`, and ended by clearing
## it — the controller reads the furniture node itself to plan the motion.

signal sit_animation_finished()
signal stand_animation_finished()

## How quickly the visual facing catches up to the character's rotation.y.
@export var turn_speed: float = 12.0
## Legacy: old scenes carried a second, shadow-only model. Hidden if set.
@export var is_shadow_only: bool = false
## NPCs roll their own body gender (cached on the parent as a meta).
@export var randomize_gender: bool = false

const BODY_SCENE_PATHS: Dictionary = {
	"male": "res://assets/models/player/adventurer/Adventurer_Male.fbx",
	"female": "res://assets/models/player/adventurer/Adventurer_Female.fbx",
}
const LIBRARY_PATHS: Dictionary = {
	"male": "res://assets/models/player/anims/adventurer_male_lib.res",
	"female": "res://assets/models/player/anims/adventurer_female_lib.res",
}
const LIB: String = "body"
const PistolLayer = preload("res://scripts/weapons/PistolAnimationLayer.gd")
var _pistol_layer: PistolLayer

const ProceduralPose: GDScript = preload("res://scripts/player/AdventurerProceduralPose.gd")
const FALLBACK_CAPSULE_HEIGHT: float = 2.0

# ─── Locomotion tuning ───────────────────────────────────────────────────────
## Below this real speed (m/s) the character is standing.
const MOVE_START_SPEED: float = 0.08
## Speed (m/s) at which the idle→gait blend is complete.
const MOVE_FULL_SPEED: float = 0.7
## Per-second smoothing rates for the blend weights.
const MOVE_BLEND_RATE: float = 9.0
const GAIT_BLEND_RATE: float = 6.0
const CARRY_BLEND_RATE: float = 7.0
## Per-second smoothing of the measured speed (kills physics jitter).
const SPEED_SMOOTH_RATE: float = 14.0
## Turning on the spot still needs footsteps: the feet sit ~this far from the
## body's vertical axis, so a turn at ω rad/s moves them at ω × radius.
const TURN_STEP_RADIUS: float = 0.18
## Procedural lean (AdventurerProceduralPose): bank into turns by
## yaw-rate × speed, tip with acceleration. Radians; kept subtle.
const LEAN_ROLL_GAIN: float = 0.012
const LEAN_ROLL_MAX: float = 0.13
const LEAN_PITCH_GAIN: float = 0.006
const LEAN_PITCH_MAX: float = 0.09
const LEAN_SMOOTH_RATE: float = 6.0
## Pillow head support fade rate while sleeping, per second.
const HEAD_SUPPORT_RATE: float = 1.2
## Look-at: glance at what the character is about to use (player: the
## interaction prompt's focus; NPC: its activity's attention target).
const LOOK_RANGE: float = 3.5
const LOOK_HEIGHT: float = 0.3

# ─── Furniture tuning (world metres) ─────────────────────────────────────────
## Hip bone height above a seat surface when sitting (pelvis half-depth).
const SEAT_HIPS_CLEARANCE: float = 0.08
## Hips sit this far behind a chair's seat centre (towards the backrest).
const SEAT_HIPS_BACK: float = 0.05
## Hip bone height above the mattress when lying on the back.
const LIE_HIPS_CLEARANCE: float = 0.12
## How far in from the bed's side edge the hips sit (bed-local |z|).
const BED_EDGE_HIPS_Z: float = 0.30
## Bed-local X of the head when lying (the pillow; headboard is at -X).
const BED_HEAD_X: float = -0.84
## Bed-local X range the seated hips may use.
const BED_SEAT_X_RANGE: Vector2 = Vector2(-0.3, 0.95)
## Calm walk used to reach the exact start spot of a sit/lie.
const APPROACH_SPEED: float = 1.25
const APPROACH_ARRIVE: float = 0.03
## In-place pivot rate before sitting, rad/s.
const PIVOT_RATE: float = 4.5
## Playback rates.
const SIT_RATE: float = 1.0
const LIE_RATE: float = 1.15
const GET_UP_RATE: float = 1.25
const STAND_RATE: float = 1.0

## Cross-fade durations (s) between the named stages.
const XF_ENTER_ACTION: float = 0.3
const XF_SEAT_LOOP: float = 0.7
const XF_STAND: float = 0.35
const XF_TO_LIE: float = 0.5
const XF_TO_SLEEP: float = 1.2
const XF_WAKE: float = 0.9
const XF_EXIT: float = 0.45
const XF_DEATH: float = 0.2
## Wall lean: blend in/out of the loop (no transition clips exist, so these
## are long enough to read as settling back / pushing off).
const XF_LEAN_IN: float = 0.75
const XF_LEAN_OUT: float = 0.6
## Keep the capsule this much further from the wall than its radius.
const LEAN_CAPSULE_GAP: float = 0.02
const XF_DEATH_TURN: float = 0.35
## Free floor wanted beyond the dying clip's own travel (m).
const DEATH_CLEARANCE: float = 0.3

enum Stage { NONE, APPROACH, PIVOT, SIT_DOWN, SEATED, LIE_DOWN, SLEEP, GET_UP, STAND_UP, DEAD, LEAN }

## A furniture-use plan: every target the stages need, computed once.
class FurniturePlan:
	var is_bed: bool = false
	var is_lean: bool = false
	var lean_base: Transform3D       ## world placement of the lean loop
	var approach_pos: Vector3        ## world floor point the clip starts from
	var approach_yaw: float
	var seat_hips: Vector3           ## world hip target when seated
	var seat_yaw: float
	var lie_hips: Vector3            ## world hip target when lying (bed)
	var head_dir: Vector3            ## world direction feet→head when lying
	var stand_end_pos: Vector3       ## world floor point the stand-up ends at
	var stand_end_yaw: float

## One clip placed in the world. Placement = warp(t) (see _warp_world()).
class ActionSlot:
	var clip: StringName = &""
	var time: float = 0.0
	var rate: float = 1.0
	var length: float = 1.0
	var looping: bool = false
	var base: Transform3D            ## W0: clip start placement
	var dpsi: float = 0.0            ## yaw correction reached at the end
	var dp: Vector3 = Vector3.ZERO   ## translation correction reached at the end
	var yaw_by_feet: bool = false    ## yaw correction paced by feet lift (lie down)
	var world: Transform3D           ## cached placement for this frame

var _player: CharacterBody3D = null
var _gender: String = "male"
var _visual: Node3D = null
var _skeleton: Skeleton3D = null
var _tree: AnimationTree = null
var _lib: AnimationLibrary = null
var _scale: float = 1.0

## Locomotion state.
var _visual_yaw: float = 0.0
var _speed: float = 0.0
var _phase: float = 0.0
var _move_w: float = 0.0
var _run_w: float = 0.0
var _carry_w: float = 0.0
var _walk_stride: float = 1.5      ## holder metres per cycle (bake metadata)
var _run_stride: float = 2.9
var _walk_len: float = 1.0
var _run_len: float = 0.7
var _walk_phase0: float = 0.0
var _run_phase0: float = 0.0
var _pose_mod: SkeletonModifier3D = null   ## AdventurerProceduralPose
var _prev_yaw: float = 0.0
var _prev_speed: float = 0.0
var _yaw_rate: float = 0.0
var _accel: float = 0.0
var _look_point: Vector3 = Vector3.ZERO

## Action state.
var _stage: Stage = Stage.NONE
var _plan: FurniturePlan = null
var _slots: Array[ActionSlot] = [ActionSlot.new(), ActionSlot.new()]
var _active_slot: int = 0
var _ab_w: float = 0.0             ## 0 = slot A shown, 1 = slot B shown
var _ab_target: float = 0.0
var _xfade_ab: float = 0.3
var _act_w: float = 0.0            ## 0 = locomotion, 1 = actions
var _act_target: float = 0.0
var _xfade_act: float = 0.3
var _last_visual_world: Transform3D = Transform3D.IDENTITY
var _lie_slot_backup: ActionSlot = null
var _stand_end_known: bool = false
## Wall lean request (begin_lean / end_lean).
var _lean_request: bool = false
var _lean_point: Vector3 = Vector3.ZERO
var _lean_normal: Vector3 = Vector3.BACK

# ─── Setup ───────────────────────────────────────────────────────────────────
func _ready() -> void:
	if get_parent() is CharacterBody3D:
		_player = get_parent() as CharacterBody3D
		_visual_yaw = _player.rotation.y
		_prev_yaw = _visual_yaw
	_gender = _resolve_gender()

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var body: Node3D = (load(BODY_SCENE_PATHS.get(_gender, BODY_SCENE_PATHS["male"])) as PackedScene).instantiate()
	## Load-bearing: every baked track is "MaleModel/%GeneralSkeleton:<bone>".
	body.name = "MaleModel"
	## FBX forward vs Godot -Z forward (both bodies need the same flip).
	body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	_visual.add_child(body)
	_skeleton = body.find_child("GeneralSkeleton", true, false) as Skeleton3D
	_pose_mod = ProceduralPose.new()
	_pose_mod.name = "ProceduralPose"
	_skeleton.add_child(_pose_mod)

	position.y = -_capsule_height() * 0.5 if _player != null else 0.0
	_setup_meshes()
	_lib = load(LIBRARY_PATHS.get(_gender, LIBRARY_PATHS["male"])) as AnimationLibrary
	_read_gait_metadata()
	_build_tree()
	# NPCs retain their existing tree; weapon input/locomotion is player-owned.
	if _player != null and not randomize_gender:
		_pistol_layer = PistolLayer.new()
		_pistol_layer.install(self)
	_last_visual_world = _visual.global_transform

func _resolve_gender() -> String:
	if randomize_gender and _player != null:
		if not _player.has_meta("_adventurer_random_gender"):
			_player.set_meta("_adventurer_random_gender", "male" if randi() % 2 == 0 else "female")
		return String(_player.get_meta("_adventurer_random_gender"))
	if randomize_gender and get_parent() != null and get_parent().has_meta("_adventurer_random_gender"):
		return String(get_parent().get_meta("_adventurer_random_gender"))
	return CharacterCreationData.gender

func _capsule_height() -> float:
	var shape_node: Node = _player.get_node_or_null("CollisionShape3D")
	if shape_node is CollisionShape3D and (shape_node as CollisionShape3D).shape is CapsuleShape3D:
		return ((shape_node as CollisionShape3D).shape as CapsuleShape3D).height
	return FALLBACK_CAPSULE_HEIGHT

func _setup_meshes() -> void:
	for node: Node in _find_all_of_type(self, "MeshInstance3D"):
		var mi: MeshInstance3D = node as MeshInstance3D
		if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
			mi.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
		else:
			## NPCs: tag for the dynamic-shadow budget (GraphicsSettings).
			mi.layers |= GraphicsSettings.NPC_SHADOW_LAYER_BIT
		if mi.name.to_lower() == "backpack":
			mi.visible = false   ## the male body's separate backpack piece is off by request
	_apply_dynamic_shadow()
	if not GraphicsSettings.settings_changed.is_connected(_apply_dynamic_shadow):
		GraphicsSettings.settings_changed.connect(_apply_dynamic_shadow)

## Characters cast only while GraphicsSettings' dynamic (layer 2) shadows are on.
func _apply_dynamic_shadow() -> void:
	var layer2: bool = GraphicsSettings.shadow_casting_enabled
	for node: Node in _find_all_of_type(self, "MeshInstance3D"):
		(node as MeshInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if layer2 and not is_shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if is_shadow_only:
		visible = false

## The idle's ankle height above the floor (model units), for the IK floor.
var _ankle_rest_height: float = 0.024

func _read_gait_metadata() -> void:
	var idle_low: PackedFloat32Array = _lib.get_animation("idle").get_meta("feet_low", PackedFloat32Array())
	if not idle_low.is_empty():
		_ankle_rest_height = idle_low[0]
	var walk: Animation = _lib.get_animation("walk")
	var run: Animation = _lib.get_animation("run")
	_walk_len = walk.length
	_run_len = run.length
	_walk_stride = float(walk.get_meta("stride_length", 1.5))
	_run_stride = float(run.get_meta("stride_length", 2.9))
	_walk_phase0 = float(walk.get_meta("phase_offset", 0.0))
	_run_phase0 = float(run.get_meta("phase_offset", 0.0))

func _anim_node(clip: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = StringName(LIB + "/" + clip)
	return node

func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("idle", _anim_node("idle"))
	for gait: String in ["walk", "run"]:
		bt.add_node(gait, _anim_node(gait))
		bt.add_node(gait + "_seek", AnimationNodeTimeSeek.new())
		bt.connect_node(gait + "_seek", 0, gait)
	bt.add_node("gait", AnimationNodeBlend2.new())
	bt.connect_node("gait", 0, "walk_seek")
	bt.connect_node("gait", 1, "run_seek")
	bt.add_node("loco", AnimationNodeBlend2.new())
	bt.connect_node("loco", 0, "idle")
	bt.connect_node("loco", 1, "gait")

	## Carrying: idle_carry's arms (and only its arms) over any gait.
	bt.add_node("idle_carry", _anim_node("idle_carry"))
	var carry := AnimationNodeBlend2.new()
	carry.filter_enabled = true
	for i: int in _skeleton.get_bone_count():
		var bone: String = _skeleton.get_bone_name(i)
		if _is_arm_bone(bone):
			carry.set_filter_path(NodePath("MaleModel/%GeneralSkeleton:" + bone), true)
	bt.add_node("carry", carry)
	bt.connect_node("carry", 0, "loco")
	bt.connect_node("carry", 1, "idle_carry")

	for slot: String in ["act_a", "act_b"]:
		bt.add_node(slot, _anim_node("idle"))
		bt.add_node(slot + "_seek", AnimationNodeTimeSeek.new())
		bt.connect_node(slot + "_seek", 0, slot)
	bt.add_node("act", AnimationNodeBlend2.new())
	bt.connect_node("act", 0, "act_a_seek")
	bt.connect_node("act", 1, "act_b_seek")
	bt.add_node("out", AnimationNodeBlend2.new())
	bt.connect_node("out", 0, "carry")
	bt.connect_node("out", 1, "act")
	bt.connect_node("output", 0, "out")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	add_child(_tree)
	_tree.add_animation_library(LIB, _lib)
	_tree.root_node = _tree.get_path_to(_visual)
	## Tracks a clip doesn't key fall back to rest — no pose ever leaks from a
	## previous clip (the old "stuck hip tilt after standing up" bug).
	_tree.deterministic = true
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tree.tree_root = bt
	_tree.active = true

static func _is_arm_bone(bone: String) -> bool:
	for key: String in ["Shoulder", "UpperArm", "LowerArm", "Hand", "Thumb", "Index", "Middle", "Ring", "Little", "Pinky"]:
		if bone.contains(key):
			return true
	return false

# ─── Frame ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _tree == null:
		return
	_scale = global_transform.basis.get_scale().x
	if _player != null:
		_update_stage(delta)
		_update_locomotion(delta)
	_update_slots(delta)
	_apply_tree_params()
	if _pistol_layer != null:
		_pistol_layer.update(delta)
	_tree.advance(delta)
	_place_visual()

func _update_stage(delta: float) -> void:
	if _is_dead():
		if _stage != Stage.DEAD:
			_enter_death()
		return
	var furniture: Node3D = _parent_furniture()
	match _stage:
		Stage.NONE:
			if furniture != null:
				_begin_furniture(furniture)
			elif _lean_request:
				_plan = _plan_lean()
				_stand_end_known = true
				_stage = Stage.APPROACH
		Stage.APPROACH:
			if _released(furniture):
				_finish_sequence()
			else:
				_tick_approach(delta)
		Stage.PIVOT:
			if _released(furniture):
				_finish_sequence()
			else:
				_tick_pivot(delta)
		Stage.LEAN:
			if not _lean_request:
				_finish_sequence()
		Stage.SIT_DOWN:
			if _slot_done():
				sit_animation_finished.emit()
				if furniture == null:
					_start_stand_up()
				elif _plan.is_bed:
					_start_lie_down()
				else:
					_start_seated_loop()
		Stage.SEATED:
			if furniture == null:
				_start_stand_up()
		Stage.LIE_DOWN:
			if furniture == null:
				_start_get_up(false)
			elif _slot_done():
				_start_sleep_loop()
		Stage.SLEEP:
			if furniture == null:
				_start_get_up(true)
		Stage.GET_UP:
			if _slot_done():
				_start_stand_up()
		Stage.STAND_UP:
			if _slot_done():
				_finish_sequence()

# ─── Locomotion ──────────────────────────────────────────────────────────────
func _update_locomotion(delta: float) -> void:
	var speed: float = _speed
	if _stage != Stage.APPROACH and _stage != Stage.PIVOT:
		## get_real_velocity(): what move_and_slide ACHIEVED — a blocked
		## character never "ghost-walks" in place.
		var v: Vector3 = _player.get_real_velocity()
		var measured: float = Vector2(v.x, v.z).length() if _stage == Stage.NONE else 0.0
		speed = lerpf(_speed, measured, clampf(SPEED_SMOOTH_RATE * delta, 0.0, 1.0))
		if _stage == Stage.NONE:
			_visual_yaw = lerp_angle(_visual_yaw, _player.rotation.y, clampf(turn_speed * delta, 0.0, 1.0))
	_speed = speed

	## Leg speed = ground speed + the feet's turning arc (turn-on-the-spot steps).
	var leg_speed: float = speed
	if _stage == Stage.NONE:
		leg_speed += absf(_yaw_rate) * TURN_STEP_RADIUS
	var walk_speed: float = _walk_stride * _scale / _walk_len
	var run_speed: float = _run_stride * _scale / _run_len
	var run_target: float = clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
	_run_w = lerpf(_run_w, run_target, clampf(GAIT_BLEND_RATE * delta, 0.0, 1.0))
	var move_target: float = smoothstep(MOVE_START_SPEED, MOVE_FULL_SPEED, leg_speed)
	_move_w = lerpf(_move_w, move_target, clampf(MOVE_BLEND_RATE * delta, 0.0, 1.0))
	var carry_target: float = 1.0 if _is_holding_item() and _stage == Stage.NONE else 0.0
	_carry_w = lerpf(_carry_w, carry_target, clampf(CARRY_BLEND_RATE * delta, 0.0, 1.0))
	## Distance-driven phase: one cycle per blended stride length.
	var stride: float = lerpf(_walk_stride, _run_stride, _run_w) * _scale
	if stride > 0.0:
		_phase = fposmod(_phase + leg_speed * delta / stride, 1.0)
	_update_procedural_pose(speed, delta)

## Feeds AdventurerProceduralPose: lean into turns / acceleration while moving
## freely, pillow head support while asleep.
func _update_procedural_pose(speed: float, delta: float) -> void:
	if delta <= 0.0:
		return
	var k: float = clampf(LEAN_SMOOTH_RATE * delta, 0.0, 1.0)
	_yaw_rate = lerpf(_yaw_rate, wrapf(_visual_yaw - _prev_yaw, -PI, PI) / delta, k)
	_accel = lerpf(_accel, (speed - _prev_speed) / delta, k)
	_prev_yaw = _visual_yaw
	_prev_speed = speed
	var free: bool = _stage == Stage.NONE
	var roll: float = clampf(_yaw_rate * speed * LEAN_ROLL_GAIN, -LEAN_ROLL_MAX, LEAN_ROLL_MAX) if free else 0.0
	var pitch: float = clampf(_accel * LEAN_PITCH_GAIN, -LEAN_PITCH_MAX, LEAN_PITCH_MAX) * _move_w if free else 0.0
	_pose_mod.lean_roll = lerpf(_pose_mod.lean_roll, roll, k)
	_pose_mod.lean_pitch = lerpf(_pose_mod.lean_pitch, pitch, k)
	## Feet stay planted wherever they can touch the floor; never on the bed
	## or while the dying clip throws the body around.
	_pose_mod.foot_lock_enabled = not _stage in [Stage.DEAD, Stage.LIE_DOWN, Stage.SLEEP, Stage.GET_UP]
	_pose_mod.floor_y = _floor_y()
	_pose_mod.ankle_floor_height = _ankle_rest_height * _scale
	_pose_mod.body_speed = speed
	## Flat feet while standing still and through sit/stand/lean transitions;
	## walking keeps the clips' own heel-toe roll.
	var flatten: float = 1.0 if _stage in [Stage.SIT_DOWN, Stage.SEATED, Stage.STAND_UP, Stage.LEAN] \
		else (1.0 - smoothstep(0.1, 0.5, speed) if _stage in [Stage.NONE, Stage.PIVOT] else 0.0)
	_pose_mod.foot_flatten = move_toward(_pose_mod.foot_flatten, flatten, delta * 4.0)
	_update_look(delta)
	var support: float = 1.0 if _stage == Stage.SLEEP else 0.0
	_pose_mod.head_support = move_toward(_pose_mod.head_support, support,
		delta * (HEAD_SUPPORT_RATE if support > 0.0 else HEAD_SUPPORT_RATE * 2.0))

## Head look-at is NPC-only (Brannon, 2026-09-28): the player's head no
## longer follows interaction focus, and NPC glances are subtle — a gentler
## weight, slow easing, and a minimum hold per target so the head doesn't
## flick between every object that passes through range.
const NPC_LOOK_WEIGHT: float = 0.4
const NPC_LOOK_FOLLOW_RATE: float = 1.6
const NPC_LOOK_FADE_RATE: float = 1.2
const NPC_LOOK_MIN_HOLD: float = 2.5
var _look_held: Node3D = null
var _look_hold_left: float = 0.0

func _update_look(delta: float) -> void:
	var want: float = 0.0
	var target: Node3D = _look_target() if _stage in [Stage.NONE, Stage.SEATED, Stage.LEAN] else null
	## Hold the current target for a moment before switching to a new one.
	_look_hold_left -= delta
	if target != _look_held:
		if _look_held != null and is_instance_valid(_look_held) and _look_hold_left > 0.0:
			target = _look_held
		else:
			_look_held = target
			_look_hold_left = NPC_LOOK_MIN_HOLD
	if target != null:
		var point: Vector3 = target.global_position + Vector3.UP * LOOK_HEIGHT
		var to: Vector3 = point - _visual.global_position
		var facing := Vector3(-sin(_visual_yaw), 0.0, -cos(_visual_yaw))
		if Vector2(to.x, to.z).length() < LOOK_RANGE and facing.dot(Vector3(to.x, 0.0, to.z).normalized()) > -0.35:
			want = NPC_LOOK_WEIGHT
			if _pose_mod.look_weight < 0.01:
				_look_point = point
			_look_point = _look_point.lerp(point, clampf(NPC_LOOK_FOLLOW_RATE * delta, 0.0, 1.0))
	_pose_mod.look_weight = move_toward(_pose_mod.look_weight, want, NPC_LOOK_FADE_RATE * delta)
	_pose_mod.look_at_world = _look_point

## Duck-typed: the player's interaction focus, or an NPC activity's
## attention target. Nothing to look at → null.
func _look_target() -> Node3D:
	var target: Variant = null
	if "brain" in _player and _player.brain != null and _player.brain.has_method("current_activity"):
		var activity: Variant = _player.brain.current_activity()
		if activity != null and activity.has_method("attention_target"):
			target = activity.attention_target(_player)
	return target as Node3D if is_instance_valid(target) and target is Node3D else null   ## validity first: `is` on a freed object errors

## True once whatever started the current sequence has been let go.
func _released(furniture: Node3D) -> bool:
	return not _lean_request if _plan != null and _plan.is_lean else furniture == null

# ─── Furniture planning ──────────────────────────────────────────────────────
func _parent_furniture() -> Node3D:
	if _player == null:
		return null
	if "seated_chair" in _player and _player.seated_chair != null and is_instance_valid(_player.seated_chair):
		return _player.seated_chair
	if "sleeping_bed" in _player and _player.sleeping_bed != null and is_instance_valid(_player.sleeping_bed):
		return _player.sleeping_bed
	return null

func _begin_furniture(furniture: Node3D) -> void:
	var is_bed: bool = "sleeping_bed" in _player and _player.sleeping_bed == furniture
	_plan = _plan_bed(furniture) if is_bed else _plan_chair(furniture)
	_stand_end_known = true
	_stage = Stage.APPROACH

func _plan_chair(chair: Node3D) -> FurniturePlan:
	var p := FurniturePlan.new()
	var seat: Transform3D = chair.get_seat_transform() if chair.has_method("get_seat_transform") \
		else chair.global_transform
	p.seat_yaw = _yaw_of(seat.basis.z)
	p.seat_hips = seat.origin - seat.basis.z.normalized() * SEAT_HIPS_BACK \
		+ Vector3.UP * SEAT_HIPS_CLEARANCE
	_plan_sit_and_stand(p)
	return p

func _plan_bed(bed: Node3D) -> FurniturePlan:
	var p := FurniturePlan.new()
	p.is_bed = true
	var bt: Transform3D = bed.global_transform
	var local_char: Vector3 = bt.affine_inverse() * _last_visual_world.origin
	var side: float = 1.0 if local_char.z >= 0.0 else -1.0
	var surface_y: float = float(bed.get("SHEETS_SURFACE_Y")) if "SHEETS_SURFACE_Y" in bed else 0.4971
	var out_dir: Vector3 = (bt.basis.z * side).normalized()
	p.seat_yaw = _yaw_of(out_dir)
	p.head_dir = -bt.basis.x.normalized()
	var head_to_hips: float = _lying_head_to_hips()
	p.lie_hips = bt * Vector3(BED_HEAD_X, surface_y, 0.0) - p.head_dir * head_to_hips \
		+ Vector3.UP * LIE_HIPS_CLEARANCE
	## Choose where along the edge to sit so the clip's own backward travel
	## lands the head on the pillow with (almost) no along-bed warping.
	var seat_x: float = 0.4
	for _i: int in 2:
		p.seat_hips = bt * Vector3(seat_x, surface_y, side * BED_EDGE_HIPS_Z) + Vector3.UP * SEAT_HIPS_CLEARANCE
		var lie: ActionSlot = _make_lie_slot(p)
		var along: float = lie.dp.dot(-p.head_dir)
		seat_x = clampf(seat_x + along / bt.basis.x.length(), BED_SEAT_X_RANGE.x, BED_SEAT_X_RANGE.y)
	p.seat_hips = bt * Vector3(seat_x, surface_y, side * BED_EDGE_HIPS_Z) + Vector3.UP * SEAT_HIPS_CLEARANCE
	_plan_sit_and_stand(p)
	return p

## Approach spot (where stand_to_sit must start to land its hips on the seat
## naturally) and the natural stand-up landing spot.
func _plan_sit_and_stand(p: FurniturePlan) -> void:
	var sit: Animation = _lib.get_animation("stand_to_sit")
	var sit_end_yaw: float = p.seat_yaw - _clip_yaw(sit, sit.length)
	var w_sit: Transform3D = _placement(sit_end_yaw, _meta_at(sit, "hips", sit.length), p.seat_hips)
	var feet0: Vector3 = w_sit * _meta_at(sit, "feet", 0.0)
	p.approach_pos = Vector3(feet0.x, _floor_y(), feet0.z)
	p.approach_yaw = sit_end_yaw + _clip_yaw(sit, 0.0)
	var stand: Animation = _lib.get_animation("sit_to_stand")
	var stand_yaw: float = p.seat_yaw - _clip_yaw(stand, 0.0)
	var w_stand: Transform3D = _placement(stand_yaw, _meta_at(stand, "hips", 0.0), p.seat_hips)
	var feet_end: Vector3 = w_stand * _meta_at(stand, "feet", stand.length)
	p.stand_end_pos = Vector3(feet_end.x, _floor_y(), feet_end.z)
	p.stand_end_yaw = stand_yaw + _clip_yaw(stand, stand.length)

func _lying_head_to_hips() -> float:
	var lie: Animation = _lib.get_animation("lie_down")
	var d: Vector3 = _meta_at(lie, "head", lie.length) - _meta_at(lie, "hips", lie.length)
	return Vector2(d.x, d.z).length() * _scale

# ─── Stage transitions ───────────────────────────────────────────────────────
func _tick_approach(delta: float) -> void:
	var here: Vector3 = _player.global_position
	var to: Vector3 = Vector3(_plan.approach_pos.x - here.x, 0.0, _plan.approach_pos.z - here.z)
	var dist: float = to.length()
	if dist <= APPROACH_ARRIVE:
		_speed = 0.0
		_stage = Stage.PIVOT
		return
	## Ease in/out so the few short steps don't start or stop abruptly.
	_speed = lerpf(_speed, minf(APPROACH_SPEED, dist * 4.0), clampf(8.0 * delta, 0.0, 1.0))
	var step: float = minf(dist, maxf(_speed, 0.1) * delta)
	_player.global_position += to / dist * step
	if dist > 0.12:
		_visual_yaw = lerp_angle(_visual_yaw, _yaw_of(to), clampf(10.0 * delta, 0.0, 1.0))

func _tick_pivot(delta: float) -> void:
	var diff: float = wrapf(_plan.approach_yaw - _visual_yaw, -PI, PI)
	var step: float = clampf(diff, -PIVOT_RATE * delta, PIVOT_RATE * delta)
	_visual_yaw += step
	## Small shuffle steps while turning on the spot (feet travel ≈ turn arc).
	_speed = lerpf(_speed, absf(step) / maxf(delta, 0.0001) * 0.18, clampf(10.0 * delta, 0.0, 1.0))
	if absf(diff) < 0.02:
		_speed = 0.0
		if _plan.is_lean:
			_start_lean()
		else:
			_start_sit_down()

func _start_sit_down() -> void:
	_stage = Stage.SIT_DOWN
	var slot: ActionSlot = _push_slot(&"stand_to_sit", SIT_RATE, false, XF_ENTER_ACTION)
	var anim: Animation = _lib.get_animation("stand_to_sit")
	slot.base = _placement(_visual_yaw - _clip_yaw(anim, 0.0), _meta_at(anim, "feet", 0.0),
		Vector3(_player.global_position.x, _floor_y(), _player.global_position.z))
	_solve_warp(slot, _plan.seat_yaw, "hips", _plan.seat_hips)
	_act_target = 1.0
	_xfade_act = XF_ENTER_ACTION

func _start_seated_loop() -> void:
	_stage = Stage.SEATED
	var slot: ActionSlot = _push_slot(&"sit", 1.0, true, XF_SEAT_LOOP)
	var anim: Animation = _lib.get_animation("sit")
	slot.base = _placement(_plan.seat_yaw - _clip_yaw(anim, 0.0), _meta_at(anim, "hips", 0.0), _plan.seat_hips)

func _start_lie_down() -> void:
	_stage = Stage.LIE_DOWN
	var slot: ActionSlot = _push_slot(&"lie_down", LIE_RATE, false, XF_TO_LIE)
	var built: ActionSlot = _make_lie_slot(_plan)
	slot.base = built.base
	slot.dpsi = built.dpsi
	slot.dp = built.dp
	slot.yaw_by_feet = true
	_lie_slot_backup = built

## Lie-down placement: starts with the hips on the bed edge facing out, ends
## on the bed's centre line with the head on the pillow. The yaw correction
## (≈90°, the clip itself lies straight back) happens while the legs are
## lifting, pivoting about the hips — the way people swing their legs up.
func _make_lie_slot(p: FurniturePlan) -> ActionSlot:
	var anim: Animation = _lib.get_animation("lie_down")
	var s := ActionSlot.new()
	s.clip = &"lie_down"
	s.length = anim.length
	s.yaw_by_feet = true
	s.base = _placement(p.seat_yaw - _clip_yaw(anim, 0.0), _meta_at(anim, "hips", 0.0), p.seat_hips)
	var head: Vector3 = s.base.basis * (_meta_at(anim, "head", anim.length) - _meta_at(anim, "hips", anim.length))
	s.dpsi = _signed_yaw(Vector3(head.x, 0.0, head.z), p.head_dir)
	var hips_end: Vector3 = s.base * _meta_at(anim, "hips", anim.length)
	s.dp = p.lie_hips - hips_end   ## rotation about the hips leaves them in place
	return s

func _start_sleep_loop() -> void:
	_stage = Stage.SLEEP
	var lie: Animation = _lib.get_animation("lie_down")
	var sleep: Animation = _lib.get_animation("sleep")
	var lie_slot: ActionSlot = _slots[_active_slot]
	var lie_end: Transform3D = _warp_world(lie_slot, lie.length)
	## Align the sleep loop's body to where the lie-down ended: same hips,
	## same feet→head direction.
	var lie_axis: Vector3 = lie_end.basis * (_meta_at(lie, "head", lie.length) - _meta_at(lie, "hips", lie.length))
	var sleep_axis: Vector3 = _meta_at(sleep, "head", 0.0) - _meta_at(sleep, "hips", 0.0)
	var yaw: float = _yaw_of(lie_axis) - _yaw_of(sleep_axis)
	var hips_world: Vector3 = lie_end * _meta_at(lie, "hips", lie.length)
	var slot: ActionSlot = _push_slot(&"sleep", 1.0, true, XF_TO_SLEEP)
	slot.base = _placement(yaw, _meta_at(sleep, "hips", 0.0), hips_world)

func _start_get_up(from_sleep: bool) -> void:
	_stage = Stage.GET_UP
	## The lie-down played backwards: sit up, swing the legs back down. Uses
	## the identical placement so it retraces the same path.
	var t_now: float = _slots[_active_slot].time if not from_sleep else _lib.get_animation("lie_down").length
	var slot: ActionSlot = _push_slot(&"lie_down", -GET_UP_RATE, false, XF_WAKE if from_sleep else XF_STAND)
	var src: ActionSlot = _lie_slot_backup if _lie_slot_backup != null else _make_lie_slot(_plan)
	slot.base = src.base
	slot.dpsi = src.dpsi
	slot.dp = src.dp
	slot.yaw_by_feet = true
	slot.time = t_now

func _start_stand_up() -> void:
	_stage = Stage.STAND_UP
	var slot: ActionSlot = _push_slot(&"sit_to_stand", STAND_RATE, false, XF_STAND)
	var anim: Animation = _lib.get_animation("sit_to_stand")
	slot.base = _placement(_plan.seat_yaw - _clip_yaw(anim, 0.0), _meta_at(anim, "hips", 0.0), _plan.seat_hips)

## Wall lean plan: the lean clip's back surface (bake meta "wall_back", the
## rear-most point of the skinned body) goes on the wall plane, facing out
## along the wall normal. The capsule waits at the hips' floor point, but no
## closer to the wall than its own radius.
func _plan_lean() -> FurniturePlan:
	var p := FurniturePlan.new()
	p.is_lean = true
	var anim: Animation = _lib.get_animation("lean")
	var n := Vector3(_lean_normal.x, 0.0, _lean_normal.z).normalized()
	var yaw: float = _yaw_of(n)
	var wall := Vector3(_lean_point.x, _floor_y(), _lean_point.z)
	p.lean_base = _placement(yaw, Vector3(0.0, 0.0, float(anim.get_meta("wall_back", 0.0))), wall)
	var hips: Vector3 = p.lean_base * _meta_at(anim, "hips", 0.0)
	var stand := Vector3(hips.x, _floor_y(), hips.z)
	var min_gap: float = _capsule_radius() + LEAN_CAPSULE_GAP
	var gap: float = (stand - wall).dot(n)
	if gap < min_gap:
		stand += n * (min_gap - gap)
	p.approach_pos = stand
	p.approach_yaw = yaw
	p.stand_end_pos = stand
	p.stand_end_yaw = yaw
	return p

func _start_lean() -> void:
	_stage = Stage.LEAN
	var slot: ActionSlot = _push_slot(&"lean", 1.0, true, XF_LEAN_IN)
	slot.base = _plan.lean_base
	slot.world = slot.base
	## Desynchronise neighbours leaning at the same time.
	slot.time = randf() * slot.length
	_act_target = 1.0
	_xfade_act = XF_LEAN_IN

func _capsule_radius() -> float:
	var shape_node: Node = _player.get_node_or_null("CollisionShape3D")
	if shape_node is CollisionShape3D and (shape_node as CollisionShape3D).shape is CapsuleShape3D:
		return ((shape_node as CollisionShape3D).shape as CapsuleShape3D).radius
	return 0.35

func _finish_sequence() -> void:
	var was_active: bool = _stage != Stage.NONE
	var from_lean: bool = _plan != null and _plan.is_lean
	if _stage == Stage.STAND_UP:
		## Hand the body back to the capsule exactly where the clip left it.
		var s: ActionSlot = _slots[_active_slot]
		var end_world: Transform3D = _warp_world(s, s.length)
		var anim: Animation = _lib.get_animation("sit_to_stand")
		var feet: Vector3 = end_world * _meta_at(anim, "feet", anim.length)
		_plan.stand_end_pos = Vector3(feet.x, _floor_y(), feet.z)
		_visual_yaw = _yaw_of(end_world.basis * _meta_at(anim, "hips_forward", anim.length))
		_plan.stand_end_yaw = _visual_yaw
	elif _plan != null:
		## Cancelled before sitting: stay where the approach walk got to.
		_plan.stand_end_pos = Vector3(_player.global_position.x, _floor_y(), _player.global_position.z)
		_plan.stand_end_yaw = _visual_yaw
	if _plan != null:
		## The controller owns the whole sequence, so it also returns the
		## capsule to where the body is standing (no pop for player or NPC).
		_player.global_position.x = _plan.stand_end_pos.x
		_player.global_position.z = _plan.stand_end_pos.z
		_player.rotation.y = _plan.stand_end_yaw
		_visual_yaw = _plan.stand_end_yaw
	_stage = Stage.NONE
	_act_target = 0.0
	_xfade_act = XF_LEAN_OUT if from_lean else XF_EXIT
	_lean_request = false
	_speed = 0.0
	_lie_slot_backup = null
	if was_active:
		stand_animation_finished.emit()

func _enter_death() -> void:
	_lean_request = false
	if _stage in [Stage.SIT_DOWN, Stage.SEATED, Stage.LIE_DOWN, Stage.SLEEP, Stage.GET_UP, Stage.STAND_UP]:
		## Dying on furniture: stay where the body is (slumped in the chair,
		## still in bed) instead of snapping to a standing collapse.
		_stage = Stage.DEAD
		for s: ActionSlot in _slots:
			s.rate = 0.0
		return
	_stage = Stage.DEAD
	var slot: ActionSlot = _push_slot(&"dying", 1.0, false, XF_DEATH)
	var anim: Animation = _lib.get_animation("dying")
	var feet: Vector3 = _last_visual_world.origin
	var start := Vector3(feet.x, _floor_y(), feet.z)
	slot.base = _placement(_visual_yaw - _clip_yaw(anim, 0.0), _meta_at(anim, "feet", 0.0), start)
	## The authored collapse travels ~1 m forward. If a wall is in the way,
	## turn the fall towards open floor (eased in by a longer cross-fade)
	## instead of dropping through the wall.
	var travel: Vector3 = slot.base.basis * (_meta_at(anim, "head", anim.length) - _meta_at(anim, "feet", 0.0))
	travel.y = 0.0
	var need: float = travel.length() + DEATH_CLEARANCE
	var xfade: float = XF_DEATH
	for turn: float in [0.0, PI * 0.25, -PI * 0.25, PI * 0.5, -PI * 0.5, PI * 0.75, -PI * 0.75, PI]:
		if _free_distance(start, travel.rotated(Vector3.UP, turn).normalized(), need) >= need:
			if turn != 0.0:
				slot.base = _placement(_visual_yaw + turn - _clip_yaw(anim, 0.0), _meta_at(anim, "feet", 0.0), start)
				xfade = XF_DEATH_TURN
			break
	_xfade_ab = xfade
	_act_target = 1.0
	_xfade_act = xfade

## Clear floor distance (up to max_dist) from `from` along `dir`, probed at
## knee and chest height against world geometry.
func _free_distance(from: Vector3, dir: Vector3, max_dist: float) -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var best: float = max_dist
	for h: float in [0.35, 0.9]:
		var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * h, from + Vector3.UP * h + dir * max_dist)
		q.exclude = [_player.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			best = minf(best, (hit["position"] as Vector3 - q.from).length())
	return best

# ─── Slots ───────────────────────────────────────────────────────────────────
func _push_slot(clip: StringName, rate: float, looping: bool, xfade: float) -> ActionSlot:
	var first: bool = _act_w <= 0.001 and _act_target <= 0.0
	if not first:
		_active_slot = 1 - _active_slot
	var slot := ActionSlot.new()
	slot.clip = clip
	slot.rate = rate
	slot.looping = looping
	slot.length = _lib.get_animation(String(clip)).length
	slot.time = 0.0 if rate >= 0.0 else slot.length
	_slots[_active_slot] = slot
	var node: AnimationNodeAnimation = (_tree.tree_root as AnimationNodeBlendTree).get_node(
		"act_a" if _active_slot == 0 else "act_b")
	node.animation = StringName(LIB + "/" + String(clip))
	_ab_target = float(_active_slot)
	if first:
		_ab_w = _ab_target   ## nothing to fade from inside the action layer
	_xfade_ab = xfade
	return slot

func _slot_done() -> bool:
	var s: ActionSlot = _slots[_active_slot]
	return (s.rate >= 0.0 and s.time >= s.length) or (s.rate < 0.0 and s.time <= 0.0)

func _update_slots(delta: float) -> void:
	for s: ActionSlot in _slots:
		if s.clip == &"":
			continue
		s.time += s.rate * delta
		s.time = fposmod(s.time, s.length) if s.looping else clampf(s.time, 0.0, s.length)
		s.world = _warp_world(s, s.time) if not s.looping else s.base
	_ab_w = move_toward(_ab_w, _ab_target, delta / maxf(_xfade_ab, 0.001))
	_act_w = move_toward(_act_w, _act_target, delta / maxf(_xfade_act, 0.001))

## Warped world placement of a slot's clip at time t:
##   W(t) = T(dp·s(t)) · RotateAbout(hips(t), dpsi·y(t)) · base
## s = normalised hip travel along the clip; y = the same, or (lie-down) the
## normalised rise of the feet. Both are read from the bake's measurements, so
## corrections happen only while the body is genuinely moving.
func _warp_world(s: ActionSlot, t: float) -> Transform3D:
	if s.clip == &"" or (s.dpsi == 0.0 and s.dp == Vector3.ZERO):
		return s.base
	var anim: Animation = _lib.get_animation(String(s.clip))
	var sp: float = _progress(anim, "hips", t)
	var yp: float = _feet_lift_progress(anim, t) if s.yaw_by_feet else sp
	var pivot: Vector3 = s.base * _meta_at(anim, "hips", t)
	var rot := Transform3D(Basis(Vector3.UP, s.dpsi * yp), Vector3.ZERO)
	var about: Transform3D = Transform3D(Basis.IDENTITY, pivot) * rot * Transform3D(Basis.IDENTITY, -pivot)
	return Transform3D(Basis.IDENTITY, s.dp * sp) * about * s.base

## Solves a slot's end corrections: yaw so the clip's end facing matches
## target_yaw, then translation so `feature` ("hips"/"feet") lands on target.
func _solve_warp(s: ActionSlot, target_yaw: float, feature: String, target: Vector3) -> void:
	var anim: Animation = _lib.get_animation(String(s.clip))
	var end_fwd: Vector3 = s.base.basis * _meta_at(anim, "hips_forward", anim.length)
	s.dpsi = wrapf(target_yaw - _yaw_of(end_fwd), -PI, PI)
	s.dp = Vector3.ZERO
	var rotated: Transform3D = _warp_world(s, anim.length)
	s.dp = target - rotated * _meta_at(anim, feature, anim.length)

# ─── Tree + placement ────────────────────────────────────────────────────────
func _apply_tree_params() -> void:
	_tree.set("parameters/walk_seek/seek_request", fposmod(_walk_phase0 + _phase * _walk_len, _walk_len))
	_tree.set("parameters/run_seek/seek_request", fposmod(_run_phase0 + _phase * _run_len, _run_len))
	_tree.set("parameters/gait/blend_amount", _run_w)
	_tree.set("parameters/loco/blend_amount", _move_w)
	_tree.set("parameters/carry/blend_amount", _carry_w)
	_tree.set("parameters/act_a_seek/seek_request", _slots[0].time)
	_tree.set("parameters/act_b_seek/seek_request", _slots[1].time)
	_tree.set("parameters/act/blend_amount", _ab_w)
	_tree.set("parameters/out/blend_amount", _act_w)

func _place_visual() -> void:
	var loco_world: Transform3D
	if _player != null:
		loco_world = _placement(_visual_yaw, Vector3.ZERO,
			Vector3(_player.global_position.x, _floor_y(), _player.global_position.z))
	else:
		loco_world = global_transform
	var world: Transform3D = loco_world
	if _act_w > 0.0:
		var act: Transform3D = _slots[0].world.interpolate_with(_slots[1].world, _ab_w) \
			if _slots[1].clip != &"" else _slots[0].world
		world = loco_world.interpolate_with(act, _act_w)
	if _act_w <= 0.0 and _act_target <= 0.0:
		for s: ActionSlot in _slots:
			s.clip = &""
	_visual.global_transform = world
	_last_visual_world = world

## World placement (yaw + model scale) that puts clip-space point `clip_point`
## at `world_point`.
func _placement(yaw: float, clip_point: Vector3, world_point: Vector3) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _scale)
	return Transform3D(basis, world_point - basis * clip_point)

func _floor_y() -> float:
	return global_position.y

# ─── Bake metadata helpers ───────────────────────────────────────────────────
static func _meta_at(anim: Animation, key: String, t: float) -> Vector3:
	var arr: PackedVector3Array = anim.get_meta(key, PackedVector3Array())
	if arr.is_empty():
		return Vector3.ZERO
	var f: float = clampf(t / anim.length, 0.0, 1.0) * float(arr.size() - 1)
	var i: int = mini(int(f), arr.size() - 2)
	return arr[i].lerp(arr[i + 1], f - float(i))

static func _clip_yaw(anim: Animation, t: float) -> float:
	return _yaw_of(_meta_at(anim, "hips_forward", t))

## Normalised cumulative hip path length at time t (0 at start, 1 at end).
static func _progress(anim: Animation, key: String, t: float) -> float:
	var arr: PackedVector3Array = anim.get_meta(key, PackedVector3Array())
	if arr.size() < 2:
		return clampf(t / anim.length, 0.0, 1.0)
	var total: float = 0.0
	var at: float = 0.0
	var f: float = clampf(t / anim.length, 0.0, 1.0) * float(arr.size() - 1)
	for i: int in arr.size() - 1:
		var seg: float = arr[i].distance_to(arr[i + 1])
		if float(i) < f:
			at += seg * clampf(f - float(i), 0.0, 1.0)
		total += seg
	return at / total if total > 0.0 else 0.0

## Normalised rise of the lower foot (0 = on the floor, 1 = at its highest),
## smoothed — paces the lie-down's leg swing.
static func _feet_lift_progress(anim: Animation, t: float) -> float:
	var arr: PackedFloat32Array = anim.get_meta("feet_low", PackedFloat32Array())
	if arr.size() < 2:
		return clampf(t / anim.length, 0.0, 1.0)
	var lo: float = arr[0]
	var hi: float = arr[0]
	for v: float in arr:
		hi = maxf(hi, v)
	var f: float = clampf(t / anim.length, 0.0, 1.0) * float(arr.size() - 1)
	var i: int = mini(int(f), arr.size() - 2)
	var running: float = lo
	for k: int in i + 1:
		running = maxf(running, arr[k])
	running = maxf(running, lerpf(arr[i], arr[i + 1], f - float(i)))
	return smoothstep(0.0, 1.0, (running - lo) / maxf(hi - lo, 0.0001))

static func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)

static func _signed_yaw(from: Vector3, to: Vector3) -> float:
	return wrapf(_yaw_of(to) - _yaw_of(from), -PI, PI)

# ─── Public API ───────────────────────────────────────────────────────────────
## NPC wall lean. `wall_point` is any point on the wall's surface (its floor
## projection is where the back rests; pick it along the wall where the NPC
## should stand) and `wall_normal` the wall's outward normal (pointing into
## the room). The body walks there, turns its back to the wall and settles
## into the looping lean; end_lean() blends back to standing on the spot.
## While this runs, is_sit_sequence_active() is true (so NPC physics stays
## frozen) and get_stand_end_position() is where the capsule will be.
## Returns false if the body is busy (furniture, dying, already sequencing).
func begin_lean(wall_point: Vector3, wall_normal: Vector3) -> bool:
	if _player == null or _stage != Stage.NONE or _parent_furniture() != null:
		return false
	_lean_point = wall_point
	_lean_normal = wall_normal
	_lean_request = true
	return true

func end_lean() -> void:
	_lean_request = false

## True while settled in the lean loop (after the approach and turn).
func is_leaning() -> bool:
	return _stage == Stage.LEAN

## True from the moment furniture use starts until the stand-up has finished.
func is_sit_sequence_active() -> bool:
	return _stage != Stage.NONE and _stage != Stage.DEAD

## Input is swallowed while a transition is mid-motion; the seated and
## sleeping holds accept input (E stands / wakes).
func is_animation_locked() -> bool:
	return _stage in [Stage.APPROACH, Stage.PIVOT, Stage.SIT_DOWN, Stage.LIE_DOWN,
		Stage.GET_UP, Stage.STAND_UP]

## The body's current absolute facing.
func get_visual_yaw() -> float:
	if _stand_end_known and _plan != null and _stage == Stage.NONE:
		return _plan.stand_end_yaw
	return _visual_yaw

## Where the stand-up leaves the body standing (world, at the capsule's own
## height). Known from the moment furniture use starts; Vector3.INF before.
func get_stand_end_position() -> Vector3:
	if not _stand_end_known or _plan == null:
		return Vector3.INF
	var y: float = _player.global_position.y if _player != null else _plan.stand_end_pos.y
	return Vector3(_plan.stand_end_pos.x, y, _plan.stand_end_pos.z)

# ─── Parent queries ──────────────────────────────────────────────────────────
func _is_holding_item() -> bool:
	if _player.has_method("get_held_item"):
		return _player.get_held_item() != null
	if "held_item" in _player:
		return _player.held_item != null
	return false

func _is_dead() -> bool:
	if _player.has_method("is_dead"):
		return bool(_player.is_dead())
	if "dead" in _player:
		return bool(_player.get("dead"))
	return false

static func _find_all_of_type(root: Node, type_name: String) -> Array[Node]:
	var results: Array[Node] = []
	for child: Node in root.get_children():
		if child.is_class(type_name):
			results.append(child)
		results.append_array(_find_all_of_type(child, type_name))
	return results
