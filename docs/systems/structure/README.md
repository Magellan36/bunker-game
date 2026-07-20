# Structure System

Small, standalone subsystem consolidating logic around the bunker's static
wall/pillar tiles that was previously scattered across the build, water, and
power subsystems. Introduced Jul 2026 (Part A of the combined
pipe/bottle/store-key refactor).

## What this is NOT

- Not a change to the GridMap tile-ID mechanism. `TILE_WALL` (1) and
  `TILE_PILLAR` (2) are still meaningful GridMap item indices, owned by
  `BuildModeController.gd` (`scripts/world/build/BuildModeController.gd`).
- Not turning walls/pillars into scripted `Node` classes. They remain plain
  GridMap cells / MeshLibrary items with a `tile_id` meta tag on their
  collision proxy, exactly as before.
- Not a new Autoload. `PillarRegistry` is a plain scene-tree `Node`, owned and
  instanced by `MainWorld.gd` like `PowerManager`/`WaterManager`, found by
  other systems via `get_tree().get_first_node_in_group("pillar_registry")`.

## Files

### `scripts/world/structure/BunkerStructure.gd`
`class_name BunkerStructure`, `extends RefCounted`. Stateless static utility.

- `BunkerStructure.is_wall_or_pillar(tile_id: int) -> bool` — the single
  source of truth for "is this GridMap tile id a wall or a pillar?". Replaces
  the previously hand-duplicated `tid == TILE_WALL or tid == TILE_PILLAR`
  (and the more dangerous inlined-magic-number `tid == 1 or tid == 2` variant
  that had drifted out of a comment-only "keep in sync" convention) across 8
  call sites:
  - `BuildModeController.gd` — lines ~1495, 2199, 2297, 2380
  - `WallSnapHelpers.gd` — lines ~131, 231, 463
  - `WaterHookup.gd` — line ~288 (this was the fragile inlined-int version;
    fixed as part of this migration since `BunkerStructure` is a stateless
    static helper and safe to reference even from a build-mode-independent
    file like `WaterHookup.gd`)

Since `class_name` is declared, no `preload()`/`load()` is needed anywhere —
`BunkerStructure.is_wall_or_pillar(...)` is globally callable.

### `scripts/world/structure/PillarRegistry.gd`
`class_name PillarRegistry`, `extends Node`. Holds the current set of pillar
world positions (`key -> Vector3`, same `"wx_key,wz_key"` string key format
`WireGraphBuilder.gd` already uses internally).

- `set_all(positions: Dictionary)` — replaces the full position set.
- `get_all_positions() -> Dictionary` — read-only accessor (returns a
  duplicate; don't rely on mutating it back into the registry).
- `PILLAR_CLEARANCE_RADIUS: float = 0.34` — verified (not guessed) against the
  real pillar physics footprint: `BuildModeController._tile_half_extents()`
  defines `TILE_PILLAR`'s collision half-extent as `Vector2(0.24, 0.24)` (a
  0.48×0.48 box). The worst-case corner-to-center distance is
  `sqrt(0.24² + 0.24²) ≈ 0.339`, so `0.34` is the smallest circumscribed-circle
  radius that guarantees no clipping regardless of the angle a pipe leg
  approaches from. This replaces an earlier `0.5` placeholder, which was safe
  but overly conservative (pushed pipe legs further from pillars than
  actually necessary).

