# Cleaning: Fix Frame-Stall on No-Storage Levels (Aug 2026)

**Files:** `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`,
`docs/systems/npc/README.md`, `HANDOVER.md`.

**Re-clone the repo fresh before starting.** Verify both anchors below
against the live file before editing.

---

## Root cause (confirmed against live code and your debug log)

`CleaningActivity._pick_next_target()`'s retry loop calls
`npc.find_cleaning_target(_skipped_ids)` fresh on every iteration.
`find_cleaning_target()` builds a distance-sorted candidate list and runs
a physics raycast (`_has_clear_approach()`) against candidates while
picking one. The loop already tracks `_no_storage_categories` (light/
heavy already confirmed hopeless this session) for its log message, but
never actually uses that to stop re-considering items from an
already-hopeless category — it re-evaluates every single remaining item
from scratch, every time, including a full raycast-driven selection
pass and a full destination tree-scan, even when we already know for a
fact that category can't succeed.

In your reported scenario — 32 loose items, zero shelving anywhere —
this means one `_pick_next_target()` call (which runs synchronously,
start to finish, in a single frame, since it's a plain `while true` loop
with no yield) does up to 32 full candidate-scans-with-raycasts back to
back. That's the stall: a genuine CPU spike on the main thread, which is
why it presents as "1fps snapping" for a burst and then smooths out —
it's synchronized with each Cleaning session attempt (which, since
nothing can ever be stored, immediately ends and restarts on the next
think-cycle, repeating the burst).

This is a real interaction bug between two earlier, independently-tested
passes (destination-first skip logic + reachability raycasting) — each
was correctness-tested on its own, but the combination's *cost* on a
level with literally zero storage anywhere wasn't performance-tested.

---

## Fix

**File:** `scripts/npc/NPC.gd`

**Anchor:** the entire existing `find_cleaning_target()`:

```gdscript
func find_cleaning_target(exclude_ids: Dictionary = {}) -> Dictionary:
	var candidates: Array = []
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()) or _cleaning_blacklist.has(item.get_instance_id()):
			continue
		candidates.append({"item": item, "is_trash": true,
			"d": NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)})
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()) or _cleaning_blacklist.has(item.get_instance_id()):
			continue
		candidates.append({"item": item, "is_trash": false,
			"d": NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return a["d"] < b["d"])

	var fallback: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if _has_clear_approach(c["item"]):
			return {"item": c["item"], "is_trash": c["is_trash"]}
	return {"item": fallback["item"], "is_trash": fallback["is_trash"]}
```

Replace with:

```gdscript
## Aug 2026 — new `exclude_categories` param (light/heavy): skips
## organizable candidates in an already-confirmed-hopeless category
## BEFORE they're ever added to the candidate list, so they never get
## raycasted (_has_clear_approach()) or re-selected at all. Without this,
## CleaningActivity's retry loop was re-evaluating every remaining item
## from scratch on every failed attempt — on a level with zero storage
## anywhere, that meant up to N full raycast-driven candidate scans
## synchronously in one frame (N = organizable item count), which is a
## real, measurable frame stall, not a false alarm — root-caused from a
## live debug capture, not a guess.
func find_cleaning_target(exclude_ids: Dictionary = {}, exclude_categories: Dictionary = {}) -> Dictionary:
	var candidates: Array = []
	for item: Node in JobBoard.get_trash_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()) or _cleaning_blacklist.has(item.get_instance_id()):
			continue
		candidates.append({"item": item, "is_trash": true,
			"d": NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)})
	for item: Node in JobBoard.get_organizable_items():
		if not is_instance_valid(item) or NPCItemUser.is_claimed_by_other(item, self):
			continue
		if exclude_ids.has(item.get_instance_id()) or _cleaning_blacklist.has(item.get_instance_id()):
			continue
		if not exclude_categories.is_empty() and exclude_categories.has(_classify_organizable_item(item)):
			continue
		candidates.append({"item": item, "is_trash": false,
			"d": NPCItemUser.flat_distance(global_position, (item as Node3D).global_position)})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return a["d"] < b["d"])

	var fallback: Dictionary = candidates[0]
	for c: Dictionary in candidates:
		if _has_clear_approach(c["item"]):
			return {"item": c["item"], "is_trash": c["is_trash"]}
	return {"item": fallback["item"], "is_trash": fallback["is_trash"]}
```

