# NPC Gardening: Migrate to Per-Cell Farming API + Seed Locks (Aug 2026)

**Files:** `scripts/npc/NPCItemUser.gd`, `scripts/world/farming/FarmingTray.gd`,
`scripts/world/items/BagOfSoilItem.gd`, `scripts/world/items/SeedItem.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/npc/JobBoard.gd`,
`docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting — this is unusually important
this time.** I checked live code before writing this: the Gardening
system from the last plan (`GardeningActivity`,
`CommandGardeningActivity`, the Talk-menu rows) **is already applied and
live**. The Farming thread's handover describes API changes
(`fill_soil_at_cell`, `plant_seed_at_cell`, `get_cell_seed_lock`, removal
of `fill_first_open_soil_cell`/`plant_first_open_cell`) that **are not
yet applied** to `FarmingTray.gd` as of this writing — it still has the
old tray-wide functions. Verify which state the repo is actually in
before touching anything; if the Farming thread's changes have landed
since this was written, some anchors below may need re-locating (the
logic doesn't change, just possibly line numbers/exact surrounding text).

---

## Cross-thread reconciliation — read this before the diffs

Two things from my last plan need addressing now that the Farming
thread has actually built the "real" version of something I anticipated:

1. **My `assigned_plant_type`/`get_next_plant_preference()` are now
   redundant.** I added those specifically as a placeholder for "a
   future gardening-side tray-assignment feature" — the Farming thread's
   `get_cell_seed_lock(cell_index)` **is** that feature, actually built.
   Keeping both would mean two disconnected "lock this cell to a type"
   concepts that could drift out of sync. Part A removes mine in favor
   of consuming their real API directly. `last_planted_type` (the
   *soft* "what grew here before" memory, distinct from a hard lock)
   stays — it's a different, complementary concept they didn't build and
   still don't need to.

2. **`GardeningActivity` currently calls `item.on_use()`**, which
   resolves "nearest valid tray/cell to the ITEM's own position" — fine
   when there was only one relevant cell per tray to worry about, but
   wrong now: once two cells in the same tray can be independently
   targeted (soil in cell 0, plant in cell 1, potentially two different
   NPCs), `on_use()` might act on whichever cell happens to be nearer to
   where the NPC is standing, not the specific cell this NPC claimed and
   walked to. Part C adds a small `apply_at_cell()` method to
   `BagOfSoilItem.gd`/`SeedItem.gd` — a thin index-aware sibling to
   `on_use()`, mirroring its charge/signal/cleanup logic exactly, just
   targeting a specific cell instead of resolving one by proximity. This
   touches Farming-owned files, but minimally and non-destructively (adds
   a method next to the existing one, changes nothing about `on_use()`
   or the player-facing path) — flag it to the Farming thread if they'd
   rather own this specific addition themselves.
   **Fertilizer is deliberately left untouched** — the handover
   explicitly says not to build against `FertilizerItem`/
   `fertilize_first_open_cell()` yet since it's likely to change shape
   next. `GardeningActivity`'s fertilize path keeps calling
   `_item.on_use()` tray-wide, completely unchanged.

3. **New requirement, not in my last plan:** per-cell claiming. Two
   NPCs could now legitimately work the two cells of the same double
   tray simultaneously — but without a claim, two NPCs' `GardeningActivity`
   instances could also both decide the *same* cell needs attention and
   both walk over before either discovers the other got there first.
   Part B adds a lightweight cell-claim system to `NPCItemUser.gd`,
   mirroring its existing item-claim shape exactly.

---

## Part A — `FarmingTray.gd`: remove the now-redundant placeholder

**Anchor:**

```gdscript
## Aug 2026 — per-cell replant memory. Unlike planted_type (blanked by
## clear_cell() on every harvest), this survives specifically so "prefer
## replanting what was there before" has something to read afterward.
## Kept in sync by plant_first_open_cell() below for BOTH player- and
## NPC-driven planting, so it's never a separate thing to maintain.
var last_planted_type: Array[String] = []

