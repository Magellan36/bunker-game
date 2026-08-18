# Plan — Shelving UI Update for 5-Tier / 10-Slot Rewrite

## Summary
The shelf model/backend was already rewritten (`shelf_y` now has 5 entries,
`slots` array is length 10, slot markers build correctly) but
`get_ui_config()` was never updated to match, and — more importantly —
`_find_slot_for()` still hardcodes the OLD 6-slot bound in two places, so
**slots 6–9 (the two new top tiers) are currently unreachable via F-place**
even though they physically exist. Both are fixed here. Both files
(`Shelving.gd`, `StorageUI` doc references) are already in this thread's
scope — no hand-off needed.

Also answering the standing question: the visible "item flies from hand to
shelf" animation is **already implemented** in `Shelving._place_item_in_slot()`
(a 0.22s Tween of position+rotation, generic over slot index) — it needs
no changes for the 10-slot layout and no other agent needs to touch it.

## Files modified
- `scripts/world/furniture/Shelving.gd` — bugfix + `get_ui_config()` update.
- `docs/systems/ui/README.md` — stale 6-slot pool-sizing example corrected.

---

## Part 1 — Bugfix: `_find_slot_for()`'s stale 6-slot bound

**old_str:**
```
func _find_slot_for(item: RigidBody3D) -> int:
	var limit: int  = _get_stack_limit(item)
	var itype: String = _get_item_type(item)

	# Pass 1: partial stack of same type
	for i: int in 6:
		var stack: Array = slots[i]
		if stack.is_empty():
			continue
		if stack.size() >= limit:
			continue
		# Check type match
		if _get_item_type(stack[0]) == itype:
			return i

	# Pass 2: first empty slot
	for i: int in 6:
		if slots[i].is_empty():
			return i

	return -1   ## No room
```
**new_str:**
```
func _find_slot_for(item: RigidBody3D) -> int:
	var limit: int  = _get_stack_limit(item)
	var itype: String = _get_item_type(item)

	# Pass 1: partial stack of same type
	for i: int in slots.size():
		var stack: Array = slots[i]
		if stack.is_empty():
			continue
		if stack.size() >= limit:
			continue
		# Check type match
		if _get_item_type(stack[0]) == itype:
			return i

	# Pass 2: first empty slot
	for i: int in slots.size():
		if slots[i].is_empty():
			return i

	return -1   ## No room
```
(Was hardcoded `6` from the old 3-tier layout — every other slot-bound
check in this file already correctly uses `slots.size()`, this was the one
spot missed by the rewrite. Without this fix, tiers 4/5 exist, show up in
the UI once Part 2 lands, and are visible/retrievable — but F-place can
never put anything in them.)

---

## Part 2 — `get_ui_config()` update: 6→10 slots, 3→5 rows

**old_str:**
```
func get_ui_config() -> Dictionary:
	return {
		"title": "SHELF CONTENTS",
		"slot_count": 6,
		"grid_cols": 2,
		"grid_rows": 3,
		"display_order": [4, 5, 2, 3, 0, 1],   ## visual position -> data slot (top row shows data slots 4/5, etc.)
		"supports_stacking": true,
		"primary_button_icon": "carry",
		"primary_button_tooltip": "Carry",
		"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
		"primary_requires_empty_hands": true,
		"closes_on_action": true,
	}
```
**new_str:**
```
func get_ui_config() -> Dictionary:
	return {
		"title": "SHELF CONTENTS",
		"slot_count": 10,
		"grid_cols": 2,
		"grid_rows": 5,
		## visual position -> data slot. Data slots are bottom-up (0/1 =
		## tier 0/bottom shelf, ... 8/9 = tier 4/top shelf, per this file's
		## header comment) but the UI panel should read top-to-bottom same
		## as the physical shelf, so row 0 (top of panel) shows the top
		## tier's data slots (8/9) and row 4 (bottom of panel) shows the
		## bottom tier's (0/1) — same top-shelf-at-top convention the old
		## 6-slot [4,5,2,3,0,1] mapping used, extended to 5 tiers.
		"display_order": [8, 9, 6, 7, 4, 5, 2, 3, 0, 1],
		"supports_stacking": true,
		"primary_button_icon": "carry",
		"primary_button_tooltip": "Carry",
		"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
		"primary_requires_empty_hands": true,
		"closes_on_action": true,
	}
```

Panel sizing: confirmed no change needed to `StorageUI.gd` — at the
current preview/button constants this renders at 266×814px (vs the old
6-slot panel's 266×522px), and you've confirmed that's fine as-is.

---

## Verification checklist
1. Open a shelf's `E` menu — 5 rows × 2 columns render, top row = top
   physical tier, bottom row = bottom physical tier, matching the shelf
   you're looking at in the world.
2. `F`-place items near a shelf until all 10 slots fill — confirm items
   actually land in tiers 4 and 5 (previously impossible), and that
   partial-stack matching (pass 1) also reaches those tiers.
3. Fill 8 slots, leave only a top-tier slot empty, `F`-place one more item
   — confirm it lands in the empty top-tier slot, not misreported as
   "Shelf is full".
4. Retrieve (`Carry`/`Add to inventory`) from a top-tier slot via the `E`
   menu — confirm correct item, correct slot clears, no display_order
   mismatch.
5. Confirm the existing hand-to-shelf flight animation
   (`_place_item_in_slot()`) still looks correct for all 5 tiers,
   especially the top one (longer flight distance, same 0.22s duration).

## Part 3 — Documentation fix: stale "6-slot shelf" pool-sizing example

`docs/systems/ui/README.md` still uses the old slot count as its worked
example of `StorageUI`'s growing slot-visual pool — this is now factually
wrong (a shelf is 10 slots, bigger than a 12-slot basket, not smaller), so
fix it rather than defer it:

**old_str:**
```
`StorageUI.gd` keeps ONE dynamic slot-visual pool that only grows (never
rebuilds) — opening a 12-slot basket after a 6-slot shelf grows the pool
to 12; reopening the shelf afterward just hides the extra 6, nothing gets
destroyed. This is what makes adding a future storage type (lockable
```
**new_str:**
```
`StorageUI.gd` keeps ONE dynamic slot-visual pool that only grows (never
rebuilds) — opening a 12-slot basket after a 10-slot shelf grows the pool
to 12; reopening the shelf afterward just hides the extra 2, nothing gets
destroyed. This is what makes adding a future storage type (lockable
```

Repo-wide grep found no other doc references to Shelving's old 6-slot/
3-tier count with enough surrounding specificity to need a mechanical
fix (the rest are either already generic or already correct at 5
tiers — see the file's own header comment, already accurate).
