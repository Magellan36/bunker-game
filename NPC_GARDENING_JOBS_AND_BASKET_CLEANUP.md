# NPC Gardening: Soil/Planting (Autonomous) + Fertilizing (Command) + Seed-Type Menu + Basket-Aware Produce Cleanup (Aug 2026)

**Files:** `scripts/world/farming/FarmingTray.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`, new file
`scripts/ui/npc/NPCSeedSelectMenuUI.gd`, `docs/systems/npc/README.md`,
`HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing.

---

## Context — what already exists, confirmed against live code

Harvest already works (existing JobBoard `HARVEST` type, per-plant). What's
new here is everything *around* it: soil, planting (with replant
preference), fertilizing, a seed-type request menu, and basket-aware
produce pickup during Cleaning.

`FarmingTray.gd` already exposes exactly the player-parity hooks needed:
`has_open_soil_cell()` / `fill_first_open_soil_cell()`,
`has_open_plantable_cell()` / `plant_first_open_cell(type)`,
`has_open_fertilizable_cell()` / `fertilize_first_open_cell(tier)`. Each
consumable item (`BagOfSoilItem`, `SeedItem`, `FertilizerItem`) already
has a real `on_use()` that finds a nearby valid tray and calls the
matching tray method, decrementing its own charge count and freeing/
spawning an empty-bag item exactly like the player experiences. NPCs
reuse these `on_use()` methods directly (hold the item, walk in range,
call `item.on_use()`) rather than reimplementing charge/consumption
logic — guarantees identical behavior to the player, and zero duplicated
mechanics to keep in sync later.

One real gap: harvesting immediately blanks `planted_type[cell]` via
`clear_cell()`, and nothing else remembers what grew there. "Prefer
replanting what was there" needs new memory that survives harvest — Part
A adds it directly on `FarmingTray`, also structured to be forward-safe
for a later gardening feature.

---

## Part A — `FarmingTray.gd`: replant memory + future tray-assignment hook

**Anchor:**

```gdscript
var soil_filled:  Array[bool]   = []
var planted_type: Array[String] = []
var plant_refs:   Array[FarmPlant] = []
```

Replace with:

```gdscript
var soil_filled:  Array[bool]   = []
var planted_type: Array[String] = []
var plant_refs:   Array[FarmPlant] = []

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

**Anchor:**

```gdscript
func _ready() -> void:
	cell_count = clampi(cell_count, 1, 2)
	soil_filled.resize(cell_count)
	planted_type.resize(cell_count)
	plant_refs.resize(cell_count)
	cell_prepped_fertilizer.resize(cell_count)
	_soil_mesh_instances.resize(cell_count)
	for i: int in range(cell_count):
		soil_filled[i]  = false
		planted_type[i] = ""
		plant_refs[i]   = null
		cell_prepped_fertilizer[i] = ""
		_soil_mesh_instances[i] = null
```

Replace with:

```gdscript
func _ready() -> void:
	cell_count = clampi(cell_count, 1, 2)
	soil_filled.resize(cell_count)
	planted_type.resize(cell_count)
	plant_refs.resize(cell_count)
	cell_prepped_fertilizer.resize(cell_count)
	_soil_mesh_instances.resize(cell_count)
	last_planted_type.resize(cell_count)
	assigned_plant_type.resize(cell_count)
	for i: int in range(cell_count):
		soil_filled[i]  = false
		planted_type[i] = ""
		plant_refs[i]   = null
		cell_prepped_fertilizer[i] = ""
		_soil_mesh_instances[i] = null
		last_planted_type[i] = ""
		assigned_plant_type[i] = ""
```

**Anchor:**

```gdscript
## Plants into the first open (soiled, unplanted) cell. Returns true on success.
func plant_first_open_cell(plant_type: String) -> bool:
	for i: int in range(cell_count):
		if soil_filled[i] and planted_type[i] == "":
			planted_type[i] = plant_type
			var plant: FarmPlant = FarmPlant.new()
			add_child(plant)
			plant.setup(self, i, plant_type)
			plant.position = Vector3(_cell_local_x(i), SOIL_LAYER_Y, 0.0)
			plant_refs[i] = plant
			## B7 — if this cell had prepped fertilizer, apply it now and clear it
			if cell_prepped_fertilizer[i] != "":
				plant.apply_fertilizer(cell_prepped_fertilizer[i])
				cell_prepped_fertilizer[i] = ""
			return true
	return false
```

