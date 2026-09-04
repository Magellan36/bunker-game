extends RefCounted
class_name FarmingShopHelper
## FarmingShopHelper.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §8.3. The "Farming" toolbar tool is a genuinely
## different code path from every other build tool — buy → spawn near player,
## no ghost preview, no grid-snap cursor, no spawn_structure() call at all.
## Split into its own small RefCounted slice (same `_owner` back-reference
## pattern as BuildMaterials.gd/GhostPreview.gd/WallSnapHelpers.gd) rather than
## bolting it onto BuildModeController.gd directly — per this project's
## standing "no god files" rule, since it's fully self-contained.
##
## BuildModeController holds one instance (`_farming_shop`) and forwards
## `_on_farming_item_chosen(item_id)` (connected to BuildModeHUD's
## `farming_item_chosen` signal) into this file's `spawn_purchased_item()`.

var _owner: BuildModeController = null

func _init(owner: BuildModeController) -> void:
	_owner = owner

## Approximate player eye/head height + a little clearance — items spawn
## just above the player's head and fall under normal gravity/pickup rules,
## same as an ejected Used Purifier Filter (plan §8.3).
const SPAWN_HEIGHT_ABOVE_PLAYER: float = 1.8

## item_id → { name, price, kind, count, type } — kind dispatches to the
## right static spawn_at() helper. type is only meaningful for "seed".
const SHOP_ITEM_INFO: Dictionary = {
	1: { "name": "Bag of Soil",   "price": 100, "kind": "soil",  "count": 1, "type": "" },
	2: { "name": "Tomato Seeds",  "price": 25,  "kind": "seed",  "count": 1, "type": "tomato" },
	3: { "name": "Onion Seeds",   "price": 25,  "kind": "seed",  "count": 1, "type": "onion" },
	4:  { "name": "Basil Seeds",        "price": 25, "kind": "seed",  "count": 1, "type": "basil" },
	5:  { "name": "Strawberry Seeds",   "price": 25, "kind": "seed", "count": 1, "type": "strawberry" },
	6:  { "name": "Carrot Seeds",       "price": 25, "kind": "seed", "count": 1, "type": "carrot" },
	7:  { "name": "Chili Pepper Seeds", "price": 25, "kind": "seed", "count": 1, "type": "chili_pepper" },
	8:  { "name": "Bell Pepper Seeds",  "price": 25, "kind": "seed", "count": 1, "type": "bell_pepper" },
	9:  { "name": "Garlic Seeds",       "price": 25, "kind": "seed", "count": 1, "type": "garlic" },
	10: { "name": "Potato Seeds",       "price": 25, "kind": "seed", "count": 1, "type": "potato" },
	11: { "name": "Blueberry Seeds",    "price": 25, "kind": "seed", "count": 1, "type": "blueberry" },
	12: { "name": "Corn Seeds",         "price": 25, "kind": "seed", "count": 1, "type": "corn" },
	13: { "name": "Pumpkin Seeds",      "price": 25, "kind": "seed", "count": 1, "type": "pumpkin" },
	14: { "name": "Normal Fertilizer", "price": 300, "kind": "fertilizer", "count": 1, "type": "normal" },
	15: { "name": "Pro Fertilizer",    "price": 400, "kind": "fertilizer", "count": 1, "type": "pro" },
	## Resources / Miscellaneous shop items (Jul 2026) — prices are
	## placeholders, unreviewed, same convention as Grow Light/Test Sink/
	## Dispenser pricing elsewhere in this project.
	16: { "name": "Water Case", "price": 80,  "kind": "scene", "scene": "res://scenes/world/WaterCase.tscn" },
	17: { "name": "Can Case",   "price": 60,  "kind": "scene", "scene": "res://scenes/world/CanCase.tscn" },
	18: { "name": "Fuel Can",   "price": 120, "kind": "scene", "scene": "res://scenes/world/FuelCan.tscn" },
	19: { "name": "Crate",      "price": 40,  "kind": "scene", "scene": "res://scenes/world/TestCrate.tscn" },
	20: { "name": "Basket",     "price": 100, "kind": "scene", "scene": "res://scenes/world/Basket.tscn" },
	21: { "name": "Cooking Pot", "price": 120, "kind": "scene", "scene": "res://scenes/world/CookingPot.tscn" },
}

func get_item_price(item_id: int) -> int:
	return int(SHOP_ITEM_INFO.get(item_id, {}).get("price", 0))

## Deducts cost and spawns the purchased item(s) above the player's head with
## a small randomized horizontal offset (spawn_at() helpers on each item
## script already add their own per-instance jitter — this just picks the
## shared base position). Returns true on success.
func spawn_purchased_item(item_id: int) -> bool:
	var info: Dictionary = SHOP_ITEM_INFO.get(item_id, {})
	if info.is_empty():
		push_warning("FarmingShopHelper: unknown item_id %d" % item_id)
		return false

	var price: int = int(info.get("price", 0))
	if _owner.world_node != null:
		if not _owner.world_node.spend_cash(price):
			return false

	var player: Node3D = _owner.get_parent()
	var base_pos: Vector3 = player.global_position + Vector3(0.0, SPAWN_HEIGHT_ABOVE_PLAYER, 0.0)
	var parent: Node = _owner.gridmap.get_parent() if _owner.gridmap != null else _owner.get_tree().get_root()

	var kind: String = String(info.get("kind", ""))
	match kind:
		"soil":
			BagOfSoilItem.spawn_at(parent, base_pos)
		"seed":
			var type: String = String(info.get("type", "tomato"))
			SeedItem.spawn_at(parent, base_pos, type)   ## One instance, 4 charges — no more count/loop
		"fertilizer":
			var tier: String = String(info.get("type", "normal"))
			FertilizerItem.spawn_at(parent, base_pos, tier)
		"scene":
			var scene_path: String = String(info.get("scene", ""))
			var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
			spawn_scene_settled(parent, scene_path, base_pos + offset)
		_:
			push_warning("FarmingShopHelper: unhandled kind '%s' for item_id %d" % [kind, item_id])
			return false

	return true

