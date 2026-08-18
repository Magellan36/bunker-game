# NPC Cleaning: Full Debug Overhaul + Specific Unavailable-Reason Errors (Aug 2026)

**Files:** `scripts/npc/NPCDebug.gd`, `scripts/npc/NPCActivity.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/ui/npc/NPCTalkMenuUI.gd`, `scripts/ui/menus/AdminMenu.gd`,
`docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify every anchor below
against the live file before editing — the previous two plans (shelf
pop-out/dead-group fix, light storage, and the Refuel redesign) have
already landed; this plan builds on top of that live state, not the
handoff doc's original description.

---

## Context

Two asks:

1. Much better debug output specifically for Cleaning — what item an NPC
   is picking up, where it's taking it, and every other decision point
   along the way — so a weird-behavior report can actually be nailed
   down instead of guessed at. Today `NPCDebug.log_cleaning()` exists but
   is only called in 2 places (both just "session ended"), and the only
   per-scan visibility is one aggregate print in `JobBoard._scan_cleaning()`.
   Picking up, destinations, delivery success/failure, claims, and
   forced/stuck-recovery grabs are all currently silent.
2. Specific error reasons instead of a blanket "nothing to clean" when
   the player issues the Cleaning request — "no storage available",
   "storage full", etc.

This plan adds three layers, from least to most invasive:

- **Continuous per-event logging** inside `CleaningActivity` (every
  pickup, every destination choice, every delivery, every failure) —
  this is what you'll watch scroll by with debug logging on.
- **An on-demand full-state dump** (`Print NPC Cleaning Debug State`, a
  new F7 row) — a single snapshot of JobBoard's caches, every tracked
  item's idle-timer progress, every storage destination's current
  occupancy, and every NPC currently mid-clean. This is the tool for
  "let's nail this down right now" rather than scrolling back through
  logs.
- **Specific unavailable-reason strings** surfaced through the existing
  Talk-menu request toast, replacing the generic empty_desc for Cleaning
  specifically.

On the "taking a minute to recognize cleanable objects" report: the
periodic scan print already existed but only showed aggregate counts —
after this plan, both the periodic print and the new on-demand dump show
each tracked item's exact remaining idle-timer seconds. Once this lands,
use it directly: enable debug logging, drop an item, and watch either
the console's periodic `[JobBoard] Cleaning scan:` line or the new dump
command to see definitively whether the delay is the (working-as-
designed but possibly too long) 90s idle gate or something else. Don't
assume it's the idle gate going in — that's exactly what this tooling is
for confirming or ruling out.

---

## Part A — `NPCActivity.gd`: new optional `debug_info()` hook

**File:** `scripts/npc/NPCActivity.gd`

**Anchor:**

```gdscript
func score(_npc: NPC) -> float: return 0.0
func enter(_npc: NPC) -> void: pass
func tick(_npc: NPC, _delta: float) -> void: pass
func done(_npc: NPC) -> bool: return true
func interruptible() -> bool: return true
func exit(_npc: NPC) -> void: pass
func label() -> String: return "Idle"
func begin_with_item(_npc: NPC, _item: Node) -> void: pass
func take_handoff() -> NPCActivity: return null
```

Replace with:

```gdscript
func score(_npc: NPC) -> float: return 0.0
func enter(_npc: NPC) -> void: pass
func tick(_npc: NPC, _delta: float) -> void: pass
func done(_npc: NPC) -> bool: return true
func interruptible() -> bool: return true
func exit(_npc: NPC) -> void: pass
func label() -> String: return "Idle"
func begin_with_item(_npc: NPC, _item: Node) -> void: pass
func take_handoff() -> NPCActivity: return null

