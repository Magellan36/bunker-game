# NPC Cleanup → Light Storage (End Table/Dresser) + Refuel Session Redesign (Aug 2026)

**Files:** `scripts/npc/NPCItemUser.gd`, `scripts/npc/JobBoard.gd`,
`scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/world/furniture/LightStorage.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing — do not assume the previous
session's fixes are the only changes present.

---

## Context

Two requests from Brannon, investigated against live code:

1. NPCs should be able to carry lighter items (fuel can, water bottle —
   anything the player can put in an End Table/Dresser) into those
   furniture pieces as part of Cleaning, the same way they already
   organize onto shelves. This needs to be built so a future container
   type (Fridge for food, Trash Can for trash) can be added without
   reworking the routing logic.
2. The "Refuel the Generators" request doesn't seem to detect generators
   that aren't critically low, and even when it works, it only ever
   fully refuels a single generator rather than sweeping the whole
   bunker. Redesign it into a proper multi-generator session: fetch one
   jerry can, visit every generator that isn't full, refuel each until
   full or the can runs dry, and never revisit a generator already
   topped off in that same session.

I found **three separate, confirmed issues** while investigating, in
order of how directly they explain what Brannon is seeing. Part A is the
most likely direct cause of "can't read generators below 100%" and is a
genuine, previously-unflagged bug affecting more than just refueling —
fix it first and re-test before assuming Part C's redesign alone
explains everything.

---

## Part A — Dead group name: NPCs can never find items already on a shelf

### Root cause

`NPCItemUser.find_shelved_item()` and `JobBoard._spare_exists()`'s
shelf-scanning loop both search `get_tree().get_nodes_in_group("shelf")`.
**Nothing in the entire project ever joins a group called `"shelf"`.**
Every real shelf/storage object (`Shelving.gd`, and `LightStorage.gd` —
End Table/Dresser) joins `"shelving"` instead (confirmed by grepping
every `add_to_group()` call in both files). This means:

- `find_shelved_item()` — used by `EatActivity`/`DrinkActivity`'s
  shelf-fallback search and `JobActivity`'s fetch-from-shelf fallback for
  Replace Filter/Refuel — has always silently returned nothing, for
  every NPC, for every item type, the entire time this system has
  existed.
- `JobBoard._spare_exists()`'s shelf loop (used to gate REPLACE_FILTER
  and — until Part C removes it — REFUEL job posting) has the same dead
  loop, so a spare filter or fuel can sitting on a shelf was never
  detected — only a loose one on the floor counted.

This directly explains part of "can't read generators below 100%": if
the only spare fuel can in the bunker was ever put away on a shelf
rather than left loose on the floor, discovery would never see it at
all, regardless of any fuel-percentage threshold.

### Fix

**File:** `scripts/npc/NPCItemUser.gd`

**Anchor:** inside `find_shelved_item()`:

```gdscript
	for node: Node in npc.get_tree().get_nodes_in_group("shelf"):
```

Replace with:

```gdscript
	## Fixed Aug 2026 — every real shelf/storage object joins "shelving"
	## (Shelving.gd, LightStorage.gd), never "shelf". This loop searched a
	## group nothing has ever joined, so it silently found nothing for
	## the entire lifetime of this function.
	for node: Node in npc.get_tree().get_nodes_in_group("shelving"):
```

**File:** `scripts/npc/JobBoard.gd`

**Anchor:** inside `_spare_exists()`:

```gdscript
	for shelf: Node in get_tree().get_nodes_in_group("shelf"):
```

Replace with:

```gdscript
	## Fixed Aug 2026 — same dead-group bug as NPCItemUser.find_shelved_item();
	## real shelf/storage objects join "shelving", never "shelf".
	for shelf: Node in get_tree().get_nodes_in_group("shelving"):
