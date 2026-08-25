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

func get_trash_material() -> String:
	return "organic"

func get_interact_prompt() -> String:
	return "[G] Open Basket"

## No get_use_prompt() override — while HELD, E is intercepted entirely by
## InteractionSystem's is_basket_container branch (adds nearby item to
## basket instead of calling on_use()), so this never actually shows.

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## Unlike every other held item — which keeps whatever tilt it happened to
	## have at pickup, by design — the basket must never lean or tip while
	## carried. Smoothly returns to its authored upright orientation (Basis
	## IDENTITY — Basket.tscn has no rotation set, and the cylinder mesh is
	## built along local Y in _build_placeholder_mesh(), so identity IS
	## upright) every physics tick, immediately after the parent class's
	## position-follow logic runs. Aug 2026 — was an instant hard snap
	## (global_transform.basis = Basis.IDENTITY outright); now eases toward
	## it via PickupableItem.slerp_to_upright(), softer but still quick. This
	## only touches rotation — linear_velocity / follow_speed / knockout
	## distance / grace timer are all untouched, still handled entirely by
	## PickupableItem._physics_process() above.
	if is_held and _hold_point != null:
		slerp_to_upright(delta, UPRIGHT_SLERP_SPEED)

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
	if item.has_method("deactivate_dynamic_state"):
		item.deactivate_dynamic_state()   ## stashed = physics/contacts/obstacle off (Aug 2026)
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
	if item.has_method("restore_dynamic_state"):
		item.restore_dynamic_state()   ## back to a live item (Aug 2026)
	item.global_position   = global_position + Vector3(0.0, 0.3, 0.0)

	item_removed.emit(slot_idx, item)
	return item

# ─── Placeholder mesh ─────────────────────────────────────────────────────────
## Woven wicker basket with cross-hatched lattice, arched handles, and an
## open hollow interior. All built from CylinderMesh + BoxMesh primitives.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.position = Vector3(0.0, 0.225, 0.0)

	var wicker_mat: StandardMaterial3D = StandardMaterial3D.new()
	wicker_mat.albedo_color = Color(0.58, 0.45, 0.30, 1.0)
	wicker_mat.roughness    = 0.90
	wicker_mat.metallic     = 0.0

	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.50, 0.38, 0.25, 1.0)
	rim_mat.roughness    = 0.88
	rim_mat.metallic     = 0.0

	var dark_mat: StandardMaterial3D = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.20, 0.15, 0.10, 1.0)
	dark_mat.roughness    = 0.95
	dark_mat.metallic     = 0.0

	## Outer wall — tapered cylinder (top wider than bottom).
	var outer: MeshInstance3D = MeshInstance3D.new()
	var outer_mesh: CylinderMesh = CylinderMesh.new()
	outer_mesh.top_radius    = 0.28
	outer_mesh.bottom_radius = 0.22
	outer_mesh.height        = 0.45
	outer.mesh = outer_mesh
	outer.position = Vector3(0.0, 0.0, 0.0)
	outer.set_surface_override_material(0, wicker_mat)
	_mesh.add_child(outer)

	## Inner cavity — dark hollow interior.
	var cavity: MeshInstance3D = MeshInstance3D.new()
	var cavity_mesh: CylinderMesh = CylinderMesh.new()
	cavity_mesh.top_radius    = 0.25
	cavity_mesh.bottom_radius = 0.19
	cavity_mesh.height        = 0.38
	cavity.mesh = cavity_mesh
	cavity.position = Vector3(0.0, 0.04, 0.0)
	cavity.set_surface_override_material(0, dark_mat)
	_mesh.add_child(cavity)

	## Top rim — thick braided ring.
	var rim: MeshInstance3D = MeshInstance3D.new()
	var rim_mesh: CylinderMesh = CylinderMesh.new()
	rim_mesh.top_radius    = 0.29
	rim_mesh.bottom_radius = 0.29
	rim_mesh.height        = 0.03
	rim.mesh = rim_mesh
	rim.position = Vector3(0.0, 0.225, 0.0)
	rim.set_surface_override_material(0, rim_mat)
	_mesh.add_child(rim)

	## Bottom ring.
	var bottom_ring: MeshInstance3D = MeshInstance3D.new()
	var bottom_mesh: CylinderMesh = CylinderMesh.new()
	bottom_mesh.top_radius    = 0.23
	bottom_mesh.bottom_radius = 0.23
	bottom_mesh.height        = 0.02
	bottom_ring.mesh = bottom_mesh
	bottom_ring.position = Vector3(0.0, -0.215, 0.0)
	bottom_ring.set_surface_override_material(0, rim_mat)
	_mesh.add_child(bottom_ring)

	## Vertical weave bars — 10 bars around the circumference.
	for i: int in 10:
		var angle: float = i * TAU / 10.0
		var bar: MeshInstance3D = MeshInstance3D.new()
		var bar_mesh: BoxMesh = BoxMesh.new()
		bar_mesh.size = Vector3(0.012, 0.40, 0.012)
		bar.mesh = bar_mesh
		var r: float = 0.265
		bar.position = Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		bar.rotation.y = -angle
		bar.set_surface_override_material(0, wicker_mat)
		_mesh.add_child(bar)

	## Diagonal cross-hatch bars (45° and -45°) — 5 rows, 10 bars each.
	for row: int in 5:
		var y: float = -0.16 + row * 0.09
		for i: int in 10:
			var angle: float = i * TAU / 10.0
			## Diagonal bar 1 (45°)
			var d1: MeshInstance3D = MeshInstance3D.new()
			var d1_mesh: BoxMesh = BoxMesh.new()
			d1_mesh.size = Vector3(0.008, 0.07, 0.008)
			d1.mesh = d1_mesh
			var r: float = 0.27
			d1.position = Vector3(cos(angle) * r, y, sin(angle) * r)
			d1.rotation.y = -angle
			d1.rotation.x = PI / 4.0
			d1.set_surface_override_material(0, rim_mat)
			_mesh.add_child(d1)
			## Diagonal bar 2 (-45°)
			var d2: MeshInstance3D = MeshInstance3D.new()
			var d2_mesh: BoxMesh = BoxMesh.new()
			d2_mesh.size = Vector3(0.008, 0.07, 0.008)
			d2.mesh = d2_mesh
			d2.position = Vector3(cos(angle) * r, y, sin(angle) * r)
			d2.rotation.y = -angle
			d2.rotation.x = -PI / 4.0
			d2.set_surface_override_material(0, rim_mat)
			_mesh.add_child(d2)

	## Arched handles — two handles on opposite sides.
	for sign_x: int in [-1, 1]:
		## Vertical posts.
		for sign_z: int in [-1, 1]:
			var post: MeshInstance3D = MeshInstance3D.new()
			var post_mesh: BoxMesh = BoxMesh.new()
			post_mesh.size = Vector3(0.018, 0.12, 0.018)
			post.mesh = post_mesh
			post.position = Vector3(sign_x * 0.28, 0.22, sign_z * 0.04)
			post.set_surface_override_material(0, rim_mat)
			_mesh.add_child(post)
		## Top arch bar.
		var arch: MeshInstance3D = MeshInstance3D.new()
		var arch_mesh: BoxMesh = BoxMesh.new()
		arch_mesh.size = Vector3(0.018, 0.018, 0.10)
		arch.mesh = arch_mesh
		arch.position = Vector3(sign_x * 0.28, 0.29, 0.0)
		arch.set_surface_override_material(0, rim_mat)
		_mesh.add_child(arch)

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

