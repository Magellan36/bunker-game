extends NPCSessionActivity
class_name GardeningActivity
## GardeningActivity.gd — a gardening session over farming-tray CELLS:
## fill empty cells with soil, plant seeds (respecting each cell's seed
## lock), optionally harvest ("farming" mode) or fertilize
## ("fertilize_only"). Cells are reserved per NPC (NPCItemUser.claim_cell)
## so two gardeners never work the same cell.
##
## Modes: "auto" (autonomous: soil + plant), "soil_only", "fertilize_only",
## "farming" (harvest + soil + plant) — the last three are command-only.
##
## Sep 2026 fixes:
##   • Holding the wrong supply for the chosen task (a soil bag when the
##     next cell needs a seed) used to be "applied" anyway, fail silently,
##     and re-pick the very same cell forever — an infinite loop inside a
##     non-interruptible session. Tasks are now chosen to match what's
##     already in hand first, a failed application skips that cell for the
##     session, and leftovers are put away at the end.
##   • The fetch phase adopted ANY held item (a food can...) as supplies.
##   • Tending takes a short, visible work beat (scaled by work speed)
##     instead of happening instantly on arrival.

const WORK_RANGE: float = 2.4
const TEND_TIME: float = 2.5   ## seconds per cell at normal work speed

var mode: String = "auto"            ## "auto" | "soil_only" | "fertilize_only" | "farming"
var forced_seed_type: String = ""    ## unused; kept for CommandGardeningActivity compatibility

var _item: RigidBody3D = null        ## supply in hand (soil / seed / fertilizer)
var _current_tray: Node = null
var _current_cell: int = -1          ## -1 for tray-wide fertilizing
var _current_task: String = ""       ## "harvest" | "soil" | "plant" | "fertilize"
var _fetch_loose: RigidBody3D = null
var _fetch_shelf: Dictionary = {}
var _phase: String = "pick_task"     ## pick_task -> fetch -> travel -> apply
var _work_left: float = 0.0
var _finished: bool = false
var _handoff: NPCActivity = null
var _cells_done: int = 0

func label() -> String:
	match _phase:
		"fetch": return "Fetching %s" % {"soil": "soil", "plant": "seeds", "fertilize": "fertilizer"}.get(_current_task, "supplies")
		"travel": return "Heading to the garden"
		"apply":
			match _current_task:
				"harvest": return "Harvesting"
				"soil": return "Filling a tray with soil"
				"plant": return "Planting seeds"
				"fertilize": return "Fertilizing"
	return "Gardening"

func score(npc: NPC) -> float:
	if mode != "auto" or not NPCJobQueries.has_gardening_target_available(npc):
		return 0.0
	return npc.work_score("GARDENING")

func accepts_held_item(_npc: NPC, item: Node) -> bool:
	return _is_supply(item)

static func _is_supply(item: Node) -> bool:
	return item is BagOfSoilItem or item is SeedItem or item is FertilizerItem

func enter(npc: NPC) -> void:
	_finished = false
	_skipped = {}
	_cells_done = 0
	_item = npc.held_item if NPCItemUser.hands_full(npc) and _is_supply(npc.held_item) else null
	_pick_next_task(npc)

# ─── Task selection ───────────────────────────────────────────────────────
func _pick_next_task(npc: NPC) -> void:
	if _item != null and (not is_instance_valid(_item) or npc.held_item != _item):
		_item = null   ## used up or lost
	while true:
		_release_current_cell(npc)
		_current_tray = null
		_current_cell = -1
		_current_task = ""
		_choose_task(npc)
		if _current_tray == null:
			_end_session(npc)
			return
		if _current_task != "fertilize" and not NPCItemUser.claim_cell(_current_tray, _current_cell, npc):
			_mark_skipped(_cell_key(_current_tray, _current_cell))
			continue
		if _current_task == "harvest" or _item_matches_task():
			_go_to_tray(npc)
			return
		## Need a different supply. Anything in hand doesn't fit ANY open
		## task (checked in _choose_task), so it goes away first.
		if _item != null:
			_handoff = PutAwayHeldItemActivity.new()
			_finished = true
			return
		_phase = "fetch"
		if _start_fetch(npc):
			return
		_mark_skipped(_cell_key(_current_tray, _current_cell))

## Picks the next cell. With a supply in hand, cells that USE it come first
## (so a half-used soil bag or seed packet is finished before fetching more).
func _choose_task(npc: NPC) -> void:
	var order: Array[String] = []
	if mode == "farming":
		order.append("harvest")
	if _item is BagOfSoilItem:
		order.append_array(["soil", "plant"])
	elif _item is SeedItem:
		order.append_array(["plant", "soil"])
	else:
		order.append_array(["soil", "plant"])
	for task: String in order:
		if task == "plant" and (mode == "soil_only" or mode == "fertilize_only"):
			continue
		if task == "soil" and mode == "fertilize_only":
			continue
		var pick: Dictionary = _nearest_ready_plant(npc) if task == "harvest" else _nearest_open_cell(npc, task)
		if not pick.is_empty():
			_current_tray = pick["tray"]
			_current_cell = int(pick["cell"])
			_current_task = task
			return
	if mode == "fertilize_only":
		var fert_tray: Node = _nearest_tray_needing(npc, "has_open_fertilizable_cell")
		if fert_tray != null:
			_current_tray = fert_tray
			_current_cell = -1
			_current_task = "fertilize"

