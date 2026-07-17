# World Core

**Read this before opening `MainWorld.gd`, `WorldManager.gd`, `SaveManager.gd`,
or `WireGraphBuilder.gd`.** Only open the actual source for the specific
function you're changing.

## Purpose
Bootstraps and wires together every other system into a running scene:
instantiates/connects the power grid, HUD, inventory, build mode, lighting,
dust VFX, and world pregen. Also owns global (cross-scene) state and the
generic save/load system.

## Responsibilities
- `MainWorld.gd`: scene `_ready()` bootstrap — instantiate `PowerManager`,
  `LightingDirector`, debug overlay, shelf UI, ambient dust, build mode;
  forward chunk dig/expand signals into the wire-graph rebuild; hold/expose
  `cash` (`spend_cash`/`add_cash`/`get_cash`/`set_cash`).
  Delegates the actual auto-wire perimeter rebuild to `WireGraphBuilder.gd`.
- `WireGraphBuilder.gd`: incremental wire-graph rebuild on chunk dig/expand —
  diffs old vs. new boundary, patches only the changed nodes/edges
  (never a full teardown), breaker-aware ring routing, player-wire culling.
- `WorldManager.gd`: **autoload.** Tiny — current scene name + a
  `player_data` dict for cross-scene state, `change_scene(path)` helper.
- `SaveManager.gd`: **autoload.** Generic field-registry save/load system —
  any system can plug a getter/setter pair into it under a string key.

## Non-responsibilities
- **Does not own the power grid's internal logic** — `MainWorld` only
  instantiates `PowerManager` and reacts to its `grid_tripped`/`grid_restored`/
  `grid_offline` signals (camera trauma, HUD alerts). All grid logic lives in
  `docs/systems/power/`.
- **Does not own build-mode placement logic** — `MainWorld._setup_build_mode()`
  only instantiates `BuildModeController` and wires its signals; placement/
  ghost/undo logic is `BuildModeController`'s own system (not yet migrated to
  a `docs/systems/` doc — see `PROJECT_SUMMARY.md`).
- **Does not own individual light dimming** — `LightingDirector` (instantiated
  here) only tints ambient fog + the HUD alarm vignette globally; per-light
  energy is each `WallLight`'s own job driven by the power system's per-zone
  reachability. Two global dimmers would fight each other — deliberately not
  done, see the power system doc's "Forbidden edits."

## Files
| File | Lines | Role |
|---|---|---|
| `MainWorld.gd` | ~940 | Scene bootstrapper — see Responsibilities |
| `WireGraphBuilder.gd` (physically in `scripts/world/power/`) | ~1510 | Auto-wire perimeter rebuild engine, owned/instantiated by `MainWorld` |
| `WorldManager.gd` | ~20 | Autoload — global scene/player state |
| `SaveManager.gd` | ~155 | Autoload — generic save/load field registry |

## Public API
**`MainWorld`** (typed `class_name MainWorld`):
`spend_cash(amount) -> bool`, `add_cash(amount)`, `get_cash() -> int`,
`set_cash(value)`. Also exposes `_compute_and_rebuild_wires()` (startup) and
the chunk-signal handlers `_on_chunk_deconstructed(origin)` /
`_on_chunk_restored(origin)` which forward into `WireGraphBuilder`.

**`WorldManager`** (autoload, access as `WorldManager.<member>`):
`change_scene(path: String)`, `current_scene_name: String`,
`player_data: Dictionary`.

**`SaveManager`** (autoload, access as `SaveManager.<method>`):
`register_field(key: String, getter: Callable, setter: Callable)`,
`unregister_field(key: String)`, `slot_exists(slot: int) -> bool`,
`get_slot_info(slot: int) -> Dictionary`, `save_game(slot: int) -> bool`,
`load_game(slot: int) -> bool`.

## Signals produced
- `WorldManager.scene_changed(scene_name: String)`.
- `MainWorld` has no signals of its own — it's a signal *consumer* for
  almost everything (power, wire tool, chunk dig/expand).

## Signals/events consumed (by `MainWorld`)
- `PowerManager.grid_tripped` → `_on_grid_tripped()` (camera trauma + HUD alert).
- `PowerManager.grid_restored` → `_on_grid_restored()`.
- `PowerManager.grid_offline` → `_on_grid_offline()`.
- `WireDrawMode.wire_nodes_connected` → `_on_wire_nodes_connected(...)`.
- `WireDrawMode.wire_placed` → `_on_player_wire_placed(...)`.
- `RockSurround.chunk_deconstructed` → `_on_chunk_deconstructed(origin)` →
  forwarded into `WireGraphBuilder`.
- `RockSurround.chunk_restored` → `_on_chunk_restored(origin)` → forwarded
  into `WireGraphBuilder`.

## Persistence
`SaveManager` has 7 fields registered, applied on load in ascending **phase**
order (`register_field(key, getter, setter, phase)` — world reconstruction is
order-dependent, e.g. placed objects must exist before wires try to
reconnect to them):
- Phase 0 — `dug_chunks` (`RockSurround.get_dug_chunk_ids_for_save()`/
  `restore_dug_chunks()`)
