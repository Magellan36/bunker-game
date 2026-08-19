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

## When true, every visual mesh under this model casts a real shadow but
## is never rendered to camera (Godot's SHADOWS_ONLY mode) instead of
## the default fully-invisible-to-shadows OFF. Set on a SECOND, scaled-
## down instance of this same scene (see Player.tscn's "PlayerModelShadow"
## node) so the player's shadow reflects the actual animated silhouette
## instead of a capsule stand-in — see docs/systems/graphics/README.md
## "Player model-based shadow". Default false: the primary, real
## PlayerModel instance is completely unaffected by this flag existing.
@export var is_shadow_only: bool = false

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
const SKIN_TEXTURES: Dictionary = {
	"male": {
		"albedo": "res://assets/models/player/textures/T_Superhero_Male_Dark.png",
		"normal": "res://assets/models/player/textures/T_Superhero_Male_Normal.png",
		"roughness": "res://assets/models/player/textures/T_Superhero_Male_Roughness.png",
	},
	"female": {
		"albedo": "res://assets/models/player/textures/T_Superhero_Female_Dark_BaseColor.png",
		"normal": "res://assets/models/player/textures/T_Superhero_Female_Normal.png",
		"roughness": "res://assets/models/player/textures/T_Superhero_Female_Roughness.png",
	},
}

## Aug 2026 — which body FBX to instantiate at runtime (see _ready()).
## Both share the identical mixamorig: skeleton, confirmed directly —
## every existing animation library plays on either unmodified.
const BODY_SCENE_PATHS: Dictionary = {
	"male": "res://assets/models/player/male.fbx",
	"female": "res://assets/models/player/female.fbx",
}

## Aug 2026 — opt-in flag for reading CharacterCreationData (gender/
## hairstyle_key/hair_tint_color) instead of the hardcoded defaults
## below. Set true on Player.tscn's PlayerModel/PlayerModelShadow nodes
## and on the character-creation screen's live preview instance. Left
## false (the default) for NPCs and anything else — nothing about NPC
## appearance changes based on what the player picks for themselves.
@export var use_character_creation_data: bool = false

