# Environment System

**Read this before opening `BunkerLayout.gd`, `BunkerPregen.gd`,
`RockSurround.gd`, `LightingDirector.gd`, or `DustMotes.gd`.** Only open the
actual source for the specific function you're changing. See
`docs/systems/graphics/README.md` for the closely-related camera/rendering
settings system (kept separate since it's about the viewport, not the world
geometry).

## Purpose
Builds and manages the physical bunker: the starting pregen room (floor,
walls, pillars, wall lights), the surrounding diggable rock mass players
expand into, and the two passive world-atmosphere systems (fog/vignette
lighting reactor, ambient dust motes).

## Responsibilities
- `BunkerLayout.gd`: thin `GridMap` wrapper — exports `bunker_width`/
  `bunker_depth` (24×18, the single source of truth other systems read this
  from) and the 4 tile-type constants (`FLOOR`/`WALL`/`PILLAR`/`SHELVING`).
- `BunkerPregen.gd`: procedurally stamps the starting bunker's floor/walls/
  pillars/wall-lights via `generate() -> Dictionary` (called once by
  `MainWorld` at startup), retints the shared `MeshLibrary` at runtime
  (`_retint_meshlib()` — never touches the binary `.meshlib` file), and
  spawns starting loot (fuel cans, flashlight).
- `RockSurround.gd`: builds/manages the diggable rock mass surrounding the
  bunker in `chunk_size`-sized chunks; `deconstruct_chunk()`/
  `restore_chunk()` toggle a chunk between solid rock and dug-out open space,
  emitting `chunk_deconstructed`/`chunk_restored` that `MainWorld` forwards
  into `WireGraphBuilder` for incremental wire-graph patching (see
  `docs/systems/world-core/README.md`).
- `LightingDirector.gd`: global fog tint + HUD alarm vignette color, reacting
  ONLY to `PowerManager.grid_state_changed` — never touches individual
  `Light3D` energy (see Non-responsibilities).
- `DustMotes.gd`: static factory (`RefCounted`, not instantiated) —
  `create_beam_dust()`/`create_ambient_dust()` build `GPUParticles3D` nodes
  on demand for flashlight beams and general ambient dust.

## Non-responsibilities
- **Does not dim individual lights.** `LightingDirector` only tints ambient
  fog + the HUD vignette globally; per-`WallLight` brightness is each
  `WallLight`'s own job, driven by the power system's per-zone reachability
  (`set_powered(bool)`). Two global dimmers fighting each other was
  deliberately avoided — see `docs/systems/power/README.md` Forbidden edits.
- **Does not own the wire graph.** `RockSurround` only emits
  `chunk_deconstructed`/`chunk_restored` signals; `MainWorld`/
  `WireGraphBuilder` own the actual incremental wire-node/edge diff (see
  `docs/systems/world-core/README.md`).
- **Does not own build-mode dig-cost/placement UI** — `RockSurround` exposes
  `deconstruct_chunk`/`restore_chunk`/chunk-lookup helpers only;
  `BuildModeController` (`docs/systems/build/README.md`) owns the actual
  player-facing dig confirm/cost flow and calls into these.
- **`BunkerPregen.gd`'s old direct wire-perimeter methods
  (`_wire_perimeter`/`_connect_lights_to_perimeter`) are dead no-op stubs**,
  kept only so stale `call_deferred` references don't crash — actual wiring
  is 100% owned by `MainWorld`/`WireGraphBuilder` now. Don't resurrect logic
  in these stubs; add new wire logic to `WireGraphBuilder` instead.

## Files
| File | Lines | Role |
|---|---|---|
| `BunkerLayout.gd` | ~40 | `GridMap` wrapper — `bunker_width=24`/`bunker_depth=18` source of truth, tile-type constants |
| `BunkerPregen.gd` | ~460 | Procedural starting-bunker stamp (floor/wall/pillar/light), MeshLibrary runtime retint, starting loot spawn |
| `RockSurround.gd` | ~360 | Diggable rock mass — chunked deconstruct/restore, `MultiMesh` rock visuals |
| `LightingDirector.gd` | ~90 | Global fog tint + alarm vignette reactor off `PowerManager.grid_state_changed` |
| `DustMotes.gd` | ~70 | Static `GPUParticles3D` factory (beam + ambient dust) |

