extends NPCSessionActivity
class_name CleaningActivity
## Cleaning (Aug 2026, sustained session). Trash disposal + shelf
## organizing under one job, mirroring GiveToFriendActivity's
## fetch→travel→deliver shape per item — but now loops through
## multiple items for 20-40 real seconds (or until nothing's left to
## clean) instead of stopping after one. Counts as a JOB for Work
## Ethic AND the Job Priority system (get_work_ethic_job_mult() *
## get_job_priority_weight()).
##
## forced_item (stuck-recovery path) is always exactly ONE grab, never
## a full session — an emergency unstick, not a deliberate shift.
const SESSION_MIN_SEC: float = 20.0
const SESSION_MAX_SEC: float = 40.0

var _item: RigidBody3D = null
var _destination: Node = null
var _is_trash: bool = false
var _forced_item: RigidBody3D = null
var _is_forced_session: bool = false
var _session_elapsed: float = 0.0
var _session_duration: float = 0.0
var _finished: bool = false
var _skipped_ids: Dictionary = {}         ## item instance_id -> true, this session — confirmed no destination, never retry
var _no_storage_categories: Dictionary = {}   ## "light"/"heavy" -> true, this session — every viable destination for the category is gone/full/nonexistent
var _basket: Basket = null                ## Aug 2026 — set once fetched, for produce collection (see _pick_next_target/_tick_produce_via_basket)

## Aug 2026 — last-resort relocation for a forced (stuck-recovery) grab
## with no real destination anywhere. Previously this case picked the
## item up and set it right back down in the same spot (no travel
## happened between pickup and drop), which didn't actually clear the
## obstruction. Deliberately a genuine navmesh-pathed walk, NOT a raw
## position teleport — the whole point is to move the item somewhere
## real, respecting collision, unlike the nudge fallback this
## complements for the "obstruction successfully identified" case.
const RELOCATE_DISTANCE: float = 2.5
var _relocating: bool = false
var _relocate_point: Vector3 = Vector3.ZERO

func _init(forced_item: RigidBody3D = null) -> void:
	_forced_item = forced_item
	_is_forced_session = forced_item != null

func label() -> String:
	if _item == null:
		return "Cleaning"
	if _relocating:
		return "Clearing the way"
	return "Cleaning (carrying)" if _destination != null else "Cleaning (fetching)"

func score(npc: NPC) -> float:
	if _is_forced_session:
		return 0.0
	if not NPCJobQueries.has_cleaning_target_available(npc):
		return 0.0
	## Aug 2026 — escalating urgency: the more clutter sits around,
	## the more Cleaning outcompetes Wander/Relax/etc. See
	## NPC.CLUTTER_URGENCY_STEP's own comment for the derivation.
	var urgency_mult: float = 1.0 + float(JobBoard.get_total_clutter_count()) * NPC.CLUTTER_URGENCY_STEP
	return NPC.CLEANING_BASE_SCORE * npc.get_work_ethic_job_mult() \
		* npc.get_job_priority_weight("CLEANING") * urgency_mult

func interruptible() -> bool:
	return _item == null   ## between items (or before the first), fine to interrupt; mid-carry, commit. Intentionally overrides NPCSessionActivity's non-interruptible default.

func enter(npc: NPC) -> void:
	_session_duration = randf_range(SESSION_MIN_SEC, SESSION_MAX_SEC)
	_session_elapsed = 0.0
	_finished = false
	_skipped_ids = {}
	_no_storage_categories = {}
	if NPCDebug.enabled and not _is_forced_session:
		NPCDebug.log_cleaning(npc, "session started", "target duration=%.0fs" % _session_duration)
	_pick_next_target(npc)

