extends RefCounted
class_name NPCItemUser
## NPCItemUser.gd  (NPC Pass 2, Part 3)
## Carry/fetch/consume helpers shared by every activity that touches items
## (Drink/Eat here; Part 4's fetch-based jobs reuse find/pickup/drop as-is).
## All world mutation goes through the SAME item methods the player uses.

const PICKUP_RANGE: float = 1.2      ## must be this close to grab — tuned for small loose items (cans, bottles, tools); left untouched, see SHELF_RANGE's own comment
const SHELF_RANGE:  float = 2.0      ## Aug 2026 — was 1.6. Brannon: NPCs were visibly walking into/pushing against shelves and other furniture for a second or two before the range check passed. Furniture/job targets got a wider 'close enough' tolerance; small loose-item ranges (PICKUP_RANGE, EatActivity/DrinkActivity's USE_RANGE) deliberately weren't touched — those already felt fine and a single can/bottle looks wrong grabbed from further away.

## Snatch specifically needs more clearance than PICKUP_RANGE — that
## constant is tuned for loose items with near-zero collision footprint;
## the player has real collision geometry, so using the same tight
## distance walks the NPC into physical contact before the range check
## is satisfied.
const SNATCH_RANGE: float = 1.6

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

## Extra reach allowed once navigation has taken the NPC as close as it can.
const REACH_LENIENCY: float = 0.9

## "Close enough to act on `target_pos`". Within `reach`, OR navigation has
## finished (the navmesh can get no closer — bulky crates, shelves and
## trays against walls sit partly inside their own nav obstacle) and we're
## within reach + REACH_LENIENCY. Without the second clause an NPC would
## stand forever a few centimetres outside a fixed range it could never
## close (the "frozen, picking up a crate" bug).
static func in_reach(npc: NPC, target_pos: Vector3, reach: float) -> bool:
	var d: float = flat_distance(npc.global_position, target_pos)
	if d <= reach:
		return true
	return npc.nav_finished() and d <= reach + REACH_LENIENCY

# ─── Reservations (Part 12, reworked Sep 2026) ─────────────────────────────
## Prevents two NPCs from targeting/grabbing the same item (or stove, etc.)
## at once. Keyed by instance_id so it works uniformly for loose items,
## shelf contents and furniture.
##
## Sep 2026 rework — reservations are now SELF-HEALING. They used to be
## released only if every code path remembered to, and several didn't (a
## half-eaten can, an item a cleaner shelved, a GiveToFriend hand-off...),
## which left items permanently invisible to every other NPC — the "there's
## food on the shelf but nobody eats it" class of bug. Three guarantees now:
##   1. NPCBrain calls release_all_for(npc) every time an activity ends, by
##      ANY path (finish, interrupt, command, pass-out, stuck-recovery).
##      A reservation can never outlive the activity that made it.
##   2. drop_held()/store_held()/hand_over() release the item they move.
##   3. A reservation whose owner NPC no longer exists is treated as free.
static var _claims: Dictionary = {}   ## item instance_id (int) -> npc instance_id (int)

static func _owner_alive(owner_iid: int) -> bool:
	if owner_iid == 0:
		return false
	var o: Object = instance_from_id(owner_iid)
	return o != null and is_instance_valid(o)

static func claim_item(item: Node, npc: Node) -> bool:
	if item == null or npc == null or not is_instance_valid(item):
		return false
	var iid: int = item.get_instance_id()
	var claimant: int = _claims.get(iid, 0)
	if claimant != 0 and claimant != npc.get_instance_id() and _owner_alive(claimant):
		return false   ## already claimed by someone else
	_claims[iid] = npc.get_instance_id()
	return true

## Seconds this item has been carried toward storage without getting there,
## kept on the item so restarting the activity (stuck recovery, a need)
## doesn't reset it. Past CARRY_LIMIT_S the carrier gives up on that storage.
const CARRY_LIMIT_S: float = 40.0
static func add_carry_time(item: Node, seconds: float) -> float:
	if item == null or not is_instance_valid(item):
		return 0.0
	var t: float = float(item.get_meta("_carry_s", 0.0)) + seconds
	item.set_meta("_carry_s", t)
	return t

static func clear_carry_time(item: Node) -> void:
	if item != null and is_instance_valid(item) and item.has_meta("_carry_s"):
		item.remove_meta("_carry_s")