```

Note: both functions gate on `"slots" in node`, which only true
`Shelving.gd` instances have (`LightStorage.gd` uses `stored`, not
`slots`) — so this fix correctly starts finding items on real shelves
without accidentally reaching into End Table/Dresser internals through
the wrong retrieval path.

Stop and report on anchor mismatch — no improvisation.

---

## Part B — NPCs can store light items in End Table / Dresser during Cleaning

### Current state (verified live)

`LightStorage.gd` already joins the `"shelving"` group (so it's already
inside `NPC.find_cleaning_destination()`'s existing search), and
`NPC.find_cleaning_destination()` already skips a candidate if
`candidate.has_room_for(item)` exists and returns false. But
`LightStorage.gd` has **no `has_room_for()` and no `npc_try_place_item()`
at all** — only `Shelving.gd` has those. So today, if an End
Table/Dresser is ever picked as a cleaning destination, two things go
wrong: the room-check silently no-ops (`has_method("has_room_for")` is
false, so the "skip if full" check never triggers), and delivery always
fails (`has_method("npc_try_place_item")` is also false), so
`CleaningActivity` just drops the item on the floor near the furniture
instead of storing it. In practice this hasn't been very visible because
`_find_slot_for()`-style eligibility never distinguished item types for
LightStorage in the first place.

### Design — future-proof, reuses the player's own eligibility rule

`LightStorage._try_store_held()` (the player path) already gates
storage on exactly one rule: `item.is_in_group("inventory_item")`. I'm
giving NPCs the identical rule via the identical group check, so NPC and
player storage eligibility can never drift apart — no separate
"can an NPC store this" list to maintain.

For the destination *routing* itself (which group(s) to search for a
given item), I'm adding one small, clearly-commented extension point in
`NPC.gd` rather than hardcoding "shelving" inline. Today everything
still resolves to `"shelving"` (which both `Shelving.gd` and
`LightStorage.gd` join), so behavior for fuel cans/water bottles today
is: prefer whichever eligible, non-full destination is nearest — could
be a shelf or an End Table/Dresser. When a Fridge (food) or Trash Can
(trash — already has its own `"trash_receptacle"` path) is added later,
extending this is a one-line classifier addition plus one new group name
in the mapping — no changes to `CleaningActivity` or the core search
logic.

### Fix

**File:** `scripts/world/furniture/LightStorage.gd`

**Anchor:** the existing `is_full()`/`_first_null_slot()` block:

```gdscript
func is_full() -> bool:
	return _first_null_slot() == -1

func _first_null_slot() -> int:
	for i: int in stored.size():
		if stored[i] == null:
			return i
	return -1
```

Add immediately after it:

```gdscript
## Public capacity+type check (Aug 2026, NPC Cleaning) — used by
## NPC.find_cleaning_destination() so an ineligible-type or full
## container is never picked as a cleaning destination. Deliberately
## reuses _try_store_held()'s own eligibility rule (is_in_group(
## "inventory_item")) rather than a separate list, so NPC and player
## storage rules can never diverge.
func has_room_for(item: RigidBody3D) -> bool:
	return item != null and item.is_in_group("inventory_item") and not is_full()

## NPC-side placement (Aug 2026, Cleaning) — mirrors
## Shelving.npc_try_place_item()'s shape (NPC-sourced item, no
## InteractionSystem bookkeeping to reconcile) and _try_store_held()'s
## own held-state clear + _absorb_item() reuse. Returns false if the item
## isn't eligible for this container or it's full — caller
## (CleaningActivity) decides what to do next (sets the item back down).
func npc_try_place_item(npc: Node, item: RigidBody3D) -> bool:
	if not has_room_for(item):
		return false
	if "held_item" in npc and npc.held_item == item:
		npc.held_item = null
	if "is_held"        in item: item.is_held        = false
	if "_hold_point"    in item: item._hold_point    = null
	if "from_inventory" in item: item.from_inventory = false
	_absorb_item(item)
	return true