## Hairstyles — Aug 2026. Sourced from WIP/FINAL/Hairstyles/"Rigged to
## Head Bone"/ (not "Origin at 0" — that variant has no bind-pose data
## to extract, see the plan doc for why "Rigged to Head Bone" was
## chosen despite looking more complex). Confirmed via direct binary
## inspection: 100% of each mesh's vertex weight is on its own "Head"
## joint, so they're treated as rigid props, not truly re-skinned.
## Everything in _setup_hair() is generic per-asset extraction, not
## specific to any particular style.
## Aug 2026 (2nd pass): the six assets actually span TWO different
## reference armatures, not one — buzzed/simple_parted/beard share
## armature A (Head bone world y=1.5998, ~-15.4deg x-rot), while
## buzzed_female/buns/long share armature B (Head bone world y=1.5496,
## ~-23.6deg x-rot). Per-style offsets are derived as
##   offset = buzzed_offset + (head_world_buzzed - head_world_style)
## (from the source inverse-bind matrices). The mesh-geometry-center
## terms cancel out of that derivation entirely — only the head-bone
## world delta matters, so armature A styles reuse buzzed's exact value
## and armature B styles get one shared small delta (+0.0502 y, -0.0065
## z). The first pass instead normalized each mesh's raw AABB center to
## buzzed's anchor, which lifted the beard ~11cm up off the jaw and
## mis-set every other style by 1-4cm.
## Aug 2026 (3rd pass, live feedback): all six Y offsets lowered by a
## uniform -0.02 (2cm) — everything still read slightly too high in the
## character creator. Relative placement between styles is unchanged.
## Aug 2026 (4th pass, live feedback): all six Z offsets moved back
## (behind the model, toward -Z) by -0.0025, then another -0.0025 (0.5cm
## total).
const HAIRSTYLES: Dictionary = {
	"buzzed": {
		"scene": "res://assets/models/player/hair/Hair_Buzzed.gltf",
		"mesh_node": "Hair_Buzzed",
		"albedo": "res://assets/models/player/hair/T_Hair_1_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_1_Normal.png",
		"position_offset": Vector3(0.0, -1.596469, 0.052),
	},
	"buzzed_female": {
		"scene": "res://assets/models/player/hair/Hair_BuzzedFemale.gltf",
		"mesh_node": "Hair_BuzzedFemale",
		"albedo": "res://assets/models/player/hair/T_Hair_1_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_1_Normal.png",
		## Armature B (Head world y=1.5496): delta from buzzed's head
		## is +0.0502 y, -0.0065 z — computed from the source
		## inverse-bind matrices, not the mesh AABB center.
		"position_offset": Vector3(0.0, -1.546269, 0.0455),
	},
	"simple_parted": {
		"scene": "res://assets/models/player/hair/Hair_SimpleParted.gltf",
		"mesh_node": "Hair_SimpleParted",
		"albedo": "res://assets/models/player/hair/T_Hair_1_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_1_Normal.png",
		## Armature A — identical head bone to buzzed's, so the same
		## offset; this style's own (higher) center places it right.
		"position_offset": Vector3(0.0, -1.596469, 0.052),
	},
	"beard": {
		"scene": "res://assets/models/player/hair/Hair_Beard.gltf",
		"mesh_node": "Hair_Beard",
		"albedo": "res://assets/models/player/hair/T_Hair_1_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_1_Normal.png",
		## Armature A — identical head bone to buzzed's. The beard's mesh
		## center sits ~11cm lower than the scalp styles' BECAUSE it
		## belongs on the jaw; the first pass's anchor-normalization
		## lifted it up onto the face, which is exactly the reported
		## problem. The same offset as buzzed preserves that correct
		## jaw placement.
		"position_offset": Vector3(0.0, -1.596469, 0.052),
	},
	"buns": {
		"scene": "res://assets/models/player/hair/Hair_Buns.gltf",
		"mesh_node": "Hair_Buns",
		"albedo": "res://assets/models/player/hair/T_Hair_2_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_2_Normal.png",
		## Armature B — see buzzed_female's note; same derived delta.
		"position_offset": Vector3(0.0, -1.546269, 0.0455),
	},
	"long": {
		"scene": "res://assets/models/player/hair/Hair_Long.gltf",
		"mesh_node": "Hair_Long",
		"albedo": "res://assets/models/player/hair/T_Hair_2_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_2_Normal.png",
		## Armature B — see buzzed_female's note; same derived delta.
		"position_offset": Vector3(0.0, -1.546269, 0.0455),
	},
}

## Aug 2026 — T_Hair_1_BaseColor.png is a neutral/untinted strand-shading
## texture, not a real hair color (opened it directly and confirmed —
## it's pale grey/beige as authored, same for T_Hair_2; the source glTF
## material doesn't set baseColorFactor either, so this was never going
## to render as real hair color without an explicit tint). Multiplied
## into albedo_color below, standard PBR base-color behavior. Exported
## so a different hair color is a one-field Inspector change, not a
## code edit.
@export var hair_tint_color: Color = Color(0.12, 0.08, 0.05)

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
	"idle_carry": "idle_carry_lib/idle_carry",
	"walk_carry": "walk_carry_lib/walk_carry",
	"run_carry": "run_carry_lib/run_carry",
}

var _player: CharacterBody3D = null
var _anim_player: AnimationPlayer = null
var _current_state: String = ""
var _skin_material: StandardMaterial3D = null
var _visual_yaw: float = 0.0

func _build_skin_material(gender: String) -> StandardMaterial3D:
	var textures: Dictionary = SKIN_TEXTURES.get(gender, SKIN_TEXTURES["male"])
	var mat := StandardMaterial3D.new()
	var albedo: Texture2D = load(textures["albedo"])
	var normal: Texture2D = load(textures["normal"])
	var rough: Texture2D = load(textures["roughness"])
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