## Storage someone else is using right now: wait a couple of metres back
## (true = waiting this frame) instead of squeezing in beside them.
static func wait_turn_at(npc: NPC, destination: Node, delta: float) -> bool:
	if not is_claimed_by_other(destination, npc):
		claim_item(destination, npc)
		return false
	if flat_distance(npc.global_position, (destination as Node3D).global_position) < 2.6:
		npc.halt_movement(delta)
	else:
		npc.nav_steer(delta)
	return true

static func release_item(item: Node) -> void:
	if item == null:
		return
	_claims.erase(item.get_instance_id())

static func is_claimed_by_other(item: Node, npc: Node) -> bool:
	if item == null:
		return false
	var claimant: int = _claims.get(item.get_instance_id(), 0)
	return claimant != 0 and claimant != npc.get_instance_id() and _owner_alive(claimant)

## Drops EVERY item and cell reservation owned by this NPC. Called by
## NPCBrain whenever an activity ends — see guarantee 1 above.
static func release_all_for(npc: Node) -> void:
	if npc == null:
		return
	var owner: int = npc.get_instance_id()
	for k in _claims.keys():
		if int(_claims[k]) == owner:
			_claims.erase(k)
	for k in _cell_claims.keys():
		if int(_cell_claims[k]) == owner:
			_cell_claims.erase(k)

## Number of live reservations held by this NPC (debug dumps / tests).
static func count_claims_for(npc: Node) -> int:
	var owner: int = npc.get_instance_id()
	var n: int = 0
	for v in _claims.values():
		if int(v) == owner:
			n += 1
	for v in _cell_claims.values():
		if int(v) == owner:
			n += 1
	return n

# ─── Per-cell claim system (Aug 2026) ──────────────────────────────────────
## Same shape as the item claims above, but for a specific farming-tray
## CELL rather than a Node — a cell isn't its own object to claim
## directly. Needed once GardeningActivity operates per-cell (soil in
## cell 0, planting in cell 1 of the same double tray can now be worked
## by two different NPCs simultaneously) — without this, two NPCs could
## both decide the SAME cell needs attention and both walk over before
## either discovers the other got there first.
static var _cell_claims: Dictionary = {}   ## "tray_instance_id:cell_index" -> npc instance_id (int)

static func _cell_key(tray: Node, cell_index: int) -> String:
	return "%d:%d" % [tray.get_instance_id(), cell_index]

static func claim_cell(tray: Node, cell_index: int, npc: Node) -> bool:
	if tray == null or npc == null:
		return false
	var key: String = _cell_key(tray, cell_index)
	var claimant: int = _cell_claims.get(key, 0)
	if claimant != 0 and claimant != npc.get_instance_id() and _owner_alive(claimant):
		return false
	_cell_claims[key] = npc.get_instance_id()
	return true

static func release_cell(tray: Node, cell_index: int, npc: Node) -> void:
	if tray == null or cell_index < 0:
		return
	var key: String = _cell_key(tray, cell_index)
	if _cell_claims.get(key, 0) == npc.get_instance_id():
		_cell_claims.erase(key)

static func is_cell_claimed_by_other(tray: Node, cell_index: int, npc: Node) -> bool:
	if tray == null or cell_index < 0:
		return false
	var claimant: int = _cell_claims.get(_cell_key(tray, cell_index), 0)
	return claimant != 0 and claimant != npc.get_instance_id() and _owner_alive(claimant)

# ─── Target search ────────────────────────────────────────────────────────
## Nearest loose (world) item matching `filter: Callable(item) -> bool`.
## Excludes held, shelved, and frozen items — an NPC can never steal from
## the player's hands or bypass the shelf API. Also respects item claims.
static func find_loose_item(npc: NPC, filter: Callable) -> RigidBody3D:
	var candidates: Array = []   ## [distance, item]
	for node: Node in npc.get_tree().get_nodes_in_group("pickup"):
		if not (node is RigidBody3D) or not is_instance_valid(node):
			continue
		var rb: RigidBody3D = node as RigidBody3D
		if rb.is_in_group("shelved") or (("is_held" in rb) and rb.is_held) or rb.freeze:
			continue
		if is_claimed_by_other(rb, npc) or npc.job_state.is_unreachable(rb):
			continue
		if not filter.call(rb):
			continue
		candidates.append([flat_distance(rb.global_position, npc.global_position), rb])
	return _nearest_reachable(npc, candidates, PICKUP_RANGE) as RigidBody3D

