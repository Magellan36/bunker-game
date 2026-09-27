extends LightStorage
class_name EndTable
## EndTable.gd
## Small 1×1 side table with a hidden drawer — light-item storage, capacity 2.
## Furniture category, TILE 32, $60.
##
## Sep 2026 — visual model swapped to `NightStand_2` from the Ultimate House
## Interior Pack (Blends/NightStand_2.blend, exported to GLB). The previous
## procedural leg+tabletop+cabinet+drawer mesh was removed. Collision is now a
## single invisible box matching the scaled model footprint, decoupled from the
## visual (model's own imported collision is stripped).

## The model's native footprint is 0.952×0.952 — scaled uniformly to the
## existing 0.90×0.90 occupancy footprint (matches Table small and the
## _tile_half_extents fallback of 0.45). Native height 0.945 × 0.9451 = 0.893.
## The drawer knob is authored on the model's +Z side, which IS the EndTable's
## front (verified in-editor Sep 2026 — the knob faces the player/arrow), so
## no rotation is applied.
const MODEL_PATH: String = "res://assets/models/nightstand2.glb"
const MODEL_SCALE: float  = 0.9451
const MODEL_ROT_Y_DEG: float = 0.0

const LEG_HEIGHT: float          = 0.72   ## Historical (procedural mesh removed) — kept for ghost height reference
const TABLETOP_THICKNESS: float  = 0.05
const TABLETOP_Y: float          = LEG_HEIGHT + TABLETOP_THICKNESS * 0.5
const FOOTPRINT: Vector2         = Vector2(0.90, 0.90)
const CABINET_SIZE: Vector3      = Vector3(0.70, 0.40, 0.70)
const CABINET_Y: float           = 0.50

func _init() -> void:
	capacity      = 2
	display_name  = "End Table"
	prompt_height = 1.2
	grid_cols     = 2
	grid_rows     = 1

func _build_mesh() -> void:
	## Hand-made OBJ/GLB swap convention (Sep 2026) — load the real model,
	## scale + rotate it into place, strip its own collision, and add a single
	## invisible box collider matching the footprint. Same shape as the Chair
	## swap.
	var packed: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position = Vector3.ZERO
			model.scale    = Vector3.ONE * MODEL_SCALE
			model.rotation_degrees = Vector3(0.0, MODEL_ROT_Y_DEG, 0.0)
			_strip_model_collision(model)
			add_child(model)
	else:
		push_warning("EndTable.gd: nightstand2.glb missing at %s — falling back to no visual mesh" % MODEL_PATH)

	## Invisible collision box matching the scaled model footprint — the model
	## is detailed, so a trimesh would be wasteful; the DetectArea/StorageUI
	## only need a shape on the root.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(FOOTPRINT.x * MODEL_SCALE, 0.893, FOOTPRINT.y * MODEL_SCALE)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, 0.893 * 0.5, 0.0)
	add_child(col_shape)

## Recursively disables collision on every CollisionObject3D descendant of an
## instanced model — same convention as Chair.gd/Table.gd/BuildStation.gd.
func _strip_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		_strip_model_collision(child)

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(FOOTPRINT.x, 0.893, FOOTPRINT.y)
	return box
