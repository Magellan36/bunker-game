# Fix: Shelf Pop-Out (Root Cause Found) + Cleaning Discovery Investigation (Aug 2026)

**Files:** `scripts/world/furniture/Shelving.gd`, `scripts/npc/NPCBrain.gd`,
`scripts/npc/JobBoard.gd`, `docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** This plan was written against
a fresh clone — do not trust that any prior session's fix landed; verify
every anchor below against the live file before editing.

---

## Context — read this first

Brannon reported, after the last agent's session (which failed out
mid-work, no fix actually applied):

1. Items placed on shelves by NPCs (confirmed with a Can Case) still pop
   back out and unfreeze roughly ~1 second after correct placement.
2. Cleaning ("nothing to clean") now fails almost universally, for both
   pre-placed and purchased/build-mode items — a regression from a
   previous state where only pre-placed items had trouble.
3. Cleaning behavior is sporadic within and across sessions — sometimes
   NPCs can't clean anything for a while, then start working correctly
   later, with no obvious trigger the user can identify.

Part A below is a confirmed, verified root cause for issue #1 with an
exact fix. Part B is an investigation + fix for issues #2/#3 — I found a
real secondary bug (a claim leak) and strong circumstantial evidence
pointing at the idle-time gate as the dominant cause of both the
regression and the sporadic behavior, but this needs to be confirmed
against live/runtime testing before we call it closed. Follow Part B's
instrumentation step and report back the actual timing behavior.

---

## Part A — Shelf pop-out (root cause confirmed)

### Root cause

`Shelving.gd`'s **player** shelf-placement path (`_try_place_item()`)
explicitly clears the item's held-state before shelving it:

```gdscript
if "is_held"        in item: item.is_held       = false
if "_hold_point"    in item: item._hold_point   = null
if "from_inventory" in item: item.from_inventory = false
```

`Shelving.gd`'s **NPC** shelf-placement path, `npc_try_place_item()`
(used by `CleaningActivity`), never does this. It clears
`npc.held_item`, but the *item's own* `is_held` flag and `_hold_point`
reference are left exactly as `pickup()` set them when the NPC first
picked the item up — `is_held = true`, `_hold_point = npc.hold_point`.

`PickupableItem._physics_process()` guards on `is_held`/`_hold_point`,
not on which shelf/group the item is in:

```gdscript
func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return
	...
	if not from_inventory:
		if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_out_of_range_time = 0.0
				_do_knocked_out()
				return
```

Because `is_held` and `_hold_point` are never cleared, this block keeps
running every physics frame on a shelved item — measuring distance
between the item and the **NPC's hold point**, which keeps moving as the
NPC walks away to its next `CleaningActivity` target immediately after
delivery. `KNOCK_DISTANCE` is 2.2m and `KNOCK_LINGER_TIME` is 0.35s, so
within roughly a second of the NPC walking off, `_do_knocked_out()`
fires:

```gdscript
func _do_knocked_out() -> void:
	is_held         = false
	_hold_point     = null
	gravity_scale   = 1.0
	freeze          = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	...
```

This unfreezes the item, restores its real collision layer, and gives it
a random outward+upward velocity — which is exactly the "pops out and
unfreezes about a second after placement" behavior reported. It's not a
timing/physics-race bug in the shelf animation at all; it's a stale
"still being carried" state that never gets cleared for the NPC path,
so the game's own knockout system (correctly) treats the shelved item as
a dropped/knocked-out held item once its old carrier wanders off.

The fix is the same two lines the player path already has.

### Fix

**File:** `scripts/world/furniture/Shelving.gd`

**Anchor:** the current `npc_try_place_item()`:

```gdscript
func npc_try_place_item(npc: Node, item: RigidBody3D) -> bool:
	var slot: int = _find_slot_for(item)
	if slot == -1:
		return false

	if "held_item" in npc and npc.held_item == item:
		npc.held_item = null

	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	if item.get_parent() != world_root:
		item.get_parent().remove_child(item)
		world_root.add_child(item)

	var stack_idx: int = slots[slot].size()
	slots[slot].append(item)
	_place_item_in_slot(item, slot, stack_idx)
	item_placed.emit(slot, item)
	return true
