# Handover — Farming Fixes Round 2 + B5 Tray Fixes + Part A/B/C/D/E (Jul 2026)

## What changed this session

### Part A Bug Fixes (from Farming Fixes Round 2 plan)

**A1 — Light floor + XZ radius**
- `FarmPlant.gd`: `LIGHT_FLOOR_SPEED = 0.1` minimum growth speed so plants never fully stall in darkness
- `GrowLight.gd`: `LIGHT_MATCH_RADIUS = 0.25` with XZ-only distance check (flat, ignores height)

**A2 — Farming tray prompt position**
- `FarmingTray.gd`: Added `get_prompt_world_pos()` — prompt sits at basin height (0.85) centered for single tray, over used side for double tray
- `InteractionSystem.gd`: Generic `has_method("get_prompt_world_pos")` check (no group restriction)

**A4 — Bounds check corner check**
- `BuildModeController.gd`: `_is_inside_bunker(pos, half_extent)` now checks all 4 corners of object footprint instead of single center point

**A5 — Warning bubble vertical centering**
- `FarmingTrayUI.gd`: Added `_wrapped_line_count()` helper; water warning bubble now properly centers multi-line text
- `WaterInfoUI.gd`: Purifier warning bubble similarly centered

**A6 — Farming shop menu no longer closes after purchase**
- `BuildModeHUD.gd`: Farming shop emits `farming_item_chosen` without closing submenu

**A7 — Grow light safety net**
- `GrowLight.gd`: `set_powered(false)` in `_ready()` guarantees fixture starts off before PowerManager can potentially power it
- `GrowLight.gd`: `_register_bucket()` deferred to after `global_position` is set (fixes "80 days" bug — lights were registered at (0,0,0))

### Part B Features

**B1 — Fertilizer on empty soil**
- `FarmingTray.gd`: `cell_prepped_fertilizer` array; fertilizer can be applied to empty soil; `plant_first_open_cell()` applies prep

**B2 — Connectable dot at tray pipe stub**
- `BuildModeController._refresh_connectable_dots()`: tray dot at `dot_x = 0.45/0.95`, `dot_y = 0.85` (pipe stub position)

**B3 — Farming tool renamed "Shop"**
- `BuildModeHUD.gd`: Toolbar label "Shop" (🛒), Soil/Seeds as flat top-level categories in 2-level menu

### Part A Bug Fixes (from PART_A_BUGFIX_PLAN)

1. `BuildModeController._refresh_connectable_dots()` — fixed indentation inside for loop
2. `FarmingTrayUI.gd` — added `_wrapped_line_count()`; water bubble vertical centering fixed
3. `FarmingTray.gd` — removed duplicate `_cell_local_x()` definition

### Part B4 — Dormant/Stalled/Ready Status

- `FarmPlant.gd`: `water_fraction` cached each tick
- `FarmingTrayUI.gd`: Status text — "Dormant" (progress=0 & no water), "Stalled (No Water/No Light)", "X hours until harvest"

### Part B5 — Floating Tray Fixes (Root Cause Fixed)

1. `GhostPreview.gd`: `snap_pos.y = 0.5` for trays (was PLACEMENT_Y=2.0 — wall-fixture height)
2. `BuildModeController.gd`: Added tray branch in `_is_position_occupied_for_tile()` — registry-only overlap check (threshold = `grid_size * 0.9`) instead of physics shape query that hit floor collider

### Part C — New Shop Items (Water Case, Can Case, Fuel Can, Crate)

**C1 — Shared unfreeze helper**
- `PickupableItem.gd`: Added `_unfreeze_after_spawn()` to base class

**C2 — Register four items + new categories**
- `FarmingShopHelper.gd`: Added 4 new "scene" kind items (Water Case $80, Can Case $60, Fuel Can $120, Crate $40) with `_spawn_scene_item()` that freezes for 1 frame then unfreezes

**C3 — Add two new categories to Shop menu**
- `BuildModeHUD.gd`: Added "Resources" (Water Case, Can Case, Fuel Can) and "Miscellaneous" (Crate) as flat top-level categories under "Shop" tool

### Part D — Shop Item Previews with Hover Spin

- Construct items: MeshLibrary mesh, `PREVIEW_ROTATION_DEFAULT` (-45°, -45°, 0°)
- Shop items: Instantiate actual scenes/scripts via `PREVIEW_SOURCES` (16=WaterCase.tscn, 17=CanCase.tscn, 18=FuelCan.tscn, 19=TestCrate.tscn)
- Separate viewport pools: `_sub_mesh_instances` (construct) / `_shop_mesh_instances` (shop)
- Hover spin: hovered preview spins 90°/sec clockwise on Y, snaps back to default pose instantly on hover-out
- `PREVIEW_ROTATION_DEFAULT = Vector3(-45.0, -45.0, 0.0)`, `PREVIEW_HOVER_SPIN_DEG_PER_SEC = 90.0`