## Sep 2026 — nearest candidate that a real navmesh path actually gets
## within reach of. Straight-line "nearest" happily picked a can that had
## rolled into a gap behind a farming tray; the NPC walked as close as it
## could, gave up, and picked the very same can again — forever, while
## starving. Checks the few nearest candidates only (path queries aren't
## free); an unreachable one is remembered for a while (NPCJobState).
const REACH_CHECKS: int = 4

static func _nearest_reachable(npc: NPC, candidates: Array, reach: float) -> Node:
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i: int in mini(candidates.size(), REACH_CHECKS):
		var n: Node3D = candidates[i][1]
		if is_reachable(npc, n.global_position, reach):
			return n
		npc.job_state.mark_unreachable(n)
	return null

## Can the NPC walk to within `reach` of `pos`? (navmesh path end check;
## cached per NPC per physics frame.) True when no navmesh is available so
## worlds without one still behave as before.
static var _reach_cache: Dictionary = {}   ## "npc:x:z:reach" -> [physics_frame, bool]
const REACH_CACHE_FRAMES: int = 90

static func is_reachable(npc: NPC, pos: Vector3, reach: float) -> bool:
	var frame: int = Engine.get_physics_frames()
	var key: String = "%d:%d:%d:%d" % [npc.get_instance_id(), int(pos.x * 4.0), int(pos.z * 4.0), int(reach * 10.0)]
	var hit: Array = _reach_cache.get(key, [])
	if not hit.is_empty() and frame - int(hit[0]) < REACH_CACHE_FRAMES \
			and flat_distance(npc.global_position, pos) > 0.0:
		return bool(hit[1])
	var result: bool = _compute_reachable(npc, pos, reach)
	if _reach_cache.size() > 2000:
		_reach_cache.clear()
	_reach_cache[key] = [frame, result]
	return result

static func _compute_reachable(npc: NPC, pos: Vector3, reach: float) -> bool:
	var map: RID = npc.get_world_3d().navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return true
	var from: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(npc.global_position.x, 0.5, npc.global_position.z))
	var to: Vector3 = Vector3(pos.x, 0.5, pos.z)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	if path.is_empty():
		return flat_distance(npc.global_position, pos) <= reach + REACH_LENIENCY
	return flat_distance(path[path.size() - 1], pos) <= reach + REACH_LENIENCY - 0.1

## Nearest shelf slot whose TOP item matches filter.
## Returns {} or {shelf: Shelving, slot: int, item: RigidBody3D}.
## Also respects item claims.
static func find_shelved_item(npc: NPC, filter: Callable) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	## Fixed Aug 2026 — every real shelf/storage object joins "shelving"
	## (Shelving.gd, LightStorage.gd), never "shelf". This loop searched a
	## group nothing has ever joined, so it silently found nothing for
	## the entire lifetime of this function.
	for node: Node in npc.get_tree().get_nodes_in_group("shelving"):
		if not is_instance_valid(node) or not ("slots" in node):
			continue
		var d: float = flat_distance((node as Node3D).global_position, npc.global_position)
		if d >= best_d or npc.job_state.is_unreachable(node):
			continue
		if not is_reachable(npc, (node as Node3D).global_position, SHELF_RANGE):
			npc.job_state.mark_unreachable(node)
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

## Aug 2026 — generic fetch-target resolution, loose-first then shelved.
## Every fetch-based job (Eat/Drink/filter-replace/Refuel/Gardening)
## should resolve its search through this ONE function instead of each
## hand-rolling the same find_loose_item -> find_shelved_item fallback
## chain independently. Cleaning is the deliberate exception — it only
## ever PUTS items INTO storage, never searches storage to take
## something OUT, so it has no reason to call this.
## Returns {} (nothing found anywhere), {"loose": RigidBody3D}, or
## {"shelf": {shelf, slot, item}} (the exact shape find_shelved_item
## already returns, just wrapped so callers can tell the two cases apart
## with one is-empty/has() check instead of juggling two return values).
static func find_fetch_target(npc: NPC, filter: Callable) -> Dictionary:
	var loose: RigidBody3D = find_loose_item(npc, filter)
	if loose != null:
		return {"loose": loose}
	var shelf: Dictionary = find_shelved_item(npc, filter)
	if not shelf.is_empty():
		return {"shelf": shelf}
	return {}

