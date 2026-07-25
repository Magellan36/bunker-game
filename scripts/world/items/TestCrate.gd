extends PickupableItem
## TestCrate.gd
## Carriable crate. While held, stays in world tree and lerps to hold point
## every physics frame — no reparenting during carry.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var item_name: String = "Crate"

## Shelf stacking — 1 crate per slot (too large to stack)
var shelf_stack_limit: int   = 1
var shelf_item_type: String  = "test_crate"

func _ready() -> void:
	super._ready()
	## Scale to match ~half the previous size.
	## plastic_crate.glb native dims: 0.298 x 0.264 x 0.408 m (real-world scale).
	## Child model node carries 0.6x scale; this root scale of 3.0 gives
	## final visual size: ~0.54 x 0.48 x 0.73 m — a sensible carry crate.
	## CollisionShape3D box in TestCrate.tscn is pre-calculated to match exactly.
	scale = Vector3(3.0, 3.0, 3.0)

func get_prompt_text() -> String:
	return "[F] Pick up %s" % item_name
