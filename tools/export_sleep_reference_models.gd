extends SceneTree
## tools/export_sleep_reference_models.gd
## Exports REFERENCE files for the bed remodel. Tinkercad only imports a
## SINGLE CLOSED (watertight) solid, so the real multi-piece bed/chair are
## rebuilt as box primitives and voxelized into one closed solid each (point-
## in-box is exact, so the boundary is always watertight).
##
## Dimensions (real, meters; export scale REF_SCALE, grounded at Y=0):
##   bed   : mattress 2.28 x 0.20 x 0.86 sitting 0.23..0.43 (TOP = 0.43m —
##           the remodel target) + headboard + footboard + 4 legs.
##   chair : seat TOP at 0.497m (SEAT_SURFACE_Y — the height the mattress
##           must match) + backboard to 1.12m + 4 legs, matching the real
##           chair's box structure (probed) and overall AABB.
##
## Output: OBJ + STL (+ textured GLBs for Blender).
## Run:  godot --headless --path <project> --script res://tools/export_sleep_reference_models.gd

const OUT_DIR: String = "res://assets/models/reference"
## Reference scale: Godot meters -> export units. 1000 = mm, 100 = cm
## (requested: models 10x smaller than the mm versions).
const REF_SCALE: float = 100.0
const BED_VOXEL: float = 2.0     ## voxel size in export units
const CHAIR_VOXEL: float = 2.5

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_export_bed()
	_export_chair()
	quit(0)

func _export_bed() -> void:
	var bed: Node3D = (load("res://scenes/world/Bed.tscn") as PackedScene).instantiate()
	root.add_child(bed)
	bed.position.y += 0.25   ## ground it (reference only)
	_save_glb(bed, "bed_reference")
	bed.free()
	var boxes: Array = [
		## mattress: 2.28 x 0.20 x 0.86, top at 0.43m
		[Vector3(-1.14, 0.23, -0.43), Vector3(1.14, 0.43, 0.43)],
		## headboard (-X end) and footboard (+X end)
		[Vector3(-1.18, 0.0, -0.43), Vector3(-1.14, 0.60, 0.43)],
		[Vector3(1.14, 0.0, -0.43), Vector3(1.18, 0.50, 0.43)],
		## 4 legs at the corners (44mm boxes), floor to mattress underside
		[Vector3(-1.152, 0.0, -0.422), Vector3(-1.108, 0.46, -0.378)],
		[Vector3(-1.152, 0.0, 0.378), Vector3(-1.108, 0.46, 0.422)],
		[Vector3(1.108, 0.0, -0.422), Vector3(1.152, 0.46, -0.378)],
		[Vector3(1.108, 0.0, 0.378), Vector3(1.152, 0.46, 0.422)],
	]
	_boxes_solid(boxes, BED_VOXEL, "bed_reference")

func _export_chair() -> void:
	## Replicate Chair.gd's runtime model setup (game scale + recenter).
	var model: Node3D = (load("res://assets/models/wooden_chair.glb") as PackedScene).instantiate()
	model.scale = Vector3(0.8946, 0.7102, 0.7667)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).position = Vector3.ZERO
	root.add_child(model)
	_save_glb(model, "chair_reference")
	model.free()
	var boxes: Array = [
		## seat slab: TOP at 0.497m (SEAT_SURFACE_Y)
		[Vector3(-0.28, 0.44, -0.24), Vector3(0.28, 0.497, 0.27)],
		## backboard: OVERLAPS the seat (Y 0.48..0.497, Z -0.24..-0.20) so the
		## two merge into one solid — no coincident faces, stays watertight
		[Vector3(-0.22, 0.48, -0.40), Vector3(0.22, 1.12, -0.20)],
		## 4 legs: OVERLAP the seat (Y up to 0.49 into it, X/Z into it) so they
		## merge with the seat; tops stay below the seat top (0.497)
		[Vector3(-0.31, 0.0, -0.30), Vector3(-0.25, 0.49, -0.18)],
		[Vector3(0.25, 0.0, -0.30), Vector3(0.31, 0.49, -0.18)],
		[Vector3(-0.31, 0.0, 0.18), Vector3(-0.25, 0.49, 0.30)],
		[Vector3(0.25, 0.0, 0.18), Vector3(0.31, 0.49, 0.30)],
	]
	_boxes_solid(boxes, CHAIR_VOXEL, "chair_reference")

func _save_glb(node: Node3D, base_name: String) -> void:
	var doc: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	doc.append_from_scene(node, state, 0)
	var path: String = OUT_DIR + "/" + base_name + ".glb"
	var err: Error = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	print("export ", base_name, ".glb  err=", err)

## Voxelizes a set of axis-aligned boxes (meters) into one closed solid.
func _boxes_solid(raw_boxes: Array, voxel: float, base_name: String) -> void:
	var boxes: Array = []
	for b: Array in raw_boxes:
		boxes.append([(b[0] as Vector3) * REF_SCALE, (b[1] as Vector3) * REF_SCALE])
	var minv := Vector3(INF, INF, INF)
	var maxv := Vector3(-INF, -INF, -INF)
	for b: Array in boxes:
		minv = minv.min(b[0]); maxv = maxv.max(b[1])
	minv -= Vector3.ONE * voxel
	maxv += Vector3.ONE * voxel
	var in_fn := func(p: Vector3) -> bool:
		for b: Array in boxes:
			if p.x >= b[0].x and p.x <= b[1].x \
					and p.y >= b[0].y and p.y <= b[1].y \
					and p.z >= b[0].z and p.z <= b[1].z:
				return true
		return false
	var tris: Array = _voxel_boundary(minv, maxv, voxel, in_fn)
	_write_solids(tris, base_name)

