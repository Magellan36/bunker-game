class_name PlayerModelController
extends Node3D
## PlayerModelController.gd
##
## ============================================================
## PACKED AWAY — Aug 2026, V1 simplification. NOT DELETED, NOT wired
## into any live scene right now. Player.tscn and the character-creation
## screen both moved to AdventurerModelController.gd / AdventurerModel.tscn
## instead (two complete Quaternius "Adventurer" models — one per gender,
## no per-piece customization). This whole file — the outfit system, the
## hairstyle/beard/hair-color system, the native-rig switch, the retexture
## work — is preserved exactly as it stood, for reintroduction once real
## customization art/scope is ready for a later version. See
## docs/systems/player-model/README.md "V1 simplification — Adventurer
## models" for the full reasoning and how to bring it back (short version:
## point Player.tscn's PlayerModel/PlayerModelShadow nodes at
## PlayerModel.tscn again instead of AdventurerModel.tscn, and re-enable
## CharacterCreationScreen.gd's Hair category button).
## ============================================================
##
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
## Aug 2026 fix — Eyes/Eyebrows are separate sub-meshes in male.fbx/
## female.fbx (confirmed via their own distinct UV layer names,
## EyesDiffuseUVLayer/EyebrowsDiffuseUVLayer) that were incorrectly
## receiving the body's skin material — see _build_eye_material()/
## _build_eyebrow_material() and the mesh loop below. A real eye
## texture exists in the source kit; there's no dedicated eyebrow
## texture anywhere in it, so eyebrows get a flat color instead (see
## _build_eyebrow_material()).
const EYE_ALBEDO_PATH: String = "res://assets/models/player/textures/T_Eye_Brown.png"
const EYE_NORMAL_PATH: String = "res://assets/models/player/textures/T_Eye_Normal.png"

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

## Aug 2026 — Peasant outfit. Only meaningful under native_rig — its
## skin joints are an exact match (65/65, same names, same order,
## confirmed by direct comparison) for the native skeleton specifically,
## not the old Mixamo one, so this is never attempted when native_rig
## is false. Note: the outfit gltf files are imported with the same
## bone_map_native.tres retarget as the native bodies, so the imported
## scene uses the Humanoid-profile bone names that OUR skeleton has.
const OUTFIT_SCENE_PATHS: Dictionary = {
	"male": "res://assets/models/player/outfits/Male_Peasant.gltf",
	"female": "res://assets/models/player/outfits/Female_Peasant.gltf",
}

## Aug 2026 (2nd rework) — Peasant outfit clip fix, REPLACED. The
## previous "option B" approach (a from-scratch per-vertex band/radius
## heuristic trying to guess which skin triangles a garment geometrically
## covers) was solving a problem this asset was never designed to have.
## Confirmed directly from the asset creator's own documentation
## (Modular Character Outfits - Fantasy's Readme.txt, read directly from
## the source pack on disk): "When using the clothing, only the head of
## the model is required. Using the full body will result in clipping."
## The outfit's own modular pieces (Body/Legs/Feet/Arms) are meant to BE
## the entire visible torso/limbs/hands on their own — they were never
## authored to align precisely with the base body's silhouette, which is
## exactly why the old per-triangle band/radius/poke-allowance system
## kept finding new gaps no matter how it was tuned (collar, hip, and
## finally the hands). Per the pack's own itch.io changelog (v2.0), the
## Arms piece deliberately bakes in its own skin-toned arm/hand geometry
## ("included the human arms on Peasant_Male, now all models work with
## just the head") specifically so the base body's real arm/hand is
## never needed — the "double hands" reported in testing was the real
## bare hand rendering underneath the outfit's own correctly-designed
## one, not a duplicate node and not a bug in the glove mesh itself.
## The fix is now simply: keep only Head/neck-dominant body skin visible
## whenever an outfit is equipped, and hide everything else outright —
## no per-garment geometry comparison, no live-pose sampling, no band/
## radius/allowance tuning to chase. This is pose-INDEPENDENT (a fixed
## per-bone decision, not a live-geometry one), so it runs once,
## synchronously, at outfit-setup time — see _hide_body_below_head().
const HEAD_REGION_BONE_MARKERS: Array[String] = ["head", "neck"]