```

Replace with:

```gdscript
func npc_try_place_item(npc: Node, item: RigidBody3D) -> bool:
	var slot: int = _find_slot_for(item)
	if slot == -1:
		return false

	if "held_item" in npc and npc.held_item == item:
		npc.held_item = null

	## Mirror _try_place_item()'s (player path) held-state clear exactly.
	## Without this, the item's own is_held/_hold_point stay set to the
	## NPC that carried it here — PickupableItem._physics_process() then
	## keeps measuring distance against the NPC's (now walking-away)
	## hold point every frame, and once that exceeds KNOCK_DISTANCE for
	## KNOCK_LINGER_TIME, _do_knocked_out() fires and un-freezes/ejects
	## the item off the shelf. This was the actual cause of shelved
	## items popping back out ~1s after an NPC placed them.
	if "is_held"        in item: item.is_held       = false
	if "_hold_point"    in item: item._hold_point   = null
	if "from_inventory" in item: item.from_inventory = false

	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	if item.get_parent() != world_root:
		item.get_parent().remove_child(item)
		world_root.add_child(item)

	var stack_idx: int = slots[slot].size()
	slots[slot].append(item)
	_place_item_in_slot(item, slot, stack_idx)
	item_placed.emit(slot, item)
	return true
```

Stop and report on anchor mismatch — no improvisation.

---

## Part B — Cleaning discovery: secondary bug fix + required investigation

I read `JobBoard._scan_cleaning()`, `NPC.find_cleaning_target()`,
`NPC.find_cleaning_destination()`, and `CleaningActivity` end to end.
No outright syntax/logic break jumped out. I did find one real bug (a
claim leak, fixed below) and one permanent design gap worth flagging,
but the leading explanation for "fails constantly, then randomly starts
working" is `CLEANING_IDLE_MIN_SEC`, which has been live at 90 seconds
this whole time and was never given a debug bypass:

```gdscript
const CLEANING_IDLE_MIN_SEC: float = 90.0
const CLEANING_IDLE_MOVE_TOLERANCE: float = 0.3
```

`_scan_cleaning()` will not add a non-trash item to
`_organizable_items_cache` until it has sat within 0.3m of its own
position, untouched, for a continuous 90 seconds — and the tracking
clock **restarts** any time the item moves more than that. This matches
the reported symptom shape closely: nothing eligible right after
spawning/placing/loading, then it starts working once items have
genuinely sat still for a minute and a half, and a fresh session or any
disturbance (including the NPC's own walk-by, physics settling, or the
player nudging something) resets the clock and reproduces the "fails
again" report.

### B1 — Fix: claim leak on delivery (confirmed real bug)

`CleaningActivity.tick()`'s delivery branch never releases the item's
claim after trash deposit, or after a failed placement (shelf became
full between target-selection and delivery):

```gdscript
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
```

`NPCItemUser.drop_held()` does not release the claim either. In the
failed-placement case, the item is dropped back into the world still
fully eligible for cleaning, but permanently marked claimed by that NPC
in `NPCItemUser._claims` — which blocks every *other* NPC from ever
picking it up (the claiming NPC itself is unaffected, since
`is_claimed_by_other()` only blocks other NPCs). Over a session with
multiple NPCs cleaning, this compounds and silently shrinks the pool of
organizable items available to the group. Successful trash deposit has
the same gap, though it's harmless there since the item is gone.

**File:** `scripts/npc/NPCBrain.gd`

**Anchor:** inside `CleaningActivity.tick()`, the delivery/travel-phase
block:

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

(Trash deposit deliberately left without an explicit `release_item()`
call — the item is freed/consumed by `npc_deposit_trash()`, so the claim
entry becomes an orphaned dictionary key rather than a live block; not
worth the added complexity to also erase it there, but flag it if that
assumption turns out wrong once a real trash receptacle exists.)

### B2 — Required live investigation before declaring #2/#3 fixed

Do not just apply B1 and report done — the idle-gate hypothesis needs to
be confirmed against actual runtime behavior, since B1 alone won't
explain a fresh-session "nothing to clean" report with only one NPC in
play.

**File:** `scripts/npc/JobBoard.gd`

Add a debug-only bypass so this can be tested in under 90 seconds instead
of waiting it out, and add print instrumentation to `_scan_cleaning()`'s
existing debug print so a test run shows exactly what's blocking each
tracked item:

**Anchor:** the constant declaration:

```gdscript
const CLEANING_IDLE_MIN_SEC: float = 90.0
```

Replace with:

```gdscript
const CLEANING_IDLE_MIN_SEC: float = 90.0
## Debug-only override (F7 → NPCDebug.enabled) so idle-gate timing can be
## tested in seconds instead of minutes. Never changes real gameplay —
## only takes effect while NPCDebug.enabled is true.
const CLEANING_IDLE_MIN_SEC_DEBUG: float = 5.0

func _effective_cleaning_idle_min_sec() -> float:
	return CLEANING_IDLE_MIN_SEC_DEBUG if NPCDebug.enabled else CLEANING_IDLE_MIN_SEC
