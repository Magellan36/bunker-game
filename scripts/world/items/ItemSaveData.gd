class_name ItemSaveData
## ItemSaveData.gd
## Static helpers for serializing PickupableItem instances into JSON-safe
## Dictionaries (for SaveManager's inventory/storage fields) and spawning a
## fresh instance back from that Dictionary.
##
## Contract with the item scripts (see PickupableItem.gd's own save/load
## section for the base no-ops):
##   - get_item_save_state() -> Dictionary   called at save time on live items
##   - apply_item_save_state(state)          called on a fresh instance BEFORE
##                                           it enters the tree, so _ready()
##                                           builds correct visuals/prompts
##   - sync_saved_state_visuals()            optional post-_ready visual fix-up
##                                           (empty-model swap, case depletion)
##
## An item spec looks like:
##   { "script": "res://scripts/world/items/SeedItem.gd",
##     "scene":  "res://scenes/world/FoodCan.tscn",     # optional
##     "state":  { ...per-item fields... },             # optional
##     "player_placed_h": 37.5 }                        # optional (see capture)

## Captures `item`'s identity + per-item state into a JSON-safe Dictionary.
## Returns {} if the item has no recognizable script (defensive — callers
## should skip empty specs).
static func capture(item: Node) -> Dictionary:
	if item == null or not is_instance_valid(item):
		return {}
	var spec: Dictionary = {}
	var sc: Script = item.get_script()
	if sc != null:
		spec["script"] = sc.resource_path
	if "scene_file_path" in item and item.scene_file_path != "":
		spec["scene"] = item.scene_file_path
	if item.has_method("get_item_save_state"):
		var st: Dictionary = item.call("get_item_save_state")
		if not st.is_empty():
			spec["state"] = st
	## Oct 2026: when the player last put it away (game hours, NPCClock):
	## residents leave it alone for a game day (NPC StorageProfile.pinned).
	if item.has_meta("player_placed_h"):
		spec["player_placed_h"] = float(item.get_meta("player_placed_h"))
	return spec

## Spawns a fresh item from a spec returned by capture(). Adds it to `parent`
## and (after _ready has run) calls sync_saved_state_visuals() if the item
## implements it. Returns the item node, or null on failure.
static func spawn(spec: Dictionary, parent: Node) -> Node:
	if spec.is_empty():
		return null
	var item: Node = null
	var scene_path: String = String(spec.get("scene", ""))
	if scene_path != "":
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			push_warning("ItemSaveData: scene missing at '%s'" % scene_path)
			return null
		item = packed.instantiate()
	else:
		var script_path: String = String(spec.get("script", ""))
		var scr: Script = load(script_path) as Script
		if scr == null:
			push_warning("ItemSaveData: script missing at '%s'" % script_path)
			return null
		item = scr.new()
	if item == null:
		return null
	if spec.has("player_placed_h"):
		item.set_meta("player_placed_h", float(spec["player_placed_h"]))
	if spec.has("state") and item.has_method("apply_item_save_state"):
		item.call("apply_item_save_state", spec["state"])
	parent.add_child(item)
	if item.has_method("sync_saved_state_visuals"):
		item.call("sync_saved_state_visuals")
	return item

## JSON-safe variant used by containers that hold loose items whose exact
## script path must survive (matches save/load vector handling elsewhere —
## caller passes a Vector3 already converted via SaveManager.vec3_to_dict).
static func capture_with_state(item: Node) -> Dictionary:
	return capture(item)