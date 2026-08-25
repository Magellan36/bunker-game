class_name AdventurerModelController
extends Node3D
## AdventurerModelController.gd
## Aug 2026 — V1 simplification. Loads one of the two complete Quaternius
## "Adventurer" models (Ultimate Modular Men/Women packs) wholesale, no
## per-piece customization: no outfit swapping, no hairstyle attachment,
## no skin-material building. The model is a single self-contained body
## with its own baked-in look (grey hair/beige clothes for male, brown
## hair/green clothes for female).
##
## This REPLACES PlayerModelController.gd/PlayerModel.tscn for V1's two
## base models. That file and its whole customization system (hairstyles,
## outfits, character-creation hair/color picking) are NOT deleted — they
## are packed away for a later version once real customization art is
## ready. See docs/systems/player-model/README.md "V1 simplification —
## Adventurer models" for the full context and how to un-pack it.
##
## Attach to: res://scenes/player/AdventurerModel.tscn's root node.
## Instanced as a child of Player.tscn's root, same as the old
## PlayerModel.tscn was — see that scene for wiring.

## Crossfade time between animation states, in seconds.
const BLEND_TIME: float = 0.3
## Longer ease between the base locomotion states (idle↔walk↔run). The
## gender-specific locomotion poses differ noticeably from each other
## (male idle especially), so the standard 0.3s blend still reads as a snap
## on walk↔run and ↔idle. Carry and sit transitions keep BLEND_TIME.
const LOCOMOTION_BLEND_TIME: float = 0.5
## Base locomotion states that transition with the longer ease above.
const LOCOMOTION_STATES: Array[String] = ["idle", "walk", "run"]

## Run only kicks in once real velocity is closing in on sprint_speed.
const RUN_SPEED_FRACTION: float = 0.85

## How quickly the model's VISUAL facing catches up to Player's actual
## rotation.y. Same convention/reasoning as the old controller.
@export var turn_speed: float = 12.0

## When true, casts a real shadow but never renders to camera — set on
## the second, scaled-down shadow instance (see Player.tscn). Same
## mechanism as the old PlayerModelController.
@export var is_shadow_only: bool = false

## Aug 2026 — opt-in flag for NPCs: each NPC randomly picks a gender
## (which Adventurer model loads) on spawn, independent of the player's
## CharacterCreationData choice and every other NPC. Set true on
## NPC.tscn's CharacterModel/CharacterModelShadow nodes. Simpler than the
## old PlayerModelController's randomize_appearance — there's no hair/
## color/beard to roll anymore, just which complete body loads. Mutually
## exclusive in practice with reading CharacterCreationData: when true,
## gender comes from this random roll instead.
@export var randomize_gender: bool = false

## Aug 2026 — the two complete Adventurer bodies. Each is a single FBX
## with its own baked mesh/materials/skeleton, imported with a
## retarget/bone_map (bone_map_adventurer.tres) that renames its bones
## to Godot's Humanoid profile — the SAME "GeneralSkeleton" convention
## our existing animation library (idle/walk/run/*_carry) is baked
## against, via bone_map_mixamo.tres on those files. That shared
## convention is what makes the existing animations play correctly on
## this different-source-rig skeleton with zero per-clip retargeting
## work. Verified directly in-editor before this controller was written
## (see the README section referenced above).
const BODY_SCENE_PATHS: Dictionary = {
	"male": "res://assets/models/player/adventurer/Adventurer_Male.fbx",
	"female": "res://assets/models/player/adventurer/Adventurer_Female.fbx",
}

## Same fallback/floor-alignment math as the old controller — kept in
## sync deliberately, see that file's own comment for why.
const FALLBACK_CAPSULE_HEIGHT: float = 2.0
const MODEL_FLOOR_FUDGE: float = 0.0

const ANIMATION_NAMES: Dictionary = {
	"idle": "idle_lib/idle",
	"walk": "walk_lib/walk",
	"run": "run_lib/run",
	"idle_carry": "idle_carry_lib/idle_carry",
	"walk_carry": "walk_carry_lib/walk_carry",
	"run_carry": "run_carry_lib/run_carry",
	"stand_to_sit": "stand_to_sit_lib/stand_to_sit",
	"sit": "sit_lib/sit",
	"sit_to_stand": "sit_to_stand_lib/sit_to_stand",
}

