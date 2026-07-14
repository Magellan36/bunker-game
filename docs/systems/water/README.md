# Water System (Phase 1 groundwork + Step 2: interactable hookup/sink, live flow-split)

**Read this before opening any `scripts/world/water/*` file.** Only open the
actual source for the specific function you're changing.

## Purpose
The wall-mounted water hookup and the pipe-placement/routing tool, plus
(Step 2, July 2026) both devices being interactable (press E) with a shared
info panel showing tiered output, a live equal flow-split across whatever's
connected, and water quality. **Still explicitly NOT in scope**: water
purifiers, pumps, quality decay over time, priority-weighted flow (like the
power system's shedding), or upgrading `WaterPipeDrawMode` to the full
continuous-drag paint UX (see Known tradeoffs) — T-split branching may
already partially work (untested, flagged as a follow-up).

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
- Both `WaterHookup` and `WaterTestSink` being interactable (press E),
  opening a shared info panel (`WaterInfoUI.gd`) showing tiered output /
  live flow-split / water quality — Step 2, July 2026.

## Non-responsibilities
- **Not wired into PowerManager/PowerGraph in any way.** This is a separate,
  standalone system — its own subfolder, its own manager, its own placement
  tool. It follows the SAME architectural patterns the power system uses
  (topology/orchestrator split, `MainWorld`-owned-node-in-a-group convention)
  but shares no runtime dependency with it. A future device that needs BOTH
  systems (e.g. `water_purifier`, which draws electricity AND water) should
  hold independent references to both managers — neither manager should ever
  reference the other.
- **Minimal flow-splitting only, still not real flow/pressure simulation**
  (Step 2, July 2026 — this line replaces the old "no flow/pressure
  simulation" claim, which stopped being accurate once Step 2 landed real
  arithmetic on top of pure connectivity): total hookup output ÷ count of
  connected `"endpoint"`-role consumer nodes, computed live on every call, no
  priority weighting, no time-based depletion, no caching. A real
  `WaterSolver.gd` (mirroring `PowerSolver.gd`) for real pressure/priority/
  depletion simulation is still a future Extension point, not this.
- **`scripts/ui/water/` is no longer empty** — `WaterInfoUI.gd` (Step 2) is
  the system's first real UI panel. Still no full dashboard/terminal UI in
  the `PowerTerminalUI` sense — add one only once a real water-consuming
  device justifies that much complexity.
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
| `WaterPipeSegment.gd` | Visual for one straight placed pipe. **Always visible** (see Known tradeoffs). Joins group `"water_pipe_visual"` on `_ready()` (Step 2, July 2026) — pure findability for `WaterHookup._redraw_pipe_segment()`, NOT the `WireSegment` hide-on-exit-build-mode pattern. |
| `WaterPipeElbow.gd` | Corner-joint visual, spawned automatically at a corner crossing. A REAL graph node (role `"corner"`), not just cosmetic — see Extension points. |
| `WaterPipeDrawMode.gd` | The placement tool. Routes strictly axis-aligned (90°-only) at a fixed near-ceiling height (`WATER_CEILING_Y`), dropping vertically into any floor-standing connectable device. **Uses the plan's own pre-approved FALLBACK interaction model (one confirm per click), not the full single-drag paint — see its own file-header comment and Known tradeoffs below.** |
| `WaterTestSink.gd` | Rudimentary test endpoint — the acceptance test for this whole phase (place a hookup, route a pipe around a corner, confirm the sink reports CONNECTED). Interactable (Step 2) — see `WaterInfoUI.gd`. |
| `WaterInfoUI.gd` (`scripts/ui/water/`) | Step 2, July 2026. ONE shared info panel for both `WaterHookup` and `WaterTestSink` (`is_source` flag distinguishes them) — sized/complexity-matched to `GeneratorInspectUI.gd`, not the full `PowerTerminalUI` dashboard. All stats recomputed live every redraw, no caching. |

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
call each hookup's own `reposition_to_outer_wall()` directly. `register_hookup()`
now `push_warning()`s if a second hookup is ever registered (Step 2 guard —
see Known tradeoffs "only one hookup").

`WaterHookup.get_facing_dir() -> Vector3` (derived live from
`rotation_degrees.y`, not cached), `WaterHookup.reposition_to_outer_wall()`,
`WaterHookup.update_graph_node_position()` (re-keys the graph node after a
position change — called by both the boundary-tracking reposition AND a
manual Move).

### Step 2 additions (July 2026) — live flow-split
`WaterHookup.get_daily_output_mL() -> float` / `get_per_minute_output_mL() ->
float` (tiered via `TIER_DAILY_ML`/`tier`) / `get_node_key() -> String` (the
one deliberate read-only exception to `_node_key` staying private) /
`WaterHookup.tier: int` / `WaterHookup.water_quality: float` (0-100, static
this pass). `WaterTestSink.get_node_key() -> String` (same reasoning).

`WaterManager.get_connected_consumer_count(hookup: WaterHookup) -> int` —
BFS count of `"endpoint"`-role nodes reachable from the hookup (forwards to
`WaterGraph.count_reachable_endpoints()`).

`WaterManager.get_per_consumer_rate_mL_per_day(hookup: WaterHookup) -> float`
— hookup's tiered output ÷ current consumer count, 0 if nothing connected.

`WaterManager.get_received_rate_mL(consumer_node_key: String) -> Dictionary`
— traces back to whichever hookup feeds this consumer
(`WaterGraph.find_reachable_hookup_key()`) and returns `{"connected": bool,
"mL_per_day": float, "mL_per_minute": float, "quality": float}` — `quality`
is always the SOURCE hookup's `water_quality`, never a separate per-consumer
value (water doesn't gain/lose quality in transit through pipes this pass).

`WaterGraph.count_reachable_endpoints(hookup_key) -> int` /
`WaterGraph.find_reachable_hookup_key(from_key) -> String` — the two new BFS
primitives Step 2's `WaterManager` methods above forward to; both mirror
`is_reachable_from_hookup()`'s exact walk shape.

`WaterGraph.get_edges_touching(key) -> Array` (`[{"edge_id": String,
"other_key": String}, ...]`) / `WaterManager.get_edges_touching(key) ->
Array` (thin forward) — added for the hookup-reposition pipe-redraw fix (see
Known tradeoffs), reusable by anything else that ever needs to know which
edges touch a given node before tearing it down.

`WaterHookup._redraw_pipe_segment(old_edge_id, new_edge_id, hookup_pos,
other_pos)` — internal helper, not called from outside this class; finds
the live `WaterPipeSegment` via the `"water_pipe_visual"` group (see Files)
and updates it in place.

## Signals produced
`WaterPipeDrawMode` produces `pipe_placed(seg_nodes, edge_ids, cost,
elbow_nodes, midpoint)` and `pipe_tool_exit_requested()` (mirrors
`WireDrawMode`'s shape), consumed by `BuildModeController`. `WaterInfoUI`
(Step 2) produces `closed` — consumed by whichever device spawned it
(`WaterHookup`/`WaterTestSink`), same spawn-once-reuse pattern as
`GeneratorInspectUI`/`PowerTerminalUI`.

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

BuildModeController (TOOL_WATER_PIPE=6, TILE_WATER_HOOKUP=17 [no longer
  player-purchasable, see Known tradeoffs "only one hookup"], TILE_WATER_SINK=18)
  → _setup_water_pipe_draw_mode() → instantiates WaterPipeDrawMode child node
  → _spawn_placed_object(TILE_WATER_HOOKUP/_SINK, ...) → WaterHookup/WaterTestSink
      → _ready() → call_deferred("_register_deferred") → WaterManager.register_node()

MainWorld._setup_build_mode() → _spawn_initial_water_hookup() (July 2026) —
  the ONE hookup that ever exists, auto-placed on the west wall at game
  start via the same _snap_to_nearest_wall()/_spawn_placed_object() path a
  player's click would use. Awaits two physics frames first — see Known
  tradeoffs "physics-server collider registration lag".

Player digs/expands (RockSurround.chunk_deconstructed/chunk_restored)
  → MainWorld._on_chunk_deconstructed/_restored (existing _wire_builder forward, UNCHANGED)
  → NEW: WaterManager._on_chunk_deconstructed/_restored → _reposition_all_hookups_after_physics_settles()
    (awaits two physics frames, NOT a single call_deferred — see Known tradeoffs)
  → each WaterHookup.reposition_to_outer_wall() → raycast along facing_dir → update_graph_node_position()

Player uses Pipe tool (TOOL_WATER_PIPE)
  → WaterPipeDrawMode.handle_input() → _try_pick_source() (phase 0) →
    _try_confirm_segment() (phase 1) → validity check (_is_path_in_bounds/
    _path_overlaps_existing) → WaterManager.register_node/register_edge
    → spawns WaterPipeSegment(s) + WaterPipeElbow (if a corner was crossed)

Player presses E on WaterHookup/WaterTestSink (Step 2)
  → on_interact() → lazy-spawns/reuses WaterInfoUI → open(display_name,
    is_source, device_ref) → _on_draw() queries WaterManager live every
    redraw (get_connected_consumer_count/get_per_consumer_rate_mL_per_day
    for the hookup, get_received_rate_mL for the sink)
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
- **T-split branching — VERIFIED working by design (July 2026 pass):**
  confirmed via code trace (no automated tests exist in this project, so
  this is static verification, not a live playtest — worth a quick
  in-editor sanity check regardless). `WaterPipeDrawMode._try_pick_source()`
  calls `_get_nearest_water_node_xz()`, which scans ALL registered nodes via
  `WaterManager.get_nodes()` regardless of `role` — so a new run can start
  from an existing corner/joint/endpoint exactly the same way it starts from
  the hookup. `WaterGraph.register_edge()` has no limit on how many edges
  touch a single node (a real graph, not a linked list — see file header),
  and `is_reachable_from_hookup()`'s BFS walks `_adjacency` generically, so
  a branching (3+ neighbor) node is reachable/traversed with zero special-
  casing. No code changes were needed — this was already correct.
- **Pipe height (July 2026, Step 2 pass):** `WATER_HOOKUP_PLACEMENT_Y`/
  `WATER_CEILING_Y` raised from 2.8 → 2.9 (walls are 3.0m tall) — per
  Brannon's explicit request to sit slightly higher, between wall-light
  height (2.5m) and the ceiling. Keep both constants equal by hand if either
  ever changes (two independent constants, water system stays standalone).
- **Wire/pipe tool exit (July 2026, Step 2 pass):** E, RMB, and Escape now
  ALL fully exit `WireDrawMode`/`WaterPipeDrawMode` immediately, regardless
  of phase — previously RMB only cancelled an in-progress drag on its first
  press (silent two-step exit) and pipes didn't respond to E at all. Both
  tools' `handle_input()` now `_cancel()`/clear-ghost + emit their
  `*_tool_exit_requested` signal on any of the three inputs, no staged
  cancel-then-exit behavior left.
- **Pipe routing now hugs the source wall (July 2026, Step 2 pass):**
  `_build_manhattan_path()`'s corner-choice heuristic flipped from
  "longer axis first" to "shorter axis first" — the hookup (or a chained
  run from it) is usually near a wall, where the axis perpendicular to that
  wall is typically the LARGER distance to a far destination; long-leg-first
  therefore usually put that "jut straight into the room" leg first. Short-
  leg-first instead keeps the run close to the wall for as long as possible
  before cutting across last. Always a valid 90°-only path either way — this
  only changes which of the two legs runs first.

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
- **Pipe placement validity added (July 2026):** `WaterPipeDrawMode` now
  rejects (red ghost preview + a warning popup, no cash spent) a path that
  either leaves the bunker's placeable area or exactly re-traces an already-
  placed pipe edge. Pipes get their OWN tightened bounds rectangle (inset by
  one full grid tile beyond `BuildModeController._is_inside_bunker()`'s own
  0.1m margin, per Brannon's explicit "1 tile too far out" bug report) rather
  than changing the shared helper itself (many other placement systems
  depend on its current tuning). Overlap detection only catches an exact
  endpoint-to-endpoint duplicate — a perpendicular mid-span crossing is not
  detected (would need real segment-intersection math).
- **"Only one hookup" locked down (Step 2, July 2026):** the build menu no
  longer lists a purchasable Hookup tile (`BuildModeHUD.CATEGORIES["Water"]`)
  — the single auto-placed hookup (`MainWorld._spawn_initial_water_hookup()`)
  is relocatable only via the Move tool. `WaterManager.register_hookup()`
  additionally `push_warning()`s (doesn't block) if a second ever somehow
  gets registered — belt-and-suspenders, not a supported configuration. Every
  Step 2 flow-split method assumes exactly one hookup exists.
- **Physics-server collider registration lag (root cause found twice, fixed
  both times, July 2026):** the starting hookup silently failed to appear,
  and separately the hookup lagged one expansion behind and floated in open
  air after a dig. Both were the SAME root cause — Godot's physics server
  doesn't register a newly added/removed `StaticBody3D` collider for
  raycast queries until it has actually stepped at least once after the
  node entered/left the tree, so a raycast run the same frame the wall was
  built/removed still saw the OLD collider layout. Fixed in both places by
  awaiting `get_tree().physics_frame` TWICE before raycasting
  (`WaterManager._reposition_all_hookups_after_physics_settles()` and
  `MainWorld._spawn_initial_water_hookup()`) instead of a single
  `call_deferred()`, which only waits out the rest of the current frame.
- **Cost float labels (July 2026):** placing a pipe (or a wire) now shows a
  "-$X" screen-space label at the moment cash is spent
  (`WaterPipeDrawMode._spawn_float_label()`/`WireDrawMode._spawn_float_label()`),
  matching the "+$X" refund label undo already showed for both. Each tool
  duplicates its own small helper rather than sharing one — matches this
  system's standalone-from-`BuildModeController`-internals convention.
- **No automated tests** (matches the rest of the project).
- **No persistence** (matches the rest of the project — see Persistence).
- **Pipe redraw across a hookup reposition — WAS A REAL BUG, FIXED (July
  2026 pass):** this was flagged as "lightly tested at best" and turned out
  to actually be broken once traced through code, not just untested.
  ROOT CAUSE: `WaterHookup.update_graph_node_position()` re-keys the
  hookup's graph node via `unregister_node()` + `register_node()` on every
  reposition; `unregister_node()` cascades to remove every edge touching the
  old key (see `WaterGraph.unregister_node()`) — but nothing ever told the
  corresponding `WaterPipeSegment` visual(s) to move or free themselves, so
  they stayed floating at the OLD position, silently disconnected from the
  (now-repaired) graph. FIX: `update_graph_node_position()` now captures
  every edge touching the old key first (`WaterGraph.get_edges_touching()`),
  re-creates the same edges against the new key once registered, and
  redraws each affected segment in place (`WaterHookup._redraw_pipe_segment()`,
  found via a new `"water_pipe_visual"` group every `WaterPipeSegment` joins
  on `_ready()` — purely for findability, a DIFFERENT group from
  `WireSegment`'s hide-on-exit-build-mode pattern, never used for show/hide
  here). Corners/elbows further down a run are untouched by this fix — their
  own positions never depended on the hookup's, only the FIRST segment
  leaving the hookup does.
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
- **Real flow/pressure simulation:** add a `WaterSolver.gd` mirroring
  `PowerSolver.gd`'s extraction — `WaterGraph`/`WaterManager` are already
  split apart specifically so this slots in later without another
  mid-project refactor (see `docs/systems/power/README.md`'s own history of
  why that split was expensive when done late). Step 2's live equal
  flow-split (`get_connected_consumer_count()`/`get_per_consumer_rate_mL_per_day()`)
  is a deliberately minimal placeholder for this, not a first version of it.
- **Water quality decay over time:** `WaterHookup.water_quality` is a static
  0-100 value this pass (Step 2) — a future pass would tick it down over
  time (and/or let events/disasters affect it). The field already exists
  and is already wired into both info-panel displays, so a future decay
  system only needs to mutate the value, not introduce it or its UI.
- **Priority-weighted flow / real consumer devices:** Step 2's split is
  strictly equal-across-all-connected-endpoints, no priority tiers like the
  power system's shedding. A real consumer device (vs. the test sink) and
  priority weighting are both explicitly out of scope for Step 2.
- **New pipe-drawing UX (the full continuous-paint upgrade):** replace
  `WaterPipeDrawMode`'s per-click confirm loop with a live multi-segment path
  preview that walks around however many corners the cursor's projected
  position crosses, confirmed all at once — see the file's own header
  comment for the exact scope of what's deferred.
