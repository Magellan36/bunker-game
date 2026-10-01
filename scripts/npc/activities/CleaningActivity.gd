extends NPCSessionActivity
class_name CleaningActivity
## CleaningActivity.gd — a tidying session: pick up loose clutter one item
## at a time and take it where it belongs (trash → trash can; light items →
## End Table/Dresser first, then shelves; heavy items → shelves). Loose
## produce is gathered into a Basket when one is free, and the basket is
## put away at the end.
##
## A session runs 20–40 s (or until nothing's left), then the brain
## re-scores, so cleaning interleaves naturally with everything else.
## Interruptible only BETWEEN items (nothing carried) — see interruptible().
##
## Forced variant (stuck recovery): CleaningActivity.new(item) clears exactly
## that one obstruction — carried to storage, or carried clear if there's
## nowhere for it — and ends.
##
## Sep 2026 fixes: the basket flow never actually registered the basket it
## picked up (it then re-picked a target every frame for the rest of the
## session and ended still holding the basket); delivered items stayed
## reserved by the cleaner forever; scoring moved to the shared scale.

const SESSION_MIN_SEC: float = 20.0
const SESSION_MAX_SEC: float = 40.0
const RELOCATE_DISTANCE: float = 2.5
const CLUTTER_CALM: int = 3      ## at/below this, cleaning barely registers
const CLUTTER_URGENT: int = 20   ## at/above this, cleaning is a real chore priority

var _item: RigidBody3D = null
var _destination: Node = null
var _is_trash: bool = false
var _forced_item: RigidBody3D = null
var _is_forced_session: bool = false
var _session_elapsed: float = 0.0
var _session_duration: float = 0.0
var _finished: bool = false
var _no_reach_time: float = 0.0             ## fetch: seconds at the path end without the item in reach
var _skipped_ids: Dictionary = {}           ## item instance_id -> true (nowhere to put it this session)
var _carry_time: float = 0.0
const FETCH_GIVE_UP_SECONDS: float = 20.0
var _no_storage_categories: Dictionary = {} ## "light"/"heavy"/"trash" -> true
var _basket: Basket = null                  ## held while gathering produce
var _relocating: bool = false
var _relocate_point: Vector3 = Vector3.ZERO
var _delivered: int = 0

func _init(forced_item: RigidBody3D = null) -> void:
	_forced_item = forced_item
	_is_forced_session = forced_item != null

func label() -> String:
	if _basket != null and _item != _basket:
		return "Gathering produce"
	if _item == null:
		return "Tidying up"
	if _relocating:
		return "Clearing the way"
	return "Putting away %s" % display_name(_item) if _destination != null else "Picking up %s" % display_name(_item)

## 4 at a tidy bunker → ~30 at a real mess (× work ethic etc.).
func score(npc: NPC) -> float:
	if _is_forced_session or not NPCJobQueries.has_cleaning_target_available(npc):
		return 0.0
	var clutter: float = float(JobBoard.get_total_clutter_count())
	var t: float = clampf((clutter - CLUTTER_CALM) / float(CLUTTER_URGENT - CLUTTER_CALM), 0.0, 1.0)
	return npc.work_score("CLEANING", 1.0, 4.0 + 26.0 * t * t * (3.0 - 2.0 * t))

## Safe window: between items, hands empty.
func interruptible() -> bool:
	return _item == null and _basket == null

func enter(npc: NPC) -> void:
	_carry_time = 0.0
	## The Lazy tidy an item or two and call it a day.
	_session_duration = randf_range(SESSION_MIN_SEC, SESSION_MAX_SEC) \
		* (1.0 - 0.5 * npc.get_sloth() * (1.0 - npc.social.drive()))
	_session_elapsed = 0.0
	_finished = false
	_skipped_ids = {}
	_no_storage_categories = {}
	_delivered = 0
	if NPCDebug.enabled and not _is_forced_session:
		NPCDebug.log_cleaning(npc, "session started", "target duration=%.0fs" % _session_duration)
	_pick_next_target(npc)