# ─── Carry primitives ─────────────────────────────────────────────────────
## True while the NPC's hands genuinely hold something. Every grab path
## refuses when this is true — grabbing while already holding used to
## reparent a SECOND item onto the same hold point, orphaning the first
## (it kept floating after the NPC forever with is_held=true).
static func hands_full(npc: NPC) -> bool:
	return npc.held_item != null and is_instance_valid(npc.held_item)

## `reach`: callers fetching something bigger than a can (a case, CASE_RANGE)
## pass their own range, or the grab fails at the distance they stopped at.
static func grab_loose(npc: NPC, item: RigidBody3D, reach: float = PICKUP_RANGE) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if hands_full(npc):
		return false
	if is_claimed_by_other(item, npc):
		return false   ## defense in depth — shouldn't happen if callers claimed first
	## The actual missing guard: an item claimed by this NPC can still
	## have been physically picked up by the player between the claim and
	## now. Claims only block other NPCs' claim_item() calls; they were
	## never consulted by the player's own pickup path.
	if "is_held" in item and item.is_held:
		return false
	## Second missing guard (Aug 2026) — a shelved item has is_held=false
	## the whole time (Shelving.gd manipulates freeze/collision directly,
	## never is_held), so the check above provides it zero protection.
	## Without this, a stale claim/target reference from before an item
	## was shelved could grab it right back off the shelf, bypassing the
	## shelf's own tracking entirely — this was the actual cause of
	## shelved items "popping out" and un-freezing on their own.
	if item.is_in_group("shelved"):
		return false
	## Aug 2026 — a pot resting on a stove (placed, cooking, done, doesn't
	## matter) stays there until manually taken off. JobBoard's scan
	## already keeps Cleaning from walking toward one as a candidate (see
	## is_on_stove()'s own comment), but this covers every other path that
	## can reach grab_loose() directly — most importantly stuck-recovery's
	## forced grab, which bypasses JobBoard's eligibility scan entirely by
	## design.
	if is_on_stove(item):
		return false
	if not in_reach(npc, item.global_position, reach):
		return false
	if item.has_method("pickup"):
		item.pickup(npc.hold_point)
		npc.held_item = item
		return true
	return false

static func grab_from_shelf(npc: NPC, shelf: Node, slot: int) -> bool:
	if shelf == null or not is_instance_valid(shelf):
		return false
	if hands_full(npc):
		return false
	if not in_reach(npc, (shelf as Node3D).global_position, SHELF_RANGE):
		return false
	if not shelf.has_method("npc_retrieve"):
		return false
	var item: RigidBody3D = shelf.npc_retrieve(slot, npc.hold_point)
	if item == null:
		return false
	npc.held_item = item
	return true

## Aug 2026 — call every tick during a loose-item fetch approach, right
## before nav_steer(). Keeps the nav target in sync with the item's real
## current position — items can roll or get bumped after an NPC starts
## walking toward them (produce, fuel cans, ingredients, anything loose),
## and without this the NPC just walks to wherever the item WAS when the
## approach began, since set_nav_target() only ever captures a position
## once. Re-setting target_position to an unchanged value is a cheap
## no-op for NavigationAgent3D (only repaths on an actual change), so
## this costs nothing extra in the common case where the item hasn't
## moved.
static func track_fetch_target(npc: NPC, item: Node) -> void:
	if item != null and is_instance_valid(item):
		npc.set_nav_target((item as Node3D).global_position)

## Put whatever is held back into the world just in front of the NPC, via
## the same drop() the player uses. Always releases the item's reservation
## (Sep 2026 — a dropped item that stayed reserved was invisible to every
## other NPC forever). The drop point is pulled back toward the NPC if a
## wall is in the way, so a set-down item can never be pushed through
## geometry and lost below the floor.
static func drop_held(npc: NPC) -> void:
	var item: RigidBody3D = npc.held_item
	npc.held_item = null
	if item == null or not is_instance_valid(item):
		return
	release_item(item)
	var world: Node = npc.get_tree().get_first_node_in_group("main_world")
	var parent: Node3D = world if world is Node3D else npc.get_parent()
	if item.has_method("drop"):
		item.drop(parent, safe_drop_point(npc))
	else:
		NPCDebug.log_missing_method("NPCItemUser.drop_held()", item, "drop")

