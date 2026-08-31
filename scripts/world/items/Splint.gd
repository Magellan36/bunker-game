extends PickupableItem
class_name Splint
## Splint.gd
## Medical item (Aug 2026) — copies Bandage.gd's shape per Brannon's build
## order. See docs/systems/medical/README.md's "Item roles and mechanics".
## Splints a selected Fractured body part — never Broken, Splint is
## Fracture-specific (see PlayerMedical.get_eligible_splint_targets()).
##
## Single-charge, destroyed on its one use, same as Trauma Kit — see the
## design doc's "Charges" section (corrected Aug 2026 from an earlier 2/2
## baseline).
##
## Placeholder visual: same procedural-sphere approach as Bandage/
## Antibiotics, a third distinct tint — intentionally low-effort, real
## models later.

# ─── Config ─────────────────────────────────────────────────────────────────
const TOTAL_CHARGES: int = 1

const PLACEHOLDER_RADIUS: float = 0.06
const PLACEHOLDER_COLOR: Color  = Color(0.78, 0.72, 0.55, 1.0)   ## light tan/wood tone

## Research Station chute yield — flat, since this is a single-charge item
## with no tiers to scale across (see docs/systems/medical/README.md's
## "Research Station chute yields" table).
const CHUTE_METAL_YIELD: int = 2

## Shelf stacking — bulkier than Bandage/Antibiotics, fewer per slot.
var shelf_stack_limit: int  = 4
var shelf_item_type: String = "splint"

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
	return "Splint Kit"

func get_prompt_text() -> String:
	return "[F] Pick up  Splint Kit"

func get_use_prompt() -> String:
	return "[E] Splint  (%d/%d)" % [_charges_left, TOTAL_CHARGES]

func has_charges_left() -> bool:
	return _charges_left > 0

# ─── Use — opens the injury-selection submenu instead of applying directly ──
func on_use() -> void:
	var isys: Node = _find_interaction_system()
	if isys != null and isys.has_method("open_medical_submenu"):
		isys.open_medical_submenu(self)

func _find_interaction_system() -> Node:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get_node_or_null("InteractionSystem")

# ─── Injury-selection submenu contract (Aug 2026) ───────────────────────────
## See PlayerMedical.get_eligible_splint_targets() for the exact
## { body_part, label, detail } shape and sort order.
func get_eligible_targets() -> Array:
	var pm: Node = get_tree().get_first_node_in_group("player_medical")
	if pm == null or not pm.has_method("get_eligible_splint_targets"):
		return []
	return pm.get_eligible_splint_targets()

## Splints the selected Fractured limb, deducts the (only) charge, and
## destroys this item outright — same call real gameplay always uses.
func apply_to_target(body_part: int) -> void:
	var pm: Node = get_tree().get_first_node_in_group("player_medical")
	if pm == null or not pm.has_method("apply_splint"):
		return
	pm.apply_splint(body_part)
	_charges_left -= 1
	charge_changed.emit()
	if _charges_left <= 0:
		queue_free()

# ─── Research Station chute contract (Aug 2026) ─────────────────────────────
func get_research_yield() -> Dictionary:
	return {"metal": CHUTE_METAL_YIELD}
