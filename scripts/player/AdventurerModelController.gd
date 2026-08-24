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
const BLEND_TIME: float = 0.15

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
}

var _player: CharacterBody3D = null
var _anim_player: AnimationPlayer = null
var _current_state: String = ""
var _visual_yaw: float = 0.0

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
		_play_state("idle")
	## TEMP DIAGNOSTIC (Aug 2026) — investigating a reported T-pose/no-
	## animation bug in the real Player.tscn context (an isolated test
	## scene with the identical script DID animate correctly). Writes to
	## a plain file instead of print/push_warning so it's readable outside
	## the running process. Remove once resolved.
	_dup_diag_log("[READY] gender=%s is_shadow_only=%s anim_player_found=%s skeleton_found=%s bone_count=%d has_idle=%s current_state=%s root_motion_track=%s" % [
		gender, is_shadow_only, _anim_player != null, skeleton != null,
		(skeleton.get_bone_count() if skeleton != null else -1),
		(_anim_player.has_animation("idle_lib/idle") if _anim_player != null else false),
		_current_state,
		(str(_anim_player.root_motion_track) if _anim_player != null else "n/a"),
	])

static func _dup_diag_log(msg: String) -> void:
	var path := "res://_dup_diag.log"
	var existing := ""
	if FileAccess.file_exists(path):
		var rf := FileAccess.open(path, FileAccess.READ)
		if rf != null:
			existing = rf.get_as_text()
			rf.close()
	var wf := FileAccess.open(path, FileAccess.WRITE)
	if wf != null:
		wf.store_string(existing + "[%s] %s\n" % [Time.get_time_string_from_system(), msg])
		wf.close()

func _process(delta: float) -> void:
	if _player == null:
		return

	_visual_yaw = lerp_angle(_visual_yaw, _player.rotation.y, clampf(turn_speed * delta, 0.0, 1.0))
	rotation.y = _visual_yaw - _player.rotation.y

	if _anim_player == null:
		return
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

func _is_holding_item() -> bool:
	if _player == null:
		return false
	if _player.has_method("get_held_item"):
		return _player.get_held_item() != null
	if "held_item" in _player:
		return _player.held_item != null
	return false

func _play_state(state: String) -> void:
	var anim_name: String = ANIMATION_NAMES.get(state, state)
	if anim_name == _current_state:
		return
	if not _anim_player.has_animation(anim_name):
		return
	_current_state = anim_name
	_anim_player.play(anim_name, BLEND_TIME)

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