## World point ~0.6 m in front of the NPC at hand height, shortened if a
## static obstacle sits in between.
static func safe_drop_point(npc: NPC) -> Vector3:
	var origin: Vector3 = npc.global_position + Vector3(0.0, 0.2, 0.0)
	var fwd: Vector3 = -npc.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var want: Vector3 = origin + fwd * 0.6
	var space: PhysicsDirectSpaceState3D = npc.get_world_3d().direct_space_state
	if space == null:
		return want
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, want + fwd * 0.25)
	q.exclude = [npc.get_rid()]
	q.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty() or not (hit.get("collider") is StaticBody3D):
		return want
	var back: float = maxf(0.0, origin.distance_to(hit["position"]) - 0.35)
	return origin + fwd * back

## Stores the held item into a Shelving/LightStorage/trash receptacle via
## its npc_try_place_item(). Returns true on success. On success the item
## is no longer held and its reservation is released (the old per-activity
## code left stored items reserved by whoever put them away).
static func store_held(npc: NPC, destination: Node) -> bool:
	var item: RigidBody3D = npc.held_item
	if item == null or not is_instance_valid(item) or destination == null or not is_instance_valid(destination):
		return false
	if not destination.has_method("npc_try_place_item"):
		return false
	if not destination.npc_try_place_item(npc, item):
		return false
	if npc.held_item == item:
		npc.held_item = null
	release_item(item)
	return true

## Moves the giver's held item straight into the receiver's hands.
static func hand_over(giver: NPC, receiver: Node) -> Node:
	var item: Node = giver.held_item
	if item == null or not is_instance_valid(item) or not item.has_method("pickup"):
		return null
	giver.held_item = null
	release_item(item)
	item.pickup(receiver.hold_point)
	receiver.held_item = item
	return item


# ─── Consumable filters (used by activities) ──────────────────────────────
static func is_drinkable_bottle(item: Node) -> bool:
	return item.has_method("take_drink") and ("current_fill_mL" in item) \
		and item.current_fill_mL > 0.0

## Fuel-can duck-typed filter (FuelCan.gd declares no class_name — same
## reasoning as is_edible/is_drinkable_bottle above). Shared by
## RefuelActivity's fetch phase and NPC.has_refuel_target_available().
static func is_spare_fuel_can(item: Node) -> bool:
	return item.has_method("refuel_tick") and ("_fuel_remaining" in item) \
		and float(item._fuel_remaining) > 0.0

static func is_edible(item: Node) -> bool:
	if item is DishItem:
		return true
	if item is FarmProduceItem:
		return true
	if item.has_method("has_bites_left"):   ## FoodCan
		return item.has_bites_left()
	return false

## Case dispensers (Aug 2026) — duck-typed like every consumable filter
## above (neither CanCase.gd nor WaterCase.gd declares a class_name, same
## reasoning as is_spare_fuel_can's own comment). Stocked check only — an
## emptied case is left in place untouched, same as everything else that
## doesn't declare is_trash()/join "trash". Used as the last-resort fetch
## tier (loose item -> shelved item -> loose case -> shelved case) by
## EatActivity/DrinkActivity via NPCCaseFetch.
static func is_stocked_can_case(item: Node) -> bool:
	return ("can_count" in item) and int(item.can_count) > 0

static func is_stocked_water_case(item: Node) -> bool:
	return ("bottle_count" in item) and int(item.bottle_count) > 0

## Cooking ingredients, by quality (Sep 2026): fresh produce first, then a
## food can; a water bottle (CookingPot keys it "water_bottle" and turns it
## into the dish's hydration) is a soup base only, never the whole meal —
## see CookingActivity._ingredient_filters().
static func is_cookable_ingredient(item: Node) -> bool:
	return is_cookable_food(item) or is_drinkable_bottle(item)

static func is_cookable_food(item: Node) -> bool:
	return is_fresh_produce(item) or is_food_can(item)