### Part E — Raise Pipes & Hookup Another 0.5

- `WaterPipeDrawMode.WATER_CEILING_Y`: 3.4 → 3.9
- `BuildModeController.WATER_HOOKUP_PLACEMENT_Y`: 3.4 → 3.9

### Other Fixes

- **GrowLight spatial bucket fix**: `_register_bucket()` deferred until after `global_position` set (fixes "80 days" bug — lights registered at (0,0,0))
- **Shelving.gd crash fix**: Removed dead `_store_hold_t`/`_use_pending` refs (deleted InteractionSystem vars)
- **Light prompts simplified**: `[E] Name` only (no priority/power state)
- **Farming UI**: days/hours display, gap/padding/block height tweaks
- **Pipe drop-down cleanup**: `_cascade_delete_dead_end_drop()` in `WaterManager.delete_and_refund_edge()` removes orphaned vertical drop segments when horizontal run is deleted

## Files Modified

### Core Systems
- `scripts/world/farming/FarmPlant.gd` — `water_fraction` cached, `_process()` live refresh, `_tick_one_game_hour()` simplified
- `scripts/world/farming/FarmingTray.gd` — `cell_prepped_fertilizer`, `_cell_local_x()` centered for single tray
- `scripts/world/farming/FarmingTrayUI.gd` — `_wrapped_line_count()`, status text, bubble centering, gap/padding/block height
- `scripts/world/farming/PlantDatabase.gd` — all 12 `grow_days` halved
- `scripts/world/farming/FarmingConstants.gd` — `LIGHT_FLOOR_SPEED = 0.1`

### Build/Placement
- `scripts/world/build/BuildModeController.gd` — `PLACEMENT_Y = 2.0`, `_is_inside_bunker()` 4-corner check, tray occupancy check, `_is_position_occupied_for_tile()` tray branch
- `scripts/world/build/GhostPreview.gd` — tray `snap_pos.y = 0.5`, half/quarter wall scaling
- `scripts/world/build/BuildModeController.gd` — `WATER_HOOKUP_PLACEMENT_Y = 3.9`, tray occupancy branch in `_is_position_occupied_for_tile()`
- `scripts/world/build/MoveDuplicateTool.gd` — tray `snap_pos.y` handling
- `scripts/world/build/BuildMaterials.gd` — half/quarter wall materials

### Items
- `scripts/world/items/PickupableItem.gd` — `_unfreeze_after_spawn()`
- `scripts/world/items/FuelCan.gd` — removed duplicate `_unfreeze_after_spawn()`
- `scripts/world/items/CanCase.gd`, `WaterCase.gd` — ejection freeze fix
- `scripts/world/items/TestCrate.gd` — inherits PickupableItem

### Build/Shop UI
- `scripts/ui/build/BuildModeHUD.gd` — Shop tool (🛒), Resources/Misc categories, `PREVIEW_SOURCES`, `PREVIEW_ROTATION_DEFAULT`, hover spin, shop preview viewports, `_refresh_shop_previews()`
- `scripts/ui/build/BuildModeHUD.gd` — `CAT_ICONS` updated for Resources/Miscellaneous
- `scripts/ui/build/BuildModeHUD.gd` — `_build_submenu()` creates shop viewports, `_refresh_shop_previews()`, `_on_submenu_draw()` shop preview lookup, `_update_preview_hover_spin()`
- `scripts/ui/build/BuildModeHUD.gd` — `FARMING_SHOP_ITEMS` → `FARMING_SHOP_ITEMS` (kept for compat), `_current_categories()` returns `FARMING_SHOP_ITEMS`
- `scripts/ui/build/BuildModeHUD.gd` — `TOOL_LABELS`/`TOOL_ICONS`: "Shop" (🛒)
- `scripts/ui/build/BuildModeHUD.gd` — Categories: "Resources" (Water Case, Can Case, Fuel Can), "Miscellaneous" (Crate)
- `scripts/ui/build/BuildModeHUD.gd` — `CAT_ICONS` for "Resources" (📦), "Miscellaneous" (🗃)

### Shop/Items
- `scripts/world/build/FarmingShopHelper.gd` — `SHOP_ITEM_INFO` 4 new items (16-19), `"scene"` kind, `_spawn_scene_item()` with freeze/unfreeze
- `scripts/world/items/PickupableItem.gd` — `_unfreeze_after_spawn()`
- `scripts/world/items/FuelCan.gd` — removed duplicate `_unfreeze_after_spawn()`

