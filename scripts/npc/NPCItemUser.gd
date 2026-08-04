extends RefCounted
class_name NPCItemUser
## NPCItemUser.gd  (NPC Pass 2, Part 3)
## Carry/fetch/consume helpers shared by every activity that touches items
## (Drink/Eat here; Part 4's fetch-based jobs reuse find/pickup/drop as-is).
## All world mutation goes through the SAME item methods the player uses.

const PICKUP_RANGE: float = 1.2      ## must be this close to grab
const SHELF_RANGE:  float = 1.6

## XZ-only distance (Part 16). An NPC's own origin is its capsule CENTER
## (~1.4 above the floor); loose items and most furniture sit much lower.
## Raw 3D distance lets that vertical gap silently eat most or all of an
## intended range budget — confirmed as the cause of unreliable water-
## bottle pickup (PICKUP_RANGE=1.2 raw vs. ~0.85 effective once a ~0.9
## vertical offset is factored in). Every proximity/range check below uses
## this instead. Same fix already applied to SitActivity (Part 12) and
## JobActivity's travel arrival (Part 15) — this closes out every remaining
## occurrence of the same bug class in one pass.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

# ─── Lightweight per-item claim system (Part 12) — prevents two NPCs from
## targeting/grabbing the same loose or shelved item at once, which caused
## intermittent lost bites/charges and items visually yanked between NPCs.
## Mirrors JobBoard's claim()/release() pattern but scoped to items. Keyed
## by instance_id so it works uniformly for loose items and shelf contents.
static var _claims: Dictionary = {}   ## item instance_id (int) -> npc instance_id (int)

static func claim_item(item: Node, npc: Node) -> bool:
	if item == null or npc == null:
		return false
	var iid: int = item.get_instance_id()
	var claimant: int = _claims.get(iid, 0)
	if claimant != 0 and claimant != npc.get_instance_id():
		return false   ## already claimed by someone else
	_claims[iid] = npc.get_instance_id()
	return true

static func release_item(item: Node) -> void:
	if item == null:
		return
	_claims.erase(item.get_instance_id())

static func is_claimed_by_other(item: Node, npc: Node) -> bool:
	if item == null:
		return false
	var claimant: int = _claims.get(item.get_instance_id(), 0)
	return claimant != 0 and claimant != npc.get_instance_id()

# ─── Target search ────────────────────────────────────────────────────────
## Nearest loose (world) item matching `filter: Callable(item) -> bool`.
## Excludes held, shelved, and frozen items — an NPC can never steal from
## the player's hands or bypass the shelf API. Also respects item claims.
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
		if is_claimed_by_other(rb, npc):
			continue
		if not filter.call(rb):
			continue
		var d: float = flat_distance(rb.global_position, npc.global_position)
		if d < best_d:
			best_d = d
			best = rb
	return best

## Nearest shelf slot whose TOP item matches filter.
## Returns {} or {shelf: Shelving, slot: int, item: RigidBody3D}.
## Also respects item claims.
static func find_shelved_item(npc: NPC, filter: Callable) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for node: Node in npc.get_tree().get_nodes_in_group("shelf"):
		if not is_instance_valid(node) or not ("slots" in node):
			continue
		var d: float = flat_distance((node as Node3D).global_position, npc.global_position)
		if d >= best_d:
			continue
		for slot_idx: int in range(node.slots.size()):
			var stack: Array = node.slots[slot_idx]
			if stack.is_empty():
				continue
			var top: RigidBody3D = stack.back()
			if top == null or not is_instance_valid(top) or not filter.call(top):
				continue
			if is_claimed_by_other(top, npc):
				continue
			best_d = d
			best = {"shelf": node, "slot": slot_idx, "item": top}
			break
	return best

# ─── Carry primitives ─────────────────────────────────────────────────────
static func grab_loose(npc: NPC, item: RigidBody3D) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if is_claimed_by_other(item, npc):
		return false   ## defense in depth — shouldn't happen if callers claimed first
	## The actual missing guard: an item claimed by this NPC can still
	## have been physically picked up by the player between the claim and
	## now. Claims only block other NPCs' claim_item() calls; they were
	## never consulted by the player's own pickup path.
	if "is_held" in item and item.is_held:
		return false
	if flat_distance(npc.global_position, item.global_position) > PICKUP_RANGE:
		return false
	if item.has_method("pickup"):
		item.pickup(npc.hold_point)
		npc.held_item = item
		return true
	return false

static func grab_from_shelf(npc: NPC, shelf: Node, slot: int) -> bool:
	if shelf == null or not is_instance_valid(shelf):
		return false
	if flat_distance(npc.global_position, (shelf as Node3D).global_position) > SHELF_RANGE:
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
	return item.has_method("take_drink") and ("current_fill_mL" in item) \
		and item.current_fill_mL > 0.0

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

# ─── Give/Takeaway helpers (Part 24) ────────────────────────────────────────
## Give (player → NPC). Reuses the exact same classifiers self-serve
## eating/drinking already uses (is_edible/is_drinkable_bottle), rather
## than re-deriving the logic — this also correctly excludes an
## already-empty can/bottle from being offered as a "gift" for free,
## since both classifiers already require remaining charge.
static func is_giveable(item: Node) -> bool:
	return is_edible(item) or is_drinkable_bottle(item)

## Takeaway (player steals mid-consumption). Which live NPC (if any) is
## currently holding this exact item — used both to gate the pickup
## prompt/action and to notify the right NPC once it's taken. A plain
## Node scan of the "npc" group; cheap at bunker-sized NPC counts.
static func find_holder(item: Node, tree: SceneTree) -> Node:
	if item == null:
		return null
	for npc: Node in tree.get_nodes_in_group("npc"):
		if is_instance_valid(npc) and ("held_item" in npc) and npc.held_item == item:
			return npc
	return null


# ─── Relationship Snatch (Part 29) ──────────────────────────────────────────
## Snatch now goes through the exact same transfer path Give uses
## (Player.release_held_item_to_npc(), which wraps InteractionSystem's
## release_held_item_to_npc()) — no more separate pickup/inventory logic
## duplicated here. This is deliberately still a SEPARATE function from
## grab_loose() (whose is_held guard should stay strict) — this is the
## one intentional exception, reached only via SnatchActivity, itself
## only ever entered through NPC.find_player_snatch_target()'s gate (or
## the F7 debug override).
static func snatch_from_player(npc: NPC, player: Node) -> bool:
	if npc.held_item != null:
		return false   ## hands already full
	if player == null or not is_instance_valid(player) or not player.has_method("get_held_item"):
		return false
	var item: Node = player.get_held_item()
	if item == null or not is_instance_valid(item):
		return false
	if flat_distance(npc.global_position, (player as Node3D).global_position) > PICKUP_RANGE:
		return false
	if not player.has_method("release_held_item_to_npc"):
		return false
	return player.release_held_item_to_npc(npc)