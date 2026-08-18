# Cleaning Root-Cause Fixes: Item Names, Destination-First Routing, Stale-Cache Loop, Refuel Errors, Neutral NPC Spawn (Aug 2026)

**Files:** `scripts/world/items/TestCrate.gd`, `scripts/world/items/CanCase.gd`,
`scripts/world/items/WaterCase.gd`, `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/world/furniture/Shelving.gd`,
`scripts/world/furniture/LightStorage.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/ui/menus/AdminMenu.gd`, `docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing.

---

## Context — reading the debug output you sent

That log is exactly what the debug overhaul was for, and it pointed at
three distinct, confirmed problems (not one):

1. **Generic "Item" naming.** `TestCrate.gd` (and `CanCase.gd`,
   `WaterCase.gd`) never override `get_display_name()`, so they fall back
   to `PickupableItem`'s default `"Item"`. Every log line involving the
   Test Crate read as "Item" because that's genuinely all the code knew
   to call it, even though `item_name = "Crate"` was sitting right there
   unused for this purpose.

2. **Pick-up-before-checking-storage, and no per-item destination
   memory.** `CleaningActivity._pick_next_target()` picks the nearest
   item and walks straight to it — it only calls
   `find_cleaning_destination()` *after* already grabbing the item. For
   the Test Crate specifically (a non-`inventory_item` object with only
   an End Table and Dresser in the test scene — both `inventory_item`-
   gated, neither able to hold it), this produced the exact loop you
   saw: pick up → no destination → set back down → immediately
   re-picked as "nearest" again next tick, for the entire 27s session.
   This is real, root-caused, and fixed in Part B below — not a guess.

3. **A second, separate loop on the *successful* Jerry Can runs** — the
   "target picked → target lost: became shelved" bursts of ~30 lines
   between the two successful deliveries. Root cause found:
   `JobBoard.get_trash_items()`/`get_organizable_items()` only filter
   for `is_instance_valid()` — they do **not** re-check whether an item
   has since become shelved or held. `JobBoard`'s cache only refreshes
   every `SCAN_INTERVAL` (2.0s). So for up to ~2 seconds after an NPC
   successfully stores an item, that same now-shelved item is still
   sitting in the cache, is now the *physically nearest* thing to the
   NPC standing right next to the Dresser it just used, gets re-picked
   as the "best" target every single think-tick, and is immediately
   rejected once the fetch-phase's `is_in_group("shelved")` check catches
   it — over and over until the next scan finally drops it. Fixed in
   Part C.

You also asked for the same specific-reason treatment for Refuel (Part
D), an explicit "light" vs "heavy" storage-category concept with the
items you listed confirmed included (Part E — good news, they're
mechanically already eligible; this makes it official and gives it a
name for error messages), and a second F7 "Spawn NPC" that produces a
fully neutral test subject (Part F).

---

## Part A — Fix generic "Item" naming

**File:** `scripts/world/items/TestCrate.gd`

**Anchor:**

```gdscript
@export var item_name: String = "Crate"