Replace with:

```gdscript
## Plants into the first open (soiled, unplanted) cell. Returns true on success.
func plant_first_open_cell(plant_type: String) -> bool:
	for i: int in range(cell_count):
		if soil_filled[i] and planted_type[i] == "":
			planted_type[i] = plant_type
			last_planted_type[i] = plant_type   ## Aug 2026 — survives the eventual harvest, unlike planted_type
			var plant: FarmPlant = FarmPlant.new()
			add_child(plant)
			plant.setup(self, i, plant_type)
			plant.position = Vector3(_cell_local_x(i), SOIL_LAYER_Y, 0.0)
			plant_refs[i] = plant
			## B7 — if this cell had prepped fertilizer, apply it now and clear it
			if cell_prepped_fertilizer[i] != "":
				plant.apply_fertilizer(cell_prepped_fertilizer[i])
				cell_prepped_fertilizer[i] = ""
			return true
	return false

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

Stop and report on anchor mismatch — no improvisation.

---

## Part B — `NPC.gd`: availability checks + scoring constant

**Anchor:** near the existing `JOB_PRIORITY_WEIGHTS`:

```gdscript
const JOB_PRIORITY_WEIGHTS: Dictionary = {
	"HARVEST": 1.3,
	"REPLACE_FILTER": 1.0,
	"REFUEL": 1.0,
	"CLEANING": 0.5,
}
```

Replace with:

```gdscript
const JOB_PRIORITY_WEIGHTS: Dictionary = {
	"HARVEST": 1.3,
	"REPLACE_FILTER": 1.0,
	"REFUEL": 1.0,
	"CLEANING": 0.5,
	"GARDENING": 0.8,
}
```

**Anchor:** near `const REFUEL_BASE_SCORE: float = 8.0`:

```gdscript
const REFUEL_BASE_SCORE: float = 8.0
```

Add immediately after it:

```gdscript
## Gardening session (Aug 2026, autonomous) — soil-filling + planting.
## Moderate priority: useful busywork, but shouldn't outrank real jobs.
const GARDENING_BASE_SCORE: float = 6.0
```

**Anchor:** immediately after `has_refuel_target_available()` (end of
that function — place this new function right after it):

```gdscript
## Autonomous-trigger availability check for GardeningActivity — mirrors
## has_cleaning_target_available()'s shape. True if ANY tray needs soil
## (and a spare Bag of Soil exists somewhere) OR ANY tray has an open
## plantable cell (and ANY seed of ANY type exists somewhere — the exact
## type match, if any, is resolved per-tray at pick time via
## FarmingTray.get_next_plant_preference(), not here).
func has_gardening_target_available() -> bool:
	var any_tray: bool = false
	var needs_soil: bool = false
	var needs_plant: bool = false
	for tray: Node in get_tree().get_nodes_in_group("farming_tray"):
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
		for item: Node in get_tree().get_nodes_in_group("pickup"):
			if is_instance_valid(item) and item is BagOfSoilItem and not (("is_held" in item) and item.is_held) and not item.is_in_group("shelved"):
				return true
		for shelf: Node in get_tree().get_nodes_in_group("shelving"):
			if not is_instance_valid(shelf) or not ("slots" in shelf):
				continue
			for stack in shelf.slots:
				if stack is Array and not stack.is_empty() and stack.back() is BagOfSoilItem:
					return true
	if needs_plant:
		for item: Node in get_tree().get_nodes_in_group("pickup"):
			if is_instance_valid(item) and item is SeedItem and not (("is_held" in item) and item.is_held) and not item.is_in_group("shelved"):
				return true
		for shelf: Node in get_tree().get_nodes_in_group("shelving"):
			if not is_instance_valid(shelf) or not ("slots" in shelf):
				continue
			for stack in shelf.slots:
				if stack is Array and not stack.is_empty() and stack.back() is SeedItem:
					return true
	return false