## Marks voxels inside via in_fn, emits the boundary between in/out voxels.
## The boundary of any in/out voxel field is always closed (watertight).
func _voxel_boundary(minv: Vector3, maxv: Vector3, res: float, in_fn: Callable) -> Array:
	var nx: int = int(ceil((maxv.x - minv.x) / res))
	var ny: int = int(ceil((maxv.y - minv.y) / res))
	var nz: int = int(ceil((maxv.z - minv.z) / res))
	var solid: Dictionary = {}
	var key := func(x: int, y: int, z: int) -> String: return str(x) + "," + str(y) + "," + str(z)
	for x in nx:
		for y in ny:
			for z in nz:
				var p := minv + Vector3((x + 0.5) * res, (y + 0.5) * res, (z + 0.5) * res)
				if in_fn.call(p):
					solid[key.call(x, y, z)] = true

	var out: Array = []
	var c := func(x: int, y: int, z: int) -> Vector3:
		return minv + Vector3(x * res, y * res, z * res)
	var in_b := func(x: int, y: int, z: int) -> bool:
		if x < 0 or y < 0 or z < 0 or x >= nx or y >= ny or z >= nz:
			return false
		return solid.has(key.call(x, y, z))
	for x in nx:
		for y in ny:
			for z in nz:
				if not in_b.call(x, y, z):
					continue
				var a: Vector3 = c.call(x, y, z)
				var b2: Vector3 = c.call(x + 1, y + 1, z + 1)
				if not in_b.call(x - 1, y, z):
					out.append([a + Vector3(0, 0, 0), a + Vector3(0, 0, res), a + Vector3(0, res, 0)])
					out.append([a + Vector3(0, res, 0), a + Vector3(0, 0, res), a + Vector3(0, res, res)])
				if not in_b.call(x + 1, y, z):
					out.append([b2 + Vector3(0, -res, -res), b2 + Vector3(0, -res, 0), b2 + Vector3(0, 0, -res)])
					out.append([b2 + Vector3(0, 0, -res), b2 + Vector3(0, -res, 0), b2 + Vector3(0, 0, 0)])
				if not in_b.call(x, y - 1, z):
					out.append([a + Vector3(0, 0, 0), a + Vector3(res, 0, 0), a + Vector3(0, 0, res)])
					out.append([a + Vector3(0, 0, res), a + Vector3(res, 0, 0), a + Vector3(res, 0, res)])
				if not in_b.call(x, y + 1, z):
					out.append([b2 + Vector3(-res, 0, -res), b2 + Vector3(-res, 0, 0), b2 + Vector3(0, 0, -res)])
					out.append([b2 + Vector3(0, 0, -res), b2 + Vector3(-res, 0, 0), b2 + Vector3(0, 0, 0)])
				if not in_b.call(x, y, z - 1):
					out.append([a + Vector3(0, 0, 0), a + Vector3(res, 0, 0), a + Vector3(0, res, 0)])
					out.append([a + Vector3(0, res, 0), a + Vector3(res, 0, 0), a + Vector3(res, res, 0)])
				if not in_b.call(x, y, z + 1):
					out.append([b2 + Vector3(-res, -res, 0), b2 + Vector3(-res, 0, 0), b2 + Vector3(0, -res, 0)])
					out.append([b2 + Vector3(0, -res, 0), b2 + Vector3(-res, 0, 0), b2 + Vector3(0, 0, 0)])
	return out

# ─── File writers (OBJ + STL) ────────────────────────────────────────────────
func _write_solids(tris: Array, base_name: String) -> void:
	_write_obj_solid(tris, base_name + ".obj")
	_write_stl(tris, base_name + ".stl")

func _write_obj_solid(tris: Array, file_name: String) -> void:
	var v := {}
	for t: Array in tris:
		for p: Vector3 in t:
			v[p] = true
	var vlist: Array = v.keys()
	var index := {}
	for i in vlist.size():
		index[vlist[i]] = i + 1
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/" + file_name), FileAccess.WRITE)
	f.store_line("# Tinkercad-ready single solid (REF_SCALE, grounded at Y=0)")
	for p: Vector3 in vlist:
		f.store_line("v %.3f %.3f %.3f" % [p.x, p.y, p.z])
	for t: Array in tris:
		f.store_line("f %d %d %d" % [index[t[0]], index[t[1]], index[t[2]]])
	f.close()
	print("export ", file_name, "  verts=", vlist.size(), " tris=", tris.size())

func _write_stl(tris: Array, file_name: String) -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/" + file_name), FileAccess.WRITE)
	f.store_line("solid reference")
	for t: Array in tris:
		var a: Vector3 = t[0]; var b: Vector3 = t[1]; var c: Vector3 = t[2]
		var n: Vector3 = (b - a).cross(c - a).normalized()
		f.store_line("facet normal %.4f %.4f %.4f" % [n.x, n.y, n.z])
		f.store_line("  outer loop")
		f.store_line("    vertex %.3f %.3f %.3f" % [a.x, a.y, a.z])
		f.store_line("    vertex %.3f %.3f %.3f" % [b.x, b.y, b.z])
		f.store_line("    vertex %.3f %.3f %.3f" % [c.x, c.y, c.z])
		f.store_line("  endloop")
		f.store_line("endfacet")
	f.store_line("endsolid reference")
	f.close()
	print("export ", file_name, "  tris=", tris.size())