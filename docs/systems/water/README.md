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
entirely. (Jul 2026, Purifier pass) Hookup water quality now genuinely
decays over time, a `WaterPurifier` device can be attached to any pipe run to
restore water passing through it to 100%, `WaterDispenser` blends incoming
quality into its stored tank volume-weighted, and a build-mode-only scrolling
arrow overlay shows flow direction on every pipe — see Purification & Quality
below. (Jul 2026, Part B) `WaterPipeDrawMode` now traces and confirms a full
multi-leg run in one click (continuous paint-along-wall mode), with pillar
clearance built in — see Known tradeoffs for the exact interpretation call
made and the `PAINT_MODE_ENABLED` fallback toggle. **Still explicitly NOT in
scope**: pumps, a real per-meter/per-second transit simulation (purification
and decay are instantaneous/topological, not physically modeled travel time
or delay).

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

## Purification & Quality (Jul 2026)
- **Decay:** `WaterHookup.water_quality` drains `1.0/24.0` (%/game-hour) —
  i.e. -1%/game-day, matching this project's standing "units per game hour"
  convention (`PlayerStats.gd`'s food/water/sleep drain rates, scaled via
  `delta / _seconds_per_game_hour` each frame). One-directional: floors at
  `0.0`, nothing raises it back up at the source — that's what the Purifier
  is for, downstream.
- **Admin cheat (F7 menu, Jul 2026):** `AdminMenu.gd`'s WATER section
  scales the single hookup's `water_quality` by ×0.5 / ×1.5 (clamped
  0-100) — relative to its current value, not a flat ±50 — via
  `WaterManager.get_the_hookup()`. Same panel also has a TIME section
  (`PlayerStats.set_elapsed()` jump of exactly `day_duration_seconds`, a
  pure clock skip — no extra stat drain applied) alongside the existing
  POWER cheat (see `docs/systems/power/README.md`).
- **Purification algorithm:** a consumer's water is pure (100%) iff EVERY
  path from the hookup to it passes through at least one `"purifier"`-role
  graph node. Computed as a single filtered BFS per solve —
  `WaterGraph.get_unpurified_reachable_keys(hookup_key)` returns every node
  reachable WITHOUT traversing into a purifier node (the "contaminated
  set"); any consumer in that set is impure, any consumer normally reachable
  but NOT in it is pure. Self-corrects automatically on any topology change
  (new pipe, bypass drawn around a purifier, purifier deleted) — recomputed
  fresh every call, no invalidation logic needed.
  `WaterManager.get_received_rate_mL()`'s `"quality"` field is the single
  integration point: `100.0` if pure, the hookup's raw `water_quality`
  otherwise.
- **`WaterPurifier.gd`:** construct-menu tile (`TILE_WATER_PURIFIER=20`,
  $240, refunded on delete), attaches directly onto an existing pipe run —
  no floor/wall snap, placed freely wherever it lands on the pipe's line
  (`WaterPurifierAttach.gd`). Splits one graph edge into two around a new
  `"purifier"` node, same shape `WaterPipeElbow`'s `"corner"` split uses.
  Read-only interact panel (`WaterInfoUI`, mode `"purifier"`) — input
  quality (upstream raw) + output quality (always 100%), no slider/toggle/
  priority (not a demand consumer).
- **Deletion order:** deconstructing a purifier does NOT delete either
  adjoining pipe edge — `WaterPurifier.revert_to_corner()` reverts its own
  graph node's role from `"purifier"` back to `"corner"` IN PLACE (same key,
  same edges — `register_node()` is idempotent on role) before its visual is
  freed; the pipe stays fully intact/connected, no pipe refund. Any
  edge-deletion path (`WaterManager.delete_and_refund_edge()` — the
  generalized form of the old `WaterHookup._delete_and_refund_edge()`,
  reused by both the hookup's reposition path and this pass) separately
  REFUSES to delete an edge touching a node still marked role ==
  `"purifier"`. That guard plus "revert first" on deconstruct is what
  enforces "purifier must be removed before the pipe beneath it," with no
  cascade-delete complexity.
- **Dispenser blending:** `WaterDispenser.stored_water_quality` now blends
  volume-weighted every tick water is actually added: `new_avg = (old_volume
  * old_avg + added_volume * added_quality) / (old_volume + added_volume)`.
  `added_mL` is clamped to remaining tank headroom BEFORE the blend, not
  after, so the formula always uses the exact volume added this frame.
- **Flow-direction arrows:** build-mode-only scrolling chevron overlay on
  every pipe segment, showing which way water flows (downstream, away from
  the hookup). `WaterGraph.compute_flow_directions(hookup_key)` — plain BFS
  hop-distance from the hookup, recomputed via
  `WaterManager.recompute_flow_directions()` after any pipe-graph mutation
  (placement, split, purifier insert, edge delete/refund, undo) — NOT every
  frame. Pushed to each live `WaterPipeSegment.set_flow_sign()`. Rendered by
  `assets/shaders/pipe_flow.gdshader` (this project's first `spatial`
  shader) on a second, additive `MeshInstance3D` layered just outside the
  pipe's own radius — the base pipe mesh/material is never touched, stays
  always-visible exactly as before. Visibility toggled per-segment
  (`set_build_mode_visible()`) from `BuildModeController.enter_build_mode()`/
  `exit_build_mode()`, mirroring `WireSegment`'s group-based show/hide
  trigger point without altering the pipe's own always-on visibility.
  **Shader fix (Jul 2026, polish pass):** the shader was scrolling `UV.x`,
  which on a `CylinderMesh` side surface wraps AROUND the circumference, not
  along the length — arrows visibly rotated around the pipe instead of
  sliding along it. `arrow_texture`'s chevrons are drawn along the image's
  own U axis, meant to repeat/scroll along the pipe's length, so the fix
  swaps which mesh UV component feeds which texture axis (`tex_uv = vec2(UV.y,
  UV.x)`) rather than just picking a different single component to scroll —
  see the shader's own inline comment for the full reasoning. Direction
  convention (`flow_sign`/`set_flow_sign()`) unchanged and still correct
  under the fix.
- **Water Quality colour convention:** water quality (0-100%) is always
  shown red/yellow/green: **0-50% red, 50.01-75% yellow, 75.01-100% green**
  (inclusive lower boundary each tier). Applies everywhere quality is
  displayed — hookup/sink panels and the Purifier's read-only panel (all via
  `WaterInfoUI._draw_quality_row()`), and `WaterDispenserUI`'s own Water
  Quality line (via its local `_quality_color()`, deliberately duplicated
  rather than shared — no `class_name` on either UI script, matches this
  water UI system's existing per-file-helper convention). `QUALITY_GOOD_COLOR`
  (real green) is a dedicated constant in both files — kept separate from
  the pre-existing `OK_COLOR` (a blue used for demand/flow-rate "on target"
  readouts, a different meaning, unchanged).
- **Dispenser panel (Jul 2026, polish pass):** added a "WATER QUALITY" line
  directly beneath "STORAGE" (same label/value styling, colour per the
  convention above) — previously `stored_water_quality` was shown only as a
  small dim placeholder line at the panel's bottom; that line is now
  removed (replaced by the new one). "REQUESTED RATE" relabelled to "FLOW
  RATE" (display label only — `requested_rate_mL_per_day` keeps its name,
  it's still the value the slider writes into the solver's demand contract).
- **Pipe placement from consumer devices (Jul 2026, polish pass):** starting
  a pipe run was already generic at the graph level — `WaterPipeDrawMode
  ._try_pick_source()` snaps onto ANY existing water graph node regardless
  of role (hookup/joint/corner/endpoint), so a sink/dispenser (registered as
  role `"endpoint"`) was already a valid pick. The actual bug was in
  `_build_manhattan_path()`: it unconditionally collapsed the source point
  straight to ceiling height with no rise segment, which only looked right
  because the hookup/joints/corners it was designed against already sit at
  ceiling height. Fixed by adding an initial vertical-rise leg, symmetric
  with the existing final vertical-drop leg at the destination end — a
  generic fix (works for any current or future floor-standing device), not
  hookup- or device-specific.
- **Purifier orientation fix (Jul 2026, polish pass):** the placed Purifier
  model rendered perpendicular to its pipe run. Root cause: `orient_along()`
  (called once at spawn) rotates the WHOLE `WaterPurifier` body via
  `look_at()` + `rotate_object_local(RIGHT, 90°)` — the same sequence
  `WaterPipeSegment.gd` uses to align its own mesh's local Y-axis along the
  pipe — but `_build_mesh()` ALSO applied its own extra
  `rotation_degrees = Vector3(90,0,0)` to the body/band `MeshInstance3D`
  children, re-tipping the already-aligned cylinder onto local Z (a double
  rotation). Fix: removed the mesh instances' own extra rotation — they now
  inherit the parent's `orient_along()` rotation directly, with no
  additional child-local rotation needed.
- **Purifier GHOST orientation fix (Jul 2026, same-day follow-up):** the
  above fix corrected the PLACED Purifier but its build-mode GHOST preview
  still rendered perpendicular. Root cause: `GhostPreview._update_ghost()`'s
  shared tail-end rotation line (`rotation_degrees = Vector3(0, current_angle_deg, 0)`)
  only ever expresses a floor-snap Y-axis rotation and is never touched by
  the purifier branch earlier in the function — the ghost inherited whatever
  angle the previously-selected floor/wall tile left behind. Fix:
  `_update_ghost()` now special-cases `TILE_WATER_PURIFIER`, deriving the
  candidate pipe segment's direction (`_ghost_purifier_candidate["seg_node"]`)
  and applying the exact same `look_at()` + `rotate_object_local(RIGHT, 90°)`
  sequence `WaterPurifier.orient_along()` uses on the real node, so the ghost
  always matches what gets placed.
- **Pipe flow-arrow "needs build-mode re-entry" fix (Jul 2026, same-day
  follow-up):** newly placed pipes' scrolling flow-arrow overlay stayed dark
  until the player exited and re-entered build mode. Root cause:
  `WaterPipeSegment._build_arrow_overlay()` always initialized its shader's
  `build_mode_visible` uniform to `false`; the overlay only ever turns on via
  `BuildModeController.enter_build_mode()`'s one-shot
  `call_group("water_pipe_visual", "set_build_mode_visible", true)` broadcast,
  which a segment placed mid-session (build mode already active, the only
  time pipes are ever placed) never receives until the next toggle. Fix:
  `BuildModeController` now adds itself to a `"build_mode_controller"` group
  in `_ready()`; new `WaterPipeSegment._is_build_mode_active()` looks that
  controller up and reads its live `is_active` flag (same `get("is_active")`
  pattern `WireGraphBuilder.gd` already uses) so a freshly spawned segment's
  overlay initializes visible/hidden correctly on the very first frame.
