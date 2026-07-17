extends Node3D
## RockSurround.gd
## Spawns a ring of underground rock chunks around the bunker perimeter.
##
## OPTIMIZED: Each 4×4 chunk = ONE StaticBody3D with one box collision shape.
## All rock visuals rendered via a single MultiMeshInstance3D.
##
## Node count before: ~5760 StaticBody3D. After: ~360 + 1 MultiMesh.

# ─── Config ───────────────────────────────────────────────────────────────────
@export var bunker_width: int  = 8
@export var bunker_depth: int  = 16
@export var dig_margin:   int  = 32
@export var chunk_size:   int  = 4

const DIG_COST: int = 15000

const ROCK_COLOR:  Color = Color(0.28, 0.24, 0.20, 1.0)
const ROCK_COLOR2: Color = Color(0.22, 0.19, 0.16, 1.0)

const BLOCK_HEIGHT: float = 2.25
const BLOCK_Y:      float = 2.5

const OFFSET_X: float = -12.5
const OFFSET_Z: float =  4.5

const ROCK_COLLISION_LAYER: int = 16

signal chunk_deconstructed(chunk_origin: Vector2i)
signal chunk_restored(chunk_origin: Vector2i)

# ─── Internal state ───────────────────────────────────────────────────────────
## Key: Vector2i(chunk_col, chunk_row)
## Value: { body: StaticBody3D, deconstructed: bool, center: Vector3,
##          mm_indices: Array,  mm_positions: Array[Vector3] }
## mm_positions is kept permanently so restore_chunk() can rebuild visuals.
var _chunks: Dictionary = {}

var _mmi: MultiMeshInstance3D = null

## Two materials — alternate per instance to break monotony (same as old code)
var _mat_a: StandardMaterial3D = null
var _mat_b: StandardMaterial3D = null

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_materials()
	_stamp_rock()

func _build_materials() -> void:
	## Load rock texture (pre-darkened by 1.75x via ImageMagick at export time).
	## Additional albedo_color tint of 0.70 brings total darkening to ~2.45x (≈2.5x).
	##
	## Two-frequency tiling strategy (same as BuildModeController walls/floor):
	##   UV1 base: coarse scale, 1 tile per ~10m
	##   UV2 detail: fine scale at 5x higher frequency for rock grain
	##   Mat A and Mat B use slightly different UV scales so alternating instances
	##   never align their seams — completely breaks the repeat grid pattern.
	var tex: Texture2D = load("res://assets/textures/rocks_ground_dark.jpg") as Texture2D
	const ROCK_DARK: float = 0.70   ## 1.75 * (1/0.70) ≈ 2.5x total vs original

	_mat_a = StandardMaterial3D.new()
	_mat_a.roughness               = 0.96
	_mat_a.metallic                = 0.0
	_mat_a.uv1_triplanar           = true
	_mat_a.uv1_triplanar_sharpness = 2.5
	_mat_a.uv1_scale               = Vector3(0.10, 0.10, 0.10)
	_mat_a.detail_enabled          = true
	_mat_a.detail_blend_mode       = BaseMaterial3D.BLEND_MODE_MIX
	_mat_a.detail_uv_layer         = BaseMaterial3D.DETAIL_UV_2
	_mat_a.uv2_triplanar           = true
	_mat_a.uv2_triplanar_sharpness = 2.5
	_mat_a.uv2_scale               = Vector3(0.55, 0.55, 0.55)
	if tex != null:
		_mat_a.albedo_texture      = tex
		_mat_a.albedo_color        = Color(ROCK_DARK, ROCK_DARK, ROCK_DARK, 1.0)
		_mat_a.detail_albedo       = tex
	else:
		_mat_a.albedo_color        = ROCK_COLOR

	_mat_b = StandardMaterial3D.new()
	_mat_b.roughness               = 0.94
	_mat_b.metallic                = 0.0
	_mat_b.uv1_triplanar           = true
	_mat_b.uv1_triplanar_sharpness = 2.5
	## Different base scale from mat_a — alternating instances never align seams
	_mat_b.uv1_scale               = Vector3(0.083, 0.083, 0.083)
	_mat_b.detail_enabled          = true
	_mat_b.detail_blend_mode       = BaseMaterial3D.BLEND_MODE_MIX
	_mat_b.detail_uv_layer         = BaseMaterial3D.DETAIL_UV_2
	_mat_b.uv2_triplanar           = true
	_mat_b.uv2_triplanar_sharpness = 2.5
	_mat_b.uv2_scale               = Vector3(0.47, 0.47, 0.47)
	if tex != null:
		_mat_b.albedo_texture      = tex
		## Slight warm tint variation so the two materials read differently up close
		_mat_b.albedo_color        = Color(ROCK_DARK * 0.93, ROCK_DARK * 0.90, ROCK_DARK * 0.87, 1.0)
		_mat_b.detail_albedo       = tex
	else:
		_mat_b.albedo_color        = ROCK_COLOR2

