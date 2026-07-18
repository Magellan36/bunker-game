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
below. **Still explicitly NOT in scope**: pumps, a real per-meter/per-second
transit simulation (purification and decay are instantaneous/topological,
not physically modeled travel time or delay), or upgrading `WaterPipeDrawMode`
to the full continuous-drag paint UX (see Known tradeoffs) — T-split
branching may already partially work (untested, flagged as a follow-up).

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
| `WaterPipeDrawMode.gd` | The placement tool. Routes strictly axis-aligned (90°-only) at a fixed near-ceiling height (`WATER_CEILING_Y`), dropping vertically into any floor-standing connectable device. **Uses the plan's own pre-approved FALLBACK interaction model (one confirm per click), not the full single-drag paint — see its own file-header comment and Known tradeoffs below.** |
| `WaterTestSink.gd` | Rudimentary test endpoint — the acceptance test for this whole phase (place a hookup, route a pipe around a corner, confirm the sink reports CONNECTED). Interactable (Step 2) — see `WaterInfoUI.gd`. Jul 2026: `priority: int` (1-5) + `fixed_demand_mL_per_day: float` exports, implements `get_current_demand_mL_per_day()` for `WaterSolver.gd`. |
| `WaterInfoUI.gd` (`scripts/ui/water/`) | Step 2, July 2026; extended Jul 2026 (Purifier pass). ONE shared info panel for `WaterHookup`/`WaterTestSink`/`WaterPurifier`, distinguished by a `_mode: String` discriminator (`"hookup"`/`"sink"`/`"purifier"` — was a 2-way `is_source: bool`, extended to a 3rd mode rather than a second ambiguous bool) — sized/complexity-matched to `GeneratorInspectUI.gd`, not the full `PowerTerminalUI` dashboard. All stats recomputed live every redraw, no caching. Purifier branch is read-only (no slider/toggle/priority) — shows input quality (upstream hookup's raw `water_quality`) and fixed output quality (always 100%). Dynamic panel height: `PANEL_H_SOURCE`/`PANEL_H_SINK`/`PANEL_H_PURIFIER`. |
| `WaterSolver.gd` | Jul 2026. Priority-tier demand waterfall — `RefCounted`, `_graph: WaterGraph` back-reference (same split pattern as `PowerGraph`/`PowerRegistry`/`PowerSolver`). Pure read-only queries, no state held between calls. |
| `WaterDispenser.gd` | Jul 2026. The first real water-consuming device — 5000mL storage, on/off, player-tunable requested rate, fill tick driven by the solver's actual grant. `TILE_WATER_DISPENSER` in `BuildModeController`, ground-placed like the test sink. (Jul 2026, Purifier pass) `stored_water_quality` now genuinely blends volume-weighted as water arrives — see Purification & Quality below. |
| `WaterDispenserUI.gd` (`scripts/ui/water/`) | Jul 2026, restyled same day. Hand-drawn `_draw()` panel (matches `WaterInfoUI`/`PowerPriorityUI`) with real `HSlider`/`Button` controls overlaid — fill level, rate slider (0 to the live dynamic max), effective (actually received) rate, on/off pill toggle, ◄ N ► demand-priority changer, live blended water quality. |
| `WaterPurifier.gd` (Jul 2026) | Construct-menu tile (`TILE_WATER_PURIFIER=20`, $240, Water submenu) that attaches directly onto an existing pipe run — splits one graph edge into two around a new `"purifier"`-role node, no floor/wall snap. Read-only interact panel (`WaterInfoUI`, mode `"purifier"`). Deconstruct reverts its node's role back to `"corner"` in place (pipe stays intact, no pipe refund) rather than deleting either adjoining edge — see its own file header for the full deletion-order design. |
| `WaterPurifierAttach.gd` (Jul 2026) | Static-only placement math for the Purifier tile — candidate-finding (`find_purifier_candidate()`) + graph insertion (`insert_purifier_at()`). Deliberately duplicates `WaterPipeDrawMode`'s split-candidate shape rather than modifying that file (documented history of subtle bugs there) — the one real difference: no grid-snap, placed freely wherever it lands on the pipe's line. Shared by both `GhostPreview.gd` (validity/position preview) and `BuildModeController._spawn_placed_object()` (actual insertion on confirm) — one copy, not duplicated a second time between those two callers. |
| `assets/shaders/pipe_flow.gdshader` (Jul 2026) | Build-mode-only scrolling arrow overlay, applied as a second additive `MeshInstance3D` on every `WaterPipeSegment` (base pipe mesh/material untouched — still always visible). This project's first `spatial` shader. |

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