## Shelf stacking — 1 crate per slot (too large to stack)
var shelf_stack_limit: int   = 1
var shelf_item_type: String  = "test_crate"

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	_mesh = get_node_or_null("Model/MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_prompt_text() -> String:
	return "[F] Pick up %s" % item_name
```

Replace with:

```gdscript
@export var item_name: String = "Crate"

## Shelf stacking — 1 crate per slot (too large to stack)
var shelf_stack_limit: int   = 1
var shelf_item_type: String  = "test_crate"

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	_mesh = get_node_or_null("Model/MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_prompt_text() -> String:
	return "[F] Pick up %s" % item_name

## Aug 2026 — was missing entirely, so every NPC-facing log/UI surface
## fell back to PickupableItem's generic "Item" default. NPCs need real
## per-object identity now (Cleaning logs, and every future job that
## touches specific objects), not just the player-facing F-prompt text.
func get_display_name() -> String:
	return item_name
```

**File:** `scripts/world/items/CanCase.gd`

**Anchor:**

```gdscript
func get_prompt_text() -> String:
	if is_held:
		return "[F] Drop %s" % item_name
	return "[F] Pick up %s" % item_name
```

Replace with:

```gdscript
func get_prompt_text() -> String:
	if is_held:
		return "[F] Drop %s" % item_name
	return "[F] Pick up %s" % item_name

## Aug 2026 — same gap as TestCrate.gd — see that file's comment.
func get_display_name() -> String:
	return item_name
```

**File:** `scripts/world/items/WaterCase.gd`

**Anchor:**

```gdscript
func get_prompt_text() -> String:
	if is_held:
		return "[F] Drop %s" % item_name
	return "[F] Pick up %s" % item_name
```

Replace with:

```gdscript
func get_prompt_text() -> String:
	if is_held:
		return "[F] Drop %s" % item_name
	return "[F] Pick up %s" % item_name

## Aug 2026 — same gap as TestCrate.gd — see that file's comment.
func get_display_name() -> String:
	return item_name
```

Stop and report on anchor mismatch — no improvisation. If you find any
*other* `PickupableItem` subclass missing `get_display_name()` while
you're in there, flag it — I audited every file under
`scripts/world/items/` and these three were the only gaps, but verify
against live code since new items may have been added since.

---

## Part B — Destination-first: never pick up an item with nowhere to go

### Design

Today's flow is pick → check destination → (maybe) abandon. The fix
inverts it: check destination → (only if viable) pick. This directly
stops the pickup/drop loop, and — just as important — an item that
*genuinely* has nowhere to go for its whole category (not just "this one
shelf is full") gets skipped for the rest of the session instead of
being retried every single tick.

This needs two small new capability checks (`has_free_space()` on both
storage types) so "is there room anywhere for this category" can be
answered without needing a specific item in hand to test against yet.

### B1 — `Shelving.gd`: generic free-space check

**Anchor:**

```gdscript
## Public capacity check, used so a full shelf isn't chosen as a
## destination in the first place — see NPC.find_cleaning_destination().
func has_room_for(item: RigidBody3D) -> bool:
	return _find_slot_for(item) != -1
```

Replace with:

```gdscript
## Public capacity check, used so a full shelf isn't chosen as a
## destination in the first place — see NPC.find_cleaning_destination().
func has_room_for(item: RigidBody3D) -> bool:
	return _find_slot_for(item) != -1

## Aug 2026 — generic "does this shelf have ANY free space at all" check,
## independent of a specific item's type. Used by
## NPC.has_viable_destination_for_category() to answer "does storage
## exist for this classification" without needing a representative item
## on hand — has_room_for(item) needs a real item to test slot-type
## matching, this doesn't. Deliberately conservative: an empty slot
## always counts, even though a specific item might ALSO fit into a
## same-type partial stack with no fully-empty slot left — fine for an
## availability estimate, not for an actual placement decision.
func has_free_space() -> bool:
	for stack: Array in slots:
		if stack.is_empty():
			return true
	return false
```

### B2 — `LightStorage.gd`: matching free-space check

**Anchor:**

```gdscript
func has_room_for(item: RigidBody3D) -> bool:
	return item != null and item.is_in_group("inventory_item") and not is_full()
```

Replace with:

```gdscript
func has_room_for(item: RigidBody3D) -> bool:
	return item != null and item.is_in_group("inventory_item") and not is_full()

## Aug 2026 — matches Shelving.gd's new has_free_space() so
## NPC.has_viable_destination_for_category() can call either storage
## type polymorphically without an item on hand yet. Type-eligibility
## (inventory_item) is handled separately by the caller, not here — this
## only answers "is there room", same contract as Shelving's version.
func has_free_space() -> bool:
	return not is_full()
```

Stop and report on anchor mismatch — no improvisation.

### B3 — `NPC.gd`: classification-aware availability check + rewritten `find_cleaning_target()`

**Anchor:**

```gdscript
func has_cleaning_target_available() -> bool:
	if not JobBoard.get_trash_items().is_empty():
		return true
	return not JobBoard.get_organizable_items().is_empty()

## Nearest eligible item across BOTH lists — trash and organizable are
## mutually exclusive per JobBoard's own scan, so no double-counting risk.
func find_cleaning_target() -> Dictionary:
	var best_item: Node = null
	var best_d: float = INF
	var best_is_trash: bool = false
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_item = item
			best_is_trash = true
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_item = item
			best_is_trash = false
	if best_item == null:
		return {}
	return {"item": best_item, "is_trash": best_is_trash}
```

Replace with:

```gdscript
func has_cleaning_target_available() -> bool:
	if not JobBoard.get_trash_items().is_empty():
		return true
	return not JobBoard.get_organizable_items().is_empty()

## Nearest eligible item across BOTH lists — trash and organizable are
## mutually exclusive per JobBoard's own scan, so no double-counting
## risk. `exclude_ids` (Aug 2026) lets CleaningActivity skip items it's
## already tried and confirmed have nowhere to go THIS session, and
## skip momentary claim-clash items, without waiting on JobBoard's own
## 2s cache refresh — see CleaningActivity._pick_next_target().
func find_cleaning_target(exclude_ids: Dictionary = {}) -> Dictionary:
	var best_item: Node = null
	var best_d: float = INF
	var best_is_trash: bool = false
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_item = item
			best_is_trash = true
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)
		if d < best_d:
			best_d = d
			best_item = item
			best_is_trash = false
	if best_item == null:
		return {}
	return {"item": best_item, "is_trash": best_is_trash}
```

**Anchor:** the existing `ORGANIZE_DESTINATION_GROUPS` block through
`_classify_organizable_item()`:

```gdscript
const ORGANIZE_DESTINATION_GROUPS: Dictionary = {
	"general": ["shelving"],
}

func _classify_organizable_item(_item: RigidBody3D) -> String:
	## FUTURE: return "food" once a Fridge exists and food items should
	## prefer it over general shelving (see comment above).
	return "general"
```

Replace with:

```gdscript
const ORGANIZE_DESTINATION_GROUPS: Dictionary = {
	"light": ["shelving"],
	"heavy": ["shelving"],
}

## Aug 2026 — "light" vs "heavy" is now the real, named classification
## (previously everything was lumped as "general"). "light" = the exact
## same is_in_group("inventory_item") gate LightStorage.has_room_for()
## already enforces, so this can never drift out of sync with actual
## eligibility — it's just naming the same rule for routing/reporting
## purposes. "heavy" = everything else (Test Crate, Can Case, Water
## Case, etc.) — these can ONLY ever fit real Shelving, never an End
## Table/Dresser, regardless of how much room the latter has.
func _classify_organizable_item(item: RigidBody3D) -> String:
	if item != null and item.is_in_group("inventory_item"):
		return "light"
	return "heavy"

## Aug 2026 — is there ANY viable destination for this classification
## ANYWHERE in the level right now, independent of a specific item?
## Used by CleaningActivity to decide "skip this whole category for the
## rest of the session" vs "try a different candidate, one shelf being
## full doesn't mean they all are." A LightStorage node never counts
## for "heavy" no matter how empty it is — it structurally can't accept
## a non-inventory_item object (see LightStorage.has_room_for()).
func has_viable_destination_for_category(category: String) -> bool:
	var group_names: Array = ORGANIZE_DESTINATION_GROUPS.get(category, ["shelving"])
	for group_name: String in group_names:
		for candidate: Node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(candidate):
				continue
			if category == "heavy" and candidate is LightStorage:
				continue
			if candidate.has_method("has_free_space") and not candidate.has_free_space():
				continue
			return true
	return false
```

Stop and report on anchor mismatch — no improvisation.

### B4 — `NPCBrain.gd`: `CleaningActivity` — destination-first, skip hopeless items

**Anchor:** the entire existing `_pick_next_target()`:

```gdscript
	## Called at session start and after each delivery (success or
	## failure) — this is what makes the NPC keep working through the
	## bunker's clutter instead of stopping after one item.
	func _pick_next_target(npc: NPC) -> void:
		_destination = null
		if _is_forced_session:
			_item = _forced_item
			_forced_item = null
			if _item == null or not is_instance_valid(_item):
				_item = null
				_finished = true
				return
			_is_trash = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "forced grab", "%s (stuck-recovery, is_trash=%s)" % [
					_display_name(_item), _is_trash])
		else:
			var result: Dictionary = npc.find_cleaning_target()
			if result.is_empty():
				_finished = true
				_item = null
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "session ended", "nothing left to clean")
				return
			_item = result.get("item")
			_is_trash = result.get("is_trash", false)
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "target picked", "%s (%s) dist=%.1f" % [
					_display_name(_item), "trash" if _is_trash else "organizable",
					NPCItemUser.flat_distance(npc.global_position, (_item as Node3D).global_position)])
		if not NPCItemUser.claim_item(_item, npc):
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "claim failed", "%s already claimed by another NPC — retrying next tick" % _display_name(_item))
			_item = null   ## momentary claim clash — try again next tick, don't end the session over it
			return
		if _item.has_method("set_nav_obstacle_enabled"):
			_item.set_nav_obstacle_enabled(false)
		npc.set_nav_target(_item.global_position)
