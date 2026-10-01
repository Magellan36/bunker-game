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
	## Aug 2026 fix — this used to return true purely on trash items
	## EXISTING (receptacle-existence was already checked at the JobBoard
	## scan level, but a full-but-existing receptacle still passed this).
	## Same class of bug as the organizable-item fix below, now closed for
	## trash too: also confirm the receptacle actually has room right now.
	var trash: Array = JobBoard.get_trash_items()
	if not trash.is_empty():
		for receptacle: Node in npc.get_tree().get_nodes_in_group("trash_receptacle"):
			if is_instance_valid(receptacle) and (not receptacle.has_method("has_room_for") \
					or receptacle.has_room_for(trash[0])):
				return true
	## Aug 2026 fix — this used to return true purely on organizable items
	## EXISTING, never checking whether anywhere exists to actually put
	## them. With zero shelving/storage anywhere in a level, that caused
	## CleaningActivity to be re-selected and instantly fail every single
	## think-cycle (its destination-first _pick_next_target() gives up
	## without ever calling set_nav_target()/nav_steer()/halt_movement(),
	## so _movement_locked stayed false) — which _tick_stuck_recovery()
	## misread as "trying to travel and not moving," firing
	## _recover_from_stuck() every second with no real obstruction to
	## find. See NPC._recover_from_stuck()'s own fix (same pass) for what
	## that cascaded into. Checking at least one category has a live
	## destination fixes the trigger at its actual source instead.
	var organizable: Array = JobBoard.get_organizable_items()
	if organizable.is_empty():
		return false
	var checked_categories: Dictionary = {}
	for item: Node in organizable:
		if not is_instance_valid(item):
			continue
		var category: String = classify_organizable_item(item)
		if checked_categories.has(category):
			continue
		checked_categories[category] = true
		if has_viable_destination_for_category(npc, category):
			return true
	return false

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

	## Prefer an item on the outside of a pile (clear line from the NPC) over
	## a nominally nearer buried one, and never one the navmesh can't reach.
	var reachable: Array = []
	for c: Dictionary in candidates:
		if npc.job_state.is_unreachable(c["item"]):
			continue
		if reachable.size() >= NPCItemUser.REACH_CHECKS:
			break
		if NPCItemUser.is_reachable(npc, (c["item"] as Node3D).global_position, NPCItemUser.PICKUP_RANGE):
			reachable.append(c)
		else:
			npc.job_state.mark_unreachable(c["item"])
	if reachable.is_empty():
		return {}
	for c: Dictionary in reachable:
		if _has_clear_approach(npc, c["item"]):
			return {"item": c["item"], "is_trash": c["is_trash"]}
	return {"item": reachable[0]["item"], "is_trash": reachable[0]["is_trash"]}

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
			## Aug 2026 fix — a dedicated trash receptacle (TrashCan, e.g.)
			## is ALSO "shelving" for player-facing reasons that can't
			## change (MainWorld.gd's storage-UI wiring, InteractionSystem.gd's
			## F-prompt discovery both depend on that group membership) —
			## but it should never be selected as an ordinary organizable-
			## item destination from the NPC side. This is what was
			## sending full/half-charge water bottles etc. into the trash
			## can as regular tidying, nothing to do with trash
			## classification itself. Trash routing (is_trash=true) is
			## completely unaffected — this only excludes the OTHER case.
			if not is_trash and candidate.is_in_group("trash_receptacle"):
				continue
			## Aug 2026 fix — this was previously skipped for trash
			## entirely, meaning a full trash can still got picked as a
			## valid destination, walked to, and failed. Trash now gets
			## the exact same room-checked treatment a full shelf already
			## gets.
			if item != null and candidate.has_method("has_room_for") and not candidate.has_room_for(item):
				continue
			if npc.job_state.is_unreachable(candidate):
				continue
			var d: float = NPCItemUser.flat_distance(npc.global_position, (candidate as Node3D).global_position)
			## Someone's already putting things there: prefer other storage
			## (five residents used to jam one shelf in a corner).
			if NPCItemUser.is_claimed_by_other(candidate, npc):
				d += 8.0
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
			## Aug 2026 fix — same exclusion as _nearest_cleaning_destination()'s
			## own comment: a dedicated trash receptacle shouldn't count as
			## viable general-purpose light/heavy storage.
			if candidate.is_in_group("trash_receptacle"):
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

