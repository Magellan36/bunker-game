# Unified "Farming" Request + Full Interruption Fix + Comprehensive NPC Debug (Aug 2026)

**Files:** `scripts/npc/NPCBrain.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCDebug.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/ui/menus/AdminMenu.gd`, delete
`scripts/ui/npc/NPCSeedSelectMenuUI.gd`, `docs/systems/npc/README.md`,
`HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing.

---

## Part 1 — Sable's bug, root-caused (and it's bigger than last time)

Traced against live code. This is a **different** manifestation of the
same underlying class of bug as the "carries soil then drops it" issue
fixed last time — that fix (protecting the item once physically held)
was correct but incomplete. Sable's case happens **before** ever picking
the soil up, during the walk toward it:

`GardeningActivity.interruptible()` currently returns `_item == null` —
only false (protected) once the NPC is physically holding something.
During the walk-*toward* a loose Bag of Soil (fetch-approach, before
pickup), `_item` is still null, so the activity is fully interruptible.
Every `THINK_INTERVAL` (~1s), `_think()` re-scores every candidate — and
with the clutter-escalation change from a few plans back,
`CleaningActivity`'s score climbs with total clutter in the level. With
enough clutter (the log shows Sable's level had 30+ loose items),
Cleaning's escalated score can exceed Gardening's own score (max ~6.2)
plus the 8.0 switch margin, and Gardening loses the fetch approach
entirely — matching exactly what was seen: closer soil succeeded (less
time exposed to a think-cycle firing mid-walk), farther soil failed
(more time = higher odds of losing the race), and the NPC dropped the
task and coasted off under whatever velocity it had until the next
think-cycle picked something new (the residual-velocity "straight line"
artifact — same mechanism as before, just not yet covered since the
earlier fix only zeroed velocity in `PutAwayHeldItemActivity`'s own drop
branch).

The correct fix is the same one already used elsewhere in this codebase
for exactly this situation — `PutAwayHeldItemActivity` already declares
itself `return false` (never interruptible) with the comment "short and
self-contained — always let it finish rather than get preempted
mid-delivery." Gardening and Refuel sessions are the same shape (short,
self-contained, always making forward progress), so they get the same
treatment. Genuine emergencies are unaffected — `_recover_from_stuck()`'s
`stop_current()` bypasses `interruptible()` entirely already (a
force-abort, not a scoring decision), so a truly stuck NPC still breaks
out correctly.

---

## Part 2 — Unify Harvest / Plant / Soil into one "Farming" request

### Design

One new mode on `GardeningActivity`, `"farming"` — command-only (never
autonomously scored, same as every other non-`"auto"` mode already).
Priority order exactly as specified: harvest anything ready, then plant
anywhere plantable (reading each cell's own seed lock/replant memory —
no separate type-selection step needed, which is also why the seed
picker popup goes away entirely), then fill soil anywhere empty. Ends
when none of the three apply anywhere.

Autonomous Harvest (the existing JobBoard `HARVEST` job type) and
autonomous soil/plant (`GardeningActivity`'s existing `"auto"` mode) are
**both left completely untouched** — this is purely a new command-only
path, not a change to what NPCs do on their own.

### 2a — `NPCBrain.gd`: `GardeningActivity` — full replacement

Replace the **entire existing `GardeningActivity` class** (from
`class GardeningActivity extends NPCActivity:` through its closing
`exit()`) with:

```gdscript
class GardeningActivity extends NPCActivity:
	## Gardening (Aug 2026, sustained session) — mirrors CleaningActivity/
	## RefuelActivity's fetch→travel→apply→[loop] shape, per-CELL (a
	## double tray's two cells are independent and workable by two
	## different NPCs at once, same as HARVEST already does per-plant).
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
	##                       lock/replant memory — no separate type
	##                       selection needed), then soil. Ends when none
	##                       of the three apply anywhere.
	## Aug 2026 — now fully non-interruptible (see interruptible() below)
	## — was only protected once physically holding an item, which left
	## the walk-TOWARD a loose item (before ever picking it up)
	## vulnerable to a high-scoring competitor (e.g. clutter-escalated
	## Cleaning) winning the very next think-cycle and aborting the
	## approach entirely. Root-caused from a live debug capture showing
	## exactly this: closer soil succeeded, farther soil didn't.
	var mode: String = "auto"            ## "auto" | "soil_only" | "fertilize_only" | "farming"
	var forced_seed_type: String = ""    ## unused now that seed type is always read from the tray — kept only so CommandGardeningActivity's signature doesn't need to change

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
		if not npc.has_gardening_target_available():
			return 0.0
		return NPC.GARDENING_BASE_SCORE * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight("GARDENING")

	func interruptible() -> bool:
		## Aug 2026 — see this class's header comment. No genuinely safe
		## mid-session gap exists (unlike Cleaning's real between-items
		## gap) — a new target is claimed immediately on completion of
		## the last one. stuck-recovery's stop_current() still bypasses
		## this entirely for real emergencies.
		return false

	func enter(npc: NPC) -> void:
		_finished = false
		if npc.held_item != null and (npc.held_item is BagOfSoilItem or npc.held_item is SeedItem or npc.held_item is FertilizerItem):
			_item = npc.held_item
		_pick_next_task(npc)

	## Finds the nearest eligible task (harvest > soil > plant, mode-
	## restricted — fertilize stays tray-wide/separate), claims it, and
	## kicks off fetch/travel. Ends the session if nothing eligible
	## remains anywhere.
	func _pick_next_task(npc: NPC) -> void:
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
			## this class's own header comment. Tray-wide, exactly as
			## before.
			_current_tray = _nearest_tray_needing(npc, "has_open_fertilizable_cell")
			if _current_tray != null:
				_current_task = "fertilize"

		if _current_tray == null:
			_finished = true
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "gardening session ended", "nothing left to do (mode=%s)" % mode)
			return

		if _current_task != "fertilize" and not NPCItemUser.claim_cell(_current_tray, _current_cell, npc):
			## Another NPC's Gardening session already has this cell —
			## try again fresh; a different cell (or nothing) will come up.
			_pick_next_task(npc)
			return

		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "gardening target picked", "%s cell=%d task=%s" \
				% [_current_tray.name, _current_cell, _current_task])

		if _current_task == "harvest":
			## No item involved — go straight to travel.
			_phase = "travel"
			npc.set_nav_target(_approach_point(npc, _current_tray))
			return

		if _item != null and _item_matches_task(npc):
			_phase = "travel"
			npc.set_nav_target(_approach_point(npc, _current_tray))
			return
		_phase = "fetch"
		_start_fetch(npc)

	## Nearest tray/cell with a ready-to-harvest plant. Only ever used by
	## mode "farming" (the unified player request) — autonomous
	## harvesting stays exclusively on the existing JobBoard HARVEST path
	## to avoid two independent systems both deciding to harvest the same
	## plant.
	func _nearest_ready_plant(npc: NPC) -> Dictionary:
		var best: Dictionary = {}
		var best_d: float = INF
		for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
			if not is_instance_valid(tray):
				continue
			for i: int in range(tray.cell_count):
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
	## "plant"), skipping cells claimed by another NPC and — for "plant"
	## — skipping cells whose hard seed lock (get_cell_seed_lock()) can't
	## currently be satisfied at all (no matching seed anywhere). A
	## locked cell NEVER falls back to a different type — the lock is
	## absolute, autonomous or commanded.
	func _nearest_open_cell(npc: NPC, kind: String) -> Dictionary:
		var best: Dictionary = {}
		var best_d: float = INF
		for tray: Node in npc.get_tree().get_nodes_in_group("farming_tray"):
			if not is_instance_valid(tray):
				continue
			for i: int in range(tray.cell_count):
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

	func _item_matches_task(npc: NPC) -> bool:
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

	## Two-stage: try the resolved locked/preferred type first; for a
	## SOFT preference only (no lock), fall back to ANY seed type if that
	## specific one isn't available. A hard lock never falls back — the
	## earlier cell-selection pass already guaranteed a locked cell's
	## type is in stock before this ever runs.
	func _start_fetch(npc: NPC) -> void:
		var found: bool = _try_fetch_with_filter(npc, _fetch_filter_for_task())
		if not found and _current_task == "plant" and _current_tray != null \
				and _current_tray.get_cell_seed_lock(_current_cell) == "":
			found = _try_fetch_with_filter(npc, func(item: Node) -> bool: return item is SeedItem)
		if not found:
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "gardening fetch failed", "nothing available for task=%s cell=%d" \
					% [_current_task, _current_cell])
			_pick_next_task(npc)

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

	## Aug 2026 — seed type is ALWAYS read from the tray now (lock, then
	## replant memory, then "any") — no separate player-chosen type
	## exists anymore.
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

	func _approach_point(npc: NPC, target: Node) -> Vector3:
		var t3: Node3D = target as Node3D
		var to_npc: Vector3 = npc.global_position - t3.global_position
		to_npc.y = 0.0
		if to_npc.length() < 0.01:
			to_npc = Vector3(0.0, 0.0, 1.0)
		return t3.global_position + to_npc.normalized() * 1.0

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
					## Unchanged, tray-wide — see this class's header comment
					## on why fertilizer stays exactly as it was.
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
			npc.set_nav_target(_approach_point(npc, _current_tray))
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

	## Aug 2026 — structured snapshot for the new "Print NPC Job Debug
	## State" dump (see NPCDebug.dump_job_state()).
	func debug_info() -> Dictionary:
		return {
			"activity": "gardening",
			"mode": mode,
			"phase": _phase,
			"task": _current_task,
			"tray": (_current_tray.name if _current_tray != null and is_instance_valid(_current_tray) else ""),
			"cell": _current_cell,
			"item": (_display_name(_item) if _item != null else ""),
		}

	static func _display_name(item: Node) -> String:
		if item == null:
			return "?"
		return item.get_display_name() if item.has_method("get_display_name") else str(item.name)

	func exit(npc: NPC) -> void:
		## Aug 2026 — log exactly what was in progress at the moment of
		## exit (natural completion vs. an outside interrupt look
		## identical from here — the NEW _think()/stuck logging elsewhere
		## in this plan is what tells them apart) — this is the detail
		## that was missing when this bug was first reported.
		if NPCDebug.enabled and not _finished:
			NPCDebug.log_cleaning(npc, "gardening exited early", "phase=%s task=%s tray=%s cell=%d item=%s" \
				% [_phase, _current_task, (_current_tray.name if _current_tray != null and is_instance_valid(_current_tray) else "?"),
					_current_cell, (_display_name(_item) if _item != null else "none")])
		_release_current_cell(npc)
		if _fetch_loose != null:
			NPCItemUser.release_item(_fetch_loose)
		if not _fetch_shelf.is_empty():
			NPCItemUser.release_item(_fetch_shelf.get("item"))
		npc.velocity = Vector3.ZERO   ## Aug 2026 — don't leave the NPC coasting in whatever direction it was last walking