# ─── Stamp ────────────────────────────────────────────────────────────────────
func _stamp_rock() -> void:
	var x_min: int = _floor_to_chunk(-dig_margin)
	var x_max: int = bunker_depth + dig_margin - 1
	var z_min: int = _floor_to_chunk(-dig_margin)
	var z_max: int = bunker_width + dig_margin - 1

	## ── Pass 1: collect ALL rock cell positions for the MultiMesh ─────────────
	var all_positions:   Array = []   ## Array of Vector3
	var all_use_alt:     Array = []   ## Array of bool (alternating material)
	var cell_chunk_ids:  Array = []   ## Array of Vector2i (parallel to positions)

	var cx: int = x_min
	while cx <= x_max:
		var cz: int = z_min
		while cz <= z_max:
			var chunk_id: Vector2i = _make_chunk_id(cx, cz)

			## Pre-register chunk in dictionary (body filled in pass 2)
			if not _chunks.has(chunk_id):
				var center: Vector3 = Vector3(
					float(cx) + float(chunk_size) * 0.5 + OFFSET_X,
					BLOCK_Y,
					float(cz) + float(chunk_size) * 0.5 + OFFSET_Z
				)
				_chunks[chunk_id] = {
					"body":          null,
					"deconstructed": false,
					"center":        center,
					"mm_indices":    [],
					"mm_positions":  [],   ## Permanent record for restore_chunk()
				}

			for dx: int in range(chunk_size):
				for dz: int in range(chunk_size):
					var cell_x: int = cx + dx
					var cell_z: int = cz + dz
					## Skip interior bunker cells (depth along X, width along Z)
					if cell_x >= 0 and cell_x < bunker_depth \
							and cell_z >= 0 and cell_z < bunker_width:
						continue
					var world_x: float = float(cell_x) + 0.5 + OFFSET_X
					var world_z: float = float(cell_z) + 0.5 + OFFSET_Z
					var idx: int = all_positions.size()
					var pos: Vector3 = Vector3(world_x, BLOCK_Y, world_z)
					all_positions.append(pos)
					all_use_alt.append((dx + dz) % 2 == 0)
					cell_chunk_ids.append(chunk_id)
					_chunks[chunk_id]["mm_indices"].append(idx)
					_chunks[chunk_id]["mm_positions"].append(pos)  ## Permanent copy

			cz += chunk_size
		cx += chunk_size

	## ── Pass 2: build MultiMesh from collected positions ─────────────────────
	_build_multimesh(all_positions, all_use_alt)

	## ── Pass 3: one StaticBody3D per chunk ───────────────────────────────────
	for chunk_id: Vector2i in _chunks:
		_build_chunk_body(chunk_id)

func _floor_to_chunk(v: int) -> int:
	return int(floor(float(v) / float(chunk_size))) * chunk_size

func _make_chunk_id(chunk_x: int, chunk_z: int) -> Vector2i:
	return Vector2i(
		int(floor(float(chunk_x) / float(chunk_size))),
		int(floor(float(chunk_z) / float(chunk_size)))
	)

