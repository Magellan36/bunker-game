extends NPCSessionActivity
class_name GardeningActivity
## Gardening (Aug 2026, sustained session) — fetch→travel→apply→loop,
## per-CELL (a double tray's two cells are independent and workable by
## two different NPCs at once, same as HARVEST already does per-plant).
## Modes:
##   "auto"           — autonomous: soil + planting only, replant-
##                       preference-aware. Never includes harvest —
##                       that stays on the existing JobBoard HARVEST
##                       path, unchanged, to avoid two competing
##                       harvest triggers.
##   "soil_only"       — command: soil only, never plants.
##   "fertilize_only"  — command: fertilizing only, tray-wide (not
##                       converted to per-cell — see the Farming
##                       thread's own note on FertilizerItem).
##   "farming"         — command: the unified player request. Harvest
##                       first (any ready plant, anywhere), then
##                       planting (reading each cell's own seed
##                       lock/replant memory), then soil. Ends when
##                       none of the three apply anywhere.
## Consolidation pass (Aug 2026): rebuilt on NPCSessionActivity. Uses
## the shared _skipped/_is_skipped/_mark_skipped instead of a
## hand-rolled _skipped_cells dict, and this REPLACES unbounded
## recursion that was still live in _pick_next_task()/_start_fetch() —
## if a soil/plant task's needed item type had zero instances anywhere
## in the level, nothing about the world changed between retry
## attempts, so it recursed identically forever and crashed with a
## stack overflow. The loop below is now bounded by the level's total
## cell count and always terminates.
var mode: String = "auto"            ## "auto" | "soil_only" | "fertilize_only" | "farming"
var forced_seed_type: String = ""    ## unused — seed type is always read from the tray now; kept only so CommandGardeningActivity's signature doesn't need to change

var _item: RigidBody3D = null        ## currently held soil bag / seed packet / fertilizer — null for the harvest task, which holds nothing
var _current_tray: FarmingTray = null
var _current_cell: int = -1          ## -1 for the fertilize path, which stays tray-wide
var _current_task: String = ""       ## "harvest" | "soil" | "plant" | "fertilize"
var _fetch_loose: RigidBody3D = null
var _fetch_shelf: Dictionary = {}
var _phase: String = "pick_task"     ## "pick_task" -> "fetch" -> "travel" -> "apply"
var _finished: bool = false

const WORK_RANGE: float = 2.0   ## generous — matches FarmingTray/item REPLACE_RANGE-style tolerances used elsewhere in farming

func label() -> String:
	match _phase:
		"fetch": return "Fetching %s" % _current_task
		"travel": return "Heading to tend a tray"
		"apply": return "Tending the garden"
		_: return "Gardening"

func score(npc: NPC) -> float:
	if mode != "auto":
		return 0.0   ## command-only modes never compete for autonomous pick
	if not NPCJobQueries.has_gardening_target_available(npc):
		return 0.0
	return NPC.GARDENING_BASE_SCORE * npc.get_work_ethic_job_mult() \
		* npc.get_job_priority_weight("GARDENING")

func enter(npc: NPC) -> void:
	_finished = false
	_skipped = {}
	if npc.held_item != null and (npc.held_item is BagOfSoilItem or npc.held_item is SeedItem or npc.held_item is FertilizerItem):
		_item = npc.held_item
	_pick_next_task(npc)

