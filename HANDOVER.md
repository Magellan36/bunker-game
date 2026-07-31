# Handover — Graphics Overhaul + Farming/Sleep Fixes + Basket + Preview Fixes + Basket Bug Fixes (Jul 2026)

## What changed this session

### Phase 0: DOF Blur Bug Fix (GameCamera.gd)
- **Root cause**: `dof_focus_distance = 9.0` was shorter than actual camera-to-player distance (~16.1m). DOF far blur transition at 13m meant player/midground was fully blurred.
- **Fix**: `dof_focus_distance: 9.0 → 15.0` (matches actual camera-to-player distance). Added `@export var dof_blur_far_transition: float = 6.0` (was hardcoded 4.0). Removed duplicate declaration.

### Phase 1: GraphicsSettings.gd Preset Overhaul + New Fields
- Updated `PRESETS` table with all Phase 2-4 fields: `anisotropic_filtering`, `shadow_quality`, `render_scale`, `screen_space_aa`, `use_taa`
- Added 8 new fields: `vsync_enabled`, `window_mode`, `fps_cap`, `screen_space_aa`, `use_taa`, `anisotropic_filtering`, `shadow_quality`, `render_scale`
- Added `_apply_to_display()` for VSync, window mode, FPS cap, anisotropic filtering, shadow quality
- Extended `_apply_to_viewport()` for `screen_space_aa`, `use_taa`, `render_scale`
- Extended `set_setting_live()`, `_save()`, `_load()` for all 8 new fields
- Updated `PRESETS` table with complete Phase 2-4 values per graphics plan

### Phase 2: Display Settings (VSync, Fullscreen, Resolution, FPS Cap)
- New fields: `vsync_enabled` (bool), `window_mode` (int enum), `fps_cap` (int, 0=uncapped)
- Added to `_apply_to_display()` and `PRESETS`

### Phase 3: Anti-Aliasing Overhaul
- New fields: `screen_space_aa` (int enum), `use_taa` (bool)
- AA combo dropdown in panel mapping 6 friendly options → 3 raw fields:
  - Off, Fast (FXAA), Balanced (MSAA 2x), Sharp (MSAA 2x+FXAA), Smooth (TAA), Max (MSAA 4x+TAA)

### Phase 4: Anisotropic Filtering, Shadow Quality, Render Scale
- New fields: `anisotropic_filtering` (0/2/4/8/16), `shadow_quality` (atlas size: 1024/2048/4096), `render_scale` (0.5-1.0)
- Applied in `_apply_to_display()` and `_apply_to_viewport()`

### Phase 5: Settings Panel UI Rewrite (GraphicsSettingsPanel.gd)
- Full rewrite with sectioned layout (Quality Preset, Display, Rendering, Advanced Quality, Flashlight, Camera)
- ScrollContainer with max height, section headers matching PauseMenuUI
- AA combo dropdown (6 options → 3 raw fields)
- Display: Window Mode, Resolution (windowed only), VSync, FPS Cap
- Rendering: AA combo, Anisotropic, Shadow Quality, Render Scale slider
- Advanced Quality: SDFGI, SSAO, SSIL, Volumetric Fog, Glow, DOF checkboxes
- Flashlight: Volumetrics, Shadows checkboxes
- Camera: FOV slider
- ScrollContainer with max height, section headers, PauseMenuUI-styled theme
- Uses `UIKit.settings_controls_theme()` for CheckBox/OptionButton/HSlider
- Reverted hover-spin to 2-pool (construct vs shop)

### Preview Scale Normalization (All 3 Pools)
- Added `PREVIEW_TARGET_SIZE = 0.85` (later adjusted to 0.5667 for 1.5x zoom-out)
- Added `_preview_normalize_scale(aabb)` helper
- Applied to all 3 preview pools: MeshLibrary, procedural, shop
- Seed packets (~0.14m) and Generator L (~1.85m) now render same on-screen size

### Preview Zoom Out 1.5×
- `PREVIEW_TARGET_SIZE: 0.85 → 0.5667` (0.85/1.5)
- All three preview pools render ~1.5× smaller

### Grow Rate Revert (PlantDatabase.gd)
- Reverted all 12 `grow_days` to original values (was halved in earlier commit)
- tomato: 5.0→10.0, onion: 10.0→20.0, basil: 2.5→5.0, strawberry: 3.5→7.0, carrot: 4.0→8.0, chili_pepper: 4.5→9.0, bell_pepper: 6.0→12.0, garlic: 7.0→14.0, potato: 8.0→16.0, blueberry: 9.0→18.0, corn: 11.0→22.0, pumpkin: 15.0→30.0