func _chunk_fully_inside_bunker(chunk_x: int, chunk_z: int) -> bool:
	for dx: int in range(chunk_size):
		for dz: int in range(chunk_size):
			var cell_x: int = chunk_x + dx
			var cell_z: int = chunk_z + dz
			if cell_x < 0 or cell_x >= bunker_depth \
					or cell_z < 0 or cell_z >= bunker_width:
				return false
	return true

# ─── MultiMesh builder ────────────────────────────────────────────────────────
func _build_multimesh(positions: Array, use_alt: Array) -> void:
	var count: int = positions.size()
	if count == 0:
		return

	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.0, BLOCK_HEIGHT, 1.0)
	box.surface_set_material(0, _mat_a)

	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors       = false
	mm.instance_count   = count
	mm.mesh             = box

	for i: int in range(count):
		mm.set_instance_transform(i, Transform3D(Basis(), positions[i]))

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh  = mm
	_mmi.top_level  = true
	add_child(_mmi)

# ─── Per-chunk physics body ───────────────────────────────────────────────────
func _build_chunk_body(chunk_id: Vector2i) -> void:
	var chunk_x: int = chunk_id.x * chunk_size
	var chunk_z: int = chunk_id.y * chunk_size

	var min_wx: float =  INF
	var min_wz: float =  INF
	var max_wx: float = -INF
	var max_wz: float = -INF

	for dx: int in range(chunk_size):
		for dz: int in range(chunk_size):
			var cell_x: int = chunk_x + dx
			var cell_z: int = chunk_z + dz
			if cell_x >= 0 and cell_x < bunker_depth \
					and cell_z >= 0 and cell_z < bunker_width:
				continue
			var wx: float = float(cell_x) + 0.5 + OFFSET_X
			var wz: float = float(cell_z) + 0.5 + OFFSET_Z
			min_wx = min(min_wx, wx - 0.5)
			max_wx = max(max_wx, wx + 0.5)
			min_wz = min(min_wz, wz - 0.5)
			max_wz = max(max_wz, wz + 0.5)

	if min_wx == INF:
		return

	var box_w: float    = max_wx - min_wx
	var box_d: float    = max_wz - min_wz
	var center_x: float = (min_wx + max_wx) * 0.5
	var center_z: float = (min_wz + max_wz) * 0.5

	var body: StaticBody3D    = StaticBody3D.new()
	body.collision_layer      = ROCK_COLLISION_LAYER
	body.collision_mask       = 0

	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D     = BoxShape3D.new()
	shape.size                = Vector3(box_w, BLOCK_HEIGHT, box_d)
	col.shape                 = shape
	body.add_child(col)

	add_child(body)
	body.global_position = Vector3(center_x, BLOCK_Y, center_z)

	_chunks[chunk_id]["body"] = body

# ─── Public API ───────────────────────────────────────────────────────────────

func get_chunk_at_world_pos(world_pos: Vector3) -> Vector2i:
	var local_x: float = world_pos.x - OFFSET_X
	var local_z: float = world_pos.z - OFFSET_Z
	var cell_x: int    = int(floor(local_x))
	var cell_z: int    = int(floor(local_z))
	var chunk_id: Vector2i = Vector2i(
		int(floor(float(cell_x) / float(chunk_size))),
		int(floor(float(cell_z) / float(chunk_size)))
	)
	if _chunks.has(chunk_id):
		return chunk_id
	return Vector2i(-9999, -9999)

func is_chunk_active(chunk_id: Vector2i) -> bool:
	if not _chunks.has(chunk_id):
		return false
	return not _chunks[chunk_id]["deconstructed"]

func get_chunk_center(chunk_id: Vector2i) -> Vector3:
	if not _chunks.has(chunk_id):
		return Vector3(-9999.0, -9999.0, -9999.0)
	return _chunks[chunk_id]["center"]