## Aug 2026 retexture — flat boot color, applied as a surface override
## material in _setup_outfit()'s piece loop instead of baking into the
## shared texture atlas. See that call site's doc comment for why.
const BOOT_ALBEDO_COLOR: Color = Color(0.055, 0.032, 0.018)

## Aug 2026 native-rig rebuild — the Quaternius-native bodies, selected
## instead of BODY_SCENE_PATHS when native_rig is true. See the flag's
## doc comment and the README "Native-rig rebuild" section for the switch
## sequence and what's verified vs. still unverified on this body.
const NATIVE_BODY_SCENE_PATHS: Dictionary = {
	"male": "res://assets/models/player/Superhero_Male_FullBody.gltf",
	"female": "res://assets/models/player/Superhero_Female_FullBody.gltf",
}

## Aug 2026 — opt-in flag for reading CharacterCreationData (gender/
## hairstyle_key/hair_tint_color) instead of the hardcoded defaults
## below. Set true on Player.tscn's PlayerModel/PlayerModelShadow nodes
## and on the character-creation screen's live preview instance. Left
## false (the default) for NPCs and anything else — nothing about NPC
## appearance changes based on what the player picks for themselves.
@export var use_character_creation_data: bool = false

## Aug 2026 — opt-in flag for NPCs: each NPC rolls its OWN random
## gender/hairstyle/color/beard on spawn, independent of both the
## player's CharacterCreationData choice and every other NPC. Set true
## on NPC.tscn's CharacterModel/CharacterModelShadow nodes. Mutually
## exclusive in practice with use_character_creation_data — an instance
## should only ever have one of the two set true.
@export var randomize_appearance: bool = false

## Aug 2026 native-rig rebuild — opt-in switch for the Quaternius-native
## base body (Superhero_Male/Female_FullBody.gltf) replacing the
## Mixamo-retargeted male.fbx/female.fbx. Default false: behavior is the
## existing Mixamo path, unchanged. Set true ONLY after the Part-2 editor
## retarget is done AND PlayerModel.tscn's animation libraries point at
## retargeted .res resources — this flag only switches the body/hair/
## material logic; the animation resources are the other half of the
## switch (see README "Native-rig rebuild" + the plan doc). Forward-facing
## is now VERIFIED (the 180° Y flip is applied in _ready(), confirmed in
## playtest); hair bind-pose placement is checked but still needs a visual
## look-over at the checkpoint.
@export var native_rig: bool = false

## Gender-applicability mirror of CharacterCreationScreen.gd's
## HAIRSTYLE_OPTIONS, used only for NPC random rolls (the UI script's
## own list isn't reachable from here — this is the model layer, it
## shouldn't depend on UI-layer script for data). Keep in sync if
## hairstyles are ever added/removed from either list.
const HAIRSTYLES_BY_GENDER: Dictionary = {
	"male": ["buzzed", "simple_parted", "long", "buns"],
	"female": ["buzzed_female", "simple_parted", "long", "buns"],
}

