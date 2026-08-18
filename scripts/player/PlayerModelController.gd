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

## How quickly the model's VISUAL facing catches up to Player's actual
## (instant) rotation.y — Player.gd itself still snaps immediately, this
## only smooths what's on screen. Same exponential-decay convention as
## PickupableItem.gd's UPRIGHT_SLERP_SPEED: t = speed * delta each frame,
## so it naturally eases in as it approaches the target rather than
## moving at a constant angular rate. ~90% converged in about 0.2s at
## this value. Exported so it's tunable in the Inspector without a code
## edit — higher = snappier/more responsive, lower = more floaty.
@export var turn_speed: float = 12.0

## Aligns the model's own floor (Mixamo's export convention: origin at
## the floor, between the feet) with the CharacterBody3D's real floor
## (which sits at -height/2 from the capsule's center, NOT at local
## (0,0,0) — PlayerModel is instanced at the capsule's center by
## default). Same fallback values as CharacterShadowStandIn.gd uses for
## the shadow proxy, kept in sync deliberately — if the collision
## capsule is ever retuned, both systems should be retuned together.
const FALLBACK_CAPSULE_HEIGHT: float = 2.0

## If the model still shows a small gap or clip through the floor after
## this offset, it means the Mixamo rig's own local origin isn't exactly
## at floor level (small per-asset authoring variance) — add a small
## correction here rather than touching the dynamic capsule-height math
## above. Zero until verified needed in-editor.
const MODEL_FLOOR_FUDGE: float = 0.0

## Body skin material — Aug 2026 fix pass. male.fbx (Mixamo export) ships
## UV layers (SuperHero_MaleDiffuseUVLayer/EyesDiffuseUVLayer/
## EyebrowsDiffuseUVLayer, confirmed via `strings male.fbx`) but zero
## embedded or referenced texture data — Mixamo's auto-rig export never
## includes textures, only the source Quaternius kit's separate
## Textures/ folder has them. Applied uniformly across every surface for
## now, the simplest correct-enough first pass to restore visibility —
## eyes/eyebrows will read as skin-colored rather than white/dark until
## a follow-up assigns per-surface materials by name. Flagged in
## docs/systems/player-model/README.md, not a blocker here.
const SKIN_ALBEDO_PATH: String = "res://assets/models/player/textures/T_Superhero_Male_Dark.png"
const SKIN_NORMAL_PATH: String = "res://assets/models/player/textures/T_Superhero_Male_Normal.png"
const SKIN_ROUGHNESS_PATH: String = "res://assets/models/player/textures/T_Superhero_Male_Roughness.png"

## Hairstyle — Aug 2026. Sourced from WIP/FINAL/Hairstyles/"Rigged to
## Head Bone"/ (not "Origin at 0" — that variant has no bind-pose data
## to extract, see the plan doc for why "Rigged to Head Bone" was
## chosen despite looking more complex). Confirmed via direct binary
## inspection: 100% of this mesh's vertex weight is on its own "Head"
## joint, so it's treated as a rigid prop, not truly re-skinned.
## Swap hairstyles by changing these two constants — everything else in
## _setup_hair() is generic per-asset extraction, not specific to this
## particular style.
const HAIR_SCENE_PATH: String = "res://assets/models/player/hair/Hair_Buzzed.gltf"
const HAIR_MESH_NODE_NAME: String = "Hair_Buzzed"

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
var _skin_material: StandardMaterial3D = null
var _visual_yaw: float = 0.0

func _build_skin_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var albedo: Texture2D = load(SKIN_ALBEDO_PATH)
	var normal: Texture2D = load(SKIN_NORMAL_PATH)
	var rough: Texture2D = load(SKIN_ROUGHNESS_PATH)
	if albedo != null:
		mat.albedo_texture = albedo
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	if rough != null:
		mat.roughness_texture = rough
	return mat

