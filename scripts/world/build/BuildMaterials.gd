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
	mat.metallic_specular  = 0.05   ## reduced highlight intensity (was 0.5 default)
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
	mat.metallic_specular  = 0.05   ## matches the floor's reduced highlight intensity
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
	mat.metallic_specular  = 0.05
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

## Angle-based ("auto smooth") normal rebuild (Sep 2026).
## Godot's wavefront_obj importer synthesizes PLAIN SMOOTH normals whenever an
## OBJ ships without `vn` data (Tinkercad exports never include normals) — it
## averages every face sharing a vertex, even across perpendicular faces. For
## boxy mechanical models that were authored to be flat-shaded this smears
## lighting across hard edges, producing exactly the two reported artifacts:
##   • PowerTerminal screen — a visible diagonal seam across the flat screen
##     (each screen quad is 2 triangles; smooth-averaged corner normals tilt
##     the otherwise-flat face).
##   • GrowLight top plate — a "needles to center" radial shading pattern
##     (the plate's flat top normals are averaged with its perpendicular
##     side walls, up to near-edge-on).
## This rebuild reclusters each vertex's incident faces by the angle between
## their face normals: within `angle_deg` they share one averaged normal
## (smooth — keeps the rounded grow-light tubes intact), beyond it they split
## into separate normals (flat — fixes the box corners/panels). Returns a NEW
## ArrayMesh (the shared imported resource is untouched); per-surface
## materials are carried over. Tangents are dropped (none of these materials
## use normal maps; Godot regenerates them if ever needed).
## CRITICAL ORIENTATION STEP: each geometric face normal is flipped to agree
## with the source mesh's importer-generated normal direction. The OBJ has no
## normals, so the wavefront importer's synthesized normal is the only
## authoritative "outward" signal — Tinkercad's triangle winding is
## inconsistent (the power terminal's faces were wound opposite to the grow
## light's), and without this flip the rebuilt flat faces point INTO the mesh,
## making the whole panel render as a dark silhouette.
## Rebuilt meshes are cached per source path so a farm full of grow lights
## (or many terminals) only pays the rebuild cost once per model, not once per
## instance — load() already returns the same shared ArrayMesh for a path.
static var _auto_smooth_cache: Dictionary = {}   ## res://path -> ArrayMesh

static func build_auto_smooth_mesh(src: ArrayMesh, angle_deg: float = 45.0) -> ArrayMesh:
	if src == null:
		return ArrayMesh.new()
	var cache_key: String = src.resource_path
	if cache_key != "" and _auto_smooth_cache.has(cache_key):
		return _auto_smooth_cache[cache_key] as ArrayMesh
	var out := _auto_smooth_mesh_rebuild(src, angle_deg)
	if cache_key != "":
		_auto_smooth_cache[cache_key] = out
	return out