```

Stop and report on anchor mismatch — no improvisation.

---

## Part C — `NPCBrain.gd`: `GardeningActivity` + `CommandGardeningActivity`

### Design recap

One session activity, mirroring `CleaningActivity`/`RefuelActivity`'s
shape exactly (fetch → travel → apply → loop). Mode-restricted for the
three entry points:

- **Autonomous** (`mode = "auto"`): soil-filling and planting both, using
  each tray's `get_next_plant_preference()` per cell (falls back to any
  available seed type if the preferred one is out of stock).
- **"Add soil to all trays"** (`mode = "soil_only"`): soil-filling only,
  never plants even if cells become plantable.
- **"Plant seeds"** with a chosen type (`mode = "plant_only"`,
  `forced_seed_type` set): also fills soil as a prerequisite (can't plant
  into unsoiled cells), but planting uses ONLY the requested type — no
  fallback substitution, since the player explicitly asked for one
  species; if none are in stock, that tray's planting is simply skipped
  (matches "only use existing stock, skip if unavailable" from the
  refuel/cleaning precedent already established).
- **"Fertilize the trays"** (`mode = "fertilize_only"`): fertilizing
  only, any tier, command-only exactly as specified — never triggered
  autonomously.

Priority within a session: soil > plant > fertilize (skipping whichever
categories the mode excludes), nearest tray within whichever category is
currently needed.

### C1 — Register in `setup()`'s candidate list

**Anchor:**

```gdscript
	_candidates = [
		WanderActivity.new(),
		SitActivity.new(),
		LieActivity.new(),
		DrinkActivity.new(),
		EatActivity.new(),
		RelaxActivity.new(),
		TalkActivity.new(),
		GiveToFriendActivity.new(),
		CleaningActivity.new(),
		RefuelActivity.new(),
		PutAwayHeldItemActivity.new(),
```

Replace with:

```gdscript
	_candidates = [
		WanderActivity.new(),
		SitActivity.new(),
		LieActivity.new(),
		DrinkActivity.new(),
		EatActivity.new(),
		RelaxActivity.new(),
		TalkActivity.new(),
		GiveToFriendActivity.new(),
		CleaningActivity.new(),
		RefuelActivity.new(),
		PutAwayHeldItemActivity.new(),
		GardeningActivity.new(),
```

### C2 — The activity itself

**Anchor:** add directly after `RefuelActivity`'s closing (place it
alongside the other session activities — exact position isn't
load-bearing):

```gdscript
class GardeningActivity extends NPCActivity:
	## Gardening (Aug 2026, sustained session) — mirrors CleaningActivity/
	## RefuelActivity's fetch→travel→apply→[loop] shape. Autonomous by
	## default (mode "auto": soil + planting, using each tray's own
	## replant preference); mode-restricted variants back the three
	## player commands — see this file's own header comment above for the
	## full breakdown. Fertilizing is NEVER autonomous — only reachable
	## via mode "fertilize_only", which only CommandGardeningActivity ever
	## constructs.
	var mode: String = "auto"            ## "auto" | "soil_only" | "plant_only" | "fertilize_only"
	var forced_seed_type: String = ""    ## only meaningful for "plant_only" — no fallback substitution when set

	var _item: RigidBody3D = null        ## currently held soil bag / seed packet / fertilizer
	var _current_tray: Node = null
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

	## Finds the nearest tray needing whichever task category applies
	## next (soil > plant > fertilize, mode-restricted), sets _current_
	## tray/_current_task, and kicks off fetch/travel for it. Ends the
	## session if nothing eligible remains.
	func _pick_next_task(npc: NPC) -> void:
		_current_tray = null
		_current_task = ""

		if mode != "fertilize_only":
			_current_tray = _nearest_tray_needing(npc, "has_open_soil_cell")
			if _current_tray != null:
				_current_task = "soil"

		if _current_tray == null and mode != "soil_only" and mode != "fertilize_only":
			_current_tray = _nearest_tray_needing(npc, "has_open_plantable_cell")
			if _current_tray != null:
				_current_task = "plant"

		if _current_tray == null and mode == "fertilize_only":
			_current_tray = _nearest_tray_needing(npc, "has_open_fertilizable_cell")
			if _current_tray != null:
				_current_task = "fertilize"

		if _current_tray == null:
			_finished = true
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "gardening session ended", "nothing left to do (mode=%s)" % mode)
			return

		if NPCDebug.enabled:
			NPCDebug.log_cleaning(npc, "gardening target picked", "%s task=%s" % [_current_tray.name, _current_task])

		if _item != null and _item_matches_task(npc):
			_phase = "travel"
			npc.set_nav_target(_approach_point(npc, _current_tray))
			return
		_phase = "fetch"
		_start_fetch(npc)

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

	## Does the currently-held item match what _current_task needs? For
	## "plant" with forced_seed_type set, the type must match exactly —
	## no substitution once the player has explicitly asked for one.
	func _item_matches_task(npc: NPC) -> bool:
		if _item == null:
			return false
		match _current_task:
			"soil": return _item is BagOfSoilItem
			"plant":
				if not (_item is SeedItem):
					return false
				if forced_seed_type != "":
					return _item.seed_type == forced_seed_type
				return true   ## autonomous — already fetched to satisfy some preference; re-validated at fetch time, not here
			"fertilize": return _item is FertilizerItem
			_: return false
		return false

	func _start_fetch(npc: NPC) -> void:
		var filt: Callable = _fetch_filter_for_task(npc)
		var loose: RigidBody3D = NPCItemUser.find_loose_item(npc, filt)
		var shelf_pick: Dictionary = {} if loose != null else NPCItemUser.find_shelved_item(npc, filt)
		var tgt: Node3D = loose if loose != null \
			else (shelf_pick.get("shelf") as Node3D if not shelf_pick.is_empty() else null)
		if tgt == null:
			## Nothing available for this specific task right now — skip
			## this tray/task and try the next one rather than ending the
			## whole session over one shortage.
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "gardening fetch failed", "nothing available for task=%s (mode=%s, forced_type=%s)" \
					% [_current_task, mode, forced_seed_type])
			_pick_next_task(npc)
			return
		if loose != null:
			if not NPCItemUser.claim_item(loose, npc):
				_pick_next_task(npc)
				return
			_fetch_loose = loose
		else:
			if not NPCItemUser.claim_item(shelf_pick.get("item"), npc):
				_pick_next_task(npc)
				return
			_fetch_shelf = shelf_pick
		npc.set_nav_target(tgt.global_position)

	## Aug 2026 — autonomous planting prefers this tray's own
	## get_next_plant_preference() (falls back to ANY seed type if the
	## preferred one is unavailable — matches "prefer X unless X isn't
	## available"). A forced_seed_type (player command) is exact-match
	## only, no fallback.
	func _fetch_filter_for_task(npc: NPC) -> Callable:
		match _current_task:
			"soil":
				return func(item: Node) -> bool: return item is BagOfSoilItem
			"plant":
				if forced_seed_type != "":
					var want: String = forced_seed_type
					return func(item: Node) -> bool: return item is SeedItem and item.seed_type == want
				var preferred: String = _current_tray.get_next_plant_preference() if _current_tray != null else ""
				if preferred != "":
					var pref: String = preferred
					return func(item: Node) -> bool: return item is SeedItem and item.seed_type == pref
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
				## Reuses the item's own real on_use() — identical mechanic
				## to the player (finds a nearby valid tray itself, applies,
				## consumes a charge, spawns EmptyBagItem/frees at zero —
				## nothing about consumption is duplicated here).
				_item.on_use()
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "gardening applied", "%s at %s" % [_current_task, _current_tray.name])
				if npc.held_item != _item:
					## Item freed itself (out of charges) — nothing left in hand
					_item = null
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

	func exit(npc: NPC) -> void:
		if _fetch_loose != null:
			NPCItemUser.release_item(_fetch_loose)
		if not _fetch_shelf.is_empty():
			NPCItemUser.release_item(_fetch_shelf.get("item"))
		## Deliberately does NOT drop _item on exit — matches
		## PutAwayHeldItemActivity's safety net, which will pick up and
		## put away any leftover held item if this gets interrupted
		## mid-carry with nothing else claiming it.
