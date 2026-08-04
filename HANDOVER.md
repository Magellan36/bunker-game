# Handover — Build Mode Ownership Expansion, Furniture, Wall Draw Mode, Ghost Model System (Aug 2026)

## What changed this session

### Role expansion
This Claude instance's scope expanded from Furniture-only to ALL Build
Mode / Construct Menu object placement (spawning, ghost preview,
wall/floor snapping, height/spacing, general placement refinement) across
every object type.

### Furniture: Small/Medium Table, Chair, Poster
- New `scripts/world/furniture/Table.gd`, `Chair.gd`, `Poster.gd` — see
  `docs/systems/build/README.md`'s Furniture section for details.
- Chair sit/stand mechanic: `Player.gd` gained `seated_chair` state;
  `InteractionSystem.gd`'s `_try_interact()`/`_update_prompt()` both check
  it first, before any proximity scan, so E always means "stand" while
  seated regardless of what else is nearby; any WASD press while seated
  also stands the player up and lets movement continue immediately
  ("walk out of the chair").

### Wall Draw Mode — click-drag-click stretched walls
Full/Half/Quarter Wall placement rewritten from single-click discrete 1m
segments to one dynamically-stretched mesh per wall, free 360° angle,
grid-snapped endpoints, Q/E height-tier cycling, RMB/ESC exit. See
`docs/systems/build/README.md`'s Wall Draw Mode section. Went through
several fix rounds this session: floating half/quarter tiers (tier-aware
placement Y), bounds-check false positives on long walls (half-extent was
incorrectly scaled by run length), ghost sunk to half-height (a
`global_position` assignment was clobbering the mesh's own floor-flush
offset), minimum length matching the idle sliver instead of a full 1m cell.

### Ghost Model Master System — real-shaped previews, universal facing arrow
New `scripts/world/build/GhostModelBuilder.gd` — see
`docs/systems/build/README.md`'s Ghost Model System section for the full
writeup. Replaced generic box/rectangle ghost previews with translucent
real-model ghosts for every object already registered for a Construct-menu
preview, and gave every placeable object a facing arrow (previously only a
few hand-picked tiles had one).

Two rounds of follow-up fixes after the initial rollout:
- **Chair ghost was invisible** — `Chair.gd`'s `_ready()` returned before
  `_build_mesh()` when `_is_preview_only` was set (pre-existing bug, not
  introduced by the ghost system — the Construct-menu spinning preview was
  almost certainly blank too, before this).
- **Ghosts had live collision, pushed the player** — root cause was a
  lifecycle-order bug: collision was stripped *before* `add_child()`, i.e.
  before `_ready()` had run, so scripts that set `collision_layer`
  unconditionally in `_ready()` (most of them) silently undid the strip.
  Fixed by moving the strip to run after `add_child()`.
