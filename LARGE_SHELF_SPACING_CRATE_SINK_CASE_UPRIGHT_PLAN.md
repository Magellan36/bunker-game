# Fix Plan — Large Shelf Column Spacing, Crate Sink Bug, Case Upright + Stack Limits

Three independent issues, all in `scripts/world/furniture/Shelving.gd` plus two item files.

---

## Part 1 — Large Shelf Column Overlap

**Root cause.** `_build_slot_markers()`'s N-column branch hardcodes column spacing at `0.30`:
```gdscript
x = (float(side) - float(slots_per_tier - 1) * 0.5) * 0.30
```
With `slots_per_tier = 3`, adjacent column centers are 0.30 apart. TestCrate (the largest item, confirmed W = 0.54 from `TestCrate.gd`) is wider than that spacing on its own — each crate's ±0.27 half-width overlaps its neighbor's by **0.24 m**, exactly matching "overlapping tremendously, pulling towards the center."

**Fix — generalize the constant, tune it on Large Shelf specifically.**

**1.1** `Shelving.gd` — add a new export alongside `slot_offset_x`/`slot_lift` (~line 38):
```gdscript
@export var multi_col_spacing: float = 0.30   ## Column spacing for the N-column (slots_per_tier != 2) layout path only
```
Then in `_build_slot_markers()`, replace the hardcoded `0.30`:
```gdscript
				x = (float(side) - float(slots_per_tier - 1) * 0.5) * multi_col_spacing
```
Base default stays 0.30 (harmless — no other variant currently uses the N-column path besides Large).

**1.2** `scripts/world/furniture/LargeShelf.gd` `_init()` — add:
```gdscript
	multi_col_spacing = 0.62   ## 0.54 (TestCrate width, the widest item) + 0.08 clearance — snug, non-overlapping
	unit_w            = 2.00   ## was 1.70 — widened so 3 crates at 0.62 spacing (edges at ±0.89) sit inside
	                            ## the frame with margin (unit_w/2 = 1.00, leaving 0.11 clearance each side)
```
Replace the existing `unit_w = 1.70` line rather than adding a duplicate.

**Math check (for the agent to confirm, not to re-derive):** columns at x = −0.62, 0, +0.62. Crate half-width 0.27 → left crate spans [−0.89, −0.35], center spans [−0.27, 0.27], right spans [0.35, 0.89] — zero overlap, 0.08 gap between neighbors. Frame half-width 1.00 → 0.11 clearance past the outermost crate edge on each side.

## Part 2 — Crate Sinking Below the Shelf Platform

**Root cause, confirmed against `TestCrate._build_placeholder_mesh()`:** the crate's own mesh is built with a **centered pivot** — its bottom plate sits at `y = -H*0.5 + T*0.5` relative to the item's origin (H=0.48, T=0.018 → bottom at **-0.231**). So placing the item's origin AT the slot marker puts almost a quarter-meter of crate below that point.

`_place_item_in_slot()`'s `extra_lift` logic (~line 471) only special-cases stack-limit 4 ("cases…lift 0.06") and 6 ("bottles/cans…lift 0.05") — crates fall through with **`extra_lift = 0.0`**, and the comment there ("Crates: slot_lift in `_build_slot_markers` already handles this") is incorrect: `slot_lift = 0.075` is nowhere near enough to compensate for a 0.231-below-origin pivot. This is the sinking bug, confirmed as a placement-code issue, not a shelf-geometry issue — the shelf and platform themselves are unaffected.

**Fix.** In `_place_item_in_slot()`, add a crate-specific branch to the `extra_lift` logic (~line 471-476):
```gdscript
	var extra_lift: float = 0.0
	if _get_item_type(item) == "test_crate":
		## Aug 2026 — TestCrate's mesh pivot is centered (bottom plate sits at
		## -H*0.5+T*0.5 = -0.231 below the item's own origin; see
		## TestCrate._build_placeholder_mesh()). Without this lift the crate's
		## origin lands at the marker itself and ~0.23m of the model sinks
		## through the shelf platform below it — this is the reported bug.
		## 0.18 = platform_top_offset(0.009) + half_crate_height(0.24) -
		## slot_lift(0.075), rounded down ~0.006 for a hair of visible
		## clearance instead of exact flush contact (avoids z-fighting).
		extra_lift = 0.18
	elif _get_stack_limit(item) == 4 and iname.contains("case"):
		extra_lift = 0.06   ## Cases laid flat — lift centre above shelf board
	elif _get_stack_limit(item) == 6:
		extra_lift = 0.05   ## Bottles/cans — minor lift so base doesn't clip
```
Use `_get_item_type(item) == "test_crate"` (the existing type-key helper, matching `TestCrate.gd`'s `shelf_item_type = "test_crate"`) rather than name/limit sniffing — more precise and won't accidentally catch a future limit-1 item.

**Note for the agent:** this file has an existing `if _get_stack_limit(item) == 4 and iname.contains("case"):` line directly above — restructure the three conditions into one `if / elif / elif` chain as shown rather than three separate `if`s, since only one should ever apply per item.

## Part 3 — CanCase / WaterCase: Stand Upright, New Stack Limits

**3.1 Rotation — stand upright.** `_stack_rotation()` currently gates the flattening rotation on `limit == 4 and iname.contains("case")` (~line 388-390):
```gdscript
	if limit == 4 and iname.contains("case"):
		return Vector3(-90.0, 90.0, 0.0)
```
Since the limits are changing (CanCase → 2, WaterCase → 1), this can no longer key off `limit == 4`. Replace with a type-based check that keeps the Y=90 label-facing convention but drops the -90° X tip that was laying them flat — literally the "rotate 90 degrees back to upright" the request describes:
```gdscript
	var itype: String = _get_item_type(item)
	if itype == "can_case" or itype == "water_case":
		return Vector3(0.0, 90.0, 0.0)   ## Aug 2026 — stand upright (was -90° X, laid flat); Y=90 keeps label facing the player, matching the existing shelf-facing convention
```

**3.2 Offset — CanCase vertical 2-stack.** `_stack_offset()`'s case branch (~line 361-368) currently lays out a 2×2 flat grid using `limit == 4`. Replace with a type-keyed vertical stack for CanCase only (WaterCase's new limit of 1 needs no offset — it already falls through to the final `Vector3.ZERO` fallback, same as crates):
```gdscript
	## ── Can Case: limit=2, stacked vertically (one on top of the other) ──────
	if _get_item_type(item) == "can_case":
		## CASE_H_UPRIGHT is a first-pass estimate (CanCase is a .tscn scene,
		## not procedural, so its real AABB isn't visible from script). Verify
		## in-editor: if the top case floats above or clips into the bottom
		## one, adjust ONLY this constant.
		var oy: float = float(idx) * (CASE_H_UPRIGHT + CASE_GAP_Y)
		return Vector3(0.0, oy, 0.0)
```
Add the new constant near the existing case constants (~line 344-347) and remove the now-unused `CASE_W` / `CASE_H_LAY` / `CASE_GAP_X` (nothing else in the file references them once the 2×2 flat branch is gone — confirm with a grep before deleting):
```gdscript
const CASE_H_UPRIGHT: float = 0.34   ## Provisional standing height of one case, top-to-bottom. Tune in-editor per the note above.
const CASE_GAP_Y: float     = 0.004  ## Small gap between the two stacked cases (kept from the old constant)
```