```

**Anchor:** add `CommandGardeningActivity` directly after
`GardeningActivity`'s closing:

```gdscript
class CommandGardeningActivity extends NPCActivity:
	## Backs all three player-issued gardening requests ("Add soil to all
	## trays", "Plant seeds" with a chosen type, "Fertilize the trays") —
	## delegates straight to a mode-restricted GardeningActivity, same
	## pattern as CommandCleaningActivity/CommandRefuelActivity.
	var mode: String = "auto"
	var forced_seed_type: String = ""
	var _inner: NPCActivity = null

	func label() -> String:
		return _inner.label() if _inner != null else "Idle"

	func score(_npc: NPC) -> float:
		return 0.0

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		var g: GardeningActivity = GardeningActivity.new()
		g.mode = mode
		g.forced_seed_type = forced_seed_type
		_inner = g
		_inner.enter(npc)
		if _inner.done(npc):
			_inner = null

	func tick(npc: NPC, delta: float) -> void:
		if _inner != null:
			_inner.tick(npc, delta)

	func done(npc: NPC) -> bool:
		return _inner == null or _inner.done(npc)

	func exit(npc: NPC) -> void:
		if _inner != null:
			_inner.exit(npc)
		_inner = null
```

Stop and report on anchor mismatch — no improvisation.

---

## Part D — `NPCTalkMenuUI.gd`: two direct commands + the seed-type submenu

### D1 — New menu entries

**Anchor:**

```gdscript
const NPC_JOB_MENU_ENTRIES: Array[Dictionary] = [
	{"type": "HARVEST", "label": "Harvest the plants", "action_desc": "heading to harvest", "empty_desc": "nothing ready to harvest"},
	{"type": "REPLACE_FILTER", "label": "Replace the water filters", "action_desc": "heading to replace a filter", "empty_desc": "no filters need replacing"},
	{"type": "REFUEL", "label": "Refuel the generator", "action_desc": "heading to refuel", "empty_desc": "nothing needs refueling"},
	{"type": "CLEANING", "label": "Clean the bunker", "action_desc": "heading to clean up", "empty_desc": "nothing to clean right now"},
]
```

Replace with:

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

Note: `PLANT_SEEDS`'s `action_desc`/`empty_desc` are unused — that
button never calls `_issue_command()` directly, it opens the new
submenu instead (see D2).

### D2 — Dispatch: two direct commands + the submenu opener

**Anchor:**

```gdscript
	if job_type == "CLEANING":
		## Aug 2026 — swap the generic empty_desc for a specific reason
		## when we have one, so the player sees exactly WHY instead of a
		## blanket "nothing to clean right now" every time.
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_cleaning_unavailable_reason"):
			var reason: String = _npc.get_cleaning_unavailable_reason()
			if reason != "" and CLEANING_UNAVAILABLE_REASONS.has(reason):
				empty_desc = String(CLEANING_UNAVAILABLE_REASONS[reason])
		_issue_command(NPCBrain.CommandCleaningActivity.new(), action_desc, empty_desc)
	elif job_type == "REFUEL":
		## Aug 2026 — same specific-reason treatment as Cleaning.
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_refuel_unavailable_reason"):
			var rreason: String = _npc.get_refuel_unavailable_reason()
			if rreason != "" and REFUEL_UNAVAILABLE_REASONS.has(rreason):
				empty_desc = String(REFUEL_UNAVAILABLE_REASONS[rreason])
		_issue_command(NPCBrain.CommandRefuelActivity.new(), action_desc, empty_desc)
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)
```

Replace with:

```gdscript
	if job_type == "CLEANING":
		## Aug 2026 — swap the generic empty_desc for a specific reason
		## when we have one, so the player sees exactly WHY instead of a
		## blanket "nothing to clean right now" every time.
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_cleaning_unavailable_reason"):
			var reason: String = _npc.get_cleaning_unavailable_reason()
			if reason != "" and CLEANING_UNAVAILABLE_REASONS.has(reason):
				empty_desc = String(CLEANING_UNAVAILABLE_REASONS[reason])
		_issue_command(NPCBrain.CommandCleaningActivity.new(), action_desc, empty_desc)
	elif job_type == "REFUEL":
		## Aug 2026 — same specific-reason treatment as Cleaning.
		if _npc != null and is_instance_valid(_npc) and _npc.has_method("get_refuel_unavailable_reason"):
			var rreason: String = _npc.get_refuel_unavailable_reason()
			if rreason != "" and REFUEL_UNAVAILABLE_REASONS.has(rreason):
				empty_desc = String(REFUEL_UNAVAILABLE_REASONS[rreason])
		_issue_command(NPCBrain.CommandRefuelActivity.new(), action_desc, empty_desc)
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
```

**Anchor:** immediately after `_on_job_command_pressed()`'s closing (right
before the `# ─── Ask About (Part 23) ───` section comment):