func _go_to_tray(npc: NPC) -> void:
	_phase = "travel"
	npc.set_nav_target(approach_point(npc, _current_tray))

func _cell_key(tray: Node, cell_index: int) -> String:
	return "%d:%d" % [tray.get_instance_id(), cell_index]

func _nearest_ready_plant(npc: NPC) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray):
			continue
		for i: int in range(tray.cell_count):
			if _is_skipped(_cell_key(tray, i)) or NPCItemUser.is_cell_claimed_by_other(tray, i, npc):
				continue
			var plant: Node = tray.plant_refs[i] if i < tray.plant_refs.size() else null
			if plant == null or not is_instance_valid(plant) or not plant.is_ready():
				continue
			var d: float = NPCItemUser.flat_distance(npc.global_position, (tray as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = {"tray": tray, "cell": i}
	return best

func _nearest_open_cell(npc: NPC, kind: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray):
			continue
		for i: int in range(tray.cell_count):
			if _is_skipped(_cell_key(tray, i)) or NPCItemUser.is_cell_claimed_by_other(tray, i, npc):
				continue
			if kind == "soil":
				if tray.soil_filled[i]:
					continue
				if not (_item is BagOfSoilItem) and not NPCJobQueries.supply_available(npc, func(it: Node) -> bool: return it is BagOfSoilItem):
					continue
			else:
				if not tray.soil_filled[i] or tray.planted_type[i] != "":
					continue
				var lock: String = tray.get_cell_seed_lock(i)
				if _item is SeedItem:
					if lock != "" and _item.seed_type != lock:
						if not NPCJobQueries.seed_available(npc, lock):
							continue
				elif not NPCJobQueries.seed_available(npc, lock):
					continue
			var d: float = NPCItemUser.flat_distance(npc.global_position, (tray as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = {"tray": tray, "cell": i}
	return best

func _nearest_tray_needing(npc: NPC, check_method: String) -> Node:
	return NPCSessionActivity.nearest_in_group(npc, "farming_tray",
		func(t: Node) -> bool: return not _is_skipped(_cell_key(t, -1)) and t.call(check_method))

func _item_matches_task() -> bool:
	if _item == null:
		return false
	match _current_task:
		"soil":
			return _item is BagOfSoilItem
		"plant":
			if not (_item is SeedItem):
				return false
			var lock: String = _current_tray.get_cell_seed_lock(_current_cell)
			return lock == "" or _item.seed_type == lock
		"fertilize":
			return _item is FertilizerItem
	return false

func _fetch_filter_for_task() -> Callable:
	match _current_task:
		"soil":
			return func(item: Node) -> bool: return item is BagOfSoilItem
		"plant":
			var want: String = _current_tray.get_cell_seed_lock(_current_cell)
			if want == "":
				want = _current_tray.last_planted_type[_current_cell]   ## soft preference
			if want != "":
				return func(item: Node) -> bool: return item is SeedItem and item.seed_type == want
			return func(item: Node) -> bool: return item is SeedItem
		"fertilize":
			return func(item: Node) -> bool: return item is FertilizerItem
	return func(_i: Node) -> bool: return false

func _start_fetch(npc: NPC) -> bool:
	var found: bool = _try_fetch_with_filter(npc, _fetch_filter_for_task())
	if not found and _current_task == "plant" and _current_tray.get_cell_seed_lock(_current_cell) == "":
		found = _try_fetch_with_filter(npc, func(item: Node) -> bool: return item is SeedItem)
	return found

func _try_fetch_with_filter(npc: NPC, filt: Callable) -> bool:
	var pick: Dictionary = NPCItemUser.find_fetch_target(npc, filt)
	var loose: RigidBody3D = pick.get("loose")
	var shelf_pick: Dictionary = pick.get("shelf", {})
	var tgt: Node3D = loose if loose != null else (shelf_pick.get("shelf") as Node3D if not shelf_pick.is_empty() else null)
	if tgt == null:
		return false
	var claim_target: Node = loose if loose != null else shelf_pick.get("item")
	if not NPCItemUser.claim_item(claim_target, npc):
		return false
	_fetch_loose = loose
	_fetch_shelf = shelf_pick if loose == null else {}
	npc.set_nav_target(tgt.global_position)
	return true

# ─── Tick ─────────────────────────────────────────────────────────────────
func tick(npc: NPC, delta: float) -> void:
	if _finished:
		return
	if _current_tray != null and not is_instance_valid(_current_tray):
		_pick_next_task(npc)
		return
	match _phase:
		"fetch":
			_tick_fetch(npc, delta)
		"travel":
			npc.nav_steer(delta)
			if NPCItemUser.in_reach(npc, (_current_tray as Node3D).global_position, WORK_RANGE):
				npc.lock_movement()
				npc.face_toward((_current_tray as Node3D).global_position, 1.0)
				_phase = "apply"
				_work_left = TEND_TIME
				npc.show_work_banner()
		"apply":
			npc.halt_movement(delta)
			_work_left -= delta * npc.get_work_speed_mult("farming")
			npc.update_work_banner(label().to_upper(), 1.0 - _work_left / TEND_TIME)
			if _work_left <= 0.0:
				npc.hide_work_banner()
				_apply(npc)

func _apply(npc: NPC) -> void:
	var key: String = _cell_key(_current_tray, _current_cell)
	var ok: bool = false
	if _current_task == "harvest":
		var plant: Node = _current_tray.plant_refs[_current_cell] if _current_cell < _current_tray.plant_refs.size() else null
		if plant != null and is_instance_valid(plant) and plant.is_ready():
			plant.harvest()
			npc.log_action("Harvested a plant")
			ok = true
	elif _item != null and is_instance_valid(_item) and npc.held_item == _item and _item_matches_task():
		if _current_task == "fertilize":
			_item.on_use()
			ok = true
		else:
			ok = _item.apply_at_cell(_current_tray, _current_cell)
		if ok:
			npc.log_action({"soil": "Filled a tray cell with soil", "plant": "Planted seeds", "fertilize": "Fertilized a tray"}.get(_current_task, "Tended the garden"))
	if ok:
		_cells_done += 1
		npc.on_work_done("farming")
	else:
		_mark_skipped(key)   ## never retry a failed cell this session
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "gardening applied", "%s cell=%d success=%s" % [_current_task, _current_cell, ok])
	if _item != null and (not is_instance_valid(_item) or npc.held_item != _item):
		_item = null   ## used up
	_pick_next_task(npc)

func _tick_fetch(npc: NPC, delta: float) -> void:
	if NPCItemUser.hands_full(npc):
		if _is_supply(npc.held_item):
			_item = npc.held_item
			_fetch_loose = null
			_fetch_shelf = {}
			if _item_matches_task():
				_go_to_tray(npc)
			else:
				_pick_next_task(npc)   ## grabbed a different supply — use it where it fits
		else:
			NPCItemUser.drop_held(npc)
		return
	if _fetch_loose != null:
		if not is_instance_valid(_fetch_loose) or (("is_held" in _fetch_loose) and _fetch_loose.is_held):
			_fetch_loose = null
			_mark_skipped(_cell_key(_current_tray, _current_cell))
			_pick_next_task(npc)
			return
		NPCItemUser.track_fetch_target(npc, _fetch_loose)
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, _fetch_loose.global_position, NPCItemUser.PICKUP_RANGE):
			if not NPCItemUser.grab_loose(npc, _fetch_loose):
				_fetch_loose = null
				_mark_skipped(_cell_key(_current_tray, _current_cell))
				_pick_next_task(npc)
		return
	if not _fetch_shelf.is_empty():
		var shelf: Node3D = _fetch_shelf.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_fetch_shelf = {}
			_pick_next_task(npc)
			return
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, shelf.global_position, NPCItemUser.SHELF_RANGE):
			if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
				_fetch_shelf = {}
				_mark_skipped(_cell_key(_current_tray, _current_cell))
				_pick_next_task(npc)
		return
	_pick_next_task(npc)

func _end_session(npc: NPC) -> void:
	_finished = true
	if NPCItemUser.hands_full(npc) and npc.held_item == _item and _item != null:
		_handoff = PutAwayHeldItemActivity.new()   ## leftover supplies go back on the shelf
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "gardening session ended", "cells tended=%d skipped=%d" % [_cells_done, _skipped.size()])

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func done(_npc: NPC) -> bool:
	return _finished and _handoff == null

func _release_current_cell(npc: NPC) -> void:
	if _current_tray != null and is_instance_valid(_current_tray) and _current_cell != -1:
		NPCItemUser.release_cell(_current_tray, _current_cell, npc)

func debug_info() -> Dictionary:
	return {
		"activity": "gardening",
		"mode": mode,
		"phase": _phase,
		"task": _current_task,
		"tray": (_current_tray.name if _current_tray != null and is_instance_valid(_current_tray) else ""),
		"cell": _current_cell,
		"item": (display_name(_item) if _item != null and is_instance_valid(_item) else ""),
	}

func exit(npc: NPC) -> void:
	var detail: String = "phase=%s task=%s cell=%d" % [_phase, _current_task, _current_cell]
	_release_current_cell(npc)
	on_session_exit(npc, "gardening", _finished, detail)