- **Pipe flow-arrow world-space scale + cross-joint phase continuity fix
  (Jul 2026, same-day follow-up):** two related bugs in the same overlay —
  (1) arrows appeared stretched/compressed differently per pipe segment and
  scrolled visibly faster on long pipes than short ones, and (2) arrow
  animation restarted its phase at every joint instead of flowing through.
  Root cause of (1): `pipe_flow.gdshader`'s length-axis UV always spans
  exactly 0-1 across a CylinderMesh segment regardless of its real length,
  so the arrow pattern was stretched to fit once per segment and a
  fixed-UV-rate scroll covered more physical distance/sec on longer pipes.
  Root cause of (2): each segment's UV started at 0 with no knowledge of
  its position along the overall pipe run. Fix: `pipe_flow.gdshader` gained
  `pipe_length`/`tile_world_length` uniforms (scales the length-axis UV by
  real segment length ÷ desired world-units-per-tile before scrolling, and
  scrolls by world-units/sec, not UV/sec — both tile size and scroll speed
  now constant in world-space on every pipe) and a `phase_offset` uniform
  (added into the scaled UV before scrolling). `WaterGraph.
  compute_flow_directions()` was reworked from hop-count BFS to real
  Euclidean cumulative-distance BFS (using nodes' stored `"pos"`), now
  returning `{"a_is_upstream": bool, "phase_offset": float}` per edge instead
  of a bare bool — `phase_offset` is the upstream endpoint's cumulative
  real-world distance from the hookup. `WaterManager.
  recompute_flow_directions()` reads both fields and calls both
  `WaterPipeSegment.set_flow_sign()` and the new `set_phase_offset()`.
  `WaterPipeSegment._build_arrow_overlay()` now also sets `pipe_length` from
  the segment's own real length at build time.
- **Flow-arrow speed/direction/connectivity polish (Jul 2026, same-day
  follow-up):** three fixes on top of the above. (1) Speed: `ARROW_SCROLL_SPEED`
  slowed to `1.2 * 0.7` (playtest feedback — original speed read too frantic
  up close). (2) Direction: reversing `flow_sign` used to only flip the
  scroll's apparent motion, not the baked chevron shape itself (confirmed via
  `assets/textures/water/pipe_flow_arrow.png` — glyphs point a single fixed
  way along +U) — so arrows on a reversed run slid backwards while still
  visually pointing the old direction. Fix: `pipe_flow.gdshader` now mirrors
  the raw length-axis UV (`1.0 - raw_uv`) whenever `flow_sign < 0.0`, before
  tiling/phase/scroll, so the glyph itself flips to match the true flow
  direction, not just its motion. (3) Connectivity: pipe runs not reachable
  from the hookup have no water in them, so they shouldn't show flow at all.
  Added a `has_flow` uniform (default `false`) — `pipe_flow.gdshader`
  discards the whole overlay fragment when `!has_flow`, same as the existing
  `build_mode_visible` gate. `WaterPipeSegment.set_has_flow()` sets it;
  `WaterManager.recompute_flow_directions()` now calls `set_has_flow(true)`
  only for segments present in `WaterGraph.compute_flow_directions()`'s
  result for the live hookup, and `set_has_flow(false)` for every other
  placed segment (dead/orphaned runs). Freshly-placed segments default to
  `has_flow = false` in `_build_arrow_overlay()` until the next
  `recompute_flow_directions()` confirms connectivity.
