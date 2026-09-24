extends StaticBody3D
class_name Drawers
## Drawers.gd
## Decorative kitchen drawer units — no interaction. Furniture category,
## TILE 43/44/45, $75 each.
##
## Uses Kitchen_1Drawers / Kitchen_2Drawers / Kitchen_3Drawers from the
## Ultimate House Interior Pack (same pack as the Stove's Kitchen_Oven_Large,
## Blends/Kitchen_*Drawers.blend, exported to GLB). One script, three variants
## via the `variant` export (1/2/3) — mirrors the Carpet tier-export
## convention. Materials (Kitchen / White / KitchenTop) are from the same
## kitchen palette as the stove, so they read cohesively placed next to it.
##
## Scaling is shared by every kitchen unit so they connect in a run: the
## stove's scaled depth is 0.7768 (native 1.070 × 0.7257), and these units'
## native depth is 1.120 — so Y/Z use scale 0.6935 to bring depth to exactly
## the stove's 0.7768 (flush front edge). WIDTH is scaled SEPARATELY (0.7420,
## not 0.6935) to land on exactly 0.75 — a clean multiple of every snap grid
## (3×0.25, 6×0.125) — so units placed side-by-side on the grid connect
## seamlessly (no gaps from a non-grid-multiple width, and no placement-
## blocking overlap).

## Model paths + shared non-uniform scale per variant. X widened to hit the
## 0.75 grid multiple; Y/Z keep the stove-flush scale (see header). The 2/3
## drawer variants are slightly taller natively (1.625 vs 1.614) — height
## follows naturally at the shared Y scale.
const MODEL_PATHS: Dictionary = {
	1: "res://assets/models/drawers1.glb",
	2: "res://assets/models/drawers2.glb",
	3: "res://assets/models/drawers3.glb",
}
const MODEL_SCALE: Vector3 = Vector3(0.7420, 0.6935, 0.6935)

## Scaled footprint (width = 0.75 grid multiple; depth = stove's 0.7768,
## flush in a run) and height — used for the collision box and ghost.
## Drawers #1 is 1.119 tall; #2/#3 are 1.127 (slightly taller native model).
const FOOTPRINT_X: float = 0.75
const FOOTPRINT_Z: float = 0.777
const MODEL_HEIGHT: Dictionary = {
	1: 1.119,
	2: 1.127,
	3: 1.127,
}

## Full-fidelity preview mode — same convention as every other furniture
## script. Drawers have nothing to register (no power, no groups), so this
## guard only keeps the pattern consistent with the codebase.
var _is_preview_only: bool = false

## Which drawer unit to build (1/2/3) — mirrors the Carpet tier-export
## convention; set by GhostModelBuilder's tier_prop when spawning previews.
@export var variant: int = 1

func _ready() -> void:
	if not MODEL_PATHS.has(variant):
		variant = 1
	_build_mesh()
	if _is_preview_only:
		return
	collision_layer = 5   ## Player + build-hover raycast
	collision_mask  = 0

func _build_mesh() -> void:
	var path: String = MODEL_PATHS[variant]
	var packed: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position = Vector3.ZERO
			model.scale    = MODEL_SCALE
			_recenter_glb_mesh(model)
			_strip_model_collision(model)
			add_child(model)
	else:
		push_warning("Drawers.gd: model missing at %s — falling back to no visual mesh" % path)

	## Invisible box collider matching the scaled drawer footprint.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(FOOTPRINT_X, MODEL_HEIGHT[variant], FOOTPRINT_Z)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, MODEL_HEIGHT[variant] * 0.5, 0.0)
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
	box.size = Vector3(FOOTPRINT_X, 1.127, FOOTPRINT_Z)
	return box