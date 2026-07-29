extends PickupableItem
class_name Basket
## Basket.gd
## Pickupable container, holds up to 12 individual food items (no stacking).
## Cylindrical placeholder mesh (waste-basket/laundry-basket silhouette).
## While HELD:
##   E  — stash the nearest world item in the "basket_storable" group into
##        the first open basket slot (overrides normal on_use()/on_interact()
##        via InteractionSystem's is_basket_container duck-type check).
##   G  — opens BasketUI (contents menu) instead of the normal store/put-away
##        action (basket itself is never inventory-storable).
## Not in the "inventory_item" group — too big to carry in a pocket slot,
## same category as WaterCase/CanCase (pickup + interact only).
## Can be placed on Shelving like any other pickupable prop (shelf_stack_limit
## / shelf_item_type below are all Shelving.gd needs — no changes required
## there).

const CAPACITY: int = 12

@export var item_name: String = "Basket"

## Duck-typed marker InteractionSystem checks for ("is_basket_container" in
## held_item) — mirrors how Shelving checks "shelf_stack_limit" in item.
var is_basket_container: bool = true

## Shelf stacking — bulky, one basket per slot, same convention as TestCrate.
var shelf_stack_limit: int  = 1
var shelf_item_type: String = "basket"

## 12 individual slots. null = empty. Items are re-parented as direct children
## of this node while stored (hidden + frozen), so they move with the basket
## for free on pickup/drop/shelf-place — no separate position bookkeeping
## needed while stored.
var slots: Array = []

var _mesh: MeshInstance3D = null

signal item_added(slot_index: int, item: RigidBody3D)
signal item_removed(slot_index: int, item: RigidBody3D)

func _ready() -> void:
	super._ready()
	add_to_group("interactable")   ## So the "E to add nearby item" prompt path can find it if ever needed directly
	slots.resize(CAPACITY)
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_display_name() -> String:
	return item_name

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % item_name

func get_interact_prompt() -> String:
	return "[G] Open Basket"

## No get_use_prompt() override — while HELD, E is intercepted entirely by
## InteractionSystem's is_basket_container branch (adds nearby item to
## basket instead of calling on_use()), so this never actually shows.

# ─── Slot helpers ─────────────────────────────────────────────────────────────
func _first_empty_slot() -> int:
	for i: int in CAPACITY:
		if slots[i] == null:
			return i
	return -1

func is_full() -> bool:
	return _first_empty_slot() == -1

func count_filled() -> int:
	var n: int = 0
	for s in slots:
		if s != null:
			n += 1
	return n

## Called by InteractionSystem when the player presses E near a
## "basket_storable" item while holding this basket.
func try_add_item(item: RigidBody3D) -> bool:
	var slot: int = _first_empty_slot()
	if slot == -1:
		return false

	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector3.ZERO

	item.visible          = false
	item.freeze            = true
	item.freeze_mode       = RigidBody3D.FREEZE_MODE_STATIC
	item.collision_layer   = 0
	item.collision_mask    = 0
	item.linear_velocity   = Vector3.ZERO
	item.angular_velocity  = Vector3.ZERO
	if "is_held" in item:
		item.is_held = false
	if "_hold_point" in item:
		item._hold_point = null

	slots[slot] = item
	item_added.emit(slot, item)
	return true

## Pops an item back out to full physics/visibility (caller — BasketUI —
## decides whether it goes to the ground or into inventory).
func remove_item(slot_idx: int) -> RigidBody3D:
	if slot_idx < 0 or slot_idx >= CAPACITY:
		return null
	var item: RigidBody3D = slots[slot_idx]
	if item == null:
		return null
	slots[slot_idx] = null

	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	if item.get_parent() != world_root:
		item.get_parent().remove_child(item)
		world_root.add_child(item)

	item.visible          = true
	item.freeze            = false
	item.freeze_mode       = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.gravity_scale     = 1.0
	item.collision_layer    = 1
	item.collision_mask    = 1
	item.linear_velocity   = Vector3.ZERO
	item.angular_velocity  = Vector3.ZERO
	item.global_position   = global_position + Vector3(0.0, 0.3, 0.0)

	item_removed.emit(slot_idx, item)
	return item

# ─── Placeholder mesh ─────────────────────────────────────────────────────────
## Plain cylinder, laundry/waste-basket silhouette — CylinderMesh top wider
## than bottom (top_radius > bottom_radius) reads visually as an open basket.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius    = 0.28
	cyl.bottom_radius = 0.22
	cyl.height        = 0.45
	_mesh.mesh = cyl
	_mesh.position = Vector3(0.0, 0.225, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.42, 0.30, 1.0)   ## Woven-basket tan
	mat.roughness    = 0.85
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself, matching
	## SeedItem.gd/FarmProduceItem.gd's documented reasoning (a nested
	## MeshInstance3D.create_trimesh_collision() would leave this body with
	## no collider and it would fall through the floor).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.28
	cyl_shape.height = 0.45
	shape.shape = cyl_shape
	shape.position = _mesh.position
	add_child(shape)