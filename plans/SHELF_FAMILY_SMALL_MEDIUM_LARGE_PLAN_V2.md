# Feature Plan v2 — Shelf Family: Small Shelf (6) / Medium Shelf (rename, 10) / Large Shelf (15)

**Supersedes** `SHELF_FAMILY_SMALL_MEDIUM_LARGE_PLAN.md` (v1) — written against a stale clone. Re-verified against current `main`: `Shelving.gd` is now a **procedural mesh** (4 corner posts + shelf platforms + notch details, no GLB, no `_load_mesh()` rotation step — that whole concern is gone) at **5 tiers × 2 = 10 slots**, `display_order` is `[8,9,6,7,4,5,2,3,0,1]`, and the facing-arrow fix from the prior session is already in place (`ARROW_OVERRIDES[3] = [0.6, 180.0]`). None of v1's Edit-1-style model-rotation work applies anymore.

**Updated capacities per Brannon:** Small Shelf = 6, Medium Shelf (rename of current Shelving) = 10 (unchanged), Large Shelf = 15. Small is now genuinely smaller than Medium (6 < 10), so no flag needed this time.

**Approach (unchanged from v1's reasoning):** subclass, not file-copy. `Shelving.gd` stays the base class (file/class/group names unchanged); "Medium Shelf" is a display-facing rename via a new `display_name` export. Small and Large are ~15-line subclasses overriding `_init()` only. All storage/stack/NPC/StorageUI/eject logic inherited untouched.

**Tile IDs:** `TILE_SMALL_SHELF = 34`, `TILE_LARGE_SHELF = 35`. **Prices:** Small $45, Medium stays $75, Large $180 (override if you want different numbers).

---

## Part 1 — Generalize `scripts/world/furniture/Shelving.gd` (base class)

**1.1 New exports**, alongside the existing tunables (~line 30, after `slot_lift`):
```gdscript
@export var slots_per_tier: int  = 2        ## Columns of slots per tier (2 = classic left/right)
@export var display_name: String = "Medium Shelf"
```
Update the file header: base class for the shelf family (Small/Medium/Large); slot count = `shelf_y.size() * slots_per_tier`.

**1.2 Derive `slots` instead of the hardcoded 10-element literal.** Replace (~line 38):
```gdscript
var slots: Array = [[], [], [], [], [], [], [], [], [], []]
```
with:
```gdscript
var slots: Array = []   ## Sized in _ready(): shelf_y.size() * slots_per_tier empty stacks
```
and at the top of `_ready()`, before `_load_mesh()`:
```gdscript
	for i: int in shelf_y.size() * slots_per_tier:
		slots.append([])
```

**1.3 Generalize `_build_slot_markers()` (~line 142) for N columns, preserving the 2-column math BIT-FOR-BIT** — existing shelved items sit at these marker positions and must not move:
```gdscript
func _build_slot_markers() -> void:
	_slot_nodes.clear()
	## Right-side slots get an extra nudge away from the left wall.
	## slot_offset_x already separates left/right; right_extra shifts them slightly further right.
	const right_extra: float = 0.06
	for tier: int in shelf_y.size():
		for side: int in slots_per_tier:
			var x: float
			if slots_per_tier == 2:
				## Classic left/right — EXACT pre-existing math, do not alter
				var base_x: float = slot_offset_x * (1.0 if side == 1 else -1.0)
				x = base_x + (right_extra if side == 1 else 0.0)
			else:
				## N evenly spaced columns centered on the unit (Large Shelf: 3)
				x = (float(side) - float(slots_per_tier - 1) * 0.5) * 0.30
			var y: float = shelf_y[tier] + slot_lift
			var marker: Marker3D = Marker3D.new()
			marker.position = Vector3(x, y, 0.0)
			add_child(marker)
			_slot_nodes.append(marker)
```

**1.4 Dynamic `get_ui_config()` (~line 766).** Must reproduce the CURRENT 10-slot values exactly (title text aside) when `slots_per_tier == 2` and `shelf_y.size() == 5`:
```gdscript
func get_ui_config() -> Dictionary:
	var tiers: int = shelf_y.size()
	## visual position -> data slot. Data slots are bottom-up; the UI panel
	## reads top-to-bottom matching the physical shelf, so visual row 0
	## (top of panel) shows the TOP tier's data slots. Generalizes the
	## existing 10-slot [8,9,6,7,4,5,2,3,0,1] mapping to any tier/column count.
	var order: Array[int] = []
	for visual_row: int in tiers:
		var data_tier: int = tiers - 1 - visual_row
		for col: int in slots_per_tier:
			order.append(data_tier * slots_per_tier + col)
	return {
		"title": display_name.to_upper(),
		"slot_count": slots.size(),
		"grid_cols": slots_per_tier,
		"grid_rows": tiers,
		"display_order": order,
		"supports_stacking": true,
		"primary_button_icon": "carry",
		"primary_button_tooltip": "Carry",
		"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
		"primary_requires_empty_hands": true,
		"closes_on_action": true,
	}
```
Confirm this produces `[8,9,6,7,4,5,2,3,0,1]` for tiers=5/slots_per_tier=2 (data_tier 4→[8,9], 3→[6,7], 2→[4,5], 1→[2,3], 0→[0,1] — matches). No `row_labels` key existed in the current file — none added, matching current behavior exactly.

**1.5 Sweep for other slot-count literals.** Grep `Shelving.gd` for bare `10`, `5`, or `2` used as slot/tier assumptions outside the exports above (e.g. any eject loop, `_first_empty_slot`, NPC-facing helpers) and confirm they already use `slots.size()` / `shelf_y.size()` rather than literals; patch any found. (Prior read of the eject/retrieval functions showed `slots.size()`-based loops already — expected to be a no-op, but verify against current file, not this plan's memory of the old one.)

## Part 2 — Variant subclasses (new files)

**`scripts/world/furniture/SmallShelf.gd`:**
```gdscript
extends Shelving
class_name SmallShelf
## SmallShelf.gd — shelf-family variant: 6 slots as 3 tiers × 2 columns
## (vs. Medium's 5×2=10). Same procedural mesh style, stack limits, NPC
## behavior, and StorageUI contract inherited — only tier layout differs.

func _init() -> void:
	display_name = "Small Shelf"
	shelf_y       = [0.225, 0.675, 1.125]
	unit_h        = 1.6   ## proportional to 3 tiers vs Medium's 5-tier 2.5
```

**`scripts/world/furniture/LargeShelf.gd`:**
```gdscript
extends Shelving
class_name LargeShelf
## LargeShelf.gd — shelf-family variant: 15 slots as 5 tiers × 3 columns
## (vs. Medium's 5×2=10). Same tier heights and unit height as Medium;
## wider unit to fit 3 columns. Same stack limits, NPC behavior, and
## StorageUI contract inherited.

func _init() -> void:
	display_name   = "Large Shelf"
	slots_per_tier = 3
	unit_w         = 1.70   ## widened from Medium's 1.25 to fit 3 columns
```
(Large keeps Medium's `shelf_y`/`unit_h` — same 5-tier height, just wider.)

## Part 3 — Rename current unit to "Medium Shelf" (display-facing only)
1. `BuildModeHUD.gd` line 44: `"name": "Shelving"` → `"name": "Medium Shelf"` (price 75, tile_id 3 unchanged). Scoped-exception rule: this data-line edit only.
2. UI title now comes from 1.4's `display_name` ("MEDIUM SHELF") automatically — no other code change. Class/file/group names (`Shelving`, `"shelving"`) intentionally unchanged.

## Part 4 — Wiring for the two new tiles
**(a)** `BuildModeController.gd` constants (near `TILE_SHELVING: int = 3`, line ~41): `TILE_SMALL_SHELF: int = 34`, `TILE_LARGE_SHELF: int = 35`.
**(b)** `BuildModeHUD.gd` CATEGORIES, after the Medium Shelf line (scoped exception, two data lines):
```gdscript
		{ "tile_id": 34, "name": "Small Shelf", "price": 45  },
		{ "tile_id": 35, "name": "Large Shelf", "price": 180 },
```
**(c)** `spawn_structure()` (~line 1213, the `if tile_id == TILE_SHELVING:` branch): two new branches copied from it verbatim including the `_interaction_system`/`_storage_ui` injection block — only the script path (`SmallShelf.gd` / `LargeShelf.gd`) and tile check differ.
**(d)** `GhostModelBuilder.PROCEDURAL_PREVIEW_SOURCES`: `34:` → SmallShelf.gd, `35:` → LargeShelf.gd, `"is_script": true`.
**(e)** `GhostModelBuilder.ARROW_OVERRIDES`: `34: [0.6, 180.0]` and `35: [0.6, 180.0]` — same as the current Shelving entry (`3: [0.6, 180.0]`), since both variants use the same procedural-mesh facing.
**(f)** `GhostPreview.gd` Shelving fallback ghost branch: extend the tile check to all three shelf tiles, loading the matching subclass script for `build_ghost_mesh()` (inherited static — same shape unless overridden). Shared `_attach_ghost_direction_arrow(0.6, 180.0)` call.
**(g)** **Occupancy — both `TILE_SHELVING` sites in `BuildModeController.gd` (lines ~2844, ~2850).** Line 2844's tile-check gating the registry-only overlap path must accept all three shelf tiles; line 2850's registry filter `entry.get("tile_id", -1) != TILE_SHELVING` becomes a not-in-`[TILE_SHELVING, TILE_SMALL_SHELF, TILE_LARGE_SHELF]` check — shelf variants must see each other (and Medium) as occupying, not just same-tile matches.
**(h)** `_ghost_half_extents_for_tile()` (~line 2985, `TILE_SHELVING: return Vector2(0.48, 0.18)`): add `TILE_SMALL_SHELF` with the same Vector2 (narrower unit but v1/v2 don't change `unit_d`, so depth-based half-extent is unaffected); add `TILE_LARGE_SHELF: return Vector2(0.65, 0.18)` reflecting the wider `unit_w = 1.70` (half of 1.70 minus a small margin — confirm against `TILE_SHELVING`'s exact derivation, likely `unit_w * ~0.38` — match that ratio rather than hand-picking).

## Part 5 — Documentation (same commit)
1. `docs/systems/furniture-items/README.md` — Shelving section becomes "Shelf family": table of Small (6, 3×2)/Medium (10, 5×2)/Large (15, 5×3), tile IDs, prices; base-class architecture note (subclasses override `_init()` only — dimensions, `slots_per_tier`, `shelf_y`); procedural-mesh generation is inherited and parametric, so all three render correctly at their own dimensions (no floating-marker compromise this time, since geometry is procedural not a fixed GLB).
2. `docs/systems/build/README.md` — tile table rows 34/35; note the shelf occupancy carve-out (§4g) now covers all three shelf tiles.
3. `HANDOVER.md` — entry: "Shelf Family (Small/Medium/Large) — Aug 2026, v2 corrected for current 10-slot Shelving": rename, subclass approach, base generalizations (N-tier/N-column slots, marker math, dynamic UI config verified against the current `[8,9,6,7,4,5,2,3,0,1]` order), wiring, note that v1 of this plan was written against a stale clone and is superseded. Flag for the NPC thread: shelf-seeking code iterating the `"shelving"` group now also finds Small/Large — inherited APIs identical, no action expected.

## Part 6 — Verification (Brannon, in-editor)
1. **Rename:** Construct menu shows "Medium Shelf" at $75, 10 slots, unchanged 5×2 layout; its UI title reads MEDIUM SHELF; existing behavior (stacking, `[8,9,6,7,4,5,2,3,0,1]` display order, NPC restock) identical to before.
2. **Placement:** Small ($45) and Large ($180) appear with correct previews/ghosts/arrows (south-default, matching facing convention), procedurally-built posts/shelves scaled to their own dimensions (Small shorter, Large wider); green/red overlap correct; two shelf variants placed adjacent detect each other as occupied; deconstruct refunds correctly and ejects items.
3. **Small Shelf:** 6 slots, UI grid 2×3, F-place and E-open work, stack limits enforced.
4. **Large Shelf:** 15 slots, UI grid 3×5, top visual row = top tier; F fills first empty data slot (bottom-left first); carry/⊕ work from all 15 slots.
5. **Regression sweep:** Basket, End Table, Dresser, existing Medium Shelf UIs all unchanged; shelf E-fairness rule unchanged; NPC shelf jobs unchanged on all three variants.
