extends StaticBody3D
class_name Table
## Table.gd
## Basic 4-legged table, wood (Wood006 retexture, Aug 2026). Two sizes via
## cell_count (1 = small 1×1, 2 = medium 2×1) — same footprint numbers as
## FarmingTray (0.90×0.90 / 1.90×0.90) so it reads as visually consistent
## furniture at the same scale. Not interactable yet — pure static decoration/
## placement object for now.

const LEG_HEIGHT: float        = 0.72   ## Matches FarmingTray.LEG_HEIGHT
const TABLETOP_THICKNESS: float = 0.05
const TABLETOP_Y: float        = LEG_HEIGHT + TABLETOP_THICKNESS * 0.5

const MEDIUM_TABLE_MODEL_PATH: String = "res://assets/models/wooden_table.glb"
const MEDIUM_TABLE_MODEL_SCALE: Vector3 = Vector3(0.6333, 0.5946, 0.4638)

@export var cell_count: int = 1   ## 1 = small table, 2 = medium table

## Full-fidelity preview mode (see Bed.gd / Shelving.gd for the full
## convention writeup) — set TRUE by BuildModeHUD's construct-tab preview
## code BEFORE add_child(). Skips group membership only (this object has no
## PowerManager/WaterManager registration to skip, but the guard is kept for
## consistency with every other furniture/device script in this codebase).
var _is_preview_only: bool = false

func _ready() -> void:
	cell_count = clampi(cell_count, 1, 2)
	if not _is_preview_only:
		add_to_group("interactable_static")  ## reserved for future use (see Part 4 note); NOT added to "interactable" — table has no on_interact() yet
	collision_layer = 5   ## Matches wall/pillar/shelving/tray convention
	collision_mask  = 0
	_build_mesh()

func _footprint() -> Vector2:
	var x: float = 0.90 if cell_count == 1 else 1.90
	return Vector2(x, 0.90)

func _build_mesh() -> void:
	var fp: Vector2 = _footprint()
	var footprint_x: float = fp.x
	var footprint_z: float = fp.y

	if cell_count == 2:
		_build_mesh_from_model(footprint_x, footprint_z)
		return

	var mat: StandardMaterial3D = BuildMaterials.build_wood_material()

	## 4 legs at the footprint's corners — identical geometry/positions to
	## FarmingTray._build_mesh()'s leg loop.
	var leg_positions: Array[Vector2] = [
		Vector2(-footprint_x * 0.5 + 0.05, -footprint_z * 0.5 + 0.05),
		Vector2( footprint_x * 0.5 - 0.05, -footprint_z * 0.5 + 0.05),
		Vector2(-footprint_x * 0.5 + 0.05,  footprint_z * 0.5 - 0.05),
		Vector2( footprint_x * 0.5 - 0.05,  footprint_z * 0.5 - 0.05),
	]
	for p: Vector2 in leg_positions:
		var leg_mi: MeshInstance3D = MeshInstance3D.new()
		var leg_mesh: CylinderMesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.03
		leg_mesh.bottom_radius = 0.03
		leg_mesh.height = LEG_HEIGHT
		leg_mesh.radial_segments = 8
		leg_mi.mesh = leg_mesh
		leg_mi.position = Vector3(p.x, LEG_HEIGHT * 0.5, p.y)
		leg_mi.set_surface_override_material(0, mat)
		add_child(leg_mi)

	## Flat tabletop slab (this replaces FarmingTray's open basin+walls).
	var top_mi:   MeshInstance3D = MeshInstance3D.new()
	var top_mesh: BoxMesh        = BoxMesh.new()
	top_mesh.size = Vector3(footprint_x, TABLETOP_THICKNESS, footprint_z)
	top_mi.mesh   = top_mesh
	top_mi.position = Vector3(0.0, TABLETOP_Y, 0.0)
	top_mi.set_surface_override_material(0, mat)
	add_child(top_mi)
	top_mi.create_trimesh_collision()
	for child in top_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

## Medium (2×1) table only — loads the real wooden_table.glb model instead
## of the procedural leg+top mesh. Collision is a separate, invisible
## BoxShape3D matching the tabletop's exact footprint/position (same
## dimensions the procedural top_mi.create_trimesh_collision() produced),
## attached directly to this StaticBody3D — decoupled from the visual mesh
## since the GLB's own collision is stripped (ghost/preview convention:
## never trust an imported model's collision, see GhostModelBuilder.gd's
## strip_collision() for the parallel case in ghost previews).
func _build_mesh_from_model(footprint_x: float, footprint_z: float) -> void:
	var packed: PackedScene = load(MEDIUM_TABLE_MODEL_PATH) if ResourceLoader.exists(MEDIUM_TABLE_MODEL_PATH) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			## MUST explicitly zero position — the source file's single node
			## has a baked (-1.7, 0, 0.7) scene-placement offset that is NOT
			## part of the mesh's own shape. Trusting the imported transform
			## would render the table badly off-center. See plan header.
			model.position = Vector3.ZERO
			model.scale    = MEDIUM_TABLE_MODEL_SCALE
			_recenter_glb_mesh(model)
			_strip_model_collision(model)
			BuildMaterials.apply_material_to_model(model, BuildMaterials.build_wood_material())
			add_child(model)
	else:
		push_warning("Table.gd: wooden_table.glb missing at %s — falling back to no visual mesh for the 2x1 table" % MEDIUM_TABLE_MODEL_PATH)

	## Invisible collision box, exact same dimensions/position as the
	## procedural tabletop's collision used to be.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(footprint_x, TABLETOP_THICKNESS, footprint_z)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, TABLETOP_Y, 0.0)
	add_child(col_shape)

## Recursively disables collision on every CollisionObject3D descendant of
## an instanced model — same responsibility as
## GhostModelBuilder.strip_collision(), duplicated here (not called) since
## this is a REAL placed object, not a ghost, and GhostModelBuilder is
## build-mode-preview-scoped. If a second real (non-ghost) model-loading
## site needs this same helper, promote it to a shared static utility
## rather than a third copy.
func _strip_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		_strip_model_collision(child)

## Godot's glTF importer always wraps an imported scene in an extra
## generated root node (representing the file's "Scene"), with the file's
## real node(s) nested one level below it as children — the top-level
## model.position reset alone does NOT reach a translation baked onto an
## inner node. Recursively finds the first MeshInstance3D descendant and
## zeros ITS local position. Safe specifically because wooden_table.glb's
## vertex data is already centered on that node's own local origin (see
## PLAN_table01_glb_swap.md's accessor min/max analysis) — this only
## eliminates a stray node-level offset, it doesn't recompute a new
## center, so it would NOT be safe to reuse blindly on a future multi-part
## model where sub-mesh offsets are intentional.
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false

static func build_ghost_mesh(cell_count: int = 1) -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	var x: float = 0.90 if cell_count == 1 else 1.90
	box.size = Vector3(x, TABLETOP_Y + TABLETOP_THICKNESS * 0.5, 0.90)
	return box