- **Flow-arrow double-flip bug (Jul 2026, same-day follow-up #2):** the
  direction fix above mirrored the glyph shape via `flow_sign`, but the
  scroll term right below it was ALSO still multiplied by `flow_sign` (left
  over from the original, shape-unaware fix) — so a reversed-flow segment
  correctly flipped its chevron shape to point the true downstream way, but
  then scrolled backwards relative to that shape (motion direction flipped
  twice, canceling out). Confirmed in playtest: a pipe run built starting
  from the hookup animated correctly, but a run built starting from the
  device (same physical direction of flow, opposite draw/registration order)
  showed arrows pointing the right way while visibly crawling backwards.
  Root cause: direction only needs to be encoded once — the mirrored `raw_uv`
  already advances correctly in the true downstream (away-from-hookup)
  direction for every segment uniformly once mirrored, so the scroll no
  longer needs (and must not have) its own `flow_sign` multiplier. Fix:
  scroll term in `pipe_flow.gdshader` now always subtracts the same way
  (`tex_uv.x -= TIME * (scroll_speed / tile_world_length)`, no `flow_sign`
  factor) — direction lives solely in the mirror.
- **Loop/cycle flow-direction fix (Jul 2026):** `WaterGraph.compute_flow_
  directions()` used to be a plain BFS spanning tree from the hookup, plus a
  naive per-edge distance comparison for any "closing" edge that reconnects
  two already-visited nodes (i.e. a real physical loop, not just branching).
  That local comparison always pointed the closing edge INTO whichever
  endpoint was farther from the hookup — but that endpoint is also usually
  the tree's own deepest node in the loop, which already receives an inflow
  from its tree parent. Result: two independent inflows converging on one
  node, arrows visibly meeting at a point instead of circulating. Fix —
  treat each closing edge as completing a fundamental cycle relative to the
  spanning tree: find the two branches' lowest common ancestor (LCA) via
  parent-pointer walk, compare each branch's real-world path length from the
  LCA (shorter/more direct branch is "dominant" and keeps its natural
  tree direction), then **reverse** every tree edge along the "recessive"
  branch's spine (LCA → recessive endpoint) so the whole loop circulates one
  consistent way; the closing edge is oriented dominant-endpoint →
  recessive-endpoint. Exact ties (equally direct branches) are broken by
  **registration order** — whichever branch's LCA-adjacent segment the
  player physically placed/connected first wins (new `_edge_creation_order`
  dict on `WaterGraph`, stamped once per edge_id the first time it's
  registered — edge_id itself is order-independent by design so a separate
  counter was needed). Multiple/nested loops are resolved by processing
  closing edges in creation order, with a `reversed_tree_edges` guard so an
  already-flipped spine from an earlier (older) loop isn't re-flipped by a
  later, overlapping one — the earlier loop's decision wins; heavily
  overlapping multi-loop topologies are handled reasonably but not
  exhaustively proven for every possible nesting. `phase_offset` (used for
  cross-joint scroll continuity) also had to change: raw hookup-BFS distance
  is wrong for reversed edges, so a second pass now walks the graph strictly
  following each edge's FINAL resolved direction from the hookup outward,
  accumulating real distance along the actual flow path, and that's what
  feeds `phase_offset` now. Adding a new branch/connection does NOT re-flip
  an existing, unrelated loop's direction — only cycles whose own topology
  or relative directness actually changes get re-evaluated (this ran on
  every full recompute, but the tie-break math itself only depends on the
  loop's own two branches, so unrelated loops are stable in practice).
- **Ring-main-through-hookup fix (Jul 2026, same-day follow-up):** the fix
  above reverses the recessive branch's entire spine "LCA → recessive
  endpoint" — but when a loop wraps all the way back through the hookup
  itself (the hookup's own two outgoing branches reconnect somewhere
  downstream), the LCA of that closing edge IS the hookup, so "reverse the
  whole spine back to the LCA" reversed a branch all the way back into the
  hookup, giving it an inflow. Visually the whole loop appeared to flow
  backward, pooling at the hookup instead of flowing away from it. The
  hookup is a pure external water source and must never have an inflow,
  full stop, regardless of topology. Fix: `compute_flow_directions()` now
  special-cases `lca == hookup_key` — skip the branch-reversal step
  entirely (both branches keep their natural hookup-outward direction) and
  only decide the closing edge's own direction by the same dominance rule.
  This is also the physically correct behavior for a real ring main: fed
  from one point, water flows both directions around the ring and meets on
  the far side — that meeting point is a normal merge, not the "two
  independent tree-inflows converging mid-tree" bug the original fix
  targeted (that bug is specifically about INTERIOR loops that don't touch
  the hookup at all).
- **"mL/day" now means per in-game day, not per real 24-hour day (Jul 2026,
  same-day follow-up):** `WaterDispenser._process()`'s tank-fill integration
  used to divide `received_mL_per_day` by a literal `86400.0` (real seconds
  in an actual day) against the raw, unscaled frame `delta` — completely
  ignoring the game's compressed clock (`PlayerStats.day_duration_seconds`,
  default 1440 real seconds = 24 real minutes per game day). Every other
  timed system (thirst/hunger/sleep drain, `WaterHookup`'s own quality decay)
  already scales off that compressed clock, so dispensers were filling
  ~60x slower than intended relative to the player's own thirst drain — a
  "2000 mL/day" hookup took a full real 24 hours to deliver 2000mL instead
  of one 24-real-minute game day. Fix: `WaterDispenser` now caches a
  `_player_stats` ref (same lazy lookup/cache pattern `WaterHookup.gd` uses)
  and divides by `_player_stats._seconds_per_game_hour * 24.0` instead of
  `86400.0`, falling back to the real-day constant only if `PlayerStats`
  isn't found yet. `WaterHookup.get_per_minute_output_mL()`'s `/ 1440.0` was
  checked and left AS-IS — that's a display-only "mL/day → mL/min" label
  conversion (literal calendar minutes-per-day), never integrated against a
  real timer, so it carries no such bug.
- **Known gap (save/load):** `WaterManager.get_pipe_network_for_save()` only
  persists `"corner"`/`"pipe_joint"` roled nodes — a `"purifier"` node (and
  both edges touching it) is silently dropped on save/load today. Not fixed
  in this pass — full save/load integration for the water system's
  player-placed infrastructure is the next major project (see HANDOVER.md);
  flagged here so it isn't silently rediscovered as a new bug later.

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
| `WaterPipeDrawMode.gd` | The placement tool. Routes strictly axis-aligned (90°-only) at a fixed near-ceiling height (`WATER_CEILING_Y`), dropping vertically into any floor-standing connectable device. **(Jul 2026, Part B) Continuous paint-along-wall mode** — one click traces/confirms a full multi-leg run with pillar clearance built in; old one-confirm-per-click model kept intact, toggle via `PAINT_MODE_ENABLED` — see its own file-header comment and Known tradeoffs below. **(Jul 2026) Wall-locked routing default** — an open-floor destination now routes along the wall perimeter via `WallPerimeterRegistry`; CTRL held falls back to freeform — see Known tradeoffs. |
| `WallPerimeterRegistry.gd` (`scripts/world/structure/`) | Jul 2026. Sibling to `PillarRegistry` — BFS-queryable wall-segment graph (`find_path_along_wall()`), populated from `WireGraphBuilder`'s `boundary_edges` at the same 3 call sites `PillarRegistry` already is. Consumed only by `WaterPipeDrawMode._trace_wall_locked_path()` — see Known tradeoffs. |
| `WaterTestSink.gd` | Rudimentary test endpoint — the acceptance test for this whole phase (place a hookup, route a pipe around a corner, confirm the sink reports CONNECTED). Interactable (Step 2) — see `WaterInfoUI.gd`. Jul 2026: `priority: int` (1-5) + `fixed_demand_mL_per_day: float` exports, implements `get_current_demand_mL_per_day()` for `WaterSolver.gd`. |
| `WaterInfoUI.gd` (`scripts/ui/water/`) | Step 2, July 2026; extended Jul 2026 (Purifier pass). ONE shared info panel for `WaterHookup`/`WaterTestSink`/`WaterPurifier`, distinguished by a `_mode: String` discriminator (`"hookup"`/`"sink"`/`"purifier"` — was a 2-way `is_source: bool`, extended to a 3rd mode rather than a second ambiguous bool) — sized/complexity-matched to `GeneratorInspectUI.gd`, not the full `PowerTerminalUI` dashboard. All stats recomputed live every redraw, no caching. Purifier branch is read-only (no slider/toggle/priority) — shows input quality (upstream hookup's raw `water_quality`) and fixed output quality (always 100%). Dynamic panel height: `PANEL_H_SOURCE`/`PANEL_H_SINK`/`PANEL_H_PURIFIER`. |
| `WaterSolver.gd` | Jul 2026. Priority-tier demand waterfall — `RefCounted`, `_graph: WaterGraph` back-reference (same split pattern as `PowerGraph`/`PowerRegistry`/`PowerSolver`). Pure read-only queries, no state held between calls. |
| `WaterDispenser.gd` | Jul 2026. The first real water-consuming device — 5000mL storage, on/off, player-tunable requested rate, fill tick driven by the solver's actual grant. `TILE_WATER_DISPENSER` in `BuildModeController`, ground-placed like the test sink. (Jul 2026, Purifier pass) `stored_water_quality` now genuinely blends volume-weighted as water arrives — see Purification & Quality below. (Jul 2026, fill-visual pass) Body mesh uses a `ShaderMaterial` (`assets/shaders/tank_fill.gdshader`) instead of a flat color — bottom portion tints water-blue up to `current_fill_mL/MAX_STORAGE_ML`, rest stays the plain empty-tank color, thin bright waterline band at the cutoff. No new geometry (the box itself IS the gauge). Pushed every frame from `_process()` via `_update_fill_visual()`, same cadence as the existing fill tick — no new polling loop. |
| `WaterDispenserUI.gd` (`scripts/ui/water/`) | Jul 2026, restyled same day. Hand-drawn `_draw()` panel (matches `WaterInfoUI`/`PowerPriorityUI`) with real `HSlider`/`Button` controls overlaid — fill level, rate slider (0 to the live dynamic max), effective (actually received) rate, on/off pill toggle, ◄ N ► demand-priority changer, live blended water quality. (Jul 2026 fix) Added an actual drawn fill bar/gauge under the STORAGE text (previously text-only) — `PANEL_H` `430 -> 454` to fit. |
| `WaterPurifier.gd` (Jul 2026) | Construct-menu tile (`TILE_WATER_PURIFIER=20`, $240, Water submenu) that attaches directly onto an existing pipe run — splits one graph edge into two around a new `"purifier"`-role node, no floor/wall snap. Read-only interact panel (`WaterInfoUI`, mode `"purifier"`). Deconstruct reverts its node's role back to `"corner"` in place (pipe stays intact, no pipe refund) rather than deleting either adjoining edge — see its own file header for the full deletion-order design. (Jul 2026, Purifier Filter plan) Owns `filter_quality` (0-100, depletes over `FILTER_LIFESPAN_DAYS=10` in-game days via its own `_process()`), `get_output_quality()` (`50 + filter_quality*0.5`), `replace_filter()`, `spawn_starting_filters()` — see the dedicated Purifier Filter section below. |
| `WaterPurifierAttach.gd` (Jul 2026) | Static-only placement math for the Purifier tile — candidate-finding (`find_purifier_candidate()`) + graph insertion (`insert_purifier_at()`). Deliberately duplicates `WaterPipeDrawMode`'s split-candidate shape rather than modifying that file (documented history of subtle bugs there) — the one real difference: no grid-snap, placed freely wherever it lands on the pipe's line. Shared by both `GhostPreview.gd` (validity/position preview) and `BuildModeController._spawn_placed_object()` (actual insertion on confirm) — one copy, not duplicated a second time between those two callers. Calls `purifier.spawn_starting_filters()` right after `orient_along()` (Jul 2026, Purifier Filter plan). |
| `PurifierFilterItem.gd` (`scripts/world/items/`, Jul 2026) | Pickupable consumable for `WaterPurifier` — ONE script for both "fresh" and "Used Purifier Filter (X%)" states, mirrors `WaterBottle.gd`'s established single-script pattern. Physics/pickup/drop/knockout copied from `FoodCan.gd`. `on_use()` finds the nearest `WaterPurifier` (group `"water_purifier"`, range `REPLACE_RANGE=2.5`, same value as `WaterBottle.REFILL_RANGE`) and calls its `replace_filter(self)` — the item itself doesn't own any swap logic. `spawn_at()` static helper (used for both the two starting filters and every ejected Used filter) drops a new instance at a small random offset near a given position, never auto-added to inventory. |
| `assets/shaders/pipe_flow.gdshader` (Jul 2026) | Build-mode-only scrolling arrow overlay, applied as a second additive `MeshInstance3D` on every `WaterPipeSegment` (base pipe mesh/material untouched — still always visible). This project's first `spatial` shader. (Jul 2026 redesign) Both quality/purity lanes collapsed onto just the ceiling-facing strip (`v_up_dot` world-normal test, `UP_BAND_DOT=0.55`), arranged as a repeating along-pipe [quality tile][purity tile][gap] sequence (`gap_world_length` uniform) instead of a front/back circumference split — see the dedicated section below. |
| `assets/shaders/tank_fill.gdshader` (Jul 2026) | `WaterDispenser`'s body-mesh fill-level gauge — REPLACES the box's flat `StandardMaterial3D` (not an overlay). Object-local `VERTEX.y` cutoff against a `fill_pct` uniform; water-blue below, empty-tank color above, thin waterline band at the cutoff. No new geometry. |

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
`stored_water_quality: float` (0-100, volume-weighted blend as water
arrives — see Purification & Quality above; also drives the Dispenser UI's
Water Quality line, see Water Quality Colour Convention below).

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
- **Wall-locked pipe routing added (Jul 2026):** when a run's destination
  resolves to open floor space (`_resolve_destination()`'s raw grid-snap
  fallback — no existing node, no mid-span split), the default routing is
  now `_trace_wall_locked_path()` — BFS along the bunker's wall perimeter
  via a new sibling registry `WallPerimeterRegistry.gd`
  (`scripts/world/structure/`, same ownership shape as Part A's
  `PillarRegistry`: instanced once by `MainWorld._setup_wall_perimeter_registry()`,
  found via group `"wall_perimeter_registry"`), instead of a raw diagonal-
  shortest Manhattan cut straight across the room. Populated by
  `WireGraphBuilder._push_wall_perimeter_registry(boundary_edges)`, called
  at the same 3 solve entry points `_push_pillar_registry()` already is
  (initial pregen solve + every incremental chunk dig/restore) — reuses the
  electrical perimeter's own `boundary_edges` topology rather than
  re-deriving wall shape from scratch. `ADJACENCY_RADIUS`=1.1m (registry
  entries are 1.0m apart along a straight wall run, ~0.707m apart at a
  convex corner — verified from `WireGraphBuilder`'s own pillar/boundary
  math, NOT the 0.3m a stale planning doc assumed).
  - **CTRL held = escape hatch back to today's freeform routing**
    (`_trace_wall_hugging_path()`, unchanged) — see `WALL_LOCKED_ROUTING_ENABLED`
    and the shared `_trace_active_path()` chooser both `_update_ghost_preview()`
    and `_try_confirm_full_path()` now call instead of the freeform trace
    directly, so ghost preview and confirm can never disagree about which
    mode a given click used.
  - **Anchored destinations always keep freeform routing** regardless of
    CTRL — an existing node or a mid-span T-split is already a valid real
    connection point, wall-locking only ever applies to a fresh open-floor
    run.
  - `_trace_wall_locked_path()` returns the exact same
    `{waypoints, waypoint_keys, valid, final_key}` shape as the freeform
    trace, so it plugs into `_try_confirm_full_path()`'s existing generic
    node/edge/segment spawning loop with zero duplication there. Every hop
    between consecutive raw points (source → each wall waypoint → dest) is
    individually re-run through the existing `_build_manhattan_path()` —
    this is what keeps the whole thing strictly axis-aligned even where two
    consecutive registry wall-segment entries are diagonally adjacent at a
    convex corner (not collinear). Pillar-clearance dogleg
    (`_dogleg_corner_around_pillars()`/`_leg_clears_all_pillars()`) is
    applied per corner exactly like the freeform trace.
  - Falls back to freeform automatically whenever wall-locking isn't
    applicable: registry null/empty (e.g. before the first perimeter solve
    completes), or no nearest-segment/BFS-path found (shouldn't happen for
    a connected perimeter, but fails safe).
  - **FIXED (Jul 2026, overlap-block pass):** wall-locked routing now runs
    `_avoid_existing_pipes()` on its full `raw_points` chain (right before
    the per-corner pillar-clearance loop) — same detour behavior the
    freeform trace already got via `_resolve_single_leg()`. See "Overlap
    block (unreroutable case)" below for what happens when even the
    detour can't clear a conflict.
  - **FIXED (Jul 2026, diagonal-detour bug):** the overlap-block pass above
    ran `_avoid_existing_pipes()` directly on the fine-grained
    `WallPerimeterRegistry` waypoint chain (one point per wall segment
    along a straight run), unlike `_resolve_single_leg()`'s
    `_build_manhattan_path()` output which is already collapsed to source
    → one corner → dest. That meant every tiny wall-segment hop got its
    own independent sidestep decision off a very short (`path[i+2]`, one
    hop ahead) lookahead — noisy enough that the sidestep sign could flip
    hop-to-hop, producing a staircase of small perpendicular jogs that
    read as a genuinely diagonal line on screen. New
    `_collapse_collinear_points()` runs right before
    `_avoid_existing_pipes()` in `_trace_wall_locked_path()`, dropping any
    interior point whose in/out leg directions match (i.e. not a real
    turn) so the detour pass only ever sees the handful of TRUE corners —
    same shape it already handled correctly for the freeform trace. Every
    resulting leg stays strictly axis-aligned; no diagonal segments.
  - **FIXED (Jul 2026, diagonal-detour bug round 2 — real corners were
    getting deleted):** the round-1 fix above still produced real
    (sometimes large) diagonal segments, especially right at a hookup with
    a very short entry/exit leg. Two separate leaks, both fixed in the same
    pass:
    1. `_build_manhattan_path()` skips its corner-insertion branch whenever
       one axis delta is `<= MIN_POINT_GAP` (treated as "already aligned
       enough") — but it then still appended the raw target point carrying
       that small non-zero delta on the skipped axis, producing a subtle
       but genuine diagonal leg (e.g. a 0.02m x-drift on what should've
       been a pure z-move). Fixed by snapping that negligible axis to
       exactly match the start point's coordinate instead of leaving the
       raw drift in place.
    2. `_collapse_collinear_points()`'s degenerate-length guard `continue`d
       (i.e. DELETED) any point whose incoming OR outgoing leg was shorter
       than `MIN_POINT_GAP` — but deleting a point doesn't just drop a
       redundant near-duplicate, it bridges that point's two now-non-
       adjacent neighbors directly. Those neighbors are essentially never
       on the same axis as each other (that deleted point was exactly what
       kept them aligned), so the result was a real diagonal jump — the
       "A" shape / long diagonal segments reported right at hookups.
       Fixed by restructuring into two passes: pass 1 spatially dedupes
       near-duplicate CONSECUTIVE points into one (pure merge, no
       direction logic, so a short leg's corner-ness is never lost); pass
       2 then runs the same-direction collapse on the deduped list, where
       every remaining pair is guaranteed non-degenerate so the collapse
       can never fire on a phantom short leg.
    Net effect: every point handed downstream to `_avoid_existing_pipes()`
    and the pillar-dogleg loop is now guaranteed strictly axis-aligned
    relative to its immediate neighbor, with no near-diagonal drift and no
    silently-deleted corners.
  - **FIXED (Jul 2026, backward-jog entry-leg bug):** a wall-locked run
    could take a small but real backward hop right at the source before
    correctly turning toward the destination (e.g. a hookup sitting almost
    equidistant between two consecutive `WallPerimeterRegistry` segments —
    one behind it relative to the destination, one ahead — would jump to
    the BEHIND one first). Root cause:
    `_trace_wall_locked_path()` anchored onto the wall using
    `WallPerimeterRegistry.get_nearest_segment_key()` at each end, which
    picks the absolute-nearest segment in isolation with no awareness of
    which direction the destination actually is — nothing stopped it
    picking the segment on the wrong side. Fixed with a new anchor picker,
    `_pick_shortest_wall_path()`: it gathers the small set of segments
    near the source and near the destination
    (`WallPerimeterRegistry.get_nearby_segment_keys()`, new method,
    `WALL_ANCHOR_CANDIDATE_RADIUS`=1.5) and runs
    `find_path_along_wall()` across every from/to combination, keeping
    whichever pair produces the fewest hops. A backward pick always costs
    at least one extra hop versus the forward-facing alternative, so the
    shortest-path criterion reliably selects the correct-direction anchor
    at both ends without needing any explicit direction/angle math.
- **Continuous paint-along-wall mode implemented (Part B, combined refactor
  pass, Jul 2026):** `WaterPipeDrawMode` now traces and confirms a FULL
  multi-leg run in one click instead of one leg at a time. New pure
  extraction `_resolve_single_leg(from_pos, cursor_pos)` (verbatim what the
  old per-leg ghost preview computed: `_resolve_destination()` →
  `_build_manhattan_path()` → `_avoid_existing_pipes()` → `_is_path_in_bounds()`).
  `_trace_wall_hugging_path()` loops it from the drag source toward the
  cursor, auto-chaining through already-placed graph nodes/joints that lie
  on the way (capped at `MAX_TRACE_LEGS`=20 hops) — **documented
  interpretation call**: "wall-hugging" here means auto-chaining through
  EXISTING placed nodes en route to the cursor (since a real network
  typically already hugs walls), NOT novel pathfinding around undiscovered
  wall/room geometry the player hasn't built pipe through yet. The
  original plan's pseudocode predates several later playtest-era rewrites
  (T-splits, crossing-insertion, overlap detours, shorter-axis-first
  heuristic) it never accounted for — flagged transparently, not silently
  assumed. `_try_confirm_full_path()` replaces `_try_confirm_segment()` as
  the LMB click handler, walking the traced waypoints leg-by-leg and
  reusing `_insert_crossings()` + the existing node/edge/segment
  registration shape per leg, with ONE total cost/spend/`pipe_placed` emit
  covering the whole run instead of per-leg. **`_try_confirm_segment()` and
  the old per-leg ghost preview body (`_update_ghost_preview_single_leg()`)
  are kept fully intact and callable** — `PAINT_MODE_ENABLED` (const, top of
  file) flips instantly back to the old one-confirm-per-click model if the
  paint UX has rough edges, no code deletion needed to recover it (per the
  original plan's own §A.6 recommendation, given this is the most complex
  change in this pass).
- **Pillar clearance added (Part B, same pass):** `PillarRegistry` (Part A)
  feeds `WaterPipeDrawMode._leg_clears_all_pillars()` (mid-leg segment check
  via the same closest-point-on-segment math already used for pipe-vs-pipe
  collinear checks). A mid-leg pillar clip is an INVALID placement (red
  ghost / blocked confirm) — explicitly NOT a pathfind-around, to avoid
  over-engineering a rare case; flag to Brannon if it comes up often in
  practice. Vertical drops into floor devices are exempt (pillars are a
  ceiling-height horizontal-run concern only).
- **Corner-pillar dogleg fix (root cause found + fixed, Jul 2026):** the
  original corner-clearance handling (`_adjust_for_pillar_clearance()`)
  pushed a violating elbow point radially straight away from the pillar's
  center — moving it on BOTH axes at once, which silently broke the
  90°-only routing guarantee right at the four pregen corner pillars
  (visually: a short diagonal clip instead of a clean bend). Replaced with
  `_dogleg_corner_around_pillars()`: when an elbow lands inside a pillar's
  clearance radius, it's swapped for a small 3-point rectangular "step"
  detour (extend the incoming leg a bit further along its own axis, jog
  sideways one short perpendicular segment, correct back onto the outgoing
  leg's axis) so every resulting segment stays strictly axis-aligned. Each
  new sub-leg is still re-validated through `_leg_clears_all_pillars()`
  exactly as before. `_PILLAR_DOGLEG_MARGIN`=0.12m is the buffer added on
  top of `PILLAR_CLEARANCE_RADIUS` for the two jog segments.
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
  - **Overlap block (unreroutable case) — added Jul 2026, overlap-block
    pass:** the single-pass "known limitation" directly above (no
    recursive re-check of the detour itself) used to mean a run jammed
    flush against a wall/corner with zero room to jog sideways would
    silently place a pipe still doubled over an existing one. Now caught
    at confirm time by `_path_has_unreroutable_overlap()` — re-runs
    `_find_collinear_conflict()` over every leg of the FINAL, already-
    detoured path (both `_try_confirm_segment()`'s single-leg path and
    `_try_confirm_full_path()`'s paint-mode `waypoints`); if any leg still
    overlaps after the detour, placement is blocked entirely (no spend, no
    graph mutation) and a red fade-in/fade-out banner fires via
    `InventoryHUD.show_error_message()` (`WaterPipeDrawMode._show_error()`
    — same convention `ShelfUI._show_error()` already reuses, deliberately
    kept separate from `_show_warning()`'s `HUD.show_soft_warning()` path
    used for out-of-bounds/no-destination/no-cash). Reroutable legs never
    reach this check — the detour already cleared them, so normal
    auto-detour behavior is unchanged. `WaterPipeDrawMode.inventory_hud` is
    wired in from `MainWorld._connect_water_pipe_inventory_hud()`, deferred
    by one frame the same way `_connect_wire_draw_mode()` already is (the
    node doesn't exist yet when `_connect_inventory()` normally runs).
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
- ~~Farming trays as demand consumers~~ — **DONE (Jul 2026).**
  `FarmingTray.gd` (`scripts/world/farming/`) registers as an "endpoint"
  demand consumer exactly like `WaterTestSink`/`WaterDispenser` (fixed
  1000/2000 mL/day, tier-adjustable priority) — zero changes needed to
  `WaterGraph`/`WaterManager`/`WaterSolver` themselves. Water quality is
  deliberately NOT read by Farming (a low-quality-water-to-trays strategy
  is intentional design, not an oversight) — see
  `docs/systems/farming/README.md`.
- **Real flow/pressure simulation:** `WaterSolver.gd` (Jul 2026) allocates by
  priority tier + live demand, but is still NOT real fluid pressure/pipe-
  diameter/distance-loss physics — that's a bigger future simulation layer,
  not this. `WaterGraph`/`WaterManager`/`WaterSolver` are already split apart
  the same way `PowerGraph`/`PowerRegistry`/`PowerSolver` are specifically so
  a real physics layer can slot in later without another mid-project
  refactor (see `docs/systems/power/README.md`'s own history of why that
  split was expensive when done late).
- ~~Water quality decay/mixing over time~~ — **DONE (Jul 2026, Purifier
  pass).** `WaterHookup.water_quality` decays -1%/game-day
  (`QUALITY_DRAIN_PER_GAME_HOUR`); `WaterDispenser.stored_water_quality`
  blends volume-weighted as water arrives; `WaterPurifier` restores quality
  to 100% for anything downstream of it. See Purification & Quality below.
- **Pump / booster device:** no pressure/throughput-boosting device exists
  yet — everything today is gravity/graph-topology only, no real physics.
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

## Water Bottle Refill (Jul 2026 — Part C rework)
`WaterBottle.gd` (`docs/systems/furniture-items/README.md`) is not part of
the water graph/solver — it's a hand-carried consumable — but it now draws
directly from `WaterDispenser.current_fill_mL`, so the two files are coupled
enough to note here:
- Replaced the old fixed 2-sip model (`WATER_PER_SIP`/`TOTAL_SIPS`) with a
  continuous mL model: `MAX_FILL_ML=750.0`, `current_fill_mL` (spawns full),
  `stored_water_quality` (spawns 100). `_is_empty()` is now a computed check
  (`current_fill_mL <= 0.0`), not a one-way latch — refilling a drained
  bottle un-empties it.
- **Drinking** (tap E, `on_use()`): removes `min(STANDARD_DRINK_ML=375.0,
  current_fill_mL)`, restoring hydration scaled proportionally
  (`STANDARD_HYDRATION=21.5 * amount_removed / STANDARD_DRINK_ML`) — draining
  a partly-empty bottle still gives partial hydration instead of a full dose.
- **Refilling** (hold E near a `WaterDispenser`, `bottle_refill_tick(delta)`):
  mirrors `FuelCan.refuel_tick()`'s shape exactly — nearest-node lookup
  (`_find_nearest_dispenser()`, `REFILL_RANGE=2.5`, group `"water_dispenser"`
  — `WaterDispenser._ready()` now joins this group), transfer clamped to both
  the bottle's headroom and the dispenser's remaining volume, at
  `REFILL_RATE_ML_PER_SEC=60.0` (derived the same way `FuelCan.FUEL_RATE` was:
  full-capacity ÷ 12.5s). Draining `dispenser.current_fill_mL` directly
  (bypassing `WaterSolver`) is intentional — the dispenser's own tank is
  already the "spent" resource once it's in storage, same as a generator's
  `set_generator_fuel()` write from `FuelCan.refuel_tick()`.
- **Quality blend:** identical volume-weighted formula to
  `WaterDispenser._process()`'s own hookup-blend (`new_avg = (old_volume *
  old_avg + added_volume * added_quality) / (old_volume + added_volume)`) —
  the bottle blends its own `stored_water_quality` against the dispenser's.
- `InteractionSystem._tick_continuous_bottle_refill()` runs every frame
  alongside `_tick_continuous_refuel()` (`docs/systems/player/README.md`),
  gated the same way (`_is_holding_e` + `has_method()` duck-type check).
- **HUD badge:** `WaterBottle.get_bottle_badge_info()` returns `{"fill_pct",
  "fill_mL", "max_fill_mL", "quality"}`, checked by `InventoryHUD._draw()`
  ahead of the generic charge-count fallback chain (`docs/systems/ui/README.md`).
  Badge shows a two-line "Xml/750ml" / "(Q%)" label (single line would
  overflow the 64px slot) coloured by quality using the same red/yellow/green
  thresholds as `WaterDispenserUI`/`WaterInfoUI` (0-50 red, 50.01-75 yellow,
  75.01-100 green) — duplicated per this project's existing per-file-helper
  convention, not shared via a base class. At 0mL (`fill_mL <= 0.0`) the
  badge instead shows a single dim "EMPTY" line via
  `InventoryHUD._draw_empty_badge()`.
- **Empty state (Jul 2026):** no separate scene/class — purely a display
  state derived from `_is_empty()` (`current_fill_mL <= 0.0`). While empty,
  `get_display_name()` returns `"Empty Water Bottle"` (shown in the ground
  prompt, held-item name, and inventory slot label) instead of the normal
  "Water Bottle" + readout. Refilling from a dispenser (`current_fill_mL`
  rising above 0 in `bottle_refill_tick()`) flips it straight back to a
  normal bottle with normal mL/quality readouts everywhere — same object,
  no state to migrate.
- **Prompt text (Jul 2026):** ground pickup (`get_prompt_text()`), drink and
  refill lines (`get_use_prompt()`) all show the same
  `"Xml/750ml (Q%)"` fragment via `WaterBottle._fill_quality_bbcode()`,
  colour-coded by quality using `[color=#hex]` BBCode. Requires the shared
  world-space prompt Label (`InteractPrompt.tscn` → `Panel/Label`) to be a
  `RichTextLabel` with `bbcode_enabled = true` (converted from a plain
  `Label` — see `docs/systems/ui/README.md`). Other items' `[F]`/`[E]`/`[G]`
  bracketed prompt text is unaffected: unrecognized BBCode tags render as
  literal text in Godot 4's `RichTextLabel`.

## Wall-locked pipe routing — three follow-up fixes (Jul 2026)

Three issues reported after the wall-locked routing feature (see "Wall-locked
routing" under Known tradeoffs) shipped:

- **Fix 1 — wall-hugging pipes clipped into the wall mesh.**
  `WallPerimeterRegistry` positions sit exactly AT the wall/boundary face
  (correct for flush-mounted electrical wires, which have no radius), but a
  pipe has real thickness (`WaterPipeSegment.PIPE_RADIUS = 0.09`) and visibly
  embedded into the wall when routed through those same positions unmodified.
  - Added `WallPerimeterRegistry.get_segment_angle(key)` — returns the wall
    face's outward-facing orientation in degrees, already carried (unused
    until now) on every `boundary_edges` entry via `WireGraphBuilder`'s
    `DIRS` table (left→180°, right→0°, top→90°, bottom→270°).
  - `find_path_along_wall()` now returns `Array[String]` of ordered segment
    **keys** instead of raw `Vector3` positions — its one caller,
    `WaterPipeDrawMode._trace_wall_locked_path()`, needs both position AND
    angle per waypoint, so handing back keys lets it call
    `get_segment_pos()`/`get_segment_angle()` itself rather than baking a
    position-only return shape into the registry.
  - `_trace_wall_locked_path()` pulls each wall waypoint inward (into the
    room, off the wall face) by a new `WALL_PIPE_OFFSET`-driven calc:
    `inward_dir = Vector3(-cos(rad), 0, sin(rad))` where
    `rad = deg_to_rad(angle)`, offset applied before reprojecting to
    `WATER_CEILING_Y`. New constant `WaterPipeDrawMode.WALL_PIPE_OFFSET =
    0.15` (radius + margin).
- **Fix 2 — stale orphaned pipe-graph nodes after undo/delete.**
  `WaterGraph.unregister_edge()` only ever removed the edge + adjacency
  entries, never the now-degree-0 waypoint node itself — so `"corner"`/
  `"pipe_joint"` nodes left behind a deleted/undone pipe run persisted
  forever in `_water_nodes` and kept snapping new pipe placements to their
  stale positions.
  - Added `WaterGraph.node_degree(key)` and
    `WaterGraph.prune_orphan_waypoint(key)` — the latter erases a node ONLY
    if its role is `"corner"` or `"pipe_joint"` AND its degree is 0; never
    touches `"hookup"`/`"endpoint"`/`"purifier"` roles (their own lifetimes
    are managed elsewhere). Forwarded through `WaterManager.
    prune_orphan_waypoint(key)`.
  - Wired into both places that fully delete an edge:
    `WaterManager.delete_and_refund_edge()` (hookup reposition + purifier-
    adjacent deletion) prunes both endpoints right after `unregister_edge()`;
    `BuildUndoStack.gd`'s `"pipe"` undo case captures every edge's `"a"`/`"b"`
    keys (via `wm.get_edges()`) BEFORE unregistering (the edge dict is gone
    afterward), dedups, then prunes all touched keys once every edge in the
    run is gone. The mid-span-split path (`_split_pipe_at()`) is untouched —
    it immediately re-attaches the same keys to new edges, so nothing is
    ever actually orphaned there.
- **Fix 3 — missing elbow spheres at bend/turn waypoints.**
  `_try_confirm_full_path()`'s per-leg spawn loop determined "is this the
  final point, so register `pipe_joint` with no elbow" by checking
  `i == points.size() - 1` **within each leg** — so every leg-boundary
  waypoint (a real 90°-turn bend, e.g. a pillar dogleg or a wall-locked
  routing corner) was wrongly treated as a run endpoint and silently got no
  `WaterPipeElbow` visual, even though the exact same crossing-insertion
  branch elsewhere in the same loop already proved elbows work fine for mid-
  leg bend points.
  - Fix: track `is_final_leg = (leg_i == waypoints.size() - 2)` outside the
    per-point loop; a point only gets `"pipe_joint"` (no elbow) when it's
    BOTH the last point of its leg AND `is_final_leg` is true — i.e. only the
    very last point of the entire confirmed run. Every other bend point,
    including all leg-boundary waypoints previously skipped, now gets a
    `"corner"` node + a spawned `WaterPipeElbow`, identical to the existing
    crossing-insertion branch.
  - `_try_confirm_segment()` (the older one-leg-at-a-time confirm path) was
    checked and does NOT have this bug — it only ever traces a single leg,
    so its existing `i == points.size() - 1` check already correctly means
    "last point of the whole (one-leg) run." No change needed there.

### Follow-up pass (Jul 2026) — wall embedding tuning + elbow overcorrection

The three fixes above landed real regressions of their own, reported after
in-editor testing:

- **Wall embedding tuning.** `0.15` wasn't quite enough clearance for
  `PIPE_RADIUS = 0.09` once the tube's actual rendered thickness was seen
  in-editor — bumped `WaterPipeDrawMode.WALL_PIPE_OFFSET` to `0.22`. Tuning
  only; the offset formula/geometry itself (verified against
  `WireGraphBuilder`'s `DIRS` table for all 4 wall orientations) was already
  correct.
- **Elbow overcorrection.** Fix 3 above (`is_final_leg`) swung too far the
  other way: wall-locked routing chains through *every*
  `WallPerimeterRegistry` segment along a straight wall run (~1m apart, one
  per cleared-cell wall face), not just actual corners — so it made EVERY
  leg-boundary waypoint a `"corner"` + visible `WaterPipeElbow`, including
  straight pass-through points with no real direction change.
  - Fix: `_try_confirm_full_path()` now computes a `waypoint_is_turn[]` array
    up front — for each interior waypoint, compares the normalized
    direction-in vs. direction-out vectors; `dot < 0.999` means a real turn.
    The per-point role decision is restructured into `is_leg_boundary` /
    `is_run_end` (final point of the final leg) / `is_real_bend`
    (leg-boundary + not run-end + `waypoint_is_turn` true) /
    `is_pass_through` (leg-boundary + not run-end + not a real bend). Only
    `is_real_bend` points get `"corner"` + a spawned elbow; `is_run_end` and
    `is_pass_through` both get `"pipe_joint"` with no elbow. Topology (nodes/
    edges/adjacency) is identical either way — only the `role` string and
    whether a decorative elbow spawns differ, so this has no effect on flow/
    reachability/graph structure.
- **Flow-arrow overlay reported completely broken** (not just at bends) —
  investigated and ruled out: `WallPerimeterRegistry` key-vs-position
  return-shape change (only caller already updated correctly), the elbow/
  role overcorrection above (topology-identical either way),
  `prune_orphan_waypoint()`/`node_degree()` (only wired into deletion paths,
  not fresh placement), `compute_flow_directions()` / `get_hookup_keys()` /
  `register_edge()` / `register_node()` (read in full, no bug spotted),
  `pipe_flow.gdshader` and `WaterPipeSegment.gd`'s arrow-overlay code
  (untouched by the offending commit). Confirmed working again in-editor
  after this pass (playtest feedback: "much better") — the exact turning
  point isn't captured in a dedicated commit message, but no further symptom
  was reported beyond the cross-joint continuity issue documented below, so
  this is considered resolved. The `[FlowDebug]` tag prints added to
  `WaterManager.recompute_flow_directions()` (hookup count, node/edge
  counts, whether the computed `directions` dict comes back empty) are kept
  intentionally (Brannon's explicit instruction) rather than stripped now
  that the symptom is gone — cheap insurance if it ever regresses.

### Cross-joint phase continuity fix (Jul 2026, follow-up)

Arrows animated fluidly along any single segment but visibly
"stuttered"/restarted at every joint between segments — each
`WaterPipeSegment`'s overlay looped its own animation independently instead
of one continuous crawl along the whole pipe run.

- **Root cause:** `pipe_flow.gdshader` derived its "position along the pipe"
  coordinate from the mesh's own `UV.y` (a `CylinderMesh` side surface's
  standard 0-1 span along its length), and encoded flow direction by
  mirroring that same coordinate (`1.0 - UV.y`) around **each segment's own
  midpoint** whenever `flow_sign < 0`. That mirror is segment-local — it
  flips correctly within one segment, but nothing ties one segment's 0-1
  span to its neighbor's in a way that matches
  `WaterGraph.compute_flow_directions()`'s existing "phase_offset counted
  continuously from the hookup outward" convention. Combined with
  `tiles_per_segment`/`phase_offset` scaling that same UV, every segment's
  tile pattern was internally fluid but discontinuous with its neighbor at
  every joint — a real bug independent of (and layered on top of) the
  earlier world-space-scale fix above.
- **Fix:** replaced the UV.y-based coordinate with a **vertex-space**
  coordinate instead. `WaterPipeSegment._rebuild_mesh()`'s `look_at()` +
  fixed 90°-local-X-rotation always orients each segment's local +Y axis
  toward its own `point_b`, regardless of the segment's world orientation —
  so a coordinate built from raw local vertex position is `0` at `point_a`
  and `1` at `point_b` for every segment uniformly, independent of Godot's
  `CylinderMesh` UV winding (never relied on again). `pipe_flow.gdshader`
  gained a `vertex()` function writing a new `varying float v_ab_uv` from
  `VERTEX.y / pipe_length + 0.5`, and a single unified coordinate —
  `along_uv = flow_sign > 0.0 ? v_ab_uv : (1.0 - v_ab_uv)` — now drives
  tiling, phase, scroll, AND chevron direction together, replacing the old
  separate "mirror the UV, then also multiply the scroll" two-step that
  could fall out of sync (see the double-flip bug above, same class of
  mistake). No GDScript changes were needed —
  `flow_sign`/`phase_offset`/`pipe_length` uniforms are unchanged, only how
  the shader consumes them internally changed.
- **Follow-up: uniform direction flip (Jul 2026).** The flagged risk above
  came true — after the continuity fix, arrows pointed *and* scrolled
  backwards uniformly on every pipe (not the old per-segment
  inconsistency, so continuity itself was confirmed fixed). Root cause:
  `v_ab_uv`'s raw 0-at-`point_a`/1-at-`point_b` sense is the opposite of
  what the baked arrow texture + `TIME`-based scroll term assume for
  "downstream". Fix: swapped the two branches of the `along_uv` ternary —
  `along_uv = flow_sign > 0.0 ? (1.0 - v_ab_uv) : v_ab_uv` — exactly the
  one-line change anticipated above. No other logic touched; `flow_sign`'s
  meaning (set from `WaterPipeSegment.set_flow_sign()`, itself driven by
  `WaterGraph.compute_flow_directions()`) is untouched.

## Pillar-registry gap, ghost/confirm diagnostic, pipe deconstruct mode (Jul 2026)

- **Corner-pillar registry gap (additive fix):** `PillarRegistry` used to be
  populated ONLY by `WireGraphBuilder`'s own outer-corner detection
  (`set_all()`, called from `_compute_and_rebuild_wires()`/
  `_on_chunk_deconstructed()`/`_on_chunk_restored()`, all of which recompute
  `pillar_positions` from the FULL current `_cleared_cells` set — this
  already independently re-derives the same 4 pregen corner positions every
  solve pass, since `BunkerPregen`'s corner math and `WireGraphBuilder`'s
  outer-corner math produce identical world coordinates for a rectangular
  bunker). `BunkerPregen.gd` Pass 3 (the 4 starting corner pillars) never
  called into the registry directly, though. Added
  `PillarRegistry.register_single(pos)` (additive, doesn't touch/clear
  `set_all()`'s own data) and wired `BunkerPregen.gd`'s Pass 3 to call it
  right after spawning each corner pillar — closes the gap directly at the
  source as a defensive belt-and-suspenders fix, independent of whether
  `WireGraphBuilder`'s own recompute already covers it. See `HANDOVER.md`
  for the full investigation writeup and the honest caveat that this may not
  be the actual root cause of any still-reproducing corner-clip bug.
- **Ghost/confirm routing-mode diagnostic:** `WaterPipeDrawMode
  ._trace_active_path()` (the single shared chooser between wall-locked and
  freeform routing, used identically by both `_update_ghost_preview()` and
  `_try_confirm_full_path()`) now logs `[PipeDebug] routing mode: ...` on
  confirm-time calls (gated behind the existing `debug` param, so it never
  fires on the 60fps preview call) — added to investigate a reported "two
  paths near an existing node" bug. Not yet confirmed/fixed — see
  `HANDOVER.md` for the next-step repro instructions.
- **Pipe segment deconstruct mode:** mirrors `BuildModeController
  ._try_deconstruct_wire()`'s hover/highlight/click-refund shape exactly.
  `WaterPipeSegment.set_highlight_delete(on)` — new method, reuses
  `WireSegment.COLOR_DELETE`'s literal value via cross-class const access so
  both systems' delete-hover reads as the same red. Hover scan
  (`BuildModeController._get_hovered_pipe_segment()`) reuses the existing
  `"water_pipe_visual"` group real placed pipes already join — no new group.
  `_try_deconstruct_pipe(seg)` calls the already-generalized `WaterManager
  .delete_and_refund_edge(edge_id)` (built earlier for hookup-reposition and
  purifier-deletion) instead of a 4th hand-rolled refund/unregister/prune
  copy — that function already handles the purifier guard, `queue_free()`,
  `unregister_edge()`, `prune_orphan_waypoint()` on both endpoints, refund +
  float label, and `recompute_flow_directions()`. Wired into
  `_try_deconstruct()`'s existing dispatch chain at the same priority level
  as the wire check (wire checked first, pipe checked only if no wire is
  hovered). Never touches the hookup device itself (separately protected,
  unrelated code path).

## Wall-locked routing notch/step skip — adjacency rewrite (Jul 2026)

Follow-up to the pillar-dogleg work above: a larger notch/step in the
bunker boundary (3 real corners, 5 turns to hug properly) was being skipped
entirely by wall-locked routing — the ghost ran a single straight leg past
the whole notch, as if that wall section didn't exist, instead of hugging
around it the way a simple single-pillar corner already did correctly.

**Root cause:** `WallPerimeterRegistry._rebuild_adjacency()` linked any two
wall-segment entries within `ADJACENCY_RADIUS` (1.1m) of each other in raw
world-space distance, with no check that a real wall path actually connected
them. At a notch, the segments on either side of the recess can end up
within 1.1m of each other once pulled inward even though the real wall path
between them wraps around 3 corners — a false "shortcut" edge.
`find_path_along_wall()`'s BFS then jumped straight across the notch in one
hop, so `_trace_wall_locked_path()` never got the intermediate waypoints
needed for `_dogleg_corner_around_pillars()` to even have a candidate to act
on (that function itself was never the bug — it only replaces one corner
point at a time and was working correctly wherever it did get called).

**Fix:** adjacency is now derived from cleared-cell grid topology instead of
world-space distance — see `docs/systems/structure/README.md`'s
`WallPerimeterRegistry.gd` entry for the full rule
(`_cells_are_wall_adjacent()`). Each `boundary_edges` entry now also carries
its originating `"cell"` (`Vector2i`) and outward-normal `"dir"` offset
(`Vector2i`), plumbed through from `WireGraphBuilder`'s existing per-cell
per-direction loop (all 3 call sites: `_compute_and_rebuild_wires()`,
`_on_chunk_deconstructed()`, `_on_chunk_restored()`) — no change to what
positions/angles get computed, only additional bookkeeping alongside them.

A `[PipeDebug] wall_keys (...)` diagnostic dump was added in
`_trace_wall_locked_path()` (confirm-time only, `debug`-gated) to inspect
the actual BFS-returned segment chain — left in as standing insurance per
this fix's own investigation plan; flag to Brannon whether to strip once
confirmed stable across more playtesting.

**Not yet confirmed working in-editor** — see playtest checklist in
`HANDOVER.md`.

## Expanded-notch corner rejected (out-of-bounds) — wrong Manhattan-corner choice (Jul 2026)

Follow-up to the adjacency rewrite above: at a real wall turn deep inside an
expanded/dug notch (a "bay" dug beyond the original bunker footprint),
wall-locked routing started getting rejected as out-of-bounds again — this
looked like the original corner-registration gap resurfacing, but the actual
cause was different and specific to the adjacency fix's own chaining step.

**Root cause:** `_trace_wall_locked_path()` chains consecutive wall
waypoints through `_build_manhattan_path()`, which inserts one intermediate
corner per turn using a generic "shorter-axis-first" heuristic (a cosmetic
default, fine for a hookup-to-open-destination leg where either corner
choice is equally valid). At a genuine wall-to-wall turn, though, the two
candidate corners are NOT equally valid — one reuses each wall's own
already-correct wall-inset coordinate (the real, safe corner), the other
does not and can land behind a concave notch pillar, outside the dug
footprint entirely. When the two legs happen to be near-equal length (common
right at a notch corner), the heuristic's tie-break picked the unsafe corner,
producing a waypoint in undug rock — `_is_path_in_bounds()` correctly
rejected it (fail-closed, not a bounds-check bug), which read as "the whole
trace is invalid" exactly like the original registration-gap symptom.

**Fix:** `_trace_wall_locked_path()` now special-cases wall-to-wall
transitions in its chaining loop — each wall waypoint already knows which
axis its own wall face defines (X for a vertical left/right wall, Z for a
horizontal top/bottom wall, derived from `WallPerimeterRegistry
.get_segment_angle()`). At a real turn between an X-defining and a
Z-defining waypoint, the corner is now built directly from each side's own
trustworthy axis (no heuristic, no ambiguity) — the source_pos/dest_pos legs
at the very start/end of the chain are untouched and still use
`_build_manhattan_path()`'s existing cosmetic default.

## Purifier clean-pulse + dual quality/purity arrows (Jul 2026 — Feature 1)

Confirmed design answers (Brannon): pulse EVERY purifier on a flipped
consumer's resolved path; ONE pulse total per recompute pass, deduped by
purifier; tweened expanding flat ring only (no particle accent); the
two-lane arrow overlay is the PERMANENT default for every pipe segment in
every save, not just purified runs.

- **`WaterQualityColor.gd`** (new, `scripts/world/water/`) — extracted shared
  red/yellow/green quality-color helper (`get_color(quality: float) ->
  Color`). `WaterInfoUI.gd` / `WaterDispenserUI.gd` both delegate here now
  instead of keeping their own near-duplicate copy.
- **`WaterManager._process_purity_and_dual_arrows(hookup_key, directions)`**
  — called once per `recompute_flow_directions()` pass. Rebuilds a directed
  adjacency (forward + reverse) from the already-resolved `directions`
  result (no second flow-direction resolution), then: (1) forward BFS from
  the hookup computing `is_purified` per edge; (2) diffs current
  per-consumer purity (`WaterGraph.get_unpurified_reachable_keys()`) against
  a new persisted `_last_purity_state` dict to detect impure->pure flips;
  (3) walks the reverse adjacency from each flipped consumer back to the
  hookup collecting every `"purifier"`-role node crossed into a deduped
  set, then pulses each exactly once. `_purity_state_seeded` guards the
  very first post-load recompute from firing a false pulse burst. Returns
  `edge_id -> bool` (is_purified) consumed by the existing per-segment push
  loop to also set `quality_pct` (100.0 if purified, else the hookup's raw
  `water_quality`).
- **`WaterManager._find_purifier_by_key(key)`** (new) — purifier nodes are
  registered without a `consumer_ref`, so scans a new `"water_purifier"`
  group (tagged in `WaterPurifier._ready()`) by `node_key`, same shape as
  `find_pipe_visual()`'s `"water_pipe_visual"` scan.
- **`WaterPurifier.play_clean_pulse()`** (new) — `TorusMesh` (lies flat in
  XZ already), unshaded/alpha/`no_depth_test` material, tweens scale
  `0.3->2.5` and alpha `->0.0` over 0.4s, frees itself on completion.
- **`pipe_flow.gdshader`** — added `quality_color`/`purity_color` uniforms;
  the scrolling arrow band splits into two adjacent half-width lanes via a
  `UV.x < 0.5` test, each remapped to a full 0..1 range so both lanes sample
  a complete (not squished) chevron. Same shared `tile_coord`/scroll/phase
  math for both lanes — purely a tint-per-half change.
- **`WaterPipeSegment.gd`** — `PURITY_COLOR_RAW` (white) /
  `PURITY_COLOR_PURIFIED` (light blue) consts; new `set_quality_color(Color)`
  / `set_purified(bool)` setters, same shape as the existing flow setters.
  Both lanes default white until the first recompute push.

**Known scope note:** the forward-BFS purity propagation assumes each node
has one resolved incoming edge (true for the common tree-like resolved
network) — a rare diamond-merge topology with two genuinely different-purity
incoming edges takes whichever the BFS visits first; not exhaustively
stress-tested.

## Quality arrow "stuck green" fix + ceiling-strip arrow redesign + dispenser fill bar (Jul 2026)

Three fixes/changes from the same playtest pass, after Feature 1/2 above shipped:

- **Quality arrow "always green" — root cause + fix.**
  `WaterManager.set_quality_color()` was ONLY ever pushed from inside
  `recompute_flow_directions()`, which only runs on graph MUTATIONS (place/
  delete/undo/etc). But `WaterHookup.water_quality` decays continuously every
  frame in `WaterHookup._process()` — so the arrow color got pushed once
  (usually near 100%, i.e. green) right after the pipe was placed, then never
  touched again as quality drifted down in real time, even well below the
  75% yellow/50% red thresholds. Fix: `WaterManager` now caches the last-
  resolved reachable-edge set + is_purified map
  (`_last_reachable_edges`/`_last_edge_purity`/`_last_hookup_key`, written at
  the end of `recompute_flow_directions()`), and a new lightweight
  `_process(delta)` + `_refresh_quality_colors()` re-pushes JUST the
  `quality_color` uniform on a `QUALITY_REFRESH_INTERVAL = 0.5s` tick using
  the CURRENT live `hookup_quality` — no graph BFS re-run, no touching
  `flow_sign`/`phase_offset`/`has_flow` (those still only change on an actual
  mutation). Cheap: a flat loop over `"water_pipe_visual"` twice a second.
- **Arrow layout redesign — both lanes onto the ceiling-facing strip.**
  Previous layout split the scrolling arrow band into two lanes wrapped
  around the pipe's full circumference (front half = quality, back half =
  purity) — both always visible somewhere around the pipe depending on
  viewing angle, with an arbitrary seam relative to world "up". Brannon's
  request: collapse both onto just the top (ceiling-facing) strip of the
  pipe, as a sequence running along the pipe's length — quality arrow tile
  touching a purity arrow tile, then a blank gap, then the next pair
  repeats. `pipe_flow.gdshader` changes:
  - New `v_up_dot` varying (world-space normal dotted with world UP,
    computed via `MODEL_NORMAL_MATRIX * NORMAL` in `vertex()`) — fragments
    below `UP_BAND_DOT = 0.55` are discarded entirely; the remainder gets a
    soft-edged `lane_v` cross-section coordinate for the arrow texture's V
    axis (cosmetic width falloff only, not a hard seam).
  - The old `UV.x < 0.5` half-circumference lane split is gone. Instead the
    along-pipe world distance (`world_dist`, same continuity/phase/scroll
    math as before) is taken `mod(period)` where `period = tile_world_length
    * 2.0 + gap_world_length` (new uniform, default `0.5`); the first
    `tile_world_length` of each period samples the quality tile
    (`quality_color` tint), the next `tile_world_length` samples the purity
    tile (`purity_color` tint) immediately touching it, and the remainder of
    the period is a fully-discarded gap.
  - **Known limitation:** a pipe segment running purely vertically has no
    circumference normal that ever points "up" — no arrows render on such a
    segment. Not raised as a requirement to fix; flagging in case a future
    report about "vertical risers show no arrows" comes in.
  - **Follow-up fix, same day — "arrows completely gone."** Two things
    stacked here. First, an actual REAL root cause: `const float
    UP_BAND_DOT: float = 0.55;` used GDScript's typed-const colon syntax,
    which is NOT valid Godot shading language — the shader failed to
    compile entirely (confirmed via a headless render harness; `tools/
    godot_check.sh`'s script-parse check does NOT catch shader compile
    errors, so it stayed green the whole time this was broken). Fixed to
    `const float UP_BAND_DOT = 0.55;`. Second, a real but secondary issue:
    `render_mode ... cull_back` (unchanged from before this redesign) would
    ALSO have hidden the arrows even with a working shader — pipes are
    ceiling-mounted and viewed from BELOW, so the upward-facing polygons the
    new discard logic wants to keep are exactly the ones that are
    back-facing relative to a camera looking up from underneath, and
    `cull_back` removes those before `fragment()`'s `discard()` ever runs.
    Fixed to `cull_disabled` (both sides now reach the fragment shader; the
    vertex-level `v_up_dot`, from the geometric `NORMAL`, is unaffected by
    which side renders, so `discard()` still decides final visibility).
    **Lesson for this codebase going forward:** a shader-only syntax error
    is invisible to `godot_check.sh` — if a shader edit ships and something
    "goes completely invisible", verify the shader itself actually compiles
    (e.g. a small headless render harness instantiating the material) before
    assuming the bug is in masking/culling/uniform logic.
  - **Follow-up fix, same day — "2 arrows squished side by side per tile."**
    `assets/textures/water/pipe_flow_arrow.png` bakes TWO chevrons side by
    side within its own 0..1 UV width (confirmed via pixel-row inspection —
    two alpha blobs exactly half the texture width apart). That was fine for
    the pre-redesign single full-circumference-wrap lane (which wanted 2
    repeats per loop), but the new per-tile sampling (`tex_u` 0..1 per
    quality/purity tile) showed both baked chevrons inside what was meant to
    be ONE arrow. Fix: scale `tex_u` into the texture's own `0..0.5`
    sub-range (`ARROW_TEXTURE_PERIOD = 0.5`, one full period of the baked-in
    repeat) instead of `0..1`, for both the quality and purity tile samples
    — no texture asset change needed.

## Arrow shape distortion (kinked "M" shapes) + spacing fixes + flat ribbon rewrite (Jul 2026)

Brannon reported two further issues after the ceiling-strip redesign above
was confirmed visible: (1) each arrow read as a distorted, kinked "M" shape
instead of a clean chevron, (2) the quality/purity pair wasn't sitting
flush and the gap to the next pair was too wide. Root-caused via direct
pixel inspection of the actual texture asset (not guesswork) rather than
the usual debug-log-first approach — summary of what shipped:

- **2.2 — Arrow spacing (shipped first, smaller/independent fix).**
  Two separate real causes, both fixed:
  - **Sub-cause A (arrows within a pair not touching):** the texture's two
    baked chevrons each have heavy transparent padding around them within
    their own `0..0.5` half — opaque content only spans pixel columns 15-50
    of the 128px-wide texture (normalized `0.1172-0.3906`). The tile
    boundary math itself was already correct (tiles genuinely touch at
    `tile_world_length`), but sampling the FULL padded half per tile meant
    the visible chevrons themselves had a real gap between them regardless.
    Fixed: `pipe_flow.gdshader` now samples only the measured opaque
    content sub-range (`ARROW_CONTENT_START = 0.1172`, `ARROW_CONTENT_WIDTH
    = 0.2734`) instead of the full padded `0..0.5`.
  - **Sub-cause B (gap between pairs too wide):** `gap_world_length`'s
    default lowered `0.5 -> 0.18`. Also newly surfaced as an explicit named
    tunable, `WaterPipeSegment.ARROW_PAIR_GAP`, pushed via
    `set_shader_parameter()` in `_build_arrow_overlay()` rather than
    silently relying on the shader uniform's own default.
- **2.1 — Arrow shape distortion, flat ribbon rewrite.** Root cause: the
  arrow overlay's cross-section coordinate (`lane_v`, texture V axis, i.e.
  the arrow's WIDTH) was derived from `v_up_dot`, a raw normal·up dot
  product — a **cosine** of the angle around the pipe's circumference, not
  linear in physical arc-length. Made significantly worse by mesh
  resolution: the visible ~113° ceiling-facing band (`UP_BAND_DOT = 0.55`)
  only spanned about 2-3 of the pipe's 10 flat faces
  (`WaterPipeSegment.PIPE_SEGMENTS`), so `v_up_dot`'s per-vertex value was
  linearly interpolated across just a couple of large flat panels with
  sharply different normals at their edges — combined with the cosine
  non-linearity, this produced the visible kinked/zigzag "M" shape instead
  of a smooth chevron.
  - **Fix shipped: flat ribbon mesh**, replacing the CylinderMesh + up-facing
    discard mask entirely. `WaterPipeSegment._build_arrow_overlay()` now
    builds a small flat quad directly via `ArrayMesh`/`add_surface_from_arrays()`
    — local Y is the length axis (`-length/2..+length/2`, same convention
    the old `CylinderMesh.height` used, so `pipe_flow.gdshader`'s
    `VERTEX.y`-based tiling/phase math needed ZERO changes), local X is the
    width axis, mapped to UV.x. Width = `PIPE_RADIUS *
    ARROW_RIBBON_WIDTH_SCALE (2.2) * 0.5`. Positioned via a plain
    world-space `+Y` offset (`PIPE_RADIUS + ARROW_RIBBON_CLEARANCE (0.015)`)
    from the pipe centerline — a plain offset works because the segment
    root's own local axes ARE world axes (zero rotation, just translated to
    the segment midpoint) — then oriented with the EXACT SAME
    `look_at()` + 90°-local-X-rotate trick the main pipe mesh already uses
    (proven correct by every prior arrow-continuity fix), with the look_at
    target computed from the ribbon's OWN already-offset global position
    (not the segment's) to avoid a slight tilt.
  - `pipe_flow.gdshader`: `v_up_dot`, `UP_BAND_DOT`, and the
    `MODEL_NORMAL_MATRIX`-based up-facing discard test are gone entirely.
    `lane_v` is now simply `UV.x` — perfectly linear by construction, no
    remapping needed. `render_mode` keeps `cull_disabled` (deliberately, NOT
    reverted to `cull_back`) — a flat ribbon's visible face depends on
    winding/orientation, and this shader has already been bitten twice by
    wrong-side-culling assumptions (see the history above); `cull_disabled`
    costs nothing extra for a 2-triangle ribbon and removes that entire
    class of regression risk going forward.
  - **Known limitation (unchanged from before):** a purely vertical pipe
    riser still shows no arrows — a flat ribbon offset by world `+Y` doesn't
    make sense for a vertical run either; not in scope, still just flagged.
  - **Verification note:** confirmed via the same headless-harness approach
    used for the shader-compile-failure fix above (instantiate the actual
    `WaterPipeSegment`, call `set_endpoints()`, confirm zero `SHADER ERROR`
    output and that `_arrow_material`/`_arrow_mesh_instance` build
    successfully) rather than relying on `godot_check.sh` alone, per the
    standing lesson from that earlier incident.
  - **Follow-up fix, same day — "arrows stretched out lengthwise."** Root
    cause: the earlier texture-content-sub-range fix (sub-cause A above)
    correctly cropped each chevron's sampled UV down to its actual ~35px-
    wide opaque content, but nothing shrank `tile_world_length` (still the
    old `0.8`, a leftover arbitrary value from the pre-redesign wrap-around-
    cylinder era, unrelated to this texture's real proportions) to match —
    that narrow content was still being stretched across the FULL
    `tile_world_length`, about 7.4x longer than its natural size (`0.8 /
    0.108 ≈ 7.4`, confirmed by direct calculation). Fixed by deriving both
    `tile_world_length` and `gap_world_length` from the ribbon's ACTUAL
    current geometry instead of hardcoded/leftover numbers:
    `WaterPipeSegment.ARROW_CONTENT_ASPECT = 35.0/64.0` (measured content
    width ÷ full texture height — `lane_v` maps that full 64px height across
    the ribbon's entire physical width, so this ratio gives the correct,
    undistorted arrow length for whatever the ribbon's current width is);
    `arrow_tile_length = ribbon_width * ARROW_CONTENT_ASPECT`; the
    inter-pair gap is kept proportional via `ARROW_PAIR_GAP_RATIO = 0.225`
    (same visual ratio the old fixed `0.18`-next-to-`0.8` numbers implied,
    reapplied to the corrected size) rather than staying a fixed absolute
    value that would now read as oversized. Both are pushed explicitly via
    `set_shader_parameter()` every time `_build_arrow_overlay()` runs — the
    shader's own uniform defaults are just harmless fallbacks now, no longer
    the real source of truth, specifically so this can't silently drift out
    of sync with the ribbon's dimensions again if either ever changes.
  - **Follow-up fix, same day — spacing tuned (more between pairs, closer
    within a pair).** Two independent ratio changes, plus one new concept:
    - `WaterPipeSegment.ARROW_PAIR_GAP_RATIO` raised `0.225 -> 0.7` — the
      gap between one quality+purity PAIR and the next now reads as
      clearly more spaced out.
    - New `intra_pair_gap` shader uniform (world units, can be negative,
      though only used positive here) — pulls the purity tile's start
      EARLIER relative to the quality tile it follows, i.e. closer
      together / slightly overlapping, instead of the previous flush (0
      gap) touch. Pushed from a new `WaterPipeSegment.ARROW_INTRA_PAIR_GAP_RATIO
      = 0.3` (relative to one arrow's own corrected length, same
      derive-from-ribbon-geometry pattern as the other spacing constants).
    - **Priority tradeoff, worth knowing:** in the small overlapping zone
      this creates, the quality tile's fragment-shader branch is checked
      FIRST and always wins — the quality arrow's own content is never
      clipped; only the purity arrow's leading edge is what's tucked in
      behind it. Chosen because quality reads as the "front" of the pair
      and purity trails it, so purity yielding at the seam reads more
      naturally than the reverse. Flag back if this ever looks wrong in a
      specific case (e.g. if the intra-pair gap ratio is pushed high enough
      to visibly eat into the purity arrow's readable shape).
- **Dispenser UI fill bar/gauge (new, not a bug fix)** — `WaterDispenserUI.gd`
  previously only had the numeric `"STORAGE: X / 5000 mL"` text line; no
  actual bar/gauge graphic existed in the panel (that was easy to conflate
  with the 3D dispenser body's own `tank_fill.gdshader` tint, a different,
  world-space visual — see Feature 2 above). Added a drawn `_canvas.draw_rect()`
  fill bar directly under the STORAGE text (dark background rect, `OK_COLOR`-
  tinted fill rect scaled by `current_fill_mL / MAX_STORAGE_ML`, bordered) —
  same "hand-drawn `_on_draw()`, no new Control node" convention as the rest
  of this panel. `PANEL_H` bumped `430 -> 454` to make room without touching
  any other row's spacing.

## Purifier Filter item, filter-quality depletion, graduated output quality (Jul 2026)

Implemented in full from an attached audit/design plan. **Confirmed design
point (Brannon):** output water quality degrades at HALF the rate filter
quality does — `output_quality = 50.0 + filter_quality * 0.5`. Filter 100%
-> 100% water. Filter 50% -> 75% water. Filter 0% -> 50% water (never fully
stops purifying, just floors at 50%). This exact formula lives in ONE place
(`WaterPurifier.get_output_quality()`) and is never re-derived elsewhere.

### New object: `PurifierFilterItem.gd`
See its own reference-table row above. Ground/inventory display: `"Purifier
Filter"` (fresh) or `"Used Purifier Filter (X%)"` (used, `X` = `filter_quality`
at time of ejection) — plain text, no color-coding (that convention is
water-quality-specific per Brannon's original spec, not assumed to extend
here without being asked). `get_use_prompt()` shows `"[E] Replace Filter"`
only within `REPLACE_RANGE` of a `WaterPurifier`.

### `WaterPurifier.gd` — filter state + swap
- `filter_quality: float` (0-100), depleted every frame in a new `_process()`
  at `100.0 / (FILTER_LIFESPAN_DAYS * seconds_per_game_day)` per second —
  same real-seconds-per-game-day conversion pattern `WaterDispenser.gd`
  already uses (`PlayerStats._seconds_per_game_hour * 24.0`, `86400.0`
  real-day fallback). A one-time debug print at `_ready()` shows the
  computed `depletion_per_second` (a 10-in-game-day rate is too slow to
  eyeball-verify otherwise).
- `get_output_quality() -> float` — the one formula, above.
- `replace_filter(new_filter: PurifierFilterItem)` — ejects the currently-
  installed filter as a new Used item (`PurifierFilterItem.spawn_at()`,
  carrying THIS purifier's `filter_quality` at the moment of ejection),
  installs `new_filter.filter_quality` as this purifier's own, frees
  `new_filter`, then forces `WaterManager.recompute_flow_directions()` so
  every downstream dispenser/sink/arrow reflects the new value immediately.
  Covers BOTH "insert a fresh 100% filter" and "reinsert a used X% filter"
  identically — no branching needed, and reinserting a used filter
  naturally resumes depletion from that %, nothing extra required.
- `spawn_starting_filters()` — two fresh (100%) filters dropped near the
  purifier's base at insertion time (`WaterPurifierAttach.insert_purifier_at()`
  calls this right after `orient_along()`), not auto-added to inventory.

### Multi-purifier resolution — `WaterGraph.get_purifiers_on_path()` (deviation from the plan, documented)
The plan's own suggested implementation was to reuse
`WaterManager._process_purity_and_dual_arrows()`'s already-built directed
reverse-adjacency (cached from the last `recompute_flow_directions()` pass).
**Deviated from that specific suggestion** after implementation: a
purifier's own `get_output_quality()` changes CONTINUOUSLY (filter depletes
every frame), so any call site needing the actual delivered quality always
needs a live re-evaluation regardless of when the graph topology was last
resolved — the exact same category of staleness bug the "quality arrow
stuck green" fix (above) already taught this project to watch for. Caching
the topology lookup on top of that would introduce a SECOND, separate
staleness class for no real benefit. Instead, added `WaterGraph
.get_purifiers_on_path(hookup_key, target_key) -> Array[String]` — a fresh,
un-cached BFS every call (same cost/shape as `get_unpurified_reachable_keys()`
immediately above it in the file, matching this file's own "compute on
demand" convention stated in its header), returning every `"purifier"`-role
node key crossed on the one BFS-resolved path. `WaterManager
._resolve_output_quality(hookup_key, node_key, raw_hookup_quality)` is the
ONE shared helper built on top of it: takes the WORST (minimum)
`get_output_quality()` among every purifier returned (Brannon's confirmed
default, same "weakest stage bottlenecks the result" principle as a real
multi-stage filter system — the safer failure mode, never overstates water
quality); falls back to `raw_hookup_quality` unchanged if no purifier is
found. Only the one resolved BFS-shortest path is considered, not every
possible path — same known limitation already documented for the purity-
flip/pulse system (a rare diamond topology takes whichever path BFS visits
first).

**Wired into every place that used to hardcode a flat `100.0` for "purified"
water** (this was the actual bug those hardcodes represented once filters
existed — the arrow color was always just a visual echo of this same
number, never the source of truth):
1. `WaterManager.get_received_rate_mL()` — what dispensers/sinks/bottle
   refills actually receive.
2. `WaterManager.recompute_flow_directions()`'s per-edge dual-arrow
   `quality_pct` push — now resolves each edge's own upstream node key
   (cached per-edge as `_last_edge_upstream_key`, alongside the existing
   `_last_reachable_edges`/`_last_edge_purity` caches) and calls the same
   helper, so the arrow color and the actual delivered quality can never
   visually disagree.
3. `WaterManager._refresh_quality_colors()` (the periodic live-decay tick
   from the earlier "quality arrow stuck green" fix) — same per-edge
   resolution, on the same `QUALITY_REFRESH_INTERVAL=0.5s` cadence, so a
   depleting filter's effect on pipe arrow color updates continuously, not
   just at the next graph mutation.

**Bug fix (Jul 2026) — quality-arrow lagged one edge behind the purity
arrow:** `get_purifiers_on_path()`'s BFS returned early when
`current == target_key` using the pre-fold `purifiers_so_far.get(current)`
dict entry, BEFORE `current`'s own `role == "purifier"` check folded it
into `forward_purifiers`. This only mattered for the one specific edge
whose upstream node key IS the purifier itself (i.e. the edge immediately
downstream of a purifier) — `_resolve_output_quality()` saw an empty
purifier list for that edge and fell back to raw hookup quality, while
`_process_purity_and_dual_arrows()`'s own separate BFS (which folds a
node's role in before tagging its outgoing edges) already marked that same
edge purified. Net effect: the purity (blue) arrow lane switched at the
correct spot right after the purifier, but the quality-color arrow lane
stayed "raw" for one extra edge/segment before catching up on the next
node downstream. Fixed by folding `current`'s own role into
`forward_purifiers` BEFORE the `current == target_key` check, so the
returned list already includes `current` when `current` is itself the
target purifier node.

### UI — `WaterInfoUI.gd`'s purifier panel
`OUTPUT QUALITY (PURIFIED)` no longer hardcodes `"100%"` — reads
`purifier.get_output_quality()`, colored via the same
`WaterQualityColor.get_color()` red/yellow/green scheme everything else in
this panel already uses. New `FILTER QUALITY` row + drawn fill bar below it
— copied structure directly from `WaterDispenserUI.gd`'s STORAGE bar (dark
background rect, colored fill scaled by a 0-1 fraction, bordered), not
re-derived. `PANEL_H_PURIFIER` grew `210 -> 270` to fit.

### Shelf storage — deviation from the plan's §0.3 recommended default (documented)
The plan flagged shelving a Used filter as a real data-loss risk, based on
an assumption that `Shelving.gd`'s slots store a plain `[count]` per item
type rather than real node references — and recommended Used filters opt
OUT of shelf storage entirely as a result. **Checked against this
codebase's actual current `Shelving.gd` before implementing** (per the
plan's own explicit instruction to verify rather than assume): its slots
(`var slots: Array = [[], [], ...]`) already hold REAL `RigidBody3D` node
references — `retrieve_to_carry()`/`retrieve_to_inventory()` pop and hand
back the exact same instance, the same mechanism that already lets
`Flashlight`'s battery % survive G-storing today. The plan's stated
premise doesn't hold for the code as it currently exists, so shelving a
Used filter is safe — no data loss. Implemented accordingly: BOTH fresh and
Used filters declare `shelf_item_type = "purifier_filter"` /
`shelf_stack_limit = 6` (matches `FoodCan`/`WaterBottle`'s stack size) and
share one stacking key, since each instance's own `filter_quality` is
tracked independently regardless of shared slot/type grouping. Neither
overrides `can_store()` — both remain G-store/carry-eligible via
`InteractionSystem`'s default (storable unless a method says otherwise).

### Persistence — flagged, not solved here (per plan §5)
`WaterPurifier.filter_quality` and `PurifierFilterItem`'s `is_used`/
`filter_quality` are NOT yet covered by `SaveManager` — same category of
gap already flagged in `HANDOVER.md`'s Save/Load System Overhaul section
(which already calls out that purifier NODES themselves are silently
dropped by save/load today). Added to that same overhaul's scope list
rather than building a one-off persistence path here.

### Playtest checklist
See the attached plan's §6 for the full version (unchanged, not re-derived
here) — placement spawns 2 fresh filters nearby + `FILTER: 100%` full bar;
filter depletion over time visibly drifts a downstream dispenser/bottle's
actual received quality per the `50 + filter_quality*0.5` formula (not
still flat green/100%); the dual-arrow front lane tracks the same graduated
number; `[E] Replace Filter` only appears near a purifier and correctly
swaps/ejects/consumes; a retrieved Used filter's `%` survives G-store and a
subsequent reinsertion resumes depletion from that %; a fresh filter shelves
like a food can and (per the shelf-storage deviation above) so does a Used
one; a two-purifier-in-series/parallel test confirms the consumer receives
the WORSE of the two output qualities.

## Purifier QoL pass — 6 items (Jul 2026)

Implemented in full from an attached follow-up plan (depends on the base
Purifier Filter system above — `filter_quality`/`get_output_quality()`/
`PurifierFilterItem`/`replace_filter()` all already existed). **Confirmed
threshold (Brannon):** the warning threshold for items 4 and 6 is **50%**,
the SAME number as `WaterQualityColor`'s own `<=50.0` red cutoff — not a
second, independently-tracked constant.

### Item 1 — Passive mesh tint
`WaterPurifier._band_mat` (promoted from a local var in `_build_mesh()` to
a member) is re-tinted every `_process()` tick via
`WaterQualityColor.get_color(filter_quality)` — only the yellow warning
BAND changes color, not the whole body (mirrors `WaterDispenser`'s
tank-fill approach of tinting a specific part of the object).

### Item 2 — Prompt shows the swap delta
Folded into item 3's `get_use_prompt()` change below — the color-coding IS
the delta display.

### Item 3 — Downgrade confirmation dialog
New **`ConfirmDialogUI.gd`** (`scripts/ui/common/`) — a reusable, parameterized
Yes/No dialog (`open(title, subtitle)`, `confirmed`/`cancelled` signals),
visually modeled on `BuildModeHUD._draw_dig_confirm()`'s "EXPAND BUNKER"
dialog (same full-screen dim, centered rounded panel, kiwi-green border,
button color treatment — literal `Color(...)` values reused verbatim so it
reads as the same dialog family) but NOT hardcoded and usable outside build
mode. **`BuildModeHUD`'s own dig-confirm was deliberately left untouched —
not migrated to this shared component.** That's a nice-to-have cleanup
flagged as a follow-up idea, not done here (touching an already-working
build-mode dialog carries more regression risk than this QoL pass needs to
take on) — a future session should NOT assume that migration already
happened.

`PurifierFilterItem.on_use()`: swapping to a LOWER-quality filter now opens
`ConfirmDialogUI` (`"REPLACE WITH LOWER-QUALITY FILTER?"` / `"X% -> Y%"`)
before calling `purifier.replace_filter(self)`; equal-or-higher swaps
proceed immediately, unchanged. `get_use_prompt()` now colors the
`(X% -> Y%)` suffix green (held filter better-or-equal) or red (worse) via
BBCode, reusing `WaterBottle`'s exact `GOOD_COLOR_HEX`/`CRIT_COLOR_HEX`
literals (`4dd959`/`ff594d`) rather than deriving new ones.

### Item 4 — Low-filter warning at 50%
New **`TransientNotice.gd`** (`scripts/ui/hud/`) — this codebase had no
toast/notification system at all before this (checked: `HUD.gd` has no
transient-message mechanism). Deliberately minimal: one string in, no
queueing/stacking, shown ~3s then fades out (`UIFade.fade_out()`, a new
counterpart added to `UIFade.gd` alongside this — the first caller needing
a fade OUT rather than in) and frees itself. `WaterPurifier._warned_low`
fires `_fire_low_filter_notice()` exactly once when `filter_quality`
crosses from above 50% to at-or-below, and re-arms if it goes back above
(filter replaced). Two purifiers crossing 50% at once just spawn two
overlapping notices — an accepted rough edge, not solved here (no
notice-queueing system, out of scope for a pass this size).

### Item 5 — Inventory badge for Used Filters
`PurifierFilterItem.get_charge_info() -> Array` — `[]` for fresh filters
(no useful badge, matches `InventoryHUD._get_charge_info()`'s existing
`charge_info.size() == 2` check drawing nothing for anything else),
`[int(filter_quality), 100]` for Used ones. Verified against
`InventoryHUD`'s actual code before wiring this in, not assumed.

### Item 6 — Aggregate query, no dedicated UI (deferred, per the plan)
`WaterManager.get_purifiers_needing_attention() -> Array` — group-scan
(`"water_purifier"`, same pattern every other purifier lookup in this file
uses) returning every purifier at or below 50%. Built as cheap groundwork;
deliberately NO dedicated "N purifiers need attention" HUD element wired up
yet — a typical base has one, maybe two purifiers, and item 4's per-purifier
notice already covers the common case. Revisit if/when a base exists with
enough purifiers for a persistent indicator to matter in practice.

## Filter wear scales with incoming water quality (Jul 2026 follow-up)

Brannon's confirmed spec: filter wear now varies with incoming (raw,
pre-purification) water quality instead of always ticking at a fixed max
rate.

- `_compute_depletion_per_second()` (unchanged) is now the MAX rate — hit
  whenever incoming water quality is **<=50%** (dirtier water works the
  filter harder).
- Scales DOWN linearly to **25%** of that max rate at **100%** incoming
  quality (cleaner water barely wears it). Linear interpolation between the
  two: `1.0 - ((incoming - 50.0) / 50.0) * 0.75`.
- **Disconnected from any water source -> 0** (no water flowing through it
  at all, nothing to wear the filter down with) — deliberately NOT treated
  as the max-rate case; confirmed explicitly with Brannon rather than
  assumed.
- "Incoming water quality" = the upstream hookup's RAW (pre-purification)
  `water_quality`, via `WaterManager.get_upstream_raw_quality()` — the
  exact same value `WaterInfoUI`'s purifier panel already shows as INPUT,
  so the wear rate always matches what the player can see in that panel.

New `WaterPurifier._compute_wear_multiplier()` returns this 0.25-1.0
multiplier; `_process()` multiplies it into the existing max-rate
depletion tick. The `_ready()` debug print was relabeled
`max_depletion_per_second` (was `depletion_per_second`) since the actual
live rate now varies below it.

Verified via a headless functional test (clamped 1.0 at incoming<=50,
linear midpoint 0.625 at incoming=75, exact 0.25 at incoming=100, 0.4 at
incoming=90, and 0.0 when disconnected/no `node_key`) plus
`tools/godot_check.sh`.