```gdscript
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

Stop and report on anchor mismatch — no improvisation.

---

## Part E — New file: `scripts/ui/npc/NPCSeedSelectMenuUI.gd`

Built entirely on the same `UIKit` helpers every other modal in the
project already uses (`build_modal_backdrop`, `build_centered_panel`,
`make_button`) — no new styling invented, matches
`PauseMenuUI.gd`/`GraphicsSettingsPanel.gd`'s established shape.

```gdscript
extends CanvasLayer
class_name NPCSeedSelectMenuUI
## NPCSeedSelectMenuUI.gd (Aug 2026)
## Standalone popup for "Plant seeds" — lists every seed TYPE currently
## available (loose or shelved, any quantity) as its own button. Picking
## one issues NPCBrain.CommandGardeningActivity(mode="plant_only",
## forced_seed_type=that type) on the NPC that opened this, then closes.
## Deliberately its own small CanvasLayer rather than more rows crammed
## into NPCTalkMenuUI — see that file's _open_seed_select_menu().

const PANEL_W: float = 320.0
const ROW_H: float = 36.0

var _npc: Node = null
var _backdrop: ColorRect = null
var _panel: Panel = null
var _vbox: VBoxContainer = null

func open(npc: Node) -> void:
	_npc = npc
	layer = 210   ## above NPCTalkMenuUI
	var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.FARMING)
	_backdrop = UIKit.build_modal_backdrop()
	add_child(_backdrop)
	_backdrop.gui_input.connect(_on_backdrop_input)

	var available_types: Array = _find_available_seed_types()
	var panel_h: float = 90.0 + float(max(available_types.size(), 1)) * (ROW_H + 6.0)
	_panel = UIKit.build_centered_panel(PANEL_W, panel_h, theme)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vbox.offset_left = 16.0
	_vbox.offset_right = -16.0
	_vbox.offset_top = 16.0
	_vbox.offset_bottom = -16.0
	_panel.add_child(_vbox)

	var header: Label = UIKit.make_section_label("What kind of seed?", theme)
	_vbox.add_child(header)

	if available_types.is_empty():
		var none_label: Label = UIKit.make_row_label("No seeds available right now.", theme)
		_vbox.add_child(none_label)
	else:
		for seed_type: String in available_types:
			var display: String = PlantDatabase.get_display_name(seed_type)
			var btn: Button = UIKit.make_button(display, _on_type_pressed.bind(seed_type), ROW_H)
			_vbox.add_child(btn)

	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	_vbox.add_child(spacer)
	var cancel: Button = UIKit.make_button("Cancel", _on_cancel_pressed, ROW_H)
	_vbox.add_child(cancel)