## Public API
**`BunkerLayout`** (extends `GridMap`): exported `bunker_width: int = 24`,
`bunker_depth: int = 18` — read directly by `RockSurround`/`BunkerPregen`/
`BuildModeController` as the single source of truth for bunker dimensions.
Tile constants `FLOOR=0`, `WALL=1`, `PILLAR=2`, `SHELVING=3`.

**`BunkerPregen`** (extends `Node3D`, no `class_name`): `generate() ->
Dictionary` (key → spawned `Node3D`, returned to `MainWorld` — called once at
startup, requires `build_controller`/`rock_surround` refs set first).

**`RockSurround`** (extends `Node3D`, no `class_name`): `get_chunk_at_world_pos
(world_pos: Vector3) -> Vector2i`, `is_chunk_active(chunk_id: Vector2i) ->
bool`, `get_chunk_center(chunk_id: Vector2i) -> Vector3`,
`deconstruct_chunk(chunk_id: Vector2i)`, `restore_chunk(chunk_id: Vector2i)`.
Exported: `bunker_width/bunker_depth` (mirrors `BunkerLayout`'s, kept in sync
manually — see Known tradeoffs), `dig_margin: int = 32`, `chunk_size: int =
4`. Constants: `DIG_COST = 15000`, `OFFSET_X = -12.5`, `OFFSET_Z = 4.5` (world
offset of the bunker's rock-carved interior — used directly by
`BunkerPregen`/`WallSnapHelpers`, NOT derived from cell-index math).

**`LightingDirector`** (`class_name LightingDirector`, extends `Node`): no
public methods — purely reactive, everything happens in
`_on_grid_state_changed()`.

**`DustMotes`** (`class_name DustMotes`, extends `RefCounted`, all-static):
`DustMotes.create_beam_dust(spread_deg: float) -> GPUParticles3D`,
`DustMotes.create_ambient_dust(bounds_size: Vector3) -> GPUParticles3D`.
Called directly as static functions (no instance) — e.g.
`Flashlight.gd`'s beam VFX, `MainWorld`'s room-ambient dust.

## Signals produced
| File | Signal | Params | Fires when |
|---|---|---|---|
| `RockSurround.gd` | `chunk_deconstructed` | `chunk_origin: Vector2i` | Player digs out a rock chunk |
| `RockSurround.gd` | `chunk_restored` | `chunk_origin: Vector2i` | A dug chunk is restored (undo, or build-mode chunk expansion) |

`BunkerPregen`/`LightingDirector`/`DustMotes`/`BunkerLayout` produce no
signals.

## Signals/events consumed
- `LightingDirector` connects to `PowerManager.grid_state_changed` in its own
  `_ready()` (must run AFTER `MainWorld._setup_power_manager()` — see
  `docs/systems/world-core/README.md` call graph ordering note).