static func is_fresh_produce(item: Node) -> bool:
	return item is FarmProduceItem

static func is_food_can(item: Node) -> bool:
	return item.has_method("has_bites_left") and item.has_bites_left()

## A Cooking Pot available to fetch — excludes one already resting on a
## stove. Confirmed Aug 2026: Stove.try_place_pot() sets is_held = false
## on the pot it hosts (matching a shelved item's own convention), so the
## is_held check alone does NOT exclude a stove-resting pot — only
## checking _host_stove directly does.
static func is_cooking_pot(item: Node) -> bool:
	if not (item is CookingPot):
		return false
	if ("_host_stove" in item) and item._host_stove != null:
		return false
	return true

## Aug 2026 fix — widened from "actively cooking" (stove powered on +
## contents) to "resting on a stove at all," per direction: a pot stays
## untouchable by Cleaning the whole time it's placed/frozen on a stove —
## empty, mid-fill, powered off, whatever — regardless of whether an NPC
## or the player put it there. Only once it's actually off the stove is
## it fair game again. No longer needs Stove.is_cooking() at all — just
## whether the pot currently has a host. Single source of truth, used by
## both grab_loose() below and JobBoard's organizable-item scan.
static func is_on_stove(item: Node) -> bool:
	return item is CookingPot and ("_host_stove" in item) and item._host_stove != null

## Apply one "consume step" of a held edible to the NPC's hunger. Returns
## true when the item is finished with (freed or empty) and the hand is clear.
static func eat_held_step(npc: NPC) -> bool:
	var item: Node = npc.held_item
	if item == null or not is_instance_valid(item):
		npc.held_item = null
		return true
	## Sep 2026 — holding something inedible (a basket, a soil bag...) used
	## to fall through to `return true` WITHOUT letting go of it, and
	## EatActivity would immediately "eat" the same item again next tick —
	## an infinite Eating loop. Set it down instead.
	if not is_edible(item):
		drop_held(npc)
		return true
	if item is DishItem or item is FarmProduceItem:
		release_item(item)
		npc.add_thought("ate_hot_meal" if item is DishItem else "ate_fresh")
		npc.hunger = minf(npc.hunger_cap, npc.hunger + item.consume_as_food())
		npc.held_item = null   ## consume_as_food frees the node
		return true
	if item.has_method("take_bite"):   ## FoodCan — multi-bite
		npc.hunger = minf(npc.hunger_cap, npc.hunger + item.take_bite())
		if not item.has_bites_left():
			npc.add_thought("ate_cold_can")
			drop_held(npc)   ## empty can — set it down (it's trash now; Cleaning takes it out)
			return true
		if npc.hunger >= 95.0:
			npc.add_thought("ate_cold_can")
			return true      ## full — keep the rest of the can in hand; PutAway stores it
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


# ─── Relationship Snatch (Part 29/Aug 2026) ──────────────────────────────
## Generalized to any target (player or NPC). Player targets still go
## through release_held_item_to_npc() (the only path with inventory-slot
## context). NPC targets are simpler — no inventory system to reconcile,
## just a direct physical reassignment plus telling the victim to clear
## their own held_item reference (mirrors what on_item_snatched() does
## for the player, at NPC scale). Reached only via SnatchActivity, which
## itself is only ever entered through NPC.find_snatch_target()'s gate
## (or the F7 debug override).
static func snatch_from(npc: NPC, target: Node) -> bool:
	if npc.held_item != null:
		return false   ## hands already full
	if target == null or not is_instance_valid(target):
		return false
	if not in_reach(npc, (target as Node3D).global_position, SNATCH_RANGE):
		return false

	if target.is_in_group("player"):
		if not target.has_method("get_held_item") or not target.has_method("release_held_item_to_npc"):
			return false
		var item: Node = target.get_held_item()
		if item == null or not is_instance_valid(item):
			return false
		return target.release_held_item_to_npc(npc)

	## NPC target
	var item: Node = target.held_item
	if item == null or not is_instance_valid(item) or not item.has_method("pickup"):
		return false
	item.pickup(npc.hold_point)
	npc.held_item = item
	if target.has_method("on_item_snatched_by_npc"):
		target.on_item_snatched_by_npc(npc)
	else:
		target.held_item = null
	return true