## Enumerates every species with at least one loose or shelved SeedItem
## right now — deliberately NOT every species in PlantDatabase, so the
## player only ever sees types that could actually succeed.
func _find_available_seed_types() -> Array:
	var found: Dictionary = {}   ## seed_type -> true
	for item: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(item) or not (item is SeedItem):
			continue
		if ("is_held" in item and item.is_held) or item.is_in_group("shelved"):
			continue
		found[item.seed_type] = true
	for shelf: Node in get_tree().get_nodes_in_group("shelving"):
		if not is_instance_valid(shelf) or not ("slots" in shelf):
			continue
		for stack in shelf.slots:
			if stack is Array and not stack.is_empty() and stack.back() is SeedItem:
				found[stack.back().seed_type] = true
	var out: Array = found.keys()
	out.sort()
	return out

func _on_type_pressed(seed_type: String) -> void:
	if _npc != null and is_instance_valid(_npc) and ("brain" in _npc) and _npc.brain != null:
		var cmd: NPCBrain.CommandGardeningActivity = NPCBrain.CommandGardeningActivity.new()
		cmd.mode = "plant_only"
		cmd.forced_seed_type = seed_type
		_npc.brain.force_command(cmd)
		var label: String = PlantDatabase.get_display_name(seed_type)
		NotificationManager.notify(UIKit.Domain.FARMING, NotificationManager.Severity.INFO,
			"%s: heading to plant %s seeds" % [_npc.npc_name if "npc_name" in _npc else "NPC", label])
	_close()