## Finds the nearest eligible task (harvest > soil > plant, mode-
## restricted — fertilize stays tray-wide/separate), claims it, and
## kicks off fetch/travel. Ends the session if nothing eligible remains
## anywhere. Iterative (see this file's own header note) — bounded by
## the level's total cell count.
func _pick_next_task(npc: NPC) -> void:
	while true:
		_release_current_cell(npc)
		_current_tray = null
		_current_cell = -1
		_current_task = ""

		if mode == "farming":
			var harvest_pick: Dictionary = _nearest_ready_plant(npc)
			if not harvest_pick.is_empty():
				_current_tray = harvest_pick["tray"]
				_current_cell = int(harvest_pick["cell"])
				_current_task = "harvest"

		if _current_tray == null and mode != "fertilize_only":
			var soil_pick: Dictionary = _nearest_open_cell(npc, "soil")
			if not soil_pick.is_empty():
				_current_tray = soil_pick["tray"]
				_current_cell = int(soil_pick["cell"])
				_current_task = "soil"

		if _current_tray == null and mode != "soil_only" and mode != "fertilize_only":
			var plant_pick: Dictionary = _nearest_open_cell(npc, "plant")
			if not plant_pick.is_empty():
				_current_tray = plant_pick["tray"]
				_current_cell = int(plant_pick["cell"])
				_current_task = "plant"

		if _current_tray == null and mode == "fertilize_only":
			## Fertilizer intentionally NOT converted to per-cell yet — see
			## this file's header comment. Tray-wide (skip key uses cell
			## index -1, same _skipped dict, no separate tracking needed).
			var fert_tray: Node = _nearest_tray_needing(npc, "has_open_fertilizable_cell")
			if fert_tray != null:
				_current_tray = fert_tray
				_current_cell = -1
				_current_task = "fertilize"

		if _current_tray == null:
			_finished = true
			if NPCDebug.enabled:
				var reason: String = "nothing left to do (mode=%s)" % mode
				if not _skipped.is_empty():
					reason += " — %d cell(s) skipped this session (no resource available or persistent claim contention)" % _skipped.size()
				NPCDebug.log_cleaning(npc, "gardening session ended", reason)
			return

		if _current_task != "fertilize" and not NPCItemUser.claim_cell(_current_tray, _current_cell, npc):
			## Another NPC's Gardening session already has this cell.
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "gardening claim failed", "%s cell=%d already claimed by another NPC — skipping for now" \
					% [_current_tray.name, _current_cell])
			_mark_skipped(_cell_key(_current_tray, _current_cell))
			continue

		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "gardening target picked", "%s cell=%d task=%s" \
				% [_current_tray.name, _current_cell, _current_task])

		if _current_task == "harvest":
			## No item involved — go straight to travel.
			_phase = "travel"
			npc.set_nav_target(approach_point(npc, _current_tray))
			return

		if _item != null and _item_matches_task():
			_phase = "travel"
			npc.set_nav_target(approach_point(npc, _current_tray))
			return

		_phase = "fetch"
		if _start_fetch(npc):
			return   ## fetch target found and nav set — commit, exit the loop

		## Nothing fetchable for this cell/task at all — release the
		## claim we just took, mark it skipped for the rest of this
		## session, and loop to try the next candidate.
		NPCItemUser.release_cell(_current_tray, _current_cell, npc)
		_mark_skipped(_cell_key(_current_tray, _current_cell))

func _cell_key(tray: Node, cell_index: int) -> String:
	return "%d:%d" % [tray.get_instance_id(), cell_index]