### `scripts/world/structure/WallPerimeterRegistry.gd` (Jul 2026 — wall-locked pipe routing)
`class_name WallPerimeterRegistry`, `extends Node`. Sibling to `PillarRegistry`
above, same ownership shape — kept as its own file rather than merged in
since pillars are point corners while wall segments carry position AND
adjacency, different enough data shape to keep separate (matches this
system's own narrow-scope-per-registry principle).

- `set_all(segments: Dictionary)` — replaces the full wall-segment set
  (same `"wx_key,wz_key" -> {"pos": Vector3, ...}` shape as
  `WireGraphBuilder`'s own `boundary_edges`) and rebuilds adjacency.
- `get_nearest_segment_key(pos: Vector3) -> String` / `get_segment_pos(key) -> Vector3`
  / `is_empty() -> bool`.
- `find_path_along_wall(from_key: String, to_key: String) -> Array` — BFS
  shortest hop-count path along the perimeter, returns `Array[Vector3]`
  waypoints or `[]` if no path exists (fails safe — caller falls back to
  freeform routing, never crashes).
- `ADJACENCY_RADIUS: float = 1.1` — verified against `WireGraphBuilder`'s own
  boundary-edge math: consecutive segments along a straight wall run are
  exactly 1.0m apart; the two segments meeting at a convex corner are
  ~0.707m apart (0.5 diagonal). 1.1 catches both with margin while staying
  well under 2.0 (minimum gap between two unrelated walls, e.g. opposite
  sides of a single-cell-wide corridor), so it can never wrongly bridge
  across open floor space.
- Stored positions use `WireGraphBuilder`'s own electrical `PLACEMENT_Y`
  (2.0), NOT water's ceiling height — consumers must re-project to their own
  working height before use (see `WaterPipeDrawMode.WATER_CEILING_Y`).

## Wiring

`MainWorld.gd`:
- `_pillar_registry: Node` / `_wall_perimeter_registry: Node` instance vars.
- `_setup_pillar_registry()` / `_setup_wall_perimeter_registry()` — mirror
  `_setup_power_manager()`/`_setup_water_manager()`'s exact shape: instance
  the registry script, tag it with group `"pillar_registry"` /
  `"wall_perimeter_registry"` **before** `add_child()` so it's discoverable
  from the moment it enters the tree, no signal wiring needed.
- Both called from `_ready()` **before** `_setup_power_manager()`, since the
  very first perimeter solve (`WireGraphBuilder._compute_and_rebuild_wires()`,
  called during power-manager/build-mode bootstrap) needs both registries to
  already exist to push into.

`WireGraphBuilder.gd`:
- `_push_pillar_registry(pillar_positions: Dictionary)` /
  `_push_wall_perimeter_registry(boundary_edges: Dictionary)` — look up
  their respective group, call `set_all()`. No-op with a `push_warning` if
  the registry isn't found (purely additive, never a hard dependency for
  the wire/perimeter engine).
- Both called from all three solve entry points, right after each one
  finishes building its own local `pillar_positions`/`boundary_edges` dicts,
  immediately before that function's `_rebuild_auto_wires(...)` call:
  - `_compute_and_rebuild_wires()` (initial pregen solve)
  - the incremental dig rebuild (inside `_on_chunk_deconstructed()`'s call
    chain)
  - the incremental undo/restore rebuild (inside `_on_chunk_restored()`)

This means both registries are always current after any pregen solve, dig,
or undo — no separate manual refresh needed by consumers.

## Consumers

- `WaterPipeDrawMode.gd`'s pillar-clearance nudge (Part B, pipe paint-along-
  wall UX) reads `PillarRegistry.get_all_positions()` + `PILLAR_CLEARANCE_RADIUS`
  to keep pipe waypoints from clipping pillar collision boxes.
- `WaterPipeDrawMode.gd`'s wall-locked routing default (Jul 2026 —
  `_trace_wall_locked_path()`, see `docs/systems/water/README.md` Known
  tradeoffs) reads `WallPerimeterRegistry.find_path_along_wall()` to route an
  open-floor pipe destination along the wall perimeter instead of a raw
  diagonal-shortest cut across the room.
- Future consumers (any build-mode placement check, AI pathing, etc.) should
  read via the appropriate registry rather than reaching into
  `WireGraphBuilder`'s internal `pillar_positions`/`boundary_edges` dicts,
  which are function-local and not otherwise exposed.