func _on_cancel_pressed() -> void:
	_close()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _close() -> void:
	queue_free()
```

---

## Part F — Basket-aware produce cleanup (the Cleaning tweak)

### Design

`FarmProduceItem` already joins `"basket_storable"`, and `Basket.gd`
already implements the real player mechanic: while holding a Basket, `E`
stashes the nearest `"basket_storable"` item into it (`InteractionSystem`
handles this today for the player; NPCs need their own equivalent call,
not a key-press). Scope: **only when the Cleaning target is produce**
(`FarmProduceItem`) does the basket-preference kick in — this doesn't
change how any other item type gets cleaned.

Rather than touching `CleaningActivity`'s already-hardened fetch/deliver
logic broadly, this is a small, targeted branch: when
`CleaningActivity._pick_next_target()` lands on a `FarmProduceItem` and a
`Basket` exists (loose or shelved) with room, fetch/hold the Basket
first (if not already holding one), then instead of picking the produce
up into the hand, walk to it and stash it into the basket directly —
mirroring the real `E`-while-holding-basket action, not a normal
pickup+carry+deliver cycle. The basket itself then gets delivered to
storage once full or once the session's produce is exhausted, exactly
like any other carried item would.

**Anchor:** `CleaningActivity`'s member variable block:

```gdscript
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
```

Replace with:

```gdscript
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
```

**Anchor:** inside `_pick_next_target()`, right where a viable
destination is confirmed for a non-trash item — add the produce/basket
branch immediately before that `break`:

```gdscript
			var category: String = npc._classify_organizable_item(_item)
			if npc.find_cleaning_destination(false, _item) != null:
				break   ## viable destination confirmed for THIS item — commit and go fetch it
```

Replace with:

```gdscript
			var category: String = npc._classify_organizable_item(_item)
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
			if npc.find_cleaning_destination(false, _item) != null:
				break   ## viable destination confirmed for THIS item — commit and go fetch it
```

**Anchor:** the fetch-phase block inside `tick()` — right at the very
start of the `if npc.held_item == null:` fetch branch, add the
basket-fetch detour before the existing shelved/held checks:

```gdscript
		if npc.held_item == null:
			## Fetch phase
			if "is_held" in _item and _item.is_held:
```

Replace with:

```gdscript
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
```

**Anchor:** immediately after `CleaningActivity`'s existing `exit()` (the
one that releases `_item`'s claim) — add the new helper functions right
after it, before `debug_info()`:

```gdscript
	func exit(npc: NPC) -> void:
		if _item != null:
			if _item.has_method("set_nav_obstacle_enabled") and "is_held" in _item and not _item.is_held:
				_item.set_nav_obstacle_enabled(true)
			NPCItemUser.release_item(_item)
		_item = null
```

Add immediately after it:

```gdscript
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
				% [_display_name(_item), _basket.slots.size() - _basket.slots.count(null), _basket.slots.size()])
		_item = null