## Called at session start and after each delivery (success or
## failure) — this is what makes the NPC keep working through the
## bunker's clutter instead of stopping after one item.
##
## Aug 2026 — destination-first. Previously this only set _item and
## walked toward it; find_cleaning_destination() was checked AFTER
## grab_loose() succeeded, in tick()'s fetch phase. That meant an
## item with genuinely nowhere to go (e.g. a Test Crate with only an
## End Table/Dresser in range, neither able to take it) got walked
## to, picked up, and dropped again — then immediately re-selected as
## "nearest" and repeated, every tick, for the entire session. Now:
## for organizable (non-trash) items, confirm a destination exists
## BEFORE claiming or moving toward it at all. If none exists for
## this SPECIFIC item but the category (light/heavy) still has
## SOME viable destination elsewhere, just try the next candidate. If
## the category has NO viable destination anywhere, remember that
## (_no_storage_categories) so every future item of that category is
## skipped on sight for the rest of the session instead of being
## retried. Trash is unchanged — it's a single flat group with its
## own pre-existing "no receptacle" handling, worth revisiting
## together once trash_receptacle actually exists.
func _pick_next_target(npc: NPC) -> void:
	_destination = null
	if _is_forced_session:
		_item = _forced_item
		_forced_item = null
		if _item == null or not is_instance_valid(_item):
			_item = null
			_finished = true
			return
		_is_trash = NPCJobQueries.is_trash_item(npc, _item)
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "forced grab", "%s (stuck-recovery, is_trash=%s)" % [
				display_name(_item), _is_trash])
	else:
		while true:
			var result: Dictionary = NPCJobQueries.find_cleaning_target(npc, _skipped_ids, _no_storage_categories)
			if result.is_empty():
				_finished = true
				_item = null
				if NPCDebug.enabled:
					var reason: String = "nothing left to clean"
					if not _no_storage_categories.is_empty():
						reason = "nothing left to clean — no storage for: %s" % ", ".join(_no_storage_categories.keys())
					NPCDebug.log_cleaning(npc, "session ended", reason)
				return
			_item = result.get("item")
			_is_trash = result.get("is_trash", false)
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "target picked", "%s (%s) dist=%.1f" % [
					display_name(_item), "trash" if _is_trash else "organizable",
					NPCItemUser.flat_distance(npc.global_position, (_item as Node3D).global_position)])
			if _is_trash:
				## Aug 2026 fix — now that trash_receptacle actually exists
				## and can fill up, trash gets the exact same
				## destination-first treatment organizable items already
				## have, reusing the SAME _no_storage_categories dict with
				## "trash" as its own category key — one full trash can
				## stops the NPC from repeatedly walking a trash item to
				## it and dropping it right back down, for the rest of
				## this session, exactly like a full shelf already does
				## for light/heavy.
				if _no_storage_categories.has("trash"):
					_skipped_ids[_item.get_instance_id()] = true
					continue
				if NPCJobQueries.find_cleaning_destination(npc, true, _item) != null:
					break   ## viable trash destination confirmed — commit and go
				_skipped_ids[_item.get_instance_id()] = true
				_no_storage_categories["trash"] = true
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "no storage for category", "%s (trash) — no viable destination exists anywhere; skipping all trash items this session" \
						% display_name(_item))
				continue
			var category: String = NPCJobQueries.classify_organizable_item(_item)
			if _item is FarmProduceItem and _basket == null:
				var basket: Basket = _find_available_basket(npc)
				if basket != null:
					## Aug 2026 — produce specifically prefers basket collection
					## over normal carry-and-deliver, mirroring how the player
					## actually gathers produce. _phase handling for this is
					## entirely in tick()'s fetch branch below — no destination
					## lookup needed for the produce item itself, the BASKET is
					## what eventually gets delivered.
					break
			if NPCJobQueries.find_cleaning_destination(npc, false, _item) != null:
				break   ## viable destination confirmed for THIS item — commit and go fetch it
			_skipped_ids[_item.get_instance_id()] = true
			if not NPCJobQueries.has_viable_destination_for_category(npc, category):
				_no_storage_categories[category] = true
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "no storage for category", "%s (%s) — no viable destination exists anywhere; skipping all %s items this session" \
						% [display_name(_item), category, category])
			elif NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "no destination (retrying)", "%s (%s) has nowhere to go right now — trying next item" \
					% [display_name(_item), category])
			## loop again — try the next nearest candidate, never having walked to this one at all
	if not NPCItemUser.claim_item(_item, npc):
		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "claim failed", "%s already claimed by another NPC — retrying next tick" % display_name(_item))
		_item = null   ## momentary claim clash — try again next tick, don't end the session over it
		return
	if _item.has_method("set_nav_obstacle_enabled"):
		_item.set_nav_obstacle_enabled(false)
	npc.set_nav_target(_item.global_position)