```

**Anchor:** inside `_scan_cleaning()`:

```gdscript
		if (now - int(rec["since_msec"])) >= int(CLEANING_IDLE_MIN_SEC * 1000.0):
			new_organizable.append(item)
```

Replace with:

```gdscript
		if (now - int(rec["since_msec"])) >= int(_effective_cleaning_idle_min_sec() * 1000.0):
			new_organizable.append(item)
```

### Testing (do these in order, report exact results for each)

1. With `NPCDebug.enabled` **off** (real 90s gate), start a fresh play
   session, place/buy a few loose items an NPC should organize, ask an
   NPC to clean immediately. Confirm "nothing to clean" is reported.
   Wait without touching the items — confirm cleaning starts working on
   its own once ~90s have passed, and note the actual elapsed time.
2. With `NPCDebug.enabled` **on** (5s debug gate), repeat the same setup.
   Confirm cleaning becomes available in ~5s instead of ~90s. This is
   the confirming test — if idle-gating is really the whole story,
   cleaning should now feel immediate/responsive in every test.
3. Nudge/bump a tracked item (walk into it, or otherwise move it >0.3m)
   partway through its idle window — confirm its clock visibly restarts
   in the `[JobBoard] Cleaning scan:` debug print (`NPCDebug.enabled`)
   rather than becoming organizable early.
4. Re-run Part A's shelf test (place a Can Case via Cleaning) and
   specifically watch for ~10+ seconds after placement, not just 1-2 —
   confirm it now stays put with the Part A fix applied.
5. Two NPCs cleaning simultaneously: manufacture a shelf-full race if
   possible (small shelf, two NPCs both targeting items destined for the
   same shelf) — confirm the B1 fix means a failed placement doesn't
   permanently block the *other* NPC from that item afterward (check via
   F7/debug that its claim clears).

**Report back plain numbers** — actual seconds observed for cleaning to
become available in test 1, and whether test 2 makes it feel
immediate — before we decide whether B1+B2 fully closes #2/#3 or whether
`CLEANING_IDLE_MIN_SEC` itself needs to be tuned down for real
gameplay (that's Brannon's call, not something to change unilaterally).

### Known permanent gap (not a bug, just flagging)

No object anywhere in the project currently belongs to the
`"trash_receptacle"` group — `JobBoard._has_trash_receptacle()` will
always return `false` today, so trash-type cleaning (empty cans/bottles)
can never actually complete regardless of any of the above. This is
by design per the existing code comment ("nothing occupies this group
yet"), but worth knowing so it isn't mistaken for another cleaning bug
during testing — only shelf/organizing behavior can be verified until a
receptacle object exists.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist (renumber if needed to
follow the existing sequence):

```
66. Have an NPC deliver an item to a shelf via Cleaning — confirm it
    stays frozen and in place for at least 10-15 seconds afterward
    (previously it would pop back out and unfreeze ~1s after placement
    due to a stale is_held/_hold_point state — see
    CLEANING_SHELF_POPOUT_FIX_AND_INVESTIGATION.md).
67. With NPCDebug.enabled (5s debug idle-gate), confirm cleaning becomes
    available quickly instead of requiring a ~90s real-time wait; with
    it off, confirm the real 90s gate still applies unchanged.
68. Force a shelf-full race between two NPCs both cleaning toward the
    same shelf — confirm a failed placement doesn't leave the item
    permanently unavailable to the other NPC (claim leak fix).
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Shelf Pop-Out Fix + Cleaning Investigation (Aug 2026)

- Root-caused and fixed shelf pop-out: `Shelving.npc_try_place_item()`
  never cleared the delivered item's `is_held`/`_hold_point`, so
  `PickupableItem`'s own knockout logic treated it as still being
  carried and ejected it once the NPC walked away. Now mirrors the
  player placement path's existing clear.
- Fixed a claim leak in `CleaningActivity` where a failed shelf
  placement (destination filled mid-delivery) dropped the item without
  releasing its `NPCItemUser` claim, permanently blocking other NPCs
  from it.
- Added an `NPCDebug`-gated fast idle-timer override
  (`CLEANING_IDLE_MIN_SEC_DEBUG`, 5s) to `JobBoard.gd` for testing the
  90s cleaning idle-gate's role in the "nothing to clean" / sporadic
  cleaning reports without waiting it out live.
- Confirmed: no object in the project currently occupies the
  `trash_receptacle` group, so trash-type cleaning cannot complete yet —
  pre-existing/by-design, not a regression, but relevant to interpreting
  cleaning test results until a receptacle object exists.

Files touched: `scripts/world/furniture/Shelving.gd`,
`scripts/npc/NPCBrain.gd`, `scripts/npc/JobBoard.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