## Ownership
None of these are autoloads. `BunkerLayout` is a `GridMap` node in the scene
tree (pregen bunker scene). `BunkerPregen`/`RockSurround` are instantiated as
part of the main world scene and wired together by `MainWorld` (`generate()`
needs `rock_surround`/`build_controller` refs assigned before it's called).
`LightingDirector` is instantiated by `MainWorld._setup_lighting_director()`.
`DustMotes` is never instantiated — called as pure static functions from
wherever a dust effect is needed (no ownership at all).

## Persistence
**Jul 2026 — dug chunk state now saved.** `RockSurround.get_dug_chunk_ids_for_save()`/
`restore_dug_chunks()` (SaveManager phase 0, applied first — everything else
that gets restored may depend on the bunker's dug shape). Handles a
mid-session Load correctly too: `restore_dug_chunks()` first restores every
currently-dug chunk back to intact rock, then re-digs exactly the saved set,
reusing `restore_chunk()`/`deconstruct_chunk()` as-is so `chunk_deconstructed`/
`chunk_restored` fire normally and `WireGraphBuilder`/`WaterManager`'s
incremental rebuild reacts exactly as it would to manual digging. **Still
not saved:** pregen bunker contents (loot spawn positions) and lighting
state — a fresh load always starts those from the same original pregen
layout (tracked gap, not scheduled).

## Call graph (brief)
```
MainWorld._ready()
  → BunkerPregen.generate() (once, startup) → stamps floor/walls/pillars/lights,
      _retint_meshlib(), spawns fuel cans + flashlight (call_deferred)
  → _setup_lighting_director() → LightingDirector connects to
      PowerManager.grid_state_changed (AFTER power manager setup)

Player digs / expands (via BuildModeController dig-confirm flow)
  → RockSurround.deconstruct_chunk(chunk_id) / restore_chunk(chunk_id)
  → chunk_deconstructed / chunk_restored emitted
  → MainWorld._on_chunk_deconstructed/_restored()
  → WireGraphBuilder._rebuild_auto_wires() (incremental wire-graph patch —
      see docs/systems/world-core/README.md)
```

## Common edits
- **Change bunker dimensions:** edit `BunkerLayout.gd`'s `bunker_width`/
  `bunker_depth` exports AND `RockSurround.gd`'s matching exports — they are
  NOT automatically synced (see Known tradeoffs), update both.
- **New starting-loot item:** follow `BunkerPregen._spawn_fuel_cans()`'s
  pattern (`call_deferred`, spawn after `generate()` so `get_parent()` is
  valid) — add a new `_spawn_*()` method rather than growing an existing one
  arbitrarily unrelated.
- **New global atmosphere reaction to grid state:** add it to
  `LightingDirector._on_grid_state_changed()` — don't create a second
  `PowerManager.grid_state_changed` listener elsewhere for atmosphere/fog
  purposes.
- **New dust/particle VFX:** add a new static factory function to
  `DustMotes.gd` following `create_beam_dust()`'s shape, rather than
  hand-building `GPUParticles3D` inline at the call site.

## Forbidden edits
- **Don't make `LightingDirector` touch individual `Light3D`/`WallLight`
  energy** — see Non-responsibilities. Per-light dimming is the power
  system's job via `set_powered(bool)`.
- **Don't resurrect logic in `BunkerPregen._wire_perimeter()`/
  `_connect_lights_to_perimeter()`** — dead no-op stubs kept only for crash
  safety, see Non-responsibilities. New wire logic belongs in
  `WireGraphBuilder`.
- **Don't do a full rock/chunk teardown-rebuild on dig/expand** — chunks are
  toggled individually via `deconstruct_chunk`/`restore_chunk`; the June 2026
  grid refactor specifically killed full-teardown wire behavior triggered by
  this same event, don't reintroduce a full-rebuild pattern anywhere in this
  chain (see `docs/systems/world-core/README.md` Forbidden edits).

## Known tradeoffs / tech debt
- No automated tests.
- Pregen loot spawn positions and lighting state aren't saved (see Persistence).
- `bunker_width`/`bunker_depth` are declared as separate `@export` vars on
  BOTH `BunkerLayout.gd` AND `RockSurround.gd` rather than one being the
  single source of truth the other reads — a manual-sync footgun if the
  bunker is ever resized. Not worth the refactor risk to fix opportunistically;
  flag it if a dimension-change bug ever traces back here.
- `MeshLibrary` runtime retint (`BunkerPregen._retint_meshlib()`) duplicates
  the whole library in memory rather than caching a shared darkened copy
  across scene reloads — negligible cost at current scale, not optimized.

## Extension points
- New chunk-triggered systems (beyond wires) should connect directly to
  `RockSurround.chunk_deconstructed`/`chunk_restored`, the same pattern
  `MainWorld` already uses — don't chain off `MainWorld`'s own handlers (see
  `docs/systems/world-core/README.md` Extension points, same rule applies
  here since `RockSurround` is the actual signal source).
