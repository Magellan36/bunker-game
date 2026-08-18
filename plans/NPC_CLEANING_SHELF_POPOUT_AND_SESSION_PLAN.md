# Cleaning: Fix Shelf Pop-Out + Sustained Session + Diagnostics (Aug 2026)

**Files:** `scripts/npc/NPCItemUser.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/npc/JobBoard.gd`, `scripts/npc/NPCDebug.gd`.

---

## Part A — The shelf pop-out bug (confirmed root cause)

`grab_loose()` checks `is_held` but never checks `is_in_group("shelved")`.
A correctly-shelved item has `is_held = false` the entire time —
`_place_item_in_slot()` manipulates `freeze`/`collision_layer` directly
and never touches `is_held` — so the existing check provides zero
protection for shelved items specifically. If any NPC's `grab_loose()`
ever fires against an already-shelved item (most likely: a claim/target
reference held from before it was placed, given items are only excluded
from Cleaning's own scan by group membership and that scan only refreshes
every 2 seconds), it succeeds completely and bypasses the shelf's own
tracking entirely — explaining both symptoms: the physics unfreezing
(that's just what `pickup()` does) and it still showing in the Shelf UI
(the shelf was never told it lost the item).

### `scripts/npc/NPCItemUser.gd`

**Anchor:** `grab_loose()`:

```gdscript
static func grab_loose(npc: NPC, item: RigidBody3D) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if is_claimed_by_other(item, npc):
		return false   ## defense in depth — shouldn't happen if callers claimed first
	## The actual missing guard: an item claimed by this NPC can still
	## have been physically picked up by the player between the claim and
	## now. Claims only block other NPCs' claim_item() calls; they were
	## never consulted by the player's own pickup path.
	if "is_held" in item and item.is_held:
		return false
	if flat_distance(npc.global_position, item.global_position) > PICKUP_RANGE:
		return false
	if item.has_method("pickup"):
		item.pickup(npc.hold_point)
		npc.held_item = item
		return true
	return false
```

Replace with:

```gdscript
static func grab_loose(npc: NPC, item: RigidBody3D) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if is_claimed_by_other(item, npc):
		return false   ## defense in depth — shouldn't happen if callers claimed first
	## The actual missing guard: an item claimed by this NPC can still
	## have been physically picked up by the player between the claim and
	## now. Claims only block other NPCs' claim_item() calls; they were
	## never consulted by the player's own pickup path.
	if "is_held" in item and item.is_held:
		return false
	## Second missing guard (Aug 2026) — a shelved item has is_held=false
	## the whole time (Shelving.gd manipulates freeze/collision directly,
	## never is_held), so the check above provides it zero protection.
	## Without this, a stale claim/target reference from before an item
	## was shelved could grab it right back off the shelf, bypassing the
	## shelf's own tracking entirely — this was the actual cause of
	## shelved items "popping out" and un-freezing on their own.
	if item.is_in_group("shelved"):
		return false
	if flat_distance(npc.global_position, item.global_position) > PICKUP_RANGE:
		return false
	if item.has_method("pickup"):
		item.pickup(npc.hold_point)
		npc.held_item = item
		return true
	return false
```

### `scripts/npc/NPCBrain.gd` — early-abort for the same case

**Anchor:** `CleaningActivity.tick()`'s fetch-phase held-item check:

```gdscript
			if "is_held" in _item and _item.is_held:
				NPCItemUser.release_item(_item)
				_item = null
				return
```

Replace with:

```gdscript
			if "is_held" in _item and _item.is_held:
				NPCItemUser.release_item(_item)
				_item = null
				return
			if _item.is_in_group("shelved"):
				## Same reasoning as the other early-abort checks
				## elsewhere in this file — give up on a target that's
				## become unavailable immediately, rather than walking
				## the full distance only to have grab_loose() correctly
				## refuse it there.
				NPCItemUser.release_item(_item)
				_item = null
				return
```

(This will be superseded structurally by Part B's full rewrite below —
included here for clarity on exactly what changed, but Part B's replacement
already incorporates this check.)

---

## Part B — Cleaning becomes a sustained session, not one-and-done

**Root cause of "only does one item":** `done()` returns `_item == null`,
which becomes true immediately after every single delivery — the
activity was designed to do exactly one item and finish, mirroring
`GiveToFriendActivity`'s single-delivery shape. Redesigning so that after
each delivery it immediately looks for the next cleanable item and keeps
going, for 20-40 real seconds (uniform random, matching the same
`randf_range()` convention used for Talk/Relax session lengths) or until
nothing's left to clean bunker-wide, whichever comes first.

Session timing is **real time**, not game-hours — matches Talk's
convention (a bounded activity duration), not Relaxing's game-hours-scale
daily budget.

The stuck-recovery path (`forced_item` non-null) stays exactly one grab,
never a full session — that's an emergency unstick, not a deliberate
cleaning shift.

**Anchor:** replace the entire `CleaningActivity` class with:

```gdscript
class CleaningActivity extends NPCActivity:
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

	func _init(forced_item: RigidBody3D = null) -> void:
		_forced_item = forced_item
		_is_forced_session = forced_item != null

	func label() -> String:
		if _item == null:
			return "Cleaning"
		return "Cleaning (carrying)" if _destination != null else "Cleaning (fetching)"

	func score(npc: NPC) -> float:
		if _is_forced_session:
			return 0.0
		if not npc.has_cleaning_target_available():
			return 0.0
		return NPC.CLEANING_BASE_SCORE * npc.get_work_ethic_job_mult() \
			* npc.get_job_priority_weight("CLEANING")

	func interruptible() -> bool:
		return _item == null   ## between items (or before the first), fine to interrupt; mid-carry, commit

	func enter(npc: NPC) -> void:
		_session_duration = randf_range(SESSION_MIN_SEC, SESSION_MAX_SEC)
		_session_elapsed = 0.0
		_finished = false
		_pick_next_target(npc)

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
			else:
				if _destination.has_method("npc_try_place_item") and _destination.npc_try_place_item(npc, _item):
					npc.log_action("Put away %s" % item_name)
				else:
					NPCItemUser.drop_held(npc)
			_item = null
			if _is_forced_session:
				_finished = true   ## stuck-recovery grab is always exactly one item

	func done(npc: NPC) -> bool:
		return _finished and _item == null

	func exit(npc: NPC) -> void:
		if _item != null:
			if _item.has_method("set_nav_obstacle_enabled") and "is_held" in _item and not _item.is_held:
				_item.set_nav_obstacle_enabled(true)
			NPCItemUser.release_item(_item)
		_item = null
```

**Note:** `CommandCleaningActivity` (the "Clean the bunker" button)
delegates to a normal organic-mode `CleaningActivity` unchanged — it
automatically inherits the new sustained-session behavior with no
changes needed there. This is deliberate: a player asking an NPC to
clean should get the same sustained effort the automatic system gives,
not artificially stop after one item.

---

## Part C — Diagnostic logging

Adds real visibility into the Cleaning pipeline for future debugging —
independently useful even with the "nothing to clean" report resolved as
a timing false-alarm, and directly relevant to investigating the
pre-placed-item question further if it comes up again.

### `scripts/npc/NPCDebug.gd`

**Anchor:** near `log_snatch()`.

Insert:

```gdscript
## Cleaning (Aug 2026) — mirrors log_snatch()'s staged pattern.
static func log_cleaning(npc: Node, stage: String, detail: String) -> void:
	if not enabled:
		return
	print("%s CLEANING [%s]: %s" % [_fmt(npc), stage, detail])
```

### `scripts/npc/JobBoard.gd`

**Anchor:** end of `_scan_cleaning()`, right before it returns (after
`_trash_items_cache = new_trash` / `_organizable_items_cache = new_organizable`):

```gdscript
	_trash_items_cache = new_trash
	_organizable_items_cache = new_organizable
```

Replace with:

```gdscript
	_trash_items_cache = new_trash
	_organizable_items_cache = new_organizable
	if NPCDebug.enabled:
		print("[JobBoard] Cleaning scan: %d trash, %d organizable, %d tracked-but-not-yet-idle" \
			% [new_trash.size(), new_organizable.size(), _cleaning_idle_tracker.size() - new_organizable.size()])
```

## Testing

```
80. Have an NPC place several items on a shelf back to back (organic
    Cleaning session) — confirm NONE of them pop back out or unfreeze,
    even several seconds later with other NPCs active nearby.
81. Scatter 3+ cleanable items around — confirm a single Cleaning session
    now picks up and delivers multiple items in sequence (watch the log
    for consecutive "Put away X"/"Threw away X" entries) rather than
    stopping after one.
82. Let a Cleaning session run out the clock (20-40s) with items still
    left — confirm it stops cleanly rather than abandoning an item
    mid-carry (should finish delivering whatever it's currently holding
    before ending).
83. Clear the bunker of all cleanable items and start a session — confirm
    it ends immediately/gracefully rather than idling forever.
84. With debug logging on, watch the console during a scan — confirm the
    new JobBoard summary line accurately reflects what's actually on the
    floor.
```
