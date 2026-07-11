# Power System

**Read this before opening any power-system script.** This doc + `PowerManager.md`
(same folder) should answer almost everything — only open source files for the
actual internal logic of a function you're changing, and only the specific
file involved. If you find yourself needing something this doc doesn't answer,
that's a doc bug: add the missing detail back after you find it in source.

## Purpose
Simulates the bunker's electrical grid: generators, batteries, breakers/zones,
wires, and every powered device (lights, appliances, terminals). Decides who
has power, who gets shed under overload, and drives the visual/UX state of
every electrical device in the game.

## Responsibilities
- Own the wire graph (nodes/edges), zones (breaker-bounded regions), and their
  adjacency/connectivity.
- Own the grid state machine: `ONLINE → BROWNOUT → OVERLOADED → TRIPPED → OFFLINE`.
- Decide, every solve, which consumers are powered vs. shed, based on priority
  tier (1=critical/never-shed → 5=luxury/first-shed) and available capacity
  (generators + batteries, cross-zone where breakers allow sharing).
- Simulate generator fuel/health drain and battery charge/discharge over time.
- Handle breaker trip/reset (standard + "smart"/upgraded variants) and the
  resulting brownout/isolation behavior.
- Provide the single source of truth every power-related device (lights,
  breakers, generators, batteries, terminals, priority panels) reads from and
  writes to.

## Non-responsibilities
- **Does not own scene placement/build-mode logic** — placing a generator,
  breaker, etc. is `BuildModeController`'s job (`scripts/world/build/`); this
  system only cares about the device once it calls `register_*()`.
- **Does not own UI layout/drawing** — `scripts/ui/power/*.gd` panels call into
  this system's public API and re-draw themselves off its signals; this
  system never touches Control nodes or `_draw()`.
- **Does not own wire *placement* interaction** (player drawing a wire with the
  wire tool) — that's `WireDrawMode.gd`. This system only registers/stores the
  resulting nodes/edges once told to.
- **Does not own save/load** — `SaveManager` (see `docs/systems/world-core/`)
  does not currently persist any power-system state at all (tracked gap, not
  a bug — see Known tradeoffs).

## Files
| File | Lines | Role | Doc |
|---|---|---|---|
| `PowerManager.gd` | ~3600 | Orchestrator + public API + signals + grid state machine + solve entry point + generator/battery tick sim | `PowerManager.md` |
| `PowerGraph.gd` | ~870 | Wire-node/wire-edge CRUD, breaker mid-span splitting, visual tube spawn/reuse | inline below |
| `PowerRegistry.gd` | ~360 | Consumer/generator/battery pure CRUD (register/unregister/getters only — no solver policy) | inline below |
| `PowerSolver.gd` | ~1220 | The 3-pass zone evaluator, component draw/capacity accounting, shed/unshed, sustained brownout, upgraded-breaker self-trip | inline below |
| `BreakerBox.gd` | ~920 | Standard breaker device — E opens settings panel (pass-through toggles, zone swatches, TRIPPED banner + RESTART) | inline below |
| `UpgradedBreakerBox.gd` | ~80 | Extends `BreakerBox` — "smart" breaker, self-trips to isolate zones instead of shared brownout | inline below |
| `GeneratorObject.gd` | ~460 | Generator device — registers with PowerManager, fuel/health sim, exhaust smoke VFX | inline below |
| `BatteryBank.gd` | ~625 | Battery device + its own hand-drawn panel, low-charge flicker VFX | inline below |
| `PowerTerminal.gd` | ~250 | Wall terminal world-object (draws 0W, priority 1 critical, cosmetic-only screen glow) | inline below |
| `PowerPriorityInteractable.gd` | ~55 | Priority-adjustment device trigger (opens `PowerPriorityUI`) | inline below |
| `WireSegment.gd` | ~215 | Wire visual mesh/tube segment | inline below |
| `WireDrawMode.gd` | ~670 | Player wire-drawing tool (build mode only) | inline below |
| `WallLight.gd` | ~430 | Consumer device — sets `power_zone`/`power_priority` before `_ready()` registers; default priority **1** (critical) | inline below |
| `WireGraphBuilder.gd` | ~1510 | Auto-wire perimeter rebuild engine (incremental node/edge diff on chunk dig/expand). Owned/instantiated by `MainWorld`, not part of the PowerManager cluster — see `docs/systems/world-core/README.md` | inline below |
| `DeviceDatabase.gd` | ~110 | **Autoload.** Pure config data: `WATT_RATINGS`, `DEFAULT_PRIORITY_BY_TYPE`, `GENERATOR_TIERS`, `STATE_EMISSION_COLORS` | inline below |

UI panels for this system live in `scripts/ui/power/` (`PowerTerminalUI.gd`,
`PowerPriorityUI.gd`, `GeneratorInspectUI.gd`) — see `docs/systems/ui/README.md`.

## Public API (call these from other systems; everything else is internal)
Get the instance via `get_tree().get_first_node_in_group("power_manager")` cast
to `PowerManager` (typed, no string dispatch anywhere in the repo).