# ─── Target selection ─────────────────────────────────────────────────────
func _pick_next_target(npc: NPC) -> void:
	_destination = null
	_relocating = false
	if _is_forced_session:
		_item = _forced_item
		_forced_item = null
		if _item == null or not is_instance_valid(_item) or _item.is_in_group("shelved") \
				or (("is_held" in _item) and _item.is_held):
			_item = null
			_finished = true
			return
		_is_trash = NPCJobQueries.is_trash_item(npc, _item)
		_claim_and_go(npc)
		return

	while true:
		var result: Dictionary = NPCJobQueries.find_cleaning_target(npc, _skipped_ids, _no_storage_categories)
		## Gathering produce into a basket: only produce is fair game until
		## the basket is put away.
		if _basket != null and (result.is_empty() or not (result.get("item") is FarmProduceItem) or _basket.slots.count(null) <= 0):
			_start_delivering_basket(npc)
			return
		if result.is_empty():
			_item = null
			_finished = true
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "session ended", "nothing left to clean%s" % (
					" — no storage for: %s" % ", ".join(_no_storage_categories.keys()) if not _no_storage_categories.is_empty() else ""))
			return
		_item = result.get("item")
		_is_trash = result.get("is_trash", false)
		if _is_trash:
			if NPCJobQueries.find_cleaning_destination(npc, true, _item) != null:
				break
			_skipped_ids[_item.get_instance_id()] = true
			_no_storage_categories["trash"] = true
			continue
		if _item is FarmProduceItem and (_basket != null or _find_available_basket(npc) != null):
			break   ## goes into a basket — no shelf needed yet
		if NPCJobQueries.find_cleaning_destination(npc, false, _item) != null:
			break
		_skipped_ids[_item.get_instance_id()] = true
		var category: String = NPCJobQueries.classify_organizable_item(_item)
		if not NPCJobQueries.has_viable_destination_for_category(npc, category):
			_no_storage_categories[category] = true
	_claim_and_go(npc)

func _claim_and_go(npc: NPC) -> void:
	if not NPCItemUser.claim_item(_item, npc):
		_skipped_ids[_item.get_instance_id()] = true   ## someone else has it — pick another next tick
		_item = null
		return
	if _item.has_method("set_nav_obstacle_enabled"):
		_item.set_nav_obstacle_enabled(false)
	npc.set_nav_target(_item.global_position)
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "target picked", "%s (%s)" % [display_name(_item), "trash" if _is_trash else "organizable"])

# ─── Tick ─────────────────────────────────────────────────────────────────
func tick(npc: NPC, delta: float) -> void:
	if not _is_forced_session:
		_session_elapsed += delta
		if _session_elapsed >= _session_duration and _item == null and _basket == null:
			_finish(npc, "time's up")
			return

	## Holding something that isn't ours to carry (shouldn't happen — the
	## brain's hands policy guards entry): set it down, carry on.
	if NPCItemUser.hands_full(npc) and npc.held_item != _item and npc.held_item != _basket:
		NPCItemUser.drop_held(npc)

	if _item == null or not is_instance_valid(_item):
		_item = null
		if not _finished:
			_pick_next_target(npc)
		return

	if _basket != null and npc.held_item == _basket and _item != _basket:
		_tick_stash_into_basket(npc, delta)
		return

	if npc.held_item == _item:
		_carry_time = NPCItemUser.add_carry_time(_item, delta)   ## kept on the item across restarts
		_tick_carry(npc, delta)
		return

	## Fetch phase — hands must be empty here.
	if (("is_held" in _item) and _item.is_held) or _item.is_in_group("shelved"):
		_item = null   ## someone else got it
		return
	if _item is FarmProduceItem and _basket == null and not _is_forced_session:
		var basket: Basket = _find_available_basket(npc)
		if basket != null:
			_tick_fetch_basket(npc, delta, basket)
			return
	NPCItemUser.track_fetch_target(npc, _item)
	npc.nav_steer(delta)
	var reachable: bool = NPCItemUser.in_reach(npc, _item.global_position, NPCItemUser.PICKUP_RANGE)
	## Sep 2026: jostling in a cramped corner never "arrives", so the check
	## below never fired, and the stuck-recovery abandon restarted the try,
	## so the same item was retried for hours. 20 s in total (kept on the
	## item, per resident, across restarts) to get to it, then it's
	## remembered as out of reach.
	var fetch_key: String = "_fetch_s_%d" % npc.get_instance_id()
	var fetch_spent: float = float(_item.get_meta(fetch_key, 0.0)) + delta
	_item.set_meta(fetch_key, fetch_spent)
	if fetch_spent > FETCH_GIVE_UP_SECONDS and not reachable:
		_item.remove_meta(fetch_key)
		npc.job_state.mark_unreachable(_item)
		_skipped_ids[_item.get_instance_id()] = true
		NPCItemUser.release_item(_item)
		if _item.has_method("set_nav_obstacle_enabled"):
			_item.set_nav_obstacle_enabled(true)
		_item = null
		return
	## Wedged where no one can get at it (against a wall, behind furniture):
	## the path ends short of reach. Give up on it instead of circling there.
	_no_reach_time = _no_reach_time + delta if npc.nav_finished() and not reachable else 0.0
	if _no_reach_time > 2.0:
		_no_reach_time = 0.0
		npc.job_state.record_cleaning_pickup_failure(npc, _item)
		_skipped_ids[_item.get_instance_id()] = true
		NPCItemUser.release_item(_item)
		if _item.has_method("set_nav_obstacle_enabled"):
			_item.set_nav_obstacle_enabled(true)
		_item = null
		return
	if reachable:
		if NPCItemUser.grab_loose(npc, _item):
			_on_picked_up(npc)
		else:
			npc.job_state.record_cleaning_pickup_failure(npc, _item)
			_skipped_ids[_item.get_instance_id()] = true
			_item = null

