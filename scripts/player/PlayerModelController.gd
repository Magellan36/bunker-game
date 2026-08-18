class_name PlayerModelController
extends Node3D
## PlayerModelController.gd
## Player-Model subsystem — owns the player's VISUAL body only: applying
## the same self-light/shadow exclusion the old capsule placeholder had,
## and picking which locomotion animation (idle/walk/run) plays based on
## the sibling Player node's actual physics state. Does not touch
## movement, stamina, or interaction logic.
##
## Attach to: res://scenes/player/PlayerModel.tscn's root node.
## PlayerModel.tscn is instanced as a child of Player.tscn's root
## (res://scenes/player/Player.tscn) — see that scene for wiring.

## Crossfade time between animation states, in seconds. Small and snappy
## since walk/run transitions happen constantly during normal play;
## retune freely, no other coupled effects.
const BLEND_TIME: float = 0.15

## Run only kicks in once real velocity is closing in on sprint_speed —
## not just "sprint key held" — since stamina lockout can force actual
## speed back toward move_speed even while sprint is still requested.
## Reading real velocity means the animation always matches what's
## actually happening on screen, not raw input state.
const RUN_SPEED_FRACTION: float = 0.85

## Maps the plain state names used below ("idle"/"walk"/"run") to the
## full animation-name strings actually registered in PlayerModel.tscn's
## AnimationPlayer. The three clip libraries (idle_lib/walk_lib/run_lib)
## are separate AnimationLibrary resources, so Godot prefixes each
## animation with its library name — see
## docs/systems/player-model/README.md "Animation names" for the
## confirmed strings.
const ANIMATION_NAMES: Dictionary = {
	"idle": "idle_lib/idle",
	"walk": "walk_lib/walk",
	"run": "run_lib/run",
}

var _player: CharacterBody3D = null
var _anim_player: AnimationPlayer = null
var _current_state: String = ""

func _ready() -> void:
	var parent: Node = get_parent()
	if parent is CharacterBody3D:
		_player = parent as CharacterBody3D

	_anim_player = _find_first_of_type(self, "AnimationPlayer") as AnimationPlayer
	var skeleton: Skeleton3D = _find_first_of_type(self, "Skeleton3D") as Skeleton3D

	## Generalizes what used to be Player.gd's single hardcoded
	## $MeshInstance3D.layers/cast_shadow lines (now removed there, see
	## docs/systems/player-model/README.md) to every visual mesh under
	## this node — a real character can end up with more than one
	## MeshInstance3D (body + separately-skinned hair/eyebrows in a
	## future pass).
	for node in _find_all_of_type(self, "MeshInstance3D"):
		var mi: MeshInstance3D = node as MeshInstance3D
		if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
			mi.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if _anim_player != null:
		## Fallback in case the manual editor step (Part 4, step 5) was
		## skipped or the imported bone name differs from expectation —
		## safe to leave in permanently either way, it's a no-op once
		## root_motion_track is already set correctly in the scene file.
		if skeleton != null and _anim_player.root_motion_track == NodePath():
			var hips: NodePath = _find_bone_path(_anim_player, skeleton, "Hips")
			if hips != NodePath():
				_anim_player.root_motion_track = hips
		_play_state("idle")

func _process(_delta: float) -> void:
	if _player == null or _anim_player == null:
		return
	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	var next_state: String = "idle"
	if speed > 0.1:
		var sprint_speed: float = 7.5
		if "sprint_speed" in _player:
			sprint_speed = _player.sprint_speed
		next_state = "run" if speed >= sprint_speed * RUN_SPEED_FRACTION else "walk"
	_play_state(next_state)

func _play_state(state: String) -> void:
	var anim_name: String = ANIMATION_NAMES.get(state, state)
	if anim_name == _current_state:
		return
	if not _anim_player.has_animation(anim_name):
		return
	_current_state = anim_name
	_anim_player.play(anim_name, BLEND_TIME)

## Recursive first-match-by-class helper — avoids hardcoding exact node
## names/paths, which vary by FBX exporter and import settings.
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

## Partial, case-insensitive bone-name match (Mixamo bones are prefixed
## "mixamorig:", so an exact match on "Hips" alone would miss
## "mixamorig:Hips"). Returns an empty NodePath if no match is found.
static func _find_bone_path(anim_player: AnimationPlayer, skeleton: Skeleton3D, bone_hint: String) -> NodePath:
	for i in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(i)
		if bone_hint.to_lower() in bone_name.to_lower():
			var skeleton_path: NodePath = anim_player.get_path_to(skeleton)
			return NodePath(str(skeleton_path) + ":" + bone_name)
	return NodePath()