## Optional (Aug 2026) — structured debug snapshot for NPCDebug's on-demand
## dumps. Empty Dictionary means "nothing interesting to show" (the
## default, for every activity that doesn't override this). An activity
## that DOES override it should include an "activity" String key so a
## dump can filter to just the activity type it cares about (see
## CleaningActivity.debug_info() for the pattern).
func debug_info() -> Dictionary: return {}
```

Stop and report on anchor mismatch — no improvisation.

---

## Part B — `NPCBrain.gd`: expose current activity's debug info + wire logging into `CleaningActivity`

### B1 — Public getter for the dump command

**Anchor:** `NPCBrain.gd`'s existing:

```gdscript
func current_label() -> String:
	return _current.label() if _current != null else "Idle"
```

Replace with:

```gdscript
func current_label() -> String:
	return _current.label() if _current != null else "Idle"

## Aug 2026 — structured debug snapshot of whatever the NPC is currently
## doing, for NPCDebug.dump_cleaning_state(). Empty Dictionary if idle or
## the current activity doesn't implement debug_info().
func get_current_activity_debug_info() -> Dictionary:
	return _current.debug_info() if _current != null else {}
```

### B2 — `CleaningActivity`: full logging pass + `debug_info()`

**Anchor:** the existing `enter()`:

```gdscript
	func enter(npc: NPC) -> void:
		_session_duration = randf_range(SESSION_MIN_SEC, SESSION_MAX_SEC)
		_session_elapsed = 0.0
		_finished = false
		_pick_next_target(npc)
```

Replace with:

```gdscript
	func enter(npc: NPC) -> void:
		_session_duration = randf_range(SESSION_MIN_SEC, SESSION_MAX_SEC)
		_session_elapsed = 0.0
		_finished = false
		if NPCDebug.enabled and not _is_forced_session:
			NPCDebug.log_cleaning(npc, "session started", "target duration=%.0fs" % _session_duration)
		_pick_next_target(npc)
```

**Anchor:** the existing `_pick_next_target()`:

```gdscript
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
		if not NPCItemUser.claim_item(_item, npc):
			_item = null   ## momentary claim clash — try again next tick, don't end the session over it
			return
		if _item.has_method("set_nav_obstacle_enabled"):
			_item.set_nav_obstacle_enabled(false)
		npc.set_nav_target(_item.global_position)
```

Replace with:

```gdscript
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

	## Shared display-name helper so every log line above uses the same
	## fallback (get_display_name() when available, raw node name otherwise).
	static func _display_name(item: Node) -> String:
		if item == null:
			return "?"
		return item.get_display_name() if item.has_method("get_display_name") else str(item.name)
```

**Anchor:** the fetch-phase block inside `tick()`:

```gdscript
		if npc.held_item == null:
			## Fetch phase
			if "is_held" in _item and _item.is_held:
				NPCItemUser.release_item(_item)
				_item = null
				return
			if _item.is_in_group("shelved"):
				## Became unavailable (someone shelved it, or a stale
				## reference pointed at something already stored) — give
				## up on THIS item immediately rather than walking the
				## full distance for nothing (grab_loose() would refuse
				## it anyway, per Part A above).
				NPCItemUser.release_item(_item)
				_item = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _item.global_position) <= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _item):
					_destination = npc.find_cleaning_destination(_is_trash, _item)
					if _destination == null:
						NPCItemUser.drop_held(npc)
						_item = null
						if _is_forced_session:
							_finished = true
				else:
					NPCItemUser.release_item(_item)
					_item = null
			return
```

Replace with:

```gdscript
		if npc.held_item == null:
			## Fetch phase
			if "is_held" in _item and _item.is_held:
				if NPCDebug.enabled:
					NPCDebug.log_cleaning(npc, "target lost", "%s became held by someone else before pickup" % _display_name(_item))
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
					NPCDebug.log_cleaning(npc, "target lost", "%s became shelved before pickup" % _display_name(_item))
				NPCItemUser.release_item(_item)
				_item = null
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, _item.global_position) <= NPCItemUser.PICKUP_RANGE:
				if NPCItemUser.grab_loose(npc, _item):
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "picked up", _display_name(_item))
					_destination = npc.find_cleaning_destination(_is_trash, _item)
					if _destination == null:
						if NPCDebug.enabled:
							NPCDebug.log_cleaning(npc, "no destination", "%s has nowhere to go (is_trash=%s) — setting back down" % [
								_display_name(_item), _is_trash])
						NPCItemUser.drop_held(npc)
						_item = null
						if _is_forced_session:
							_finished = true
					elif NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "destination chosen", "%s -> %s" % [_display_name(_item), _destination.name])
				else:
					if NPCDebug.enabled:
						NPCDebug.log_cleaning(npc, "pickup failed", "grab_loose() refused %s" % _display_name(_item))
					NPCItemUser.release_item(_item)
					_item = null
			return
