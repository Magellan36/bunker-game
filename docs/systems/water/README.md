# Water System (Phase 1 groundwork + Step 2 interactable hookup/sink + demand/priority allocation)

**Read this before opening any `scripts/world/water/*` file.** Only open the
actual source for the specific function you're changing.

## Purpose
The wall-mounted water hookup, the pipe-placement/routing tool, both devices
being interactable (press E) with a shared info panel (Step 2), and (Jul
2026) a REAL demand-based, priority-tier allocation system
(`WaterSolver.gd`) plus the water system's first real consuming device,
`WaterDispenser.gd`. Every registered consumer (`WaterTestSink`,
`WaterDispenser`) now has its own tunable priority (1-5, same convention as
the power system's shedding tiers) and live demand; a hookup's total daily
output is allocated tier-by-tier (see `WaterSolver.gd`'s own header for the
full waterfall algorithm), replacing the old Step 2 equal-split placeholder
entirely. **Still explicitly NOT in scope**: water purifiers, pumps, quality
decay/mixing over time (`stored_water_quality`/`water_quality` stay static
placeholders), or upgrading `WaterPipeDrawMode` to the full continuous-drag
paint UX (see Known tradeoffs) — T-split branching may already partially
work (untested, flagged as a follow-up).

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
  `WaterTestSink.gd` — now with a tunable `priority`/`fixed_demand_mL_per_day`
  (Jul 2026) for exercising `WaterSolver.gd` against different playtest
  configurations.
- Both `WaterHookup` and `WaterTestSink` being interactable (press E),
  opening a shared info panel (`WaterInfoUI.gd`) showing tiered output /
  connected demand vs. capacity / water quality — Step 2, July 2026 (wording
  updated Jul 2026 once allocation stopped being equal-split).
- **Demand-based priority-tier water allocation** (`WaterSolver.gd`, Jul
  2026) — the real solver this system was always going to need (flagged as
  an Extension point since Phase 1). Groups every registered consumer
  reachable from a hookup by priority tier, processes tiers 1→5, fully
  serving a tier if under supply or proportionally scaling it down if
  oversubscribed (see that file's own header for the exact algorithm and
  worked examples).
- `WaterDispenser.gd` — the system's first real, gameplay-relevant
  water-consuming device (Jul 2026): 5000mL storage, a player-tunable
  requested rate (slider, `WaterDispenserUI.gd`), on/off toggle, and a fill
  tick driven by the solver's actual per-tick GRANT, never the raw
  requested rate.

## Non-responsibilities
- **Not wired into PowerManager/PowerGraph in any way.** This is a separate,
  standalone system — its own subfolder, its own manager, its own placement
  tool. It follows the SAME architectural patterns the power system uses
  (topology/orchestrator split, `MainWorld`-owned-node-in-a-group convention)
  but shares no runtime dependency with it. A future device that needs BOTH
  systems (e.g. `water_purifier`, which draws electricity AND water) should
  hold independent references to both managers — neither manager should ever
  reference the other.
- **Priority-tier demand allocation, still not real flow/pressure simulation**
  (Jul 2026 — supersedes the old Step 2 "equal flow-split" claim entirely):
  `WaterSolver.gd` allocates a hookup's total daily output tier-by-tier based
  on each consumer's live requested demand and 1-5 priority — no actual
  fluid pressure/pipe-diameter/distance-loss physics, no time-based
  depletion of the SOURCE (the hookup's own tiered output is still a flat
  constant, see `WaterHookup.TIER_DAILY_ML`), no caching (recomputed fresh
  on every call, matching this system's existing "compute live, no
  persistence" pattern).
- **`scripts/ui/water/` now holds two panels, both hand-drawn `_draw()`
  panels** — `WaterInfoUI.gd` (Step 2, read-only hookup/sink stats) and
  `WaterDispenserUI.gd` (Jul 2026, interactive rate slider + on/off + demand
  priority). `WaterDispenserUI.gd` was originally built as a stock
  `Panel`/`VBoxContainer`/`CheckBox` tree mirroring `GraphicsSettingsPanel.gd`
  (default Godot theme throughout); restyled the same day to match
  `WaterInfoUI`/`PowerPriorityUI`'s look instead — a `Control` + `_on_draw()`
  background/border/text pass with real `HSlider`/`Button` nodes (styled,
  not stock-themed) overlaid and repositioned every frame, same pattern
  `PowerPriorityUI.gd` already used for its ◄ N ► priority changer. Still no
  full dashboard/terminal UI in the `PowerTerminalUI` sense.
- **Demand priority is now player-adjustable from both device panels**
  (Jul 2026) — `WaterInfoUI.gd`'s sink branch and `WaterDispenserUI.gd` both
  draw the same ◄ N ► chip+pip-strip layout as `PowerPriorityUI.gd` (same
  `PRIO_COLORS` green→red legend, reused verbatim — universal tier meaning,
  not a power-vs-water palette). Priority is set directly on the device
  (`sink.priority` / `dispenser.priority`) rather than through a manager
  setter call — `WaterSolver.gd` already reads `priority` live off
  `consumer_ref` every solve (see `_read_priority()`), so no explicit
  "apply" step is needed; the very next solve picks up the change.
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
| `WaterPipeSegment.gd` | Visual for one straight placed pipe. **Always visible** (see Known tradeoffs). Joins group `"water_pipe_visual"` on `_ready()` (Step 2, July 2026) — pure findability for `WaterHookup._delete_and_refund_edge()`, NOT the `WireSegment` hide-on-exit-build-mode pattern. Also carries `placement_cost` (July 2026) — per-leg cost stashed at spawn time, source of truth for that same refund path. |
| `WaterPipeElbow.gd` | Corner-joint visual, spawned automatically at a corner crossing. A REAL graph node (role `"corner"`), not just cosmetic — see Extension points. |
| `WaterPipeDrawMode.gd` | The placement tool. Routes strictly axis-aligned (90°-only) at a fixed near-ceiling height (`WATER_CEILING_Y`), dropping vertically into any floor-standing connectable device. **Uses the plan's own pre-approved FALLBACK interaction model (one confirm per click), not the full single-drag paint — see its own file-header comment and Known tradeoffs below.** |
| `WaterTestSink.gd` | Rudimentary test endpoint — the acceptance test for this whole phase (place a hookup, route a pipe around a corner, confirm the sink reports CONNECTED). Interactable (Step 2) — see `WaterInfoUI.gd`. Jul 2026: `priority: int` (1-5) + `fixed_demand_mL_per_day: float` exports, implements `get_current_demand_mL_per_day()` for `WaterSolver.gd`. |
| `WaterInfoUI.gd` (`scripts/ui/water/`) | Step 2, July 2026. ONE shared info panel for both `WaterHookup` and `WaterTestSink` (`is_source` flag distinguishes them) — sized/complexity-matched to `GeneratorInspectUI.gd`, not the full `PowerTerminalUI` dashboard. All stats recomputed live every redraw, no caching. Hookup-side stats rewritten Jul 2026 (see Non-responsibilities). Sink branch gained a `PowerPriorityUI`-style ◄ N ► demand-priority changer Jul 2026 (dynamic panel height: `PANEL_H_SOURCE`/`PANEL_H_SINK`). |
| `WaterSolver.gd` | Jul 2026. Priority-tier demand waterfall — `RefCounted`, `_graph: WaterGraph` back-reference (same split pattern as `PowerGraph`/`PowerRegistry`/`PowerSolver`). Pure read-only queries, no state held between calls. |
| `WaterDispenser.gd` | Jul 2026. The first real water-consuming device — 5000mL storage, on/off, player-tunable requested rate, fill tick driven by the solver's actual grant. `TILE_WATER_DISPENSER` in `BuildModeController`, ground-placed like the test sink. |
| `WaterDispenserUI.gd` (`scripts/ui/water/`) | Jul 2026, restyled same day. Hand-drawn `_draw()` panel (matches `WaterInfoUI`/`PowerPriorityUI`) with real `HSlider`/`Button` controls overlaid — fill level, rate slider (0 to the live dynamic max), effective (actually received) rate, on/off pill toggle, ◄ N ► demand-priority changer, water-quality placeholder. |

## Public API
Get the instance via
`get_tree().get_first_node_in_group("water_manager")` cast to `WaterManager`.

`register_node(pos, role, consumer_ref: Node = null) -> String` (Jul 2026:
gained the optional `consumer_ref` param — the back-reference `WaterSolver.gd`
reads priority/demand off of; only meaningful for role `"endpoint"`) /
`unregister_node(key)` / `has_water_node(key) -> bool` (NOT `has_node` — that
name collides with `Node`'s own built-in method since `WaterManager extends
Node`; this was caught by the headless compile check during this pass, see
Known tradeoffs) / `get_node_data(key) -> Dictionary` / `get_consumer_ref(key)
-> Node` (Jul 2026, forwards to `WaterGraph`) / `register_edge(key_a,
key_b) -> String` / `unregister_edge(edge_id)` / `has_edge(edge_id) -> bool` /
`get_nodes() -> Dictionary` / `get_edges() -> Dictionary` /
`is_reachable_from_hookup(node_key) -> bool` (the one piece of pure
connectivity "simulation" this phase needs) / `WaterManager.make_node_key(pos)
-> String` (static).

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

### Step 2 additions (July 2026)
`WaterHookup.get_daily_output_mL() -> float` / `get_per_minute_output_mL() ->
float` (tiered via `TIER_DAILY_ML`/`tier`) / `get_node_key() -> String` (the
one deliberate read-only exception to `_node_key` staying private) /
`WaterHookup.tier: int` / `WaterHookup.water_quality: float` (0-100, static
this pass). `WaterTestSink.get_node_key() -> String` (same reasoning).

`WaterManager.get_connected_consumer_count(hookup: WaterHookup) -> int` —
BFS count of `"endpoint"`-role nodes reachable from the hookup (forwards to
`WaterGraph.count_reachable_endpoints()`).

`WaterGraph.count_reachable_endpoints(hookup_key) -> int` /
`WaterGraph.find_reachable_hookup_key(from_key) -> String` — the two BFS
primitives Step 2's `WaterManager` methods forward to; both mirror
`is_reachable_from_hookup()`'s exact walk shape.

### Demand/priority-tier allocation additions (July 2026) — supersedes Step 2's equal-split
`WaterGraph.get_consumer_ref(key) -> Node` — reads the `consumer_ref` stored
by `register_node()`; null for non-`"endpoint"` roles or if unset.
`WaterGraph.get_reachable_endpoint_keys(hookup_key) -> Array[String]` — same
BFS walk as `count_reachable_endpoints()`, returns keys instead of a count
(what `WaterSolver.gd` iterates over).

`WaterSolver.new(graph: WaterGraph)` / `solve_for_hookup(hookup_key: String,
total_supply_mL_per_day: float) -> Dictionary` — the core waterfall, returns
`{ node_key(String) -> received_mL_per_day(float) }` for every endpoint
reachable from the hookup (a missing key means 0 received, same as an
explicit 0.0 entry) / `get_dynamic_max_for_device(hookup_key, total_supply,
device_key, device_priority) -> float` — a specific device's live slider
ceiling (waterfalls every tier strictly above the device's own, then
subtracts every OTHER same-tier device's current demand from what's left,
floored at 0). Both fully recomputed on every call, no caching, no state
held on the solver instance between calls.

`WaterManager.get_total_requested_demand_mL(hookup: WaterHookup) -> float`
— sum of every reachable endpoint's CURRENT requested demand (not what
they'll actually receive) — used by the hookup's own info panel now that
the split is no longer equal.

`WaterManager.get_received_rate_mL(consumer_node_key: String) -> Dictionary`
— traces back to whichever hookup feeds this consumer
(`WaterGraph.find_reachable_hookup_key()`), runs the WHOLE hookup's
`WaterSolver.solve_for_hookup()`, and returns `{"connected": bool,
"mL_per_day": float, "mL_per_minute": float, "quality": float}` for THIS
consumer's actual received share (can be less than requested) — `quality`
is always the SOURCE hookup's `water_quality`, never a separate per-consumer
value (water doesn't gain/lose quality in transit through pipes this pass).
**Rewritten Jul 2026** — previously an equal hookup-output ÷ consumer-count
split; now solver-backed.

`WaterManager.get_dynamic_max_mL_per_day(consumer_node_key: String,
device_priority: int) -> float` — thin forward to
`WaterSolver.get_dynamic_max_for_device()`, resolving the hookup + its
output for the caller. What `WaterDispenser`/`WaterDispenserUI` query every
frame for the slider ceiling.

`WaterDispenser.get_current_demand_mL_per_day() -> float` /
`get_node_key() -> String` / `set_on(value: bool)` / `set_requested_rate(value:
float)` — the duck-typed demand contract + the small mutator API
`WaterDispenserUI.gd` drives. `WaterDispenser.priority: int` (1-5, same
convention), `requested_rate_mL_per_day: float` (the slider's stored value,
untouched by `set_on()`), `is_on: bool`, `current_fill_mL: float`,
`stored_water_quality: float` (0-100, unread/undecayed placeholder, same
treatment as `WaterHookup.water_quality`).

**REMOVED (Jul 2026):** `WaterManager.get_per_consumer_rate_mL_per_day()` —
the old equal-split method. No longer meaningful once allocation is
priority-tiered; nothing calls it anymore.

`WaterGraph.get_edges_touching(key) -> Array` (`[{"edge_id": String,
"other_key": String}, ...]`) / `WaterManager.get_edges_touching(key) ->
Array` (thin forward) — added for the hookup-reposition delete-and-refund
fix (see Known tradeoffs), reusable by anything else that ever needs to know
which edges touch a given node before tearing it down.

`WaterHookup._delete_and_refund_edge(edge_id, wm)` / `_find_pipe_visual(edge_id)`
— internal helpers, not called from outside this class; delete the edge's
graph registration and its `WaterPipeSegment` visual (found via the
`"water_pipe_visual"` group, see Files), refunding `placement_cost` to the
player.

## Signals produced
`WaterPipeDrawMode` produces `pipe_placed(seg_nodes, edge_ids, cost,
elbow_nodes, midpoint)` and `pipe_tool_exit_requested()` (mirrors
`WireDrawMode`'s shape), consumed by `BuildModeController`. `WaterInfoUI`
(Step 2) and `WaterDispenserUI` (Jul 2026) both produce `closed` — consumed
by whichever device spawned them (`WaterHookup`/`WaterTestSink`/
`WaterDispenser`), same spawn-once-reuse pattern as
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
**Jul 2026 — now saved.** `WaterManager.get_pipe_network_for_save()`/
`restore_pipe_network()` (SaveManager phase 3) persists every pipe-owned
graph node (`corner`/`pipe_joint`) and edge (world-space endpoint positions +
per-segment `placement_cost`, for `WaterHookup._delete_and_refund_edge()`
refund accuracy after a later reposition). `WaterHookup`/`WaterTestSink`/
`WaterDispenser` themselves are NOT saved here — they're ordinary
`BuildModeController` placed objects (phase 1), each with a device-specific
`extra` dict (sink: priority/fixed_demand; dispenser: priority/requested
rate/on/current fill). See `docs/systems/world-core/README.md` Persistence
for the full phase order. Mid-session Load clears existing pipe nodes/
visuals first via `clear_water_pipes()`. **Not persisted:** `WaterHookup.tier`/
`water_quality` — no upgrade mechanic exists yet to ever change `tier` away
from its default 0, so this is low-risk, not scheduled.

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
  → each WaterHookup.reposition_to_outer_wall() → raycast along facing_dir →
    update_graph_node_position() ONLY IF the raycast hit position actually
    differs from the current position (fix, Jul 2026 — see Known tradeoffs
    "reposition fires on every dig, not just ones touching this wall")

Player uses Pipe tool (TOOL_WATER_PIPE)
  → WaterPipeDrawMode.handle_input() → _try_pick_source() (phase 0) →
    _try_confirm_segment() (phase 1) → validity check (_is_path_in_bounds/
    _path_overlaps_existing) → WaterManager.register_node/register_edge
    → spawns WaterPipeSegment(s) + WaterPipeElbow (if a corner was crossed)

Player presses E on WaterHookup/WaterTestSink (Step 2)
  → on_interact() → lazy-spawns/reuses WaterInfoUI → open(display_name,
    is_source, device_ref) → _on_draw() queries WaterManager live every
    redraw (get_connected_consumer_count/get_total_requested_demand_mL
    for the hookup, get_received_rate_mL for the sink — solver-backed
    since Jul 2026)

Player presses E on WaterDispenser (Jul 2026)
  → on_interact() → lazy-spawns/reuses WaterDispenserUI → open(self)
    → _process()/_pull_live() every frame: WaterManager.get_dynamic_max_mL_per_day()
    (slider ceiling) + get_received_rate_mL() (effective/actually-received
    rate) — both re-solve the whole hookup's WaterSolver waterfall live
  → WaterDispenser._process() independently reclamps requested_rate_mL_per_day
    to the same dynamic max every frame (not just while the panel is open)
    and fills current_fill_mL off get_received_rate_mL()'s GRANT, never the
    raw requested rate
```

## Common edits
- **New pipe-connectable device (beyond the test sink/dispenser):** register
  a `"endpoint"` (or other) role node via `WaterManager.register_node()` in
  `_ready()` (deferred, same pattern `WaterTestSink`/`WaterHookup`/
  `WaterDispenser` use) — but register it at the device's actual physical
  connection point (e.g. the TOP of a floor-standing box, see
  `WaterTestSink`'s own comment), not its origin/base. Pass `self` as the
  new `consumer_ref` param if the device is a real consumer (implements
  `get_current_demand_mL_per_day()` + a `priority: int` field) so
  `WaterSolver.gd` picks it up automatically — `WaterDispenser.gd` is the
  reference example for a full real-consumer implementation.
  `WaterPipeDrawMode._get_nearest_water_node_xz()` will find the new node
  automatically as a valid source/destination, no registry to update. Also
  add its tile ID to `BuildModeController`'s `CONNECTABLE_TILES`/
  `CONNECTABLE_TILES_QUICK` arrays (+ `GhostPreview.gd`/`MoveDuplicateTool.gd`
  ghost-mesh branches, + a `BuildModeHUD.CATEGORIES["Water"]` entry if
  player-placeable) so it gets the blue "connectable" dot overlay in build
  mode, same as lights/generators/the hookup/the test sink/the dispenser.
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
- **Wire/pipe "exit placing" corrected (July 2026, third playtest pass —
  supersedes a wrong fix from the Step 2 pass):** the Step 2 pass made E/
  RMB/Escape fully exit `WireDrawMode`/`WaterPipeDrawMode` back to Construct
  tool — Brannon flagged this as exactly wrong: pressing E "wasn't working"
  because it was leaving wire/pipe mode entirely (switching to Construct,
  which visually reads as an unwanted mode-switch) instead of just cancelling
  the in-progress placement. **Corrected behavior:** E, RMB, and Escape now
  cancel the current phase-1 drag (clear ghost + cost label, reset to
  phase 0) and STAY in the wire/pipe tool — no `*_tool_exit_requested` signal
  fires from any of the three anymore; the only way to leave the tool
  entirely is re-clicking its own toolbar button (pre-existing toggle
  behavior, unchanged).
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

## Debug logging (July 2026, seventh playtest pass)
`WaterPipeDrawMode.PIPE_DEBUG` (`const`, currently `true`) gates a full
`[PipeDebug]` trace — mirrors the project's standing `WIRE_DEBUG` convention
(see `WireDrawMode.gd`/`BuildModeController.gd`). Added specifically to
diagnose pipes still routing/placing oddly after the hookup-grid-snap fix.
- `_try_pick_source()` and `_try_confirm_segment()` each dump the full
  current `"water_pipe_visual"` network (`_dump_pipe_network()`) plus every
  intermediate value: resolved destination, raw Manhattan path, avoided
  path (and whether a detour was inserted), the exact point that fails
  `_is_path_in_bounds()` if any, final cost, and every registered
  key/edge/segment actually placed.
- `_leg_collinear_overlaps()`/`_find_collinear_conflict()`/
  `_avoid_existing_pipes()` take a `debug: bool = false` param — MUST stay
  `false` for the per-frame ghost preview call (`_update_ghost_preview()`)
  or `PIPE_DEBUG` would flood the console at 60fps while dragging; only the
  confirm-click call (`_try_confirm_segment()`) passes `true`, logging the
  exact reason (different axis / different height / lateral offset exceeds
  tolerance / no range overlap) each existing segment was or wasn't treated
  as a conflict.
- **Debug logging spam — WAS A REAL BUG, FIXED (July 2026, eighth playtest
  pass):** `_is_path_in_bounds()` and `_find_split_candidate()` were
  accidentally left un-gated when the `debug` param pattern above was
  introduced — both are called every frame from the read-only ghost
  preview (`_update_ghost_preview()`/`_resolve_destination()`), so they
  flooded the console with hundreds of near-duplicate lines per second
  while the player merely held the cursor still, reported as "the debug
  output format was incorrect." FIX: both now take the same
  `debug: bool = false` param as the collinear-check functions above —
  `_resolve_destination()` also gained the same param so it can thread
  `debug` through to `_find_split_candidate()` from whichever caller needs
  it. Only `_try_pick_source()`/`_try_confirm_segment()` (one-off clicks)
  pass `true`; the ghost preview's own calls stay at the silent default.
- `_find_split_candidate()` logs the raw (pre-grid-snap) closest point
  alongside the grid-snapped result, so a debug session can directly
  confirm whether the grid-snap fix is actually taking effect.
Only strip these prints once Brannon explicitly asks for this system
stable (matches the project's standing debug-logging discipline).

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
- **Live cost preview added to pipes, both previews doubled in size (July
  2026, third playtest pass):** `WaterPipeDrawMode` now shows a floating
  "$X" `Label3D` at the path midpoint during phase-1 drag, updated every
  frame — same create-once/reuse pattern as `WireDrawMode._update_cost_label()`.
  Per Brannon's "a bit small" feedback, both tools' live cost label
  `font_size` doubled (28 → 56).
- **T-splits now work from ANY point on a placed pipe, not just registered
  nodes (July 2026, third playtest pass):** the pre-existing "start/end a
  run at any existing node (hookup/joint/corner)" T-split support already
  worked (see the entry below) — this extends it to any POINT along an
  existing pipe's mid-span. `WaterPipeDrawMode._find_split_candidate()`
  (read-only, safe every frame for the ghost preview) finds the closest
  mid-span point within `SPLIT_SNAP_RADIUS` (0.6m, excluding points too
  close to either endpoint — real node-snapping already covers that);
  `_split_pipe_at()` (mutating, only called from an actual click — phase-0
  source pick or phase-1 confirm) tears down the old edge + its one
  `WaterPipeSegment` visual, registers a new `"corner"` node + `WaterPipeElbow`
  at the split point, and re-creates two edges/segments in its place.
- **Pipes never overlap each other — collinear runs are rerouted, not
  rejected; perpendicular "+" crossings ARE allowed and create a shared
  joint (July 2026, third playtest pass):** replaces the old exact-
  duplicate-edge rejection (`_path_overlaps_existing()`/`_is_path_valid()`,
  removed). Two separate cases, both computed on the (already wall-hugging)
  Manhattan path:
  - **Collinear overlap** (`_leg_collinear_overlaps()`/`_avoid_existing_pipes()`):
    same axis, same lateral offset, overlapping range — the new leg would
    literally run on top of an existing pipe. Rerouted with a 3-point
    sidestep detour (`DETOUR_OFFSET` = 0.5m: jog out, run parallel past the
    conflict, jog back) rather than blocked — a real loop around the
    obstruction. Applied identically in the ghost preview and at confirm
    time (`_update_ghost_preview()`/`_try_confirm_segment()` both call
    `_avoid_existing_pipes()`) so what's previewed is exactly what gets
    placed. **Known limitations** (documented rather than over-engineered
    away): detours around the FULL leg span, not just the overlapping
    sub-range; only one avoidance pass (doesn't recursively re-check the
    detour itself against yet another pipe); fixed sidestep direction (+Z
    for an X-axis leg, +X for a Z-axis leg) rather than picking whichever
    side has more clearance.
  - **Perpendicular crossing** (`_find_perpendicular_crossing()`/
    `_insert_crossings()`): different axis, ranges actually intersect at one
    interior point — an explicitly ALLOWED "+" formation. MUTATES the graph
    (splits the crossed existing pipe at the crossing point via
    `_split_pipe_at()`, inserts the crossing as a shared joint waypoint) —
    only ever runs at confirm time (`_try_confirm_segment()`), never from
    the read-only ghost preview, since it's not safe to mutate every frame
    during a drag. Multiple crossings on one leg are ordered along the leg
    before insertion.
  - `_try_confirm_segment()`'s node/edge-registration loop was rewritten
    around a unified `Array[Dictionary]` point list (`{"pos", "existing_key"}`)
    produced by `_insert_crossings()` — every point that already has a key
    (source, an existing-node/split destination, or a crossing joint) is
    reused as-is; every other point gets a fresh `"corner"`/`"pipe_joint"`
    registration exactly as before.
- **Ghost/preview pipes were polluting the avoidance scan — WAS A REAL BUG,
  FIXED (July 2026, fourth playtest pass):** the no-overlap routing above
  shipped with a real feedback-loop bug. ROOT CAUSE: `WaterPipeSegment._ready()`
  unconditionally joined `"water_pipe_visual"` — including for TEMPORARY
  ghost instances from `make_ghost_pipe()`, which use the exact same script/
  class as real placed pipes. `_clear_ghost()`'s `queue_free()` is deferred
  to end-of-frame, so the PREVIOUS frame's ghost was still alive (and still
  in the group) when the NEXT frame's `_update_ghost_preview()` ran its
  avoidance/crossing scan — the preview detected its own leftover ghost as a
  "conflict" and rerouted around it, then that new ghost became the
  "conflict" for the following frame, oscillating between two different
  reroutes every single frame. Matched the reported symptoms exactly:
  rapidly changing "weird loop" layouts and a flickering cost label. FIX:
  added `WaterPipeSegment.is_ghost` (set by `make_ghost_pipe()` BEFORE
  `add_child()`, so `_ready()` sees it in time) — ghost instances never join
  `"water_pipe_visual"` at all now.
- **T-split points now grid-snap, fixing a "little legs" visual bug (July
  2026, fifth playtest pass):** `_find_split_candidate()`'s split point
  (from `_closest_point_on_segment_xz()`) used to be an arbitrary,
  un-grid-snapped position along the existing pipe's line — unlike every
  other waypoint in the system (fresh mid-air waypoints go through
  `_grid_snap_xz()`, and node positions ultimately trace back to a
  grid-snapped waypoint too, except the hookup's own wall-snap position —
  see below). Any pipe continuing from an off-grid split point almost never
  lined up with the 0.25m grid on its next bend, leaving a tiny sub-grid-
  tile jog right at the joint — reported as small stray "legs" sticking out
  at bend points that should have been clean, empty space. FIX:
  `_grid_snap_split_point()` snaps the axis running ALONG the segment to the
  nearest 0.25m grid line (clamped strictly between the segment's own two
  endpoints); the fixed lateral coordinate is copied exactly from the
  segment, never independently snapped, so the point stays precisely ON the
  pipe's line. **Known remaining edge case (CLOSED — see next entry):**
  `WaterHookup`'s own position comes from
  `WallSnapHelpers._snap_to_nearest_wall()`'s raycast hit point, not the
  0.25m grid — a pipe's very FIRST bend leaving the hookup could still show
  the same tiny-jog artifact if the hookup itself happened to sit slightly
  off-grid.
- **Hookup position now grid-snapped along the wall too, fixing pipes that
  visually crossed through each other (July 2026, sixth playtest pass):**
  this was the "known remaining edge case" flagged above, and turned out to
  be worse than a cosmetic jog — it could let a NEW pipe run right through
  an EXISTING one without the collinear-overlap check ever catching it.
  ROOT CAUSE: the existing pipe's line traced back to the hookup's
  non-grid-aligned position, so its fixed lateral coordinate was off the
  grid by a few centimeters; a fresh destination elsewhere is always
  exactly grid-aligned via `_grid_snap_xz()`, so the two lines' lateral
  coordinates differed by just enough to fail the old strict
  `_leg_collinear_overlaps()` tolerance (`MIN_POINT_GAP` = 0.05m) even
  though the pipes' physical tubes (radius 0.09m each) visually clipped
  into each other. TWO fixes, both needed:
  - `WaterHookup._grid_snap_along_wall()` (new) snaps the hookup's
    along-the-wall coordinate to the same 0.25m grid as everything else —
    called from both `_register_deferred()` (initial placement) and
    `update_graph_node_position()` (covers both the boundary-tracking
    reposition and the Move tool in one place). The perpendicular
    into-the-wall coordinate is left untouched so the hookup stays flush
    against the actual wall face.
  - `WaterPipeDrawMode.COLLINEAR_LATERAL_TOLERANCE` (new) widens the
    "same line" lateral tolerance in `_leg_collinear_overlaps()` from
    `MIN_POINT_GAP` (0.05m) to 2x `WaterPipeSegment.PIPE_RADIUS` (~0.18m) —
    two pipes visually touching/clipping given their real tube thickness
    now count as needing avoidance even when not on the mathematically
    EXACT same line. Also added a missing Y-equality check between the two
    segments in the same function (previously only checked each was
    individually horizontal, never that they were at the SAME height —
    harmless in practice once every pipe is on `WATER_CEILING_Y`, but a
    real gap if an older run was ever placed at a stale height value).
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
- `WaterHookup.tier`/`water_quality` not persisted (see Persistence — low risk, no upgrade mechanic exists yet).
- **Pipe redraw across a hookup reposition — CORRECTED to delete-and-refund
  (July 2026, supersedes the auto-redraw fix from the previous pass):** the
  original bug was real — `unregister_node()` cascades to remove every edge
  touching the hookup's old key (see `WaterGraph.unregister_node()`), but
  nothing told the corresponding `WaterPipeSegment` visual to move or free
  itself, so it stayed floating at the OLD position, silently disconnected.
  The FIRST fix made `update_graph_node_position()` auto-redraw the directly-
  touching segment(s) to the hookup's new position, keeping the connection
  alive. **That fix was itself wrong** — it fixed the visual bug but reopened
  it as an economy exploit: pipes cost per meter (`COST_PER_M`), and a free
  auto-redraw on every reposition let a player dig outward repeatedly and get
  arbitrarily long pipe runs without ever paying for the added length, since
  wall expansion (`reposition_to_outer_wall()`) fires on every dig. CORRECTED
  BEHAVIOR: `update_graph_node_position()` now captures every edge touching
  the old key (`WaterGraph.get_edges_touching()`), then **deletes and
  refunds** each one via `_delete_and_refund_edge()` — same treatment as a
  normal undo (refunds `WaterPipeSegment.placement_cost`, shows the same
  "+$X" float label) — rather than re-creating or redrawing anything.
  Nothing reconnects automatically: whatever the deleted segment used to
  connect to (a corner, a T-split joint, further pipe run) stays exactly
  where it is, still registered in the graph, just no longer reachable from
  the hookup until the player manually places a new segment from the
  hookup's new position, at normal cost. Applies uniformly to BOTH callers
  of `update_graph_node_position()` — `reposition_to_outer_wall()` (wall
  expansion) and `MoveDuplicateTool`'s manual Move — deliberately not
  caller-specific, so a player can't dodge the fix by relocating via the
  Move tool instead. `WaterPipeSegment.placement_cost` (new field, set at
  spawn time by `WaterPipeDrawMode._try_confirm_segment()` from that leg's
  own length × `COST_PER_M`) is the source of truth for the refund amount —
  removes the need to re-derive/assume the pricing formula at refund time.
  `_redraw_pipe_segment()` is deleted entirely; nothing calls it anymore.
  Corners/elbows further down a run are untouched by this fix — their own
  positions never depended on the hookup's, only the FIRST segment leaving
  the hookup does.
- **Reposition fires on every dig, not just ones touching this wall (fixed,
  July 2026):** `WaterManager._on_chunk_deconstructed/_restored` calls
  `reposition_to_outer_wall()` on every registered hookup for EVERY chunk
  dig/restore anywhere in the bunker, not just digs on the hookup's own
  wall — that's intentional, it's how the hookup notices its wall moved.
  The bug: `reposition_to_outer_wall()` used to call
  `update_graph_node_position()` (delete+refund the touching pipe edge,
  see above) unconditionally at the end, even when the raycast landed on
  the exact same wall the hookup was already mounted on (i.e. an unrelated
  dig elsewhere). Net effect: expanding ANYWHERE in the bunker silently
  deleted the hookup's pipe connection, even with zero actual movement.
  FIX: `reposition_to_outer_wall()` now compares the raycast-derived
  position against the hookup's current position first and returns early
  (no position change, no `update_graph_node_position()` call, no
  delete/refund) when they match. Only a genuine reposition — the wall
  actually moved further out, or the Move tool relocated it — reaches
  `update_graph_node_position()`.
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
- **Real flow/pressure simulation:** `WaterSolver.gd` (Jul 2026) allocates by
  priority tier + live demand, but is still NOT real fluid pressure/pipe-
  diameter/distance-loss physics — that's a bigger future simulation layer,
  not this. `WaterGraph`/`WaterManager`/`WaterSolver` are already split apart
  the same way `PowerGraph`/`PowerRegistry`/`PowerSolver` are specifically so
  a real physics layer can slot in later without another mid-project
  refactor (see `docs/systems/power/README.md`'s own history of why that
  split was expensive when done late).
- **Water quality decay/mixing over time:** `WaterHookup.water_quality` and
  `WaterDispenser.stored_water_quality` are both static placeholder values
  this pass — a future pass would tick them down over time and/or model
  mixing (e.g. a dispenser's stored water reflecting a running average of
  what it's received). Both fields already exist and are already wired into
  their respective UI displays, so a future decay/mixing system only needs
  to mutate the values, not introduce them or their UI.
- ~~Priority adjustment UI for `WaterTestSink`/`WaterDispenser`~~ — **DONE
  (Jul 2026, same day).** Both devices now have a `PowerPriorityUI.gd`-style
  ◄ N ► changer: `WaterTestSink`'s lives in `WaterInfoUI.gd`'s sink branch,
  `WaterDispenser`'s lives directly in `WaterDispenserUI.gd`. Both set
  `priority` straight on the device node (no manager setter call needed —
  `WaterSolver._read_priority()` already reads it live off `consumer_ref`
  every solve).
- **New pipe-drawing UX (the full continuous-paint upgrade):** replace
  `WaterPipeDrawMode`'s per-click confirm loop with a live multi-segment path
  preview that walks around however many corners the cursor's projected
  position crosses, confirmed all at once — see the file's own header
  comment for the exact scope of what's deferred.
