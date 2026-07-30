# Handover — Graphics Overhaul + Farming/Sleep Fixes + Basket + Preview Fixes (Jul 2026)

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

### Verification
- `tools/godot_check.sh` → **PASS**
- Code compiles cleanly

## Files Modified (Graphics Overhaul + Fixes)

### Core Graphics System
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/core/GraphicsSettings.gd` — 8 new fields, PRESETS overhaul, _apply_to_display(), _apply_to_viewport() extended
- `scripts/core/GraphicsSettings.gd` — set_setting_live/_save/_load extended for 8 new fields

### UI Panels
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — complete rewrite with sectioned layout
- `scripts/ui/common/UIKit.gd` — added `settings_controls_theme()` function
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — removed duplicate `interaction_system`, `nil`→`null` fixes
- `scripts/ui/menus/BuildModeHUD.gd` — preview scale normalization, zoom out

### Core Systems
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/core/GraphicsSettings.gd` — 8 new fields, PRESETS overhaul
- `scripts/core/PlantDatabase.gd` — grow_days reverted to original values

### Basket Feature
- New: `scripts/world/items/Basket.gd`, `scenes/world/Basket.tscn`, `scripts/ui/inventory/BasketUI.gd`
- `scripts/player/InteractionSystem.gd` — basket UI wiring, E/G key handling
- `scripts/world/core/MainWorld.gd` — `_basket_ui` wiring

### Item Scripts
- `scripts/world/items/Basket.gd` (new)
- `scripts/world/items/WaterBottle.gd` — added `basket_storable` group
- `scripts/world/items/FoodCan.gd` — added `basket_storable` group
- `scripts/world/items/FarmProduceItem.gd` — added `basket_storable` group

### Farming Systems
- `scripts/world/farming/PlantDatabase.gd` — `grow_days` reverted to original values (×2)
- `scripts/world/farming/PlantDatabase.gd` — grow_days reverted to original values

### Build/Shop UI
- `scripts/ui/build/BuildModeHUD.gd` — preview scale normalization, zoom out
- `scripts/ui/menus/AdminSpawnMenu.gd` — added Basket spawn entry

### Fixes & Cleanups
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — removed duplicate `interaction_system`, `nil`→`null`
- `scripts/ui/menus/BuildModeHUD.gd` — preview scale normalization, zoom out
- `scripts/ui/common/UIKit.gd` — fixed `settings_controls_theme()` syntax error
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/world/power/GrowLight.gd` — path fix (`farming/` → `power/`)
- `scripts/world/build/BuildModeController.gd` — `TILE_BASKET` constant
- `scripts/ui/menus/AdminSpawnMenu.gd` — Basket spawn entry

### Files Created
- `scripts/world/items/Basket.gd`
- `scenes/world/Basket.tscn`
- `scripts/ui/inventory/BasketUI.gd`

### Verification
- `tools/godot_check.sh` → **PASS**
- Code compiles cleanly

---

## Files Modified (Graphics Overhaul + Fixes)

### Core Graphics System
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/core/GraphicsSettings.gd` — 8 new fields, PRESETS overhaul, _apply_to_display(), _apply_to_viewport() extended
- `scripts/core/GraphicsSettings.gd` — set_setting_live/_save/_load extended for 8 new fields
- `scripts/core/PlantDatabase.gd` — grow_days reverted to original values (×2)

### UI Panels
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — complete rewrite with sectioned layout
- `scripts/ui/common/UIKit.gd` — added `settings_controls_theme()` function
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — removed duplicate `interaction_system`, `nil`→`null` fixes
- `scripts/ui/menus/BuildModeHUD.gd` — preview scale normalization, zoom out

### Core Systems
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/core/GraphicsSettings.gd` — 8 new fields, PRESETS overhaul, _apply_to_display(), _apply_to_viewport() extended
- `scripts/core/PlantDatabase.gd` — grow_days reverted to original values (×2)

### Basket Feature
- `scripts/world/items/Basket.gd` (new)
- `scenes/world/Basket.tscn` (new)
- `scripts/ui/inventory/BasketUI.gd` (new)
- `scripts/player/InteractionSystem.gd` — basket UI wiring, E/G key handling
- `scripts/world/core/MainWorld.gd` — `_basket_ui` field + `_setup_basket_ui()` wiring
- `scripts/world/items/WaterBottle.gd` — added `basket_storable` group
- `scripts/world/items/FoodCan.gd` — added `basket_storable` group
- `scripts/world/items/FarmProduceItem.gd` — added `basket_storable` group

### Build/Shop UI
- `scripts/ui/build/BuildModeHUD.gd` — preview scale normalization, zoom out
- `scripts/ui/menus/AdminSpawnMenu.gd` — added Basket spawn entry
- `scripts/world/build/BuildModeController.gd` — `TILE_BASKET = 25` constant

### Farming Systems
- `scripts/world/farming/PlantDatabase.gd` — `grow_days` reverted to original values (×2)

### Fixes & Cleanups
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — removed duplicate `interaction_system`, `nil`→`null` fixes
- `scripts/ui/common/UIKit.gd` — fixed `settings_controls_theme()` syntax error
- `scripts/core/GameCamera.gd` — DOF fix, export transition
- `scripts/world/power/GrowLight.gd` — path fix (`farming/` → `power/`)
- `scripts/ui/build/BuildModeHUD.gd` — preview scale normalization, zoom out

---

## Next Up
- Polish audit items 6–23 (InteractPrompt jitter, Flashlight pause battery drain, FuelCan prompt, Water pipe labels, Farming tray UI alignment, Build ghost z-fighting, etc.)
- Await Brannon's playtest feedback and next request

---

## Updated Files Summary (Recent Commits)

| Commit | Description |
|--------|-------------|
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

---

## Next Up
- Polish audit items 6–23 (InteractPrompt jitter, Flashlight pause battery drain, FuelCan prompt, Water pipe labels, Farming tray UI alignment, Build ghost z-fighting, etc.)
- Await Brannon's playtest feedback and next request