## Aug 2026 — future gardening-feature hook (not built yet — a later
## pass will let the player lock a tray/cell to one species via its own
## UI). Every cell defaults to "" (unassigned) until that ships; nothing
## writes this yet except that future feature, but
## get_next_plant_preference() below already reads it FIRST, so no NPC-
## side code will need to change once tray assignment exists.
var assigned_plant_type: Array[String] = []
```

Replace with:

```gdscript
## Aug 2026 — per-cell replant memory. Unlike planted_type (blanked by
## clear_cell() on every harvest), this survives specifically so "prefer
## replanting what was there before" has something to read afterward.
## Kept in sync by whichever plant-a-cell function is live (player- and
## NPC-driven planting both go through it) so it's never a separate thing
## to maintain. This is a SOFT preference only — distinct from and
## unrelated to get_cell_seed_lock()'s hard per-cell constraint; NPC
## Gardening consults the lock first and only falls back to this when a
## cell has no lock at all.
var last_planted_type: Array[String] = []
```

**Anchor:** wherever the resize block currently reads (verify exact
surrounding lines against live code — this may already read differently
if the Farming thread's own pass landed first):

```gdscript
	last_planted_type.resize(cell_count)
	assigned_plant_type.resize(cell_count)
```

Replace with:

```gdscript
	last_planted_type.resize(cell_count)
```

**Anchor:**

```gdscript
		last_planted_type[i] = ""
		assigned_plant_type[i] = ""
```

Replace with:

```gdscript
		last_planted_type[i] = ""
```

**Anchor:** the entire existing `get_next_plant_preference()` function:

```gdscript
## Aug 2026 — what type should go in the NEXT open plantable cell, in
## priority order: assigned_plant_type (future feature, see its own
## comment above) > last_planted_type (what grew here before) > "" (no
## preference at all — any available type is fine). Returns "" if there's
## no open plantable cell right now. NPCGardeningActivity uses this for
## autonomous planting; an explicit player-requested seed type (via the
## Plant Seeds menu) bypasses this entirely and is never overridden by it.
func get_next_plant_preference() -> String:
	for i: int in range(cell_count):
		if soil_filled[i] and planted_type[i] == "":
			if i < assigned_plant_type.size() and assigned_plant_type[i] != "":
				return assigned_plant_type[i]
			if i < last_planted_type.size() and last_planted_type[i] != "":
				return last_planted_type[i]
			return ""
	return ""
```

Delete this function entirely — `GardeningActivity` now resolves
per-cell preference itself (reading `get_cell_seed_lock(i)` and
`last_planted_type[i]` directly), since it needs to know which of the
two applies for its own fallback-vs-no-fallback branching, which a
single combined string return can't express.

**Anchor:** wherever `plant_first_open_cell()` (or, if the Farming
thread's own pass already landed first, `plant_seed_at_cell()`) sets
`last_planted_type[i] = plant_type` — leave that line exactly as-is
regardless of which function currently contains it; just delete the
`assigned_plant_type` reference from its own doc comment if present.

Stop and report on anchor mismatch — no improvisation. If
`FarmingTray.gd` already has `fill_soil_at_cell()`/`plant_seed_at_cell()`/
`get_cell_seed_lock()` live by the time you reach this file, skip
straight to confirming `last_planted_type[i] = plant_type` still fires
inside whichever function now does the actual planting — that's the one
thing here that has to keep existing regardless of which pass landed
first.

---

## Part B — `NPCItemUser.gd`: per-cell claim system

**Anchor:** immediately after the existing `is_claimed_by_other()` (end
of the item-claim block, right before the `# ─── Target search ───`
section comment):

```gdscript
static func is_claimed_by_other(item: Node, npc: Node) -> bool:
	if item == null:
		return false
	var claimant: int = _claims.get(item.get_instance_id(), 0)
	return claimant != 0 and claimant != npc.get_instance_id()
```

Add immediately after it:

```gdscript
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
	if claimant != 0 and claimant != npc.get_instance_id():
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
	return claimant != 0 and claimant != npc.get_instance_id()
```

Stop and report on anchor mismatch — no improvisation.

---

## Part C — Index-aware apply methods (mirrors `on_use()`, targets a specific cell)

**File:** `scripts/world/items/BagOfSoilItem.gd`

**Anchor:** immediately after the existing `on_use()` (its full body,
ending at the `if _charges <= 0:` block that spawns `EmptyBagItem`):

```gdscript
	if _charges <= 0:
		EmptyBagItem.spawn_at(get_parent(), tray.global_position)
		queue_free()
```

Add immediately after it (still inside/after `on_use()`, as a sibling
function):

```gdscript
## Aug 2026 (NPC Gardening thread) — index-aware counterpart to on_use(),
## for callers that have already resolved a SPECIFIC cell (e.g. via a
## per-cell claim) rather than "nearest cell to my own position." Mirrors
## on_use() exactly — same charge decrement, same signal, same
## EmptyBagItem-at-zero cleanup — just targets fill_soil_at_cell(cell_index)
## instead of resolving a cell itself. Flag to the Farming thread if this
## doesn't fit however fill_soil_at_cell() ends up shaped.
func apply_at_cell(tray: FarmingTray, cell_index: int) -> bool:
	if not tray.fill_soil_at_cell(cell_index):
		return false
	_charges -= 1
	charge_changed.emit()
	_update_target_highlight(null)
	if _charges <= 0:
		EmptyBagItem.spawn_at(get_parent(), tray.global_position)
		queue_free()
	return true
```

