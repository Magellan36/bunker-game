extends RefCounted
class_name NPCJobQueries
## NPCJobQueries.gd (Aug 2026) — every "does this NPC have a Cleaning/
## Refuel/Gardening target available, and where" query, extracted out of
## NPC.gd (which was 2,681 lines and still growing with every new job
## type). Mirrors NPCItemUser.gd's own established static-utility-class
## shape exactly — every function takes `npc: NPC` as its first
## parameter. NPC.gd keeps thin one-line delegating wrappers with the
## SAME names/signatures it always had, so nothing calling
## npc.find_cleaning_target(...) etc. anywhere else in the codebase
## needs to change — only the implementation moved.

const ORGANIZE_DESTINATION_GROUPS: Dictionary = {
	"light": ["shelving"],
	"heavy": ["shelving"],
}

static func has_cleaning_target_available(npc: NPC) -> bool:
	if not JobBoard.get_trash_items().is_empty():
		return true
	return not JobBoard.get_organizable_items().is_empty()

static func find_cleaning_target(npc: NPC, exclude_ids: Dictionary = {}, exclude_categories: Dictionary = {}) -> Dictionary:
	var candidates: Array = []
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, npc):
			continue
		if exclude_ids.has(item.get_instance_id()) or npc.job_state.is_cleaning_blacklisted(item.get_instance_id()):
			continue
		candidates.append({"item": item, "is_trash": true,
			"d": NPCItemUser.flat_distance(npc.global_position, (item as Node3D).global_position)})
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, npc):
			continue
		if exclude_ids.has(item.get_instance_id()) or npc.job_state.is_cleaning_blacklisted(item.get_instance_id()):
			continue
		if not exclude_categories.is_empty() and exclude_categories.has(classify_organizable_item(item)):
			continue
		candidates.append({"item": item, "is_trash": false,
			"d": NPCItemUser.flat_distance(npc.global_position, (item as Node3D).global_position)})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return a["d"] < b["d"])

	var fallback: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if _has_clear_approach(npc, c["item"]):
			return {"item": c["item"], "is_trash": c["is_trash"]}
	return {"item": fallback["item"], "is_trash": fallback["is_trash"]}

