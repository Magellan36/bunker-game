extends PickupableItem
class_name Antibiotics
## Antibiotics.gd
## Medical item (Aug 2026) — copies Bandage.gd's shape per Brannon's build
## order. See docs/systems/medical/README.md's "Item roles and mechanics".
## Dual role: applied to a plain Open Wound, prevents infection; applied
## to an infected one, cures it — the same treat_open_wound_antibiotics()
## call either way, PlayerMedical decides which behavior applies based on
## the wound's own current state.
##
## Differs from Bandage in one key way: on its LAST charge, this becomes
## an "Empty Bottle" (same node, FoodCan-style persistent empty variant)
## instead of destroying itself outright — see docs/systems/medical/
## README.md's "Charges" section for why. The Empty Bottle can still be
## fed into the Research Station chute for a small yield of its own.
##
## Placeholder visual: same procedural-sphere approach as Bandage, just a
## different tint so the two are distinguishable at a glance while both
## are still placeholders — now the real models handle it (full bottle vs
## dedicated Empty model).

# ─── Config ─────────────────────────────────────────────────────────────────
const TOTAL_CHARGES: int = 2

const PLACEHOLDER_RADIUS: float = 0.05
const FULL_COLOR: Color  = Color(0.60, 0.78, 0.68, 1.0)   ## pale green "medicine bottle" tint (fallback only)

## Real models (Aug 2026) — Tinkercad OBJ, MTL flat colors. The full bottle
## swaps to the dedicated Empty model when charges run out (the "Empty
## Bottle" mechanic). MODEL_SCALE maps the bottle's largest dimension
## (6.8 units) to 2x the placeholder diameter (0.20m visual).
const MODEL_PATH:       String = "res://assets/models/medical/antibiotics/tinker.obj"
const MODEL_EMPTY_PATH: String = "res://assets/models/medical/antibiotics_empty/tinker.obj"
const MODEL_SCALE:      float  = 0.0294

## Research Station chute yields (Aug 2026) — see
## docs/systems/medical/README.md's "Research Station chute yields" table.
## Scaled to whichever charge tier the bottle is in at the moment of
## feeding — 2 charges yields more than 1, and the emptied bottle still
## yields a small amount of plastic on its own.
const CHUTE_ORGANIC_AT_2: int = 2
const CHUTE_PLASTIC_AT_2: int = 1
const CHUTE_ORGANIC_AT_1: int = 1
const CHUTE_PLASTIC_AT_1: int = 1
const CHUTE_PLASTIC_EMPTY: int = 1

## Shelf stacking — matches FoodCan.gd's convention (small item, several per slot).
var shelf_stack_limit: int  = 6
var shelf_item_type: String = "antibiotics"

# ─── State ───────────────────────────────────────────────────────────────────
var _charges_left: int = TOTAL_CHARGES
var _is_empty: bool = false
var _mesh_instance: MeshInstance3D = null
## Body-space visual AABB of the loaded model — the cylinder collision is
## built from it so it roughly matches the bottle.
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
		_apply_bottle_mesh(mesh)
		_model_aabb = _mesh_instance.transform * _mesh_instance.mesh.get_aabb()
		BuildMaterials.apply_mood_override(_mesh_instance)
		add_child(BuildMaterials.build_model_collision("cylinder", _model_aabb))
	else:
		var sphere := SphereMesh.new()
		sphere.radius = PLACEHOLDER_RADIUS
		sphere.height = PLACEHOLDER_RADIUS * 2.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FULL_COLOR
		sphere.material = mat
		_mesh_instance.mesh = sphere
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = PLACEHOLDER_RADIUS
		cs.shape = sp
		add_child(cs)
	add_child(_mesh_instance)