static func _auto_smooth_mesh_rebuild(src: ArrayMesh, angle_deg: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	var cos_threshold: float = cos(deg_to_rad(angle_deg))
	for s: int in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var src_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if verts.size() < 3:
			continue

		## Flatten to an explicit triangle list, skipping degenerate triangles
		## (a face with a duplicated vertex index has zero area — Tinkercad's
		## fan triangulation emits a handful of these; they carry no geometry
		## and leave null group slots in the clustering below).
		var faces: Array[Vector3i] = []
		if indices.size() >= 3:
			for i: int in range(0, indices.size() - 2, 3):
				var a: int = indices[i]
				var b: int = indices[i + 1]
				var c: int = indices[i + 2]
				if a == b or b == c or a == c:
					continue
				faces.append(Vector3i(a, b, c))
		else:
			for i: int in range(0, verts.size() - 2, 3):
				if i == i + 1 or i + 1 == i + 2:
					continue
				faces.append(Vector3i(i, i + 1, i + 2))

		## Per-face geometric normal, ORIENTED to agree with the source mesh's
		## importer-generated normal. This is the critical step: the OBJ carries
		## no normals and the wavefront importer synthesizes them, so the source
		## normal's DIRECTION is authoritative (it consistently points outward —
		## verified against the terminal screen's room-facing face). The raw
		## geometric cross-product can disagree with it whenever the OBJ's
		## triangle winding is inconsistent (Tinkercad exports vary), which would
		## silently flip whole flat faces inward (the "covered in a dark shadow"
		## bug on the power terminal). We keep the cross product's magnitude-free
		## angle for clustering, but flip it to match the source's outward
		## orientation. Fallback = the source smooth normal itself if degenerate.
		var face_normals: Array[Vector3] = []
		for f: Vector3i in faces:
			var geo: Vector3 = (verts[f.y] - verts[f.x]).cross(verts[f.z] - verts[f.x])
			if src_normals.size() > f.x and src_normals[f.x].length_squared() > 0.001:
				## Source normal at the face's first corner gives the outward
				## half-space to keep — flip the geometric normal to match it.
				if geo.dot(src_normals[f.x]) < 0.0:
					geo = -geo
			elif geo.length_squared() < 0.0001 and src_normals.size() > f.x:
				geo = src_normals[f.x]
			face_normals.append(geo.normalized())

		## Incident faces per vertex index.
		var incident: Array[PackedInt32Array] = []
		incident.resize(verts.size())
		for fi: int in faces.size():
			for k: int in 3:
				incident[faces[fi][k]].append(fi)

		## Greedy cluster incident faces per vertex by normal angle. A face joins
		## an existing group only if it is within `angle_deg` of EVERY member
		## (conservative: splits more, never merges a true hard edge).
		var group_of: Array[Array] = []   ## [vertex][face] -> group index
		group_of.resize(verts.size())
		for vi: int in verts.size():
			var groups: Array[Array] = []   ## each group = Array of face indices
			for fi: int in incident[vi]:
				var placed: bool = false
				for g: Array in groups:
					var compatible: bool = true
					for gf: int in g:
						if face_normals[fi].dot(face_normals[gf]) < cos_threshold:
							compatible = false
							break
					if compatible:
						g.append(fi)
						placed = true
						break
				if not placed:
					groups.append([fi])
			var vg: Array = []
			vg.resize(incident[vi].size())
			for gi: int in groups.size():
				for fi: int in groups[gi]:
					vg[incident[vi].find(fi)] = gi
			group_of[vi] = vg

		## Averaged normal per (vertex, group).
		var group_normals: Array[Dictionary] = []   ## [vertex] -> {group: Vector3}
		group_normals.resize(verts.size())
		for vi: int in verts.size():
			var sums: Dictionary = {}
			for gi: int in incident[vi].size():
				var g: int = group_of[vi][gi]
				if not sums.has(g):
					sums[g] = Vector3.ZERO
				sums[g] += face_normals[incident[vi][gi]]
			var avg: Dictionary = {}
			for g: int in sums:
				var v: Vector3 = (sums[g] as Vector3).normalized()
				if v.length_squared() < 0.0001:
					v = Vector3.UP
				avg[g] = v
			group_normals[vi] = avg

		## Rebuild arrays, deduping corners that share a (vertex, normal) so flat
		## panels keep shared vertices instead of tripling the count.
		var new_verts := PackedVector3Array()
		var new_normals := PackedVector3Array()
		var new_indices := PackedInt32Array()
		var corner_map: Dictionary = {}
		for fi: int in faces.size():
			for k: int in 3:
				var vi: int = faces[fi][k]
				var gi: int = incident[vi].find(fi)
				var g: int = group_of[vi][gi]
				var n: Vector3 = group_normals[vi][g]
				var key: String = "%d|%s" % [vi, n]
				var new_idx: int = corner_map.get(key, -1)
				if new_idx < 0:
					new_idx = new_verts.size()
					corner_map[key] = new_idx
					new_verts.append(verts[vi])
					new_normals.append(n)
				new_indices.append(new_idx)

		var new_arrays: Array = []
		new_arrays.resize(Mesh.ARRAY_MAX)
		new_arrays[Mesh.ARRAY_VERTEX] = new_verts
		new_arrays[Mesh.ARRAY_NORMAL] = new_normals
		new_arrays[Mesh.ARRAY_INDEX] = new_indices
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		out.surface_set_material(s, src.surface_get_material(s))
	return out

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