### Basket Feature (12-slot Container)
- New files: `scripts/world/items/Basket.gd`, `scenes/world/Basket.tscn`, `scripts/ui/inventory/BasketUI.gd`
- `InteractionSystem.gd`: `_basket_ui` field, `_basket_ui_open()`, E-key stash (`_try_add_nearest_to_basket`), G-key open menu, ground-prompt override
- `WaterBottle`/`FoodCan`/`FarmProduceItem`: added `basket_storable` group
- `MainWorld.gd`: `_basket_ui` field + `_setup_basket_ui()` wiring
- Shelving compatibility verified (uses `shelf_stack_limit`/`shelf_item_type` duck typing)

### Fixes & Cleanups
- Removed duplicate `interaction_system` declaration in GraphicsSettingsPanel.gd
- Fixed `nil` → `null` typos (2 occurrences) in GraphicsSettingsPanel.gd
- Removed duplicate `_make_checkbox`/`_make_button` definitions
- Removed dead code: `interaction_system`, `inventory`, `inventory_hud` (unused in this file)
- Deleted duplicate `_make_checkbox`/`_make_button` definitions
- Fixed `interaction_system` duplicate declaration in GraphicsSettingsPanel.gd
- Reverted Basket purchasable in Build Mode (kept in AdminSpawnMenu for testing only)
- Fixed GrowLight.gd path in _procedural_ghost_mesh() (farming/ → power/)
- Fixed UIKit settings_controls_theme() syntax error (removed invalid `also` keyword)
- DOF blur fix: `dof_focus_distance: 9.0→15.0`, added `dof_blur_far_transition` export

### Preview Scale Normalization
- Added `PREVIEW_TARGET_SIZE = 0.85` (later 0.5667) + `_preview_normalize_scale()`
- Applied to MeshLibrary, procedural, and shop preview branches

### Preview Zoom Out 1.5×
- `PREVIEW_TARGET_SIZE: 0.85 → 0.5667` (0.85/1.5)

### Grow Rate Revert
- PlantDatabase.gd: all 12 `grow_days` reverted to original values (×2 from previous halved state)

### Basket Feature
- New files: `scripts/world/items/Basket.gd`, `scenes/world/Basket.tscn`, `scripts/ui/inventory/BasketUI.gd`
- InteractionSystem: `_basket_ui`, `_basket_ui_open()`, E-key stash, G-key open, ground-prompt override
- WaterBottle/FoodCan/FarmProduceItem: added `basket_storable` group
- MainWorld: `_basket_ui` + `_setup_basket_ui()` wiring
- Shelving compatibility verified (duck-typed `shelf_stack_limit`/`shelf_item_type`)

### Fixes & Cleanups
- Removed duplicate `interaction_system` in GraphicsSettingsPanel.gd
- Fixed `nil` → `null` typos (2 occurrences)
- Removed duplicate `_make_checkbox`/`_make_button` definitions
- Removed dead code: `interaction_system`, `inventory`, `inventory_hud` (unused)
- Fixed GrowLight.gd path in `_procedural_ghost_mesh()` (`farming/` → `power/`)
- Fixed UIKit `settings_controls_theme()` syntax error (removed invalid `also` keyword)
- DOF blur fix: `dof_focus_distance: 9.0→15.0`, added `dof_blur_far_transition` export

### Combined-AABB Calculation Fix (Rotation Pivot / Centering Bug)
- **Root cause**: Both construct-tab and shop-tab preview paths merged raw local-space mesh AABBs without accounting for each mesh's offset from its root node. Most procedural devices position body mesh above root (floor-contact point), so merging local AABBs biased the computed center toward the base, causing objects to orbit around their feet instead of spinning in place.
- **Fix**: Added static helper `_combined_local_aabb(root: Node3D)` in BuildModeHUD.gd that correctly transforms each mesh's AABB into root's local coordinate space using global transforms (`root_inverse * mi.global_transform`). Replaced duplicated buggy logic in both call sites:
  1. Construct-tab procedural preview path (`_refresh_submenu_previews`)
  2. Shop-tab imported model preview path (`_refresh_shop_previews`)
- MeshLibrary-mesh branch untouched (single mesh, no parent-imposed offset)

### Basket Item Added to Shop (Miscellaneous) — $100
- `FARMING_SHOP_ITEMS`: added Basket (tile_id 20) to Miscellaneous
- `PREVIEW_SOURCES`: added preview entry for Basket.tscn
- `SHOP_ITEM_INFO`: added purchase/spawn entry for Basket ($100, kind=scene)
- Reuses existing generic `_spawn_scene_item()` path (same as Crate/Water Case/etc.)