func _on_picked_up(npc: NPC) -> void:
	_item.remove_meta("_fetch_s_%d" % npc.get_instance_id())
	_destination = NPCJobQueries.find_cleaning_destination(npc, _is_trash, _item)
	if _destination != null:
		npc.set_nav_target((_destination as Node3D).global_position)
		return
	if _is_forced_session:
		_relocating = true
		_relocate_point = _pick_relocate_point(npc)
		npc.set_nav_target(_relocate_point)
		return
	## Nowhere for it after all (storage filled since selection) — put it
	## back down and skip it for this session.
	_skipped_ids[_item.get_instance_id()] = true
	NPCItemUser.drop_held(npc)
	_item = null

func _tick_carry(npc: NPC, delta: float) -> void:
	if _relocating:
		npc.nav_steer(delta)
		if npc.nav_finished() or NPCItemUser.in_reach(npc, _relocate_point, NPCItemUser.SNATCH_RANGE):
			NPCItemUser.drop_held(npc)
			_item = null
			_relocating = false
			_finished = true   ## forced grab is exactly one item
		return
	if _destination == null or not is_instance_valid(_destination):
		_destination = NPCJobQueries.find_cleaning_destination(npc, _is_trash, _item)
		if _destination == null:
			NPCItemUser.drop_held(npc)
			_item = null
			return
	## Sep 2026: storage that can't be reached (boxed in, deep shelf) used to
	## be carried toward for minutes; set it down and skip it this session.
	if _carry_time > NPCItemUser.CARRY_LIMIT_S:
		_skipped_ids[_item.get_instance_id()] = true
		## Remember it: that storage can't be reached, and this item isn't
		## worth picking straight back up (5 s later) to try again.
		if _destination != null and is_instance_valid(_destination):
			npc.job_state.mark_unreachable(_destination)
		npc.job_state.blacklist_cleaning_item(npc, _item, "couldn't reach its storage")
		NPCItemUser.clear_carry_time(_item)
		NPCItemUser.drop_held(npc)
		_item = null
		_carry_time = 0.0
		return
	npc.set_nav_target((_destination as Node3D).global_position)
	if NPCItemUser.wait_turn_at(npc, _destination, delta):
		return   ## someone's using that storage — wait a little way back
	npc.nav_steer(delta)
	## Shelf reach (furniture), not the snatch range meant for people.
	if NPCItemUser.in_reach(npc, (_destination as Node3D).global_position, NPCItemUser.SHELF_RANGE):
		npc.lock_movement()
		var item_name: String = display_name(_item)
		var was_basket: bool = _item == _basket
		NPCItemUser.clear_carry_time(_item)
		var used_storage: Node = _destination
		if NPCItemUser.store_held(npc, _destination):
			_delivered += 1
			if not was_basket:
				npc.log_action("Threw away %s" % item_name if _is_trash else "Put away %s" % item_name)
		else:
			NPCItemUser.drop_held(npc)
			_skipped_ids[_item.get_instance_id()] = true
		if was_basket:
			_basket = null
		_item = null
		_carry_time = 0.0
		NPCItemUser.release_item(used_storage)   ## next person's turn at that shelf
		if _is_forced_session:
			_finished = true