```

**File:** `scripts/npc/NPC.gd`

**Anchor:** the existing `find_cleaning_destination()`:

```gdscript
## Nearest member of the matching destination group. For trash, returning
## null here (no receptacle exists) is expected and handled gracefully by
## CleaningActivity — it just abandons and sets the item back down.
func find_cleaning_destination(is_trash: bool, item: RigidBody3D = null) -> Node:
	var group_name: String = "trash_receptacle" if is_trash else "shelving"
	var best: Node = null
	var best_d: float = INF
	for candidate: Node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(candidate):
			continue
		if not is_trash and item != null and candidate.has_method("has_room_for") and not candidate.has_room_for(item):
			continue   ## skip shelves with no room — this check was the whole gap
		var d: float = NPCItemUser.flat_distance(global_position, (candidate as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = candidate
	return best
```

Replace with:

```gdscript
## Cleaning destination routing (Aug 2026) — maps an organizable item's
## CLASSIFICATION to the destination group(s) to search, in priority
## order. Every classification today resolves to "shelving", which both
## Shelving.gd (real shelves) AND LightStorage.gd (End Table/Dresser)
## join — LightStorage's own has_room_for() already enforces the
## inventory_item type gate, so this stays correct with zero extra logic
## here. To add a new dedicated container later (e.g. a Fridge that
## should only receive food, joining a new "food_storage" group instead
## of "shelving"): add one classification check to
## _classify_organizable_item() below and one new entry to
## ORGANIZE_DESTINATION_GROUPS. No other cleaning code needs to change.
const ORGANIZE_DESTINATION_GROUPS: Dictionary = {
	"general": ["shelving"],
}

func _classify_organizable_item(_item: RigidBody3D) -> String:
	## FUTURE: return "food" once a Fridge exists and food items should
	## prefer it over general shelving (see comment above).
	return "general"

## Nearest member of the matching destination group(s). For trash,
## returning null here (no receptacle exists) is expected and handled
## gracefully by CleaningActivity — it just abandons and sets the item
## back down.
func find_cleaning_destination(is_trash: bool, item: RigidBody3D = null) -> Node:
	var group_names: Array = ["trash_receptacle"] if is_trash \
		else ORGANIZE_DESTINATION_GROUPS.get(_classify_organizable_item(item), ["shelving"])
	var best: Node = null
	var best_d: float = INF
	for group_name: String in group_names:
		for candidate: Node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(candidate):
				continue
			if not is_trash and item != null and candidate.has_method("has_room_for") and not candidate.has_room_for(item):
				continue   ## skip a full/ineligible container — this check was the whole gap
			var d: float = NPCItemUser.flat_distance(global_position, (candidate as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = candidate
	return best
```

Stop and report on anchor mismatch — no improvisation.

### Testing (Part A + B)

1. Put a spare fuel can or filter on a real shelf (not the floor) and
   confirm an NPC's Eat/Drink/Replace-Filter behavior can now find items
   stored there (Part A fix).
2. Drop a loose Fuel Can, Water Bottle, and something bulky (Can Case or
   Water Case) near an NPC and an empty End Table/Dresser. Ask the NPC to
   clean. Confirm the Fuel Can/Water Bottle get carried into and stored
   inside the End Table/Dresser (menu shows them via `[E]`), and the
   bulky Case items go to a real shelf instead — never dropped on the
   floor near the furniture, and never rejected in a way that ends the
   cleaning session prematurely.
3. Fill an End Table/Dresser to capacity, drop another eligible item
   nearby, ask an NPC to clean — confirm it's routed to a real shelf (or
   a second, non-full End Table/Dresser) instead of getting stuck
   retrying the full one.
4. Re-run Part A of the previous shelf pop-out plan's test but targeting
   an End Table/Dresser instead of a shelf — confirm stored items stay
   put (this should already hold, since `npc_try_place_item()` above
   clears `is_held`/`_hold_point` the same way the shelf fix does, but
   confirm live).

---

## Part C — Refuel redesign: multi-generator session, not a single JobBoard job

### Root cause of "can't read generators below 100%"

`JobBoard._scan_refuel()` only ever posts a REFUEL job when
`fuel < REFUEL_BELOW` (40.0) — a generator at, say, 70% never gets a job
posted at all, so "Refuel the generator" correctly (if confusingly)
reports "nothing needs refueling" for anything above 40%. Combined with
Part A's dead-shelf-group bug (a shelved spare can was never found
either), this is almost certainly the entire "can't read generators
below 100%" experience: the system was only ever designed to react to a
crisis-low generator, not to top off anything short of full, and even
that had a real detection gap.

### Design

This is architecturally the same shape as Cleaning: fetch once, then
work through multiple targets in one sustained session, stopping only
when the resource runs out or there's nothing left to do.
`JobBoard.gd`'s own header comment already says exactly this about
multi-location jobs not fitting its single-target claim shape — Refuel
belongs in that category too, not JobBoard's. So Refuel is being pulled
out of `JobBoard`/`JobActivity` entirely (mirroring how Cleaning and
Give-to-Friend already work) and rebuilt as its own `RefuelActivity`,
with a `CommandRefuelActivity` wrapper for the Talk-menu request,
following `CleaningActivity`/`CommandCleaningActivity`'s exact pattern.

Behavior: fetch ONE fuel can (loose or shelved — Part A fix makes
shelved ones reachable again), then repeatedly find the nearest
generator that's below 100% and hasn't been refueled yet **this
session**, travel to it, pour continuously (reusing `FuelCan.refuel_tick()`
exactly as before — same real continuous-pour mechanic, nothing about
the pour itself changes) until it hits 100% or the can runs dry, mark it
done for this session (so it's never picked again even if it's still
the "nearest" target), and either move to the next eligible generator or
end the session. Session ends when the can is empty or no generator
remains below 100%, satisfying Brannon's stated end condition exactly.

Autonomous (uncommanded) triggering keeps a distinct, higher urgency bar
than the session's own sweep target — an NPC won't autonomously drop
what it's doing over a generator at 95%, but once a session starts (by
either autonomous trigger or player command), it tops off *everything*
below 100%, not just the one that triggered it. This carries over the
old `REFUEL_BELOW = 40.0` tuning as the autonomous gate only; flag to
Brannon if this feels wrong once live-tested, it's an easy constant to
retune.

### C1 — Remove REFUEL from JobBoard/JobActivity

**File:** `scripts/npc/JobBoard.gd`

**Anchor:** the header job-shape comment:

```gdscript
##   type         String  — "HARVEST" | "REPLACE_FILTER" | "REFUEL"
```

Replace with:

```gdscript
##   type         String  — "HARVEST" | "REPLACE_FILTER"
##   (REFUEL was JobBoard-claimed through Aug 2026; moved to a dedicated
##   multi-generator session — NPCBrain.RefuelActivity — since sweeping
##   every generator in one trip doesn't fit this single-target shape any
##   better than Cleaning's multi-item sweep does. See docs/systems/npc/README.md.)
```

**Anchor:**

```gdscript
const REFUEL_BELOW: float = 40.0
```

Delete this line entirely (moved to `NPC.gd` as
`REFUEL_URGENT_BELOW`, see C2).

**Anchor:** inside `_rescan()`:

```gdscript
	_scan_harvest(seen)
	_scan_filters(seen)
	_scan_refuel(seen)
	_scan_cleaning(seen)
```

Replace with:

```gdscript
	_scan_harvest(seen)
	_scan_filters(seen)
	_scan_cleaning(seen)
```

**Anchor:** the entire `_scan_refuel()` function:

```gdscript
func _scan_refuel(seen: Dictionary) -> void:
	## FuelCan.gd declares no class_name — duck-type instead of `is FuelCan`.
	var fuel_can: Callable = func(item: Node) -> bool:
		return item.has_method("refuel_tick") and item.has_method("can_store") \
			and ("_fuel_remaining" in item) and item._fuel_remaining > 0.0
	if not _spare_exists(fuel_can):
		return
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return
	for gen: Node in get_tree().get_nodes_in_group("generator"):
		if not is_instance_valid(gen):
			continue
		var fuel: float = pm.get_generator_fuel(str(gen.get_instance_id()))
		if fuel < REFUEL_BELOW:
			_mark(seen, "refuel_%d" % gen.get_instance_id(),
				"REFUEL", gen, fuel_can)
```

Delete this function entirely — its logic moves into
`NPC.find_next_refuel_target()` / `NPC.has_refuel_target_available()`
(C2) and `RefuelActivity` (C3).

**File:** `scripts/npc/NPCBrain.gd`

**Anchor:** inside `JobActivity.TYPE_CONF`:

```gdscript
	const TYPE_CONF: Dictionary = {
		"HARVEST":        {"time": 4.0, "skill": "farming",    "base": 55.0, "verb": "HARVESTING"},
		"REPLACE_FILTER": {"time": 5.0, "skill": "plumbing",   "base": 65.0, "verb": "FITTING FILTER"},
		"REFUEL":         {"time": 6.0, "skill": "electrical", "base": 60.0, "verb": "REFUELING"},
	}
```

Replace with:

```gdscript
	const TYPE_CONF: Dictionary = {
		"HARVEST":        {"time": 4.0, "skill": "farming",    "base": 55.0, "verb": "HARVESTING"},
		"REPLACE_FILTER": {"time": 5.0, "skill": "plumbing",   "base": 65.0, "verb": "FITTING FILTER"},
	}
```

**Anchor:** inside `JobActivity.tick()`'s `"work"` phase:

```gdscript
			npc.update_work_banner(String(conf["verb"]),
				1.0 - (_work_left / _work_total))
			## FuelCan.gd declares no class_name — duck-type via has_method.
			if _job["type"] == "REFUEL" and npc.held_item != null \
					and npc.held_item.has_method("refuel_tick"):
				npc.held_item.refuel_tick(delta)   ## REAL continuous pour
			if _work_left <= 0.0:
				_complete(npc)
```

Replace with:

```gdscript
			npc.update_work_banner(String(conf["verb"]),
				1.0 - (_work_left / _work_total))
			if _work_left <= 0.0:
				_complete(npc)
```

**Anchor:** inside `JobActivity._complete()`'s match block:

```gdscript
			"REPLACE_FILTER":
				if npc.held_item is PurifierFilterItem:
					var filt: PurifierFilterItem = npc.held_item
					npc.held_item = null      ## replace_filter consumes/frees it
					target.replace_filter(filt)
					NotificationManager.notify(UIKit.Domain.WATER,
						NotificationManager.Severity.INFO,
						"%s replaced the purifier filter" % npc.npc_name)
			"REFUEL":
				## Pouring already happened continuously during "work".
				if npc.held_item != null:
					NPCItemUser.drop_held(npc)   ## set the can back down
				NotificationManager.notify(UIKit.Domain.POWER,
					NotificationManager.Severity.INFO,
					"%s refueled the generator" % npc.npc_name)
```

Replace with:

```gdscript
			"REPLACE_FILTER":
				if npc.held_item is PurifierFilterItem:
					var filt: PurifierFilterItem = npc.held_item
					npc.held_item = null      ## replace_filter consumes/frees it
					target.replace_filter(filt)
					NotificationManager.notify(UIKit.Domain.WATER,
						NotificationManager.Severity.INFO,
						"%s replaced the purifier filter" % npc.npc_name)
```

Stop and report on anchor mismatch — no improvisation.

### C2 — `NPC.gd`: target search + availability + scoring constant

**Anchor:** near the existing `const CLEANING_BASE_SCORE: float = 5.5`:

```gdscript
const CLEANING_BASE_SCORE: float = 5.5
```

Add immediately after it:

```gdscript
## Refuel session (Aug 2026). Higher than Cleaning's base — running out
## of power is more urgent than clutter — tune visually once live-tested.
const REFUEL_BASE_SCORE: float = 8.0

## Autonomous-trigger gate ONLY (carried over from JobBoard's old
## REFUEL_BELOW). has_refuel_target_available()'s score() use of this
## just decides whether an NPC will interrupt other work over fuel level;
## once a refuel session actually starts (autonomous OR commanded), it
## tops off every generator below 100%, not just the urgent one.
const REFUEL_URGENT_BELOW: float = 40.0
```

**Anchor:** right after the existing `find_cleaning_destination()`
function from Part B (i.e., after the closing of that function), add:

```gdscript
## Nearest generator still below 100% fuel, excluding IDs already
## refueled THIS SESSION (passed in by RefuelActivity — its own session
## state stays the single source of truth, same shape as
## find_cleaning_target() not owning any state itself either). Also used
## with an empty exclude set for a quick "is there anything to do at
## all" check.
func find_next_refuel_target(exclude_ids: Dictionary) -> Node:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return null
	var best: Node = null
	var best_d: float = INF
	for gen: Node in get_tree().get_nodes_in_group("generator"):
		if not is_instance_valid(gen):
			continue
		var gid: int = gen.get_instance_id()
		if exclude_ids.has(gid):
			continue
		var fuel: float = pm.get_generator_fuel(str(gid))
		if fuel >= 100.0:
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (gen as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = gen
	return best

## Autonomous-trigger availability check — mirrors
## has_cleaning_target_available()'s shape. Gates on REFUEL_URGENT_BELOW
## (not "any generator below 100%") so an NPC doesn't autonomously
## interrupt other work over a near-full generator; RefuelActivity's own
## session sweep still tops off everything below 100% once it starts.
func has_refuel_target_available() -> bool:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	if pm == null:
		return false
	var urgent_exists: bool = false
	for gen: Node in get_tree().get_nodes_in_group("generator"):
		if not is_instance_valid(gen):
			continue
		if pm.get_generator_fuel(str(gen.get_instance_id())) < REFUEL_URGENT_BELOW:
			urgent_exists = true
			break
	if not urgent_exists:
		return false
	if held_item != null and held_item.has_method("refuel_tick"):
		return true
	var filt: Callable = Callable(NPCItemUser, "is_spare_fuel_can")
	return NPCItemUser.find_loose_item(self, filt) != null \
		or not NPCItemUser.find_shelved_item(self, filt).is_empty()
```

Stop and report on anchor mismatch — no improvisation.

### C3 — `NPCItemUser.gd`: shared fuel-can filter

**Anchor:** near the existing `is_drinkable_bottle()`:

```gdscript
static func is_drinkable_bottle(item: Node) -> bool:
	return item.has_method("take_drink") and ("current_fill_mL" in item) \
		and item.current_fill_mL > 0.0
```

Add immediately after it:

```gdscript
## Fuel-can duck-typed filter (FuelCan.gd declares no class_name — same
## reasoning as is_edible/is_drinkable_bottle above). Shared by
## RefuelActivity's fetch phase and NPC.has_refuel_target_available().
static func is_spare_fuel_can(item: Node) -> bool:
	return item.has_method("refuel_tick") and ("_fuel_remaining" in item) \
		and float(item._fuel_remaining) > 0.0
```

Stop and report on anchor mismatch — no improvisation.

### C4 — `NPCBrain.gd`: `RefuelActivity` + `CommandRefuelActivity`

**Anchor:** register the new activity in `setup()`'s candidate list:

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
	]
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
	]
```

**Anchor:** add the new `RefuelActivity` class. Place it directly after
the closing of `class CleaningActivity extends NPCActivity:` (i.e.,
right before `class EatActivity extends NPCActivity:` begins — the exact
insertion point Cleaning's own class ends at):

```gdscript
class RefuelActivity extends NPCActivity:
	## Refuel (Aug 2026, sustained session) — fetch ONE fuel can, then
	## visit every generator below 100% in turn, refueling each until
	## full (or the can runs dry) before moving to the next. Mirrors
	## CleaningActivity's fetch→travel→[loop] shape exactly — multi-
	## location work doesn't fit JobBoard's single-target claim system,
	## see JobBoard.gd's own header comment. Ends when the can empties or
	## no generator remains below 100%. Never revisits a generator
	## already topped off THIS session (_refueled_ids) — that's what
	## prevents an infinite loop once the first generator it fills is
	## still nearest again.
	const APPROACH_DISTANCE: float = 1.0
	const WORK_RANGE: float = 1.6

	var _can: RigidBody3D = null
	var _fetch_loose: RigidBody3D = null
	var _fetch_shelf: Dictionary = {}
	var _current_gen: Node = null
	var _refueled_ids: Dictionary = {}   ## generator instance_id -> true, this session only
	var _phase: String = "fetch"         ## fetch -> travel -> refuel
	var _finished: bool = false

	func label() -> String:
		match _phase:
			"fetch": return "Fetching fuel can"
			"travel": return "Heading to generator"
			_: return "Refueling"

	func score(npc: NPC) -> float:
		if not npc.has_refuel_target_available():
			return 0.0
		return NPC.REFUEL_BASE_SCORE * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight("REFUEL")

	func interruptible() -> bool:
		return _phase != "refuel"   ## mid-pour, commit; between generators/fetching, fine to interrupt

	func enter(npc: NPC) -> void:
		_refueled_ids = {}
		_finished = false
		if npc.held_item != null and npc.held_item.has_method("refuel_tick"):
			_can = npc.held_item
			_pick_next_generator(npc)
			return
		_phase = "fetch"
		_start_fetch(npc)

	func _start_fetch(npc: NPC) -> void:
		var filt: Callable = Callable(NPCItemUser, "is_spare_fuel_can")
		var loose: RigidBody3D = NPCItemUser.find_loose_item(npc, filt)
		var shelf_pick: Dictionary = {} if loose != null else NPCItemUser.find_shelved_item(npc, filt)
		var tgt: Node3D = loose if loose != null \
			else (shelf_pick.get("shelf") as Node3D if not shelf_pick.is_empty() else null)
		if tgt == null:
			_finished = true   ## no spare can anywhere — nothing to do
			return
		if loose != null:
			if not NPCItemUser.claim_item(loose, npc):
				_finished = true   ## momentary claim clash — try again next think-cycle
				return
			_fetch_loose = loose
		else:
			if not NPCItemUser.claim_item(shelf_pick.get("item"), npc):
				_finished = true
				return
			_fetch_shelf = shelf_pick
		npc.set_nav_target(tgt.global_position)

	func _tick_fetch(npc: NPC, delta: float) -> void:
		if npc.held_item != null:
			_can = npc.held_item
			_pick_next_generator(npc)
			return
		if _fetch_loose != null and is_instance_valid(_fetch_loose):
			if "is_held" in _fetch_loose and _fetch_loose.is_held:
				_fetch_loose = null
				_finished = true
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) <= NPCItemUser.PICKUP_RANGE:
				if not NPCItemUser.grab_loose(npc, _fetch_loose):
					_finished = true
			return
		if not _fetch_shelf.is_empty():
			var shelf: Node3D = _fetch_shelf.get("shelf")
			if shelf == null or not is_instance_valid(shelf):
				_finished = true
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) <= NPCItemUser.SHELF_RANGE:
				if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
					_finished = true
			return
		_finished = true   ## nothing left to fetch — spare can vanished between scan and now

	func _pick_next_generator(npc: NPC) -> void:
		_current_gen = npc.find_next_refuel_target(_refueled_ids)
		if _current_gen == null:
			_finished = true   ## every generator full — session complete
			return
		npc.set_nav_target(_approach_point(npc, _current_gen))
		_phase = "travel"

	func _approach_point(npc: NPC, target: Node) -> Vector3:
		var t3: Node3D = target as Node3D
		var to_npc: Vector3 = npc.global_position - t3.global_position
		to_npc.y = 0.0
		if to_npc.length() < 0.01:
			to_npc = Vector3(0.0, 0.0, 1.0)   ## degenerate case: npc exactly at center
		return t3.global_position + to_npc.normalized() * APPROACH_DISTANCE

	func tick(npc: NPC, delta: float) -> void:
		match _phase:
			"fetch":
				_tick_fetch(npc, delta)
			"travel":
				if _current_gen == null or not is_instance_valid(_current_gen):
					_pick_next_generator(npc)
					return
				npc.nav_steer(delta)
				var t_pos: Vector3 = (_current_gen as Node3D).global_position
				var flat_dist: float = Vector2(npc.global_position.x, npc.global_position.z) \
					.distance_to(Vector2(t_pos.x, t_pos.z))
				if flat_dist <= WORK_RANGE:
					npc.velocity = Vector3.ZERO
					_phase = "refuel"
					npc.show_work_banner()
			"refuel":
				npc.halt_movement(delta)
				if _can == null or not is_instance_valid(_can) \
						or _current_gen == null or not is_instance_valid(_current_gen):
					npc.hide_work_banner()
					_pick_next_generator(npc)
					return
				var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
				if pm == null:
					_finished = true
					return
				var gid: String = str(_current_gen.get_instance_id())
				npc.update_work_banner("REFUELING", pm.get_generator_fuel(gid) / 100.0)
				_can.refuel_tick(delta)   ## REAL continuous pour, same mechanic as before
				var fuel_after: float = pm.get_generator_fuel(gid)
				var can_empty: bool = ("_fuel_remaining" in _can) and float(_can._fuel_remaining) <= 0.0
				if fuel_after >= 100.0 or can_empty:
					npc.hide_work_banner()
					_refueled_ids[_current_gen.get_instance_id()] = true
					NotificationManager.notify(UIKit.Domain.POWER, NotificationManager.Severity.INFO,
						"%s refueled the generator" % npc.npc_name)
					npc.log_action("Refueled a generator")
					npc.gain_skill("electrical")
					if can_empty:
						_finished = true   ## can is dry — session ends even if generators remain
					else:
						_pick_next_generator(npc)

	func done(_npc: NPC) -> bool:
		return _finished

	func exit(npc: NPC) -> void:
		npc.hide_work_banner()
		if _fetch_loose != null:
			NPCItemUser.release_item(_fetch_loose)
		if not _fetch_shelf.is_empty():
			NPCItemUser.release_item(_fetch_shelf.get("item"))
		if _finished and npc.held_item != null and npc.held_item == _can:
			NPCItemUser.drop_held(npc)   ## session truly over — set the (empty or spare) can down
```

**Anchor:** add `CommandRefuelActivity` directly after the closing of
`class CommandCleaningActivity extends NPCActivity:`:

```gdscript
class CommandRefuelActivity extends NPCActivity:
	## "Can you complete this job?" → Refuel the generators (Aug 2026).
	## Delegates straight to a normal (organic-mode) RefuelActivity — its
	## own enter() already does the full fetch/target search; done()
	## right after enter() tells us whether anything was actually found.
	var _inner: NPCActivity = null

	func label() -> String:
		return _inner.label() if _inner != null else "Idle"

	func score(_npc: NPC) -> float:
		return 0.0

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		_inner = RefuelActivity.new()
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

### C5 — `NPCTalkMenuUI.gd`: route the "Refuel the generator" request

**Anchor:**

```gdscript
	if job_type == "CLEANING":
		_issue_command(NPCBrain.CommandCleaningActivity.new(), action_desc, empty_desc)
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)
```

Replace with:

```gdscript
	if job_type == "CLEANING":
		_issue_command(NPCBrain.CommandCleaningActivity.new(), action_desc, empty_desc)
	elif job_type == "REFUEL":
		_issue_command(NPCBrain.CommandRefuelActivity.new(), action_desc, empty_desc)
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)
```

Also update the comment just above `NPC_JOB_MENU_ENTRIES` (currently
says REFUEL routes through the generic path) to reflect that REFUEL now
also special-cases like CLEANING:

**Anchor:**

```gdscript
## Centralized so a new job type later needs ONE entry here, nothing
## else. "type" must match JobBoard's job "type" string exactly
## (HARVEST/REPLACE_FILTER/REFUEL), or the literal string "CLEANING"
## (routed to CommandCleaningActivity instead of the generic
## CommandJobActivity, since Cleaning isn't JobBoard-claimed at all).
```

Replace with:

```gdscript
## Centralized so a new job type later needs ONE entry here, nothing
## else. "type" must match JobBoard's job "type" string exactly
## (HARVEST/REPLACE_FILTER), or the literal strings "CLEANING"/"REFUEL"
## (routed to CommandCleaningActivity/CommandRefuelActivity instead of
## the generic CommandJobActivity, since neither is JobBoard-claimed).
```

Stop and report on anchor mismatch — no improvisation.

### Testing (Part C)

1. Set one generator to ~70% (F7 debug, or drain it naturally) with
   others full. Open Requests → "Refuel the generator" — confirm it's
   now offered (previously required <40%).
2. Set two generators below 100% (e.g. 70% and 30%) with a single fuel
   can that has enough fuel for both. Issue the command — confirm the
   NPC fetches the can once, fully tops off the first generator it
   reaches, then walks to the second and tops it off too, without
   re-fetching a second can and without looping back to the first.
3. Set three generators below 100% with a fuel can that will run out
   partway through the second one — confirm the session ends cleanly
   once the can is empty (NPC sets it down), rather than trying to
   travel to a third generator with nothing left to give it.
4. Confirm a generator sitting at exactly 100% is never selected as a
   target, and confirm the same generator is never revisited twice in
   one session even if it's still the geometrically nearest one after
   being topped off (this is the loop-prevention Brannon specifically
   asked for — watch it directly, don't just infer from the end state).
5. With autonomous behavior only (don't issue the command), leave a
   generator at 25% and another at 90% — confirm an NPC will
   autonomously start a refuel session (crosses `REFUEL_URGENT_BELOW`),
   and confirm that once started, it also tops off the 90% one in the
   same session rather than ignoring it.
6. Confirm `refuel_tick()`'s real pour behavior (rate, generator-full
   short-circuit, can depletion) is visually unchanged from before —
   this redesign only changes *what decides where the can goes next*,
   never the pour mechanic itself.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist (continue numbering from
wherever the live file currently ends):

```
69. Put a spare Fuel Can or Purifier Filter on a real shelf (not the
    floor) — confirm Eat/Drink/Replace-Filter/Refuel can now find it
    (previously find_shelved_item()/_spare_exists() searched a group
    ("shelf") nothing ever joined — see NPC_LIGHT_STORAGE_AND_REFUEL_
    REDESIGN.md).
70. Ask an NPC to clean with a loose Fuel Can/Water Bottle and an empty
    End Table or Dresser nearby — confirm it gets carried in and stored
    (End Table/Dresser previously had no npc_try_place_item(), so this
    always silently failed/dropped the item).
71. Set a generator to a mid-range fuel level (e.g. 70%) — confirm
    "Refuel the generator" now offers it (previously gated at <40%).
72. Issue "Refuel the generator" with 2+ generators below 100% and one
    fuel can — confirm the NPC sweeps every eligible generator in one
    trip, never re-fetches mid-session, never revisits a generator
    already topped off, and stops cleanly when the can runs dry or
    everything's full.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Light Storage (End Table/Dresser) Cleanup + Refuel Session Redesign (Aug 2026)

- Fixed a dead group-name bug: NPCItemUser.find_shelved_item() and
  JobBoard._spare_exists() both searched group "shelf", which nothing in
  the project has ever joined (real shelves/storage join "shelving").
  NPCs could never find a spare item that had been put away on a shelf —
  affected Eat/Drink/Replace-Filter/Refuel fetch-from-shelf fallback.
- Added has_room_for()/npc_try_place_item() to LightStorage.gd (End
  Table/Dresser) so Cleaning can actually store eligible light items
  there — previously silently failed since only Shelving.gd had these.
  Eligibility reuses the player's own inventory_item group gate.
- Added an extensible item-classification → destination-group mapping
  to NPC.find_cleaning_destination() (currently everything still
  resolves to "shelving") so a future dedicated container (Fridge for
  food, etc.) is a one-line addition, not a rework.
- Pulled REFUEL out of JobBoard/JobActivity entirely (it never fit the
  single-target claim shape any better than Cleaning did) and rebuilt it
  as NPCBrain.RefuelActivity/CommandRefuelActivity: fetches one fuel can,
  sweeps every generator below 100% in one session, never revisits a
  generator already topped off, ends when the can empties or everything's
  full. Also fixes the old REFUEL_BELOW=40% gate that meant a mid-range
  generator was never even detectable as needing fuel.

Files touched: `scripts/npc/NPCItemUser.gd`, `scripts/npc/JobBoard.gd`,
`scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/world/furniture/LightStorage.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
