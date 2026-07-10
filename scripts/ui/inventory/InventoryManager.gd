extends Node
## InventoryManager.gd
## Manages 4 inventory slots. Items are removed from the world when stored.
## Items can be "activated" (brought to hand) while remaining in their slot,
## so the HUD always shows them and slot positions never change.

const SLOT_COUNT: int = 4

signal inventory_changed()

## Each slot is either null (empty) or a RigidBody3D node reference.
## Items stay in their slot even when held — slot only clears on world-drop.
var slots: Array = [null, null, null, null]

## Reference to world root for dropping items back into
var _world_root: Node3D = null

func _ready() -> void:
	add_to_group("inventory_manager")   ## lets BunkerPregen find us via get_first_node_in_group
	_world_root = get_tree().get_first_node_in_group("world")

# ─── Public API ───────────────────────────────────────────────────────────────
func is_full() -> bool:
	for slot in slots:
		if slot == null:
			return false
	return true

func has_item(item: Node) -> bool:
	return item in slots

func first_empty_slot() -> int:
	for i in SLOT_COUNT:
		if slots[i] == null:
			return i
	return -1

func slot_of(item: Node) -> int:
	for i in SLOT_COUNT:
		if slots[i] == item:
			return i
	return -1

# ─── Store ────────────────────────────────────────────────────────────────────
## Store item in the first empty slot.
## Returns the slot index on success, -1 on failure.
func add_item(item: RigidBody3D) -> int:
	var slot: int = first_empty_slot()
	if slot == -1:
		return -1
	_store_to_slot(item, slot)
	inventory_changed.emit()
	return slot

## Store item directly into a specific slot (slot must be empty).
## Returns true on success.
func add_item_to_slot(item: RigidBody3D, slot: int) -> bool:
	if slot < 0 or slot >= SLOT_COUNT:
		return false
	if slots[slot] != null:
		return false  # Occupied
	_store_to_slot(item, slot)
	inventory_changed.emit()
	return true

func _store_to_slot(item: RigidBody3D, slot: int) -> void:
	slots[slot] = item
	item.freeze          = true
	item.visible         = false
	item.collision_layer = 0
	item.collision_mask  = 0
	item.remove_from_group("pickup")
	# Clear held state — prevents ghost physics running while hidden
	if "is_held" in item:
		item.is_held = false
	if "_hold_point" in item:
		item._hold_point = null

# ─── Activate / Deactivate (in-hand while staying in slot) ───────────────────
## Make an inventory item visible and physics-active so the player can hold it,
## WITHOUT removing it from its slot. Returns the item, or null on failure.
func activate_item(slot: int) -> RigidBody3D:
	if slot < 0 or slot >= SLOT_COUNT:
		return null
	var item: RigidBody3D = slots[slot]
	if item == null:
		return null
	item.freeze          = false
	item.visible         = true
	item.collision_layer = 2   ## held-item layer — collides with world but not pickup
	item.collision_mask  = 1
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	# Don't add back to "pickup" group — item is in hand, not on ground
	return item

## Hide and freeze an inventory item back to its stored state (still in slot).
## Call this when swapping away without dropping.
func deactivate_item(slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	var item: RigidBody3D = slots[slot]
	if item == null:
		return
	item.freeze          = true
	item.visible         = false
	item.collision_layer = 0
	item.collision_mask  = 0
	if "is_held" in item:
		item.is_held = false
	if "_hold_point" in item:
		item._hold_point = null

# ─── Retrieve (removes from slot — use for world-drop only) ──────────────────
## Remove item from slot entirely and restore world state.
## Use only when dropping to the world, not when bringing to hand.
func retrieve_item(slot: int) -> RigidBody3D:
	if slot < 0 or slot >= SLOT_COUNT:
		return null
	var item: RigidBody3D = slots[slot]
	if item == null:
		return null

	slots[slot] = null

	item.freeze          = false
	item.visible         = true
	item.collision_layer = 1
	item.collision_mask  = 1
	item.add_to_group("pickup")
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

	inventory_changed.emit()
	return item

## Drop item from slot back into the world at drop_position.
func remove_item(slot: int, drop_position: Vector3) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	var item: RigidBody3D = slots[slot]
	if item == null:
		return

	slots[slot] = null

	item.freeze          = false
	item.visible         = true
	item.collision_layer = 1
	item.collision_mask  = 1
	item.add_to_group("pickup")

	if item.has_method("drop"):
		item.drop(_world_root, drop_position)

	inventory_changed.emit()