## Confirms root_motion_track actually resolves to a real bone on the
## given skeleton, rather than trusting whatever NodePath happens to be
## set. Aug 2026 fix pass — see the "Confirmed gap #2" note in
## PLAYER_MODEL_GREEN_CIRCLE_FIX_PLAN.md for why this replaced a
## simpler "only fill in if empty" check.
static func _root_motion_track_valid(anim_player: AnimationPlayer, skeleton: Skeleton3D) -> bool:
	var track: NodePath = anim_player.root_motion_track
	if track == NodePath():
		return false
	var bone_name: String = track.get_concatenated_subnames()
	return skeleton.find_bone(bone_name) != -1

## One-time diagnostic print — Aug 2026, added specifically to root-cause
## the "green circle" report without guessing blind. Safe to delete once
## the character reliably renders correctly on a playtest; only prints
## once per spawn, not per-frame.
func _print_diagnostics(skeleton: Skeleton3D) -> void:
	var mesh_instances: Array[Node] = _find_all_of_type(self, "MeshInstance3D")
	print("[PlayerModelController] mesh_instances_found=", mesh_instances.size())
	for node in mesh_instances:
		var mi: MeshInstance3D = node as MeshInstance3D
		print("[PlayerModelController]   ", mi.name,
			" local_aabb_size=", mi.get_aabb().size,
			" global_pos=", mi.global_position,
			" visible=", mi.visible)
	if skeleton != null:
		print("[PlayerModelController] skeleton_bone_count=", skeleton.get_bone_count(),
			" skeleton_global_pos=", skeleton.global_position)
	if _anim_player != null:
		print("[PlayerModelController] root_motion_track=", _anim_player.root_motion_track,
			" has_idle=", _anim_player.has_animation("idle_lib/idle"))

func _ready() -> void:
	var parent: Node = get_parent()
	if parent is CharacterBody3D:
		_player = parent as CharacterBody3D

	## Starts already matching Player's real facing so there's no
	## spurious spin-up turn at spawn (would otherwise lerp from 0 to
	## wherever Player actually starts facing).
	if _player != null:
		_visual_yaw = _player.rotation.y

	## Aug 2026 fix pass — see "Root cause #1: hovering" in
	## PLAYER_MODEL_FLOOR_FACING_FIX_PLAN.md. Same math
	## CharacterShadowStandIn.gd uses: floor sits at -height/2 from the
	## capsule's own center, which is where this node is instanced.
	var capsule_height: float = FALLBACK_CAPSULE_HEIGHT
	if _player != null:
		var collision_node: Node = _player.get_node_or_null("CollisionShape3D")
		if collision_node is CollisionShape3D:
			var shape: Shape3D = (collision_node as CollisionShape3D).shape
			if shape is CapsuleShape3D:
				capsule_height = (shape as CapsuleShape3D).height
	position.y = -(capsule_height * 0.5) + MODEL_FLOOR_FUDGE

	_anim_player = _find_first_of_type(self, "AnimationPlayer") as AnimationPlayer
	var skeleton: Skeleton3D = _find_first_of_type(self, "Skeleton3D") as Skeleton3D

	## Generalizes what used to be Player.gd's single hardcoded
	## $MeshInstance3D.layers/cast_shadow lines (now removed there, see
	## docs/systems/player-model/README.md) to every visual mesh under
	## this node — a real character can end up with more than one
	## MeshInstance3D (body + separately-skinned hair/eyebrows in a
	## future pass).
	_skin_material = _build_skin_material()
	for node in _find_all_of_type(self, "MeshInstance3D"):
		var mi: MeshInstance3D = node as MeshInstance3D
		if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
			mi.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		## Aug 2026 fix pass — see SKIN_ALBEDO_PATH above.
		if mi.mesh != null:
			for surf_i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(surf_i, _skin_material)

	_setup_hair(skeleton)

	if _anim_player != null:
		## Aug 2026 fix pass — ALWAYS re-validate rather than only when
		## empty. PlayerModel.tscn hardcodes root_motion_track by hand;
		## the old `== NodePath()` guard skipped past a wrong-but-
		## non-empty value without ever checking it actually resolves.
		if skeleton != null and not _root_motion_track_valid(_anim_player, skeleton):
			var hips: NodePath = _find_bone_path(_anim_player, skeleton, "Hips")
			if hips != NodePath():
				_anim_player.root_motion_track = hips
		_play_state("idle")

	_print_diagnostics(skeleton)