**Consumers:** `register_consumer(id, watts, node, type, zone, priority, active)`,
`unregister_consumer(id)`, `set_consumer_active(id, active)`,
`set_consumer_priority(id, priority)`, `get_consumer_watts/priority/active/
powered/shed/status(id)`.

**Generators:** `register_generator(id, watts, node, is_backup, fuel, health)`,
`unregister_generator(gen_id)`, `set_generator_fuel/health/running/backup(...)`,
`get_generator_fuel/running/is_backup/health/watts(gen_id)`,
`get_generators_status()`.

**Batteries:** `register_battery(id, capacity_wh, node, initial_charge)`,
`unregister_battery(bat_id)`, `set_battery_charge(bat_id, wh)`,
`set_battery_enabled(bat_id, enabled)`, `total_battery_wh()`,
`battery_charge_ratio()`.

**Breakers/zones:** `register_breaker(wire_node_key, scene_node)`,
`unregister_breaker(breaker_id)`, `trip_breaker/reset_breaker(breaker_id)`,
`reset_main_breaker()`, `set_breaker_passthrough(id, pass_battery,
pass_generator)`, `set_breaker_upgraded/get_breaker_upgraded(id)`,
`get_zone_snapshot()`, `get_zone_index_for_key(node_key)`,
`reset_zone_by_index(zone_index)`, `zone_color_at(color_index, alpha)`,
`clear_exhausted_brownout()`.

**Wire graph:** `register_wire_node/unregister_wire_node`,
`register_wire_edge/unregister_wire_edge`, `has_wire_edge(edge_id)`,
`get_wire_nodes/get_wire_edges/get_breakers()`, `get_wire_zones()` /
`get_wire_zones_cached()` / `get_wire_zones_with_colors()`,
`get_zone_node_set_for_key_cached(node_key)`,
`get_edge_world_endpoints/get_edge_load(edge_id)`,
`reconcile_wire_visuals()`, `snapshot_zone_colors/restore_zone_colors(...)`
(used across chunk expand/dig).

**Grid-wide:** `load_ratio()`, `headroom_watts()`, `is_consumer_powered(id)`,
`get_grid_state_string()`, `get_debug_snapshot()`, `get_status()`,
`begin_bulk()/end_bulk()` (batch multiple register/unregister calls, defer
solve until `end_bulk()`), `request_solve()` (force a solve; defers if
`_bulk_depth > 0`).

## Signals produced (all on `PowerManager`)
| Signal | Params | Fires when |
|---|---|---|
| `grid_state_changed` | `new_state: GridState, old_state: GridState` | Any of the 5 grid states change |
| `draw_changed` | `active_watts, capacity_watts, battery_pct` | Every solve |
| `grid_tripped` / `grid_restored` / `grid_offline` | — | Grid enters/leaves TRIPPED/OFFLINE |
| `overloaded_started` / `overloaded_ended` | — | Grid enters/leaves OVERLOADED (the 5s grace window) |
| `consumer_registered` / `unregistered` | `id, watts, priority` / `id` | Device add/remove |
| `consumer_priority_changed` | `id, priority` | Priority changed (after the grace-period timer fires — see Known tradeoffs) |
| `generator_registered/unregistered/started/stopped/fuel_low` | various | Generator lifecycle + low-fuel warning |
| `battery_registered/unregistered/low/state_changed/drained` | various | Battery lifecycle + low-charge/discharge-state changes |
| `wire_edge_registered/unregistered`, `wire_node_registered/unregistered` | ids | Wire graph mutations |
| `breaker_tripped/reset` | `breaker_id` | Breaker trip/reset |

## Signals/events consumed
- `WireDrawMode.wire_placed` / `wire_nodes_connected` — `MainWorld` listens,
  forwards into `WireGraphBuilder`, which calls `PowerManager.register_wire_*`.
- `RockSurround.chunk_deconstructed` / `chunk_restored` — `MainWorld` listens,
  forwards into `WireGraphBuilder._rebuild_auto_wires()` (incremental wire
  graph patch on chunk dig/expand — see `WireGraphBuilder` row above).

## Ownership
`PowerManager` is instantiated by `MainWorld._setup_power_manager()`
(`Node.new()` + `set_script()` + `add_child()`, added to group
`"power_manager"` — not an autoload). It internally creates and owns
`PowerGraph`, `PowerRegistry`, `PowerSolver` instances in its own `_ready()`
(all three take an `_owner: PowerManager` back-reference — see Extension
points). Every device (`BreakerBox`, `GeneratorObject`, `BatteryBank`,
`WallLight`, etc.) finds the manager via
`get_tree().get_first_node_in_group("power_manager")` and registers itself
in its own `_ready()`.

## Persistence
**None currently.** Grid/generator/battery/consumer/wire state is NOT saved
via `SaveManager` — a fresh load starts the grid from scratch. Tracked as a
known gap, not scheduled (see Known tradeoffs).

