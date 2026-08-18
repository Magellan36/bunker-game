# Build Mode System

**Read this before opening `BuildModeController.gd` or any of its extracted
slices (`BuildMaterials.gd`, `BuildUndoStack.gd`, `GhostPreview.gd`,
`GhostModelBuilder.gd`, `MoveDuplicateTool.gd`, `WallSnapHelpers.gd`,
`WallDrawMode.gd`, `PlacementIndicator.gd`).** Only
open the actual source for the specific function you're changing. UI (the
build toolbar/construct menu) is `BuildModeHUD.gd` — see
`docs/systems/ui/README.md`. Power devices placeable in build mode
(generators, breakers, batteries, terminals, wires) are documented in
`docs/systems/power/README.md`; this doc only covers the generic
placement/construction machinery, not what a placed device does once live.

## Purpose
Everything about placing, moving, duplicating, and removing structures/
devices in the bunker: grid-snapped ghost preview, tile footprint/occupancy
tracking, wall/light/breaker wall-snapping, rock-chunk digging, the undo
stack, and the wire-draw tool's host controller.

## Responsibilities
- `BuildModeController.gd` (~2,013 lines, `class_name`): the orchestrator.
  Owns build-mode enter/exit, active-tool state (Construct/Deconstruct/Move/
  Duplicate/Wire — mirrors `BuildModeHUD`'s tool IDs), the `_placed_objects`
  registry (every player-placed AND pregen/autofill structure, with a
  `player_placed` flag distinguishing player-built from locked level
  geometry), `spawn_structure()`/`remove_placed_object()`, rock-chunk dig
  confirm flow, and instantiates/owns the 5 extracted helper slices below.
- `BuildMaterials.gd`: builds/caches the ghost-preview and world-placed
  `StandardMaterial3D` resources (darkened concrete tint for walls, etc.).
- `BuildUndoStack.gd`: the undo stack (`place`/`remove`/`dig_rock`/`move`
  entry types, `MAX_UNDO = 50`).
- `GhostPreview.gd`: builds/updates the translucent placement-preview mesh
  that follows the cursor. For any tile registered in
  `GhostModelBuilder.PROCEDURAL_PREVIEW_SOURCES`, delegates to
  `GhostModelBuilder` for a real-shaped ghost instead of building a generic
  box — see that file's own section below. Falls back to per-tile
  hand-built box/mesh logic (unchanged, still present) for anything not yet
  registered there.
- `GhostModelBuilder.gd` — **MASTER FILE** for all ghost/preview visuals.
  See "Ghost Model System" section below.
- `WallSnapHelpers.gd`: snaps wall-lights and breakers to the nearest wall
  face within range, and the pregen-vs-player-wall interior-face check used
  to fix the expanded-area wall/breaker snap bug (see `HANDOVER.md`
  history).
- `WallDrawMode.gd`: click-drag-click wall placement tool. See "Wall Draw
  Mode" section below.
- `PlacementIndicator.gd`: small standalone visual indicator node (not part
  of the `_owner`-pattern cluster — simpler, self-contained).

| `PlacementIndicator.gd` | ~35 | Small standalone cursor/placement indicator visual |
 
## Basket
A 12-slot container item (`Basket.gd`, `scenes/world/Basket.tscn`) purchased
from the Farming Shop's Miscellaneous category ($100, `FarmingShopHelper.
SHOP_ITEM_INFO` item_id 20, kind `"scene"`) or spawned via the F7 Admin
Menu's "FARMING" section for testing. Holds up to 12 individual food items (Water Bottle, Food Can,
Farm Produce — all in `basket_storable` group). E-key stashes nearest
`basket_storable` item, G-key opens `BasketUI` (12-slot grid with Drop/Add
to inventory buttons; G, E, and Escape all close it). While held, the
basket is locked upright (`Basket._physics_process()` snaps
`global_transform.basis` to identity every tick) — unlike every other
held item, which keeps whatever tilt it had at pickup. Can be placed on
Shelving like a Crate (`shelf_stack_limit=1`, `shelf_item_type="basket"`).
Contents travel with basket on pickup/drop/shelf-place (items are
reparented as children, hidden/frozen). See `Basket.gd`, `BasketUI.gd`,
`InteractionSystem.gd` for full logic.

## Furniture: Small/Medium Table, Chair, Poster
Three furniture pieces added this session, all in the Construct menu's
Furniture category, all floor/wall-standing procedural `StaticBody3D`
scripts following the same pattern as `Shelving.gd`/`Bed.gd`:

- **`Table.gd`** (tile IDs 27/28, Small/Medium) — one shared script for
  both sizes via `cell_count` (1 or 2, mirrors `FarmingTray.gd`'s
  convention), 4-leg beige model sized off the Farming Tray's own
  footprint numbers.
- **`Chair.gd`** (tile ID 29) — 4-leg seat + backrest, beige. Interactable:
  `[E] Sit` moves the player into `get_seat_transform()` and freezes
  `Player._physics_process()` (same mechanism `SleepOverlay` uses for
  beds); `[E] Stand` (or any WASD movement key — see Player docs) returns
  the player to `get_stand_position()` and re-enables physics. Chair's
  local **+Z** is its true open/seat-facing front — its own front-facing
  ghost arrow needed a `GhostModelBuilder.ARROW_OVERRIDES`-era correction
  before the master arrow-default fix made it moot; see `HANDOVER.md`.
- **`Poster.gd`** (tile ID 31) — wall-mounted, `StaticBody3D` (not
  `Node3D` like `WallLight.gd`) specifically so it has real collision and
  can be targeted by the Deconstruct tool's raycast — see the file's own
  class comment for the reasoning. Wall-snapped via the generic
  `BuildModeController._snap_to_nearest_wall()` helper (not the
  light-specific one), blank beige canvas + dark frame, meant as the
  baseline for future wall decor.

**Aug 2026 — Chair now uses a real GLB model.** `Chair.gd` loads
`assets/models/wooden_chair.glb` (non-uniform scale `Vector3(0.8946,
0.7102, 0.7667)`) instead of building a procedural leg+seat+backrest
mesh. Facing was verified (not assumed) by reading the source file's raw
vertex buffer: the tall backrest vertices cluster on the model's own -Z
side, matching Chair.gd's actual backrest-at--Z convention, so no
rotation was needed. Collision is a separate invisible `BoxShape3D` at
the seat's exact footprint/position, decoupled from the visual mesh
(model's own imported collision is stripped). Same wrapper-translation
handling as the Medium Table fix — see that entry for the general
explanation; this file's node carried its own stray `(-4.1, 0, 0.8)`
offset, corrected the same way via `_recenter_glb_mesh()`.

**Aug 2026 — Medium Table + Build Station now use a real GLB model.**
`Table.gd`'s `cell_count == 2` path and `BuildStation.gd`'s tabletop both
now load `assets/models/wooden_table.glb` (non-uniform scale
`Vector3(0.6333, 0.5946, 0.4638)`, applied in code rather than the
`.import` file since the required correction isn't uniform) instead of
building a procedural leg+top mesh. `cell_count == 1` (Small Table) is
UNCHANGED — still fully procedural, the GLB doesn't fit that footprint.
Collision for both is now a separate invisible `BoxShape3D` matching the
exact same footprint/position the old procedural
`top_mi.create_trimesh_collision()` produced — decoupled from the visual
mesh since the model's own imported collision is always stripped (see
`_strip_model_collision()` in both files). The source asset's single glTF
node carries a baked `(-1.7, 0, 0.7)` scene-placement translation that is
NOT part of the mesh's own shape — every instantiation site explicitly
zeroes `model.position` after `instantiate()` rather than trusting the
import; don't remove that line if this code is ever touched again.

**Correction (same session):** the initial `model.position = Vector3.ZERO`
fix targeted the wrong node — Godot's glTF importer always wraps an
imported scene in a generated root representing the file's "Scene", with
the file's real node(s) (and their own baked transforms) nested one level
below it. `packed.instantiate()` returns that wrapper, so zeroing its
position was a no-op; the actual `(-1.7, 0, 0.7)` offset lived on the
inner mesh node. Both `Table.gd` and `BuildStation.gd` now also call a
new `_recenter_glb_mesh()` helper that finds the real `MeshInstance3D`
descendant and zeros its local position directly. Any future GLB load
site in this codebase should check for this same wrapper layer rather
than assuming the instantiated root is the node carrying the file's real
transform.

## Cooking Pot: Procedural Mesh → 4-State GLB Model (Aug 2026)

`CookingPot.gd` now loads one of 4 real models based on
`count_filled()` (0/1/2/3 ingredients) instead of building a single
static procedural mesh: `pot.glb` (empty) and `pot-stew-1/2/3.glb`
(stew visibly rising as ingredients are added — see
`docs/systems/models/glb-stew-level-generation.md` for how the 3 stew
levels were generated from a single empty/full asset pair). Uniform
scale `0.8315` (unlike Table/Chair's non-uniform fits — the pot's
collision is a rotationally-symmetric `CylinderShape3D`, so there's no
axis-aligned footprint forcing a non-uniform match, and uniform scaling
preserves the real asset proportions with zero distortion). Collision
(`CylinderShape3D`, radius 0.28 / height 0.30) is now built ONCE in
`_build_collision()`, decoupled from the swappable visual child —
unlike Table/BuildStation/Chair, this asset's source nodes had no
wrapper-translation bug, so `_recenter_glb_mesh()` is present but
inert here (kept for consistency). `_update_pot_visual()` is called
from every slot-count-changing site (`try_add_item()` ×2,
`remove_item()`, `serve_dish()`, `restore_saved_state()`) and no-ops
if the fill state hasn't actually changed.

## Light Storage: End Table / Dresser (Aug 2026)
Tile IDs **32** (`End Table`, $60, capacity 2) and **33** (`Dresser`,
$150, capacity 6) in Construct → Furniture — floor-standing hidden-
storage furniture sharing the `LightStorage.gd` base. These two are the
current **reference example of complete new-object wiring** (see the
checklist below): every layer that a new placeable furniture type must
touch is wired here.

- `EndTable.gd` / `Dresser.gd`: mesh-only subclasses of
  `scripts/world/furniture/LightStorage.gd`, each exposing
  `static func build_ghost_mesh()`.
- `BuildModeController.gd`: `TILE_END_TABLE`/`TILE_DRESSER` consts (32/33);
  a shared spawn branch in `spawn_structure()` that mirrors the Shelving
  branch's StorageUI + InteractionSystem injection (so mid-session-placed
  units open the shared UI with no "not injected" warning); both tiles
  added to the `_is_position_occupied_for_tile()` floor-furniture registry
  block and the inner `et !=` filter; `_tile_half_extents()` arms
  `Vector2(0.45, 0.45)` / `Vector2(0.95, 0.48)`.
- `BuildModeHUD.gd`: two data lines in `CATEGORIES["Furniture"]`.
- `GhostModelBuilder.gd`: `PROCEDURAL_PREVIEW_SOURCES` entries for 32/33.
- `GhostPreview.gd`: ghost branches via the static helpers + the
  floor-standing `snap_pos.y = 0.5` elif extended.
- `MainWorld.gd` / `InteractionSystem.gd`: **no changes** — the shared
  `_setup_storage_ui()` group loop and the shared `shelf_ui` ref already
  cover pre-placed units and input-blocking.

**Wiring checklist for a new placeable object** (complete set):
1. `BuildModeController` const + `spawn_structure()` branch (incl. any
   UI/interaction ref injection for storage types).
2. `BuildModeHUD` category data line.
3. `GhostModelBuilder.PROCEDURAL_PREVIEW_SOURCES` entry (if procedural).
4. `GhostPreview` ghost branch + floor/wall snap-Y handling.
5. `_is_position_occupied_for_tile()` / `_tile_half_extents()` if
   floor-standing.
6. Docs + HANDOVER.

Player-side seat/stand wiring (`seated_chair` state, movement-priority
interaction override) lives in `Player.gd`/`InteractionSystem.gd`, not this
system — see those docs / `HANDOVER.md` for that half of the mechanic.

## Trash Can (Aug 2026)
Tile ID **36** (`Trash Can`, $50, capacity 10) in Construct → Furniture.
First floor-standing `LightStorage.gd` subclass with a custom F-slot:
empties a full can into a runtime-only `TrashBag.gd` object handed
straight to the player. See `docs/systems/furniture-items/README.md` for
the full behavior + the hover panel (`TrashBagInfoPanel.gd`, new ambient
UI category).

Wired across the same complete set as End Table/Dresser above:
- `BuildModeController.gd`: `TILE_TRASH_CAN` const (36); `spawn_structure()`
  shared Light-Storage branch extended to a three-way; tile added to the
  `_is_position_occupied_for_tile()` floor-furniture block + inner `et !=`
  filter; `_tile_half_extents()` arm `Vector2(0.28, 0.28)` (1×1 cylinder,
  slightly smaller than a table).
- `BuildModeHUD.gd`: `{ "tile_id": 36, "name": "Trash Can", "price": 50 }`
  in `CATEGORIES["Furniture"]`.
- `GhostModelBuilder.gd`: `PROCEDURAL_PREVIEW_SOURCES` entry for 36.
- `GhostPreview.gd`: ghost branch via `TrashCan.build_ghost_mesh()` + the
  floor-standing `snap_pos.y = 0.5` elif extended.
- `MainWorld.gd`: one `_setup_trash_bag_panel()` call (hover-panel wiring;
  new — End Table/Dresser needed no MainWorld change, this one does).

## Build Station (Aug 2026)
Tile ID **37** — a singleton `BuildStation.gd` object that spawns once at
the starting bunker's geometric center at game start (see
`MainWorld._spawn_initial_build_station()`), **never purchasable**,
**never deconstructable**, movable only via the Move tool. It is the
in-fiction entry point into Build Mode (F1 remains a dev/admin shortcut
alongside it, unchanged); entering drops any held item exactly like an F
press (centralized in `MainWorld._toggle_build_mode()`, so both entry
paths behave identically).

Excluded from the shop/purchase path entirely, exactly like Water Hookup:
- `BuildModeHUD.gd`: **no entry** (never appears in the shop).
- `BuildModeController.gd`: `TILE_BUILD_STATION` const (37);
  `get_placed_objects_for_save()` skips it; deconstruct guard shows
  "Build Station cannot be removed — use Move instead"; tile added to the
  `_is_position_occupied_for_tile()` floor-furniture block + inner `et !=`
  filter; `_tile_half_extents()` arm `Vector2(0.95, 0.48)` (2×1, same as
  Medium Table); `_spawn_placed_object()` has a dedicated branch.
- `GhostModelBuilder.gd`: `PROCEDURAL_PREVIEW_SOURCES` entry for 37.
- `GhostPreview.gd`: ghost branch via `BuildStation.build_ghost_mesh()` +
  the floor-standing `snap_pos.y = 0.5` elif extended.
- `MainWorld.gd`: `_spawn_initial_build_station()` (computes the true
  floor center from `rock_surround` constants, not a literal), injects
  `_main_world`/`build_station`/`interact_prompt` refs.
- `InteractionSystem.gd`: `_process()`'s build-mode branch no longer
  touches the prompt node — `BuildModeController` owns the prompt display
  for the duration of build mode (the Build Station exit prompt; avoids a
  same-frame ownership race between the two `_process()` loops).

Exit interaction is entirely `BuildModeController`-owned (the E-prompt
appears within `BUILD_STATION_EXIT_REACH` = 2.5m of the station during
build mode, E closes build mode). See
`docs/systems/furniture-items/README.md` for the full feature write-up.

## Research Station (Aug 2026)
Tile ID **38** — a singleton `ResearchStation.gd` object that spawns once
at game start alongside the Build Station (2m off the Build Station's
computed center — verify visually in-editor that the two don't overlap),
**never purchasable**, **never deconstructable**, movable only via the Move
tool. `[E] Open Research Station` opens a modal UI (`ResearchStationUI`),
unlike Build Station's game-mode toggle — so there's no
`InteractionSystem` prompt-ownership handoff here; the standard modal
input-blocking applies (`InteractionSystem.research_ui` gates E/F while
open). This pass is object + UI shell only (3 selectable tabs, placeholder
content) — see `docs/systems/research/README.md`.

Excluded from the shop/purchase path entirely, exactly like Water Hookup /
Build Station:
- `BuildModeHUD.gd`: **no entry** (never appears in the shop).
- `BuildModeController.gd`: `TILE_RESEARCH_STATION` const (38);
  `get_placed_objects_for_save()` skips it; deconstruct guard shows
  "Research Station cannot be removed — use Move instead"; tile added to
  the `_is_position_occupied_for_tile()` floor-furniture block + inner
  `et !=` filter; `_tile_half_extents()` arm `Vector2(0.95, 0.48)` (2×1);
  `_spawn_placed_object()` has a dedicated branch.
- `GhostModelBuilder.gd`: `PROCEDURAL_PREVIEW_SOURCES` entry for 38.
- `GhostPreview.gd`: ghost branch via `ResearchStation.build_ghost_mesh()`
  + the floor-standing `snap_pos.y = 0.5` elif extended.
- `MainWorld.gd`: `_spawn_initial_research_station()` + `_setup_research_ui()`
  (creates the UI once, injects `_research_ui` into the station and
  `research_ui` into `InteractionSystem`).

## Shelf Family: Small / Medium / Large (Aug 2026)
Tile IDs **3** (`Medium Shelf`, $75, 10 slots — the former "Shelving"),
**34** (`Small Shelf`, $45, 6 slots), and **35** (`Large Shelf`, $180,
15 slots) in Construct → Furniture. All three share the `Shelving.gd` base
class; `SmallShelf.gd` / `LargeShelf.gd` are ~15-line subclasses overriding
`_init()` only (dimensions, `slots_per_tier`, `shelf_y`). Slot count =
`shelf_y.size() * slots_per_tier`, sized in `_ready()`; the procedural mesh,
slot markers, and `get_ui_config()` are all parametric, so each variant
renders and stores at its own layout (Medium reproduces the previous 10-slot
2-column math and UI `display_order` exactly).

- `Shelving.gd`: new exports `slots_per_tier` (2) and `display_name`
  ("Medium Shelf"); `_build_slot_markers()` keeps the classic 2-column math
  bit-for-bit for `slots_per_tier == 2` and spaces N columns evenly
  otherwise; `get_ui_config()` derives `title`/`slot_count`/`grid_cols`/
  `grid_rows`/`display_order` dynamically.
- `BuildModeController.gd`: `TILE_SMALL_SHELF`/`TILE_LARGE_SHELF` consts
  (34/35); two spawn branches in `spawn_structure()` copied from the
  Shelving branch (incl. StorageUI + InteractionSystem injection); the
  `_is_position_occupied_for_tile()` shelf block now accepts all three
  tiles and its inner filter counts **any** shelf variant as occupying (a
  Small placed beside a Large beside a Medium all block each other, not
  just same-tile matches); `_tile_half_extents()` arms
  `Vector2(0.48, 0.18)` (Small, same depth as Medium) and
  `Vector2(0.77, 0.18)` (Large — widened to 2.00 in Aug 2026, still at
  Medium's `unit_w * ~0.384` ratio).
- `BuildModeHUD.gd`: CATEGORIES line 3 renamed "Shelving" → "Medium Shelf"
  plus data lines for 34/35.
- `GhostModelBuilder.gd`: `PROCEDURAL_PREVIEW_SOURCES` entries for 34/35
  (subclass scripts) and `ARROW_OVERRIDES` `[0.6, 180.0]` for both (same
  procedural-mesh facing as Medium).
- `GhostPreview.gd` / `MoveDuplicateTool.gd`: shelf-family ghost-build and
  `SHELF_PLACEMENT_Y` snap-Y branches extended to all three tiles so
  previews, moves, and duplicates behave identically across variants.

## Wall Draw Mode
Full/Half/Quarter Wall placement is no longer a single-click, single-tile
action — selecting any of the three from Construct → Structure
auto-activates `WallDrawMode.gd`, a click-drag-click sub-mode (same
activate()/deactivate()/handle_input()->bool contract as
`WireDrawMode.gd`/`WaterPipeDrawMode.gd`, but auto-activated by tile
selection rather than a separate toolbar tool).

- **Geometry:** one dynamically-stretched `BoxMesh`/`BoxShape3D` per wall
  (0.3m thick × tier height × drag length), not discrete 1m segments —
  real dimensions confirmed from `tile_set.tscn`'s wall `BoxMesh`, not
  guessed. Texture tiles correctly at any length via the existing
  `_mat_wall` material's triplanar (world-space) UV mapping — no new
  tiling code needed.
- **Direction:** free 360°, not locked to cardinal/8-direction — angle
  taken directly from the cursor, only endpoint *position* snaps to the
  fine grid.
- **Height tiers:** Q/E cycle Full ↔ Half ↔ Quarter at any time, before or
  during a drag. E is NOT used for exit (unlike Wire/Pipe draw modes) to
  avoid the conflict — RMB and ESC both exit/cancel instead, mirroring
  each other exactly (phase 0 = exit tool, phase 1 = cancel current drag).
- **Idle sliver:** before the first click, shows a short (`WALL_CELL_SIZE
  * 0.25`) sliver ghost — same height/thickness as a real wall — marking
  where a drag would start. `MIN_LENGTH` matches this exactly, so a
  click-click with no movement places a wall at sliver length, not a full
  1m segment.
- **Cost:** `price_per_meter × length` — no separate `$/meter` constant,
  reuses each tier's existing Construct-menu price.
- **Save/restore:** `BuildModeController._spawn_stretched_wall()` is the
  single source of truth for real (non-ghost) wall geometry — both live
  placement (`WallDrawMode._confirm_wall()`) and `restore_placed_objects()`
  call it, so a reloaded wall reconstructs at its exact saved length
  (`wall_length` stored via `node.set_meta()`, read back through
  `_get_device_extra()`), not a fixed stub.

## Ghost Model System (`GhostModelBuilder.gd`)
**Master file** for every ghost/preview visual in Build Mode — both the
Construct submenu's spinning preview (`BuildModeHUD.gd`) and the in-world
placement ghost (`GhostPreview.gd`) call into this one file rather than
maintaining separate logic.

- **`PROCEDURAL_PREVIEW_SOURCES`** — the single registry mapping tile_id →
  real script/scene path (relocated here from `BuildModeHUD.gd`, which now
  just calls `GhostModelBuilder.build_real_instance()`). **To add a new
  furniture/device object: one entry here.** That's the entire requirement
  to get a spinning menu preview, a correctly-shaped in-world ghost, and a
  facing arrow, all three, automatically.
- **`build_real_instance()`** — instantiates the real script/scene with
  `_is_preview_only = true` (the pre-existing guard nearly every
  furniture/device script already has), same construction every object
  needed for its menu preview to work in the first place.
- **Preview-guard placement rule (Ghost blanking — Chair, then Grow
  Light):** the `_is_preview_only` guard in an object's `_ready()` must sit
  **after mesh construction** (`_build_mesh()`/`_build_fixture()`) and
  **before side effects** (group membership, registration, power setup).
  Putting it before the mesh call blanked preview instances twice — first
  `Chair.gd` (returned before `_build_mesh()`), then `GrowLight.gd`
  (returned before `_build_fixture()`), leaving the Construct-menu preview
  and in-world ghost invisible either way. The same rule governs every
  renderable object: build the visual first, *then* gate side effects on
  preview status.
- **`strip_collision()`** — call this **only after the instance is inside the SceneTree** — `add_child()` on an out-of-tree parent does not fire `_ready()`, so a strip at that point runs too early and gets undone. `_spawn_ghost()` therefore adds the ghost root to the tree **BEFORE** `_rebuild_ghost_mesh()` runs; do not reorder. An end-of-frame deferred re-strip is also applied (Fix 2) to catch any script that configures collision via `call_deferred` after its `_ready()`.
- **`apply_ghost_tint()`** — recursively recolors every mesh surface under
  a ghost root to translucent green/red, replacing whatever real
  materials/textures the object has. Works for any number of mesh parts.
- **`attach_facing_arrow()`** — universal front-direction indicator.
  Default direction is **180°** (most objects' real "front" is local +Z,
  opposite the arrow geometry's own base direction) — hand-tuned
  `ARROW_OVERRIDES` entries exist only for the handful of tiles that
  genuinely need a different offset (Bed, Shelving, Generators). New
  furniture should NOT need an override unless proven otherwise in-editor.
- **Fallback tiers, in order:** (1) `PROCEDURAL_PREVIEW_SOURCES` real
  script/scene, (2) `build_meshlibrary_instance()` for MeshLibrary-backed
  tiles with no script (Pillar, Floor), (3) whatever tile-specific
  hand-built box/mesh logic already existed in `GhostPreview.gd` before
  this system, left untouched as a safety net for anything not yet
  registered in tier 1 or 2.
- **Does not own what a placed device DOES once live** — a placed generator/
  breaker/battery/terminal registers itself with `PowerManager` in its own
  `_ready()`; `BuildModeController` only handles the placement transaction
  (cost, position, rotation, registry entry) and calls
  `remove_breakers_in_bounds()`/`remove_lights_in_bounds()` on
  deconstruct/dig. See `docs/systems/power/README.md`.
- **Does not draw the build toolbar/construct menu UI** —
  `BuildModeHUD.gd` (`docs/systems/ui/README.md`) owns all Control-node
  drawing; `BuildModeController` only reads its signals
  (`tool_selected`, `construct_item_chosen`, `dig_confirmed`, etc.) and
  calls its setters (`show_hud()`/`set_active_tool()`/etc.).
- **Does not own the wire-drawing INPUT/visual logic itself** — that's
  `WireDrawMode.gd` (physically lives in `scripts/world/power/`, documented
  in `docs/systems/power/README.md`'s Files table since it's part of the
  power-system file cluster). `BuildModeController._setup_wire_draw_mode()`
  only instantiates it as a child node, forwards camera/world/HUD refs into
  it every frame, and forwards `handle_input()` while the Wire tool is
  active.
- **Does not own rock-chunk geometry/visuals** — `RockSurround.gd`
  (`docs/systems/environment/README.md`) owns the actual chunk mesh/
  deconstruct/restore; `BuildModeController` only triggers
  `deconstruct_chunk()`/`restore_chunk()` after the player confirms a dig and
  deducts/refunds `ROCK_DIG_COST`.

## Facing convention (Aug 2026)
- Every object's real "front" is **local +Z** (`DEFAULT_ARROW_Y_ROT = 180.0`
  rotates the arrow geometry, whose base points -Z, to match).
- `ARROW_OVERRIDES` is for placement z-offsets and **intentional** quirks
  (the Bed's 90° side-facing asset) — it is NOT for papering over a
  backwards-baked model. Fix a wrong-facing model at the source (rotate
  the visual instance at load, as `Shelving._load_mesh()` now does), then
  set its override to the standard 180° (or drop it if the z-offset is
  also unnecessary).
- Every construct-menu selection resets the ghost facing to
  `BuildModeController.DEFAULT_ORIENT_INDEX` (index 0 → 0.0° → front = +Z
  = world south). Scroll-wheel rotation then steps 45° relative to that
  reset; wall-snapped tiles (posters/lights/breakers) still recompute
  their own angle every frame, unaffected by the reset.

## Files
| File | Lines | Role |
|---|---|---|
| `BuildModeController.gd` | ~2,013 | Orchestrator — see Responsibilities |
| `BuildMaterials.gd` | ~200 | Ghost/world material builder+cache |
| `BuildUndoStack.gd` | ~250 | Undo stack (`MAX_UNDO=50`) |
| `GhostPreview.gd` | ~450 | Placement ghost mesh + direction-arrow |
| `GhostModelBuilder.gd` | ~240 | Master ghost/preview registry + real-model builder + arrow |
| `MoveDuplicateTool.gd` | ~290 | Move (2-phase) + Duplicate tool |
| `WallSnapHelpers.gd` | ~430 | Wall-light/breaker wall-snapping + pregen interior-face check |
| `WallDrawMode.gd` | ~310 | Click-drag-click stretched wall placement |
| `PlacementIndicator.gd` | ~35 | Small standalone cursor/placement indicator visual |

**NEW (Jul 2026): Preview Scale Normalization & Zoom** — All construct-tab previews
now use a shared normalization constant `PREVIEW_TARGET_SIZE = 0.5667` (1.5× zoom
out from previous 0.85). `_preview_normalize_scale(aabb)` computes a uniform
scale per preview so every item's largest AABB dimension maps to the same
on-screen size — seed packets (~0.14m) and Generator L (~1.85m) now render at
identical on-screen size. Applied to all three preview pools: MeshLibrary
(construct), procedural (Bed/Shelving/Generators/Batteries/etc.), and shop
(Water Case/Can Case/Fuel Can/Crate). Hover-spin (90°/sec) and centering
unchanged.

**NEW (Jul 2026): Combined-AABB Calculation Fix (Rotation Pivot / Centering Bug)**
- **Root cause**: Both construct-tab procedural-preview path and shop-tab imported-model preview path merged raw local-space mesh AABBs without accounting for each mesh's offset from its root node. Most procedural devices position their body mesh above their root (so the root represents the floor-contact point, e.g. GeneratorObject's body sits at local Y = height/2 — see `BOX_SIZE.y * 0.5` convention throughout `scripts/world/power|water/*.gd`). Merging raw local-space AABBs biased the computed "center" toward each object's base. Since `pivot.rotation_degrees` rotates around the pivot's local origin (0,0,0), and the object gets shifted so that miscomputed off-center point sits at that origin, rotating looked like the object orbiting around a point near its feet instead of spinning in place.
- **Fix**: Added static helper `_combined_local_aabb(root: Node3D)` in `BuildModeHUD.gd` that correctly transforms each mesh's AABB into root's local coordinate space using global transforms (`root_inverse * mi.global_transform`). Replaced duplicated buggy logic in both call sites:
  1. Construct-tab procedural preview (`_refresh_submenu_previews`)
  2. Shop-tab imported model preview (`_refresh_shop_previews`)
- Uses GLOBAL transforms (`root_inverse * mi.global_transform`) rather than a mesh's own local `.transform` — correct regardless of how many levels deep a mesh is nested (direct child, or 2-3 levels down inside an imported model), which a single-level-only approach would get wrong.
- Requires `root` to already be inside the SceneTree (`global_transform` must be valid) — call AFTER `add_child()`, never before.
- MeshLibrary-mesh branch untouched (single freshly-created MeshInstance3D with zero parent-imposed offset, so it never had this bug).

**NEW (Jul 2026): Basket** — Added to Furniture category in construct menu:
- `TILE_BASKET` (25) — 12-slot container, $80. Uses procedural mesh (laundry basket silhouette). Opens `BasketUI` on G while held, E-key stashes nearby `basket_storable` items (Water Bottle, Food Can, Farm produce). Can be placed on Shelving like any other pickupable prop (uses `shelf_stack_limit = 1`, `shelf_item_type = "basket"`). Admin spawn entry added for testing.

All 5 helper slices (`BuildMaterials`/`BuildUndoStack`/`GhostPreview`/
`MoveDuplicateTool`/`WallSnapHelpers`) extend `RefCounted` with
`class_name`, take a plain `_owner: BuildModeController` back-reference in
`_init(owner)`, and reach into `BuildModeController`'s own state
(`_placed_objects`, `_undo_stack`, `_ghost`, etc.) rather than owning copies
— same extraction pattern as the power system's
`PowerGraph`/`PowerRegistry`/`PowerSolver` split (Stage 10, July 2026; see
`docs/systems/power/README.md` Forbidden edits for why the pattern exists).
Almost every method on these 5 files is `_`-prefixed (private, called only by
`BuildModeController` itself) — there is effectively no cross-file public API
to document beyond `_init(owner)`.

## Purchased-Prop Spawn Fix (Jul 2026, multi-round)
**Root cause (real, round 5):** The freeze/kinematic dance (`freeze=true` +
`FREEZE_MODE_KINEMATIC` + `await physics_frame` ×2) was the bug — not the
fix. None of the provably-working `spawn_at()` helpers
(`SeedItem`/`BagOfSoilItem`/`FertilizerItem`/`EmptyBagItem`) ever freeze;
they just `add_child()` then set `global_position` once and let gravity take
over. The kinematic freeze was silently interfering with the position write
(the body's transform authority works differently while frozen), causing the
spawned item to default to `(0,0,0)`, get rescued by `MainWorld.
_check_abyss_items()` to the single fixed point `(0, 1.5, 5.5)` (the bunker's
valid-Z clamp from `RockSurround.OFFSET_X/Z = -12.5/4.5` and `depth/width
= 16/8`), and stack there — hence the "items teleport to a single point and
pile up" symptom.

**Rounds 1–4 (superseded):**
1. `call_deferred("_unfreeze_after_spawn")` — fires before physics registers
   the collision shape
2. `await get_tree().physics_frame` ×2 — registration timing theory
3. Raycast to floor (`intersect_ray()`) — called from UI thread, "space is
   locked", silently returned empty → fell back to original spawn point
4. `PhysicsServer3D.body_set_state()` forced transform — patched around the
   freeze without removing it

**Fix (round 5):** `FarmingShopHelper.spawn_scene_settled()` now matches the
working pattern exactly — load scene, `add_child()`, set `global_position`
once, return. No freeze, no raycast, no `physics_frame` waits.
`continuous_cd = true` kept on all 5 `.tscn` files (`WaterCase`/`CanCase`/
`FuelCan`/`TestCrate`/`Basket`) as tunneling insurance (larger/heavier than
seed packets). `FarmingShopHelper.spawn_scene_settled()` is the single
caller/owner for scene-based item spawns; the F7 Admin Menu's
`_spawn_produce()` uses it for admin produce spawns.

**Verification:** Buy/admin-spawn Water Case, Can Case, Fuel Can, Crate,
Basket from two different spots in the bunker — each falls from head height
and lands where you're standing, no flicker, no teleport to `(0, 1.5, 5.5)`.

## Public API
**`BuildModeController`** (`class_name BuildModeController`, extends
`Node3D`): `enter_build_mode()` / `exit_build_mode()`,
`spawn_structure(tile_id: int, pos: Vector3, angle_deg: float,
is_true_pregen: bool = false) -> Node3D` (the ONLY way to create a placed
structure — used for both player placement and pregen/autofill geometry,
`is_true_pregen` distinguishes the original 4 boundary walls for the
stricter interior-face snap check, see `HANDOVER.md` history),
`remove_placed_object(node: Node3D)`, `remove_breakers_in_bounds(x_min,
x_max, z_min, z_max) -> bool` / `remove_lights_in_bounds(...)` (called when a
rock chunk is dug/restored, to clean up devices inside the affected bounds).
Public var `is_active: bool`. Tile-ID constants (`TILE_WALL`, `TILE_PILLAR`,
`TILE_GEN_S/M/L`, `TILE_BREAKER`, `TILE_BREAKER_SMART`, `TILE_BATTERY_S/M/L`,
`TILE_TERMINAL`, `TILE_HEAVY`, `TILE_WIRE` — logical-only, no longer a real
placeable tile, kept for save-compat, etc.) are the shared vocabulary
`BuildModeHUD`'s construct menu also uses (see
`docs/systems/ui/README.md`'s `get_item_price(tile_id)`).

## Signals produced
`BuildModeController.gd` produces no signals of its own — it's primarily a
signal *consumer* (see below). The 5 helper slices produce none either.

## Signals/events consumed
- `BuildModeHUD.tool_selected(tool_id)` → `set_active_tool()`,
  `construct_item_chosen(tile_id)`, `dig_confirmed()` /`dig_cancelled()`,
  `undo_requested()`, `cancel_requested()` (see
  `docs/systems/ui/README.md` for the full signal list).
- `WireDrawMode.wire_placed` → `_push_undo_wire()` (from
  `BuildUndoStack.gd`); `WireDrawMode.wire_nodes_connected` →
  `_on_wire_nodes_connected()`; `WireDrawMode.wire_tool_exit_requested` →
  `_on_wire_tool_exit_requested()` — all connected conditionally via
  `has_signal()` checks in `_setup_wire_draw_mode()`.
- `PowerManager.zone_color_changed` — `BuildModeController._ready()`
  listens directly to repaint world wire tubes instantly on a player
  zone-recolor (see `docs/systems/power/README.md` Signals produced table).

## Ownership
`BuildModeController` is instantiated by `MainWorld._setup_build_mode()`
(a coroutine/one-shot-signal setup, per `docs/systems/world-core/README.md`
call graph) — not an autoload. It creates and owns its 5 `RefCounted` helper
slices in its own `_ready()`. `WireDrawMode` is created as a child `Node` at
runtime (script loaded and attached dynamically, not a static scene child).

## Persistence
**Jul 2026 — `_placed_objects` now saved** via
`get_placed_objects_for_save()`/`restore_placed_objects()` (SaveManager
phase 1) — see `docs/systems/world-core/README.md` Persistence for the full
phase order and the per-device `extra` state shape. `restore_placed_objects()`
calls `clear_all_player_placed()` first (mid-session Load safety — a fresh
boot has nothing to clear) then reuses `_spawn_placed_object()` (the exact
same function `_try_construct()` calls) for every saved entry, so a restored
object goes through an identical code path to a normal purchase, just
without spending cash or pushing an undo entry. `_undo_stack` is still pure
in-memory session state — undo history does not survive a save/load and
is not intended to.

## Call graph (brief)
```
MainWorld._setup_build_mode() → instantiates BuildModeController
BuildModeController._ready()
  → BuildMaterials.new(self), BuildUndoStack.new(self), GhostPreview.new(self),
    MoveDuplicateTool.new(self), WallSnapHelpers.new(self)
  → _setup_wire_draw_mode() → instantiates WireDrawMode child node

Player enters build mode (BuildModeHUD tool_selected / enter_build_mode())
  → active tool = Construct/Deconstruct/Move/Duplicate/Wire
  → Construct: GhostPreview._update_ghost() every frame → click →
      **_spawn_ghost() → add_child(_ghost) → _rebuild_ghost_mesh() → BuildMaterials applies material →
      BuildUndoStack._push_undo_place()**
  → Deconstruct: hover → click → remove_placed_object() /
      RockSurround.deconstruct_chunk() (via dig-confirm flow) →
      BuildUndoStack._push_undo_remove()/_push_undo_dig_rock()
  → Move: MoveDuplicateTool 2-phase select→confirm →
      BuildUndoStack._push_undo_move()
  → Wire: WireDrawMode.handle_input() (forwarded every frame while active)
```

## Common edits
- **New placeable tile/device type:** add a `TILE_*` constant, wire it into
  `BuildModeHUD`'s construct menu (`get_item_price()`, see
  `docs/systems/ui/README.md`), handle it in `spawn_structure()`'s tile-id
  branch, and — if it's a power device — implement `register_*()` with
  `PowerManager` in the new device's own `_ready()` (see
  `docs/systems/power/README.md` Common edits — nothing else in
  `BuildModeController` needs to know about the device's internal behavior).
- **New wall-snappable device (like lights/breakers):** add a
  `_snap_*_to_wall()` method to `WallSnapHelpers.gd` following
  `_snap_light_to_wall()`/`_snap_breaker_to_wall()`'s shape.
- **New tool (beyond Construct/Deconstruct/Move/Duplicate/Wire):** add a new
  `TOOL_*` constant, a new `RefCounted` helper slice (own file) following the
  `_owner: BuildModeController` pattern if the tool's logic is self-contained
  enough — don't bolt more state onto `BuildModeController` itself if it can
  be its own file (per the repo's "no god files" rule).

## Forbidden edits
- **Don't move `_placed_objects`/`_undo_stack`/`_ghost` off
  `BuildModeController`.** Same reasoning as the power system's forbidden
  dict-move rule — these are referenced from many call sites across the
  5 helper slices; they reach in via `_owner._placed_objects` etc. instead.
- **Don't reintroduce the old `_is_pregen`-only wall-snap check.** The fix
  (`_is_true_pregen` tag distinct from the broader `_is_pregen` tag) exists
  specifically so autofill walls in expanded/dug areas snap the same simple
  way player-placed walls do, while the ORIGINAL 4 boundary walls keep the
  stricter interior-face check — see `HANDOVER.md` history for the bug this
  fixed. Don't collapse the two tags back into one.
- **Don't give a new tool/helper slice its own duplicate undo-stack** — all
  undo entries funnel through `BuildUndoStack.gd`'s single `_undo_stack`
  array with a typed entry-kind field, not a per-tool stack.

## Known tradeoffs / tech debt
- No automated tests.
- `_undo_stack` doesn't survive save/load (see Persistence — by design).
- `BuildModeController.gd` at ~2,013 lines is still the largest single file
  in the repo even after the Stage 10 extraction — a plausible future
  candidate for further slicing (e.g. extracting the dig-confirm flow or the
  connectable-dot-overlay logic into their own `_owner`-pattern files) but
  not currently scheduled; only do so opportunistically if a new
  self-contained feature naturally wants its own file (per the "no god
  files" rule), not as a dedicated refactor pass.
- `WIRE_DEBUG` debug constant/prints preserved per the project's
  "keep all debug logging" standing rule — don't strip preemptively.

## Extension points
- Any new self-contained build-mode feature should default to its own new
  `RefCounted` + `_owner` back-reference file in `scripts/world/build/`
  rather than growing `BuildModeController.gd` further — this is the
  established, already-proven pattern in this exact folder.
- New wall-snap-eligible device types extend `WallSnapHelpers.gd` rather than
  duplicating wall-raycast/snap logic inline in `BuildModeController`.
- ~~A non-ghost-preview "buy → spawn near player" tool~~ — **DONE (Jul
  2026).** The Farming toolbar tool (`TOOL_FARMING`) is the first tool that
  skips `spawn_structure()`/ghost-preview entirely — see
  `FarmingShopHelper.gd` (`_owner` slice pattern, same as every other file in
  this folder) and `BuildModeHUD._current_categories()`/`_submenu_source`,
  which generalize the existing two-level Construct submenu to also browse
  `FARMING_SHOP_ITEMS` for a non-ghost shop flow. Reuse this pattern for any
  future non-placement buy-and-spawn tool rather than inventing a third
  submenu data shape. Two new Construct-menu tiles (`TILE_TRAY_SINGLE`/
  `TILE_TRAY_DOUBLE`, category "Farming") and two new Lighting-category tiles
  (`TILE_GROW_LIGHT_NORMAL`/`TILE_GROW_LIGHT_PRO`) went through the normal
  ghost-preview path with no framework changes — see
  `docs/systems/farming/README.md`.
