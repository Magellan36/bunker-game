# Build Mode System

**Read this before opening `BuildModeController.gd` or any of its extracted
slices (`BuildMaterials.gd`, `BuildUndoStack.gd`, `GhostPreview.gd`,
`MoveDuplicateTool.gd`, `WallSnapHelpers.gd`, `PlacementIndicator.gd`).** Only
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
  that follows the cursor (including the direction-arrow overlay for
  directional tiles like wall lights).
- `MoveDuplicateTool.gd`: the Move tool's 2-phase click flow (idle-hover-glow
  → object-selected-ghost-follows-cursor → click-confirms) and the
  Duplicate tool.
- `WallSnapHelpers.gd`: snaps wall-lights and breakers to the nearest wall
  face within range, and the pregen-vs-player-wall interior-face check used
  to fix the expanded-area wall/breaker snap bug (see `HANDOVER.md` history).
- `PlacementIndicator.gd`: small standalone visual indicator node (not part
  of the `_owner`-pattern cluster — simpler, self-contained).

## Non-responsibilities
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

## Files
| File | Lines | Role |
|---|---|---|
| `BuildModeController.gd` | ~2,013 | Orchestrator — see Responsibilities |
| `BuildMaterials.gd` | ~200 | Ghost/world material builder+cache |
| `BuildUndoStack.gd` | ~250 | Undo stack (`MAX_UNDO=50`) |
| `GhostPreview.gd` | ~450 | Placement ghost mesh + direction-arrow |
| `MoveDuplicateTool.gd` | ~290 | Move (2-phase) + Duplicate tool |
| `WallSnapHelpers.gd` | ~430 | Wall-light/breaker wall-snapping + pregen interior-face check |
| `PlacementIndicator.gd` | ~35 | Small standalone cursor/placement indicator visual |

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
**None.** `_placed_objects`/`_undo_stack` are pure in-memory session state —
a fresh load has no player-built structures (tracked gap, same as
power/environment/furniture systems — see
`docs/systems/world-core/README.md` Persistence).

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
      spawn_structure() → BuildMaterials applies material →
      BuildUndoStack._push_undo_place()
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
- Build-mode state isn't saved (see Persistence).
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
