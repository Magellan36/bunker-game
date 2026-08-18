# Fix Plan — Medium Shelf Dimensions: Fit Test Crate, Lower Bottom Shelf

## Investigation

`TestCrate.gd` (`_build_placeholder_mesh()`, lines 53-56) is the largest carriable item in the game: **W = 0.54, H = 0.48, D = 0.73**.

Checked against current `Shelving.gd` (base class, also used by Large Shelf — Large doesn't override `shelf_y`/`unit_d`):
- `unit_h = 2.5`, `shelf_y = [0.225, 0.675, 1.125, 1.575, 2.025]` → **tier spacing = 0.45**. Shelf platforms are 0.018 thick, so interior clear height between tiers ≈ 0.45 − 0.018 = **0.432** — narrower than the crate's 0.48 height. Confirms the reported bug exactly: the crate cannot visibly fit between shelves.
- `unit_d = 0.625` — **also narrower than the crate's own depth (0.73)**. This is a second, independent fit problem beyond what was reported: even with taller tier spacing, the crate is deeper than the entire shelf unit and would clip through the front/back. Flagging and fixing this alongside the requested height change, since "fit this object on all of its shelves" isn't satisfied by a height-only fix.
- Bottom tier at `y = 0.225` — matches the "too high off the floor" report.

**Small Shelf** (`SmallShelf.gd`) hardcodes its own `shelf_y = [0.225, 0.675, 1.125]` and `unit_h = 1.6` — same 0.45 spacing, same undersized-for-crate problem. Brannon's request named Medium specifically; Small isn't mentioned. Included as an optional Part 2 so the two shelf sizes stay visually/functionally consistent — flag for approval rather than assuming.

## Part 1 — `scripts/world/furniture/Shelving.gd` (base class — fixes Medium AND Large, since Large inherits these values)

**1.1 Tier spacing + bottom height.** Replace (~line 36):
```gdscript
@export var shelf_y: Array[float] = [0.225, 0.675, 1.125, 1.575, 2.025]
```
with:
```gdscript
## Aug 2026 — widened from 0.45 to 0.60 spacing (interior clear height
## 0.432 -> 0.582) so TestCrate (H=0.48, the largest carriable item) fits
## with clearance on every tier. Bottom tier dropped from 0.225 to 0.12,
## closer to the floor per design feedback.
@export var shelf_y: Array[float] = [0.12, 0.72, 1.32, 1.92, 2.52]
```

**1.2 Unit depth.** Replace (~line 34):
```gdscript
@export var unit_d: float = 0.625
```
with:
```gdscript
## Aug 2026 — widened from 0.625 to 0.85 so TestCrate (D=0.73, the deepest
## carriable item) fits within the shelf's own depth instead of clipping
## through the front/back — found during the tier-spacing fix above.
@export var unit_d: float = 0.85
```

**1.3 Unit height** (raise to keep the taller/wider tier stack and top-tier item proportioned inside the frame — posts are derived from `unit_h`, so this must grow with `shelf_y`'s new top value). Replace (~line 33):
```gdscript
@export var unit_h: float = 2.5
```
with:
```gdscript
## Aug 2026 — raised from 2.5 to 3.55 alongside the shelf_y spacing
## increase, so the posts (derived below as unit_h - 0.2375) still extend
## comfortably above the new top tier (2.52) with headroom for a
## crate-height item, matching the previous proportions.
@export var unit_h: float = 3.55
```

**No other changes.** `slot_offset_x`, `slot_lift`, `unit_w`, post/notch/platform generation code, collision (`_build_collision()` already reads `unit_w/unit_h/unit_d` live, so it auto-adjusts), and `_build_slot_markers()` (already derives Y positions live from `shelf_y`) all pick up the new dimensions automatically — nothing there needs editing.

## Part 2 — OPTIONAL, confirm before implementing: `scripts/world/furniture/SmallShelf.gd`
Same undersized-spacing problem exists on Small Shelf's own hardcoded 3-tier values. If you want Small brought in line:
```gdscript
func _init() -> void:
	display_name = "Small Shelf"
	shelf_y       = [0.12, 0.72, 1.32]   ## was [0.225, 0.675, 1.125] — same 0.60 spacing/lowered-floor fix as Medium
	unit_h        = 2.35                  ## was 1.6 — proportioned the same way as Medium's unit_h bump
```
(`unit_d` is inherited from the base class fix in Part 1.2 automatically — Small already gets the depth fix with no override needed.) **Skip this part if you'd rather Small stay small/tight and only fits smaller items — say the word either way.**

## Out of scope
- `unit_w` / `slot_offset_x` (left-right fit) — not reported as broken, not touched.
- `LargeShelf.gd` — takes no action, inherits Part 1's fixes automatically (doesn't override `shelf_y`/`unit_d`/`unit_h`).
- Slot marker Y math, collision box derivation — both already live-derived from the changed exports, confirmed no hardcoded literals to chase.
- Stack limits / `shelf_stack_limit` on any item — unrelated to physical fit.

## Documentation Updates (same commit)
1. `docs/systems/furniture-items/README.md` — Shelf family section: update Medium Shelf's dimensions (spacing 0.60, bottom tier 0.12, depth 0.85, height 3.55) and note the crate-fit rationale; note Large inherits it; note Small's status per whichever way Part 2 is resolved.
2. `HANDOVER.md` — entry: "Medium Shelf Resize for Test Crate Fit — Aug 2026": symptom (crate too large to fit visually, bottom shelf too high), root causes (tier spacing narrower than crate height; ALSO shelf depth narrower than crate depth, found during investigation), new dimensions, Large inherits automatically, Small's resolution.

## Verification Checklist (Brannon, in-editor)
1. **Crate fits, all 5 tiers:** Place a Medium Shelf, F-store (or E → simulate) a Test Crate into each of the 5 tiers in turn — model doesn't clip the shelf above/below it, and doesn't poke out the front/back of the unit.
2. **Bottom shelf height:** Visually confirm the bottom tier sits noticeably closer to the floor than before.
3. **Large Shelf:** Since it inherits the base class, repeat check 1 on a Large Shelf — same fit fix should apply automatically at its 3-column width.
4. **Small Shelf:** If Part 2 was implemented, repeat check 1 on Small; if not, confirm Small's current behavior (crate still doesn't fit) is the accepted/expected state for now.
5. **Regression:** existing smaller items (FoodCan, WaterBottle, cases) still look correctly positioned on the taller/deeper shelves — nothing floats or sinks oddly at the new slot marker heights. Overlap/occupancy footprint unaffected (unit_w unchanged, and occupancy uses footprint not depth/height). StorageUI still opens/lists/retrieves correctly on all three shelf types.
