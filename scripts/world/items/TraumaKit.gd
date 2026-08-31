extends PickupableItem
class_name TraumaKit
## TraumaKit.gd
## Medical item (Aug 2026). See docs/systems/medical/README.md's "Item
## roles and mechanics" and "Trauma Kit" scope note in the Item roles
## table. Deliberately open-ended baseline pending later, more serious
## injury/illness content (gunshots, chronic diseases, etc.) — this game
## hasn't touched that content yet, so Trauma Kit doesn't have a fully
## distinct role from Bandage+Splint combined yet. Tweak/expand once that
## content exists rather than over-designing this now.
##
## Behavior: pressing E immediately bandages EVERY currently-Bleeding
## wound and splints EVERY currently-Fractured limb, all at once — NO
## target selection, unlike Bandage/Antibiotics/Splint. This is the one
## Medical item that does NOT open the injury-selection submenu at all;
## see PlayerMedical.treat_all_bleeding_and_fractures(). Single-charge,
## destroyed on use regardless of whether anything was actually eligible
## to treat (a deliberate simplification, not re-litigated per press).
##
## Placeholder visual: same procedural-sphere approach as the other three
## items, a fourth distinct (red, "kit") tint — intentionally low-effort,
## real models later.

# ─── Config ─────────────────────────────────────────────────────────────────
const TOTAL_CHARGES: int = 1

const PLACEHOLDER_RADIUS: float = 0.07
const PLACEHOLDER_COLOR: Color  = Color(0.75, 0.20, 0.18, 1.0)   ## red "kit" tone, distinct from the other three

## Research Station chute yield — flat, single-charge item, no tiers.
const CHUTE_METAL_YIELD: int = 4

## Shelf stacking — bulkiest of the four Medical items, fewest per slot.
var shelf_stack_limit: int  = 2
var shelf_item_type: String = "trauma_kit"

# ─── State ───────────────────────────────────────────────────────────────────
var _charges_left: int = TOTAL_CHARGES
var _mesh_instance: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")     ## pocket inventory + Dresser/EndTable (LightStorage)
	add_to_group("basket_storable")    ## Basket's separate storage mechanism
	_build_placeholder_mesh()

func _build_placeholder_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = PLACEHOLDER_RADIUS
	sphere.height = PLACEHOLDER_RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLACEHOLDER_COLOR
	sphere.material = mat
	_mesh_instance.mesh = sphere
	add_child(_mesh_instance)

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Trauma Kit"

func get_prompt_text() -> String:
	return "[F] Pick up  Trauma Kit"

func get_use_prompt() -> String:
	return "[E] Use Trauma Kit"

func has_charges_left() -> bool:
	return _charges_left > 0

# ─── Use — mass-applies immediately, no submenu (see this file's header) ────
func on_use() -> void:
	var pm: Node = get_tree().get_first_node_in_group("player_medical")
	if pm != null and pm.has_method("treat_all_bleeding_and_fractures"):
		pm.treat_all_bleeding_and_fractures()
	_charges_left -= 1
	charge_changed.emit()
	if _charges_left <= 0:
		queue_free()

# ─── Research Station chute contract (Aug 2026) ─────────────────────────────
func get_research_yield() -> Dictionary:
	return {"metal": CHUTE_METAL_YIELD}