```

Replace with:

```gdscript
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
			_is_trash = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "forced grab", "%s (stuck-recovery, is_trash=%s)" % [
					_display_name(_item), _is_trash])
		else:
			while true:
				var result: Dictionary = npc.find_cleaning_target(_skipped_ids)
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
						_display_name(_item), "trash" if _is_trash else "organizable",
						NPCItemUser.flat_distance(npc.global_position, (_item as Node3D).global_position)])
				if _is_trash:
					break   ## trash keeps its existing post-pickup handling — commit and go
				var category: String = npc._classify_organizable_item(_item)
				if npc.find_cleaning_destination(false, _item) != null:
					break   ## viable destination confirmed for THIS item — commit and go fetch it
				_skipped_ids[_item.get_instance_id()] = true
				if not npc.has_viable_destination_for_category(category):
					_no_storage_categories[category] = true
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "no storage for category", "%s (%s) — no viable destination exists anywhere; skipping all %s items this session" \
							% [_display_name(_item), category, category])
				elif NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "no destination (retrying)", "%s (%s) has nowhere to go right now — trying next item" \
						% [_display_name(_item), category])
				## loop again — try the next nearest candidate, never having walked to this one at all
		if not NPCItemUser.claim_item(_item, npc):
			if NPCDebug.enabled:
				NPCDebug.log_cleaning(npc, "claim failed", "%s already claimed by another NPC — retrying next tick" % _display_name(_item))
			_item = null   ## momentary claim clash — try again next tick, don't end the session over it
			return
		if _item.has_method("set_nav_obstacle_enabled"):
			_item.set_nav_obstacle_enabled(false)
		npc.set_nav_target(_item.global_position)
