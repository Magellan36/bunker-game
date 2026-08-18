# Cleaning Bug Fixes + Job Priority System + Requests UI (Aug 2026)

**Files:** `scripts/npc/JobBoard.gd`, `scripts/world/furniture/Shelving.gd`,
`scripts/world/items/PickupableItem.gd` ⚠️ (small, targeted, additive —
flagging since it's a World Items file, not one I've touched before),
`scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/ui/npc/NPCTalkMenuUI.gd`.

---

## Part A — Three confirmed bugs (traced to root cause, not guessed)

### A1. Crash: `JobBoard`'s cleaning caches can hold freed references

**Root cause:** `get_trash_items()`/`get_organizable_items()` return the
raw cached array with no validity check. The scan only refreshes every
`SCAN_INTERVAL` — if an item gets destroyed/consumed in between scans
(entirely possible), any NPC's `find_cleaning_target()` call in that
window iterates a stale reference, and the moment it's assigned to the
loop's typed `Node` variable, Godot flags it — same class of bug
already fixed once for `JobBoard.get_open_jobs()`.

**Anchor:**

```gdscript
func get_trash_items() -> Array:
	return _trash_items_cache

func get_organizable_items() -> Array:
	return _organizable_items_cache
```

Replace with:

```gdscript
func get_trash_items() -> Array:
	_trash_items_cache = _trash_items_cache.filter(func(i): return is_instance_valid(i))
	return _trash_items_cache

func get_organizable_items() -> Array:
	_organizable_items_cache = _organizable_items_cache.filter(func(i): return is_instance_valid(i))
	return _organizable_items_cache
```

(The lambda parameter is untyped, so passing a freed reference into
`is_instance_valid()` here is safe — the danger is specifically typed
assignment, which this avoids.)

### A2. Heavy items (Crates) can't actually be approached for pickup

**Root cause:** confirmed by checking `TestCrate.tscn` directly —
`mass = 7.0`, above `HEAVY_OBSTACLE_MASS = 3.0`, meaning it gets a
`NavigationObstacle3D` with `avoidance_enabled = true`. That system
exists so NPCs route AROUND heavy clutter while traveling elsewhere —
exactly the wrong behavior when an NPC is deliberately trying to walk
UP TO a heavy item to grab it, since avoidance actively prevents closing
the final distance. `pickup()`/`drop()` already correctly toggle this
off/on for the held/dropped states — there's just no existing hook for
"someone is actively approaching me to grab me while I'm still on the
ground," which is exactly the missing piece. This is why the fuel can
(light, no obstacle) worked fine while the crate (heavy) didn't.

**Anchor:** `scripts/world/items/PickupableItem.gd`, near
`_maybe_create_nav_obstacle()`.

Insert:

```gdscript
## Lets external code (an NPC actively approaching this item to grab it)
## temporarily suspend obstacle avoidance while it's still on the ground.
## pickup()/drop() already handle the held/dropped states correctly —
## this covers the gap in between: the walk-up itself, during which
## avoidance would otherwise prevent ever closing the final distance to
## a heavy item.
func set_nav_obstacle_enabled(enabled: bool) -> void:
	if _nav_obstacle != null:
		_nav_obstacle.avoidance_enabled = enabled
```

**Anchor:** `scripts/npc/NPCBrain.gd`, `CleaningActivity.enter()`:

```gdscript
	func enter(npc: NPC) -> void:
		if _forced_item != null:
			_item = _forced_item
			_is_trash = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
		else:
			var result: Dictionary = npc.find_cleaning_target()
			if result.is_empty():
				return
			_item = result.get("item")
			_is_trash = result.get("is_trash", false)
		if _item == null or not is_instance_valid(_item):
			_item = null
			return
		if not NPCItemUser.claim_item(_item, npc):
			_item = null
			return
		npc.set_nav_target(_item.global_position)
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		if _forced_item != null:
			_item = _forced_item
			_is_trash = npc.is_trash_item(_item) if npc.has_method("is_trash_item") else false
		else:
			var result: Dictionary = npc.find_cleaning_target()
			if result.is_empty():
				return
			_item = result.get("item")
			_is_trash = result.get("is_trash", false)
		if _item == null or not is_instance_valid(_item):
			_item = null
			return
		if not NPCItemUser.claim_item(_item, npc):
			_item = null
			return
		if _item.has_method("set_nav_obstacle_enabled"):
			_item.set_nav_obstacle_enabled(false)
		npc.set_nav_target(_item.global_position)
```