## Male-only idle override (Aug 2026) — the Male Locomotion Pack idle clip
## replaces the idle for MALE bodies only; walk/run/carry/sit and every
## female state keep the shared ANIMATION_NAMES.
const MALE_ANIMATION_NAMES: Dictionary = {
	"idle": "idle_male_lib/idle_male",
}

## Female-only idle override (Aug 2026) — the Female Basic Locomotion Pack
## idle clip replaces the idle for FEMALE bodies only; walk/run/carry/sit
## and every male state keep the shared ANIMATION_NAMES.
const FEMALE_ANIMATION_NAMES: Dictionary = {
	"idle": "idle_female_lib/idle_female",
}

var _player: CharacterBody3D = null
var _anim_player: AnimationPlayer = null
var _current_state: String = ""
var _last_state: String = ""
var _visual_yaw: float = 0.0
## Which body gender this controller loaded — drives MALE_ANIMATION_NAMES
## selection in _resolve_anim_name(). Set in _ready() from
## CharacterCreationData (player) or the per-NPC random roll.
var _gender: String = "male"

## Sit lifecycle (Aug 2026): "" = standing/normal locomotion.
## "sitting_down" → "seated" → "standing_up" → "" drives the imported
## stand_to_sit / sit / sit_to_stand sequence. The transitions advance on
## AnimationPlayer.animation_finished (see _on_anim_finished).
var _sit_phase: String = ""

## Aug 2026 — the two horizontal anchor points the sit sequence eases
## between: the approach spot (near the chair's front edge, where sitting
## down starts / standing up ends) and the seat center (where sitting down
## ends / standing up starts). Set by MainWorld.gd right as the sit
## sequence begins — see _wire_chair()'s seat_requested handler.
var _chair_approach_pos: Vector3 = Vector3.ZERO
var _chair_seat_pos: Vector3 = Vector3.ZERO

## Aug 2026 (5th pass) — the constant vertical gap between where the
## clips' own baked Hip motion naturally lands (a fixed floor anchor +
## the skeleton's own physically-correct standing→seated knee-bend, see
## docs/systems/player-model/README.md "Sit animation root-offset fix")
## and the ACTUAL chair seat surface (`Chair.SEAT_Y`). These are
## DIFFERENT things — the clip fix made the animation internally
## consistent (feet grounded, natural knee-bend), but never had any
## awareness of THIS specific chair's height. Measured directly via a
## real, ground-truth headless Godot diagnostic (not Blender-space
## assumptions): instantiate the actual body + sit_lib.res, seek to the
## seated pose, read the real Skeleton3D Hip bone's world Y, compare
## against Chair.SEAT_Y. Male and female bodies have different skeleton
## proportions, hence different corrections — verified separately for
## both. If SEAT_Y or either body's rig ever changes, re-measure rather
## than guess (see the README section for the exact diagnostic script
## used).
const SEAT_HEIGHT_CORRECTION: Dictionary = {
	"male": 0.3316,
	"female": 0.4398,
}

## Aug 2026 — emitted the moment the stand_to_sit clip actually finishes
## (sitting_down → seated), so the chair/world code can snap the player
## down onto the actual seat position at exactly that moment — not
## before. See MainWorld.gd's _wire_chair() for the consumer.
signal sit_animation_finished()

## Aug 2026 — emitted the moment the sit_to_stand clip actually finishes
## (standing_up → ""), so the chair/world code can keep the player
## anchored in place until the stand-up animation is genuinely done,
## instead of snapping the player's position/physics loose the instant E
## is pressed. See MainWorld.gd's _wire_chair() for the consumer.
signal stand_animation_finished()

