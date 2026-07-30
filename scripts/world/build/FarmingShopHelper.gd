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
			spawn_scene_settled(_owner, parent, scene_path, base_pos + offset)
		_:
			push_warning("FarmingShopHelper: unhandled kind '%s' for item_id %d" % [kind, item_id])
			return false

	return true

## Shared spawn helper — waits for a physics frame BEFORE raycasting, so the
## raycast runs inside a physics-safe window (the UI button press that leads
## here runs on the main thread, where space_state.intersect_ray() silently
## fails with "space is locked"). After raycasting to the floor, waits one
## more physics frame before unfreezing so the settled position registers.
## Static so AdminSpawnMenu can call it directly without constructing a
## FarmingShopHelper instance.
##
## Parameters:
##   anchor  — any Node3D already in the scene tree (used to get world_3d)
##   parent  — node to add the spawned item as a child of
##   scene_path — path to the .tscn to instantiate
##   pos     — initial spawn position (raycast origin)
## Returns: the instantiated Node3D (or null on failure)
static func spawn_scene_settled(anchor: Node3D, parent: Node, scene_path: String, pos: Vector3) -> Node3D:
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
	if node is RigidBody3D:
		var rb: RigidBody3D = node as RigidBody3D
		rb.freeze      = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	parent.add_child(node)
	## Wait for a physics frame FIRST so the raycast below runs in a
	## physics-safe window — otherwise space_state.intersect_ray() fails
	## with "space is locked" because we're still on the main thread.
	await anchor.get_tree().physics_frame
	node.global_position = _find_floor_position(anchor, pos)
	if node is RigidBody3D:
		var rb2: RigidBody3D = node as RigidBody3D
		rb2.linear_velocity  = Vector3.ZERO
		rb2.angular_velocity = Vector3.ZERO
		## One more physics frame before unfreezing so the settled
		## position registers before gravity takes over.
		await anchor.get_tree().physics_frame
		if is_instance_valid(rb2):
			rb2.freeze = false
	return node

## Raycasts straight down from from_pos looking for the floor (collision
## layer 1) and returns a point 0.05m above whatever it hits. Falls back to
## from_pos unchanged if nothing is hit within 20m. Must only be called from
## a physics-safe window — see spawn_scene_settled() above.
static func _find_floor_position(anchor: Node3D, from_pos: Vector3) -> Vector3:
	var space_state: PhysicsDirectSpaceState3D = anchor.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_pos, from_pos + Vector3.DOWN * 20.0)
	query.collision_mask = 1
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return from_pos
	return (result["position"] as Vector3) + Vector3(0.0, 0.05, 0.0)