**Anchor:** `CleaningActivity.exit()`:

```gdscript
	func exit(npc: NPC) -> void:
		if _item != null:
			NPCItemUser.release_item(_item)
		_item = null
```

Replace with:

```gdscript
	func exit(npc: NPC) -> void:
		if _item != null:
			## Restore avoidance if we're abandoning it back on the ground —
			## pickup() already handles this correctly if it was actually
			## grabbed (is_held true), so only restore when it wasn't.
			if _item.has_method("set_nav_obstacle_enabled") and "is_held" in _item and not _item.is_held:
				_item.set_nav_obstacle_enabled(true)
			NPCItemUser.release_item(_item)
		_item = null
```

### A3. Shelf destination is picked with no capacity check — the actual "just drops" cause

**Root cause:** confirmed by reading `find_cleaning_destination()`
directly — it picks the nearest `"shelving"` group member by distance
alone, with no check that it can actually accept the item. If that
nearest shelf happens to be full (very plausible with limited early-game
shelving), the NPC carries the item all the way there, the placement
attempt correctly fails, and it falls through to the "just drop it"
fallback — consistently, not intermittently, exactly matching what you
saw.

**Anchor:** `scripts/world/furniture/Shelving.gd`, near `npc_try_place_item()`.

Insert:

```gdscript
## Public capacity check, used so a full shelf isn't chosen as a
## destination in the first place — see NPC.find_cleaning_destination().
func has_room_for(item: RigidBody3D) -> bool:
	return _find_slot_for(item) != -1
```

**Anchor:** `scripts/npc/NPC.gd`'s `find_cleaning_destination()`:

```gdscript
func find_cleaning_destination(is_trash: bool) -> Node:
	var group_name: String = "trash_receptacle" if is_trash else "shelving"
	var best: Node = null
	var best_d: float = INF
	for candidate: Node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(candidate):
			continue
		var d: float = NPCItemUser.flat_distance(global_position, (candidate as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = candidate
	return best
```

Replace with:

```gdscript
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

**Anchor:** `CleaningActivity.tick()`'s fetch-phase success branch:

```gdscript
				if NPCItemUser.grab_loose(npc, _item):
					_destination = npc.find_cleaning_destination(_is_trash)
```

Replace with:

```gdscript
				if NPCItemUser.grab_loose(npc, _item):
					_destination = npc.find_cleaning_destination(_is_trash, _item)
```

---

## Part B — Job priority system

Universal per-job-type weighting, separate axis from Work Ethic (which
is about whether THIS NPC wants to work at all right now — this is about
how urgent/important this KIND of work is, in general). Deliberately an
NPC.gd *instance* method even though it doesn't use `personality` yet —
your planned Gardening (boosts Harvest) and Mechanic (boosts repairs)
traits will read from `personality` right here later, one central place.

Initial weights: Harvest highest, Cleaning lowest, filters/refuel in
between. Exact numbers are a starting point for you to tune, not a final
answer.

### `scripts/npc/NPC.gd`

**Anchor:** anywhere convenient near the Work Ethic section.

Insert:

```gdscript
# ─── Job Priority (Aug 2026) ─────────────────────────────────────────────
## Separate from Work Ethic's job/passive multiplier — this is about how
## important the TASK is, universally, not whether this NPC feels like
## working right now. Both multiply together into the final score.
## FUTURE WORK: Gardening trait → boost "HARVEST" specifically for NPCs
## who have it; Mechanic trait → boost "REPLACE_FILTER"/"REFUEL" — read
## `personality` right here once those traits exist, rather than adding a
## parallel system elsewhere.
const JOB_PRIORITY_WEIGHTS: Dictionary = {
	"HARVEST": 1.3,
	"REPLACE_FILTER": 1.0,
	"REFUEL": 1.0,
	"CLEANING": 0.5,
}
const JOB_PRIORITY_DEFAULT: float = 1.0

func get_job_priority_weight(job_type: String) -> float:
	return float(JOB_PRIORITY_WEIGHTS.get(job_type, JOB_PRIORITY_DEFAULT))