func _ready() -> void:
	var parent: Node = get_parent()
	if parent is CharacterBody3D:
		_player = parent as CharacterBody3D
	if _player != null:
		_visual_yaw = _player.rotation.y

	## Aug 2026 — gender comes from CharacterCreationData for the real
	## player (the creation screen's Body/gender category is still
	## functional in V1; only Hair is disabled), or from a random per-NPC
	## roll when randomize_gender is set. The two instances per NPC
	## (CharacterModel/CharacterModelShadow) synchronize through node
	## metadata on their shared parent, same pattern the old
	## PlayerModelController used for its fuller random roll: whichever
	## runs _ready() first rolls and stashes the result, the second reads
	## it back, so a body and its shadow always match.
	var gender: String = "male"
	if randomize_gender and _player != null:
		if not _player.has_meta("_adventurer_random_gender"):
			var rolled_gender: String = "male" if randi() % 2 == 0 else "female"
			_player.set_meta("_adventurer_random_gender", rolled_gender)
		gender = _player.get_meta("_adventurer_random_gender")
	else:
		gender = CharacterCreationData.gender
	_gender = gender

	var body_scene_path: String = BODY_SCENE_PATHS.get(gender, BODY_SCENE_PATHS["male"])
	var body_scene: PackedScene = load(body_scene_path)
	var body: Node3D = body_scene.instantiate()
	## Load-bearing: every baked AnimationLibrary track is NodePath
	## "MaleModel/%GeneralSkeleton:<bone>" (see docs/systems/player-model/
	## README.md "Runtime body & character creation" — the SAME convention
	## the old PlayerModelController.gd relies on for its own runtime body).
	## The Adventurer FBX's own root node name ("Adventurer_Male"/
	## "Adventurer_Female") does NOT match that hardcoded prefix, which
	## silently breaks every track's resolution — confirmed directly via a
	## runtime diagnostic: has_animation()/root_motion_track resolution/
	## _play_state() all succeeded, yet the body stayed in bind pose
	## (T-pose), because the ACTUAL per-bone tracks inside the animation
	## couldn't find a child literally named "MaleModel" to resolve
	## through. Renaming here, regardless of gender, matches what the
	## animation data actually expects.
	body.name = "MaleModel"
	## Aug 2026 — same 180° Y-rotation fix the old PlayerModelController.gd
	## needed for BOTH the Mixamo and native-rig bodies (Mixamo/FBX forward
	## axis vs. Godot's own -Z forward). The Adventurer rig needs the exact
	## same correction — confirmed live: without this, the model and its
	## animations render facing/walking backwards. A model-space fix, not
	## a movement-code change; Player.gd's own facing math is untouched.
	body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	add_child(body)

	var capsule_height: float = FALLBACK_CAPSULE_HEIGHT
	var had_real_collision: bool = false
	if _player != null:
		var collision_node: Node = _player.get_node_or_null("CollisionShape3D")
		if collision_node is CollisionShape3D:
			var shape: Shape3D = (collision_node as CollisionShape3D).shape
			if shape is CapsuleShape3D:
				capsule_height = (shape as CapsuleShape3D).height
				had_real_collision = true
	position.y = -(capsule_height * 0.5) + MODEL_FLOOR_FUDGE if had_real_collision else 0.0

	_anim_player = _find_first_of_type(self, "AnimationPlayer") as AnimationPlayer
	var skeleton: Skeleton3D = _find_first_of_type(self, "Skeleton3D") as Skeleton3D

	for node in _find_all_of_type(self, "MeshInstance3D"):
		var mi: MeshInstance3D = node as MeshInstance3D
		if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
			mi.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
		mi.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if is_shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		## Aug 2026 — the male Adventurer body ships its own separate
		## "Backpack" mesh piece (the female body has no equivalent node at
		## all, confirmed directly — this check naturally no-ops for her).
		## Turned off per explicit request; a simple visibility toggle since
		## it's a genuinely separate mesh, not baked into the body/clothes.
		if mi.name.to_lower() == "backpack":
			mi.visible = false
		## Aug 2026 — the Adventurer FBX's own baked materials are used
		## as-is (flat colors, no texture files, confirmed directly
		## against the source pack). No skin/eye/eyebrow override logic
		## needed here, unlike the old controller.

	if _anim_player != null and skeleton != null:
		if not _root_motion_track_valid(_anim_player, skeleton):
			var hips: NodePath = _find_bone_path(_anim_player, skeleton, "Hips")
			if hips != NodePath():
				_anim_player.root_motion_track = hips
		_anim_player.animation_finished.connect(_on_anim_finished)
		_play_state("idle")

