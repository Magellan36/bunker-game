extends RefCounted
class_name BuildMaterials
## BuildMaterials.gd  —  Stage 10 (BuildModeController slice) extraction
## ─────────────────────────────────────────────────────────────────────────────
## Ghost-preview and world-surface material builders, extracted out of
## BuildModeController.gd. Chosen as the first slice of BuildModeController's
## own god-object cleanup because it's fully self-contained: confirmed zero
## external callers anywhere else in the repo, and internally only touches
## the 5 material vars + 1 const listed below — no placement/undo/ghost/move
## state at all.
##
## SCOPE:
##   _build_ghost_materials, _build_world_materials, _apply_world_material,
##   _apply_wall_material_recursive.
##
## OUT OF SCOPE: _apply_material_recursive (hover-glow material swap) stays on
## BuildModeController — it's a different feature (hover highlight, not
## static ghost/world material setup) that happens to share a similar
## recursive-MeshInstance3D-walk shape, but touches `_hover_restore_mats` and
## is only ever called from `_update_hover_glow`/`_clear_hover_glow`, which
## stay put.
##
## DESIGN — same `_owner` back-reference pattern as every prior extraction.
## `_mat_valid`/`_mat_invalid`/`_mat_hover`/`_mat_wall`/`_mat_floor` (the actual
## StandardMaterial3D instances, read by ghost-preview/placement code
## elsewhere in BuildModeController) and `TILE_FLOOR` stay declared on
## BuildModeController — reached via `_owner.<name>`.
##
## BuildModeController holds one instance (`_materials`) and forwards the 3
## functions still called from elsewhere in that file with identical
## signatures: `_build_ghost_materials()`/`_build_world_materials()` (called
## once from `_ready()`), `_apply_world_material()` (called from bed-wiring
## and `_spawn_placed_object()`). `_apply_wall_material_recursive()` is only
## called from within this same cluster, so needs no wrapper.

var _owner: BuildModeController = null

func _init(owner: BuildModeController) -> void:
	_owner = owner


func _build_ghost_materials() -> void:
	_owner._mat_valid = StandardMaterial3D.new()
	_owner._mat_valid.albedo_color               = Color(0.42, 0.87, 0.15, 0.50)
	_owner._mat_valid.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_owner._mat_valid.depth_draw_mode            = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_owner._mat_valid.no_depth_test              = true
	_owner._mat_valid.emission_enabled           = true
	_owner._mat_valid.emission                   = Color(0.3, 0.8, 0.1)
	_owner._mat_valid.emission_energy_multiplier = 0.8
	_owner._mat_valid.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_owner._mat_valid.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_owner._mat_valid.render_priority            = 1

	_owner._mat_invalid = StandardMaterial3D.new()
	_owner._mat_invalid.albedo_color               = Color(0.9, 0.2, 0.15, 0.50)
	_owner._mat_invalid.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_owner._mat_invalid.depth_draw_mode            = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_owner._mat_invalid.no_depth_test              = true
	_owner._mat_invalid.emission_enabled           = true
	_owner._mat_invalid.emission                   = Color(0.8, 0.1, 0.05)
	_owner._mat_invalid.emission_energy_multiplier = 0.7
	_owner._mat_invalid.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_owner._mat_invalid.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_owner._mat_invalid.render_priority            = 1

	_owner._mat_hover = StandardMaterial3D.new()
	_owner._mat_hover.albedo_color               = Color(0.25, 0.65, 1.0, 0.60)
	_owner._mat_hover.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_owner._mat_hover.depth_draw_mode            = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_owner._mat_hover.no_depth_test              = true
	_owner._mat_hover.emission_enabled           = true
	_owner._mat_hover.emission                   = Color(0.15, 0.55, 1.0)
	_owner._mat_hover.emission_energy_multiplier = 1.2
	_owner._mat_hover.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_owner._mat_hover.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	_owner._mat_hover.render_priority            = 1