**File:** `scripts/npc/NPCBrain.gd`

**Anchor:** inside `CleaningActivity._pick_next_target()`'s retry loop:

```gdscript
			while true:
				var result: Dictionary = npc.find_cleaning_target(_skipped_ids)
```

Replace with:

```gdscript
			while true:
				var result: Dictionary = npc.find_cleaning_target(_skipped_ids, _no_storage_categories)
```

Stop and report on anchor mismatch — no improvisation.

### Why this fully resolves it, not just reduces it

Walk through your exact repro with the fix applied: NPC picks the
nearest item (say a heavy Crate) → no destination → "heavy" marked
hopeless. Next `find_cleaning_target()` call now excludes every heavy
item from the candidate list entirely — picks the nearest remaining
(light) item → no destination → "light" marked hopeless too. The THIRD
call now excludes both categories — with no trash existing either, the
candidate list is empty immediately, and the session ends. That's 2
evaluated items instead of 32, and — critically — it's bounded by the
number of distinct categories (2: light/heavy), not by how much clutter
happens to be in the level. A future level with 200 items and no
storage will still resolve in 2-3 evaluations, not 200.

---

## Testing

1. Reproduce your exact scenario — a level with loose clutter and zero
   shelving/light storage anywhere — and watch the console with debug
   logging on. Confirm the "no storage for category" message now appears
   at most once per category per session (not once per item), and
   confirm the session ends within a handful of log lines instead of
   dozens.
2. Watch NPC movement during this — confirm the stutter/snapping is
   gone; movement should stay smooth even while a Cleaning session
   starts, fails immediately, and restarts on the next think-cycle.
3. Confirm normal Cleaning (storage present, most items succeed) is
   completely unaffected — this only changes behavior once a category
   has actually been confirmed hopeless.
4. Confirm the earlier per-item skip behavior (`_skipped_ids`, for
   items whose SPECIFIC destination is full/unavailable while other
   items of the same category still have somewhere to go) is unchanged
   — this fix only short-circuits at the category level, never at the
   individual-item level beyond what already existed.
5. With two NPCs cleaning simultaneously on a no-storage level (like
   your log), confirm neither produces a stall burst anymore.

---

## Documentation updates (apply in the same pass)

### `docs/systems/npc/README.md`

Add to the end of the verification checklist:

```
96. On a level with clutter but zero shelving/light storage anywhere,
    watch NPC movement while Cleaning sessions repeatedly start and
    immediately end — confirm no frame stall/snapping, and confirm the
    console shows at most one "no storage for category" line per
    category per session, not one per item.
```

### `HANDOVER.md`

Add a new dated entry near the top of the relevant recent section:

```
## NPC: Fixed Cleaning Frame-Stall on No-Storage Levels (Aug 2026)

- Root-caused a real performance bug from a live debug capture:
  CleaningActivity._pick_next_target()'s retry loop re-evaluated every
  remaining organizable item from scratch on every failed attempt
  (including a fresh raycast-driven candidate search per item), even
  after a category was already confirmed hopeless this session. On a
  level with clutter but zero storage anywhere, this meant a
  synchronous burst of up to N full candidate scans in one frame,
  presenting as "1fps snapping" every time a Cleaning session started.
- find_cleaning_target() now takes an exclude_categories param
  (NPC.gd) — CleaningActivity passes its own _no_storage_categories in,
  so a confirmed-hopeless category's items are filtered out before ever
  being raycasted or re-selected. Bounded by category count (2), not
  item count, regardless of clutter volume.

Files touched: `scripts/npc/NPC.gd`, `scripts/npc/NPCBrain.gd`.
```

Files: `docs/systems/npc/README.md`, `HANDOVER.md`.
