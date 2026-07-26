# Handover — Polish Batch 1 + Structure Fixes + Half/Quarter Walls + HUD Fix (Jul 2026)

## What changed this session

### Polish Batch 1 (from audit items 1–5)
- **PickupableItem base class** — new `scripts/world/items/PickupableItem.gd` (~153 lines) extracted ~800 lines of duplicated scaffolding (pickup/drop/place/knockout/culling/hold-follow physics) from all 12 item scripts. All items now extend `PickupableItem` instead of the minimal `PickupItem.gd` (legacy, ~65 lines, kept for reference).
- **InventoryHUD type bug fix** — renamed `COLOR_CHARGE_FONT: float` → `CHARGE_FONT_SIZE: int` in `InventoryHUD.gd`; fixed `int(COLOR_CHARGE_FONT)` cast error.
- **SleepOverlay API fix** — added `PlayerStats.skip_time(hours)` public method; `SleepOverlay.gd` now calls it instead of mutating private `_elapsed`/`_seconds_per_game_hour`.
- **CanCase/WaterCase ejection fix** — added one-frame freeze (`freeze = true` + `call_deferred("_unfreeze_after_spawn")`) to ejected FoodCan/WaterBottle to prevent floor fall-through on spawn.
- **Water TEMP cleanup** — removed 4 debug `TEMP` print blocks from `WaterManager.gd`, `WaterPipeDrawMode.gd` (×2), `WaterPipeSegment.gd`.

### BunkerPregen wall height alignment
- **`BunkerPregen.gd`**: changed `PLACEMENT_Y: 1.0 → 2.0` to match `BuildModeController.PLACEMENT_Y` (2.0) and `WireGraphBuilder`/`WallPerimeterRegistry` (2.0). Pregen walls now sit at same height as player-placed walls/pillars.

### Half-Wall / Quarter-Wall (Structure → Build menu)
- New tile IDs: `TILE_HALF_WALL = 25`, `TILE_QUARTER_WALL = 26` in `BuildModeController.gd` + `BuildModeHUD.gd` ("Structure" category).
- Both reuse the MeshLibrary wall mesh (`TILE_WALL` = 1) scaled vertically:
  - Half-Wall: 0.5× height (1.5m), `HALF_WALL_PLACEMENT_Y = 1.0`, $30
  - Quarter-Wall: 0.25× height (0.75m), `QUARTER_WALL_PLACEMENT_Y = 0.25`, $15
- Scaling handled in `BuildModeController._spawn_placed_object()`, `GhostPreview._rebuild_ghost_mesh()`, `MoveDuplicateTool._spawn_move_ghost()` — origin shifted so bottom sits at Y=0.
- No new meshlib entries; pure visual variant via scale.

### Duplicate HUD fix
- **MainWorld.tscn** had 3 HUD instances (two extra `CanvasLayer` under GameCamera and root). Only the root `HUD` node (line 75) is referenced by `$HUD`. Removed the two duplicates. `hud.set_build_mode(true)` now correctly hides the single inventory bar.

## Files added/modified

### New
- `scripts/world/items/PickupableItem.gd`

### Modified
- `scripts/world/items/*.gd` (12 files) — extend `PickupableItem`, removed duplicated scaffolding
- `scripts/ui/inventory/InventoryHUD.gd` — `COLOR_CHARGE_FONT` → `CHARGE_FONT_SIZE: int`
- `scripts/player/PlayerStats.gd` — added `skip_time(hours)`
- `scripts/ui/menus/SleepOverlay.gd` — uses `player_stats.skip_time(8.0)`
- `scripts/world/items/CanCase.gd`, `WaterCase.gd` — ejection freeze
- `scripts/world/water/WaterManager.gd`, `WaterPipeDrawMode.gd` (×2), `WaterPipeSegment.gd` — TEMP prints removed
- `scripts/world/environment/BunkerPregen.gd` — `PLACEMENT_Y = 2.0`
- `scripts/world/build/BuildModeController.gd` — `PLACEMENT_Y = 2.0`, Half/Quarter wall constants, scaling logic, `HALF_WALL_PLACEMENT_Y`, `QUARTER_WALL_PLACEMENT_Y`
- `scripts/ui/build/BuildModeHUD.gd` — Structure category: Half-Wall, Quarter-Wall entries
- `scripts/ui/inventory/InventoryHUD.gd` — charge font size fix
- `scripts/world/build/GhostPreview.gd` — ghost scaling for half/quarter walls
- `scripts/world/build/MoveDuplicateTool.gd` — move ghost scaling for half/quarter walls
- `scenes/world/MainWorld.tscn` — removed 2 duplicate HUD CanvasLayers
- `scripts/world/build/BuildModeController.gd` — `PLACEMENT_Y` comment updated

## Verification done
- `bash tools/godot_check.sh <headless Godot 4.6.3 binary>` → **PASS**, no script parse/compile/type errors across the whole repo.
- Not yet manually playtested in-editor (no compiler/runtime in sandbox — requires an in-editor pass from Brannon).

## Playtest checklist for Brannon
1. Pull `origin/main`.
2. **Pickup items** — pick up/drop/place each of the 12 items; verify no regressions in physics, knockout, culling, hold-follow.
3. **Inventory HUD** — confirm charge badges render correctly (int font size, no cast errors).
4. **Sleep** — sleep 8h; confirm time advances correctly without mutating private PlayerStats fields.
5. **CanCase/WaterCase** — eject items; confirm they don't fall through floor on spawn.
6. **Pregen walls** — verify pregen walls/pillars align vertically with player-placed walls/pillars (same top height).
7. **Half-Wall / Quarter-Wall** — open Construct → Structure; buy/place both; confirm heights (1.5m / 0.75m), prices ($30 / $15), collision matches visual height.
8. **Build mode** — enter build mode; confirm inventory bar hides completely (no 4 empty boxes visible).

## Next up (not started)
- Polish audit items 6–23 (InteractPrompt jitter, Flashlight pause battery drain, FuelCan prompt, Water pipe labels, Farming tray UI alignment, Build ghost z-fighting, etc.)
- Await Brannon's playtest feedback and next request.

---

## Previous session (Fertilizer & Item-Charge Consolidation — Jul 2026)
Implemented `FARMING_FERTILIZER_AND_CHARGES_PLAN` in full:

- **FertilizerItem.gd** — two tiers (Normal +12.5%, Pro +25%); targets one growing plant per tray; blocks re-fertilizing with toast; sold in Farming shop Soil submenu ($300/$400).
- **BagOfSoilItem.gd** — 2 charges, Empty Bag drops only at 0 charges (was every use).
- **SeedItem.gd** — 4 charges, single instance per purchase; no empty packet; shop names lost "(x4)".
- **FarmingShopHelper.gd** / **BuildModeHUD.gd** — updated shop items and construct menu.
- **Docs** — `docs/systems/farming/README.md` updated.

**Flagged**: `shelf_stack_limit = 6` unchanged on Bag of Soil / Seed / Fertilizer.

**Playtest**: buy fertilizer, apply to growing plant, verify growth speedup + status line; verify blocked re-fertilize; check HUD charge badges; verify Bag of Soil drops Empty Bag only on 2nd use; verify single seed item with 4 charges.