- Phase 1 — `placed_objects` (`BuildModeController.get_placed_objects_for_save()`/
  `restore_placed_objects()`) — every player-placed device, each entry
  carrying `tile_id`/`pos`/`angle_deg`/`price` PLUS an embedded per-device
  `extra` dict (generator fuel/health/backup/running, battery charge/enabled,
  breaker tripped/pass-through, consumer priority/active, water sink/
  dispenser priority/rate/fill/on). Devices apply their `extra` state via a
  `call_deferred` after spawning, since PM/WM registration itself is deferred
  one level inside each device's own `_ready()`.
- Phase 2 — `player_wires` (`MainWorld.get_player_wires_for_save()`/
  `restore_player_wires()`) — player-placed power wire endpoints only; the
  auto-generated perimeter wiring regenerates itself once `dug_chunks`
  restores (phase 0), so it is deliberately NOT persisted separately.
- Phase 3 — `water_pipes` (`WaterManager.get_pipe_network_for_save()`/
  `restore_pipe_network()`) — pipe-owned graph nodes (`corner`/`pipe_joint`)
  and edges only; `hookup`/`endpoint` nodes belong to devices restored in
  phase 1.
- Phase 4 (last) — `player_position`, `cash`, `game_elapsed` — applied once
  the whole world above already exists.

Saves to `user://save_slot_<1|2|3>.json`. Loading a save silently skips any
key that isn't currently registered (safe for adding new fields later — no
migration needed for old saves, they just won't have the new key populated).
Mid-session Load (not just fresh-boot Load) is supported: `restore_placed_objects()`
calls `clear_all_player_placed()` first and `restore_pipe_network()` calls
`clear_water_pipes()` first, so a Load while devices/pipes already exist from
the current session tears them down before rebuilding from the save.
**Known gap:** zone name/color overrides (`ZoneCustomization.gd`) are
best-effort only — not explicitly re-verified across a save/load round trip
this pass.

## Call graph (brief)
```
MainWorld._ready()
  → _setup_power_manager()       → PowerManager instantiated, group "power_manager"
  → _setup_lighting_director()   → LightingDirector instantiated, connects to
                                    PowerManager.grid_state_changed (must run
                                    AFTER power manager setup)
  → _setup_debug_overlay(), _setup_shelf_ui(), _setup_lighting(),
    _setup_ambient_dust(), _setup_build_mode() (coroutine, one-shot signal)
  → _compute_and_rebuild_wires()  → WireGraphBuilder (startup wire graph)

RockSurround.chunk_deconstructed/restored
  → MainWorld._on_chunk_deconstructed/_restored
  → WireGraphBuilder._rebuild_auto_wires() (incremental diff, not full teardown)
```

## Common edits
- **New autoload:** write the script, but DO NOT hand-edit `project.godot`'s
  `[autoload]` section — Brannon registers new autoloads himself via
  Project Settings > Autoload in the editor (see the class-cache gotcha in
  `HANDOVER.md` — the editor owns that section and can silently overwrite
  hand-edits).
- **New global cross-scene state:** add it to `WorldManager.player_data` or
  a new typed field on `WorldManager` directly — don't create a second
  global-state autoload.
- **New persisted field:** call `SaveManager.register_field(key, getter,
  setter)` from the owning system's own `_ready()` — don't add fields
  directly inside `SaveManager.gd` itself.
- **New chunk-dig-triggered rebuild logic:** goes in `WireGraphBuilder`, not
  `MainWorld` — `MainWorld`'s handlers only forward the signal.

## Forbidden edits
- **Don't do a full wire-graph teardown/rebuild on chunk dig/expand.** The
  wire graph is durable state; a dig is a local edit (add/remove only the
  perimeter nodes/edges that changed via a boundary diff). Distant
  lights/generator/player wires must never disconnect. This was a whole
  refactor project (June 2026) specifically to kill full-teardown behavior —
  don't reintroduce it.
- **Don't add a second global light-dimming system** off `grid_state_changed`
  — see Non-responsibilities above.

## Known tradeoffs / tech debt
- No automated tests.
- Zone name/color overrides (`ZoneCustomization.gd`) aren't explicitly
  re-verified across save/load (see Persistence known gap).
- `BuildModeController.gd` (2000+ lines) is a possible future extraction
  candidate but not part of any current plan — see `PROJECT_SUMMARY.md`.

## Extension points
- New systems that need to react to chunk dig/expand should connect to
  `RockSurround.chunk_deconstructed`/`chunk_restored` directly (same pattern
  `MainWorld` uses), not chain off `MainWorld`'s own handlers.
- New `_setup_*()` bootstrap steps in `MainWorld._ready()` should follow the
  existing `Node.new()` + `set_script()` + `add_child()` pattern used by
  `_setup_power_manager()`/`_setup_lighting_director()`.