```

**Anchor:** the member variable block near the top of `CleaningActivity`:

```gdscript
	var _item: RigidBody3D = null
	var _destination: Node = null
	var _is_trash: bool = false
	var _forced_item: RigidBody3D = null
	var _is_forced_session: bool = false
	var _session_elapsed: float = 0.0
	var _session_duration: float = 0.0
	var _finished: bool = false
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
```

**Anchor:** the existing `enter()` (reset session state here too):

```gdscript
	func enter(npc: NPC) -> void:
		_session_duration = randf_range(SESSION_MIN_SEC, SESSION_MAX_SEC)
		_session_elapsed = 0.0
		_finished = false
		if NPCDebug.enabled and not _is_forced_session:
			NPCDebug.log_cleaning(npc, "session started", "target duration=%.0fs" % _session_duration)
		_pick_next_target(npc)
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		_session_duration = randf_range(SESSION_MIN_SEC, SESSION_MAX_SEC)
		_session_elapsed = 0.0
		_finished = false
		_skipped_ids = {}
		_no_storage_categories = {}
		if NPCDebug.enabled and not _is_forced_session:
			NPCDebug.log_cleaning(npc, "session started", "target duration=%.0fs" % _session_duration)
		_pick_next_target(npc)
```

**Anchor:** `debug_info()`'s return dictionary:

```gdscript
		return {
			"activity": "cleaning",
			"item": _display_name(_item) if _item != null else "",
			"is_trash": _is_trash,
			"phase": phase,
			"destination": (_destination.name if _destination != null and is_instance_valid(_destination) else ""),
			"session_elapsed": _session_elapsed,
			"session_duration": _session_duration,
			"forced": _is_forced_session,
		}
```

Replace with:

```gdscript
		return {
			"activity": "cleaning",
			"item": _display_name(_item) if _item != null else "",
			"is_trash": _is_trash,
			"phase": phase,
			"destination": (_destination.name if _destination != null and is_instance_valid(_destination) else ""),
			"session_elapsed": _session_elapsed,
			"session_duration": _session_duration,
			"forced": _is_forced_session,
			"no_storage_categories": _no_storage_categories.keys(),
		}
```

Note: the fetch-phase's own post-pickup `find_cleaning_destination()`
call (inside `tick()`) is left completely unchanged — it's now a
redundant-but-cheap safety re-check for the rare race where the
pre-confirmed destination fills up during the walk over (another NPC
gets there first). No need to touch `tick()` at all for this part.

Stop and report on anchor mismatch — no improvisation.

---

## Part C — Fix the stale-cache repeat loop at its source

**File:** `scripts/npc/JobBoard.gd`

**Anchor:**

```gdscript
func get_trash_items() -> Array:
	_trash_items_cache = _trash_items_cache.filter(func(i): return is_instance_valid(i))
	return _trash_items_cache

func get_organizable_items() -> Array:
	_organizable_items_cache = _organizable_items_cache.filter(func(i): return is_instance_valid(i))
	return _organizable_items_cache
```

Replace with:

```gdscript
## Aug 2026 — now also filters out anything that's become shelved or
## held SINCE the last _scan_cleaning() pass, not just freed instances.
## Root cause of a real bug: this cache only rebuilds every
## SCAN_INTERVAL (2s), so for up to ~2s after an NPC successfully
## stores an item, the now-shelved item was still returned here as if
## still organizable — and since it's now the item physically nearest
## to the NPC standing right next to the storage it just used,
## find_cleaning_target() kept re-selecting it, only for the fetch
## phase's own is_in_group("shelved") check to immediately reject it,
## every single think-tick, in a tight repeating loop until the next
## scan finally dropped it. Filtering here closes the gap at the source
## for every caller, not just find_cleaning_target()'s own defensive
## checks.
func get_trash_items() -> Array:
	_trash_items_cache = _trash_items_cache.filter(func(i):
		return is_instance_valid(i) and not i.is_in_group("shelved") \
			and not (("is_held" in i) and i.is_held))
	return _trash_items_cache