func _process(delta: float) -> void:
	if _player == null:
		return

	## Smooth visual turn — see "Smooth Facing Turn" plan for the math.
	## Player.gd's own rotation.y still snaps instantly every frame;
	## this only eases what's rendered, everything reading Player's real
	## rotation elsewhere is unaffected.
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

## Same partial match, but returns the bare bone name — used wherever a
## caller needs just the name (e.g. BoneAttachment3D.bone_name), not a
## full track-relative NodePath.
static func _find_bone_name(skeleton: Skeleton3D, bone_hint: String) -> String:
	for i in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(i)
		if bone_hint.to_lower() in bone_name.to_lower():
			return bone_name
	return ""

## Attaches the configured hairstyle to our OWN Mixamo skeleton's Head
## bone. The source asset is a skinned mesh bound to a completely
## different (Quaternius-native) reference armature — we don't reuse
## that skin or skeleton at all. Instead: read the source mesh's own
## bind-pose transform for its "Head" joint (Skin.get_bind_pose() —
## exact per-asset value, not a guessed/hardcoded offset, since this
## differs slightly between hairstyle files), then apply that same
## transform to a plain static copy of the mesh, parented under a new
## BoneAttachment3D bound to OUR skeleton's Head bone. Valid specifically
## because the source mesh is 100% rigidly weighted to its own Head
## joint (verified by direct binary inspection, not assumed) — a static
## mesh at the bind transform is visually identical to true skinning
## here, without needing to remap joint indices onto a different
## skeleton entirely.
func _setup_hair(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var hair_scene: PackedScene = load(HAIR_SCENE_PATH)
	if hair_scene == null:
		return
	var hair_root: Node = hair_scene.instantiate()
	var hair_mesh_src: MeshInstance3D = hair_root.find_child(HAIR_MESH_NODE_NAME, true, false) as MeshInstance3D
	if hair_mesh_src == null or hair_mesh_src.skin == null:
		hair_root.free()
		return

	var bind_transform: Transform3D = Transform3D.IDENTITY
	var found_bind: bool = false
	for i in hair_mesh_src.skin.get_bind_count():
		if hair_mesh_src.skin.get_bind_name(i) == "Head":
			bind_transform = hair_mesh_src.skin.get_bind_pose(i)
			found_bind = true
			break
	if not found_bind:
		hair_root.free()
		return

	var head_bone_name: String = _find_bone_name(skeleton, "Head")
	if head_bone_name == "":
		hair_root.free()
		return

	## Aug 2026 deviation from the plan doc (flagged): the plan used
	## hair_mesh.transform = skin.get_bind_pose("Head") directly. That
	## inverse-bind matrix is authored in the SOURCE armature's frame and
	## only composes to identity when multiplied by a head transform with
	## the source's own orientation — our Mixamo head's rest basis is
	## rotated ~10 deg off it (verified headlessly: hair landed at the
	## feet/hips). Using OUR head bone's rest global inverse instead gives
	## exactly the plan's intended result: identity composition at rest
	## (hair renders at its authored head position) and the hair rides the
	## head's animated deviation like true skinning would.
	var head_bone_idx: int = skeleton.find_bone(head_bone_name)
	var our_head_rest: Transform3D = skeleton.get_bone_global_rest(head_bone_idx)
	bind_transform = our_head_rest.affine_inverse()

	var attachment := BoneAttachment3D.new()
	attachment.bone_name = head_bone_name
	skeleton.add_child(attachment)

	var hair_mesh := MeshInstance3D.new()
	hair_mesh.name = "Hair"
	hair_mesh.mesh = hair_mesh_src.mesh
	hair_mesh.transform = bind_transform
	## Same self-light/shadow treatment as the body mesh (see the main
	## mesh loop in _ready()) — applied directly here since this mesh is
	## created AFTER that loop already ran.
	if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
		hair_mesh.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
	hair_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attachment.add_child(hair_mesh)

	hair_root.free()