```

Stop and report on anchor mismatch — no improvisation.

### 2b — `NPCBrain.gd`: `RefuelActivity` — same interruptibility fix + debug_info() + exit() logging

**Anchor:**

```gdscript
	func interruptible() -> bool:
		return _phase != "refuel"   ## mid-pour, commit; between generators/fetching, fine to interrupt
```

Replace with:

```gdscript
	func interruptible() -> bool:
		## Aug 2026 — same fix and same reasoning as GardeningActivity
		## (see that class's header comment) — was only protected during
		## the final "refuel" sub-phase, leaving the fetch-approach and
		## travel-with-can phases vulnerable to the identical bug. Not
		## separately reported for Refuel yet, but the mechanism is
		## identical, so fixed the same way rather than waiting.
		return false
```

**Anchor:** locate `RefuelActivity`'s existing `exit()` (releases
`_fetch_loose`/`_fetch_shelf`, no `debug_info()` present today) and
replace it with:

```gdscript
	func debug_info() -> Dictionary:
		return {
			"activity": "refuel",
			"phase": _phase,
			"can_held": _can != null and is_instance_valid(_can),
			"current_generator": (_current_gen.name if _current_gen != null and is_instance_valid(_current_gen) else ""),
			"refueled_this_session": _refueled_ids.size(),
		}

	func exit(npc: NPC) -> void:
		if NPCDebug.enabled and not _finished:
			NPCDebug.log_cleaning(npc, "refuel exited early", "phase=%s can_held=%s generator=%s" \
				% [_phase, _can != null and is_instance_valid(_can),
					(_current_gen.name if _current_gen != null and is_instance_valid(_current_gen) else "none")])
		if _fetch_loose != null:
			NPCItemUser.release_item(_fetch_loose)
		if not _fetch_shelf.is_empty():
			NPCItemUser.release_item(_fetch_shelf.get("item"))
		if _finished and npc.held_item != null and npc.held_item == _can:
			NPCItemUser.drop_held(npc)   ## session truly over — set the (empty or spare) can down
		npc.velocity = Vector3.ZERO   ## Aug 2026 — same reasoning as GardeningActivity's exit()
