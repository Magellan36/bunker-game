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
func _build_world_materials() -> void:
	## Darkening factor: 1/1.5 = 0.667 applied via albedo_color tint.
	##
	## TILING STRATEGY — two-frequency blending:
	##   UV1 (base): very coarse scale so 1 tile covers ~10-16m — eliminates
	##               the obvious grid repeat across large surfaces.
	##   UV2 (detail): fine scale at ~5-7x higher frequency overlaid at low
	##               opacity — adds surface grain/micro-detail without a
	##               visible repeat grid. detail_blend_mode = MIX at 0.35
	##               opacity means base dominates, detail just breaks flatness.
	##   Both layers use triplanar so seams never appear on any face angle.
	const DARK:          float = 0.667
	const DETAIL_WEIGHT: float = 0.35  ## 0=all base, 1=all detail

	var wall_tex:  Texture2D = load("res://assets/textures/concrete_wall.jpg")  as Texture2D
	var floor_tex: Texture2D = load("res://assets/textures/concrete_floor.jpg") as Texture2D

	## ── Wall material ──────────────────────────────────────────────────────
	_owner._mat_wall = StandardMaterial3D.new()
	_owner._mat_wall.roughness                = 0.92
	_owner._mat_wall.metallic                 = 0.0
	## Base layer — coarse, 1 tile per ~12m
	_owner._mat_wall.uv1_triplanar            = true
	_owner._mat_wall.uv1_triplanar_sharpness  = 3.0
	_owner._mat_wall.uv1_scale                = Vector3(0.083, 0.083, 0.083)
	## Detail layer — same texture at 6x higher frequency for surface grain
	_owner._mat_wall.detail_enabled           = true
	_owner._mat_wall.detail_blend_mode        = BaseMaterial3D.BLEND_MODE_MIX
	_owner._mat_wall.detail_uv_layer          = BaseMaterial3D.DETAIL_UV_2
	_owner._mat_wall.uv2_triplanar            = true
	_owner._mat_wall.uv2_triplanar_sharpness  = 3.0
	_owner._mat_wall.uv2_scale                = Vector3(0.50, 0.50, 0.50)
	if wall_tex != null:
		_owner._mat_wall.albedo_texture       = wall_tex
		_owner._mat_wall.albedo_color         = Color(DARK, DARK, DARK, 1.0)
		_owner._mat_wall.detail_albedo        = wall_tex
	else:
		_owner._mat_wall.albedo_color         = Color(0.37, 0.35, 0.32, 1.0)
	## Blend detail at reduced opacity so base stays dominant
	_owner._mat_wall.detail_mask              = null   ## no mask — uniform blend everywhere

	## ── Floor material ─────────────────────────────────────────────────────
	_owner._mat_floor = StandardMaterial3D.new()
	_owner._mat_floor.roughness               = 0.93
	_owner._mat_floor.metallic                = 0.0
	## Base layer — even coarser on floor (viewed top-down so tile edge stands out)
	_owner._mat_floor.uv1_triplanar           = true
	_owner._mat_floor.uv1_triplanar_sharpness = 3.0
	_owner._mat_floor.uv1_scale               = Vector3(0.063, 0.063, 0.063)
	## Detail layer
	_owner._mat_floor.detail_enabled          = true
	_owner._mat_floor.detail_blend_mode       = BaseMaterial3D.BLEND_MODE_MIX
	_owner._mat_floor.detail_uv_layer         = BaseMaterial3D.DETAIL_UV_2
	_owner._mat_floor.uv2_triplanar           = true
	_owner._mat_floor.uv2_triplanar_sharpness = 3.0
	_owner._mat_floor.uv2_scale               = Vector3(0.42, 0.42, 0.42)
	if floor_tex != null:
		_owner._mat_floor.albedo_texture      = floor_tex
		_owner._mat_floor.albedo_color        = Color(DARK, DARK, DARK, 1.0)
		_owner._mat_floor.detail_albedo       = floor_tex
	else:
		_owner._mat_floor.albedo_color        = Color(0.30, 0.29, 0.27, 1.0)

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
