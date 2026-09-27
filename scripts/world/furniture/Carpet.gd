extends StaticBody3D
class_name Carpet
## Carpet.gd
## Flat floor-covering rug — decorative, no interaction. Two variants via the
## `variant` export (1 or 2) mapping to Carpet_1 / Carpet_2 from the Ultimate
## House Interior Pack (Blends/Carpet_1.blend / Carpet_2.blend, exported to
## GLB). Furniture category, TILE 40 / TILE 41, $75 each.
##
## One script, two variants — mirrors the GrowLight tier-export convention
## rather than two near-duplicate classes (same as SmallShelf/LargeShelf are
## tiny Shelving subclasses, but those also differ in slot layout; a carpet's
## only difference is which GLB loads, so a single script with an export is
## the simpler fit).

## Which carpet model to load: 1 = Carpet_1 (runner, 2.13×3.09 native),
## 2 = Carpet_2 (nearly square, 3.09×3.18 native), 3 = Carpet_Round (round,
## 2.49×2.53 native). Set by BuildModeController before add_child() (and by
## GhostModelBuilder for the preview instance).
@export var variant: int = 1

## Model paths + scale. Each carpet is scaled UNIFORMLY so its longest side
## lands at 1.80m — "about 4 end tables in a square" (4×0.90 = 1.80), the
## requested in-game size. No scrunching: the other axis follows the model's
## natural aspect. Carpet_1 → 1.24×1.80, Carpet_2 → 1.75×1.80, Carpet_Round
## → 1.80 round (0.7112 × 2.531).
const MODEL_PATHS: Dictionary = {
	1: "res://assets/models/carpet1.glb",
	2: "res://assets/models/carpet2.glb",
	3: "res://assets/models/carpet3.glb",
}
const MODEL_SCALES: Dictionary = {
	1: 0.5820,
	2: 0.5659,
	3: 0.7112,
}
## Scaled dimensions per variant (longest 1.80, other follows native aspect) —
## used for the collision box and ghost. Carpet_1: 1.24×1.80, Carpet_2: 1.75×1.80,
## Carpet_3 (round): 1.80×1.80.
const SCALED_SIZE: Dictionary = {
	1: Vector3(1.240, 0.022, 1.800),
	2: Vector3(1.750, 0.022, 1.800),
	3: Vector3(1.800, 0.016, 1.800),
}

## Small lift off the floor (Sep 2026) — the carpet's base sits at y=0 and
## just barely clipped the floor; raise the whole rug (visual + collision)
## this much so it reads as resting on top of the floor instead of z-fighting
## into it. Applied as a shared Y offset to both the model and its collider.
const FLOOR_CLEARANCE: float = 0.025

## Full-fidelity preview mode — same convention as every other furniture
## script. Carpets have nothing to register (no power, no groups), so this
## guard only keeps the pattern consistent with the codebase.
var _is_preview_only: bool = false

func _ready() -> void:
	variant = variant if MODEL_PATHS.has(variant) else 1
	_build_mesh()
	if _is_preview_only:
		return
	collision_layer = 5   ## Player + build-hover raycast
	collision_mask  = 0

func _build_mesh() -> void:
	var packed: PackedScene = load(MODEL_PATHS[variant]) if ResourceLoader.exists(MODEL_PATHS[variant]) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position = Vector3(0.0, FLOOR_CLEARANCE, 0.0)
			model.scale    = Vector3.ONE * MODEL_SCALES[variant]
			_strip_model_collision(model)
			add_child(model)
	else:
		push_warning("Carpet.gd: model missing at %s — falling back to no visual mesh" % MODEL_PATHS[variant])

	## Thin invisible collision box matching the scaled carpet footprint — the
	## carpet is a flat rug, so a single low box is all the DetectArea/hover
	## needs. Positioned so the rug sits just above the floor (base at y=0),
	## raised by the same FLOOR_CLEARANCE as the visual model.
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	var sz: Vector3 = SCALED_SIZE[variant]
	box.size = sz
	col_shape.shape = box
	col_shape.position = Vector3(0.0, FLOOR_CLEARANCE + sz.y * 0.5, 0.0)
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
	box.size = SCALED_SIZE[1]
	return box