```

Note: once `_basket` is non-null and full (or nothing left to stash),
the NEXT `_pick_next_target()` cycle sees `npc.held_item == _basket` (a
`Basket`, not a `FarmProduceItem` or any other classified type) — the
existing classification/destination logic (`_classify_organizable_item`)
treats an unrecognized held type as "heavy" by default (not
`inventory_item`-gated), which correctly routes the full basket to a
real Shelving object rather than attempting an End Table/Dresser. No
further change needed there — verify this live rather than assuming,
since it depends on `Basket` never having joined `"inventory_item"`
(confirmed already, from `Basket.gd`'s own header comment: "Not in the
'inventory_item' group — too big to carry in a pocket slot").

Stop and report on anchor mismatch — no improvisation.

---

## Testing

### Gardening (autonomous)
1. Set up an empty tray, a Bag of Soil, and Tomato seeds loose nearby.
   Let an NPC idle — confirm it autonomously fills soil, then plants
   Tomato.
2. Harvest that Tomato plant (via the existing Harvest job or manually),
   leave only Onion seeds available this time — confirm autonomous
   replanting tries Tomato first (none available), falls back to Onion,
   and plants that.
3. With both soil and seeds needed across multiple trays, confirm an NPC
   sweeps all of them in one session, not just one tray then stopping.
4. With NO seeds of any type anywhere, confirm the session still fills
   soil (if needed) and ends cleanly rather than erroring.

### Commands
5. "Add soil to all trays" with some trays also needing planting —
   confirm ONLY soil gets filled, planting is never attempted even for
   now-plantable cells.
6. "Plant seeds" → confirm the new popup lists only species currently in
   stock (verify against actual loose/shelved seeds), and Cancel closes
   it with no command issued.
7. Pick a specific type with none in stock somehow changing between
   opening the menu and pressing it (edge case) — confirm the NPC simply
   skips that tray/task rather than substituting a different type.
8. "Fertilize the trays" — confirm it never triggers autonomously (watch
   a long idle period with fertilizable cells present and no command
   issued — nothing should happen on its own), and confirm the command
   itself works and uses any available tier.

### Basket-aware produce cleanup
9. Harvest several plants so multiple `FarmProduceItem`s are on the
   ground, with a Basket available. Ask an NPC to clean — confirm it
   fetches the Basket FIRST, then walks to each produce item and stashes
   it (item visibly disappears into the basket, not carried in hand),
   continuing until the basket is full or produce runs out.
10. Confirm the full (or partially full) basket then gets delivered to
    real Shelving (not an End Table/Dresser) once produce collection is
    done for the session.
11. Confirm non-produce items in the same session are completely
    unaffected — normal carry-and-deliver behavior, no basket
    involvement.
12. With no Basket available anywhere, confirm produce still gets
    cleaned normally via the regular carry-in-hand path (no basket
    detour blocks it).

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
91. Autonomous gardening: confirm an idle NPC fills soil and plants
    seeds on its own, preferring the last-planted type per cell and
    falling back to any available type when that's out of stock.
92. "Add soil to all trays" only fills soil, never plants. "Plant seeds"
    opens a new popup listing only in-stock species; picking one plants
    ONLY that type, no substitution. "Fertilize the trays" never
    triggers on its own, only via the command.
93. Ask an NPC to clean with harvested produce and a Basket both
    present — confirm it fetches the basket first and stashes produce
    into it (not hand-carried), then delivers the basket to real
    shelving once done. Non-produce cleaning is unaffected.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Gardening (Soil/Plant/Fertilize) + Seed-Type Menu + Basket Produce Cleanup (Aug 2026)

- Added FarmingTray.last_planted_type (survives harvest, unlike
  planted_type) and assigned_plant_type (unused placeholder for a future
  gardening-side tray-assignment feature — already wired into
  get_next_plant_preference()'s priority order so no NPC code will need
  to change once that ships).
- Added NPCBrain.GardeningActivity/CommandGardeningActivity — session
  activity mirroring Cleaning/Refuel's shape. Mode "auto" (autonomous,
  soil+planting, replant-preference-aware) is the default; "soil_only",
  "plant_only" (with forced_seed_type, no fallback substitution), and
  "fertilize_only" back the three player commands. Fertilizing is
  reachable ONLY via command, never autonomous. Reuses each consumable
  item's own real on_use() (BagOfSoilItem/SeedItem/FertilizerItem) rather
  than duplicating charge/consumption logic — identical mechanic to the
  player by construction.
- Added NPCTalkMenuUI rows for "Add soil to all trays" and "Fertilize
  the trays" (direct commands), and "Plant seeds" (opens a new standalone
  popup, NPCSeedSelectMenuUI.gd, listing only currently-in-stock seed
  species — built on the same UIKit modal helpers every other popup in
  the project uses).
- CleaningActivity now special-cases FarmProduceItem: if a Basket is
  available, fetches it first and stashes produce into it (mirroring
  Basket.gd's real "E while holding basket" player mechanic) instead of
  hand-carrying each item individually, then delivers the basket to
  storage once done. All other item types are unaffected.

Files touched: `scripts/world/farming/FarmingTray.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/ui/npc/NPCSeedSelectMenuUI.gd` (new).
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