### Basket Bug Fixes & Follow-Ups (Jul 2026, multi-round)

**1. BasketUI type error fix**
- **Bug**: `_refresh_slot()` treated basket slots as arrays (copied from ShelfUI's stacked-slot model), but Basket slots hold single items. Assigning a `RigidBody3D` to an `Array` var threw "Trying to assign value of type 'Object' to a variable of type 'Array'."
- **Fix**: `_refresh_slot()` reads the slot directly: `var item = _basket.slots[slot_idx] ... _set_slot(slot_idx, item, 1 if item != null else 0)`

**2. Floating prompts — basket & storable items**
- **Root cause**: `InteractionSystem._update_prompt()` has two mutually-exclusive halves — CASE 1 (holding item, returns early) and CASE 2 (empty-handed). The "[E] Add to Basket" logic was in CASE 2 behind a `held_item != null` check that can never be true there (dead code).
- **Fix (3 parts)**: `Basket.get_interact_prompt()` added ("[G] Open Basket" while held); "[E] Add to Basket" logic moved from CASE 2 into CASE 1 (uses `_tracked_bodies`); dead CASE 2 basket-check removed.
- **Verification**: Pick up basket → "[G] Open Basket" appears. Walk near Water Bottle/Food Can/produce while holding basket → "[E] Add to Basket" appears over that item. Press E → item stashes. Fuel Can/Seed packets show no prompt (not `basket_storable`).

**3. Spawn flicker — Water Case / Can Case / Fuel Can / Crate / Basket (5 rounds to root-cause)**
- **Symptom**: item visible for an instant on spawn, vanishes, reappears seconds later at a single fixed point `(0, 1.5, 5.5)` regardless of purchase location, items stacking on top of each other.
- **Rounds 1–4 (superseded, kept here for history)**: `call_deferred` → `await physics_frame` ×2 (registration-timing theory) → raycast-to-floor (`intersect_ray()` called outside `_physics_process()`, silently failed — "space is locked") → `PhysicsServer3D.body_set_state()` forced-transform patch. None of these were the real cause.
- **Real root cause (round 5)**: the freeze/kinematic dance itself was the bug. None of the provably-working `spawn_at()` helpers (`SeedItem`/`BagOfSoilItem`/`FertilizerItem`/`EmptyBagItem`) ever freeze — they just `add_child()` then set `global_position` once. The fixed rescue point is explained exactly by the bunker's real floor plan (`RockSurround.OFFSET_X/Z = -12.5/4.5`, `depth/width = 16/8`): an item stuck at world `(0,0,0)` gets its Z clamped by `MainWorld._check_abyss_items()`'s bounds-check to `5.5` (world Z=0 is outside the bunker's valid `[4.5, 12.5]` range) every single time — meaning the item was never actually near the player at all.
- **Fix**: `FarmingShopHelper.spawn_scene_settled()` now matches the working pattern exactly — load scene, `add_child()`, set `global_position` once, done. No freeze, no raycast, no `physics_frame` waits. `continuous_cd = true` kept on all 5 `.tscn` files as tunneling insurance. `AdminSpawnMenu._spawn_scene()` calls this same shared function instead of keeping its own copy.

**4. G/E close BasketUI**
- `BasketUI._unhandled_input()` only checked `"ui_cancel"`/`"interact"` (Escape/E) as close triggers; G (`"store_item"`) fell into the do-nothing `elif` branch. Added `"store_item"` alongside the other two.

**5. Basket stays upright while held**
- Every other held item keeps whatever tilt it had at pickup (intentional/correct for those). `Basket._physics_process()` now overrides the parent's follow logic (`super()` first, so position/knockout/grace-timer are untouched) and forces `global_transform.basis = Basis.IDENTITY` every tick while held — hard snap, not a spring.

**Verification**: `tools/godot_check.sh` → PASS after each round. Manually confirmed: G/E/Escape all close BasketUI; basket stays vertical through movement/turning/collisions; Water Case/Can Case/Fuel Can/Crate/Basket all spawn cleanly from two different purchase locations with no flicker; admin-spawn path behaves identically to the real Shop purchase path.

---

## Files Modified (Graphics Overhaul + Fixes + Basket)

### Core Graphics System
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/core/GraphicsSettings.gd` — 8 new fields, PRESETS overhaul, _apply_to_display(), _apply_to_viewport() extended
- `scripts/core/GraphicsSettings.gd` — set_setting_live/_save/_load extended for 8 new fields

### UI Panels
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — complete rewrite with sectioned layout
- `scripts/ui/common/UIKit.gd` — added `settings_controls_theme()` function
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — removed duplicate `interaction_system`, `nil`→`null` fixes
- `scripts/ui/menus/BuildModeHUD.gd` — preview scale normalization, zoom out, Combined-AABB fix, Basket shop entry
- `scripts/ui/menus/AdminSpawnMenu.gd` — spawn floor-through fix (await physics_frame), Basket spawn entry

### Core Systems
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/core/GraphicsSettings.gd` — 8 new fields, PRESETS overhaul
- `scripts/core/PlantDatabase.gd` — grow_days reverted to original values (×2)

### Basket Feature
- New: `scripts/world/items/Basket.gd`, `scenes/world/Basket.tscn`, `scripts/ui/inventory/BasketUI.gd`
- `scripts/player/InteractionSystem.gd` — basket UI wiring, E/G key handling, floating prompts fix
- `scripts/world/core/MainWorld.gd` — `_basket_ui` wiring
- `scripts/world/items/WaterBottle.gd` — added `basket_storable` group
- `scripts/world/items/FoodCan.gd` — added `basket_storable` group
- `scripts/world/items/FarmProduceItem.gd` — added `basket_storable` group
- `scripts/world/items/Basket.gd` — get_interact_prompt() added

### Farming Systems
- `scripts/world/farming/PlantDatabase.gd` — `grow_days` reverted to original values (×2)

### Build/Shop UI
- `scripts/ui/build/BuildModeHUD.gd` — preview scale normalization, zoom out, Combined-AABB fix, Basket shop entry
- `scripts/ui/menus/AdminSpawnMenu.gd` — added Basket spawn entry, spawn floor-through fix
- `scripts/world/build/BuildModeController.gd` — `TILE_BASKET` constant
- `scripts/world/build/FarmingShopHelper.gd` — SHOP_ITEM_INFO entry for Basket, spawn floor-through fix

### Fixes & Cleanups
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — removed duplicate `interaction_system`, `nil`→`null`
- `scripts/ui/common/UIKit.gd` — fixed `settings_controls_theme()` syntax error
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/world/power/GrowLight.gd` — path fix (`farming/` → `power/`)
- `scripts/ui/build/BuildModeHUD.gd` — preview scale normalization, zoom out, Combined-AABB helper
- `scripts/world/items/Basket.gd` — get_interact_prompt() for "[G] Open Basket"
- `scripts/player/InteractionSystem.gd` — CASE 1 basket prompts, dead code removal
- `scripts/ui/inventory/BasketUI.gd` — _refresh_slot() type fix
- `scripts/ui/menus/AdminSpawnMenu.gd` — await physics_frame ×2
- `scripts/world/build/FarmingShopHelper.gd` — await physics_frame ×2

### Files Created
- `scripts/world/items/Basket.gd`
- `scenes/world/Basket.tscn`
- `scripts/ui/inventory/BasketUI.gd`

---

## Updated Files Summary (Recent Commits)

| Commit | Description |
|--------|-------------|
| `72db17c` | Basket bug fixes (items 1-3 from plan_basket_fixes.md) |
| `5e11424` | Add Basket item to Shop (Miscellaneous) — $100 |
| `0e6d24f` | Fix Combined-AABB Calculation (Rotation Pivot / Centering Bug) |
| `7a28135` | Fix GraphicsSettingsPanel duplicate declarations + remove UIKit dangling comment |
| `538aeb3` | Remove duplicate interaction_system in GraphicsSettingsPanel |
| `4c4e260` | Settings panel UI rewrite + Admin spawn entry |
| `185d89f` | Zoom out previews by 1.5x |
| `5f385f1` | Normalize preview scale across all pools |
| `5077e34` | Full-fidelity construct-tab previews |
| `d252a58` | Full basket feature + farming/sleep fixes |
| `672e1ab` | Revert Basket purchasable in Build Mode |
| `6424c86` | Basket purchasable in Build Mode |
| `78591ed` | Fix GrowLight path |
| `b78bd51` | Fix UIKit settings_controls_theme() syntax |
| `54728d6` | DOF blur fix + preset overhaul |
| `ff3a80e` | fix(spawn): remove freeze/raycast machinery, match working pattern exactly |
| `483e052` | fix(spawn): consolidate into shared physics-safe raycast spawn |
| `b99e31a` | fix(spawn): raycast-based floor placement + continuous_cd for flicker fix |

---

## Next Up
- Polish audit items 6–23 (InteractPrompt jitter, Flashlight pause battery drain, FuelCan prompt, Water pipe labels, Farming tray UI alignment, Build ghost z-fighting, etc.)
- Await Brannon's playtest feedback and next request