## One-time floor-raycast diagnostic — Aug 2026, added after a report
## that the character's head appeared level with a "small table" (far
## too short for a standing human), which seems to conflict with the
## floor_offset print already confirmed self-consistent last pass. That
## self-consistency only proves the model is correctly aligned to
## wherever the CharacterBody3D's capsule physically rests — it can't
## detect a mismatch between the physics floor and the visual floor a
## player actually sees. Casts straight down from the skeleton's own
## position and compares the hit point to the skeleton's own Y — a
## meaningful non-zero diff here points at collision/level geometry,
## not this file. No-op (skipped, not printed) if there's no player or
## skeleton to check, or nothing within 5m below to hit.
func _print_floor_raycast_diagnostic(skeleton: Skeleton3D) -> void:
	if _player == null or skeleton == null:
		return
	var space_state: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var from: Vector3 = skeleton.global_position + Vector3(0, 0.5, 0)
	var to: Vector3 = skeleton.global_position + Vector3(0, -5.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.has("position"):
		var hit_y: float = (hit["position"] as Vector3).y
		print("[PlayerModelController] floor_raycast: hit_y=", hit_y,
			" skeleton_y=", skeleton.global_position.y,
			" diff=", skeleton.global_position.y - hit_y)
	else:
		print("[PlayerModelController] floor_raycast: no hit within 5m below skeleton")

func _ready() -> void:
	var parent: Node = get_parent()
	if parent is CharacterBody3D:
		_player = parent as CharacterBody3D

	## Starts already matching Player's real facing so there's no
	## spurious spin-up turn at spawn (would otherwise lerp from 0 to
	## wherever Player actually starts facing).
	if _player != null:
		_visual_yaw = _player.rotation.y

	## Aug 2026 — Character Creation. Only opted-in instances (Player's
	## real body + its shadow copy, and the creation screen's own
	## preview) read the player's chosen gender/hairstyle/color; NPCs
	## and anything else keep these hardcoded defaults untouched.
	var gender: String = "male"
	var hairstyle_key: String = "buzzed"
	if use_character_creation_data:
		gender = CharacterCreationData.gender
		hairstyle_key = CharacterCreationData.hairstyle_key
		hair_tint_color = CharacterCreationData.hair_tint_color

	## Body is now instantiated at runtime instead of being a static
	## child baked into PlayerModel.tscn (see that scene — the old
	## "MaleModel" node is gone from the .tscn). It's named "MaleModel"
	## anyway because every baked AnimationLibrary track is NodePath
	## "MaleModel/Skeleton3D:mixamorig_*" (the .fbx scenes expose their
	## skeleton as a direct child literally named "Skeleton3D", same for
	## male and female) — a different name here would make all six
	## animation libraries fail to resolve their tracks. Same 180°
	## Y-rotation fix as the original male-only pass (Mixamo forward-axis
	## vs. Godot's own -Z forward), applied generically to whichever body
	## loads — not independently re-verified for the female body, flagged
	## in the plan doc.
	var body_scene_path: String = BODY_SCENE_PATHS.get(gender, BODY_SCENE_PATHS["male"])
	var body_scene: PackedScene = load(body_scene_path)
	var body: Node3D = body_scene.instantiate()
	body.name = "MaleModel"
	body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	add_child(body)

	## Aug 2026 fix pass — see "Root cause #1: hovering" in
	## PLAYER_MODEL_FLOOR_FACING_FIX_PLAN.md. Same math
	## CharacterShadowStandIn.gd uses: floor sits at -height/2 from the
	## capsule's own center, which is where this node is instanced.
	##
	## Aug 2026, second fix pass — this offset only makes sense relative
	## to an actual CharacterBody3D's collision capsule. It was being
	## applied unconditionally even with no such parent (the character-
	## creation screen's standalone preview, parented to a plain
	## Node3D) — falling back to FALLBACK_CAPSULE_HEIGHT and shoving the
	## preview down by a meter for a "real floor" that doesn't exist in
	## that context. Confirmed directly against CharacterCreation.tscn:
	## no CharacterBody3D parent, no floor geometry either — this should
	## be a pure no-op there, not a shove.
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

	## Aug 2026 — diagnostic for the REAL spawned Player/NPC path
	## specifically (as opposed to the preview, fixed above). I
	## couldn't find a code-level regression there by reading the
	## files — Player.tscn's structure and the collision capsule are
	## both unchanged from the last confirmed-working state. If this
	## still prints "had_real_collision=false" for an actual in-game
	## Player or NPC (not the creation screen), that pins down exactly
	## what's failing to resolve; if it prints "true" with a sane
	## capsule_height and this still looks sunk, the bug is elsewhere
	## and this rules out the floor-offset code as the cause. Report
	## back the exact printed line rather than just "still sunk."
	if not is_shadow_only:
		print("[PlayerModelController] floor_offset: had_real_collision=", had_real_collision,
			" capsule_height=", capsule_height, " applied_position_y=", position.y,
			" parent=", (parent.name if parent != null else "null"))

	_anim_player = _find_first_of_type(self, "AnimationPlayer") as AnimationPlayer
	var skeleton: Skeleton3D = _find_first_of_type(self, "Skeleton3D") as Skeleton3D

	## Generalizes what used to be Player.gd's single hardcoded
	## $MeshInstance3D.layers/cast_shadow lines (now removed there, see
	## docs/systems/player-model/README.md) to every visual mesh under
	## this node — a real character can end up with more than one
	## MeshInstance3D (body + separately-skinned hair/eyebrows in a
	## future pass).
	_skin_material = _build_skin_material(gender)
	for node in _find_all_of_type(self, "MeshInstance3D"):
		var mi: MeshInstance3D = node as MeshInstance3D
		if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
			mi.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
		mi.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if is_shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		## Aug 2026 fix pass — see SKIN_TEXTURES above.
		if mi.mesh != null:
			for surf_i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(surf_i, _skin_material)

	_setup_hair(skeleton, hairstyle_key)

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

	## Aug 2026 follow-up: skip the diagnostic print for the shadow
	## instance — purely console-noise cleanup (duplicate block at
	## spawn), no behavior change either way.
	if not is_shadow_only:
		_print_diagnostics(skeleton)
		_print_floor_raycast_diagnostic(skeleton)

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
	if _is_holding_item():
		next_state += "_carry"
	_play_state(next_state)

## Works for both Player (get_held_item(), a method — see Player.gd) and
## NPC (held_item, a plain property — see NPC.gd) without needing either
## file to expose a shared interface. Returns false for anything that
## has neither, rather than erroring.
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

## Aug 2026 fix pass — see HAIRSTYLES' per-style albedo/normal above.
func _build_hair_material(style: Dictionary) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var albedo: Texture2D = load(style["albedo"])
	var normal: Texture2D = load(style["normal"])
	if albedo != null:
		mat.albedo_texture = albedo
		mat.albedo_color = hair_tint_color
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	## Source glTF material had doubleSided = true (thin hair-card
	## geometry needs both faces rendered, unlike the closed-surface
	## body mesh) — preserved explicitly since we're bypassing the
	## imported material entirely now.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

## Aug 2026 — now an ADDITIONAL fine-tune on top of whichever style's
## own base position_offset in HAIRSTYLES (was previously the sole
## placement mechanism, hardcoded to "buzzed"'s tuned value — now that
## multiple styles share this controller, that value moved into
## HAIRSTYLES as "buzzed"'s own entry, and these two exports go back to
## a neutral zero delta). Nudge in the Inspector while watching the live
## result if a specific style needs a small correction beyond its
## dictionary default.
@export var hair_position_offset: Vector3 = Vector3.ZERO
@export var hair_rotation_offset_deg: Vector3 = Vector3.ZERO

## Attaches the configured hairstyle to our OWN Mixamo skeleton's Head
## bone. The source asset is a skinned mesh bound to a completely
## different (Quaternius-native) reference armature — we don't reuse
## that skin or skeleton at all. A static copy of the mesh is parented
## under a new BoneAttachment3D bound to OUR skeleton's Head bone with a
## plain identity local transform; placement is entirely manual via
## hair_position_offset / hair_rotation_offset_deg (see the second fix
## pass comment below for why there's no automatic placement).
func _setup_hair(skeleton: Skeleton3D, hairstyle_key: String) -> void:
	if skeleton == null:
		return
	var style: Dictionary = HAIRSTYLES.get(hairstyle_key, HAIRSTYLES["buzzed"])
	var hair_scene: PackedScene = load(style["scene"])
	if hair_scene == null:
		return
	var hair_root: Node = hair_scene.instantiate()
	var hair_mesh_src: MeshInstance3D = hair_root.find_child(style["mesh_node"], true, false) as MeshInstance3D
	if hair_mesh_src == null or hair_mesh_src.skin == null:
		hair_root.free()
		return

	## Aug 2026, second fix pass: the SOURCE skin's own bind-pose data is
	## no longer used to compute a transform (two automatic attempts at
	## that — the original plan's raw bind pose, then a rest-pose-inverse
	## heuristic — landed at the feet/hips, then the mid-section
	## respectively; both wrong, and this can't be iterated on further
	## without seeing the live result). This check now only confirms the
	## asset is a genuinely rigged hair mesh (sanity guard), nothing more.
	var has_valid_skin: bool = hair_mesh_src.skin.get_bind_count() > 0
	if not has_valid_skin:
		hair_root.free()
		return

	var head_bone_name: String = _find_bone_name(skeleton, "Head")
	if head_bone_name == "":
		hair_root.free()
		return

	## Base offset now comes from this style's own HAIRSTYLES entry
	## (see the dict's doc comment above for why only "buzzed"'s value
	## is actually playtested-correct) — hair_position_offset/
	## hair_rotation_offset_deg (both zero by default now) apply as an
	## additional delta on top, for a quick per-style correction without
	## touching the dictionary.
	var base_offset: Vector3 = style.get("position_offset", Vector3.ZERO)

	var attachment := BoneAttachment3D.new()
	attachment.bone_name = head_bone_name
	skeleton.add_child(attachment)

	var offset_basis: Basis = Basis.from_euler(Vector3(
		deg_to_rad(hair_rotation_offset_deg.x),
		deg_to_rad(hair_rotation_offset_deg.y),
		deg_to_rad(hair_rotation_offset_deg.z),
	))
	var tuned_transform: Transform3D = Transform3D(offset_basis, base_offset + hair_position_offset)

	var hair_mesh := MeshInstance3D.new()
	hair_mesh.name = "Hair"
	hair_mesh.mesh = hair_mesh_src.mesh
	hair_mesh.transform = tuned_transform
	## Aug 2026 fix pass — see HAIRSTYLES' per-style albedo/normal above.
	## Applied to every surface the same way the body's skin material is,
	## in case this hairstyle ever has more than one (Hair_Buzzed only
	## has one today).
	var hair_material: StandardMaterial3D = _build_hair_material(style)
	if hair_mesh.mesh != null:
		for surf_i in hair_mesh.mesh.get_surface_count():
			hair_mesh.set_surface_override_material(surf_i, hair_material)
	## Same self-light/shadow treatment as the body mesh (see the main
	## mesh loop in _ready()) — applied directly here since this mesh is
	## created AFTER that loop already ran. Aug 2026 follow-up: this line
	## used to hardcode OFF regardless of is_shadow_only, which meant the
	## PlayerModelShadow instance's hair never cast a shadow either —
	## the silhouette was missing hair mass. Now matches the body mesh
	## loop's conditional exactly.
	if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
		hair_mesh.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
	hair_mesh.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if is_shadow_only
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	attachment.add_child(hair_mesh)

	hair_root.free()