```

Verify the exact existing `exit()` body against live code before
replacing — the fetch-release lines and the final-drop condition should
match what's already there; only the new `debug_info()` function, the
early-exit log line, and the trailing `npc.velocity = Vector3.ZERO` are
new. Stop and report on anchor mismatch — no improvisation.

---

## Part 3 — Rich interrupt/stuck logging (the actual "why was this dropped" answer)

### 3a — `NPCBrain.gd`: log the interrupt decision itself

**Anchor:**

```gdscript
	## Incumbent defends its seat: challenger needs margin AND permission.
	if _current.interruptible() and best_score > _current.score(_npc) + SWITCH_MARGIN:
		NPCDebug.log_activity(_npc, _current.label(), best.label())
		_current.exit(_npc)
		_start(best)
```

Replace with:

```gdscript
	## Incumbent defends its seat: challenger needs margin AND permission.
	if _current.interruptible() and best_score > _current.score(_npc) + SWITCH_MARGIN:
		## Aug 2026 — this is the exact moment an activity gets
		## preempted, and previously the ONLY thing logged was the bare
		## "X -> Y" label transition, with no indication of WHY —
		## whether it was a natural score win, by how much, or what the
		## incumbent's own score was. This was the missing piece when
		## diagnosing a session getting dropped for no visible reason.
		if NPCDebug.enabled:
			NPCDebug.log_interrupt(_npc, _current.label(), _current.score(_npc), best.label(), best_score, SWITCH_MARGIN)
		NPCDebug.log_activity(_npc, _current.label(), best.label())
		_current.exit(_npc)
		_start(best)
