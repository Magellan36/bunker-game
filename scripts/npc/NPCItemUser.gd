extends RefCounted
class_name NPCItemUser
## NPCItemUser.gd  (NPC Pass 2, Part 3)
## Carry/fetch/consume helpers shared by every activity that touches items
## (Drink/Eat here; Part 4's fetch-based jobs reuse find/pickup/drop as-is).
## All world mutation goes through the SAME item methods the player uses.

const PICKUP_RANGE: float = 1.2      ## must be this close to grab
const SHELF_RANGE:  float = 1.6

# ─── Target search ────────────────────────────────────────────────────────
## Nearest loose (world) item matching `filter: Callable(item) -> bool`.
## Excludes held, shelved, and frozen items — an NPC can never steal from
## the player's hands or bypass the shelf API.
static func find_loose_item(npc: NPC, filter: Callable) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d: float = INF
	for node: Node in npc.get_tree().get_nodes_in_group("pickup"):
		if not (node is RigidBody3D) or not is_instance_valid(node):
			continue
		var rb: RigidBody3D = node as RigidBody3D
		if rb.is_in_group("shelved"):
			continue
		if ("is_held" in rb) and rb.is_held:
			continue
		if rb.freeze:
			continue
		if not filter.call(rb):
			continue
		var d: float = rb.global_position.distance_to(npc.global_position)
		if d < best_d:
			best_d = d
			best = rb
	return best

## Nearest shelf slot whose TOP item matches filter.
## Returns {} or {shelf: Shelving, slot: int, item: RigidBody3D}.
static func find_shelved_item(npc: NPC, filter: Callable) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for node: Node in npc.get_tree().get_nodes_in_group("shelf"):
		if not is_instance_valid(node) or not ("slots" in node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(npc.global_position)
		if d >= best_d:
			continue
		for slot_idx: int in range(node.slots.size()):
			var stack: Array = node.slots[slot_idx]
			if stack.is_empty():
				continue
			var top: RigidBody3D = stack.back()
			if top == null or not is_instance_valid(top) or not filter.call(top):
				continue
			best_d = d
			best = {"shelf": node, "slot": slot_idx, "item": top}
			break
	return best

# ─── Carry primitives ─────────────────────────────────────────────────────
static func grab_loose(npc: NPC, item: RigidBody3D) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if npc.global_position.distance_to(item.global_position) > PICKUP_RANGE:
		return false
	if item.has_method("pickup"):
		item.pickup(npc.hold_point)
		npc.held_item = item
		return true
	return false

static func grab_from_shelf(npc: NPC, shelf: Node, slot: int) -> bool:
	if shelf == null or not is_instance_valid(shelf):
		return false
	if npc.global_position.distance_to((shelf as Node3D).global_position) > SHELF_RANGE:
		return false
	if not shelf.has_method("npc_retrieve"):
		return false
	var item: RigidBody3D = shelf.npc_retrieve(slot, npc.hold_point)
	if item == null:
		return false
	npc.held_item = item
	return true

## Put whatever is held back into the world at the NPC's feet, via the same
## drop() the player uses.
static func drop_held(npc: NPC) -> void:
	var item: RigidBody3D = npc.held_item
	npc.held_item = null
	if item == null or not is_instance_valid(item):
		return
	var world: Node = npc.get_tree().get_first_node_in_group("main_world")
	var parent: Node3D = world if world is Node3D else npc.get_parent()
	if item.has_method("drop"):
		item.drop(parent, npc.global_position
			+ npc.global_transform.basis * Vector3(0.0, 0.6, -0.7))

# ─── Consumable filters (used by activities) ──────────────────────────────
static func is_drinkable_bottle(item: Node) -> bool:
	return item is WaterBottle and item.current_fill_mL > 0.0

static func is_edible(item: Node) -> bool:
	if item is DishItem:
		return true
	if item is FarmProduceItem:
		return true
	if item.has_method("has_bites_left"):   ## FoodCan
		return item.has_bites_left()
	return false

## Apply one "consume step" of a held edible to the NPC's hunger. Returns
## true when the item is finished with (freed or empty) and the hand is clear.
static func eat_held_step(npc: NPC) -> bool:
	var item: Node = npc.held_item
	if item == null or not is_instance_valid(item):
		npc.held_item = null
		return true
	if item is DishItem or item is FarmProduceItem:
		npc.hunger = minf(100.0, npc.hunger + item.consume_as_food())
		npc.held_item = null   ## consume_as_food frees the node
		return true
	if item.has_method("take_bite"):   ## FoodCan — multi-bite
		npc.hunger = minf(100.0, npc.hunger + item.take_bite())
		if not item.has_bites_left() or npc.hunger >= 95.0:
			drop_held(npc)   ## empty can (or full NPC) — set it back down
			return true
		return false   ## more bites coming; EatActivity re-times the next one
	return true