func get_organizable_items() -> Array:
	_organizable_items_cache = _organizable_items_cache.filter(func(i):
		return is_instance_valid(i) and not i.is_in_group("shelved") \
			and not (("is_held" in i) and i.is_held))
	return _organizable_items_cache
```

Stop and report on anchor mismatch — no improvisation.

---

## Part D — Specific unavailable-reason errors for Refuel (and going forward, the standard for every job)

**File:** `scripts/npc/NPC.gd`

**Anchor:** immediately after `find_next_refuel_target()` (end of that
function, right before `has_refuel_target_available()` begins):

```gdscript
	return best

## Autonomous-trigger availability check — mirrors
## has_cleaning_target_available()'s shape. Gates on REFUEL_URGENT_BELOW
## (not "any generator below 100%") so an NPC doesn't autonomously
## interrupt other work over a near-full generator; RefuelActivity's own
## session sweep still tops off everything below 100% once it starts.
func has_refuel_target_available() -> bool:
```

Replace with:

```gdscript
	return best

## Specific, human-readable-key reason Refuel currently isn't available
## for THIS NPC (Aug 2026) — same pattern as
## get_cleaning_unavailable_reason(), replacing the old blanket "nothing
## needs refueling" with an exact cause:
##   ""                    — available right now
##   "ALL_GENERATORS_FULL" — genuinely nothing needs fuel
##   "FUEL_CAN_CLAIMED"    — a generator needs fuel and a spare can
##                           exists, but another NPC already has it
##   "NO_FUEL_CAN"         — a generator needs fuel and nothing else
##                           explains why it can't proceed
## This is the standard going forward for every job's "can't do it"
## message — specific and checked in priority order, not a single
## catch-all string. NPCTalkMenuUI maps these to player-facing text —
## see REFUEL_UNAVAILABLE_REASONS there. Keep both in sync.
func get_refuel_unavailable_reason() -> String:
	var pm: Node = get_tree().get_first_node_in_group("power_manager")
	var any_needs_fuel: bool = false
	if pm != null:
		for gen: Node in get_tree().get_nodes_in_group("generator"):
			if not is_instance_valid(gen):
				continue
			if pm.get_generator_fuel(str(gen.get_instance_id())) < 100.0:
				any_needs_fuel = true
				break
	if not any_needs_fuel:
		return "ALL_GENERATORS_FULL"
	if held_item != null and held_item.has_method("refuel_tick"):
		return ""   ## already holding a can — available regardless of anything below
	var filt: Callable = Callable(NPCItemUser, "is_spare_fuel_can")
	if NPCItemUser.find_loose_item(self, filt) != null:
		return ""
	if not NPCItemUser.find_shelved_item(self, filt).is_empty():
		return ""
	## Nothing claimable right now — distinguish "no can exists at all"
	## from "one exists but another NPC already has it."
	for node: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(node) or node.is_in_group("shelved"):
			continue
		if "is_held" in node and node.is_held:
			continue
		if NPCItemUser.is_spare_fuel_can(node) and NPCItemUser.is_claimed_by_other(node, self):
			return "FUEL_CAN_CLAIMED"
	return "NO_FUEL_CAN"

## Autonomous-trigger availability check — mirrors
## has_cleaning_target_available()'s shape. Gates on REFUEL_URGENT_BELOW
## (not "any generator below 100%") so an NPC doesn't autonomously
## interrupt other work over a near-full generator; RefuelActivity's own
## session sweep still tops off everything below 100% once it starts.
func has_refuel_target_available() -> bool:
```

Stop and report on anchor mismatch — no improvisation.

**File:** `scripts/ui/npc/NPCTalkMenuUI.gd`

**Anchor:** the existing `CLEANING_UNAVAILABLE_REASONS` constant (both
replace its contents to drop the now-superseded generic key, and add the
Refuel map right after it):

```gdscript
const CLEANING_UNAVAILABLE_REASONS: Dictionary = {
	"NOTHING_TO_CLEAN":     "nothing to clean right now",
	"NO_TRASH_RECEPTACLE":  "there's trash, but nowhere to throw it away yet",
	"STILL_SETTLING":       "everything's still settling — check back shortly",
	"ALL_CLAIMED":          "everything's already being handled by someone else",
	"NO_STORAGE_AVAILABLE": "there's nothing to put things away in",
	"STORAGE_FULL":         "storage is full",
}
```

Replace with:

```gdscript
const CLEANING_UNAVAILABLE_REASONS: Dictionary = {
	"NOTHING_TO_CLEAN":          "nothing to clean right now",
	"NO_TRASH_RECEPTACLE":       "there's trash, but nowhere to throw it away yet",
	"STILL_SETTLING":            "everything's still settling — check back shortly",
	"ALL_CLAIMED":               "everything's already being handled by someone else",
	"NO_LIGHT_STORAGE_AVAILABLE": "there's nothing to put light items away in",
	"NO_HEAVY_STORAGE_AVAILABLE": "there's nothing to put heavy items away in",
	"STORAGE_FULL":              "storage is full",
}