```

Stop and report on anchor mismatch — no improvisation.

### 3b — `NPC.gd`: attach current-activity context to the stuck log

**Anchor:**

```gdscript
func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	NPCDebug.log_stuck(self)
	var stuck_item: RigidBody3D = _find_stuck_obstruction()
```

Replace with:

```gdscript
func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	## Aug 2026 — was just "STUCK — aborting current activity", with no
	## indication of what the NPC was actually doing when it happened.
	## Include the current activity's label (and its debug_info() when
	## available) so the console shows exactly what got interrupted.
	var context: String = brain.current_label() if brain != null else "?"
	var info: Dictionary = brain.get_current_activity_debug_info() if brain != null else {}
	NPCDebug.log_stuck(self, context, info)
	var stuck_item: RigidBody3D = _find_stuck_obstruction()
```

Stop and report on anchor mismatch — no improvisation.

### 3c — `NPCDebug.gd`: new/expanded logging functions

**Anchor:**

```gdscript
static func log_stuck(npc: Node) -> void:
	if not enabled:
		return
	print("%s STUCK — aborting current activity and re-scoring" % _fmt(npc))
```

Replace with:

```gdscript
## Aug 2026 — context/info params added so the console shows WHAT was
## interrupted, not just that something was. `info` is whatever the
## current activity's debug_info() returned (empty for activities that
## don't implement it, e.g. Wander/Relax).
static func log_stuck(npc: Node, context: String = "?", info: Dictionary = {}) -> void:
	if not enabled:
		return
	var detail: String = ""
	if not info.is_empty():
		var parts: Array = []
		for key: String in info.keys():
			parts.append("%s=%s" % [key, str(info[key])])
		detail = " [%s]" % ", ".join(parts)
	print("%s STUCK while %s%s — aborting current activity and re-scoring" % [_fmt(npc), context, detail])