```

**Anchor:** the delivery block inside `tick()`:

```gdscript
		if NPCItemUser.flat_distance(npc.global_position, (_destination as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
			var item_name: String = _item.get_display_name() if _item.has_method("get_display_name") else "an item"
			if _is_trash:
				if _destination.has_method("npc_deposit_trash"):
					_destination.npc_deposit_trash(npc, _item)
				npc.log_action("Threw away %s" % item_name)
			else:
				if _destination.has_method("npc_try_place_item") and _destination.npc_try_place_item(npc, _item):
					npc.log_action("Put away %s" % item_name)
				else:
					## Placement failed (shelf filled between selection and
					## arrival) — item goes back on the ground and MUST be
					## released here, or it stays permanently claimed by
					## this NPC and invisible to every other NPC's cleaning
					## scans for the rest of the session.
					NPCItemUser.release_item(_item)
					NPCItemUser.drop_held(npc)
			_item = null
			if _is_forced_session:
				_finished = true   ## stuck-recovery grab is always exactly one item
```

Replace with:

```gdscript
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
```

**Anchor:** immediately after `CleaningActivity`'s existing `exit()`:

```gdscript
	func exit(npc: NPC) -> void:
		if _item != null:
			if _item.has_method("set_nav_obstacle_enabled") and "is_held" in _item and not _item.is_held:
				_item.set_nav_obstacle_enabled(true)
			NPCItemUser.release_item(_item)
		_item = null
```

Add immediately after it (still inside `class CleaningActivity`):

```gdscript
	## Aug 2026 — structured snapshot for NPCDebug.dump_cleaning_state().
	## "activity" key lets the dump filter to cleaning-only, since
	## RefuelActivity doesn't implement this and would otherwise show up
	## under the same generic getter.
	func debug_info() -> Dictionary:
		var phase: String = "idle"
		if _item != null:
			phase = "carrying" if _destination != null else "fetching"
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

Stop and report on anchor mismatch — no improvisation.

---

## Part C — `JobBoard.gd`: track WHY items aren't cleanable + a debug snapshot getter

### C1 — Track trash blocked by missing receptacle, expand the periodic print

**Anchor:**

```gdscript
var _cleaning_idle_tracker: Dictionary = {}   ## item instance_id -> {"pos": Vector3, "since_msec": int}
var _trash_items_cache: Array = []
var _organizable_items_cache: Array = []
```

Replace with:

```gdscript
var _cleaning_idle_tracker: Dictionary = {}   ## item instance_id -> {"pos": Vector3, "since_msec": int}
var _trash_items_cache: Array = []
var _organizable_items_cache: Array = []

## Aug 2026 — count of genuine trash-classified items sitting in the world
## RIGHT NOW that are being silently excluded because no trash_receptacle
## exists anywhere in the level yet (see _has_trash_receptacle()'s own
## comment — this is a known, by-design permanent gap until a receptacle
## object is added). Tracked purely so debug tooling can surface it as a
## specific reason instead of it looking identical to "nothing to clean".
var _trash_blocked_by_no_receptacle: int = 0
```

**Anchor:** inside `_scan_cleaning()`:

```gdscript
func _scan_cleaning(seen: Dictionary) -> void:
	var trash_receptacle_exists: bool = _has_trash_receptacle()
	var new_trash: Array = []
	var new_organizable: Array = []
	var seen_ids: Dictionary = {}

	for item: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(item) or not ("is_held" in item):
			continue
		if item.is_held or item.is_in_group("shelved"):
			continue
		var id: int = item.get_instance_id()
		seen_ids[id] = true

		if _is_trash_item(item):
			if trash_receptacle_exists:
				new_trash.append(item)
			continue   ## trash never also counts as organizable
```

Replace with:

```gdscript
func _scan_cleaning(seen: Dictionary) -> void:
	var trash_receptacle_exists: bool = _has_trash_receptacle()
	var new_trash: Array = []
	var new_organizable: Array = []
	var seen_ids: Dictionary = {}
	var trash_blocked_this_scan: int = 0

	for item: Node in get_tree().get_nodes_in_group("pickup"):
		if not is_instance_valid(item) or not ("is_held" in item):
			continue
		if item.is_held or item.is_in_group("shelved"):
			continue
		var id: int = item.get_instance_id()
		seen_ids[id] = true

		if _is_trash_item(item):
			if trash_receptacle_exists:
				new_trash.append(item)
			else:
				trash_blocked_this_scan += 1
			continue   ## trash never also counts as organizable
```

**Anchor:** the end of `_scan_cleaning()`:

```gdscript
	for id in _cleaning_idle_tracker.keys().duplicate():
		if not seen_ids.has(id):
			_cleaning_idle_tracker.erase(id)

	_trash_items_cache = new_trash
	_organizable_items_cache = new_organizable
	if NPCDebug.enabled:
		print("[JobBoard] Cleaning scan: %d trash, %d organizable, %d tracked-but-not-yet-idle" \
			% [new_trash.size(), new_organizable.size(), _cleaning_idle_tracker.size() - new_organizable.size()])
```

Replace with:

```gdscript
	for id in _cleaning_idle_tracker.keys().duplicate():
		if not seen_ids.has(id):
			_cleaning_idle_tracker.erase(id)

	_trash_items_cache = new_trash
	_organizable_items_cache = new_organizable
	_trash_blocked_by_no_receptacle = trash_blocked_this_scan
	if NPCDebug.enabled:
		var blocked_suffix: String = " | %d trash item(s) blocked (no trash_receptacle in level)" % trash_blocked_this_scan \
			if trash_blocked_this_scan > 0 else ""
		print("[JobBoard] Cleaning scan: %d trash, %d organizable, %d tracked-but-not-yet-idle%s" \
			% [new_trash.size(), new_organizable.size(), _cleaning_idle_tracker.size() - new_organizable.size(), blocked_suffix])
```

Stop and report on anchor mismatch — no improvisation.

### C2 — Getters for `NPC.get_cleaning_unavailable_reason()` and the debug dump

**Anchor:** immediately after `get_organizable_items()`:

```gdscript
func get_organizable_items() -> Array:
	_organizable_items_cache = _organizable_items_cache.filter(func(i): return is_instance_valid(i))
	return _organizable_items_cache
```

Add immediately after it:

```gdscript
## Aug 2026 — cheap count for NPC.get_cleaning_unavailable_reason()'s
## "STILL_SETTLING" check. Same subtraction the periodic debug print
## already does, exposed as a real getter instead of duplicated inline.
func get_pending_cleaning_count() -> int:
	return maxi(0, _cleaning_idle_tracker.size() - _organizable_items_cache.size())

## Aug 2026 — for NPC.get_cleaning_unavailable_reason()'s "NO_TRASH_
## RECEPTACLE" check.
func get_trash_blocked_by_no_receptacle_count() -> int:
	return _trash_blocked_by_no_receptacle

## Aug 2026 — full snapshot for NPCDebug.dump_cleaning_state(). Resolves
## every still-tracked-but-not-yet-idle item's live remaining time, so a
## single dump answers "why isn't X organizable yet" directly instead of
## needing to watch the periodic scan print over time.
func get_cleaning_debug_snapshot() -> Dictionary:
	var idle_needed: float = _effective_cleaning_idle_min_sec()
	var now: int = Time.get_ticks_msec()
	var pending: Array = []
	for id in _cleaning_idle_tracker.keys():
		var item: Object = instance_from_id(id)
		if item == null or not is_instance_valid(item) or _organizable_items_cache.has(item):
			continue   ## already ready, or freed since — not "pending"
		var rec: Dictionary = _cleaning_idle_tracker[id]
		var elapsed: float = float(now - int(rec["since_msec"])) / 1000.0
		var name: String = item.get_display_name() if item.has_method("get_display_name") else str(item.name)
		pending.append({"name": name, "elapsed_sec": elapsed, "remaining_sec": maxf(0.0, idle_needed - elapsed)})
	return {
		"trash_count": _trash_items_cache.size(),
		"organizable_count": _organizable_items_cache.size(),
		"pending": pending,
		"trash_blocked_by_no_receptacle": _trash_blocked_by_no_receptacle,
		"idle_gate_sec": idle_needed,
		"idle_gate_is_debug": NPCDebug.enabled,
	}
```

Stop and report on anchor mismatch — no improvisation.

---

## Part D — `NPC.gd`: specific unavailable-reason resolver

**Anchor:** immediately after the existing `find_cleaning_destination()`
function (right before `find_next_refuel_target()` begins):

```gdscript
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

Add immediately after it:

```gdscript
## Specific, human-readable-key reason Cleaning currently isn't available
## for THIS NPC (Aug 2026) — replaces a blanket "nothing to clean" with an
## exact cause. Checked in priority order (each check assumes the ones
## before it didn't already explain the situation):
##   ""                     — available right now
##   "NOTHING_TO_CLEAN"     — genuinely nothing tracked at all
##   "NO_TRASH_RECEPTACLE"  — trash-eligible items exist but there's no
##                            receptacle anywhere in the level (permanent
##                            gap until one's built — see JobBoard.gd)
##   "STILL_SETTLING"       — items exist and are being tracked, but none
##                            have sat idle long enough yet (see
##                            JobBoard.CLEANING_IDLE_MIN_SEC)
##   "ALL_CLAIMED"          — ready items exist but every one is already
##                            claimed by another NPC
##   "NO_STORAGE_AVAILABLE" — a ready organizable item exists and is
##                            claimable, but zero shelves/End
##                            Tables/Dressers exist anywhere in the level
##   "STORAGE_FULL"         — same as above, except storage exists but
##                            every candidate is currently full
## NPCTalkMenuUI maps these to player-facing strings — see
## CLEANING_UNAVAILABLE_REASONS there. Keep both in sync if this list changes.
func get_cleaning_unavailable_reason() -> String:
	var trash: Array = JobBoard.get_trash_items()
	var organizable: Array = JobBoard.get_organizable_items()
	if trash.is_empty() and organizable.is_empty():
		if JobBoard.get_trash_blocked_by_no_receptacle_count() > 0:
			return "NO_TRASH_RECEPTACLE"
		if JobBoard.get_pending_cleaning_count() > 0:
			return "STILL_SETTLING"
		return "NOTHING_TO_CLEAN"
	var target: Dictionary = find_cleaning_target()
	if target.is_empty():
		return "ALL_CLAIMED"   ## ready items exist, but this NPC can't claim any of them
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

Stop and report on anchor mismatch — no improvisation.

---

## Part E — `NPCTalkMenuUI.gd`: surface the specific reason in the request toast

**Anchor:**

```gdscript
	var action_desc: String = String(entry.get("action_desc", "heading to work"))
	var empty_desc: String = String(entry.get("empty_desc", "nothing to do right now"))
	if job_type == "CLEANING":
		_issue_command(NPCBrain.CommandCleaningActivity.new(), action_desc, empty_desc)
	elif job_type == "REFUEL":
		_issue_command(NPCBrain.CommandRefuelActivity.new(), action_desc, empty_desc)
	else:
		_issue_command(NPCBrain.CommandJobActivity.new(job_type), action_desc, empty_desc)
```

Replace with:

```gdscript
	var action_desc: String = String(entry.get("action_desc", "heading to work"))
	var empty_desc: String = String(entry.get("empty_desc", "nothing to do right now"))
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

**Anchor:** the existing `NPC_JOB_MENU_ENTRIES` constant (add the new
mapping constant right after it):

```gdscript
const NPC_JOB_MENU_ENTRIES: Array[Dictionary] = [
	{"type": "HARVEST", "label": "Harvest the plants", "action_desc": "heading to harvest", "empty_desc": "nothing ready to harvest"},
	{"type": "REPLACE_FILTER", "label": "Replace the water filters", "action_desc": "heading to replace a filter", "empty_desc": "no filters need replacing"},
	{"type": "REFUEL", "label": "Refuel the generator", "action_desc": "heading to refuel", "empty_desc": "nothing needs refueling"},
	{"type": "CLEANING", "label": "Clean the bunker", "action_desc": "heading to clean up", "empty_desc": "nothing to clean right now"},
]
```

Add immediately after it:

```gdscript
## Aug 2026 — maps NPC.get_cleaning_unavailable_reason()'s keys to the
## exact player-facing toast text. Keep in sync with that function's own
## doc comment if the reason set ever changes. Falls back to the generic
## "nothing to clean right now" (NPC_JOB_MENU_ENTRIES' empty_desc) for any
## key not listed here, including "" (available).
const CLEANING_UNAVAILABLE_REASONS: Dictionary = {
	"NOTHING_TO_CLEAN":     "nothing to clean right now",
	"NO_TRASH_RECEPTACLE":  "there's trash, but nowhere to throw it away yet",
	"STILL_SETTLING":       "everything's still settling — check back shortly",
	"ALL_CLAIMED":          "everything's already being handled by someone else",
	"NO_STORAGE_AVAILABLE": "there's nothing to put things away in",
	"STORAGE_FULL":         "storage is full",
}
```

Stop and report on anchor mismatch — no improvisation.

---

## Part F — `NPCDebug.gd`: the on-demand full dump

**Anchor:** immediately after the existing `log_cleaning()`:

```gdscript
## Cleaning (Aug 2026) — mirrors log_snatch()'s staged pattern.
static func log_cleaning(npc: Node, stage: String, detail: String) -> void:
	if not enabled:
		return
	print("%s CLEANING [%s]: %s" % [_fmt(npc), stage, detail])
```

Add immediately after it:

```gdscript
## One-shot full Cleaning-system snapshot — call from the F7 "Print NPC
## Cleaning Debug State" row. Always prints regardless of `enabled` (an
## explicit on-demand request, same convention as dump_all()). Covers:
## JobBoard's caches (including WHY something isn't ready yet — per-item
## remaining idle time, and trash blocked by a missing receptacle),
## every storage destination's current occupancy, and every NPC currently
## mid-clean with its exact phase/item/destination/session progress.
static func dump_cleaning_state(tree: SceneTree) -> void:
	print("═══ NPC Cleaning Debug Dump ═══════════════════════════")
	var snap: Dictionary = JobBoard.get_cleaning_debug_snapshot()
	print("Idle gate: %.1fs%s" % [
		float(snap["idle_gate_sec"]),
		" (DEBUG override active — real gameplay uses 90s)" if bool(snap["idle_gate_is_debug"]) else ""])
	print("Ready now — trash: %d   organizable: %d" % [int(snap["trash_count"]), int(snap["organizable_count"])])
	if int(snap["trash_blocked_by_no_receptacle"]) > 0:
		print("  ⚠ %d trash item(s) exist but no trash_receptacle in the level — permanently blocked until one's added" \
			% int(snap["trash_blocked_by_no_receptacle"]))

	var pending: Array = snap["pending"]
	if pending.is_empty():
		print("Pending (tracked, not yet idle-eligible): none")
	else:
		print("Pending (tracked, not yet idle-eligible): %d" % pending.size())
		for p: Dictionary in pending:
			print("  - %s: %.1fs elapsed / %.1fs remaining" % [p["name"], p["elapsed_sec"], p["remaining_sec"]])

	print("── Destinations (\"shelving\" group) ──")
	var dest_count: int = 0
	for candidate: Node in tree.get_nodes_in_group("shelving"):
		if not is_instance_valid(candidate):
			continue
		dest_count += 1
		print("  %s: %s" % [candidate.name, _describe_storage_room(candidate)])
	if dest_count == 0:
		print("  (none — no shelf/End Table/Dresser exists anywhere in the level)")

	print("── NPCs currently cleaning ──")
	var any_cleaning: bool = false
	for npc: Node in tree.get_nodes_in_group("npc"):
		if not is_instance_valid(npc) or not ("brain" in npc) or npc.brain == null:
			continue
		if not npc.brain.has_method("get_current_activity_debug_info"):
			continue
		var info: Dictionary = npc.brain.get_current_activity_debug_info()
		if info.is_empty() or String(info.get("activity", "")) != "cleaning":
			continue
		any_cleaning = true
		var npc_name: String = npc.npc_name if "npc_name" in npc else "?"
		print("  %s: phase=%s item=%s is_trash=%s destination=%s session=%.0fs/%.0fs%s" % [
			npc_name, info.get("phase", "?"), info.get("item", ""), info.get("is_trash", false),
			info.get("destination", ""), info.get("session_elapsed", 0.0), info.get("session_duration", 0.0),
			" (forced/stuck-recovery)" if info.get("forced", false) else ""])
	if not any_cleaning:
		print("  (none)")
	print("═════════════════════════════════════════════════════════")

## Duck-typed room description — Shelving.gd uses `slots` (Array of
## per-slot stacks), LightStorage.gd (End Table/Dresser) uses `stored`
## (flat Array, null = empty slot). Anything joining "shelving" without
## either shape just reports as unknown rather than erroring.
static func _describe_storage_room(candidate: Node) -> String:
	if "slots" in candidate and candidate.slots is Array:
		var used: int = 0
		for stack in candidate.slots:
			if stack is Array and not stack.is_empty():
				used += 1
		return "shelf, %d/%d slots used" % [used, candidate.slots.size()]
	if "stored" in candidate and candidate.stored is Array:
		var used2: int = 0
		for slot in candidate.stored:
			if slot != null:
				used2 += 1
		var label: String = candidate.display_name if "display_name" in candidate else "storage"
		return "%s, %d/%d used" % [label, used2, candidate.stored.size()]
	return "(unknown storage type)"
```

Stop and report on anchor mismatch — no improvisation.

---

## Part G — `AdminMenu.gd`: new F7 row for the dump

**Anchor:**

```gdscript
			["Print NPC Debug State", _on_npc_print_debug_pressed],
```

Replace with:

```gdscript
			["Print NPC Debug State", _on_npc_print_debug_pressed],
			["Print NPC Cleaning Debug State", _on_npc_print_cleaning_debug_pressed],
```

**Anchor:**

```gdscript
func _on_npc_print_debug_pressed() -> void:
	NPCDebug.dump_all(get_tree())
```

Replace with:

```gdscript
func _on_npc_print_debug_pressed() -> void:
	NPCDebug.dump_all(get_tree())

func _on_npc_print_cleaning_debug_pressed() -> void:
	NPCDebug.dump_cleaning_state(get_tree())
```

Stop and report on anchor mismatch — no improvisation.

---

## Testing

1. Enable NPC Debug Logging (F7). Drop a loose item, watch the console —
   confirm you now see the item appear in the periodic
   `[JobBoard] Cleaning scan:` line's tracked count, then ask an NPC to
   clean and confirm you see, in order: `target picked` → `picked up` →
   `destination chosen` → `delivered`, each naming the actual item and
   destination.
2. Press the new "Print NPC Cleaning Debug State" F7 row with nothing
   happening — confirm it lists every real shelf/End Table/Dresser with
   accurate occupancy, and an accurate ready/pending item breakdown.
3. Drop an item, immediately open the dump — confirm it shows up under
   "Pending" with an accurate elapsed/remaining time; wait, dump again —
   confirm remaining time has counted down correctly and it eventually
   moves into "Ready now — organizable".
4. This is the direct test for the "takes a minute" report: with debug
   OFF (real 90s gate), drop an item and ask an NPC to clean immediately
   — confirm the toast now says something specific (likely
   "everything's still settling") instead of the old blanket message.
   With debug ON (5s gate), confirm the same request becomes available
   almost immediately, and the dump's "Pending" list empties out into
   "Ready now" within a few seconds of watching it. This should tell you
   definitively whether the delay you're seeing matches the idle gate's
   own timing or clearly doesn't (if it doesn't, that's a new, distinct
   bug to chase next, not this one).
5. Fill every shelf/End Table/Dresser in the test area to capacity, drop
   an eligible item, request Cleaning — confirm the toast now says
   "storage is full" specifically.
6. Test in an area with zero shelves/End Tables/Dressers at all, drop an
   eligible item, request Cleaning — confirm the toast says "there's
   nothing to put things away in", distinct from the full-storage case.
7. Have two NPCs both target the same item's general vicinity so one
   claims it first, immediately request Cleaning from the second NPC —
   confirm "everything's already being handled by someone else".
8. Force a placement failure (contrive a shelf that fills between
   selection and arrival, e.g. two NPCs racing for the same shelf's last
   slot) — confirm the console shows `delivery failed` with the specific
   reason, not just a silent drop.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
73. Enable NPC Debug Logging, drop a loose item, ask an NPC to clean —
    confirm the console shows target picked / picked up / destination
    chosen / delivered lines naming the actual item and destination, not
    just session start/end.
74. Press F7 → "Print NPC Cleaning Debug State" — confirm it lists every
    shelf/End Table/Dresser's occupancy, every pending (not-yet-idle)
    item with an accurate remaining-time countdown, and any NPC
    currently mid-clean with its exact phase/item/destination.
75. Fill all storage in a test area, request Cleaning — confirm the
    toast says "storage is full" specifically. Empty the area of storage
    entirely, request again — confirm a distinct "nothing to put things
    away in" message instead of the same generic failure.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Cleaning Debug Overhaul + Specific Unavailable-Reason Errors (Aug 2026)

- CleaningActivity now logs every meaningful decision point (target
  picked, claim failed, picked up, destination chosen, no destination,
  delivered, delivery failed, target lost, forced grab, session
  started/ended) via NPCDebug.log_cleaning() — previously only session-
  end was logged.
- Added NPCActivity.debug_info() (optional, empty by default) and wired
  it through NPCBrain.get_current_activity_debug_info(); CleaningActivity
  implements it with phase/item/destination/session-progress.
- Added a new F7 row, "Print NPC Cleaning Debug State"
  (NPCDebug.dump_cleaning_state()) — one-shot snapshot of JobBoard's
  ready/pending caches (with live per-item remaining idle-timer seconds),
  every "shelving"-group destination's occupancy, and every NPC currently
  mid-clean.
- JobBoard now tracks trash items blocked by the missing trash_receptacle
  separately (get_trash_blocked_by_no_receptacle_count()), and exposes
  get_pending_cleaning_count()/get_cleaning_debug_snapshot() for the
  above.
- Added NPC.get_cleaning_unavailable_reason() — replaces the blanket
  "nothing to clean right now" toast with a specific one: NOTHING_TO_
  CLEAN, NO_TRASH_RECEPTACLE, STILL_SETTLING, ALL_CLAIMED, NO_STORAGE_
  AVAILABLE, or STORAGE_FULL. Mapped to player-facing text in
  NPCTalkMenuUI.CLEANING_UNAVAILABLE_REASONS.

Files touched: `scripts/npc/NPCDebug.gd`, `scripts/npc/NPCActivity.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/npc/JobBoard.gd`, `scripts/npc/NPC.gd`,
`scripts/ui/npc/NPCTalkMenuUI.gd`, `scripts/ui/menus/AdminMenu.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
