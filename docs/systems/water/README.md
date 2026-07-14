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
- The pipe placement tool — strictly axis-aligned (Manhattan/90°-only)
  routing along a fixed near-ceiling height, with a final vertical drop into
  any floor-standing connectable device — `WaterPipeDrawMode.gd`.
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
  `WallSnapHelpers._snap_to_nearest_wall()` (added alongside, for hookup
  placement/move, which DOES go through `BuildModeController`) or raycasts
  independently (`WaterHookup.reposition_to_outer_wall()` — deliberately
  self-contained, no build-mode dependency, so the water system stays
  standalone). Pipe routing itself (`WaterPipeDrawMode`) does no wall
  raycasting at all as of the July 2026 routing rewrite — see Common edits.

## Files
| File | Role |
|---|---|
| `WaterGraph.gd` | Node/edge registry + BFS connectivity. `RefCounted`, `_owner: WaterManager` back-reference (same pattern as `PowerGraph`/`PowerRegistry`/`PowerSolver` — see `docs/systems/power/README.md`). |
| `WaterManager.gd` | Orchestrator + public API. Forwards to `WaterGraph`. Also holds the hookup registry + dispatches boundary-change reposition events. |
| `WaterHookup.gd` | The wall-mounted source device. Wall-snapped placement, never deletable, auto-tracks the outermost wall in its facing direction as the bunker expands. |
| `WaterPipeSegment.gd` | Visual for one straight placed pipe. **Always visible** (see Known tradeoffs). |
| `WaterPipeElbow.gd` | Corner-joint visual, spawned automatically at a corner crossing. A REAL graph node (role `"corner"`), not just cosmetic — see Extension points. |
| `WaterPipeDrawMode.gd` | The placement tool. Routes strictly axis-aligned (90°-only) at a fixed near-ceiling height (`WATER_CEILING_Y`), dropping vertically into any floor-standing connectable device. **Uses the plan's own pre-approved FALLBACK interaction model (one confirm per click), not the full single-drag paint — see its own file-header comment and Known tradeoffs below.** |
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
  `_ready()` (deferred, same pattern `WaterTestSink`/`WaterHookup` use) — but
  register it at the device's actual physical connection point (e.g. the
  TOP of a floor-standing box, see `WaterTestSink`'s own comment), not its
  origin/base. `WaterPipeDrawMode._get_nearest_water_node_xz()` will find it
  automatically as a valid source/destination, no registry to update. Also
  add its tile ID to `BuildModeController`'s `CONNECTABLE_TILES`/
  `CONNECTABLE_TILES_QUICK` arrays so it gets the blue "connectable" dot
  overlay in build mode, same as lights/generators/the hookup/the test sink.
- **Changing pipe/hookup visual diameter:** `WaterHookup.STUB_RADIUS`,
  `WaterPipeSegment.PIPE_RADIUS`, and `WaterPipeElbow.JOINT_RADIUS` are kept
  in sync MANUALLY (no shared constant) so they visually read as one
  continuous pipe — update all three together (elbow radius should stay
  slightly larger than the pipe radius so corners read as a fitting).
- **Real water-consuming device (`water_purifier`/`water_pump`):** follow the
  `DeviceDatabase`-driven pattern the power system uses (both already have
  wattage/priority entries in `DeviceDatabase.gd`, unused) — hold independent
  `PowerManager`/`WaterManager` refs, don't couple the two managers.
- **T-split branching:** since corners/joints are already real graph nodes,
  this is "let `WaterPipeDrawMode._try_pick_source()`/`_resolve_destination()`
  start or end a run at an
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
  interaction model** (one confirm per click, up to the next destination,
  with auto-elbow-insertion at every bend), not the full single
  continuous-drag "paint the whole run in one click" experience the plan
  describes as its primary vision. Flagged explicitly per the plan's own
  instructions — full multi-segment live-preview-and-confirm was judged too
  complex to responsibly build and verify with zero in-editor testing
  available this pass (headless compile-check only). **Upgrading to the
  full paint experience is the clear, expected next step for this tool** —
  not currently scheduled, do it as its own isolated pass.
- **Pipe pricing set (July 2026 playtest pass):** `WaterPipeDrawMode.COST_PER_M`
  is now $24/m — 3x `WireDrawMode.COST_PER_M` ($8/m), per Brannon's explicit
  request. Kept as its own constant (water system stays standalone) — update
  both by hand if wire pricing ever changes. Hookup price
  (`BuildModeHUD.CATEGORIES["Water"]`, $200) is still an unreviewed placeholder.