## Aug 2026 — mirrors CLEANING_UNAVAILABLE_REASONS for
## NPC.get_refuel_unavailable_reason(). Keep in sync with that
## function's own doc comment if the reason set changes.
const REFUEL_UNAVAILABLE_REASONS: Dictionary = {
	"ALL_GENERATORS_FULL": "every generator is already full",
	"FUEL_CAN_CLAIMED":    "the only fuel can is already being used",
	"NO_FUEL_CAN":         "there's no fuel can anywhere to refuel with",
}
```

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
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)
```

Stop and report on anchor mismatch — no improvisation.

**File:** `scripts/npc/NPC.gd` — update `get_cleaning_unavailable_reason()`
itself to use the new category-aware check instead of bare group-presence:

**Anchor:**

```gdscript
	if not bool(target.get("is_trash", false)):
		var item: RigidBody3D = target.get("item")
		if find_cleaning_destination(false, item) == null:
			## Distinguish "nothing exists to store it in" from "it exists
			## but every candidate is full" — same group set
			## find_cleaning_destination() itself searches, just checking
			## bare presence separately for a precise message.
			var group_names: Array = ORGANIZE_DESTINATION_GROUPS.get(_classify_organizable_item(item), ["shelving"])
			var any_candidate: bool = false
			for group_name: String in group_names:
				if not get_tree().get_nodes_in_group(group_name).is_empty():
					any_candidate = true
					break
			return "STORAGE_FULL" if any_candidate else "NO_STORAGE_AVAILABLE"
	return ""   ## available
```

Replace with:

```gdscript
	if not bool(target.get("is_trash", false)):
		var item: RigidBody3D = target.get("item")
		if find_cleaning_destination(false, item) == null:
			## Aug 2026 — now uses has_viable_destination_for_category()
			## (accounts for LightStorage never accepting "heavy" items
			## regardless of room) instead of a bare group-presence check,
			## and reports which specific category (light/heavy) has
			## nothing available.
			var category: String = _classify_organizable_item(item)
			if not has_viable_destination_for_category(category):
				return "NO_LIGHT_STORAGE_AVAILABLE" if category == "light" else "NO_HEAVY_STORAGE_AVAILABLE"
			return "STORAGE_FULL"
	return ""   ## available
```

Also update that function's own doc comment listing possible reasons —
**anchor:**

```gdscript
##   "NO_STORAGE_AVAILABLE" — a ready organizable item exists and is
##                            claimable, but zero shelves/End
##                            Tables/Dressers exist anywhere in the level
##   "STORAGE_FULL"         — same as above, except storage exists but
##                            every candidate is currently full
```

Replace with:

```gdscript
##   "NO_LIGHT_STORAGE_AVAILABLE" — a ready LIGHT (inventory_item)
##                            organizable item exists and is claimable,
##                            but no shelf/End Table/Dresser anywhere can
##                            currently take it
##   "NO_HEAVY_STORAGE_AVAILABLE" — same, for a HEAVY (non-inventory_item)
##                            item — only a real Shelving object can ever
##                            take these, never an End Table/Dresser
##   "STORAGE_FULL"         — a viable destination TYPE exists somewhere,
##                            just not one with room right now
```

Stop and report on anchor mismatch — no improvisation.

---

## Part E — Confirm the listed items as "light" (Water Bottle, Food Can, seed packets, Bag of Soil, Normal/Pro Fertilizer)

I checked every one of these against live code before writing this
plan — **all of them already join `"inventory_item"`**:
`WaterBottle.gd`, `FoodCan.gd`, `SeedItem.gd` (covers every seed-packet
type through one shared script), `BagOfSoilItem.gd`, and
`FertilizerItem.gd` (one script for both the Normal and Pro tiers via an
exported `tier` property — both already join the group, since it's the
same `_ready()` for either tier).

That means they were already mechanically eligible for End
Table/Dresser storage under the `has_room_for()` gate from the previous
plan. What Part B above adds is the **formal "light" classification
name** tied to that exact same group check — so nothing needs to change
on any of these five item files. No action needed here beyond
confirming it, which this section is doing. If live code shows any of
them NOT in `"inventory_item"` when you check, stop and report that
specifically rather than assuming this section is still accurate.

---

## Part F — F7: "Spawn Neutral NPC" for reproducible testing

