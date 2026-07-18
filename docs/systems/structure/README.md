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

## Wiring

`MainWorld.gd`:
- `_pillar_registry: Node` instance var.
- `_setup_pillar_registry()` — mirrors `_setup_power_manager()`/
  `_setup_water_manager()`'s exact shape: instances `PillarRegistry.gd`,
  tags it with group `"pillar_registry"` **before** `add_child()` so it's
  discoverable from the moment it enters the tree, no signal wiring needed.
- Called from `_ready()` **before** `_setup_power_manager()`, since the very
  first perimeter solve (`WireGraphBuilder._compute_and_rebuild_wires()`,
  called during power-manager/build-mode bootstrap) needs the registry to
  already exist to push into.

`WireGraphBuilder.gd`:
- `_push_pillar_registry(pillar_positions: Dictionary)` — looks up
  `"pillar_registry"` group, calls `set_all()`. No-ops with a `push_warning`
  if the registry isn't found (purely additive, never a hard dependency for
  the wire/perimeter engine).
- Called from all three solve entry points, right after each one finishes
  building its own local `pillar_positions` dict, immediately before that
  function's `_rebuild_auto_wires(...)` call:
  - `_compute_and_rebuild_wires()` (initial pregen solve)
  - the incremental dig rebuild (inside `_on_chunk_deconstructed()`'s call
    chain)
  - the incremental undo/restore rebuild (inside `_on_chunk_restored()`)

This means `PillarRegistry` is always current after any pregen solve, dig, or
undo — no separate manual refresh needed by consumers.

## Consumers

- `WaterPipeDrawMode.gd`'s pillar-clearance nudge (Part B, pipe paint-along-
  wall UX) reads `PillarRegistry.get_all_positions()` + `PILLAR_CLEARANCE_RADIUS`
  to keep pipe waypoints from clipping pillar collision boxes.
- Future consumers (any build-mode placement check, AI pathing, etc.) should
  read via the registry rather than reaching into `WireGraphBuilder`'s
  internal `pillar_positions` dict, which is function-local and not otherwise
  exposed.
