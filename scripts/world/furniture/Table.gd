extends StaticBody3D
class_name Table
## Table.gd
## Two sizes via cell_count (1 = small 1×1, 2 = medium 2×1) — same footprint
## numbers as FarmingTray (0.90×0.90 / 1.90×0.90) so it reads as visually
## consistent furniture at the same scale. Both sizes now load human-built GLB
## models (small → folding stool, medium → wooden_table.glb) with the shared
## Wood006 wood material applied. Not interactable yet — pure static decoration/
## placement object for now.

const LEG_HEIGHT: float        = 0.72   ## Matches FarmingTray.LEG_HEIGHT
const TABLETOP_THICKNESS: float = 0.05
const TABLETOP_Y: float        = LEG_HEIGHT + TABLETOP_THICKNESS * 0.5

const MEDIUM_TABLE_MODEL_PATH: String = "res://assets/models/wooden_table.glb"
const MEDIUM_TABLE_MODEL_SCALE: Vector3 = Vector3(0.6333, 0.5946, 0.4638)

## Small (1×1) table — human-built folding stool model (Sep 2026), replacing the
## old procedural legs+tabletop mesh. The GLB is pre-scaled at export to the
## exact small-table footprint (0.90 × 0.77 × 0.90, base at y=0), so scale is
## Vector3.ONE — see _build_mesh_from_model().
const SMALL_TABLE_MODEL_PATH: String = "res://assets/models/small_table.glb"
const SMALL_TABLE_MODEL_SCALE: Vector3 = Vector3.ONE

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
		_build_mesh_from_model(MEDIUM_TABLE_MODEL_PATH, MEDIUM_TABLE_MODEL_SCALE, footprint_x, footprint_z)
		return

	_build_mesh_from_model(SMALL_TABLE_MODEL_PATH, SMALL_TABLE_MODEL_SCALE, footprint_x, footprint_z)

## Loads a model GLB for a table size (medium → wooden_table.glb, small →
## small_table.glb) and applies the shared wood material. Collision is a
## separate, invisible BoxShape3D matching the tabletop's exact footprint/
## position (same dimensions the old procedural top_mi.create_trimesh_collision()
## produced), attached directly to this StaticBody3D — decoupled from the visual
## mesh since the GLB's own collision is stripped (ghost/preview convention:
## never trust an imported model's collision, see GhostModelBuilder.gd's
## strip_collision() for the parallel case in ghost previews).
func _build_mesh_from_model(model_path: String, model_scale: Vector3, footprint_x: float, footprint_z: float) -> void:
	var packed: PackedScene = load(model_path) if ResourceLoader.exists(model_path) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			## MUST explicitly zero position — the source file's single node
			## has a baked (-1.7, 0, 0.7) scene-placement offset that is NOT
			## part of the mesh's own shape. Trusting the imported transform
			## would render the table badly off-center. See plan header.
			model.position = Vector3.ZERO
			model.scale    = model_scale
			BuildMaterials.recenter_glb_mesh(model)
			BuildMaterials.strip_model_collision(model)
			BuildMaterials.apply_material_to_model(model, BuildMaterials.build_wood_material())
			add_child(model)
	else:
		push_warning("Table.gd: model missing at %s — falling back to no visual mesh" % model_path)

	## Invisible collision box, exact same dimensions/position as the
	## procedural tabletop's collision used to be.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(footprint_x, TABLETOP_THICKNESS, footprint_z)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, TABLETOP_Y, 0.0)
	add_child(col_shape)

static func build_ghost_mesh(cell_count: int = 1) -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	var x: float = 0.90 if cell_count == 1 else 1.90
	box.size = Vector3(x, TABLETOP_Y + TABLETOP_THICKNESS * 0.5, 0.90)
	return box