# ─── Basket (produce) ─────────────────────────────────────────────────────
func _find_available_basket(npc: NPC) -> Basket:
	var best: Basket = null
	var best_d: float = INF
	for n: Node in npc.get_tree().get_nodes_in_group("pickup"):
		if not (n is Basket) or not is_instance_valid(n):
			continue
		if (("is_held" in n) and n.is_held) or n.is_in_group("shelved") or n.slots.count(null) <= 0 \
				or NPCItemUser.is_claimed_by_other(n, npc):
			continue
		var d: float = NPCItemUser.flat_distance(npc.global_position, (n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n as Basket
	return best

func _tick_fetch_basket(npc: NPC, delta: float, basket: Basket) -> void:
	NPCItemUser.claim_item(basket, npc)
	NPCItemUser.track_fetch_target(npc, basket)
	npc.nav_steer(delta)
	if NPCItemUser.in_reach(npc, basket.global_position, NPCItemUser.PICKUP_RANGE):
		if NPCItemUser.grab_loose(npc, basket):
			_basket = basket
			npc.set_nav_target(_item.global_position)

func _tick_stash_into_basket(npc: NPC, delta: float) -> void:
	if not is_instance_valid(_basket):
		_basket = null
		_item = null
		return
	if not (_item is FarmProduceItem) or (("is_held" in _item) and _item.is_held) or _item.is_in_group("shelved"):
		_item = null
		return
	NPCItemUser.track_fetch_target(npc, _item)
	npc.nav_steer(delta)
	if not NPCItemUser.in_reach(npc, _item.global_position, NPCItemUser.PICKUP_RANGE):
		return
	var slot_index: int = _basket.slots.find(null)
	if slot_index == -1:
		_item = null
		return
	var produce: RigidBody3D = _item
	NPCItemUser.release_item(produce)
	produce.get_parent().remove_child(produce)
	_basket.add_child(produce)
	produce.global_position = _basket.global_position
	produce.freeze = true
	produce.visible = false
	if produce.has_method("deactivate_dynamic_state"):
		produce.deactivate_dynamic_state()
	produce.remove_from_group("pickup")
	produce.add_to_group("shelved")
	if produce.is_in_group("interactable"):
		produce.set_meta("_was_interactable", true)
		produce.remove_from_group("interactable")
	if "is_held" in produce:
		produce.is_held = false
	_basket.slots[slot_index] = produce
	_basket.item_added.emit(slot_index, produce)
	npc.log_action("Gathered %s into a basket" % display_name(produce))
	_item = null

## Done gathering: the basket itself becomes the item to put away.
func _start_delivering_basket(npc: NPC) -> void:
	_item = _basket
	_is_trash = false
	_destination = NPCJobQueries.find_cleaning_destination(npc, false, _basket)
	if _destination == null:
		NPCItemUser.drop_held(npc)   ## nowhere to store it — set it down
		_basket = null
		_item = null
	else:
		npc.set_nav_target((_destination as Node3D).global_position)

# ─── End ──────────────────────────────────────────────────────────────────
func _finish(npc: NPC, reason: String) -> void:
	_finished = true
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "session ended", reason)

func _pick_relocate_point(npc: NPC) -> Vector3:
	var dir: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if dir.length() < 0.01:
		dir = Vector3(1.0, 0.0, 0.0)
	var p: Vector3 = npc.stuck.snap_to_navmesh(npc.global_position + dir.normalized() * RELOCATE_DISTANCE)
	return p if p != Vector3.INF else npc.global_position

func done(_npc: NPC) -> bool:
	return _finished and _item == null and _basket == null

func exit(npc: NPC) -> void:
	var detail: String = "item=%s destination=%s" % [display_name(_item),
		(_destination.name if _destination != null and is_instance_valid(_destination) else "none")]
	if _item != null and is_instance_valid(_item) and _item.has_method("set_nav_obstacle_enabled") \
			and not (("is_held" in _item) and _item.is_held):
		_item.set_nav_obstacle_enabled(true)
	if _delivered > 0:
		npc.on_work_done()
	_item = null
	_basket = null
	on_session_exit(npc, "cleaning", done(npc), detail)

func debug_info() -> Dictionary:
	var phase: String = "idle"
	if _item != null:
		phase = "relocating" if _relocating else ("carrying" if _destination != null else "fetching")
	return {
		"activity": "cleaning",
		"item": display_name(_item) if _item != null else "",
		"is_trash": _is_trash,
		"phase": phase,
		"basket": _basket != null,
		"destination": (_destination.name if _destination != null and is_instance_valid(_destination) else ""),
		"session_elapsed": _session_elapsed,
		"session_duration": _session_duration,
		"forced": _is_forced_session,
		"no_storage_categories": _no_storage_categories.keys(),
	}