# ─── World surface materials ──────────────────────────────────────────────────
## Shared floor material (Aug 2026, Concrete032 retexture) — used by BOTH the
## pregen GridMap floor (MainWorld._apply_floor_texture) and player-built
## floors (_mat_floor). One ambientCG 2048² concrete set projected triplanar
## in world space at uv1_scale = 1/16, so one texture instance spans the whole
## ~16m bunker interior instead of repeating per 2m GridMap tile (the old flat
## per-tile UV). The .tres that ships with the set claims channel 4 (alpha)
## for roughness/AO, but the PNGs' alpha is 255 everywhere — the gray values
## live in the red channel, so use TEXTURE_CHANNEL_RED.
const FLOOR_TEX_UV_SCALE: float = 0.0625  ## 1/16 → 1 texture per 16m
## Half-strength AO copy for the floor (baked from
## Concrete032_2K-PNG_AmbientOcclusion.png — dials the occlusion influence
## down without touching the source asset).
const FLOOR_AO_SOFT := "res://assets/textures/Concrete032/Concrete032_2K-PNG_AmbientOcclusion_soft.png"
static func build_floor_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.90
	mat.metallic  = 0.0
	mat.specular  = 0.05   ## reduced highlight intensity (was 0.5 default)
	mat.uv1_triplanar           = true
	mat.uv1_world_triplanar     = true   ## world-space projection — CRITICAL on the GridMap
	mat.uv1_triplanar_sharpness = 3.0
	mat.uv1_scale               = Vector3(FLOOR_TEX_UV_SCALE, FLOOR_TEX_UV_SCALE, FLOOR_TEX_UV_SCALE)
	var color_tex: Texture2D = load("res://assets/textures/Concrete032/Concrete032_2K-PNG_Color.png") as Texture2D
	var normal_tex: Texture2D = load("res://assets/textures/Concrete032/Concrete032_2K-PNG_NormalGL.png") as Texture2D
	var rough_tex:  Texture2D = load("res://assets/textures/Concrete032/Concrete032_2K-PNG_Roughness.png") as Texture2D
	var ao_tex:     Texture2D = load(FLOOR_AO_SOFT) as Texture2D
	if color_tex != null:
		mat.albedo_texture = color_tex
		mat.albedo_color   = Color(1.15, 1.15, 1.15, 1.0)   ## subtle lift (Aug 2026)
	if normal_tex != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_tex
	if rough_tex != null:
		mat.roughness_texture           = rough_tex
		mat.roughness_texture_channel   = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if ao_tex != null:
		mat.ao_enabled       = true
		mat.ao_texture       = ao_tex
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return mat

## Shared wall material (Aug 2026, Concrete028 retexture) — used by BOTH the
## pregen walls/pillars (spawned via spawn_structure → _apply_world_material)
## and player-placed walls. Same setup as the floor: one ambientCG 2048² set,
## world-space triplanar at uv1_scale = 1/16 so one texture instance spans a
## ~16m wall run (matches the floor's density). No tint, no detail-blend layer
## (those existed to hide the low-res concrete_wall.jpg repeat). Roughness/AO
## gray values live in the red channel (the shipping .tres's alpha channel is
## a trap — the PNGs' alpha is 255 everywhere).
const WALL_TEX_UV_SCALE: float = 0.20   ## 1/5 → 1 texture per ~5m (slightly stretched so the fine-grained set reads larger; 16m wall = ~3 instances)
static func build_wall_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.92
	mat.metallic  = 0.0
	mat.specular  = 0.05   ## matches the floor's reduced highlight intensity
	mat.uv1_triplanar           = true
	mat.uv1_world_triplanar     = true
	mat.uv1_triplanar_sharpness = 3.0
	mat.uv1_scale               = Vector3(WALL_TEX_UV_SCALE, WALL_TEX_UV_SCALE, WALL_TEX_UV_SCALE)
	var color_tex: Texture2D = load("res://assets/textures/Concrete028/Concrete028_2K-PNG_Color.png") as Texture2D
	var normal_tex: Texture2D = load("res://assets/textures/Concrete028/Concrete028_2K-PNG_NormalGL.png") as Texture2D
	var rough_tex:  Texture2D = load("res://assets/textures/Concrete028/Concrete028_2K-PNG_Roughness.png") as Texture2D
	var ao_tex:     Texture2D = load("res://assets/textures/Concrete028/Concrete028_2K-PNG_AmbientOcclusion.png") as Texture2D
	if color_tex != null:
		mat.albedo_texture = color_tex
		mat.albedo_color   = Color(1.0, 1.0, 1.0, 1.0)
	if normal_tex != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_tex
	if rough_tex != null:
		mat.roughness_texture           = rough_tex
		mat.roughness_texture_channel   = BaseMaterial3D.TEXTURE_CHANNEL_RED
	if ao_tex != null:
		mat.ao_enabled       = true
		mat.ao_texture       = ao_tex
		mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return mat

## Shared wood material (Aug 2026, Wood006 retexture) — used by Table.gd's
## small + medium tables and the BuildStation/ResearchStation (all reuse the
## same wooden_table.glb base). Flat UV (the GLB has proper 0-1 UVs) at
## uv1_scale ~0.8 so the grain reads at a natural plank size on both the 3m
## medium table and the 0.9m small table. This set has NO ambient occlusion
## map (Wood006 ships Color/NormalGL/Roughness only). Roughness gray lives in
## the red channel (the shipping .tres's alpha channel is a trap — alpha is
## 255 everywhere).
const WOOD_TEX_UV_SCALE: float = 0.8   ## 1 texture per ~1.25m — zoomed in a touch from 1.0 so the grain reads bigger/fewer planks
static func build_wood_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.85
	mat.metallic  = 0.0
	mat.specular  = 0.05
	## Object-space triplanar: the mesh UVs wrap the texture to the model's
	## non-square 3m x 1.94m footprint (stretched ~1.5x along the length).
	## Triplanar projects from the object's own space so texels stay square
	## and the grain stays proportionate to the source image — and it follows
	## the table when the object is rotated (unlike world-space).
	mat.uv1_triplanar           = true
	mat.uv1_triplanar_sharpness = 3.0
	mat.uv1_scale               = Vector3(WOOD_TEX_UV_SCALE, WOOD_TEX_UV_SCALE, WOOD_TEX_UV_SCALE)
	var color_tex: Texture2D = load("res://assets/textures/Wood006/Wood006_2K-PNG_Color_rot.png") as Texture2D
	var normal_tex: Texture2D = load("res://assets/textures/Wood006/Wood006_2K-PNG_NormalGL_rot.png") as Texture2D
	var rough_tex:  Texture2D = load("res://assets/textures/Wood006/Wood006_2K-PNG_Roughness_rot.png") as Texture2D
	if color_tex != null:
		mat.albedo_texture = color_tex
		mat.albedo_color   = Color(1.0, 1.0, 1.0, 1.0)
	if normal_tex != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_tex
	if rough_tex != null:
		mat.roughness_texture           = rough_tex
		mat.roughness_texture_channel   = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return mat