```

### `scripts/npc/NPCBrain.gd`

**Anchor:** `JobActivity.score()`'s final line:

```gdscript
		var willingness: float = 1.0 - (npc.irritability / 100.0) * 0.5
		return base_score * willingness * npc.get_work_ethic_job_mult()
```

Replace with:

```gdscript
		var willingness: float = 1.0 - (npc.irritability / 100.0) * 0.5
		return base_score * willingness * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight(_job.get("type", ""))
```

**Anchor:** `CleaningActivity.score()`:

```gdscript
	func score(npc: NPC) -> float:
		if _forced_item != null:
			return 0.0   ## forced-only instance, never auto-selected
		if not npc.has_cleaning_target_available():
			return 0.0
		return NPC.CLEANING_BASE_SCORE * npc.get_work_ethic_job_mult()
```

Replace with:

```gdscript
	func score(npc: NPC) -> float:
		if _forced_item != null:
			return 0.0   ## forced-only instance, never auto-selected
		if not npc.has_cleaning_target_available():
			return 0.0
		return NPC.CLEANING_BASE_SCORE * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight("CLEANING")
```

---

## Part C — Requests UI + generalized job commands

### 1. `scripts/npc/NPCBrain.gd` — generalized "force this job type" command

Replaces the need for one dedicated `Command*Activity` class per job
type. `CommandHarvestActivity` is left in place (harmless, unused from
the UI going forward) rather than removed, to avoid needing to verify
nothing else references it.

**Anchor:** add as a new class near `CommandHarvestActivity`.

```gdscript
class CommandJobActivity extends NPCActivity:
	## Generalized "can you complete this job?" command (Aug 2026) —
	## CommandHarvestActivity's exact pattern, parameterized by job type,
	## so adding a new JobBoard-routed job type later needs no new class
	## here, just a new entry in NPCTalkMenuUI's job menu list.
	var _job_type: String = ""
	var _inner: NPCActivity = null

	func _init(job_type: String) -> void:
		_job_type = job_type

	func label() -> String:
		return _inner.label() if _inner != null else "Idle"

	func score(_npc: NPC) -> float:
		return 0.0   ## command-only, never auto-selected

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		for job: Dictionary in JobBoard.get_open_jobs():
			if job.get("type", "") == _job_type:
				_inner = JobActivity.new(job)
				_inner.enter(npc)
				return
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

**Anchor:** add another new class right after it — Cleaning isn't routed
through `JobBoard`'s claim system at all (see `CleaningActivity`'s own
class comment), so it needs its own thin command wrapper rather than
using `CommandJobActivity`:

```gdscript
class CommandCleaningActivity extends NPCActivity:
	## "Can you complete this job?" → Clean the bunker (Aug 2026).
	## Delegates straight to a normal (organic-mode) CleaningActivity —
	## its own enter() already does the full find_cleaning_target() +
	## claim search; done() right after enter() tells us whether anything
	## was actually found.
	var _inner: NPCActivity = null

	func label() -> String:
		return _inner.label() if _inner != null else "Idle"

	func score(_npc: NPC) -> float:
		return 0.0

	func interruptible() -> bool:
		return _inner == null or _inner.interruptible()

	func enter(npc: NPC) -> void:
		_inner = CleaningActivity.new()
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

### 2. `scripts/ui/npc/NPCTalkMenuUI.gd` — the Requests/Jobs submenu

**Anchor:** the `PANEL_H`-adjacent constants (wherever `LOG_AREA_H` etc.
currently live) — add:

```gdscript
## Generous fixed bump covering the Requests box (4 buttons) plus the
## Jobs sub-list (currently 4 entries, grows as job types are added) —
## simplification: ONE combined bump rather than precisely tracking two
## separate additive heights, same "retune visually later" spirit as
## every other PANEL_H bump in this file's history.
const REQUESTS_SECTION_H: float = 260.0
```

**Anchor:** var declarations — add:

```gdscript
var _requests_toggle_button: Button = null
var _requests_box: VBoxContainer = null
var _requests_expanded: bool = false
var _jobs_box: VBoxContainer = null
var _jobs_expanded: bool = false
```

**Anchor:** anywhere near the top of the file (class-level consts) — add
the centralized, easily-extended job menu registry:

```gdscript
## Centralized so a new job type later needs ONE entry here, nothing
## else. "type" must match JobBoard's job "type" string exactly
## (HARVEST/REPLACE_FILTER/REFUEL), or the literal string "CLEANING"
## (routed to CommandCleaningActivity instead of the generic
## CommandJobActivity, since Cleaning isn't JobBoard-claimed at all).
const NPC_JOB_MENU_ENTRIES: Array[Dictionary] = [
	{"type": "HARVEST", "label": "Harvest the plants", "action_desc": "heading to harvest", "empty_desc": "nothing ready to harvest"},
	{"type": "REPLACE_FILTER", "label": "Replace the water filters", "action_desc": "heading to replace a filter", "empty_desc": "no filters need replacing"},
	{"type": "REFUEL", "label": "Refuel the generator", "action_desc": "heading to refuel", "empty_desc": "nothing needs refueling"},
	{"type": "CLEANING", "label": "Clean the bunker", "action_desc": "heading to clean up", "empty_desc": "nothing to clean right now"},
]
```

**Anchor:** the `_command_box` build block:

```gdscript
	_command_box = VBoxContainer.new()
	_command_box.add_theme_constant_override("separation", 4)
	_command_box.visible = false
	_vbox.add_child(_command_box)
	_command_box.add_child(UIKit.make_button("Go eat something", _on_command_eat_pressed))
	_command_box.add_child(UIKit.make_button("Go drink something", _on_command_drink_pressed))
	_command_box.add_child(UIKit.make_button("Take a load off", _on_command_rest_pressed))
	_command_box.add_child(UIKit.make_button("Harvest the plants", _on_command_harvest_pressed))
```

Replace with:

```gdscript
	_command_box = VBoxContainer.new()
	_command_box.add_theme_constant_override("separation", 4)
	_command_box.visible = false
	_vbox.add_child(_command_box)
	_requests_toggle_button = UIKit.make_button("Requests", _on_requests_toggle_pressed)
	_command_box.add_child(_requests_toggle_button)

	_requests_box = VBoxContainer.new()
	_requests_box.add_theme_constant_override("separation", 4)
	_requests_box.visible = false
	_command_box.add_child(_requests_box)
	_requests_box.add_child(UIKit.make_button("Can you go eat something?", _on_command_eat_pressed))
	_requests_box.add_child(UIKit.make_button("Can you go drink something?", _on_command_drink_pressed))
	_requests_box.add_child(UIKit.make_button("Take a load off", _on_command_rest_pressed))
	_requests_box.add_child(UIKit.make_button("Can you complete this job?", _on_jobs_toggle_pressed))

	_jobs_box = VBoxContainer.new()
	_jobs_box.add_theme_constant_override("separation", 4)
	_jobs_box.visible = false
	_command_box.add_child(_jobs_box)
	for entry: Dictionary in NPC_JOB_MENU_ENTRIES:
		var job_type: String = String(entry.get("type", ""))
		var label_text: String = String(entry.get("label", job_type))
		_jobs_box.add_child(UIKit.make_button(label_text, Callable(self, "_on_job_command_pressed").bind(job_type)))
```

**Anchor:** replace the entire `_on_command_harvest_pressed()` function
with three new functions:

```gdscript
func _on_command_harvest_pressed() -> void:
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("is_relaxing") and _npc.is_relaxing():
		if _npc.has_method("request_job_while_relaxing") and not _npc.request_job_while_relaxing():
			if _dialogue_label != null and _npc.has_method("get_relaxing_refusal_line"):
				_dialogue_label.text = _npc.get_relaxing_refusal_line()
				_dialogue_label.visible = true
			return
	_issue_command(NPCBrain.CommandHarvestActivity.new(), "heading to harvest", "nothing ready to harvest")
```

Replace with:

```gdscript
func _on_requests_toggle_pressed() -> void:
	_requests_expanded = not _requests_expanded
	_requests_toggle_button.text = "Requests ▴" if _requests_expanded else "Requests"
	if _requests_box != null:
		_requests_box.visible = _requests_expanded
	if not _requests_expanded and _jobs_box != null:
		## collapsing Requests also collapses Jobs so it doesn't linger
		## open behind a now-hidden parent
		_jobs_box.visible = false
		_jobs_expanded = false
	_refresh_panel_height()