func tick(npc: NPC, delta: float) -> void:
	if not _is_forced_session:
		_session_elapsed += delta
		if _session_elapsed >= _session_duration and _item == null:
			_finished = true
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "session ended", "time's up (%.0fs)" % _session_duration)
			return

	if _item == null or not is_instance_valid(_item):
		_item = null
		if not _finished:
			_pick_next_target(npc)
		return

	if npc.held_item == null:
		## Fetch phase
		## Aug 2026 — produce collection: fetch a Basket FIRST if one's
		## needed and not already held, before ever approaching the
		## produce item itself. Once holding a basket, produce items get
		## stashed into it (see the branch further below) instead of the
		## normal carry-in-hand pickup.
		if _item is FarmProduceItem and _basket == null:
			var basket: Basket = _find_available_basket(npc)
			if basket == null:
				## No basket after all (taken/gone since selection) —
				## fall through to a normal hand-carry pickup instead.
				pass
			elif not _tick_fetch_basket(npc, delta, basket):
				return
		if _basket != null and _item is FarmProduceItem:
			_tick_stash_into_basket(npc, delta)
			return
		if "is_held" in _item and _item.is_held:
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "target lost", "%s became held by someone else before pickup" % display_name(_item))
			NPCItemUser.release_item(_item)
			_item = null
			return
		if _item.is_in_group("shelved"):
			## Became unavailable (someone shelved it, or a stale
			## reference pointed at something already stored) — give
			## up on THIS item immediately rather than walking the
			## full distance for nothing (grab_loose() would refuse
			## it anyway, per Part A above).
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "target lost", "%s became shelved before pickup" % display_name(_item))
			NPCItemUser.release_item(_item)
			_item = null
			return
		NPCItemUser.track_fetch_target(npc, _item)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, _item.global_position) <= NPCItemUser.PICKUP_RANGE:
			if NPCItemUser.grab_loose(npc, _item):
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "picked up", display_name(_item))
				_destination = NPCJobQueries.find_cleaning_destination(npc, _is_trash, _item)
				if _destination == null:
					if _is_forced_session:
						## Aug 2026 — last resort: this item is genuinely
						## storable nowhere, but it's still the obstruction
						## that got the NPC stuck. Setting it back down in
						## the same spot (the old behavior) doesn't clear
						## anything — carry it a short, real, pathed distance
						## away first instead.
						_relocating = true
						_relocate_point = _pick_relocate_point(npc)
						if NPCDebug.enabled:
							NPCDebug.log_cleaning(npc, "relocating (no destination)", "%s has nowhere to go — carrying it clear instead of dropping in place" % display_name(_item))
						npc.set_nav_target(_relocate_point)
					else:
						if NPCDebug.enabled:
							NPCDebug.log_cleaning(npc, "no destination", "%s has nowhere to go (is_trash=%s) — setting back down" % [
								display_name(_item), _is_trash])
						NPCItemUser.drop_held(npc)
						_item = null
				elif NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "destination chosen", "%s -> %s" % [display_name(_item), _destination.name])
			else:
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "pickup failed", "grab_loose() refused %s" % display_name(_item))
				npc.job_state.record_cleaning_pickup_failure(npc, _item)   ## Aug 2026 — counts toward the give-up limit; claim/held/shelved misses elsewhere never call this
				NPCItemUser.release_item(_item)
				_item = null
		return

	## Relocate phase (forced-session, no-destination last resort)
	if _relocating:
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, _relocate_point) <= NPCItemUser.SNATCH_RANGE:
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "relocated", "%s dropped clear of the original spot" % display_name(_item))
			NPCItemUser.drop_held(npc)
			_item = null
			_relocating = false
			_finished = true   ## stuck-recovery grab is always exactly one item
		return

	## Travel phase
	if _destination == null or not is_instance_valid(_destination):
		_item = null
		return
	npc.set_nav_target((_destination as Node3D).global_position)
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, (_destination as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
		var item_name: String = _item.get_display_name() if _item.has_method("get_display_name") else "an item"
		if _is_trash:
			if _destination.has_method("npc_deposit_trash"):
				_destination.npc_deposit_trash(npc, _item)
			npc.log_action("Threw away %s" % item_name)
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "delivered", "threw away %s at %s" % [item_name, _destination.name])
		else:
			if _destination.has_method("npc_try_place_item") and _destination.npc_try_place_item(npc, _item):
				npc.log_action("Put away %s" % item_name)
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "delivered", "stored %s in %s" % [item_name, _destination.name])
			else:
				## Placement failed (shelf filled between selection and
				## arrival) — item goes back on the ground and MUST be
				## released here, or it stays permanently claimed by
				## this NPC and invisible to every other NPC's cleaning
				## scans for the rest of the session.
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "delivery failed", "%s no longer had room for %s — dropping it" % [_destination.name, item_name])
				NPCItemUser.release_item(_item)
				NPCItemUser.drop_held(npc)
		_item = null
		if _is_forced_session:
			_finished = true   ## stuck-recovery grab is always exactly one item

## Short, random-direction, navmesh-pathed relocation point for a
## forced-grab item with nowhere real to go. Deliberately mirrors
## _nudge_free_of_obstruction()'s random-direction fallback shape, but
## travels there via real navigation instead of a raw position write —
## that's the whole fix: same "move it somewhere else" goal, done through
## collision-respecting movement instead of a blind teleport.
func _pick_relocate_point(npc: NPC) -> Vector3:
	var dir: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if dir.length() < 0.01:
		dir = Vector3(1.0, 0.0, 0.0)
	return npc.global_position + dir.normalized() * RELOCATE_DISTANCE