- **Grow Light placement was broken** (always red, "Space is already
  occupied," intermittently fixable by rapid mouse movement/clicking) —
  traced to the same collision bug: `_is_position_occupied()`'s physics
  query (`collision_mask = 1`) was detecting the ghost's own still-live
  collision shape at its own query position. Same fix resolved both.
- **Facing arrow was backward on most objects** — rather than continuing
  to add a hand-tuned override per newly-reported tile (Chair, Dispenser,
  Test Sink, then Battery ×3, Stove, Tables, Trays), recognized the
  pattern (every default-using tile was backward; only hand-tuned ones
  were correct) and flipped the *default* itself (180°), removing the
  now-redundant individual overrides.
- **Wall Lights failed to place in player-expanded bunker areas** despite
  a green ghost — `TILE_LIGHT` had no entry in `_tile_half_extents()`,
  inheriting the generic 0.40 floor-object fallback for the confirm-time
  bunker-bounds check, oversized for a thin wall-flush fixture. Same fix
  already applied to `TILE_POSTER` earlier in the session, now applied to
  Light too.

---

# Handover — NPC Basics + Cooking Fixes + UI Unification + NPC Basics (Aug 2026)

## What changed this session

### NPC Basics — Wandering NPC + Talk UI + Admin Spawn (Aug 2026)

- **scripts/npc/NPC.gd**: New `CharacterBody3D` NPC with IDLE/WANDERING state machine, random wandering within dug-out bunker bounds (using `MainWorld.get_cleared_cell_bounds_world()`), collision with all structures, [E] Talk interaction that opens `NPCTalkMenuUI`
- **scripts/ui/npc/NPCTalkMenuUI.gd**: Modal menu with Talk button → placeholder dialogue ("...") + Close button, built on shared UIKit builders
- **scenes/npc/NPC.tscn**: CharacterBody3D with capsule mesh/collision, no custom collision_layer/mask (uses default layer 1 for proper collision)
- **MainWorld.gd**: Added `get_cleared_cell_bounds_world()` returning Rect2 of all cleared cells (pregen + dug) for NPC wander bounds
- **AdminMenu.gd**: Added "Spawn NPC" row under NPC section; callback spawns NPC.tscn 2m in front of player

### Cooking Fixes — Part 1/2 (Aug 2026)

- **CookingPot.gd**: Added `get_use_prompt()` — shows `"[E] Place Cooking Pot"` when holding pot near a stove with an open slot (3m range)
- **Stove.gd**: Added `_grid_connected` tracking; `set_powered()` now tracks grid connection and auto-turns-off stove when wire connection lost; `on_interact()` prevents turning on without grid connection; `get_interact_prompt()` shows "Stove Not Connected" when unpowered and not grid-connected

### Fix 1: Missing "Place on Stove" prompt when holding pot near stove
### Fix 2: Stove must be wired to power; auto-shuts-off if disconnected

### UI Unification — Pause Menu + Graphics Settings Panel (Jul 2026)

- **UIKit.gd**: Added shared menu builders (`build_modal_backdrop()`, `build_centered_panel()`, `make_button()`, `make_section_label()`, `make_row_label()`), font-size constants (`FONT_SIZE_TITLE=20`, `FONT_SIZE_SECTION=11`, `FONT_SIZE_BODY=13`), `MENU_PANEL_W=380`
- **PauseMenuUI.gd**: Complete rewrite using UIKit builders; fixed UTF-8 encoding (removed BOM/garbled comments); unified colors with NEUTRAL theme; confirm dialog now matches main panel gray
- **GraphicsSettingsPanel.gd**: Complete rewrite using UIKit builders; **FIXED off-center bug** (`build_centered_panel()` with fixed size); row labels now use `make_row_label()` with proper font/color; unified panel width (380), fonts, button styles with PauseMenuUI

### Fix: Removed invalid `custom_maximum_size` from `build_centered_panel()`

Control/Panel has no `custom_maximum_size` property in Godot 4 — that line always errored. The fixed anchor offsets + `custom_minimum_size` already fully lock the panel's size.

### NPC Basics — Wandering NPC + Talk UI + Admin Spawn (Aug 2026)

- **scripts/npc/NPC.gd**: CharacterBody3D NPC with IDLE/WANDERING state machine, random wandering within dug-out bunker bounds (using `MainWorld.get_cleared_cell_bounds_world()`), collision with all structures, [E] Talk interaction that opens `NPCTalkMenuUI`
- **scripts/ui/npc/NPCTalkMenuUI.gd**: Modal menu with Talk button → placeholder dialogue ("...") + Close button, built on shared UIKit builders
- **scenes/npc/NPC.tscn**: CharacterBody3D with capsule mesh/collision, no custom collision_layer/mask (uses default layer 1 for proper collision)
- **MainWorld.gd**: Added `get_cleared_cell_bounds_world()` returning Rect2 of all cleared cells (pregen + dug) for NPC wander bounds
- **AdminMenu.gd**: Added "Spawn NPC" row under NPC section; callback spawns NPC.tscn 2m in front of player

### Cooking Fixes — Part 1/2 (Aug 2026)

- **CookingPot.gd**: Added `get_use_prompt()` — shows `"[E] Place Cooking Pot"` when holding pot near a stove with an open slot (3m range)
- **Stove.gd**: Added `_grid_connected` tracking; `set_powered()` now tracks grid connection and auto-turns-off stove when wire connection lost; `on_interact()` prevents turning on without grid connection; `get_interact_prompt()` shows "Stove Not Connected" when unpowered and not grid-connected

### Fix 1: Missing "Place on Stove" prompt when holding pot near stove
### Fix 2: Stove must be wired to power; auto-shuts-off if disconnected

---

## Files Modified

### NPC Basics
- `scripts/npc/NPC.gd` — new file
- `scripts/ui/npc/NPCTalkMenuUI.gd` — new file
- `scenes/npc/NPC.tscn` — new file
- `scripts/world/core/MainWorld.gd` — added `get_cleared_cell_bounds_world()`
- `scripts/ui/menus/AdminMenu.gd` — added "Spawn NPC" row + callback

### Cooking Fixes (Part 1/2)
- `scripts/world/items/CookingPot.gd` — added `get_use_prompt()`
- `scripts/world/cooking/Stove.gd` — added `_grid_connected` tracking, grid-aware `set_powered()`/`on_interact()`/`get_interact_prompt()`

### UI Unification
- `scripts/ui/common/UIKit.gd` — added `build_centered_panel()`, `make_button()`, `make_section_label()`, `make_row_label()`, font-size constants, `MENU_PANEL_W=380`
- `scripts/ui/menus/PauseMenuUI.gd` — complete rewrite using UIKit builders
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — complete rewrite using UIKit builders; fixed off-center bug
- `scripts/ui/common/UIKit.gd` — removed invalid `custom_maximum_size` from `build_centered_panel()`

### Admin Menu Additions (Part A)
- `scripts/ui/menus/AdminMenu.gd` — added `world_node`, `ADMIN_CASH_STEP`, `PRODUCE_SPAWN_HEIGHT`, new `_row_defs` rows, `_format_thousands()`, `_on_add_cash_pressed()`, `_on_hookup_output_double_pressed()`, `_spawn_produce()` + 3 callbacks

### Admin Spawn Menu Removal (Part B)
- `scripts/ui/menus/AdminSpawnMenu.gd` + `.uid` — deleted
- `MainWorld.gd` — removed F10 handler, `_admin_menu` var, `_toggle_admin_spawn_menu()`
- `PauseMenuUI.gd` — layer comment fixed
- `PickupableItem.gd` — spawn helper comment updated
- `FarmingShopHelper.gd` — "Single source of truth" comment updated
- `AdminMenu.gd` — docstring F10 reference removed; layer comment fixed
- Docs updated across `PROJECT_SUMMARY.md`, `docs/systems/ui/README.md`, `docs/systems/build/README.md`, `docs/systems/water/README.md`, `docs/systems/farming/README.md`
- `architecture.json` regenerated

---

## Files Created
- `scripts/npc/NPC.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `scenes/npc/NPC.tscn`
- `scripts/ui/hud/NeedsGauge.gd`
- `scripts/ui/hud/StatusEffectIcon.gd`
- `scripts/ui/hud/StatusEffectsContainer.gd`
- `assets/shaders/grunge_overlay.gdshader`
- `scripts/ui/hud/NeedsGauge.gd`
- `scripts/ui/hud/StatusEffectIcon.gd`
- `scripts/ui/hud/StatusEffectsContainer.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `scenes/npc/NPC.tscn`

---

## Files Deleted
- `scripts/ui/hud/StatusBars.gd` + `.uid`
- `scripts/ui/hud/CircleFill.gd` + `.uid`
- `scripts/ui/menus/AdminSpawnMenu.gd` + `.uid`

---

## Next Up
- Real gameplay status effects still need to be wired into `StatusEffectsContainer.add_effect()` — currently F7 test-only.
- Cooking System Part 2: Cook timer + Dish item (Part G from `COOKING_SYSTEM_PLAN_PART3.md`)
- `BuildModeHUD.gd`'s buttons/tabs/interactions are now in UI Claude's scope per Brannon's Jul 2026 note — not yet started, rest of `BuildModeHUD.gd` stays with the non-UI Claude instance.
- Worn-look shader defaults (`grit_strength = 0.14`, `grit_scale = 26.0`) are a first pass — confirm they read right in actual play, not just the single reviewed screenshot.
- Admin Menu Part A: economy/water-tier/produce-spawn cheats (already done in this session)
- Admin Menu Part B: F10 Admin Spawn Menu removal + docs (already done in this session)
- NPC Basics (already done in this session)
- Cooking Fixes Part 1/2 (already done in this session)
- UI Unification (already done in this session)

---

## Verification Checklist (for Brannon's in-editor test)
1. **NPC**: F7 → Spawn NPC → NPC wanders, collides with walls/furniture, [E] Talk → popup → Talk → "..." → Close
2. **Cooking**: Pot near stove → [E] Place prompt appears; Stove requires grid connection; power loss auto-shuts-off; prompt shows "Stove Not Connected"
3. **UI**: Pause Menu (ESC) centered; Graphics Settings (F7→Settings) centered; row labels use project font; confirm dialog gray matches main panel
3. **Admin Menu (F7)**: 11 rows, 6 sections; +$100k Cash updates HUD; Hookup Output x2 increments tier (warns at max); Spawn Potato/Blueberry/Tomato drops items with pop-in
4. F10 does nothing (no menu, no errors)
5. F7 Admin Menu: 11 rows, 6 sections; all original buttons (Power, Time, Water, Economy, Farming, Status) + new rows work