**File:** `scripts/ui/menus/AdminMenu.gd`

**Anchor:**

```gdscript
			["Spawn NPC", _on_spawn_npc_pressed],
```

Replace with:

```gdscript
			["Spawn NPC", _on_spawn_npc_pressed],
			["Spawn Neutral NPC (Testing)", _on_spawn_neutral_npc_pressed],
```

**Anchor:** immediately after the existing `_on_spawn_npc_pressed()`:

```gdscript
## Spawns one NPC.tscn instance 2m in front of the player, facing them —
## same spawn-offset pattern MainWorld._dev_spawn_crate() uses for TestCrate.
func _on_spawn_npc_pressed() -> void:
	if world_node == null:
		push_warning("[AdminMenu] world_node not injected — cannot spawn NPC")
		return
	var player_node: Node3D = get_tree().get_first_node_in_group("player")
	if player_node == null:
		push_warning("[AdminMenu] No player found in scene — cannot spawn NPC")
		return

	var npc_scene: PackedScene = load("res://scenes/npc/NPC.tscn")
	if npc_scene == null:
		push_warning("[AdminMenu] NPC.tscn not found — check path")
		return

	var npc: Node3D = npc_scene.instantiate()
	world_node.add_child(npc)
	npc.global_position = player_node.global_position \
		+ (-player_node.global_transform.basis.z * 2.0) \
		+ Vector3(0.0, 0.5, 0.0)
```

Add immediately after it:

```gdscript
## Aug 2026 — identical spawn to _on_spawn_npc_pressed() above, but then
## overrides _ready()'s random personality/skill roll with a fully
## neutral baseline: for reproducible bug-hunting where trait-driven
## behavior variance (irritability, work ethic, forgetfulness, job
## priority weighting) would otherwise be one more variable to account
## for. personality = {} already means "every trait absent/baseline" per
## randomize_personality()'s own convention (a PRESENT trait is never
## neutral by design — see that function's comment) — this just makes it
## deterministic instead of leaving it to chance which traits happened
## not to roll present. Skills forced to 1.0 (dead center of
## randomize_skills()'s normal 0.6-1.4 range) for the same reason. Name
## stays on the normal random pool — only traits/skills are neutralized.
func _on_spawn_neutral_npc_pressed() -> void:
	if world_node == null:
		push_warning("[AdminMenu] world_node not injected — cannot spawn NPC")
		return
	var player_node: Node3D = get_tree().get_first_node_in_group("player")
	if player_node == null:
		push_warning("[AdminMenu] No player found in scene — cannot spawn NPC")
		return

	var npc_scene: PackedScene = load("res://scenes/npc/NPC.tscn")
	if npc_scene == null:
		push_warning("[AdminMenu] NPC.tscn not found — check path")
		return

	var npc: Node3D = npc_scene.instantiate()
	world_node.add_child(npc)
	npc.global_position = player_node.global_position \
		+ (-player_node.global_transform.basis.z * 2.0) \
		+ Vector3(0.0, 0.5, 0.0)

	if "personality" in npc:
		npc.personality = {}
	if "skills" in npc:
		for key: String in npc.skills.keys():
			npc.skills[key] = 1.0
```

Stop and report on anchor mismatch — no improvisation.

---

## Testing

1. **Item naming.** Enable NPC Debug Logging, have an NPC clean a Test
   Crate, a Can Case, and a Water Case (individually) — confirm the
   console now shows "Crate", "Can Case", "Water Case" instead of
   generic "Item" in every log line.
2. **Destination-first / no wasted pickups.** In a scene with only an
   End Table/Dresser (no real shelf) and a Test Crate present, ask an
   NPC to clean — confirm the console shows exactly ONE "no storage for
   category" line for the Crate (not a repeating pickup/drop loop), and
   confirm the NPC is never seen physically walking to or picking up the
   Crate at all. Confirm any light items (Fuel Can, Water Bottle, etc.)
   present in the same scene still get properly routed to the End
   Table/Dresser and stored.
3. **Stale-cache loop gone.** With both a real shelf/light-storage and
   several light items present, watch a full session — confirm you no
   longer see "target picked → target lost: became shelved" bursts
   between successful deliveries. Each delivered item's cache entry
   should simply disappear rather than being repeatedly re-picked and
   rejected.
4. **Mixed heavy+light scene.** With one real Shelving object AND an End
   Table, plus both a Test Crate and a few light items — confirm the
   Crate correctly routes to the Shelving object (not rejected), while
   light items still prefer whichever's nearer with room, matching
   normal shelving-group behavior.
5. **Specific Refuel errors.** Test each: all generators full → "every
   generator is already full"; a generator below 100% with zero fuel
   cans anywhere → "there's no fuel can anywhere to refuel with"; same
   but with a second NPC actively holding the only fuel can → "the only
   fuel can is already being used".