**3.3 Sink-check flag for upright cases.** Part 2 found TestCrate sinks because of a centered mesh pivot. CanCase/WaterCase are also `.tscn`-based models and MAY share the same centered-pivot convention — if so, standing them upright (3.1) will very likely expose the identical sinking symptom, just not yet measurable from script. **Required verification step, not optional:** after implementing 3.1-3.2, visually check both cases in-editor exactly like the crate check in Part 2's checklist. If either sinks through its shelf platform, apply the same fix pattern as Part 2 — add a `_get_item_type(item) == "can_case"` / `"water_case"` branch to the `extra_lift` chain with a value derived the same way (half the model's real standing height, measured in-editor, plus the 0.009 platform-top offset, minus the 0.075 slot_lift already applied).

**3.4** `scripts/world/items/CanCase.gd` — change (~line 15-16):
```gdscript
## Shelf stacking — 4 cases lay flat per slot (2×2 grid)
var shelf_stack_limit: int   = 4
```
to:
```gdscript
## Shelf stacking — 2 cases stack vertically per slot (Aug 2026: was 4 lying
## flat in a 2×2 grid; now stands upright, one case on top of another)
var shelf_stack_limit: int   = 2
```

**3.5** `scripts/world/items/WaterCase.gd` — change (~line 14-15):
```gdscript
## Shelf stacking — 4 cases lay flat per slot (2×2 grid)
var shelf_stack_limit: int   = 4
```
to:
```gdscript
## Shelf stacking — 1 case per slot (Aug 2026: was 4 lying flat; now stands
## upright and the model is too large for a second to fit in the same slot)
var shelf_stack_limit: int   = 1
```

## Out of scope
- Small Shelf, End Table/Dresser, Basket — none affected by any change here.
- `unit_d` (shelf depth) — already fixed for the crate-fit pass; untouched here.
- Bottles/cans (`limit == 6` branch) — untouched, not part of this request.

## Documentation Updates (same commit)
1. `docs/systems/furniture-items/README.md` — Shelf family section: Large Shelf's column spacing (0.62) and widened `unit_w` (2.00) with the fit-math; CanCase/WaterCase now stand upright with new stack limits (2 / 1); note the TestCrate/case sinking root cause (centered mesh pivots vs. marker-based placement) as a pattern to watch for with any future item added to shelf stacking.
2. `HANDOVER.md` — entry: "Large Shelf Spacing + Crate Sink Fix + Case Upright/Restack — Aug 2026": all three root causes and fixes; explicitly flag 3.3's sink-check as a required in-editor verification step, not assumed-done.

## Verification Checklist (Brannon, in-editor)
1. **Large Shelf columns:** place 3 Test Crates across one tier of a Large Shelf — snug side-by-side, no visible overlap, no z-fighting, small even gaps between them; crates don't poke past the shelf's outer frame/posts.
2. **Crate sinking:** place a Test Crate on any tier of any shelf size — its bottom now rests visibly ON the platform surface, not clipped through it; repeat on the shelf's bottom tier and top tier.
3. **Case orientation:** place a Can Case and a Water Case on a shelf — both stand upright ("sitting like normal"), not lying on their side; label/front orientation faces the same way as other placed items.
4. **Can Case stacking:** place 2 Can Cases in the same slot — second one stacks visibly on top of the first, no clipping/floating gap; a 3rd Can Case attempt is rejected (slot full at 2).
5. **Water Case limit:** place 1 Water Case in a slot — a 2nd attempt in the same slot is rejected (full at 1); case is not sinking through the platform (per 3.3's required check).
6. **Regression:** bottle/can (limit-6) placement unchanged; retrieval (Carry/⊕) still returns cases and crates correctly from Shelving/Small/Medium/Large; StorageUI slot display unaffected by any of these changes (only physical placement math changed, not slot data or grid layout).