## Nearest tray/cell with a ready-to-harvest plant. Only ever used by
## mode "farming" (the unified player request) — autonomous harvesting
## stays exclusively on the existing JobBoard HARVEST path to avoid two
## independent systems both deciding to harvest the same plant.
func _nearest_ready_plant(npc: NPC) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray):
			continue
		for i: int in range(tray.cell_count):
			if _is_skipped(_cell_key(tray, i)):
				continue
			var plant: FarmPlant = tray.plant_refs[i] if i < tray.plant_refs.size() else null
			if plant == null or not is_instance_valid(plant) or not plant.is_ready():
				continue
			if NPCItemUser.is_cell_claimed_by_other(tray, i, npc):
				continue
			var d: float = NPCItemUser.flat_distance(npc.global_position, (tray as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = {"tray": tray, "cell": i}
	return best

## Scans every farming_tray's cells for the given kind ("soil" or
## "plant"), skipping cells claimed by another NPC, cells already
## marked skipped this session, and — for "plant" — cells whose hard
## seed lock (get_cell_seed_lock()) can't currently be satisfied at all
## (no matching seed anywhere). A locked cell NEVER falls back to a
## different type — the lock is absolute, autonomous or commanded.
func _nearest_open_cell(npc: NPC, kind: String) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
		if not is_instance_valid(tray):
			continue
		for i: int in range(tray.cell_count):
			if _is_skipped(_cell_key(tray, i)):
				continue
			var eligible: bool = false
			if kind == "soil":
				eligible = not tray.soil_filled[i]
			else:
				eligible = tray.soil_filled[i] and tray.planted_type[i] == ""
			if not eligible:
				continue
			if NPCItemUser.is_cell_claimed_by_other(tray, i, npc):
				continue
			if kind == "plant":
				var lock: String = tray.get_cell_seed_lock(i)
				if lock != "" and not _seed_type_available(npc, lock):
					continue   ## locked type not in stock anywhere — skip silently
			var d: float = NPCItemUser.flat_distance(npc.global_position, (tray as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = {"tray": tray, "cell": i}
	return best

func _nearest_tray_needing(npc: NPC, check_method: String) -> Node:
	var best: Node = null
	var best_d: float = INF
	for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
		if _is_skipped(_cell_key(tray, -1)):
			continue
		if not is_instance_valid(tray) or not tray.call(check_method):
			continue
		var d: float = NPCItemUser.flat_distance(npc.global_position, (tray as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = tray
	return best

func _seed_type_available(npc: NPC, seed_type: String) -> bool:
	for item: Node in npc.get_tree().get_nodes_in_group("pickup"):
		if is_instance_valid(item) and item is SeedItem and item.seed_type == seed_type \
				and not (("is_held" in item) and item.is_held) and not item.is_in_group("shelved"):
			return true
	for shelf: Node in npc.get_tree().get_nodes_in_group("shelving"):
		if not is_instance_valid(shelf) or not ("slots" in shelf):
			continue
		for stack in shelf.slots:
			if stack is Array and not stack.is_empty() and stack.back() is SeedItem and stack.back().seed_type == seed_type:
				return true
	return false

func _item_matches_task() -> bool:
	if _item == null:
		return false
	match _current_task:
		"soil": return _item is BagOfSoilItem
		"plant":
			if not (_item is SeedItem):
				return false
			var lock: String = _current_tray.get_cell_seed_lock(_current_cell) if _current_tray != null else ""
			if lock != "":
				return _item.seed_type == lock
			return true   ## soft preference — re-validated at fetch time, not here
		"fertilize": return _item is FertilizerItem
		_: return false
	return false

## Two-stage: try the resolved locked/preferred type first; for a SOFT
## preference only (no lock), fall back to ANY seed type if that
## specific one isn't available. A hard lock never falls back — the
## earlier cell-selection pass already guaranteed a locked cell's type
## is in stock before this ever runs. Returns bool now instead of
## recursing on failure (was the actual stack-overflow bug).
func _start_fetch(npc: NPC) -> bool:
	var found: bool = _try_fetch_with_filter(npc, _fetch_filter_for_task())
	if not found and _current_task == "plant" and _current_tray != null \
			and _current_tray.get_cell_seed_lock(_current_cell) == "":
		found = _try_fetch_with_filter(npc, func(item: Node) -> bool: return item is SeedItem)
	if not found and NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "gardening fetch failed", "nothing available for task=%s cell=%d — skipping for the rest of this session" \
			% [_current_task, _current_cell])
	return found

func _try_fetch_with_filter(npc: NPC, filt: Callable) -> bool:
	var loose: RigidBody3D = NPCItemUser.find_loose_item(npc, filt)
	var shelf_pick: Dictionary = {} if loose != null else NPCItemUser.find_shelved_item(npc, filt)
	var tgt: Node3D = loose if loose != null \
		else (shelf_pick.get("shelf") as Node3D if not shelf_pick.is_empty() else null)
	if tgt == null:
		return false
	if loose != null:
		if not NPCItemUser.claim_item(loose, npc):
			return false
		_fetch_loose = loose
	else:
		if not NPCItemUser.claim_item(shelf_pick.get("item"), npc):
			return false
		_fetch_shelf = shelf_pick
	npc.set_nav_target(tgt.global_position)
	return true

## Aug 2026 — seed type is ALWAYS read from the tray (lock, then
## replant memory, then "any") — no separate player-chosen type exists
## anymore.
func _fetch_filter_for_task() -> Callable:
	match _current_task:
		"soil":
			return func(item: Node) -> bool: return item is BagOfSoilItem
		"plant":
			var lock: String = _current_tray.get_cell_seed_lock(_current_cell) if _current_tray != null else ""
			var want: String = lock
			if want == "" and _current_tray != null:
				want = _current_tray.last_planted_type[_current_cell]   ## soft preference
			if want != "":
				var w: String = want
				return func(item: Node) -> bool: return item is SeedItem and item.seed_type == w
			return func(item: Node) -> bool: return item is SeedItem
		"fertilize":
			return func(item: Node) -> bool: return item is FertilizerItem
		_:
			return func(_item: Node) -> bool: return false

func tick(npc: NPC, delta: float) -> void:
	match _phase:
		"fetch":
			_tick_fetch(npc, delta)
		"travel":
			if _current_tray == null or not is_instance_valid(_current_tray):
				_pick_next_task(npc)
				return
			npc.nav_steer(delta)
			var t_pos: Vector3 = (_current_tray as Node3D).global_position
			var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
				.distance_to(Vector2(t_pos.x, t_pos.z))
			if flat_dist <= WORK_RANGE:
				npc.velocity = Vector3.ZERO
				_phase = "apply"
		"apply":
			npc.halt_movement(delta)
			if _current_tray == null or not is_instance_valid(_current_tray):
				_pick_next_task(npc)
				return
			if _current_task == "harvest":
				var plant: FarmPlant = _current_tray.plant_refs[_current_cell] \
					if _current_cell >= 0 and _current_cell < _current_tray.plant_refs.size() else null
				if plant != null and is_instance_valid(plant) and plant.is_ready():
					plant.harvest()
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "gardening applied", "harvest cell=%d success=true" % _current_cell)
				elif NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "gardening applied", "harvest cell=%d success=false (no longer ready)" % _current_cell)
				_pick_next_task(npc)
				return
			if _item == null or not is_instance_valid(_item):
				_pick_next_task(npc)
				return
			var applied: bool = true
			if _current_task == "fertilize":
				## Unchanged, tray-wide — see this file's header comment on
				## why fertilizer stays exactly as it was.
				_item.on_use()
			else:
				## Index-aware apply. Targets the SPECIFIC claimed cell,
				## not "nearest to the item."
				applied = _item.apply_at_cell(_current_tray, _current_cell)
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "gardening applied", "%s cell=%d success=%s" \
					% [_current_task, _current_cell, applied])
			if npc.held_item != _item:
				_item = null   ## item freed itself (out of charges) — nothing left in hand
			_pick_next_task(npc)

func _tick_fetch(npc: NPC, delta: float) -> void:
	if npc.held_item != null:
		_item = npc.held_item
		_phase = "travel"
		npc.set_nav_target(approach_point(npc, _current_tray))
		return
	if _fetch_loose != null and is_instance_valid(_fetch_loose):
		if "is_held" in _fetch_loose and _fetch_loose.is_held:
			_fetch_loose = null
			_pick_next_task(npc)
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) <= NPCItemUser.PICKUP_RANGE:
			if not NPCItemUser.grab_loose(npc, _fetch_loose):
				_pick_next_task(npc)
		return
	if not _fetch_shelf.is_empty():
		var shelf: Node3D = _fetch_shelf.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_pick_next_task(npc)
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) <= NPCItemUser.SHELF_RANGE:
			if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
				_pick_next_task(npc)
		return
	_pick_next_task(npc)   ## nothing left to fetch — vanished between scan and now

func done(_npc: NPC) -> bool:
	return _finished

func _release_current_cell(npc: NPC) -> void:
	if _current_tray != null and _current_cell != -1:
		NPCItemUser.release_cell(_current_tray, _current_cell, npc)

func debug_info() -> Dictionary:
	return {
		"activity": "gardening",
		"mode": mode,
		"phase": _phase,
		"task": _current_task,
		"tray": (_current_tray.name if _current_tray != null and is_instance_valid(_current_tray) else ""),
		"cell": _current_cell,
		"item": (display_name(_item) if _item != null else ""),
	}

func exit(npc: NPC) -> void:
	var detail: String = "phase=%s task=%s tray=%s cell=%d item=%s" \
		% [_phase, _current_task, (_current_tray.name if _current_tray != null and is_instance_valid(_current_tray) else "?"),
			_current_cell, (display_name(_item) if _item != null else "none")]
	_release_current_cell(npc)
	if _fetch_loose != null:
		NPCItemUser.release_item(_fetch_loose)
	if not _fetch_shelf.is_empty():
		NPCItemUser.release_item(_fetch_shelf.get("item"))
	on_session_exit(npc, "gardening", _finished, detail)
