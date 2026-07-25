# Handover — Fertilizer & Item-Charge Consolidation (Jul 2026)

## What changed this session
Implemented `FARMING_FERTILIZER_AND_CHARGES_PLAN` in full, one pass:

### New: Fertilizer item
- `scripts/world/items/FertilizerItem.gd` — new item, two tiers (Normal +12.5% growth bonus, Pro +25%).
- Targets one specific plant/cell in a `FarmingTray` (growing, not-yet-ready only). Already-fertilized plant is blocked with toast "This plant is already fertilized." (not replaced/stacked).
- Bonus applied as `* (1.0 + fertilizer_bonus)` multiplier in `FarmPlant`'s growth formula.
- Sold in the Farming shop's **Soil** submenu (not Seeds): $300 Normal / $400 Pro.

### FarmingTray.gd
- Added `has_open_fertilizable_cell()`, `has_already_fertilized_growing_cell()`, `fertilize_first_open_cell(tier)`.

### FarmPlant.gd
- Added `fertilizer_bonus` / `fertilizer_tier` fields, `is_fertilized()` / `apply_fertilizer(tier)`.
- Growth formula and header doc comment updated to reflect the bonus multiplier.

### FarmingTrayUI.gd
- `PLANT_BLOCK_H` bumped 108→126 to fit a new fertilized-status line drawn in `_draw_plant_block()`.

### Item charge consolidation (onto existing multi-charge convention — `InventoryHUD.gd` needed ZERO changes, its `_charges`/`_max_charges` fallback already renders the "x/y" badge)
- **BagOfSoilItem.gd**: now has 2 charges. `get_prompt_text()` shows `(%d/%d)`. `on_use()` decrements charges; Empty Bag only spawns/frees when charges actually hit 0 (previously dropped an empty bag on every single use — behavior change).
- **SeedItem.gd**: now has 4 charges, **one physical instance per purchase** (not 4 separate items). `get_prompt_text()`/`get_use_prompt()` show `(%d/%d)`. `on_use()` decrements charges and `queue_free()`s at 0 — no "empty packet" object exists.
- All 12 seed species lost the `"(x4)"` suffix in shop/submenu display names (the charge badge now communicates count).

### FarmingShopHelper.gd
- `SHOP_ITEM_INFO`: all 12 seed entries changed `count: 4→1`, names lost `(x4)`. Added entries 14/15 (Normal/Pro Fertilizer, Soil submenu).
- `spawn_purchased_item()` seed branch now spawns exactly 1 instance (loop removed). Added `"fertilizer"` match branch → `FertilizerItem.spawn_at()`.

### BuildModeHUD.gd
- `FARMING_SHOP_ITEMS["Soil"]` gained tile_id 14/15 (fertilizer entries). All 12 `["Seeds"]` entries renamed (dropped `(x4)`).

### Docs
- `docs/systems/farming/README.md` — new "Fertilizer & item-charge consolidation (Jul 2026)" section appended, same commit as code per doc-update discipline.

## Flagged but deliberately unchanged
- `shelf_stack_limit = 6` left unchanged on all three items (Bag of Soil, Seed, Fertilizer) — flagged per plan, not silently tuned. Revisit if shelf density feels off in playtest.

## Verification done
- `bash tools/godot_check.sh <headless Godot 4.6.3 binary>` → **PASS**, no script parse/compile/type errors across the whole repo.
- Not yet manually playtested in-editor (no compiler/runtime in sandbox — requires an in-editor pass from Brannon).

## Playtest checklist for Brannon
1. Pull `origin/main`.
2. Open Farming shop → Soil submenu → buy Normal and Pro Fertilizer ($300 / $400).
3. Apply fertilizer to a growing (not-yet-ready) plant in a tray — confirm status line appears in tray UI and growth speeds up.
4. Try applying fertilizer to an already-fertilized plant — confirm blocked with toast "This plant is already fertilized."
5. Check inventory HUD charge badges (x/y) show correctly on Bag of Soil, Seed, and Fertilizer slots.
6. Use Bag of Soil twice — confirm Empty Bag only drops after the 2nd use (charges hit 0), not after the 1st.
7. Buy a seed packet — confirm exactly 1 item spawns with 4 charges (not 4 separate items), and shop/submenu names no longer show "(x4)".

## Next up (not started)
- No specific next-feature commitments from this session; awaiting Brannon's playtest feedback and next request.