static func _has_clear_approach(npc: NPC, item: Node) -> bool:
	var space_state: PhysicsDirectSpaceState3D = npc.get_world_3d().direct_space_state
	var from: Vector3 = npc.global_position + Vector3(0.0, 0.9, 0.0)
	var to: Vector3 = (item as Node3D).global_position + Vector3(0.0, 0.2, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [npc.get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return true
	var hit: Object = result.get("collider")
	if hit == item:
		return true
	return not (hit is Node and (hit as Node).is_in_group("pickup"))

static func classify_organizable_item(item: RigidBody3D) -> String:
	if item != null and item.is_in_group("inventory_item"):
		return "light"
	return "heavy"

static func find_cleaning_destination(npc: NPC, is_trash: bool, item: RigidBody3D = null) -> Node:
	var group_names: Array = ["trash_receptacle"] if is_trash \
		else ORGANIZE_DESTINATION_GROUPS.get(classify_organizable_item(item), ["shelving"])

	var prefer_light_storage: bool = not is_trash and item != null \
		and classify_organizable_item(item) == "light"
	if prefer_light_storage:
		var light_pick: Node = _nearest_cleaning_destination(npc, group_names, item, is_trash, true)
		if light_pick != null:
			return light_pick
	return _nearest_cleaning_destination(npc, group_names, item, is_trash, false)

static func _nearest_cleaning_destination(npc: NPC, group_names: Array, item: RigidBody3D, is_trash: bool, light_storage_only: bool) -> Node:
	var best: Node = null
	var best_d: float = INF
	for group_name: String in group_names:
		for candidate: Node in npc.get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(candidate):
				continue
			if light_storage_only and not (candidate is LightStorage):
				continue
			if not is_trash and item != null and candidate.has_method("has_room_for") and not candidate.has_room_for(item):
				continue
			var d: float = NPCItemUser.flat_distance(npc.global_position, (candidate as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = candidate
	return best

static func has_viable_destination_for_category(npc: NPC, category: String) -> bool:
	var group_names: Array = ORGANIZE_DESTINATION_GROUPS.get(category, ["shelving"])
	for group_name: String in group_names:
		for candidate: Node in npc.get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(candidate):
				continue
			if category == "heavy" and candidate is LightStorage:
				continue
			if candidate.has_method("has_free_space") and not candidate.has_free_space():
				continue
			return true
	return false

static func get_cleaning_unavailable_reason(npc: NPC) -> String:
	var trash: Array = JobBoard.get_trash_items()
	var organizable: Array = JobBoard.get_organizable_items()
	if trash.is_empty() and organizable.is_empty():
		if JobBoard.get_trash_blocked_by_no_receptacle_count() > 0:
			return "NO_TRASH_RECEPTACLE"
		if JobBoard.get_pending_cleaning_count() > 0:
			return "STILL_SETTLING"
		return "NOTHING_TO_CLEAN"
	var target: Dictionary = find_cleaning_target(npc)
	if target.is_empty():
		return "ALL_CLAIMED"
	if not bool(target.get("is_trash", false)):
		var item: RigidBody3D = target.get("item")
		if find_cleaning_destination(npc, false, item) == null:
			var category: String = classify_organizable_item(item)
			if not has_viable_destination_for_category(npc, category):
				return "NO_LIGHT_STORAGE_AVAILABLE" if category == "light" else "NO_HEAVY_STORAGE_AVAILABLE"
			return "STORAGE_FULL"
	return ""

static func find_next_refuel_target(npc: NPC, exclude_ids: Dictionary) -> Node:
	var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return null
	var best: Node = null
	var best_d: float = INF
	for gen: Node in npc.get_tree().get_nodes_in_group("generator"):
		if not is_instance_valid(gen):
			continue
		var gid: int = gen.get_instance_id()
		if exclude_ids.has(gid):
			continue
		var fuel: float = pm.get_generator_fuel(str(gid))
		if fuel >= 100.0:
			continue
		var d: float = NPCItemUser.flat_distance(npc.global_position, (gen as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = gen
	return best

static func get_refuel_unavailable_reason(npc: NPC) -> String:
	var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
	var any_needs_fuel: bool = false
	if pm != null:
		for gen: Node in npc.get_tree().get_nodes_in_group("generator"):
			if not is_instance_valid(gen):
				continue
			if pm.get_generator_fuel(str(gen.get_instance_id())) < 100.0:
				any_needs_fuel = true
				break
	if not any_needs_fuel:
		return "ALL_GENERATORS_FULL"
	if npc.held_item != null and npc.held_item.has_method("refuel_tick"):
		return ""
	var filt: Callable = Callable(NPCItemUser, "is_spare_fuel_can")
	if NPCItemUser.find_loose_item(npc, filt) != null:
		return ""
	if not NPCItemUser.find_shelved_item(npc, filt).is_empty():
		return ""
	for node: Node in npc.get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(node) or node.is_in_group("shelved"):
			continue
		if "is_held" in node and node.is_held:
			continue
		if NPCItemUser.is_spare_fuel_can(node) and NPCItemUser.is_claimed_by_other(node, npc):
			return "FUEL_CAN_CLAIMED"
	return "NO_FUEL_CAN"

static func has_refuel_target_available(npc: NPC) -> bool:
	var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return false
	var urgent_exists: bool = false
	for gen: Node in npc.get_tree().get_nodes_in_group("generator"):
		if not is_instance_valid(gen):
			continue
		if pm.get_generator_fuel(str(gen.get_instance_id())) < NPC.REFUEL_URGENT_BELOW:
			urgent_exists = true
			break
	if not urgent_exists:
		return false
	if npc.held_item != null and npc.held_item.has_method("refuel_tick"):
		return true
	var filt: Callable = Callable(NPCItemUser, "is_spare_fuel_can")
	return NPCItemUser.find_loose_item(npc, filt) != null \
		or not NPCItemUser.find_shelved_item(npc, filt).is_empty()

static func has_gardening_target_available(npc: NPC) -> bool:
	var any_tray: bool = false
	var needs_soil: bool = false
	var needs_plant: bool = false
	for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray):
			continue
		any_tray = true
		if tray.has_open_soil_cell():
			needs_soil = true
		if tray.has_open_plantable_cell():
			needs_plant = true
		if needs_soil and needs_plant:
			break
	if not any_tray:
		return false
	if needs_soil:
		for item: Node in npc.get_tree().get_nodes_in_group("pickup"):
			if is_instance_valid(item) and item is BagOfSoilItem and not (("is_held" in item) and item.is_held) and not item.is_in_group("shelved"):
				return true
		for shelf: Node in npc.get_tree().get_nodes_in_group("shelving"):
			if not is_instance_valid(shelf) or not ("slots" in shelf):
				continue
			for stack in shelf.slots:
				if stack is Array and not stack.is_empty() and stack.back() is BagOfSoilItem:
					return true
	if needs_plant:
		for item: Node in npc.get_tree().get_nodes_in_group("pickup"):
			if is_instance_valid(item) and item is SeedItem and not (("is_held" in item) and item.is_held) and not item.is_in_group("shelved"):
				return true
		for shelf: Node in npc.get_tree().get_nodes_in_group("shelving"):
			if not is_instance_valid(shelf) or not ("slots" in shelf):
				continue
			for stack in shelf.slots:
				if stack is Array and not stack.is_empty() and stack.back() is SeedItem:
					return true
	return false

static func is_trash_item(_npc: NPC, item: Node) -> bool:
	return JobBoard._is_trash_item(item) if JobBoard.has_method("_is_trash_item") else false