```

**Anchor:** immediately after `log_activity()`:

```gdscript
static func log_activity(npc: Node, from_label: String, to_label: String) -> void:
	if not enabled:
		return
	print("%s activity: %s -> %s" % [_fmt(npc), from_label, to_label])
```

Add immediately after it:

```gdscript
## Aug 2026 — logs the actual score comparison behind an interrupt
## decision, called right before log_activity() at the one place this
## decision is made (NPCBrain._think()). This is what answers "why did
## my NPC's job get dropped" directly, instead of needing to infer it
## from a bare label transition.
static func log_interrupt(npc: Node, from_label: String, from_score: float, to_label: String, to_score: float, margin: float) -> void:
	if not enabled:
		return
	print("%s INTERRUPTED: %s (score=%.2f) -> %s (score=%.2f, needed >%.2f)" \
		% [_fmt(npc), from_label, from_score, to_label, to_score, from_score + margin])
```

Stop and report on anchor mismatch — no improvisation.

### 3d — `NPCDebug.gd`: new "Print NPC Job Debug State" dump

Generalizes the existing Cleaning-only dump's "NPCs currently cleaning"
section into one that shows every NPC's current activity and its full
`debug_info()`, whatever activity type that happens to be (Cleaning,
Gardening, Refuel, or any future one) — not filtered to a single
activity name.

**Anchor:** immediately after the existing `dump_cleaning_state()`
function and its `_describe_storage_room()` helper (add this new
function after `_describe_storage_room()`, not in the middle of it):

```gdscript
## Aug 2026 — one-shot snapshot of EVERY NPC's current activity and its
## full debug_info(), whatever that activity is. dump_cleaning_state()
## stays Cleaning-specific (JobBoard caches, storage occupancy) — this
## is the general-purpose complement for diagnosing Gardening/Refuel/
## anything else without needing a dedicated dump per activity type.
## Always prints regardless of `enabled` (an explicit on-demand request,
## same convention as dump_all()/dump_cleaning_state()).
static func dump_job_state(tree: SceneTree) -> void:
	print("═══ NPC Job Debug Dump ════════════════════════════════")
	var any_npc: bool = false
	for npc: Node in tree.get_nodes_in_group("npc"):
		if not is_instance_valid(npc):
			continue
		any_npc = true
		var npc_name: String = npc.npc_name if "npc_name" in npc else "?"
		var label: String = npc.brain.current_label() if ("brain" in npc and npc.brain != null) else "?"
		var info: Dictionary = {}
		if "brain" in npc and npc.brain != null and npc.brain.has_method("get_current_activity_debug_info"):
			info = npc.brain.get_current_activity_debug_info()
		if info.is_empty():
			print("  %s: %s" % [npc_name, label])
		else:
			var parts: Array = []
			for key: String in info.keys():
				parts.append("%s=%s" % [key, str(info[key])])
			print("  %s: %s [%s]" % [npc_name, label, ", ".join(parts)])
	if not any_npc:
		print("  (no NPCs)")
	print("═════════════════════════════════════════════════════════")
