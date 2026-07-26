# Handover — Farming Fixes Round 2 + B5 Tray Fixes (Jul 2026)

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

### Files Modified
- `scripts/world/farming/FarmPlant.gd` — `water_fraction` cached
- `scripts/world/farming/FarmingTray.gd` — `cell_prepped_fertilizer`, fertilizer logic, removed duplicate `_cell_local_x`
- `scripts/world/farming/FarmingTrayUI.gd` — `_wrapped_line_count()`, status text, bubble centering
- `scripts/world/build/GhostPreview.gd` — tray `snap_pos.y = 0.5`
- `scripts/world/build/BuildModeController.gd` — tray occupancy check, `_is_inside_bunker` corner check, debug print
- `scripts/ui/farming/FarmingTrayUI.gd` — status text, bubble centering
- `scripts/world/build/BuildModeController.gd` — bounds check 4 corners, tray occupancy
- `scripts/ui/build/BuildModeHUD.gd` — Shop tool, flat categories
- `scripts/ui/inventory/InventoryHUD.gd` — charge font fix
- `scripts/world/items/*.gd` — PickupableItem base class
- `scripts/player/InteractionSystem.gd` — generic prompt position
- `scripts/player/PlayerStats.gd` — `skip_time(hours)`
- `scripts/ui/menus/SleepOverlay.gd` — uses `skip_time`
- `scripts/world/items/CanCase.gd`, `WaterCase.gd` — ejection fix
- `scripts/world/water/WaterManager.gd`, `WaterPipeDrawMode.gd`, `WaterPipeSegment.gd` — TEMP cleanup
- `scripts/world/environment/BunkerPregen.gd` — `PLACEMENT_Y = 2.0`
- `scripts/world/build/BuildModeController.gd` — `PLACEMENT_Y = 2.0`, bounds check, tray occupancy
- `scripts/ui/build/BuildModeHUD.gd` — Shop tool, Half/Quarter walls
- `scripts/ui/inventory/InventoryHUD.gd` — charge font fix
- `scripts/world/build/GhostPreview.gd` — half/quarter wall scaling, tray Y=0.5
- `scripts/world/build/MoveDuplicateTool.gd` — move ghost scaling
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
7. **Half/Quarter Wall** — heights (1.5m/0.75m), prices ($30/$15), collision matches.
8. **Build mode** — inventory bar hides completely.
9. **Farming tray** — place on floor (Y=0.5 ghost, Y=0 placed), no "space occupied" false positive.
10. **Fertilizer** — apply to empty soil, prep works, seed inherits prep.
11. **Tray UI** — Status shows Dormant/Stalled/Ready correctly.
12. **Water warning bubble** — text vertically centered.
13. **Shop tool** — "Shop" (🛒), Soil/Seeds categories, menu stays open after purchase.
14. **Grow light** — never fully stalls (0.1 floor), XZ radius 0.25.
15. **Build mode** — inventory hides, tray placement works, no false "occupied".

## Next Up
- Polish audit items 6–23 (InteractPrompt jitter, Flashlight pause battery drain, FuelCan prompt, Water pipe labels, Farming tray UI alignment, Build ghost z-fighting, etc.)
- Await Brannon's playtest feedback and next request.