## Lowest fuel % across all generators (100 if none).
static func lowest_generator_fuel(npc: NPC) -> float:
	var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
	var lowest: float = 100.0
	if pm == null:
		return lowest
	for gen: Node in npc.get_tree().get_nodes_in_group("generator"):
		if is_instance_valid(gen):
			lowest = minf(lowest, pm.get_generator_fuel(str(gen.get_instance_id())))
	return lowest

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
	var soil_ok: bool = supply_available(npc, func(it: Node) -> bool: return it is BagOfSoilItem)
	for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray):
			continue
		for i: int in range(tray.cell_count):
			if NPCItemUser.is_cell_claimed_by_other(tray, i, npc):
				continue
			if not tray.soil_filled[i]:
				if soil_ok:
					return true
			elif tray.planted_type[i] == "" and seed_available(npc, tray.get_cell_seed_lock(i)):
				return true
	return false

## Sep 2026 — a supply "is available" only if a free (unheld, unreserved by
## someone else) item matching `filter` is loose or on a shelf, or already
## in this NPC's hands. Availability checks that ignored reservations and
## seed locks made activities win on score, find nothing in enter(), and
## re-enter every second — the "frozen gardener" loop.
static func supply_available(npc: NPC, filter: Callable) -> bool:
	if NPCItemUser.hands_full(npc) and filter.call(npc.held_item):
		return true
	return not NPCItemUser.find_fetch_target(npc, filter).is_empty()

## Seed for a cell with this lock ("" = any seed).
static func seed_available(npc: NPC, lock: String) -> bool:
	if lock == "":
		return supply_available(npc, func(it: Node) -> bool: return it is SeedItem)
	return supply_available(npc, func(it: Node) -> bool: return it is SeedItem and it.seed_type == lock)

static func is_trash_item(_npc: NPC, item: Node) -> bool:
	return JobBoard._is_trash_item(item) if JobBoard.has_method("_is_trash_item") else false

# ─── Cooking (Aug 2026) ─────────────────────────────────────────────────────
## Priority order used by CookingActivity.enter(): serve a ready dish >
## finish an in-progress pot > start a new pot on an empty stove. All three
## skip any stove currently claimed by another NPC (NPCItemUser.claim_item
## treats a Stove exactly like any other claimable Node — no new claim
## mechanism needed).
## Wired to a live power grid (switched on or not). Residents only put
## ingredients in, and switch on, a pot on a connected stove.
static func stove_connected(stove: Node) -> bool:
	return stove.has_method("npc_can_power_on") and stove.npc_can_power_on()