func done(npc: NPC) -> bool:
	return _finished and _item == null

func exit(npc: NPC) -> void:
	var detail: String = "item=%s destination=%s is_trash=%s" \
		% [display_name(_item), (_destination.name if _destination != null and is_instance_valid(_destination) else "none"), _is_trash]
	if _item != null:
		if _item.has_method("set_nav_obstacle_enabled") and "is_held" in _item and not _item.is_held:
			_item.set_nav_obstacle_enabled(true)
		NPCItemUser.release_item(_item)
	_item = null
	on_session_exit(npc, "cleaning", done(npc), detail)

## Aug 2026 — nearest Basket with at least one open slot, loose or
## shelved. Mirrors the general fetch-candidate search shape used
## elsewhere in this file, scoped to Basket specifically.
func _find_available_basket(npc: NPC) -> Basket:
	var best: Basket = null
	var best_d: float = INF
	for node: Node in npc.get_tree().get_nodes_in_group("pickup"):
		if not (node is Basket) or not is_instance_valid(node):
			continue
		if ("is_held" in node and node.is_held) or node.is_in_group("shelved"):
			continue
		if node.slots.count(null) <= 0:
			continue   ## full
		var d: float = NPCItemUser.flat_distance(npc.global_position, (node as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = node as Basket
	return best

## Walks to and picks up the basket itself (a normal hand-carry pickup
## — Basket isn't a "basket_storable" item, it's the container).
## Returns false while still in progress (caller should return this
## tick), true once holding it and ready to proceed.
func _tick_fetch_basket(npc: NPC, delta: float, basket: Basket) -> bool:
	if npc.held_item == basket:
		_basket = basket
		return true
	if not NPCItemUser.is_claimed_by_other(basket, npc):
		NPCItemUser.claim_item(basket, npc)
	NPCItemUser.track_fetch_target(npc, basket)
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, basket.global_position) <= NPCItemUser.PICKUP_RANGE:
		NPCItemUser.grab_loose(npc, basket)
	return false

## Walks to the produce item and stashes it into the held basket —
## mirrors Basket.gd's own player-facing "E while holding basket"
## mechanic exactly (first open slot, item re-parented/hidden/frozen
## under the basket), not a normal carry pickup. Once the basket has
## no open slots left, or this produce item vanished, moves on.
func _tick_stash_into_basket(npc: NPC, delta: float) -> void:
	if _item == null or not is_instance_valid(_item) or ("is_held" in _item and _item.is_held) or _item.is_in_group("shelved"):
		_item = null
		return
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, _item.global_position) > NPCItemUser.PICKUP_RANGE:
		return
	var slot_index: int = _basket.slots.find(null)
	if slot_index == -1:
		## Basket just filled up (e.g. by something else) — treat like
		## any other carried item now: it needs delivering, not more
		## stashing. Hand control back to the normal fetch/travel logic
		## by clearing _item so _pick_next_target() re-evaluates fresh
		## next cycle with the FULL basket as npc.held_item.
		_item = null
		return
	_item.get_parent().remove_child(_item)
	_basket.add_child(_item)
	_item.global_position = _basket.global_position
	_item.freeze = true
	_item.visible = false
	if "is_held" in _item:
		_item.is_held = false
	_basket.slots[slot_index] = _item
	_basket.item_added.emit(slot_index, _item)
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "stashed in basket", "%s -> basket (%d/%d slots used)" \
			% [display_name(_item), _basket.slots.size() - _basket.slots.count(null), _basket.slots.size()])
	_item = null

## Aug 2026 — structured snapshot for NPCDebug.dump_cleaning_state().
## "activity" key lets the dump filter to cleaning-only, since
## RefuelActivity doesn't implement this and would otherwise show up
## under the same generic getter.
func debug_info() -> Dictionary:
	var phase: String = "idle"
	if _item != null:
		if _relocating:
			phase = "relocating"
		else:
			phase = "carrying" if _destination != null else "fetching"
	return {
		"activity": "cleaning",
		"item": display_name(_item) if _item != null else "",
		"is_trash": _is_trash,
		"phase": phase,
		"destination": (_destination.name if _destination != null and is_instance_valid(_destination) else ""),
		"session_elapsed": _session_elapsed,
		"session_duration": _session_duration,
		"forced": _is_forced_session,
		"no_storage_categories": _no_storage_categories.keys(),
	}