## Call graph (brief)
```
MainWorld._setup_power_manager() → instantiates PowerManager
Device._ready() → PowerManager.register_*() → PowerRegistry / PowerGraph
Any state-changing call → PowerManager._solve_network() (or request_solve())
  → PowerSolver._evaluate_per_component()
      → _evaluate_pass1_local_surplus()
      → _evaluate_pass2_cross_zone_sharing()
      → _evaluate_pass3_zone_resolution()
  → emits grid_state_changed / draw_changed / consumer_priority_changed / etc.
Device.set_powered(bool) ← called by PowerManager on every consumer after solve
UI panel.open() ← player interacts with device → reads PowerManager getters,
  connects to signals for live updates, calls PowerManager setters on input
```

## Common edits
- **Add a new consumer device type:** implement `set_powered(bool)` on it,
  call `PowerManager.register_consumer(...)` in `_ready()`, add a default
  wattage/priority to `DeviceDatabase.WATT_RATINGS` /
  `DEFAULT_PRIORITY_BY_TYPE`. Nothing else required — it rides the existing
  reachability/shed pipeline automatically.
- **Change shedding behavior for a tier:** `PowerSolver.gd`'s 3-pass
  evaluator — see "Grid mechanics" in `PowerManager.md`.
- **Add a new breaker behavior variant:** extend `BreakerBox.gd` the same way
  `UpgradedBreakerBox.gd` does (inherits its UI/panel/spark-VFX for free).
- **New UI panel for a power device:** put it in `scripts/ui/power/`, call
  `UIFade.fade_in(target)` right after `visible = true` in `open()` (standing
  convention, see `docs/systems/ui/README.md`).

## Forbidden edits
- **Don't zone-signature off perimeter position for graph coloring.** Tried
  and reverted — no perimeter-based signature is stable across chunk
  expansion (expansion moves the perimeter). Current approach is
  always-distinct deterministic greedy graph-coloring with min-node-key
  tiebreaker; colors may shuffle after an expansion but are always valid
  (accepted tradeoff).
- **Don't move `_wire_nodes`/`_wire_edges`/`_consumers`/`_generators`/
  `_batteries` off `PowerManager`.** They're referenced from 100+ scattered
  call sites; `PowerGraph`/`PowerRegistry`/`PowerSolver` reach in via
  `_owner._some_dict` instead (see Extension points). Moving the dicts
  physically was evaluated and explicitly rejected during the Stage 5–8
  extraction.
- **Don't reintroduce string-dispatch** (`get_first_node_in_group(...)` +
  `.call()`/`.has_method()`) for anything with a `class_name` already —
  all ~64 prior call sites were converted to typed refs; this was a real
  cleanup effort, don't regress it.
- **Don't have `PowerGridReconciler.gd`-style polling safety nets.** Deleted
  (Stage 7) — the incremental wire-graph rebuild made it obsolete. If a
  "wires go stale after X" bug reappears, the fix belongs in
  `WireGraphBuilder._rebuild_auto_wires()`'s diff logic, not a new poller.

## Known tradeoffs / tech debt
- No save/load persistence for any power-system state (see Persistence).
- No automated tests — `PowerSolver.gd` is the best candidate once/if a test
  framework (GUT) is ever added, since it was extracted specifically into
  pure value-in/out form.
- `BreakerBox.gd`/`BatteryBank.gd`/`GeneratorObject.gd`'s existing tuned LED
  emission colors were NOT retrofitted onto `DeviceDatabase.
  STATE_EMISSION_COLORS` (added for new devices only) — real regression risk
  on the most-tested system in the project, no functional payoff, so
  deliberately left alone.
- Generator exhaust smoke intensity is NOT scaled to fuel-burn/load rate
  (always on/off at fixed intensity) — would need solver draw-accounting
  wiring, explicitly deferred.
- `PRIORITY_CHANGE_GRACE_SECS` (0.5s) delay on `set_consumer_priority()`'s
  actual grid reset+resolve exists specifically to stop a priority change
  from visibly flashing the grid through a transient state — the displayed
  priority value itself still updates instantly for UI purposes.

## Extension points
- **New solver pass:** add it as a 4th `_evaluate_passN_*` function in
  `PowerSolver.gd`, called from `_evaluate_per_component()`'s orchestrator.
- **New device class needing PowerManager's internal dicts:** follow the
  `_owner: PowerManager` back-reference pattern (`PowerGraph`/`PowerRegistry`/
  `PowerSolver` all do this) rather than moving state — see the extraction
  methodology in `HANDOVER.md`.
- **New zone-sharing behavior across breakers:** `PowerSolver`'s
  `_flood_component_keys`/`_flood_gen_component_keys` BFS helpers already do
  component-wide traversal respecting `pass_battery`/`pass_generator` — reuse
  them rather than writing a new single-zone lookup (a single-zone-lookup bug
  here is exactly what caused the "batteries don't charge across breakers"
  bug, fixed July 2026).