- **Pipe placement now snaps to the same 0.25m grid as everything else**
  (`WaterPipeDrawMode._grid_snap_xz()`, matches
  `BuildModeController.grid_size`/`PowerManager.SNAP_GRID`/`WireDrawMode`'s own
  `_WIRE_GRID`) — only applied to fresh mid-air waypoints in
  `_resolve_destination()`; snapping onto an existing node is unaffected.
- **Pipe undo implemented (July 2026):** `WaterPipeDrawMode.pipe_placed` now
  also emits `elbow_nodes` (every `WaterPipeElbow` spawned for that confirmed
  segment — previously untracked, meaning undo would have left corner visuals
  orphaned) and `midpoint` (for the refund float label). `BuildUndoStack`'s new
  `"pipe"` case frees every segment + elbow node, unregisters each edge via
  `WaterManager.unregister_edge()`, and refunds cash — mirrors the `"wire"`
  case exactly, minus zone-color snapshot/restore (the water system has no
  zones/breakers).
- **No automated tests** (matches the rest of the project).
- **No persistence** (matches the rest of the project — see Persistence).
- **Reconnecting a hookup's pipe network across a reposition event is
  lightly tested at best for this phase** — `WaterHookup.update_graph_node_position()`
  re-keys the hookup's own graph node on reposition, and existing pipe edges
  DO follow it (edges reference node keys, not positions, in `WaterGraph`) —
  but whether the visual `WaterPipeSegment`s attached to that edge also
  re-draw to the hookup's new position after a boundary-tracking move has
  NOT been exercised by any test. Flagged for whoever builds on top of this.
- **Routing model rewrite (July 2026, playtest feedback):** pipes originally
  used a "wall-hugging" magnetic-snap model (see plan §5) — this was
  replaced with the current strictly-axis-aligned, fixed-ceiling-height
  Manhattan routing after playtesting showed the wall-hugging model produced
  diagonal-looking runs and didn't match the intended "pipes run along the
  ceiling, bend at exactly 90°" look. `WaterPipeDrawMode._find_wall_hug_point()`
  and its wall-snap constants no longer exist — routing is now pure
  geometry (`_build_manhattan_path()`), no raycasting at all. If a future
  pass wants pipes to hug actual wall geometry again (rather than a flat
  ceiling plane), that's a bigger redesign, not a tweak to the current code.
- **Hookup expansion-lag bug FIXED (July 2026 playtest pass):** the hookup
  used to lag exactly one expansion behind and end up floating in open air.
  ROOT CAUSE: `WaterManager._on_chunk_deconstructed/_restored` used a single
  `call_deferred("_reposition_all_hookups")`, which only waits for the rest
  of the current frame — not enough, since Godot's physics server doesn't
  register a newly added/freed `StaticBody3D` collider for raycast queries
  until it has actually stepped at least once after the node entered/left
  the tree. The next reposition raycast still saw the OLD collider layout,
  one expansion behind. FIX: `_reposition_all_hookups_after_physics_settles()`
  awaits `get_tree().physics_frame` twice before raycasting, replacing the
  single `call_deferred`.
- **Starting hookup (July 2026):** `MainWorld._spawn_initial_water_hookup()`
  places one `WaterHookup` at game start on the west wall (-X,
  `RockSurround.OFFSET_X`), near the -Z end, placed exactly the way a player
  would (reuses `BuildModeController._snap_to_nearest_wall()` +
  `_spawn_placed_object()`, registered into `_placed_objects` so the Move
  tool can find it) — free of charge, no undo entry (not a player action).
  Called right after `_run_pregen()` in `_setup_build_mode()`, before wire
  connection — walls already exist by then.
- **Every connectable device must register its `WaterGraph` node at its own
  real physical connection point**, not an arbitrary reference position —
  this is how `WaterPipeDrawMode` decides whether a final vertical drop
  segment is needed (compares the node's registered Y against
  `WATER_CEILING_Y`) with zero per-device-type special-casing. `WaterTestSink`
  registers at `global_position + Vector3(0, BOX_SIZE.y, 0)` (the TOP of its
  box) for exactly this reason — copy this convention for any new
  connectable device rather than registering at the object's origin/base.

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
