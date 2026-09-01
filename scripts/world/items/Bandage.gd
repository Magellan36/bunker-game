extends PickupableItem
class_name Bandage
## Bandage.gd
## Medical item (Aug 2026) — see docs/systems/medical/README.md's "Item
## roles and mechanics" for the full design. Stops Bleeding on a selected
## body part via the injury-selection submenu (InteractionSystem.gd owns
## the submenu UI/input; this file just supplies eligibility data and the
## real treatment call).
##
## First of the four Medical items — Antibiotics/Splint/Trauma Kit are
## meant to copy this file's shape once it's tested working, per Brannon's
## explicit build order. Kept intentionally self-contained (no shared base
## class yet) for that reason — factor out a common MedicalItem base once
## there are 2+ real copies to compare, not before. NOTE: Antibiotics does
## NOT copy the destroy-on-empty behavior below — it becomes an "Empty
## Bottle" instead (same node, FoodCan-style persistent empty variant),
## per the design doc's "Charges" section.
##
## Placeholder visual: a plain beige sphere, procedurally built (no model
## file) — intentionally low-effort per Brannon's explicit instruction.
## Swap _build_placeholder_mesh() for a real model later without touching
## anything else in this file.

# ─── Config ─────────────────────────────────────────────────────────────────
## Baseline per docs/systems/medical/README.md's "Charges" — Bandage and
## Antibiotics stay at 2/2; Splint/Trauma Kit are explicitly single-charge
## (see that section for the full per-item breakdown, corrected Aug 2026).
const TOTAL_CHARGES: int = 2

const PLACEHOLDER_RADIUS: float = 0.05
const PLACEHOLDER_COLOR: Color  = Color(0.85, 0.75, 0.60, 1.0)   ## beige

## Real model (Aug 2026) — Tinkercad OBJ, MTL flat colors. MODEL_SCALE maps
## the model's largest dimension (5.0 units) to 1.5x the placeholder diameter
## (0.15m visual).
const MODEL_PATH:  String = "res://assets/models/medical/bandage/tinker.obj"
const MODEL_SCALE: float  = 0.03

## Research Station chute yield (Aug 2026) — see
## docs/systems/medical/README.md's "Research Station chute yields".
## Scales 1:1 with whatever charge count remains at the moment of feeding
## (1 charge = +1 Paper/+1 Plastic, 2 charges = +2/+2) — see
## get_research_yield() below.
const CHUTE_PAPER_PER_CHARGE: int   = 1
const CHUTE_PLASTIC_PER_CHARGE: int = 1

## Shelf stacking — matches FoodCan.gd's convention (small item, several per slot).
var shelf_stack_limit: int  = 6
var shelf_item_type: String = "bandage"

# ─── State ───────────────────────────────────────────────────────────────────
var _charges_left: int = TOTAL_CHARGES
var _mesh_instance: MeshInstance3D = null
## Body-space visual AABB of the loaded model — the collision is built from
## it (cylinder for bandage) so it roughly matches the model.
var _model_aabb: AABB = AABB()

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")     ## pocket inventory + Dresser/EndTable (LightStorage)
	add_to_group("basket_storable")    ## Basket's separate storage mechanism
	_build_placeholder_mesh()

func _build_placeholder_mesh() -> void:
	_mesh_instance = MeshInstance3D.new()
	var mesh: ArrayMesh = load(MODEL_PATH) as ArrayMesh
	if mesh != null:
		_mesh_instance.mesh = mesh
		_mesh_instance.scale = Vector3.ONE * MODEL_SCALE
		_mesh_instance.rotation.x = -PI / 2.0   ## OBJ height runs along Z (Tinkercad) — stand upright
		var aabb: AABB = _mesh_instance.transform * _mesh_instance.mesh.get_aabb()
		## Base sits at the old collision sphere's bottom so the model rests flush.
		_mesh_instance.position = Vector3(0.0, -aabb.position.y - PLACEHOLDER_RADIUS, 0.0)
		_model_aabb = _mesh_instance.transform * _mesh_instance.mesh.get_aabb()
		BuildMaterials.apply_mood_override(_mesh_instance)
		add_child(BuildMaterials.build_model_collision("cylinder", _model_aabb))
	else:
		var sphere := SphereMesh.new()
		sphere.radius = PLACEHOLDER_RADIUS
		sphere.height = PLACEHOLDER_RADIUS * 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = PLACEHOLDER_COLOR
		sphere.material = mat
		_mesh_instance.mesh = sphere
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = PLACEHOLDER_RADIUS
		cs.shape = sp
		add_child(cs)
	add_child(_mesh_instance)

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Bandage"

func get_prompt_text() -> String:
	return "[F] Pick up  Bandage"

func get_use_prompt() -> String:
	return "[E] Bandage  (%d/%d)" % [_charges_left, TOTAL_CHARGES]

func has_charges_left() -> bool:
	return _charges_left > 0

# ─── Use — opens the injury-selection submenu instead of applying directly ──
## Which body part to treat is itself a player choice, so E doesn't apply
## treatment immediately the way FoodCan's E-to-eat does — it hands off to
## InteractionSystem's submenu (open_medical_submenu()), which reuses the
## exact same hovering-prompt rendering path this item's normal use-prompt
## already uses. See docs/systems/medical/README.md's "Injury-selection
## submenu" for the full design.
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
## Called by InteractionSystem every frame the submenu is open — worst-
## severity-first list of every body part this Bandage can currently
## treat. See PlayerMedical.get_eligible_bleeding_targets() for the exact
## { body_part, label, detail } shape.
func get_eligible_targets() -> Array:
	var pm: Node = get_tree().get_first_node_in_group("player_medical")
	if pm == null or not pm.has_method("get_eligible_bleeding_targets"):
		return []
	return pm.get_eligible_bleeding_targets()

## Called by InteractionSystem when the player selects a target (number
## key or controller confirm). Applies the real treatment, deducts one
## charge, and DESTROYS this item outright once charges hit 0 — Bandage
## doesn't persist as an "empty" object the way FoodCan/Antibiotics do
## (see this file's own header comment for why Antibiotics differs). The
## exact same treatment call real gameplay always uses — F7's own row
## calls PlayerMedical.treat_bleeding() directly; this just adds the
## charge/destroy bookkeeping around the identical call.
func apply_to_target(body_part: int) -> void:
	var pm: Node = get_tree().get_first_node_in_group("player_medical")
	if pm == null or not pm.has_method("treat_bleeding"):
		return
	pm.treat_bleeding(body_part)
	_charges_left -= 1
	charge_changed.emit()
	if _charges_left <= 0:
		queue_free()

# ─── Research Station chute contract (Aug 2026) ─────────────────────────────
## See ResearchStation._feed_single_item()'s multi-material branch, and
## docs/systems/medical/README.md's "Research Station chute yields".
## Deliberately NOT get_trash_material() (the older single-material,
## fixed-quantity-1 contract every pre-Medical item uses) — Bandage yields
## TWO materials at once, scaled by remaining charges, which that older
## contract can't express. Feeding always fully consumes/destroys the
## item regardless of how many charges remain, same as any other
## single-item chute feed.
func get_research_yield() -> Dictionary:
	return {
		"paper":   CHUTE_PAPER_PER_CHARGE * _charges_left,
		"plastic": CHUTE_PLASTIC_PER_CHARGE * _charges_left,
	}