```

Stop and report on anchor mismatch — no improvisation.

### 3e — `AdminMenu.gd`: F7 row for the new dump

**Anchor:**

```gdscript
			["Print NPC Cleaning Debug State", _on_npc_print_cleaning_debug_pressed],
```

Replace with:

```gdscript
			["Print NPC Cleaning Debug State", _on_npc_print_cleaning_debug_pressed],
			["Print NPC Job Debug State", _on_npc_print_job_debug_pressed],
```

**Anchor:**

```gdscript
func _on_npc_print_cleaning_debug_pressed() -> void:
	NPCDebug.dump_cleaning_state(get_tree())
```

Replace with:

```gdscript
func _on_npc_print_cleaning_debug_pressed() -> void:
	NPCDebug.dump_cleaning_state(get_tree())

func _on_npc_print_job_debug_pressed() -> void:
	NPCDebug.dump_job_state(get_tree())
```

Stop and report on anchor mismatch — no improvisation.

---

## Part 4 — Talk menu: one "Farming" request, no seed-type popup

### 4a — `NPCTalkMenuUI.gd`: menu entries

**Anchor:**

```gdscript
const NPC_JOB_MENU_ENTRIES: Array[Dictionary] = [
	{"type": "HARVEST", "label": "Harvest the plants", "action_desc": "heading to harvest", "empty_desc": "nothing ready to harvest"},
	{"type": "REPLACE_FILTER", "label": "Replace the water filters", "action_desc": "heading to replace a filter", "empty_desc": "no filters need replacing"},
	{"type": "REFUEL", "label": "Refuel the generator", "action_desc": "heading to refuel", "empty_desc": "nothing needs refueling"},
	{"type": "CLEANING", "label": "Clean the bunker", "action_desc": "heading to clean up", "empty_desc": "nothing to clean right now"},
	{"type": "ADD_SOIL", "label": "Add soil to all trays", "action_desc": "heading to fill trays with soil", "empty_desc": "no trays need soil, or no soil available"},
	{"type": "FERTILIZE", "label": "Fertilize the trays", "action_desc": "heading to fertilize", "empty_desc": "nothing needs fertilizing, or none available"},
	{"type": "PLANT_SEEDS", "label": "Plant seeds", "action_desc": "", "empty_desc": ""},
]
```

Replace with:

```gdscript
const NPC_JOB_MENU_ENTRIES: Array[Dictionary] = [
	{"type": "REPLACE_FILTER", "label": "Replace the water filters", "action_desc": "heading to replace a filter", "empty_desc": "no filters need replacing"},
	{"type": "REFUEL", "label": "Refuel the generator", "action_desc": "heading to refuel", "empty_desc": "nothing needs refueling"},
	{"type": "CLEANING", "label": "Clean the bunker", "action_desc": "heading to clean up", "empty_desc": "nothing to clean right now"},
	{"type": "FARMING", "label": "Tend the farm", "action_desc": "heading to tend the farm", "empty_desc": "nothing to harvest, plant, or add soil to right now"},
	{"type": "FERTILIZE", "label": "Fertilize the trays", "action_desc": "heading to fertilize", "empty_desc": "nothing needs fertilizing, or none available"},
]
```

Note: `HARVEST` as a standalone entry, `ADD_SOIL`, and `PLANT_SEEDS` are
all removed — folded into the single `FARMING` entry (priority: harvest
→ plant → soil, per `GardeningActivity`'s `"farming"` mode). `FERTILIZE`
is unchanged — still its own separate, command-only request exactly as
before.

### 4b — `NPCTalkMenuUI.gd`: dispatch

**Anchor:**

```gdscript
	elif job_type == "ADD_SOIL":
		var soil_cmd: NPCBrain.CommandGardeningActivity = NPCBrain.CommandGardeningActivity.new()
		soil_cmd.mode = "soil_only"
		_issue_command(soil_cmd, action_desc, empty_desc)
	elif job_type == "FERTILIZE":
		var fert_cmd: NPCBrain.CommandGardeningActivity = NPCBrain.CommandGardeningActivity.new()
		fert_cmd.mode = "fertilize_only"
		_issue_command(fert_cmd, action_desc, empty_desc)
	elif job_type == "PLANT_SEEDS":
		## Aug 2026 — separate small popup instead of expanding this panel
		## further; see NPCSeedSelectMenuUI.gd. Picking a type there issues
		## the actual command back on this NPC.
		if _dialogue_label != null:
			_dialogue_label.text = "What kind of seed do you want?"
			_dialogue_label.visible = true
		_open_seed_select_menu()
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)

