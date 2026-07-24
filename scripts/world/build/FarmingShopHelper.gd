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
	1: { "name": "Bag of Soil",       "price": 100, "kind": "soil",  "count": 1, "type": "" },
	2: { "name": "Tomato Seeds (x4)", "price": 25,  "kind": "seed",  "count": 4, "type": "tomato" },
	3: { "name": "Onion Seeds (x4)",  "price": 25,  "kind": "seed",  "count": 4, "type": "onion" },
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
			var count: int = int(info.get("count", 1))
			var type: String = String(info.get("type", "tomato"))
			for i: int in range(count):
				SeedItem.spawn_at(parent, base_pos, type)
		_:
			push_warning("FarmingShopHelper: unhandled kind '%s' for item_id %d" % [kind, item_id])
			return false

	return true