## Recursively overrides every surface material of an instanced model with
## the given material — used to texture wooden_table.glb at runtime (its
## baked material is plain white). Surface overrides, not mesh mutation, so
## the shared GLB mesh resource is untouched across instances.
static func apply_material_to_model(model: Node3D, mat: StandardMaterial3D) -> void:
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		for s: int in m.mesh.get_surface_count():
			m.set_surface_override_material(s, mat)

## Mood override (Aug 2026) — dims, slightly desaturates and mattens a model's
## surfaces so they read in-theme with the dark bunker instead of toy-bright.
## Per-instance surface overrides (imported mesh materials are shared, never
## mutate them in place). Same recipe as FarmProduceItem's produce filter.
static func apply_mood_override(mi: MeshInstance3D, dark: float = 0.6, desat: float = 0.12, roughness: float = 0.8) -> void:
	if mi == null or mi.mesh == null:
		return
	for s: int in mi.mesh.get_surface_count():
		apply_surface_override(mi, s, dark, desat, roughness, 0.0)

## Per-SURFACE mood override with full control over dark/desat/roughness/
## metallic — for models whose parts need different treatments (e.g. the bed's
## grey frame is darker/rougher/metallic while the mattress accent keeps the
## standard filter). Reads the surface's base albedo off the shared imported
## material and writes a fresh StandardMaterial3D as the instance override.
static func apply_surface_override(mi: MeshInstance3D, surface: int,
		dark: float, desat: float, roughness: float, metallic: float) -> void:
	if mi == null or mi.mesh == null or surface < 0 or surface >= mi.mesh.get_surface_count():
		return
	var base: Color = Color(1.0, 1.0, 1.0, 1.0)
	var existing: Material = mi.mesh.surface_get_material(surface)
	if existing is StandardMaterial3D:
		base = (existing as StandardMaterial3D).albedo_color
	var c: Color = Color(base.r * dark, base.g * dark, base.b * dark, 1.0)
	var lum: float = c.get_luminance()
	c = c.lerp(Color(lum, lum, lum, 1.0), desat)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = roughness
	mat.metallic  = metallic
	mi.set_surface_override_material(surface, mat)

## Builds a CollisionShape3D from a model's visual AABB (in body space) for a
## given kind — "cylinder" is a vertical (Y-axis) cylinder sized to the AABB
## (height = size.y, radius = max of the horizontal extents / 2), anything
## else is a box. Centered on the AABB so the bottom rests flush with the
## model base.
static func build_model_collision(kind: String, aabb: AABB) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sz: Vector3 = aabb.size
	cs.position = aabb.position + sz * 0.5
	match kind:
		"cylinder":
			var cyl := CylinderShape3D.new()
			cyl.height = sz.y
			cyl.radius = maxf(sz.x, sz.z) * 0.5
			cs.shape = cyl
		_:
			var box := BoxShape3D.new()
			box.size = sz
			cs.shape = box
	return cs

func _build_world_materials() -> void:
	## ── Wall material ──────────────────────────────────────────────────────
	## Concrete028 retexture (Aug 2026): shared builder — pregen + build-mode.
	_owner._mat_wall = build_wall_material()

	## ── Floor material ─────────────────────────────────────────────────────
	## Concrete032 retexture (Aug 2026): shared builder — same look on
	## pregen + build-mode floors, one image across the whole bunker.
	_owner._mat_floor = build_floor_material()

## Apply the wall material to every surface of a freshly-spawned wall/pillar node.
## Called immediately after _spawn_placed_object returns a body.
func _apply_world_material(body: Node3D, tile_id: int) -> void:
	if body == null:
		return
	var mat: StandardMaterial3D = _owner._mat_wall if tile_id != _owner.TILE_FLOOR else _owner._mat_floor
	if mat == null:
		return
	_apply_wall_material_recursive(body, mat)

func _apply_wall_material_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			for s: int in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat)
	for child in node.get_children():
		_apply_wall_material_recursive(child, mat)