## Aug 2026 — opens the standalone seed-type picker (NPCSeedSelectMenuUI)
## as a top-layer popup over this panel. Built fresh each time rather than
## kept as a persistent child, matching how little state it needs.
func _open_seed_select_menu() -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var menu: NPCSeedSelectMenuUI = NPCSeedSelectMenuUI.new()
	get_tree().root.add_child(menu)
	menu.open(_npc)
```

Replace with:

```gdscript
	elif job_type == "FARMING":
		## Aug 2026 — unified request: harvest -> plant -> soil, in that
		## priority, in one session. Seed type for planting is always
		## read from each cell's own lock/replant memory now — no
		## separate player-chosen-type step exists anymore.
		var farm_cmd: NPCBrain.CommandGardeningActivity = NPCBrain.CommandGardeningActivity.new()
		farm_cmd.mode = "farming"
		_issue_command(farm_cmd, action_desc, empty_desc)
	elif job_type == "FERTILIZE":
		var fert_cmd: NPCBrain.CommandGardeningActivity = NPCBrain.CommandGardeningActivity.new()
		fert_cmd.mode = "fertilize_only"
		_issue_command(fert_cmd, action_desc, empty_desc)
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)
```

Stop and report on anchor mismatch — no improvisation.

### 4c — Delete `scripts/ui/npc/NPCSeedSelectMenuUI.gd`

No longer referenced anywhere. Delete the file entirely (or, if your
tooling can't delete, replace its contents with a single-line comment
noting it's retired — but a real delete is correct here, nothing else
in the project references this class).

**Also update** the header comment above `NPC_JOB_MENU_ENTRIES`:

**Anchor:**

```gdscript
## Centralized so a new job type later needs ONE entry here, nothing
## else. "type" must match JobBoard's job "type" string exactly
## (HARVEST/REPLACE_FILTER), or the literal strings "CLEANING"/"REFUEL"
## (routed to CommandCleaningActivity/CommandRefuelActivity instead of
## the generic CommandJobActivity, since neither is JobBoard-claimed).
```

Replace with:

```gdscript
## Centralized so a new job type later needs ONE entry here, nothing
## else. "type" must match JobBoard's job "type" string exactly
## (REPLACE_FILTER), or the literal strings "CLEANING"/"REFUEL"/
## "FARMING"/"FERTILIZE" (routed to their own Command*Activity instead
## of the generic CommandJobActivity, since none of the four are
## JobBoard-claimed). HARVEST is intentionally absent as a standalone
## entry — it's folded into "FARMING"'s priority order (harvest -> plant
## -> soil) — autonomous per-plant Harvest via JobBoard is untouched.
```

Stop and report on anchor mismatch — no improvisation.

---

## Testing

### Interruption fix
1. Reproduce Sable's exact scenario — a level with 30+ loose clutter
   items (so Cleaning's score is well escalated) and a tray needing
   soil some distance away. Request Farming/soil — confirm the NPC now
   walks the entire distance to the soil without being pulled away,
   regardless of how much clutter exists.
2. Confirm the same for Refuel over a long fetch/travel distance.
3. Confirm genuine stuck-recovery still works — wedge an NPC mid-
   Gardening or mid-Refuel and confirm `stop_current()` still correctly
   force-aborts it (this path was never gated by `interruptible()`).

### Unified Farming request
4. With a ready-to-harvest plant, an empty-but-soiled plantable cell,
   and an unsoiled cell all present, request "Tend the farm" — confirm
   strict priority: harvest happens first, then planting, then soil,
   all in one continuous session.
5. Confirm planting during this session reads each cell's own seed
   lock/replant memory correctly — no popup, no player-chosen type,
   and a locked cell is respected exactly as before.
6. Confirm autonomous Harvest (JobBoard) and autonomous soil/planting
   (`GardeningActivity` "auto" mode) are both completely unaffected —
   this only added a new command path.
7. Confirm "Fertilize the trays" still works exactly as before, still
   the only farming-related autonomous-never/command-only entry.

### Debug expansion
8. Force an interruption (e.g. contrive a high-scoring competitor) and
   confirm the console now prints an `INTERRUPTED:` line with both
   scores and the required margin, immediately before the activity
   transition line.
9. Force a stuck event during Gardening/Refuel/Cleaning and confirm the
   `STUCK while ...` line now names the actual activity and its
   debug_info() detail, not just "STUCK — aborting current activity."
10. Press F7 → "Print NPC Job Debug State" — confirm it shows every
    NPC's current activity and full debug_info(), correctly covering
    Cleaning, Gardening, and Refuel without needing three separate
    dumps.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
98. On a level with heavy clutter (so Cleaning's score is escalated),
    request Farming with a distant tray needing soil — confirm the NPC
    walks the entire distance without being pulled away.
99. Request "Tend the farm" with harvest, planting, and soil all needed
    at once — confirm strict priority order (harvest -> plant -> soil)
    in one session, with seed type always read from each cell, no
    popup.
100. Force an interrupt and a stuck event — confirm the console now
     shows an INTERRUPTED: line with both scores, and a STUCK while ...
     line naming the actual activity. Press F7 -> "Print NPC Job Debug
     State" — confirm it shows every NPC's current activity/debug info
     regardless of type.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Unified Farming Request, Full Interruption Fix, Comprehensive Debug (Aug 2026)

- Root-caused Sable's bug as a broader version of the earlier mid-carry
  interrupt fix: GardeningActivity/RefuelActivity were only non-
  interruptible during their FINAL sub-phase, leaving the walk-TOWARD a
  loose item (before ever picking it up) vulnerable to any high-scoring
  competitor (confirmed: clutter-escalated Cleaning) winning the next
  think-cycle (~1s) and aborting the approach — explaining why closer
  items succeeded and farther ones didn't. Both now return `false` from
  interruptible() (matching PutAwayHeldItemActivity's existing "short
  and self-contained" precedent) — non-interruptible for the whole
  session, with stuck-recovery's stop_current() unaffected since it
  never went through interruptible() in the first place.
- Unified Harvest/Plant/Soil into one "Tend the farm" Talk-menu request
  (GardeningActivity mode "farming"): strict priority harvest -> plant
  -> soil, ends when none apply anywhere. Autonomous Harvest (JobBoard)
  and autonomous soil/planting (mode "auto") are unchanged — this is a
  new command-only path only. Planting now always reads each cell's own
  seed lock/replant memory — the seed-type-selection popup
  (NPCSeedSelectMenuUI.gd) is retired/deleted, no longer needed.
  Fertilizer stays its own separate, command-only request.
- Comprehensive debug expansion: NPCBrain._think() now logs the exact
  score comparison behind every interrupt decision
  (NPCDebug.log_interrupt()); NPC._recover_from_stuck() now attaches
  the current activity's label + debug_info() to the stuck log
  (NPCDebug.log_stuck() signature expanded); added GardeningActivity/
  RefuelActivity debug_info() and early-exit logging (mirrors
  CleaningActivity's existing pattern); added a new generalized F7
  dump, "Print NPC Job Debug State"
  (NPCDebug.dump_job_state()), showing every NPC's current activity and
  full debug info regardless of activity type, complementing the
  existing Cleaning-specific dump.

Files touched: `scripts/npc/NPCBrain.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCDebug.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/ui/menus/AdminMenu.gd`; deleted
`scripts/ui/npc/NPCSeedSelectMenuUI.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
