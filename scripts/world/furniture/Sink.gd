extends StaticBody3D
class_name Sink
## Sink.gd
## Decorative kitchen sink — no interaction. Furniture category, TILE 46, $75.
##
## Uses Kitchen_Sink from the Ultimate House Interior Pack (same pack as the
## Stove's Kitchen_Oven_Large and the Drawers, Blends/Kitchen_Sink.blend,
## exported to GLB). Shares the exact same scaling/footprint convention as
## the Drawers so it connects seamlessly in the same kitchen run: same
## non-uniform scale (X 0.7420 → 0.75 grid-multiple width, Y/Z 0.6935 →
## 0.7768 stove-flush depth), just taller natively (1.924 → 1.334 scaled —
## the sink unit has a taller backsplash/faucet). Materials (Kitchen / White
## / LightMetal / Glass / KitchenTop) are the same kitchen palette.

const MODEL_PATH:  String  = "res://assets/models/sink.glb"
const MODEL_SCALE: Vector3 = Vector3(0.7420, 0.6935, 0.6935)

## Scaled footprint (same as Drawers: width = 0.75 grid multiple; depth =
## stove's 0.7768, flush in a run) and height (taller than the drawers —
## 1.334 vs 1.119 — for the sink's backsplash/faucet) — used for the
## collision box and ghost.
const FOOTPRINT_X: float = 0.75
const FOOTPRINT_Z: float = 0.777
const MODEL_HEIGHT: float = 1.334

## Full-fidelity preview mode — same convention as every other furniture
## script. Sinks have nothing to register (no power, no groups), so this
## guard only keeps the pattern consistent with the codebase.
var _is_preview_only: bool = false

func _ready() -> void:
	_build_mesh()
	if _is_preview_only:
		return
	collision_layer = 5   ## Player + build-hover raycast
	collision_mask  = 0

func _build_mesh() -> void:
	var packed: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position = Vector3.ZERO
			model.scale    = MODEL_SCALE
			_recenter_glb_mesh(model)
			_strip_model_collision(model)
			add_child(model)
	else:
		push_warning("Sink.gd: model missing at %s — falling back to no visual mesh" % MODEL_PATH)

	## Invisible box collider matching the scaled sink footprint.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(FOOTPRINT_X, MODEL_HEIGHT, FOOTPRINT_Z)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, MODEL_HEIGHT * 0.5, 0.0)
	add_child(col_shape)

## Recursively disables collision on every CollisionObject3D descendant of an
## instanced model — same convention as every model swap in this codebase.
func _strip_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		_strip_model_collision(child)

## Godot's glTF importer wraps an imported scene in a generated root node —
## same helper as Table.gd/Stove.gd. Zeros the real MeshInstance3D's local
## position so the model's base sits at the root origin.
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(FOOTPRINT_X, MODEL_HEIGHT, FOOTPRINT_Z)
	return box