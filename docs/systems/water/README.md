# Water System (Phase 1 — Groundwork: Hookup + Pipes)

**Read this before opening any `scripts/world/water/*` file.** Only open the
actual source for the specific function you're changing.

## Purpose
The wall-mounted water hookup and the pipe-placement/routing tool. This is
Phase 1 of a multi-phase system — **explicitly NOT in scope yet**: water
purifiers, pumps, any real water resource/consumption simulation, a water
dashboard/terminal UI, or T-split branching (the data model supports it
later; the placement tool doesn't build it yet).

## Responsibilities
- Own the water plumbing graph (nodes/edges) and connectivity (BFS
  reachability from a hookup outward) — `WaterGraph.gd`/`WaterManager.gd`.
- The wall-mounted hookup device, including auto-tracking whichever wall is
  currently the outermost in its recorded facing direction as the player digs
  further out — `WaterHookup.gd`.
- The pipe placement tool (wall-hugging, magnetic-but-resistible wall snap,
  auto-elbow-insertion at corners) — `WaterPipeDrawMode.gd`.
- Static pipe/corner visuals, always visible (never hidden outside build
  mode, unlike wires) — `WaterPipeSegment.gd`/`WaterPipeElbow.gd`.
- A rudimentary test endpoint that proves the plumbing works end to end —
  `WaterTestSink.gd`.

## Non-responsibilities
- **Not wired into PowerManager/PowerGraph in any way.** This is a separate,
  standalone system — its own subfolder, its own manager, its own placement
  tool. It follows the SAME architectural patterns the power system uses
  (topology/orchestrator split, `MainWorld`-owned-node-in-a-group convention)
  but shares no runtime dependency with it. A future device that needs BOTH
  systems (e.g. `water_purifier`, which draws electricity AND water) should
  hold independent references to both managers — neither manager should ever
  reference the other.
- **No flow/pressure simulation.** The only "simulation" this phase has is
  BFS connectivity (`is_reachable_from_hookup()`). A future `WaterSolver.gd`
  (mirroring `PowerSolver.gd`) would slot in the same way if flow/pressure is
  ever added — see Extension points.
- **No dashboard/terminal UI.** `scripts/ui/water/` is intentionally empty —
  add a panel only once a real water-consuming device justifies one (same
  reasoning `PowerTerminalUI` exists for the power system).
- **Does not reuse `WallSnapHelpers.gd`'s existing snap functions directly**
  (`_snap_light_to_wall`/`_snap_breaker_to_wall` stay build-mode-only,
  untouched) — the water system either calls the new generic
  `WallSnapHelpers._snap_to_nearest_wall()` (added alongside, for
  hookup placement/move, which DOES go through `BuildModeController`) or
  raycasts independently (`WaterHookup.reposition_to_outer_wall()`,
  `WaterPipeDrawMode._find_wall_hug_point()` — deliberately self-contained,
  no build-mode dependency, so the water system stays standalone).

## Files
| File | Role |
|---|---|
| `WaterGraph.gd` | Node/edge registry + BFS connectivity. `RefCounted`, `_owner: WaterManager` back-reference (same pattern as `PowerGraph`/`PowerRegistry`/`PowerSolver` — see `docs/systems/power/README.md`). |
| `WaterManager.gd` | Orchestrator + public API. Forwards to `WaterGraph`. Also holds the hookup registry + dispatches boundary-change reposition events. |
| `WaterHookup.gd` | The wall-mounted source device. Wall-snapped placement, never deletable, auto-tracks the outermost wall in its facing direction as the bunker expands. |
| `WaterPipeSegment.gd` | Visual for one straight placed pipe. **Always visible** (see Known tradeoffs). |
| `WaterPipeElbow.gd` | Corner-joint visual, spawned automatically at a corner crossing. A REAL graph node (role `"corner"`), not just cosmetic — see Extension points. |
| `WaterPipeDrawMode.gd` | The placement tool. **Uses the plan's own pre-approved FALLBACK interaction model, not the full single-drag paint — see its own file-header comment and Known tradeoffs below.** |
| `WaterTestSink.gd` | Rudimentary test endpoint — the acceptance test for this whole phase (place a hookup, route a pipe around a corner, confirm the sink reports CONNECTED). |

## Public API
Get the instance via
`get_tree().get_first_node_in_group("water_manager")` cast to `WaterManager`.

`register_node(pos, role) -> String` / `unregister_node(key)` /
`has_water_node(key) -> bool` (NOT `has_node` — that name collides with
`Node`'s own built-in method since `WaterManager extends Node`; this was
caught by the headless compile check during this pass, see Known
tradeoffs) / `get_node_data(key) -> Dictionary` / `register_edge(key_a,
key_b) -> String` / `unregister_edge(edge_id)` / `has_edge(edge_id) -> bool` /
`get_nodes() -> Dictionary` / `get_edges() -> Dictionary` /
`is_reachable_from_hookup(node_key) -> bool` (the one piece of "simulation"
this phase needs) / `WaterManager.make_node_key(pos) -> String` (static).

`register_hookup(hookup)` / `unregister_hookup(hookup)` — plain node-ref
list (separate from the graph registry above) so boundary-change events can
call each hookup's own `reposition_to_outer_wall()` directly.

`WaterHookup.get_facing_dir() -> Vector3` (derived live from
`rotation_degrees.y`, not cached), `WaterHookup.reposition_to_outer_wall()`,
`WaterHookup.update_graph_node_position()` (re-keys the graph node after a
position change — called by both the boundary-tracking reposition AND a
manual Move).

## Signals produced
None yet — this phase has no dashboard UI to drive with signals.
`WaterPipeDrawMode` produces `pipe_placed(seg_nodes, edge_ids, cost)` and
`pipe_tool_exit_requested()` (mirrors `WireDrawMode`'s shape), consumed by
`BuildModeController`.

## Signals/events consumed
- `RockSurround.chunk_deconstructed` / `chunk_restored` — the SAME
  boundary-change event `WireGraphBuilder` already reacts to for the wire
  graph's incremental rebuild. `MainWorld._on_chunk_deconstructed/_restored`
  forwards into `WaterManager` (deferred one frame, after the wall
  rebuild finishes) alongside its existing `_wire_builder` forward — see
  `docs/systems/world-core/README.md`. This is a deliberate reuse of an
  existing mechanism, not a new poller (per the plan's explicit instruction).

## Ownership
`WaterManager` is instantiated by `MainWorld._setup_water_manager()` —
`Node.new()` + `set_script()` + `add_child()`, added to group
`"water_manager"`, same shape as `_setup_power_manager()`. NOT an autoload
(per-world-instance state). `WaterHookup`/`WaterTestSink` are placed via
`BuildModeController._spawn_placed_object()` like any other build-menu
device. `WaterPipeDrawMode` is instantiated as a child `Node` of
`BuildModeController` (`_setup_water_pipe_draw_mode()`), same pattern as
`WireDrawMode`.

## Persistence
**None.** Same known gap as every other system in this project — see
`docs/systems/world-core/README.md` Persistence.

## Call graph (brief)
```
MainWorld._setup_water_manager() → instantiates WaterManager

BuildModeController (TOOL_WATER_PIPE=6, TILE_WATER_HOOKUP=17, TILE_WATER_SINK=18)
  → _setup_water_pipe_draw_mode() → instantiates WaterPipeDrawMode child node
  → _spawn_placed_object(TILE_WATER_HOOKUP/_SINK, ...) → WaterHookup/WaterTestSink
      → _ready() → call_deferred("_register_deferred") → WaterManager.register_node()

Player digs/expands (RockSurround.chunk_deconstructed/chunk_restored)
  → MainWorld._on_chunk_deconstructed/_restored (existing _wire_builder forward, UNCHANGED)
  → NEW: WaterManager._on_chunk_deconstructed/_restored → call_deferred("_reposition_all_hookups")
  → each WaterHookup.reposition_to_outer_wall() → raycast along facing_dir → update_graph_node_position()

Player uses Pipe tool (TOOL_WATER_PIPE)
  → WaterPipeDrawMode.handle_input() → _try_pick_source() (phase 0) →
    _try_confirm_segment() (phase 1) → WaterManager.register_node/register_edge
    → spawns WaterPipeSegment(s) + WaterPipeElbow (if a corner was crossed)
```

## Common edits
- **New pipe-connectable device (beyond the test sink):** register a
  `"endpoint"` (or other) role node via `WaterManager.register_node()` in
  `_ready()` (deferred, same pattern `WaterTestSink`/`WaterHookup` use) —
  `WaterPipeDrawMode._get_nearest_water_node()` will find it automatically
  as a valid source/destination, no registry to update.
- **Real water-consuming device (`water_purifier`/`water_pump`):** follow the
  `DeviceDatabase`-driven pattern the power system uses (both already have
  wattage/priority entries in `DeviceDatabase.gd`, unused) — hold independent
  `PowerManager`/`WaterManager` refs, don't couple the two managers.
- **T-split branching:** since corners/joints are already real graph nodes,
  this is "let `WaterPipeDrawMode._try_pick_source()` start a new run from an
  existing mid-chain node" — it already does this for ANY existing node
  (hookup, joint, or corner), so a T-split may already partially work by
  simply drawing a second pipe from an existing joint; verify before
  assuming new code is needed.

## Forbidden edits
- **Don't wire this system into `PowerManager`/`PowerGraph` directly.** See
  Non-responsibilities — a dual-dependency device holds two independent
  manager references, the two managers never reference each other.
- **Don't give `WaterPipeSegment`/`WaterPipeElbow` the `WireSegment`
  hidden-outside-build-mode / `"wire_segment"`-group toggle pattern.** Pipes
  are always visible by explicit design (see `WaterPipeSegment.gd` file
  header) — this was called out explicitly in the groundwork plan precisely
  to prevent copy-pasting that part of the wire pattern by habit.
- **Don't name a `WaterManager` method `has_node`.** `WaterManager extends
  Node`, and `Node` already defines `has_node(NodePath) -> bool` — an
  incompatible override is a parse error (hit and fixed during this pass,
  see `has_water_node()` in Public API above). `WaterGraph.has_node()` itself
  is fine (`RefCounted`, no clash) — only the `WaterManager` forwarding
  wrapper needed the different name.

## Known tradeoffs / tech debt
- **`WaterPipeDrawMode` uses the plan's own pre-approved FALLBACK
  interaction model** (one wall-hugging segment per click, up to the next
  corner, with auto-elbow-insertion), not the full single continuous-drag
  "paint the whole run in one click" experience the plan describes as its
  primary vision. Flagged explicitly per the plan's own instructions — full
  multi-segment live-preview-and-confirm was judged too complex to
  responsibly build and verify with zero in-editor testing available this
  pass (headless compile-check only). **Upgrading to the full paint
  experience is the clear, expected next step for this tool** — not
  currently scheduled, do it as its own isolated pass.
- **No pricing was specified by the groundwork plan** for the hookup or
  pipes — `BuildModeHUD.CATEGORIES["Water"]`'s hookup price ($200) and
  `WaterPipeDrawMode.COST_PER_M` ($5/m) are deliberately conservative
  placeholders for a future balance pass, not a considered game-design cost.
- **No automated tests** (matches the rest of the project).
- **No persistence** (matches the rest of the project — see Persistence).
- **Reconnecting a hookup's pipe network across a reposition event is
  untested/theoretical for this phase** — `WaterHookup.update_graph_node_position()`
  re-keys the hookup's own graph node on reposition, but since no pipes exist
  yet in this pass that could be attached to a hookup when it moves, whether
  existing pipe edges correctly follow the hookup to its new node key across
  a boundary-change reposition has NOT been exercised by any test. Flagged
  for whoever builds on top of this — verify this specifically once pipes
  routinely exist alongside hookup repositioning.
- **`WaterPipeDrawMode`'s wall-hug raycast (`_find_wall_hug_point()`) and
  `WaterHookup`'s outer-wall raycast (`reposition_to_outer_wall()`) are each
  independently implemented** rather than sharing one helper — a deliberate
  choice to keep this system's build-mode-adjacent code (the pipe tool,
  which DOES run inside `BuildModeController`) separate from its fully
  standalone code (the hookup's boundary-tracking, which does NOT touch
  `BuildModeController`/`WallSnapHelpers` at all). Revisit if this duplication
  becomes a real maintenance burden once Phase 2 work begins.

## Extension points
- **Flow/pressure simulation:** add a `WaterSolver.gd` mirroring
  `PowerSolver.gd`'s extraction — `WaterGraph`/`WaterManager` are already
  split apart specifically so this slots in later without another
  mid-project refactor (see `docs/systems/power/README.md`'s own history of
  why that split was expensive when done late).
- **New pipe-drawing UX (the full continuous-paint upgrade):** replace
  `WaterPipeDrawMode`'s per-click confirm loop with a live multi-segment path
  preview that walks around however many corners the cursor's projected
  position crosses, confirmed all at once — see the file's own header
  comment for the exact scope of what's deferred.