# ─── StorageUI contract (Aug 2026 — Storage UI Unification pass) ────────────
## Baskets never stack (1 item per slot, count is always 0 or 1) and have
## no "carry" concept — the primary button drops the item on the ground
## near the basket (see get_ui_config()'s primary_button_tooltip below;
## the contract method is still named take_for_carry(), see StorageUI.gd's
## own header comment for why that name is kept generic across storage
## types with different primary actions).
func get_slot_display(slot_idx: int) -> Array:
	if slot_idx < 0 or slot_idx >= CAPACITY:
		return [null, 0]
	var item: RigidBody3D = slots[slot_idx]
	return [item, 1 if item != null else 0]

func take_for_carry(slot_idx: int, _isys: Node) -> bool:
	var item: RigidBody3D = remove_item(slot_idx)
	return item != null

func take_for_inventory(slot_idx: int, inv: Node) -> bool:
	var item: RigidBody3D = remove_item(slot_idx)
	if item == null:
		return false
	## Match Shelving.retrieve_to_inventory's post-remove physics reset —
	## remove_item() above already re-enables physics/visibility/layers,
	## so this is just the inventory hand-off.
	inv.add_item(item)
	return true

func get_ui_config() -> Dictionary:
	return {
		"title": "BASKET CONTENTS",
		"slot_count": CAPACITY,
		"grid_cols": 3,
		"grid_rows": 4,
		"display_order": [],    ## [] = identity (visual position i -> data slot i)
		"supports_stacking": false,
		"primary_button_icon": "drop",
		"primary_button_tooltip": "Drop",
		"primary_button_color": Color(0.55, 0.20, 0.20, 1.00),
		"primary_requires_empty_hands": false,
		"closes_on_action": false,
	}