func _process(delta: float) -> void:
	if _player == null:
		return

	## Sitting (Aug 2026): the model faces the seat's backrest — 180° from
	## the character's own facing (which the seat flow points at the chair's
	## open front). Same for player and NPC, both genders (shared controller).
	## The offset holds for the WHOLE sit sequence (down/seated/up) so the
	## transition clips don't snap 180° mid-play.
	var seated: bool = _parent_seated()
	var facing_target: float = _player.rotation.y
	if seated or _sit_phase != "":
		facing_target += PI
	_visual_yaw = lerp_angle(_visual_yaw, facing_target, clampf(turn_speed * delta, 0.0, 1.0))
	rotation.y = _visual_yaw - _player.rotation.y

	if _anim_player == null:
		return

	## Sit sequence overrides locomotion entirely while it's active.
	## Aug 2026 fix — the XZ-lerp calls below are guarded to the REAL
	## (non-shadow) instance only. Both PlayerModel and PlayerModelShadow
	## are separate AdventurerModelController instances under the SAME
	## player node, both independently reaching this code every frame
	## (seated just checks the shared _player.seated_chair) — without this
	## guard, the shadow instance's own _chair_approach_pos/_chair_seat_pos
	## (never set externally, still their Vector3.ZERO default) fought the
	## real instance over the SAME shared player.global_position every
	## frame, snapping the player to world origin.
	if seated:
		if _sit_phase == "":
			_sit_phase = "sitting_down"
			_play_state("stand_to_sit")
		elif _sit_phase == "sitting_down":
			if not is_shadow_only:
				_lerp_sit_position(_chair_approach_pos, _chair_seat_pos, SIT_DOWN_CURVE, true)
		elif _sit_phase == "seated":
			_play_state("sit")   ## looped anchor, idempotent once current
		return
	## Not seated, but mid sit-sequence — play the stand-up and wait.
	if _sit_phase == "sitting_down" or _sit_phase == "seated":
		_sit_phase = "standing_up"
		_play_state("sit_to_stand")
		return
	if _sit_phase == "standing_up":
		if not is_shadow_only:
			_lerp_sit_position(_chair_seat_pos, _chair_approach_pos, STAND_UP_CURVE, false)
		return   ## waiting for sit_to_stand to finish → back to locomotion

	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	var next_state: String = "idle"
	if speed > 0.1:
		var sprint_speed: float = 7.5
		if "sprint_speed" in _player:
			sprint_speed = _player.sprint_speed
		next_state = "run" if speed >= sprint_speed * RUN_SPEED_FRACTION else "walk"
	if _is_holding_item():
		next_state += "_carry"
	_play_state(next_state)

## True while the owning character is seated in a chair. Player exposes
## `seated_chair`; NPC.gd mirrors it (set by SitActivity/RelaxSitActivity).
func _parent_seated() -> bool:
	if _player == null:
		return false
	if "seated_chair" in _player:
		return _player.seated_chair != null
	return false

## Advances the sit lifecycle when a one-shot sit clip finishes.
func _on_anim_finished(_anim_name: StringName) -> void:
	if _sit_phase == "sitting_down":
		_sit_phase = "seated"
		_play_state("sit")
	elif _sit_phase == "standing_up":
		_sit_phase = ""
		stand_animation_finished.emit()

## Aug 2026 — smoothly interpolates the player's horizontal (X/Z)
## position between the chair's approach spot (near the front edge) and
## its seat center. Vertical motion is untouched here; that's already
## handled entirely by the animation's own baked Hip motion (see the Aug
## 2026 root-offset fix in docs/systems/player-model/README.md).
##
## Aug 2026 (2nd pass) — the horizontal slide's PACE now follows one of
## the two curves below instead of raw animation time. Sampled directly
## from each clip's own baked Hip motion in Blender (21 evenly-spaced
## points across the clip, standing/seated height mapped to 0/1): the
## real sit-down/stand-up motion is NOT linear over time — e.g.
## stand_to_sit stays essentially upright for the first ~10% of the clip,
## does almost the entire vertical drop across the next ~55%, then holds
## at seated height for the remaining ~35% (sit_to_stand is similarly
## non-linear, just shaped differently — it isn't a mirror of the other).
## Driving the horizontal slide by raw time put it badly out of sync with
## the actual vertical motion: the body kept sliding sideways while still
## standing tall, then dropped late, reading as "hovering" over the chair
## rather than settling into it. Sampling these curves instead keeps the
## horizontal slide's pace locked to however fast the body is actually
## lowering/rising at each moment, so both motions read as one connected
## movement instead of two independent ones.
const SIT_DOWN_CURVE: PackedFloat32Array = [
	0.0, 0.0014, 0.0055, 0.0324, 0.0658, 0.1023, 0.1660, 0.2703, 0.4118,
	0.5398, 0.6790, 0.8071, 0.9037, 0.9782, 0.9967, 0.9996, 1.0, 1.0, 1.0, 1.0, 1.0,
]
const STAND_UP_CURVE: PackedFloat32Array = [
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0069, 0.0643, 0.1632, 0.2603, 0.3574,
	0.4398, 0.5505, 0.6667, 0.7474, 0.8217, 0.8633, 0.9039, 0.9410, 0.9692, 1.0,
]

