# Handover — NPC Give/Takeaway + F7 Relationship Visualizer (Aug 2026)

## What changed this session

### Give
- **NPC.gd**: `receive_item_from_player()` (V1 scope: DishItem/
  FarmProduceItem only), `GIVE_RELATIONSHIP_BONUS` (+15).
- **NPCItemUser.gd**: `is_giveable()`.
- **InteractionSystem.gd** (Player subsystem — **NOT applied this session**;
  flagged for the later plan): new "[E] Give `<item>` to `<name>`" prompt
  block (mirrors Basket/Cooking Pot pattern) + dispatch, `_find_nearest_npc()`,
  `_try_give_to_nearest_npc()`. Deferred with the rest of section 5.

### Takeaway
- **NPC.gd**: `is_consuming_from_need()` (gated on the same 55.0 threshold
  Eat/DrinkActivity auto-trigger on), `on_item_taken_by_player()`,
  `TAKEAWAY_RELATIONSHIP_PENALTY` (-15).
- **NPCItemUser.gd**: `find_holder()`.
- **InteractionSystem.gd** (Player subsystem — **NOT applied this session**):
  `_try_pickup()` and `_nearest_pickup_distance()` `is_held` carve-outs; the
  CASE 2 prompt-loop carve-out. Deferred with the rest of section 5.
  (Note: the latent gap this closes in `_try_pickup()` is likewise still open
  until that section lands.)

### F7 Relationship Visualizer
- **NPC.gd**: `_update_relationship_debug_label()`, piggybacking
  `NPCDebug.enabled` (no new F7 row) — floating per-NPC relationship
  readout above the Part-5 name/activity label.
- **NPCDebug.gd**: `log_relationship_event()` for discrete Give/Takeaway
  events (separate from the existing continuous `log_relationship_tick`).

### Docs
`docs/systems/npc/README.md` — new Give/Takeaway section, Relationships'
Future Work item marked done/superseded, three new Testing Checklist
items.

## Files Modified
- `scripts/npc/NPC.gd`
- `scripts/npc/NPCItemUser.gd`
- `scripts/npc/NPCDebug.gd`
- `docs/systems/npc/README.md`
- ~~`scripts/player/InteractionSystem.gd`~~ ⚠️ Player subsystem — deferred
  (section 5), expected in a later pass.

## Verification Checklist (for Brannon's in-editor test)
See `docs/systems/npc/README.md` Testing Checklist items 13–15. Note items
13–14 (Give/Takeaway player prompts) depend on the still-deferred
`InteractionSystem.gd` section 5; the F7 visualizer (item 15) is fully
live now.

---

# Handover — Ghost Collision Regression Fix (Aug 2026)

## What changed this session

### Root cause — Ghost collision regression
The July "strip collision AFTER add_child" fix ran at the wrong tree level:
`GhostModelBuilder.strip_collision()` was called inside `_rebuild_ghost_mesh()`
**before** the ghost root entered the SceneTree. Since `add_child(real_inst)`
on an out-of-tree parent does **not** fire `_ready()`, the strip ran **before**
scripts' own `_ready()` ran — scripts that unconditionally set
`collision_layer = 5` in their `_ready()` silently re-enabled collision
on every ghost spawn. This is why Fix 2's strip "didn't take" — it ran at
the wrong lifecycle point.

**Consequences:** (1) Ghosts of every `PROCEDURAL_PREVIEW_SOURCES` tile
push the player/NPCs (live collision). (2) Grow lights always red/"space
occupied" — the ghost's own live collider sits exactly at the
`_is_position_occupied()` query position, so the ghost blocks itself.
Grow lights had no registry carve-out in `_is_position_occupied_for_tile()`
(unlike Purifier/Light/Shelving), so the physics query always ran for
them and always found the ghost's own collider at the query position.

### Fixes

**Fix 1 — Core: Reorder `_spawn_ghost()`** — `_spawn_ghost()` now:
1. Creates ghost root
2. Sets `visible = false` (prevents 1-frame flash)
2. **Adds ghost root to SceneTree** (`parent.add_child(_ghost)`)
3. **Then** calls `_rebuild_ghost_mesh()` → `build_real_instance()` →
   `strip_collision()` now runs AFTER `add_child(real_inst)` fires
   `_ready()`, so the strip sticks.

**Fix 2 — Hardening: Deferred re-strip + freed-node guard**
- `_rebuild_ghost_mesh()`: added `GhostModelBuilder.strip_collision.call_deferred(real_inst)`
  to catch any script that configures collision via `call_deferred` in
  its `_ready()`.