## Atomic multi-item checkout used by the new ShopPanel.  All resources are
## validated and instantiated while detached before cash changes.  If a clear
## delivery area cannot be reserved, or any item cannot be prepared, nothing
## is charged and the cart remains intact.
func checkout_order(lines: Dictionary) -> Dictionary:
	if lines.is_empty() or _owner == null or _owner.world_node == null:
		return {"ok": false, "message": "Your cart is empty."}
	var total := 0
	var item_count := 0
	var order: Array[int] = []
	for raw_id in lines:
		var item_id := int(raw_id)
		var quantity := int(lines[raw_id])
		if not SHOP_ITEM_INFO.has(item_id) or quantity < 1 or quantity > 99:
			return {"ok": false, "message": "The cart contains an unavailable item."}
		item_count += quantity
		if item_count > ShopCart.MAX_ITEMS:
			return {"ok": false, "message": "This order is too large."}
		total += int(SHOP_ITEM_INFO[item_id]["price"]) * quantity
		for _copy in quantity:
			order.append(item_id)
	if _owner.world_node.get_cash() < total:
		return {"ok": false, "message": "Not enough cash for this order."}
	var player := _owner.get_parent() as Node3D
	var parent: Node = _owner.gridmap.get_parent() if _owner.gridmap != null else _owner.world_node
	if player == null or parent == null or not parent.is_inside_tree():
		return {"ok": false, "message": "Delivery is currently unavailable."}
	var positions := _delivery_positions(player, item_count)
	if positions.size() != item_count:
		return {"ok": false, "message": "Clear some space near the player for delivery."}
	var prepared: Array[Node3D] = []
	for item_id in order:
		var node := _prepare_item(item_id)
		if node == null:
			for prior in prepared:
				prior.free()
			return {"ok": false, "message": "One of those items could not be prepared."}
		prepared.append(node)
	if not _owner.world_node.spend_cash(total):
		for node in prepared:
			node.free()
		return {"ok": false, "message": "Not enough cash for this order."}
	for i in prepared.size():
		parent.add_child(prepared[i])
		prepared[i].global_position = positions[i]
	return {"ok": true, "message": "%d item%s delivered nearby." % [item_count, "" if item_count == 1 else "s"], "total": total}

func _prepare_item(item_id: int) -> Node3D:
	var info: Dictionary = SHOP_ITEM_INFO[item_id]
	match String(info.get("kind", "")):
		"soil":
			return BagOfSoilItem.new()
		"seed":
			var seed := SeedItem.new()
			seed.seed_type = String(info.get("type", "tomato"))
			return seed
		"fertilizer":
			var fertilizer := FertilizerItem.new()
			fertilizer.tier = String(info.get("type", "normal"))
			return fertilizer
		"scene":
			var path := String(info.get("scene", ""))
			if not ResourceLoader.exists(path):
				return null
			var packed := load(path) as PackedScene
			return packed.instantiate() as Node3D if packed != null else null
	return null

func _delivery_positions(player: Node3D, count: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var space := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	for ring in range(1, 8):
		var samples := ring * 8
		for sample in samples:
			if result.size() >= count:
				return result
			var angle := TAU * float(sample) / float(samples)
			var flat := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * (1.1 + ring * 0.55)
			var ray := PhysicsRayQueryParameters3D.create(flat + Vector3.UP * 2.5, flat + Vector3.DOWN * 2.5, 1, exclude)
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < 0.8:
				continue
			var point: Vector3 = hit.position + Vector3.UP * 0.45
			var clear := true
			var box := BoxShape3D.new()
			box.size = Vector3(0.75, 0.7, 0.75)
			var shape_query := PhysicsShapeQueryParameters3D.new()
			shape_query.shape = box
			shape_query.transform = Transform3D(Basis.IDENTITY, point)
			shape_query.collision_mask = 7
			shape_query.exclude = exclude
			if not space.intersect_shape(shape_query, 1).is_empty():
				clear = false
			for accepted in result:
				if accepted.distance_to(point) < 0.8:
					clear = false
					break
			if clear:
				result.append(point)
	return result

## Loads a scene, adds it to the tree, and positions it — same pattern as
## SeedItem.spawn_at() / BagOfSoilItem.spawn_at() / FertilizerItem.spawn_at()
## / EmptyBagItem.spawn_at() (no freeze, no raycast, no physics-frame waits).
## Those four have never had a spawn-flicker problem; the freeze/kinematic
## dance this function used to do was the one piece of machinery not present
## in any of them, and is what's been interfering with the position write —
## see the plan doc for the full trace. Single source of truth for scene-based item spawns.
static func spawn_scene_settled(parent: Node, scene_path: String, pos: Vector3) -> Node3D:
	if not ResourceLoader.exists(scene_path):
		push_warning("FarmingShopHelper: scene not found: %s" % scene_path)
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_warning("FarmingShopHelper: failed to load: %s" % scene_path)
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		push_warning("FarmingShopHelper: instantiate failed: %s" % scene_path)
		return null
	parent.add_child(node)
	node.global_position = pos
	return node