## Piecewise-linear lookup into one of the curves above — maps a raw
## 0..1 time fraction to the corresponding motion fraction.
static func _sample_curve(curve: PackedFloat32Array, t: float) -> float:
	var n: int = curve.size() - 1
	var scaled: float = clampf(t, 0.0, 1.0) * n
	var i: int = clampi(int(scaled), 0, n - 1)
	var frac: float = scaled - i
	return lerpf(curve[i], curve[i + 1], frac)

func _lerp_sit_position(from_xz: Vector3, to_xz: Vector3, curve: PackedFloat32Array, is_sitting_down: bool) -> void:
	if _player == null or _anim_player == null:
		return
	var length: float = _anim_player.current_animation_length
	if length <= 0.0:
		return
	var raw_t: float = clampf(_anim_player.current_animation_position / length, 0.0, 1.0)
	var t: float = _sample_curve(curve, raw_t)
	_player.global_position.x = lerpf(from_xz.x, to_xz.x, t)
	_player.global_position.z = lerpf(from_xz.z, to_xz.z, t)
	## Aug 2026 (5th pass) — curve-synced seat-height correction, same
	## timing as the X/Z slide above. is_sitting_down picks the direction
	## explicitly (passed by the caller, not inferred) — correction eases
	## IN while sitting down, eases back OUT while standing up.
	var seat_correction: float = SEAT_HEIGHT_CORRECTION.get(_gender, 0.0)
	var corrected_y: float = _chair_approach_pos.y - seat_correction
	if is_sitting_down:
		_player.global_position.y = lerpf(_chair_approach_pos.y, corrected_y, t)
	else:
		_player.global_position.y = lerpf(corrected_y, _chair_approach_pos.y, t)

func _is_holding_item() -> bool:
	if _player == null:
		return false
	if _player.has_method("get_held_item"):
		return _player.get_held_item() != null
	if "held_item" in _player:
		return _player.held_item != null
	return false

func _play_state(state: String) -> void:
	var anim_name: String = _resolve_anim_name(state)
	if anim_name == _current_state:
		return
	if not _anim_player.has_animation(anim_name):
		return
	## Longer ease between base locomotion states (idle↔walk↔run) — the
	## gender-specific poses differ enough that the standard blend reads as
	## a snap, most visibly on the male model's distinct idle stance.
	var blend: float = BLEND_TIME
	if state == "idle" or _last_state == "idle" \
			or (LOCOMOTION_STATES.has(state) and LOCOMOTION_STATES.has(_last_state)):
		blend = LOCOMOTION_BLEND_TIME
	_last_state = state
	_current_state = anim_name
	_anim_player.play(anim_name, blend)

## Gender-aware clip lookup: male uses MALE_ANIMATION_NAMES, female uses
## FEMALE_ANIMATION_NAMES; any state not overridden (carry, sit) falls
## through to the shared ANIMATION_NAMES for both genders.
func _resolve_anim_name(state: String) -> String:
	if _gender == "male" and MALE_ANIMATION_NAMES.has(state):
		return String(MALE_ANIMATION_NAMES[state])
	if _gender == "female" and FEMALE_ANIMATION_NAMES.has(state):
		return String(FEMALE_ANIMATION_NAMES[state])
	return String(ANIMATION_NAMES.get(state, state))

static func _root_motion_track_valid(anim_player: AnimationPlayer, skeleton: Skeleton3D) -> bool:
	var track: NodePath = anim_player.root_motion_track
	if track == NodePath():
		return false
	var bone_name: String = track.get_concatenated_subnames()
	return skeleton.find_bone(bone_name) != -1

static func _find_first_of_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.is_class(type_name):
			return child
		var found: Node = _find_first_of_type(child, type_name)
		if found != null:
			return found
	return null

static func _find_all_of_type(root: Node, type_name: String) -> Array[Node]:
	var results: Array[Node] = []
	for child in root.get_children():
		if child.is_class(type_name):
			results.append(child)
		results.append_array(_find_all_of_type(child, type_name))
	return results

static func _find_bone_path(anim_player: AnimationPlayer, skeleton: Skeleton3D, bone_hint: String) -> NodePath:
	for i in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(i)
		if bone_hint.to_lower() in bone_name.to_lower():
			var skeleton_path: NodePath = anim_player.get_path_to(skeleton)
			return NodePath(str(skeleton_path) + ":" + bone_name)
	return NodePath()