## Mirrors CharacterCreationScreen.gd's HAIR_COLOR_SWATCHES — same
## reasoning as HAIRSTYLES_BY_GENDER above, kept independent rather than
## cross-referenced.
const RANDOM_HAIR_COLORS: Array[Color] = [
	Color(0.02, 0.02, 0.02),
	Color(0.12, 0.08, 0.05),
	Color(0.25, 0.15, 0.08),
	Color(0.45, 0.30, 0.15),
	Color(0.55, 0.42, 0.20),
	Color(0.75, 0.60, 0.30),
	Color(0.35, 0.12, 0.05),
	Color(0.55, 0.25, 0.08),
	Color(0.55, 0.55, 0.55),
	Color(0.85, 0.85, 0.82),
]

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
## (behind the model, toward -Z) by -0.0025 three times, then -0.0015,
## then -0.001 (1.0cm total).
## Aug 2026 (female pass, live feedback): the female body inherits these
## exact male-tuned offsets (shared dict, identical Head-bone orientation
## verified from both FBX bind poses), but the hair still read slightly
## too high and too forward on her. A small uniform female-only delta is
## applied at runtime below (FEMALE_HAIR_DELTA) so the male stays locked.
const HAIRSTYLES: Dictionary = {
	"buzzed": {
		"scene": "res://assets/models/player/hair/Hair_Buzzed.gltf",
		"mesh_node": "Hair_Buzzed",
		"albedo": "res://assets/models/player/hair/T_Hair_1_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_1_Normal.png",
		"position_offset": Vector3(0.0, -1.596469, 0.047),
	},
	"buzzed_female": {
		"scene": "res://assets/models/player/hair/Hair_BuzzedFemale.gltf",
		"mesh_node": "Hair_BuzzedFemale",
		"albedo": "res://assets/models/player/hair/T_Hair_1_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_1_Normal.png",
		## Armature B (Head world y=1.5496): delta from buzzed's head
		## is +0.0502 y, -0.0065 z — computed from the source
		## inverse-bind matrices, not the mesh AABB center.
		"position_offset": Vector3(0.0, -1.546269, 0.0405),
	},
	"simple_parted": {
		"scene": "res://assets/models/player/hair/Hair_SimpleParted.gltf",
		"mesh_node": "Hair_SimpleParted",
		"albedo": "res://assets/models/player/hair/T_Hair_1_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_1_Normal.png",
		## Armature A — identical head bone to buzzed's, so the same
		## offset; this style's own (higher) center places it right.
		"position_offset": Vector3(0.0, -1.596469, 0.047),
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
		"position_offset": Vector3(0.0, -1.596469, 0.047),
	},
	"buns": {
		"scene": "res://assets/models/player/hair/Hair_Buns.gltf",
		"mesh_node": "Hair_Buns",
		"albedo": "res://assets/models/player/hair/T_Hair_2_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_2_Normal.png",
		## Armature B — see buzzed_female's note; same derived delta.
		"position_offset": Vector3(0.0, -1.546269, 0.0405),
	},
	"long": {
		"scene": "res://assets/models/player/hair/Hair_Long.gltf",
		"mesh_node": "Hair_Long",
		"albedo": "res://assets/models/player/hair/T_Hair_2_BaseColor.png",
		"normal": "res://assets/models/player/hair/T_Hair_2_Normal.png",
		## Armature B — see buzzed_female's note; same derived delta.
		"position_offset": Vector3(0.0, -1.546269, 0.0405),
	},
}

## Aug 2026 — female-only placement correction, added to every style's
## position_offset when the body gender is "female". The female body
## shares the exact male-tuned HAIRSTYLES values (see the dict comment),
## but live feedback showed her hair still sitting slightly too high and
## too forward, so she gets a small extra uniform shift (down, back).
## Uniform across styles so relative placement between them is unchanged;
## tweak freely while iterating, the male is unaffected.
## Aug 2026 (female 2nd pass): a further per-style "back" push was needed
## for every style EXCEPT long — see FEMALE_HAIR_EXTRA_BACK_Z below.
const FEMALE_HAIR_DELTA: Vector3 = Vector3(0.0, -0.005, -0.005)