**File:** `scripts/world/items/SeedItem.gd`

**Anchor:** immediately after the existing `on_use()` (its full body,
ending at the `if _charges <= 0: queue_free()` line):

```gdscript
	if _charges <= 0:
		_charges -= 1 == 0   ## placeholder — do not use, see actual live text
```

(The exact surrounding lines of the live `on_use()` were captured
earlier in this thread's history as:)

```gdscript
	tray.plant_first_open_cell(seed_type)
	...
	_charges -= 1
	charge_changed.emit()
	_update_target_highlight(null)

	if _charges <= 0:
		queue_free()   ## No "empty packet" object — seeds don't have one, unlike soil/fertilizer bags
```

**Anchor (use this one — locate the real line, ignore the placeholder
above):**

```gdscript
	if _charges <= 0:
		queue_free()   ## No "empty packet" object — seeds don't have one, unlike soil/fertilizer bags
```

Add immediately after it (as a sibling function to `on_use()`):

```gdscript
## Aug 2026 (NPC Gardening thread) — index-aware counterpart to on_use(),
## same reasoning as BagOfSoilItem.apply_at_cell(). Uses this instance's
## own seed_type (same source on_use() reads) rather than taking a type
## parameter — by the time an NPC is holding a specific SeedItem, its
## type is already fixed and already the one that was fetched to satisfy
## whatever cell this is being applied to.
func apply_at_cell(tray: FarmingTray, cell_index: int) -> bool:
	if not tray.plant_seed_at_cell(cell_index, seed_type):
		return false
	_charges -= 1
	charge_changed.emit()
	_update_target_highlight(null)
	if _charges <= 0:
		queue_free()
	return true
```

Stop and report on anchor mismatch — no improvisation. If
`fill_soil_at_cell()`/`plant_seed_at_cell()` don't exist yet on
`FarmingTray.gd` when you reach this part, hold this part until Part A's
prerequisite (the Farming thread's own change) has actually landed —
these two methods call it directly and won't compile otherwise.

---

## Part D — `NPCBrain.gd`: `GardeningActivity` rewritten per-cell

Replace the **entire existing `GardeningActivity` class** (everything
from `class GardeningActivity extends NPCActivity:` through its closing
`exit()` — confirmed as already-live code, not hypothetical) with:

```gdscript
class GardeningActivity extends NPCActivity:
	## Gardening (Aug 2026, sustained session) — mirrors CleaningActivity/
	## RefuelActivity's fetch→travel→apply→[loop] shape, now operating
	## per-CELL rather than per-tray (Farming thread's handover: a double
	## tray's two cells are independent and must be workable by two
	## different NPCs at once, exactly like two ready plants in a double
	## tray already post two independent HARVEST jobs). Autonomous by
	## default (mode "auto": soil + planting); mode-restricted variants
	## back the three player commands — see this file's own header
	## comment above for the full breakdown. Fertilizing is NEVER
	## autonomous (mode "fertilize_only" only, command-only) and stays
	## tray-wide/on_use()-based per the Farming thread's explicit "don't
	## build against FertilizerItem yet" note.
	var mode: String = "auto"            ## "auto" | "soil_only" | "plant_only" | "fertilize_only"
	var forced_seed_type: String = ""    ## only meaningful for "plant_only" — never overrides a cell's hard seed lock

	var _item: RigidBody3D = null        ## currently held soil bag / seed packet / fertilizer
	var _current_tray: FarmingTray = null
	var _current_cell: int = -1          ## -1 for the fertilize path, which stays tray-wide
	var _current_task: String = ""       ## "soil" | "plant" | "fertilize"
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
		return _phase != "apply"   ## mid-application, commit; between tasks, fine to interrupt

	func enter(npc: NPC) -> void:
		_finished = false
		if npc.held_item != null and (npc.held_item is BagOfSoilItem or npc.held_item is SeedItem or npc.held_item is FertilizerItem):
			_item = npc.held_item
		_pick_next_task(npc)

	## Finds the nearest eligible CELL for whichever task category
	## applies next (soil > plant, mode-restricted; fertilize stays
	## tray-wide, unaffected by any of this), claims it, and kicks off
	## fetch/travel. Ends the session if nothing eligible remains.
	func _pick_next_task(npc: NPC) -> void:
		_release_current_cell(npc)
		_current_tray = null
		_current_cell = -1
		_current_task = ""

		if mode != "fertilize_only":
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

		if _item != null and _item_matches_task(npc):
			_phase = "travel"
			npc.set_nav_target(_approach_point(npc, _current_tray))
			return
		_phase = "fetch"
		_start_fetch(npc)

	## Scans every farming_tray's cells for the given kind ("soil" or
	## "plant"), skipping cells claimed by another NPC and — for "plant"
	## — skipping cells whose hard seed lock (get_cell_seed_lock()) can't
	## currently be satisfied at all (no matching seed anywhere), per the
	## Farming thread's own recommended discovery logic. A locked cell
	## NEVER falls back to a different type, autonomous or commanded —
	## the lock is absolute.
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
					if lock != "":
						if forced_seed_type != "" and forced_seed_type != lock:
							continue   ## player asked for a different type than this cell allows — skip, never override a lock
						if not _seed_type_available(npc, lock):
							continue   ## locked type not in stock anywhere — skip silently, per Farming thread's own guidance
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
				if forced_seed_type != "":
					return _item.seed_type == forced_seed_type
				return true   ## soft preference — re-validated at fetch time, not here
			"fertilize": return _item is FertilizerItem
			_: return false
		return false

	## Two-stage: try the resolved preferred/locked/forced type first; for
	## a SOFT preference only (no lock, no forced command), fall back to
	## ANY seed type if that specific one isn't available — matches
	## "prefer X unless X isn't available." A hard lock or an explicit
	## player-requested type NEVER falls back (the earlier cell-selection
	## pass already guaranteed a locked cell's type is in stock before
	## this ever runs — see _nearest_open_cell()).
	func _start_fetch(npc: NPC) -> void:
		var found: bool = _try_fetch_with_filter(npc, _fetch_filter_for_task())
		if not found and _current_task == "plant" and _current_tray != null \
				and _current_tray.get_cell_seed_lock(_current_cell) == "" and forced_seed_type == "":
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

	func _fetch_filter_for_task() -> Callable:
		match _current_task:
			"soil":
				return func(item: Node) -> bool: return item is BagOfSoilItem
			"plant":
				var lock: String = _current_tray.get_cell_seed_lock(_current_cell) if _current_tray != null else ""
				var want: String = lock if lock != "" else forced_seed_type
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
				if _item == null or not is_instance_valid(_item) or _current_tray == null or not is_instance_valid(_current_tray):
					_pick_next_task(npc)
					return
				var applied: bool = true
				if _current_task == "fertilize":
					## Unchanged, tray-wide — see this class's header comment
					## on why fertilizer stays exactly as it was.
					_item.on_use()
				else:
					## Index-aware apply — see Part C. Targets the SPECIFIC
					## claimed cell, not "nearest to the item."
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

	func exit(npc: NPC) -> void:
		_release_current_cell(npc)
		if _fetch_loose != null:
			NPCItemUser.release_item(_fetch_loose)
		if not _fetch_shelf.is_empty():
			NPCItemUser.release_item(_fetch_shelf.get("item"))
		## Deliberately does NOT drop _item on exit — matches
		## PutAwayHeldItemActivity's safety net, which will pick up and
		## put away any leftover held item if this gets interrupted
		## mid-carry with nothing else claiming it.
```

Stop and report on anchor mismatch — no improvisation. `CommandGardeningActivity`
(the wrapper class right after this one) needs **no changes at all** —
it only ever sets `mode`/`forced_seed_type` and delegates, both of which
are unchanged in shape.

---

## Part E — `NPC.gd` and `JobBoard.gd`: no functional changes, one doc cleanup

`NPC.has_gardening_target_available()` needs no change — it only checks
coarse tray-level existence (`has_open_soil_cell()`/
`has_open_plantable_cell()`, both confirmed unchanged/still-live by the
Farming thread's own handover §3), which is a fine approximation for
"is autonomous Gardening worth entering at all." The precise per-cell/
seed-lock decision now happens inside `GardeningActivity._pick_next_task()`
itself — if that coarse check is ever slightly too optimistic (e.g. every
open cell turns out to be locked to an unavailable type), the activity
just enters and ends immediately, which is a harmless, self-correcting
edge case, not a bug worth adding complexity to prevent.

**File:** `scripts/npc/JobBoard.gd`

**Anchor:** locate the header's `FUTURE WORK` line (exact wording may
have shifted — find it rather than assuming):

```gdscript
## FUTURE WORK: planting, cooking, water-collection, repair jobs — each is
```

If it still lists "planting" as future work, update to drop it (Gardening
now exists, just not JobBoard-based) — this is a pure doc-accuracy
cleanup, not a functional change, and low priority if the exact wording
has already drifted from this anchor by the time you get here.

---

## Testing

1. **Per-cell independence.** Empty both cells of a double tray. Get two
   NPCs gardening at once (autonomous or via command) — confirm one
   works cell 0 while the other works cell 1 of the SAME tray
   simultaneously, without either waiting on or interfering with the
   other.
2. **Cell claim correctness.** Confirm a claimed cell is never picked by
   a second NPC's `_pick_next_task()` while still claimed, and confirm
   the claim releases correctly (interrupt one NPC mid-travel to that
   cell — confirm a different NPC can claim it shortly after, not stuck
   permanently claimed).
3. **Seed lock respected, autonomous.** Lock one cell to a specific
   species (however the Farming thread's own UI sets
   `get_cell_seed_lock()` once it exists — or set it directly for testing
   if that UI isn't built yet). Confirm autonomous planting NEVER plants
   anything else there, and skips it entirely (not looping/retrying) if
   that species isn't in stock.
4. **Seed lock overrides a forced command.** With a locked cell and the
   player requesting a DIFFERENT specific type via "Plant seeds" —
   confirm that locked cell is skipped, not overridden, while other
   unlocked cells still get the requested type.
5. **Soft preference still falls back.** An unlocked cell with
   `last_planted_type` set to a species with zero current stock — confirm
   autonomous planting falls back to any available species (unchanged
   behavior from before, just re-verify it survived the rewrite).
6. **Fertilizer completely unaffected.** Confirm "Fertilize the trays"
   still works exactly as before this plan — tray-wide, `on_use()`-based,
   no per-cell claiming involved at all.
7. **Charge/consumption parity.** Confirm `apply_at_cell()` behaves
   identically to `on_use()` from the player's perspective — same charge
   decrement, same `EmptyBagItem` spawn at zero for soil, same `queue_free()`
   at zero for seeds.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
94. Two NPCs gardening the same double tray at once — confirm each
    works its own cell (soil in one, planting in the other) without
    conflict, and confirm a cell claim releases correctly if an NPC gets
    interrupted mid-travel to it.
95. Lock a cell to a specific seed type — confirm autonomous planting
    never substitutes a different type there (skips if unavailable
    rather than looping), and confirm an explicit "Plant seeds" request
    for a different type skips that locked cell rather than overriding
    the lock.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Gardening Migrated to Per-Cell Farming API + Seed Locks (Aug 2026)

- Reconciled with the Farming thread's per-cell FarmingTray API
  (fill_soil_at_cell/plant_seed_at_cell/get_cell_seed_lock, replacing the
  old tray-wide fill_first_open_soil_cell/plant_first_open_cell).
  Removed my own now-redundant assigned_plant_type/
  get_next_plant_preference() (a placeholder for exactly the feature the
  Farming thread has now actually built) — last_planted_type (soft
  replant preference, distinct from a hard lock) stays.
- GardeningActivity rewritten to operate per-CELL, not per-tray, mirroring
  HARVEST's existing one-job-per-ready-plant shape — a double tray's two
  cells can now be worked by two different NPCs simultaneously. Added a
  matching per-cell claim system (NPCItemUser.claim_cell()/release_cell()/
  is_cell_claimed_by_other()) to prevent two NPCs targeting the same cell.
- Seed locks (get_cell_seed_lock()) are respected as an ABSOLUTE
  constraint by both autonomous planting and player-forced type
  requests — never substituted, cell skipped silently if the locked
  type isn't in stock, exactly per the Farming thread's own recommended
  discovery logic.
- Added BagOfSoilItem.apply_at_cell()/SeedItem.apply_at_cell() — thin,
  index-aware siblings to on_use(), needed because on_use() resolves the
  nearest cell to the ITEM's position, which is no longer guaranteed to
  be the specific cell an NPC claimed and walked to. Mirror on_use()'s
  charge/signal/cleanup logic exactly; nothing about consumption is
  duplicated elsewhere.
- Fertilizer intentionally NOT touched — stays tray-wide/on_use()-based,
  per the Farming thread's explicit note that FertilizerItem is likely to
  change shape in a follow-up pass.

Files touched: `scripts/npc/NPCItemUser.gd`,
`scripts/world/farming/FarmingTray.gd`, `scripts/world/items/BagOfSoilItem.gd`,
`scripts/world/items/SeedItem.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/npc/JobBoard.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