func _on_jobs_toggle_pressed() -> void:
	_jobs_expanded = not _jobs_expanded
	if _jobs_box != null:
		_jobs_box.visible = _jobs_expanded
	_refresh_panel_height()

## Same "asking during a conversation shouldn't count" relaxing-refusal
## guard the old Harvest-only handler had — now applies to EVERY job
## type uniformly, fulfilling the note left in an earlier plan about
## extending this to future job buttons.
func _on_job_command_pressed(job_type: String) -> void:
	if _npc != null and is_instance_valid(_npc) and _npc.has_method("is_relaxing") and _npc.is_relaxing():
		if _npc.has_method("request_job_while_relaxing") and not _npc.request_job_while_relaxing():
			if _dialogue_label != null and _npc.has_method("get_relaxing_refusal_line"):
				_dialogue_label.text = _npc.get_relaxing_refusal_line()
				_dialogue_label.visible = true
			return
	var entry: Dictionary = {}
	for e: Dictionary in NPC_JOB_MENU_ENTRIES:
		if String(e.get("type", "")) == job_type:
			entry = e
			break
	var action_desc: String = String(entry.get("action_desc", "heading to work"))
	var empty_desc: String = String(entry.get("empty_desc", "nothing to do right now"))
	if job_type == "CLEANING":
		_issue_command(NPCBrain.CommandCleaningActivity.new(), action_desc, empty_desc)
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)
```

**Anchor:** the existing `_on_log_toggle_pressed()`'s final line:

```gdscript
	_apply_panel_height(PANEL_H + (LOG_SECTION_H if _log_expanded else 0.0))
```

Replace with:

```gdscript
	_refresh_panel_height()
```

Add the new shared helper nearby:

```gdscript
## Combines every section that can currently be expanded — Log and
## Requests/Jobs both call this instead of computing height independently,
## so they stack correctly rather than overwriting each other's contribution.
func _refresh_panel_height() -> void:
	var height: float = PANEL_H
	if _log_expanded:
		height += LOG_SECTION_H
	if _requests_expanded:
		height += REQUESTS_SECTION_H
	_apply_panel_height(height)
```

**Anchor:** `_teardown()` — add alongside the existing `_log_expanded = false` reset:

```gdscript
	_log_expanded = false
```

Replace with:

```gdscript
	_log_expanded = false
	_requests_expanded = false
	_jobs_expanded = false
```

**Known simplification, not a bug:** expanded Requests/Jobs state
persists across multiple Talk-presses within the same panel session
(only resets on full panel close via `_teardown()`) — deliberate, to
avoid extra state-tracking complexity for a minor polish concern.

---

## Documentation

`docs/systems/npc/README.md` — update the Cleaning section with the
three bug fixes and their root causes (useful context for future
debugging of similar issues). New "Job Priority" subsection documenting
the weight table and the Gardening/Mechanic extension point. Update the
Command/UI section describing the Requests → Jobs nested menu structure
and the centralized `NPC_JOB_MENU_ENTRIES` registry.

**Testing Checklist:**

```
75. Drop a Crate somewhere reachable, wait for the idle timer — confirm
    an NPC now actually walks up to and picks it up (not just standing
    near it), then confirm it correctly delivers to a shelf with room.
76. With a shelf deliberately filled to capacity nearby but another
    shelf with room farther away, confirm an NPC organizing an item goes
    to the farther shelf with room, not the closer full one.
77. Open Talk on an NPC — confirm you see a single "Requests" button
    where the four direct action buttons used to be. Click it — confirm
    the four rephrased buttons appear, panel grows to fit. Click "Can
    you complete this job?" — confirm the job list appears with all
    four current job types, panel doesn't clip/overflow.
78. Trigger each job button once — confirm each one works exactly like
    its old direct-button equivalent (Harvest) or its automatic
    counterpart (filters/refuel/cleaning), including the relaxing-refusal
    check now applying to all four, not just Harvest.
79. Confirm Harvest jobs still get picked meaningfully more often than
    Cleaning jobs under otherwise-equal conditions (same NPC, same
    distance, same urgency) — the priority weight actually doing
    something, not just present in code.
```