static func find_cooking_serve_target(npc: NPC) -> Node:
	var best: Node = null
	var best_d: float = INF
	for stove: Node in npc.get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(stove):
			continue
		if NPCItemUser.is_claimed_by_other(stove, npc):
			continue
		var pot: Node = stove.pot_ref
		if pot == null or not pot.has_method("is_dish_ready") or not pot.is_dish_ready():
			continue
		var d: float = NPCItemUser.flat_distance(npc.global_position, (stove as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = stove
	return best

static func find_cooking_ingredient_target(npc: NPC) -> Node:
	var best: Node = null
	var best_d: float = INF
	for stove: Node in npc.get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(stove):
			continue
		if NPCItemUser.is_claimed_by_other(stove, npc):
			continue
		if not stove_connected(stove):
			continue   ## never load a pot that can't be cooked
		var pot: Node = stove.pot_ref
		if pot == null or not pot.has_method("is_full") or pot.is_full():
			continue
		if pot.has_method("is_dish_ready") and pot.is_dish_ready():
			continue   ## already done cooking, waiting to be served — not an ingredient target
		var d: float = NPCItemUser.flat_distance(npc.global_position, (stove as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = stove
	return best

## Aug 2026 — a stove whose pot has ≥1 ingredient but isn't powered on
## (e.g. the last attempt found it unpowered and left it exactly as-is,
## per the leave-and-recheck model). find_cooking_ingredient_target()
## above skips a FULL pot entirely, and find_cooking_pot_target() below
## skips any stove that already has a pot — so without this tier, a
## fully-loaded, never-lit pot would be invisible to every future "Cook a
## meal" command. Ranked above find_cooking_pot_target() (retrying a
## near-finished stove beats starting a brand new one).
static func find_cooking_needs_power_target(npc: NPC) -> Node:
	var best: Node = null
	var best_d: float = INF
	for stove: Node in npc.get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(stove):
			continue
		if NPCItemUser.is_claimed_by_other(stove, npc):
			continue
		if stove.powered_on or not stove_connected(stove):
			continue   ## an unplugged stove is never "cooked on" — see stove_connected()
		if NPCClock.now() < float(stove.get_meta("_npc_unpowered_until", -1.0)):
			continue   ## tried recently and there's no power — don't retry every few seconds
		var pot: Node = stove.pot_ref
		if pot == null or not pot.has_method("count_filled") or pot.count_filled() <= 0:
			continue
		if pot.has_method("is_dish_ready") and pot.is_dish_ready():
			continue   ## shouldn't happen (serve tier catches this first) — stay defensive
		var d: float = NPCItemUser.flat_distance(npc.global_position, (stove as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = stove
	return best

static func find_cooking_pot_target(npc: NPC) -> Node:
	var best: Node = null
	var best_d: float = INF
	for stove: Node in npc.get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(stove):
			continue
		if NPCItemUser.is_claimed_by_other(stove, npc):
			continue
		if not stove.has_method("has_open_slot") or not stove.has_open_slot():
			continue
		## A pot may go on an unplugged stove (it's ready for when it's wired
		## up), but a connected stove always wins.
		var d: float = NPCItemUser.flat_distance(npc.global_position, (stove as Node3D).global_position)
		if not stove_connected(stove):
			d += 1000.0
		if d < best_d:
			best_d = d
			best = stove
	return best

## Availability check — written now (unused this pass) so a later
## autonomous-scoring pass can plug it straight into CookingActivity.score()
## the same way REFUEL/GARDENING's own has_..._available() functions
## already feed their score()s.
static func has_cooking_target_available(npc: NPC) -> bool:
	return not cooking_opportunity(npc).is_empty()

## Sep 2026 — the single source of truth for "is there cooking this NPC can
## actually do right now", shared by CookingActivity.score() AND enter().
## The old availability check said yes whenever a stove had an open pot
## slot or a non-full pot — even with no pot or no ingredient anywhere in
## the bunker — so NPCs re-entered Cooking every second and did nothing.
## Returns {"mode": "serve"|"power"|"ingredient"|"pot", "stove": Node} or {}.
## `demand_only`: skip starting/filling meals unless someone could use food.
static func cooking_opportunity(npc: NPC) -> Dictionary:
	var serve: Node = find_cooking_serve_target(npc)
	if serve != null:
		return {"mode": "serve", "stove": serve}
	var power: Node = find_cooking_needs_power_target(npc)
	if power != null:
		return {"mode": "power", "stove": power}
	## A meal needs FOOD (produce or cans — loose, stored, or still in a
	## can case). Water alone never starts a pot.
	var have_ingredient: bool = supply_available(npc, Callable(NPCItemUser, "is_cookable_food")) \
		or supply_available(npc, Callable(NPCItemUser, "is_stocked_can_case"))
	if not have_ingredient:
		return {}
	var ing: Node = find_cooking_ingredient_target(npc)
	if ing != null:
		return {"mode": "ingredient", "stove": ing}
	var pot: Node = find_cooking_pot_target(npc)
	if pot != null and supply_available(npc, Callable(NPCItemUser, "is_cooking_pot")):
		return {"mode": "pot", "stove": pot}
	return {}

## How much the bunker could use a cooked meal right now (0..1): someone is
## getting hungry, and there's no ready meal already waiting.
static func cooking_demand(npc: NPC) -> float:
	var hungriest: float = 100.0
	for other: Node in npc.get_tree().get_nodes_in_group("npc"):
		if other is NPC:
			hungriest = minf(hungriest, other.hunger)
	var dishes_waiting: int = 0
	for item: Node in npc.get_tree().get_nodes_in_group("pickup"):
		if item is DishItem and is_instance_valid(item):
			dishes_waiting += 1
	for shelf: Node in npc.get_tree().get_nodes_in_group("shelving"):
		if is_instance_valid(shelf) and "slots" in shelf:
			for stack in shelf.slots:
				if stack is Array:
					for it in stack:
						if it is DishItem:
							dishes_waiting += 1
	var residents: int = npc.get_tree().get_nodes_in_group("npc").size()
	if dishes_waiting >= maxi(1, (residents + 1) / 2):
		return 0.0   ## enough cooked food waiting
	## Meal prep: with ingredients in reach and nothing cooked waiting,
	## someone cooks even when nobody is hungry yet (a hot meal beats a
	## cold can, and it's ready before anyone needs it). Hunger adds urgency.
	var prep: float = 0.45 if dishes_waiting == 0 else 0.2
	return clampf(prep + (80.0 - hungriest) / 40.0, 0.0, 1.0)

static func get_cooking_unavailable_reason(npc: NPC) -> String:
	if has_cooking_target_available(npc):
		return ""
	for stove: Node in npc.get_tree().get_nodes_in_group("stove"):
		if is_instance_valid(stove):
			return ""   ## a stove exists, just nothing actionable right now — generic message covers it
	return "NO_STOVE"
