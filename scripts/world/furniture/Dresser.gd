extends LightStorage
class_name Dresser
## Dresser.gd
## Tall 2×1 dresser with 6 hidden drawers — light-item storage, capacity 6.
## Furniture category, TILE 33, $150.
##
## Sep 2026 — visual model swapped to `Drawer_5` from the Ultimate House
## Interior Pack (Blends/Drawer_5.blend, exported to GLB). The previous
## procedural body+top+2×3-drawer mesh was removed. Collision is now a single
## invisible box matching the scaled model footprint, decoupled from the
## visual (model's own imported collision is stripped).

## The model's native width is 2.794 — scaled UNIFORMLY by 0.68 so the width
## lands EXACTLY on the current Dresser width (1.90, matching the occupancy
## footprint / _tile_half_extents fallback of 0.95). No scrunching: height and
## depth follow the model's natural proportions (scaled 0.906 × 0.784, both
## within the 1.90×0.96 occupancy box). The drawer fronts/knobs are authored
## on the model's +Z side, same as the old procedural Dresser, so no rotation.
const MODEL_PATH: String = "res://assets/models/drawer5.glb"
const MODEL_SCALE: float  = 0.68
const MODEL_ROT_Y_DEG: float = 0.0

## Scaled model dims — used for the collision box and ghost.
const SCALED_W: float = 1.90
const SCALED_H: float = 0.906
const SCALED_D: float = 0.784

func _init() -> void:
	capacity      = 6
	display_name  = "Dresser"
	prompt_height = 0.8
	grid_cols     = 2
	grid_rows     = 3

func _build_mesh() -> void:
	## Hand-made OBJ/GLB swap convention (Sep 2026) — load the real model,
	## scale + rotate it into place, strip its own collision, and add a single
	## invisible box collider matching the footprint. Same shape as the
	## Chair / EndTable swaps.
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
		push_warning("Dresser.gd: drawer5.glb missing at %s — falling back to no visual mesh" % MODEL_PATH)

	## Invisible collision box matching the scaled model footprint.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(SCALED_W, SCALED_H, SCALED_D)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, SCALED_H * 0.5, 0.0)
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
	box.size = Vector3(SCALED_W, SCALED_H, SCALED_D)
	return box