6. **Specific Cleaning storage errors.** Reproduce a scene with only
   heavy-capable storage (a real shelf) and no light-capable storage,
   drop a light item, request Cleaning — confirm "there's nothing to put
   light items away in" specifically (not the old generic message).
   Reverse the setup (only End Table/Dresser, a heavy item present) —
   confirm "there's nothing to put heavy items away in".
7. **Neutral NPC.** Press "Spawn Neutral NPC (Testing)" — confirm via F7
   → Print NPC Debug State that the spawned NPC shows no personality
   trait words (baseline on every trait) and skills all at exactly 1.0,
   while a regular "Spawn NPC" alongside it still shows normal
   randomized variance for comparison.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
76. Clean a Test Crate, Can Case, and Water Case individually with debug
    logging on — confirm real names appear in the console, not generic
    "Item" (all three were missing get_display_name() entirely).
77. In a scene with only light-capable storage, ask an NPC to clean a
    heavy item (e.g. Test Crate) — confirm it's skipped once with a "no
    storage for category" log line, never picked up, and the toast (if
    requested) says "there's nothing to put heavy items away in"
    specifically, not a generic message.
78. Watch a full multi-item cleaning session end-to-end — confirm no
    repeating "target picked / target lost: became shelved" bursts
    between successful deliveries (stale-cache bug, fixed at
    JobBoard.get_trash_items()/get_organizable_items()).
79. Test each specific Refuel unavailable reason (all full, no can
    anywhere, can claimed by another NPC) — confirm distinct toast text
    for each.
80. Press F7 → "Spawn Neutral NPC (Testing)" — confirm the spawned NPC
    has zero personality trait words and all skills at exactly 1.0.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Cleaning Root-Cause Fixes + Refuel Errors + Neutral NPC Spawn (Aug 2026)

- Fixed generic "Item" naming: TestCrate.gd, CanCase.gd, WaterCase.gd
  were all missing get_display_name() entirely, falling back to
  PickupableItem's "Item" default despite already having a usable
  item_name field.
- CleaningActivity is now destination-first: confirms a viable
  destination for an organizable item BEFORE claiming/walking to it,
  not after already picking it up. An item with genuinely no viable
  destination for its whole classification (light/heavy) is skipped
  once and never retried for the rest of the session
  (_skipped_ids/_no_storage_categories), instead of being picked up and
  dropped on a loop every tick — this was the direct cause of the
  Test Crate repeat-loop seen in a live debug capture.
- Fixed a real stale-cache bug: JobBoard.get_trash_items()/
  get_organizable_items() only filtered is_instance_valid(), not
  shelved/held state, so a just-stored item stayed "organizable" in the
  cache for up to the full 2s SCAN_INTERVAL — and being physically
  nearest to the NPC that just used it, got endlessly re-picked and
  rejected until the next scan. This was the cause of the repeating
  "target picked / target lost: became shelved" bursts between
  otherwise-successful deliveries.
- Formalized "light" (inventory_item-gated) vs "heavy" as NPC.gd's real
  organizable-item classification (previously always "general"), with
  NPC.has_viable_destination_for_category() backing both the new
  destination-first check and specific unavailable-reason errors:
  NO_LIGHT_STORAGE_AVAILABLE / NO_HEAVY_STORAGE_AVAILABLE replace the
  old generic NO_STORAGE_AVAILABLE. Confirmed (no code change needed)
  that Water Bottle, Food Can, all seed packets, Bag of Soil, and both
  Fertilizer tiers were already inventory_item-gated and thus already
  "light"-eligible.
- Added NPC.get_refuel_unavailable_reason() — replaces the old blanket
  "nothing needs refueling" with ALL_GENERATORS_FULL / FUEL_CAN_CLAIMED
  / NO_FUEL_CAN, same pattern as Cleaning's reason system. This is now
  the standard going forward for every job's failure messaging.
- Added Shelving.has_free_space()/LightStorage.has_free_space() —
  generic "any room at all" checks used by the new category-availability
  logic without needing a specific item on hand yet.
- Added F7 "Spawn Neutral NPC (Testing)" — spawns via the same path as
  the existing Spawn NPC row, then overrides personality to fully
  baseline and every skill to exactly 1.0, for reproducible testing
  without trait-driven behavior variance.

Files touched: `scripts/world/items/TestCrate.gd`,
`scripts/world/items/CanCase.gd`, `scripts/world/items/WaterCase.gd`,
`scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/world/furniture/Shelving.gd`,
`scripts/world/furniture/LightStorage.gd`, `scripts/ui/npc/NPCTalkMenuUI.gd`,
`scripts/ui/menus/AdminMenu.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