### Power/Lights
- `scripts/world/power/GrowLight.gd` — `_register_bucket()` deferred, `LIGHT_MATCH_RADIUS = 0.40`, `CELL_BUCKET_SIZE = 0.45`, `LIGHT_FLOOR_SPEED = 0.1`
- `scripts/world/power/WallLight.gd` — `get_priority_prompt()` simplified

### Water/Pipes
- `scripts/world/water/WaterPipeDrawMode.gd` — `WATER_CEILING_Y = 3.9`
- `scripts/world/build/BuildModeController.gd` — `WATER_HOOKUP_PLACEMENT_Y = 3.9`
- `scripts/world/water/WaterManager.gd` — `_cascade_delete_dead_end_drop()` for drop-down cleanup
- `scripts/world/water/WaterHookup.gd` — `_process(delta)` for quality decay

### Water UI
- `scripts/ui/farming/FarmingTrayUI.gd` — `_wrapped_line_count()`, status text, bubble centering, gap/padding/block height
- `scripts/ui/water/WaterInfoUI.gd` — purifier bubble vertical centering

### Misc
- `scripts/ui/build/BuildModeHUD.gd` — Shop tool (🛒), Resources/Misc categories, `PREVIEW_SOURCES`, `PREVIEW_ROTATION_DEFAULT`, hover spin, shop preview viewports, `_refresh_shop_previews()`, `_on_submenu_draw()` shop lookup, `_update_preview_hover_spin()`
- `scripts/ui/build/BuildModeHUD.gd` — `CAT_ICONS` for Resources (📦), Miscellaneous (🗃)
- `scripts/ui/build/BuildModeHUD.gd` — `FARMING_SHOP_ITEMS` flat categories "Soil"/"Seeds" under "Shop"
- `scripts/world/build/FarmingShopHelper.gd` — `SHOP_ITEM_INFO` items 16-19, `"scene"` kind, `_spawn_scene_item()`
- `scripts/world/items/PickupableItem.gd` — `_unfreeze_after_spawn()`
- `scripts/world/items/FuelCan.gd` — removed duplicate `_unfreeze_after_spawn()`
- `scripts/world/environment/BunkerPregen.gd` — `PLACEMENT_Y = 2.0`
- `scripts/world/build/BuildModeController.gd` — `PLACEMENT_Y = 2.0`, `_is_inside_bunker()` corner check, tray occupancy
- `scripts/world/build/GhostPreview.gd` — tray `snap_pos.y = 0.5`
- `scripts/world/build/MoveDuplicateTool.gd` — tray `snap_pos.y` handling
- `scenes/world/MainWorld.tscn` — removed duplicate HUD CanvasLayers

## Verification
- `bash tools/godot_check.sh <headless Godot 4.6.3 binary>` → **PASS**
- Not yet manually playtested in-editor

## Playtest Checklist
1. Pull `origin/main`.
2. **Pickup items** — all 12 items: pickup/drop/place, physics, knockout, culling, hold-follow.
3. **Inventory HUD** — charge badges render correctly (int font size).
4. **Sleep** — 8h sleep advances time correctly.
5. **CanCase/WaterCase** — eject items, no floor fall-through.
6. **Pregen walls** — align with player-placed walls vertically.
7. **Half/Quarter Wall** — heights (1.5m/0.75m), prices ($30/$15), collision matches visual.
8. **Build mode** — inventory bar hides completely.
9. **Farming tray** — place on floor (Y=0.5 ghost, Y=0 placed), no "space occupied" false positive.
10. **Fertilizer** — apply to empty soil, prep works, seed inherits prep.
11. **Tray UI** — Status shows Dormant/Stalled/Ready correctly.
12. **Water warning bubble** — text vertically centered.
13. **Shop tool** — "Shop" (🛒), Soil/Seeds categories, menu stays open after purchase.
14. **Grow light** — never fully stalls (0.1 floor), XZ radius 0.40.
15. **Build mode** — inventory hides, tray placement works, no false "occupied".
16. **Grow light detection** — single tray plant centered, light at center detects it.
17. **Fast-forward** — food/water/sleep/health drain, water quality decay, plant growth all advance ~24h.
17. **Shop items** — Water Case/Can Case/Fuel Can/Crate spawn at head height, freeze 1 frame, no floor fall-through.
17. **Shop previews** — all items show model, hover spins 90°/sec, snaps back on hover-out.
18. **Pipe height** — pipes at 3.9m, hookup at 3.9m, purifier attaches, drop-down works.
18. **Drop-down cleanup** — delete horizontal run, vertical drop vanishes + refunded.

## Next Up
- Polish audit items 6–23 (InteractPrompt jitter, Flashlight pause battery drain, FuelCan prompt, Water pipe labels, Farming tray UI alignment, Build ghost z-fighting, etc.)
- Await Brannon's playtest feedback and next request.