func deconstruct_chunk(chunk_id: Vector2i) -> void:
	if not _chunks.has(chunk_id):
		return
	var entry: Dictionary = _chunks[chunk_id]
	if entry["deconstructed"]:
		return

	## Hide visual cells by zeroing their transform scale
	if _mmi != null and _mmi.multimesh != null:
		for idx: int in entry["mm_indices"]:
			_mmi.multimesh.set_instance_transform(
				idx, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))

	## Free physics body
	if entry["body"] != null and is_instance_valid(entry["body"]):
		entry["body"].queue_free()

	entry["deconstructed"] = true
	entry["body"]          = null
	## mm_indices is intentionally KEPT so restore_chunk() can use the exact
	## original indices without scanning. DO NOT clear it here.

	var origin: Vector2i = Vector2i(
		chunk_id.x * chunk_size,
		chunk_id.y * chunk_size
	)
	chunk_deconstructed.emit(origin)

## Restore a previously deconstructed chunk — called by BuildModeController undo.
## Re-shows the visual cells and re-creates the physics body.
func restore_chunk(chunk_id: Vector2i) -> void:
	if not _chunks.has(chunk_id):
		return
	var entry: Dictionary = _chunks[chunk_id]
	if not entry["deconstructed"]:
		return   ## Already active — nothing to do

	## Restore MultiMesh visuals using the original indices from build time.
	## mm_indices[i] ↔ mm_positions[i] — a permanent 1:1 mapping set in
	## _stamp_rock() and never modified. We just re-stamp the transforms
	## at their original positions.
	if _mmi != null and _mmi.multimesh != null:
		var mm: MultiMesh = _mmi.multimesh
		var indices: Array  = entry["mm_indices"]
		var positions: Array = entry["mm_positions"]
		for i: int in range(indices.size()):
			mm.set_instance_transform(indices[i], Transform3D(Basis(), positions[i]))

	## Re-create physics body
	_build_chunk_body(chunk_id)
	entry["deconstructed"] = false

	## Notify listeners (MainWorld) so they can tear down auto-fill walls/pillars
	## that sat on now-restored rock cells and re-solve the perimeter.
	var origin: Vector2i = Vector2i(
		chunk_id.x * chunk_size,
		chunk_id.y * chunk_size
	)
	chunk_restored.emit(origin)


# ─── Save/Load (Jul 2026) ──────────────────────────────────────────────────────
## Returns every currently-dug chunk id as plain {x,z} dicts (JSON-friendly —
## Vector2i isn't natively serializable). Registered as SaveManager's phase-0
## field so dug chunks exist before anything else on load tries to build on
## top of them (placed objects, wires, pipes).
func get_dug_chunk_ids_for_save() -> Array:
	var ids: Array = []
	for chunk_id: Vector2i in _chunks:
		if _chunks[chunk_id]["deconstructed"]:
			ids.append({"x": chunk_id.x, "z": chunk_id.y})
	return ids

## Reconstructs dug-chunk state from get_dug_chunk_ids_for_save()'s output.
## Handles BOTH a fresh boot (no chunks dug yet) and a mid-session Load
## (some chunks already dug from the current playthrough) by first restoring
## every currently-dug chunk back to intact rock, then re-digging exactly the
## saved set. Reuses restore_chunk()/deconstruct_chunk() as-is — no new
## teardown logic — so the existing chunk_deconstructed/chunk_restored
## signals fire normally and WireGraphBuilder/WaterManager's incremental
## perimeter rebuild reacts exactly as it would to manual digging.
func restore_dug_chunks(ids: Array) -> void:
	for chunk_id: Vector2i in _chunks.keys():
		if _chunks[chunk_id]["deconstructed"]:
			restore_chunk(chunk_id)
	for entry: Dictionary in ids:
		var cid: Vector2i = Vector2i(int(entry.get("x", 0)), int(entry.get("z", 0)))
		if _chunks.has(cid):
			deconstruct_chunk(cid)