- `GhostModelBuilder.strip_collision()`: added `is_instance_valid(node)`
  guard so the deferred call is safe if the ghost was freed the same
  frame (tile switch / build-mode exit).

**Fix 3 — Grow Light bucket registry** — preview-only grow lights no
longer register into `GrowLight._bucket_registry`. Moved the
`_is_preview_only` guard **before** the `call_deferred("_register_bucket")`
call in `GrowLight._ready()` (same fix pattern as the chair ghost
invisibility bug).

### Files modified
- `scripts/world/build/GhostPreview.gd` — `_spawn_ghost()` reorder, deferred re-strip
- `scripts/world/build/GhostModelBuilder.gd` — `strip_collision()` freed-node guard
- `scripts/world/power/GrowLight.gd` — preview guard before bucket register
- `docs/systems/build/README.md` — `strip_collision()` bullet updated with
  precise lifecycle rule; Call graph updated with `_spawn_ghost()` order
- `docs/systems/farming/README.md` — note that preview-only grow lights
  no longer register into spatial bucket
- `HANDOVER.md` — this entry

### Verification checklist
1. Ghost collision gone — walk through any furniture ghost, no push.
2. Grow lights placeable — green over open floor, places correctly.
3. Occupancy still works — ghost red over existing object, green over open floor.
4. No flash/regression — rapid tile switching (Chair → Wall → Stove → Grow Light) shows no flash at origin.
5. Bucket fix — with a plant in a tray and NO real grow light, hover a grow-light ghost over tray — plant must NOT register as lit.

---

# Handover — NPC Names + Ask-About Relationship Dialogue (Aug 2026)

## What changed this session

### Names
- **NPC.gd**: `NPC_NAMES` (10-name pool), `_assign_random_name()`
  (collision-avoided against every live NPC), called from `_ready()` when
  `npc_name` is still its "Survivor" default. No persistence changes
  needed — `npc_name` was already saved.

### Ask About (relationship Q&A dialogue)
- **NPC.gd**: `get_relationship_dialogue_line(target_id)` (5 flavor-text
  pools keyed to `get_relationship_label()`), `get_other_npc_topics()`
  (every other live NPC, for building UI buttons).
- **NPCTalkMenuUI.gd**: new "ASK ABOUT" section revealed alongside
  dialogue/commands on Talk — "What do you think of me?" (player) + one
  button per other live NPC by name; answers render in the existing
  dialogue label. `PANEL_H` bumped 760 → 900.
- Docs: `docs/systems/npc/README.md` — new Names & Ask-About section,
  Relationships' dialogue Future Work item marked done (narrower scope),
  Responsibilities bullets updated, new Testing Checklist items.

## Files Modified
- `scripts/npc/NPC.gd`
- `scripts/ui/npc/NPCTalkMenuUI.gd`
- `docs/systems/npc/README.md`

---

# Handover — NPC Relationships Groundwork + Sociability Wiring (Aug 2026)

## What changed this session

### Relationships — data model + proximity baseline
- **NPC.gd**: new stable `npc_id` identity (auto-assigned, persisted,
  collision-safe across save/load via `NPC._register_id()`); new
  `relationships` Dictionary (directional, NPC's own perspective, keyed by
  target `npc_id` or `"player"`, -100..100); `get_relationship()`,
  `get_relationship_label()` (Hostile/Cold/Neutral/Friendly/Close),
  `_adjust_relationship()` (single mutation point — applies sociability
  multiplier + clamp); baseline driver this pass is passive proximity
  (`_tick_relationships()`, 4m XZ range, 5s cadence alongside mood/
  irritability).
- **Sociability trait wired** (previously generated/displayed only):
  `_sociability_trait_mult()`, 0.5x–1.5x, scales every relationship delta.
- **NPCDebug.gd**: `log_relationship_tick()`; `_dump_one()` now includes
  each NPC's relationships with labels.
- **MainWorld.gd**: `_get_npcs_for_save()`/`_restore_npcs()` persist
  `npc_id` and `relationships`.
- Docs: `docs/systems/npc/README.md` — new Relationships section, updated
  Personality/Non-responsibilities sections, new Testing Checklist items.

### Explicitly not done this pass (see README's Relationships → Future Work)
Item giving/taking, crisis-help behavior, command-compliance influence,
personal-space avoidance scaling, gift-dropping, relationship-aware
dialogue, Player→NPC reciprocal value.

---

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