## Aug 2026 — additional female-only backward (toward -Z) shift per style,
## applied on top of FEMALE_HAIR_DELTA's Z. Live feedback pass: every
## non-long style was brought to land on the SAME effective z as buns
## (0.028): base_z + FEMALE_HAIR_DELTA.z + this = 0.028. long is
## deliberately 0.0 — it already sat right.
## Aug 2026 (per-style follow-ups): simple_parted pushed back another
## 0.2cm, buzzed_female a further 0.05cm back (-0.0005).
const FEMALE_HAIR_EXTRA_BACK_Z: Dictionary = {
	"buzzed": -0.014,
	"simple_parted": -0.023,
	"beard": -0.014,
	"buzzed_female": -0.008,
	"buns": -0.0075,
	"long": 0.0,
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

func _build_eye_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var albedo: Texture2D = load(EYE_ALBEDO_PATH)
	var normal: Texture2D = load(EYE_NORMAL_PATH)
	if albedo != null:
		mat.albedo_texture = albedo
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	return mat

## No dedicated eyebrow texture exists anywhere in the source kit
## (checked) — a flat color is the simplest correct fix, and reuses
## hair_tint_color rather than adding a separate eyebrow-color concept.
func _build_eyebrow_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = hair_tint_color
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
	var beard_enabled: bool = false
	if use_character_creation_data:
		gender = CharacterCreationData.gender
		hairstyle_key = CharacterCreationData.hairstyle_key
		hair_tint_color = CharacterCreationData.hair_tint_color
		beard_enabled = CharacterCreationData.beard_enabled
	elif randomize_appearance and _player != null:
		## Whichever of this NPC's two PlayerModelController instances
		## (CharacterModel/CharacterModelShadow) runs _ready() first
		## rolls and stashes the result on their shared parent (the NPC
		## CharacterBody3D itself, via Godot's built-in node metadata —
		## no NPC.gd changes needed); the second instance just reads it
		## back, so the model and its shadow always match.
		if not _player.has_meta("_char_random_gender"):
			var rolled_gender: String = "male" if randi() % 2 == 0 else "female"
			var valid_styles: Array = HAIRSTYLES_BY_GENDER.get(rolled_gender, HAIRSTYLES_BY_GENDER["male"])
			var rolled_style: String = valid_styles[randi() % valid_styles.size()]
			var rolled_color: Color = RANDOM_HAIR_COLORS[randi() % RANDOM_HAIR_COLORS.size()]
			## Strictly no beard on female — never part of the random
			## roll for female NPCs, not just "didn't happen to roll
			## it". The explicit final override below is a deliberate
			## second guard on top of the male-only roll, not
			## redundant: if this logic is ever reordered or extended
			## later, female still can't end up with a beard.
			var rolled_beard: bool = rolled_gender == "male" and randi() % 2 == 0
			if rolled_gender == "female":
				rolled_beard = false
			_player.set_meta("_char_random_gender", rolled_gender)
			_player.set_meta("_char_random_hairstyle", rolled_style)
			_player.set_meta("_char_random_color", rolled_color)
			_player.set_meta("_char_random_beard", rolled_beard)
		gender = _player.get_meta("_char_random_gender")
		hairstyle_key = _player.get_meta("_char_random_hairstyle")
		hair_tint_color = _player.get_meta("_char_random_color")
		beard_enabled = _player.get_meta("_char_random_beard")

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
	var body_scene_path: String = (
		NATIVE_BODY_SCENE_PATHS.get(gender, NATIVE_BODY_SCENE_PATHS["male"])
		if native_rig
		else BODY_SCENE_PATHS.get(gender, BODY_SCENE_PATHS["male"])
	)
	var body_scene: PackedScene = load(body_scene_path)
	var body: Node3D = body_scene.instantiate()
	body.name = "MaleModel"
	## Aug 2026 native-rig rebuild, VERIFIED in playtest: the native body
	## also faces backwards (same as the Mixamo body did) — the baked -90° X
	## rotation on its root orients the skeleton Y-up but does NOT correct
	## the forward axis, so the body and every animation render mirrored
	## when the player moves along Godot's -Z forward. Apply the same 180° Y
	## flip both rigs need.
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
	_skin_material = _build_skin_material(gender) if not native_rig else null
	var eye_material: StandardMaterial3D = _build_eye_material() if not native_rig else null
	## Unlike skin/eyes there's no dedicated eyebrow texture in the
	## source kit, so the gltf-baked material is just the untinted hair
	## texture (MI_Hair_1/MI_Hair_2) and reads wrong next to
	## hair_tint_color. Build the flat-color eyebrow material on BOTH
	## paths so native-rig eyebrows match hair color at load and stay
	## repaintable from the creation screen.
	var eyebrow_material: StandardMaterial3D = _build_eyebrow_material()
	## This loop runs before _setup_hair() attaches anything, so at this
	## point it only ever sees the body file's own sub-meshes — never the
	## later-attached Hair/Beard meshes, which get their own dedicated
	## materials in _setup_hair()/_build_hair_material() instead.
	for node in _find_all_of_type(self, "MeshInstance3D"):
		var mi: MeshInstance3D = node as MeshInstance3D
		if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
			mi.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
		mi.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if is_shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		## Aug 2026 native-rig rebuild: on the native body the gltf import's
		## own baked materials are used as-is (they reference the real
		## textures — verified in the source file), so the runtime
		## skin/eye overrides below are Mixamo-path-only. The eyebrow
		## override is the exception and applies on BOTH paths — there's
		## no eyebrow texture in the kit, so the baked material is just
		## the untinted hair texture and must be replaced with the
		## flat-color hair-tint material (see the builder above).
		var material_to_apply: StandardMaterial3D = null
		if not native_rig:
			material_to_apply = _skin_material
			if mi.name == "Eyes":
				material_to_apply = eye_material
			elif mi.name == "Eyebrows":
				material_to_apply = eyebrow_material
		elif mi.name == "Eyebrows":
			material_to_apply = eyebrow_material
		if material_to_apply != null and mi.mesh != null:
			for surf_i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(surf_i, material_to_apply)

	_setup_outfit(skeleton, gender)

	_setup_hair(skeleton, hairstyle_key, gender)
	if beard_enabled:
		## Second, independent call into the same placement logic the
		## main hairstyle already drives — see the attachment_mesh_name
		## param's doc comment. "Beard" instead of "Hair" so the
		## creation screen's swatch re-tint can repaint both by name.
		_setup_hair(skeleton, "beard", gender, "Beard")

	if _anim_player != null:
		## Aug 2026 fix pass — ALWAYS re-validate rather than only when
		## empty. PlayerModel.tscn hardcodes root_motion_track by hand;
		## the old `== NodePath()` guard skipped past a wrong-but-
		## non-empty value without ever checking it actually resolves.
		if skeleton != null and not _root_motion_track_valid(_anim_player, skeleton):
			## Aug 2026 native-rig rebuild — with the Part-2 retarget config the
			## native skeleton's hip bone is ALSO renamed to the humanoid-profile
			## "Hips" (bone_map_native.tres maps pelvis->Hips), so both pipelines
			## resolve the same way here.
			var hips: NodePath = _find_bone_path(
				_anim_player, skeleton, "Hips")
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
## Aug 2026 — attachment_mesh_name added so a second call (for the
## beard, see the _ready() call site) can produce a distinctly-named
## mesh ("Beard") instead of colliding with the main hairstyle's
## "Hair" — CharacterCreationScreen.gd's swatch re-tint logic looks
## for both names so beard color always follows the selected hair
## color. Every other line of this function is completely unaware
## beard is a special case at all; it's just attaching a second style
## by key, exactly like the first.
## Aug 2026 — direct skin/skeleton reassignment, not a BoneAttachment3D
## rig like hair/beard use. Only valid because the outfit's skin joints
## are confirmed identical to our own skeleton (same source rig, and both
## imported through bone_map_native.tres so the bone names match) — for
## any future asset where that ISN'T true, this is the wrong pattern to
## copy, use the hair-style bind-pose/BoneAttachment3D approach instead.
func _setup_outfit(skeleton: Skeleton3D, gender: String) -> void:
	if skeleton == null or not native_rig:
		return
	var outfit_scene_path: String = OUTFIT_SCENE_PATHS.get(gender, OUTFIT_SCENE_PATHS["male"])
	var outfit_scene: PackedScene = load(outfit_scene_path)
	if outfit_scene == null:
		return
	var outfit_root: Node = outfit_scene.instantiate()
	var pieces: Array[MeshInstance3D] = []
	for src_node in _find_all_of_type(outfit_root, "MeshInstance3D"):
		var src: MeshInstance3D = src_node as MeshInstance3D
		var piece := MeshInstance3D.new()
		piece.name = "Outfit_" + src.name
		piece.mesh = src.mesh
		piece.skin = src.skin
		pieces.append(piece)
	outfit_root.free()
	if pieces.is_empty():
		return

	## Realign the outfit's baked skin binds to the body's rest pose
	## (identity skinning) — see _rewrite_outfit_skin_binds()'s own doc
	## comment. A separate concern from body-hiding below: this is about
	## the outfit rendering in the right place, not about what body skin
	## stays visible under it.
	for piece in pieces:
		_rewrite_outfit_skin_binds(skeleton, piece)
	## Aug 2026 (2nd rework) — hide everything but the head/neck now that
	## an outfit is confirmed equipped. See HEAD_REGION_BONE_MARKERS' doc
	## comment for why. Synchronous — no more await/frame-sampling needed,
	## since which bone a vertex belongs to doesn't depend on live pose.
	_hide_body_below_head(skeleton)

	for piece in pieces:
		if _player != null and "PLAYER_SELF_LIGHT_LAYER_BIT" in _player:
			piece.layers = _player.PLAYER_SELF_LIGHT_LAYER_BIT
		piece.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			if is_shadow_only
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		## Aug 2026 retexture — boots get a flat, very dark brown material
		## instead of the shared outfit texture atlas. A pixel-level fix on
		## the atlas kept reverting a specific patch of the boot shaft back
		## to its original pale color for reasons that resisted diagnosis
		## (not caching, masking, lighting, or the shared UV-overlap logic —
		## see docs/systems/player-model/README.md "Boot retexture" for the
		## dead ends ruled out); a flat material sidesteps that pipeline
		## entirely and is also just what a solid "very dark brown boots"
		## look calls for — no texture detail is lost that the design
		## actually needed.
		if "feet" in piece.name.to_lower():
			var boot_mat := StandardMaterial3D.new()
			boot_mat.albedo_color = BOOT_ALBEDO_COLOR
			boot_mat.roughness = 0.55
			if piece.mesh != null:
				for surf_i in piece.mesh.get_surface_count():
					piece.set_surface_override_material(surf_i, boot_mat)
		## Parented directly under our own skeleton (not the outfit's own
		## bundled one, which gets discarded below) — skeleton = ".."
		## points back at its own new parent. This is the whole trick:
		## the mesh's skin data already references bone names that exist
		## on OUR skeleton, so Godot binds and deforms it correctly using
		## our skeleton's live pose, no retargeting math needed.
		skeleton.add_child(piece)
		piece.skeleton = NodePath("..")

## The single skinned body mesh (Superhero_Female / SuperHero_Male) under
## this controller. The Eyes/Eyebrows sub-meshes are filtered out by the
## name check; outfit pieces aren't attached yet when this runs.
func _find_body_mesh() -> MeshInstance3D:
	for node in _find_all_of_type(self, "MeshInstance3D"):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.skin != null and mi.name.to_lower().contains("superhero"):
			return mi
	return null

## Hides every body-mesh vertex EXCEPT those dominantly weighted to a
## head/neck bone (see HEAD_REGION_BONE_MARKERS' doc comment above for
## the design rationale). Synchronous and pose-INDEPENDENT: which bone a
## vertex is dominantly skinned to never changes with animation, so
## unlike the old band/radius system this needs no live-pose sampling,
## no idle/carry-state handling, no awaits at all — it runs once, right
## when the outfit is attached.
func _hide_body_below_head(skeleton: Skeleton3D) -> void:
	var body_mesh: MeshInstance3D = _find_body_mesh()
	if body_mesh == null or body_mesh.mesh == null or body_mesh.skin == null:
		return
	var keep_binds := {}
	for b in body_mesh.skin.get_bind_count():
		var bone_name: String = body_mesh.skin.get_bind_name(b).to_lower()
		for marker in HEAD_REGION_BONE_MARKERS:
			if marker in bone_name:
				keep_binds[b] = true
				break
	var covered := PackedByteArray()
	for s in body_mesh.mesh.get_surface_count():
		var arrays := body_mesh.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vi in verts.size():
			var dominant: int = -1
			var dw := -1.0
			for w in 4:
				var bj: int = joints[vi * 4 + w]
				var bw: float = weights[vi * 4 + w]
				if bw > dw:
					dw = bw
					dominant = bj
			covered.append(0 if keep_binds.has(dominant) else 1)
	_split_body_mesh(body_mesh, covered)

## Realigns a piece's skin bind poses to identity skinning on the body
## skeleton: each bind pose becomes body-rest^-1 for its (name-matched)
## bone, so skel_global * bind == I at rest and the piece renders exactly
## at its authored coordinates while still following the animation. The
## male Peasant gltf was baked against a different rest pose and was
## displaced 2-4cm otherwise; the female gltf already ships rest^-1, so
## this is a no-op there. A fresh Skin is built (never mutating the
## imported resource, which is shared across every spawn).
func _rewrite_outfit_skin_binds(skeleton: Skeleton3D, piece: MeshInstance3D) -> void:
	if piece.skin == null:
		return
	var new_skin := Skin.new()
	new_skin.set_bind_count(piece.skin.get_bind_count())
	for b in piece.skin.get_bind_count():
		new_skin.set_bind_name(b, piece.skin.get_bind_name(b))
		new_skin.set_bind_pose(b, piece.skin.get_bind_pose(b))
	for b in piece.skin.get_bind_count():
		var bone_name: String = piece.skin.get_bind_name(b)
		if bone_name == "":
			continue
		var bone_idx: int = skeleton.find_bone(bone_name)
		if bone_idx == -1:
			continue
		new_skin.set_bind_pose(b, skeleton.get_bone_global_rest(bone_idx).affine_inverse())
	piece.skin = new_skin

## Rebuilds the body mesh without the covered triangles (conservative:
## a triangle is dropped if any of its vertices is covered). Preserves
## per-surface materials and surface count so the existing surface
## material overrides keep applying.
func _split_body_mesh(body_mesh: MeshInstance3D, covered: PackedByteArray) -> void:
	var old_mesh: Mesh = body_mesh.mesh
	var materials: Array = []
	for s in old_mesh.get_surface_count():
		materials.append(old_mesh.surface_get_material(s))
	var new_mesh := ArrayMesh.new()
	var offset := 0
	for s in old_mesh.get_surface_count():
		var arrays := old_mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array(range(verts.size()))
		var remap := PackedInt32Array()
		remap.resize(verts.size())
		remap.fill(-1)
		var kept_count := 0
		for vi in verts.size():
			if covered[offset + vi] == 0:
				remap[vi] = kept_count
				kept_count += 1
		var out_arrays: Array = []
		out_arrays.resize(Mesh.ARRAY_MAX)
		for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
				Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2,
				Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			var src: Variant = arrays[key]
			if src == null:
				continue
			out_arrays[key] = _remap_surface_array(key, src, remap, verts.size())
		var out_indices := PackedInt32Array()
		for t in indices.size() / 3:
			var i0: int = indices[t * 3]
			var i1: int = indices[t * 3 + 1]
			var i2: int = indices[t * 3 + 2]
			if remap[i0] != -1 and remap[i1] != -1 and remap[i2] != -1:
				out_indices.append(remap[i0])
				out_indices.append(remap[i1])
				out_indices.append(remap[i2])
		out_arrays[Mesh.ARRAY_INDEX] = out_indices
		new_mesh.add_surface_from_arrays(old_mesh.surface_get_primitive_type(s), out_arrays)
		offset += verts.size()
	for s in materials.size():
		new_mesh.surface_set_material(s, materials[s])
	body_mesh.mesh = new_mesh

## Rebuilds one surface array keeping only the vertices whose remap entry
## is >= 0. Stride handling: TANGENT/WEIGHTS/BONES are 4 elements per
## vertex, everything else is one element per vertex.
static func _remap_surface_array(key: int, src: Variant, remap: PackedInt32Array, src_size: int) -> Variant:
	match key:
		Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
			var out3 := PackedVector3Array()
			for vi in src_size:
				if remap[vi] != -1:
					out3.append(src[vi])
			return out3
		Mesh.ARRAY_TANGENT, Mesh.ARRAY_WEIGHTS:
			var outf := PackedFloat32Array()
			for vi in src_size:
				if remap[vi] != -1:
					for e in 4:
						outf.append(src[vi * 4 + e])
			return outf
		Mesh.ARRAY_COLOR:
			var outc := PackedColorArray()
			for vi in src_size:
				if remap[vi] != -1:
					outc.append(src[vi])
			return outc
		Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
			var out2 := PackedVector2Array()
			for vi in src_size:
				if remap[vi] != -1:
					out2.append(src[vi])
			return out2
		Mesh.ARRAY_BONES:
			var outi := PackedInt32Array()
			for vi in src_size:
				if remap[vi] != -1:
					for e in 4:
						outi.append(src[vi * 4 + e])
			return outi
	return null

## Aug 2026 — hair styles are their own scenes (bone-attached under the
## skeleton), driven entirely by the per-style HAIRSTYLES data. This
## function is called once per hairstyle (see the beard call in
## _ready()); the attachment_mesh_name param is how the same logic
## attaches both the main hair mesh (named "Hair") and the beard mesh
## (named "Beard") without special-casing either inline.
func _setup_hair(skeleton: Skeleton3D, hairstyle_key: String, gender: String, attachment_mesh_name: String = "Hair") -> void:
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
	var hair_skin: Skin = hair_mesh_src.skin

	## Aug 2026, second fix pass: the SOURCE skin's own bind-pose data is
	## no longer used to compute a transform on the Mixamo body (two
	## automatic attempts — the original plan's raw bind pose, then a
	## rest-pose-inverse heuristic — landed at the feet/hips, then the
	## mid-section respectively; both wrong because the hairstyles were
	## rigged against a DIFFERENT reference armature than our Mixamo body).
	## This check now only confirms the asset is a genuinely rigged hair
	## mesh (sanity guard), nothing more.
	var has_valid_skin: bool = hair_skin.get_bind_count() > 0
	if not has_valid_skin:
		hair_root.free()
		return

	var head_bone_name: String = _find_bone_name(skeleton, "Head")
	if head_bone_name == "":
		hair_root.free()
		return

	var attachment := BoneAttachment3D.new()
	attachment.bone_name = head_bone_name
	skeleton.add_child(attachment)

	var offset_basis: Basis = Basis.from_euler(Vector3(
		deg_to_rad(hair_rotation_offset_deg.x),
		deg_to_rad(hair_rotation_offset_deg.y),
		deg_to_rad(hair_rotation_offset_deg.z),
	))
	var base_offset: Vector3 = Vector3.ZERO
	var tuned_transform: Transform3D
	if native_rig:
		## Aug 2026 native-rig rebuild (Part 5 of the plan) — with the body
		## on the same native skeleton the hairstyles were rigged for, the
		## source skin's own Head bind pose should place each style
		## correctly with ZERO manual offset for the first time. The
		## Mixamo-era manual offsets (HAIRSTYLES position_offset,
		## FEMALE_HAIR_DELTA, FEMALE_HAIR_EXTRA_BACK_Z, the female beard
		## +3cm) are all derived from the OLD skeleton's geometry and
		## deliberately NOT applied here. "Should work, verify before
		## trusting" — if the bind pose lands wrong at the checkpoint, fall
		## back to the manual path and re-derive fresh numbers.
		var bind_index: int = -1
		for i in hair_skin.get_bind_count():
			if hair_skin.get_bind_name(i) == "Head":
				bind_index = i
				break
		if bind_index == -1:
			hair_root.free()
			attachment.free()
			return
		tuned_transform = Transform3D(offset_basis, hair_position_offset) * hair_skin.get_bind_pose(bind_index)
		print("[PlayerModelController] native hair: style=", hairstyle_key,
			" bind_pose=", hair_skin.get_bind_pose(bind_index))
	else:
		## Base offset comes from this style's own HAIRSTYLES entry
		## (see the dict's doc comment above for why only "buzzed"'s value
		## is actually playtested-correct) — hair_position_offset/
		## hair_rotation_offset_deg (both zero by default now) apply as an
		## additional delta on top, for a quick per-style correction without
		## touching the dictionary.
		base_offset = style.get("position_offset", Vector3.ZERO)
		if gender == "female":
			base_offset += FEMALE_HAIR_DELTA
			base_offset.z += FEMALE_HAIR_EXTRA_BACK_Z.get(hairstyle_key, 0.0)
			## Aug 2026 — beard-specific, on top of the generic female
			## delta above (which was tuned for scalp hair, not jaw
			## placement). Female beard sat 3cm too low.
			if hairstyle_key == "beard":
				base_offset.y += 0.03
		tuned_transform = Transform3D(offset_basis, base_offset + hair_position_offset)

	var hair_mesh := MeshInstance3D.new()
	hair_mesh.name = attachment_mesh_name
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