## Applies the bottle model transform (scale + stand-up + base at the old
## collision sphere's bottom so it rests flush) — reused by the empty swap.
## Re-applies the mood override too, so the Empty model's materials match.
func _apply_bottle_mesh(mesh: ArrayMesh) -> void:
	_mesh_instance.mesh = mesh
	_mesh_instance.scale = Vector3.ONE * MODEL_SCALE
	_mesh_instance.rotation.x = -PI / 2.0   ## OBJ height runs along Z (Tinkercad) — stand upright
	var aabb: AABB = _mesh_instance.transform * _mesh_instance.mesh.get_aabb()
	_mesh_instance.position = Vector3(0.0, -aabb.position.y - PLACEHOLDER_RADIUS, 0.0)
	BuildMaterials.apply_mood_override(_mesh_instance)

## Empty-bottle mechanic: swap the visual to the dedicated Empty model.
func _update_visual() -> void:
	if _mesh_instance == null:
		return
	var mesh: ArrayMesh = load(MODEL_EMPTY_PATH if _is_empty else MODEL_PATH) as ArrayMesh
	if mesh != null:
		_apply_bottle_mesh(mesh)

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Empty Bottle" if _is_empty else "Antibiotics"

func get_prompt_text() -> String:
	if _is_empty:
		return "[F] Pick up  Empty Bottle"
	return "[F] Pick up  Antibiotics"

func get_use_prompt() -> String:
	if _is_empty:
		return ""   ## no charges left — E does nothing, same convention as any empty consumable
	return "[E] Antibiotics  (%d/%d)" % [_charges_left, TOTAL_CHARGES]

func has_charges_left() -> bool:
	return not _is_empty and _charges_left > 0

## Same live-state trash convention FoodCan.gd uses — an emptied bottle
## persists as the same node, so this is a live check, not a one-time tag.
func is_trash() -> bool:
	return _is_empty

# ─── Use — opens the injury-selection submenu instead of applying directly ──
func on_use() -> void:
	if _is_empty:
		return
	var isys: Node = _find_interaction_system()
	if isys != null and isys.has_method("open_medical_submenu"):
		isys.open_medical_submenu(self)

func _find_interaction_system() -> Node:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get_node_or_null("InteractionSystem")

# ─── Injury-selection submenu contract (Aug 2026) ───────────────────────────
## See PlayerMedical.get_eligible_antibiotic_targets() for the exact
## { body_part, label, detail } shape and sort order.
func get_eligible_targets() -> Array:
	var pm: Node = get_tree().get_first_node_in_group("player_medical")
	if pm == null or not pm.has_method("get_eligible_antibiotic_targets"):
		return []
	return pm.get_eligible_antibiotic_targets()

## Applies the real treatment (preventative or curative, decided by
## PlayerMedical based on the wound's own state), deducts one charge, and
## becomes an Empty Bottle at 0 — NOT destroyed, unlike Bandage/Splint/
## Trauma Kit. Same call real gameplay always uses.
func apply_to_target(body_part: int) -> void:
	if _is_empty:
		return
	var pm: Node = get_tree().get_first_node_in_group("player_medical")
	if pm == null or not pm.has_method("treat_open_wound_antibiotics"):
		return
	pm.treat_open_wound_antibiotics(body_part)
	_charges_left -= 1
	charge_changed.emit()
	if _charges_left <= 0:
		_become_empty()

func _become_empty() -> void:
	_is_empty     = true
	_charges_left = 0
	_update_visual()

# ─── Research Station chute contract (Aug 2026) ─────────────────────────────
## Yield tier depends on remaining charges at the moment of feeding — see
## docs/systems/medical/README.md's "Research Station chute yields" table.
## Not get_trash_material() (see that method's own comment above) — this
## is the contract ResearchStation._feed_single_item() actually prefers.
func get_research_yield() -> Dictionary:
	if _is_empty:
		return {"plastic": CHUTE_PLASTIC_EMPTY}
	if _charges_left >= 2:
		return {"organic": CHUTE_ORGANIC_AT_2, "plastic": CHUTE_PLASTIC_AT_2}
	return {"organic": CHUTE_ORGANIC_AT_1, "plastic": CHUTE_PLASTIC_AT_1}
