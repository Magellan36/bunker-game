# BunkerGame — Project Summary
**Keep this file current.** Update it whenever a system's structure, file layout,
or responsibilities change. This is the first thing to read in a new session —
reference it instead of re-scanning the codebase, to keep credit usage low.

**Last updated:** Friday, July 10, 2026 — repo HEAD `e374fbc`
**Repo:** `Magellan36/bunker-game` (GitHub, branch `main`), Godot 4.6.3, GDScript, statically typed.
**Engine notes:** No Godot binary in the sandbox — all sandbox-side verification is
bracket-balance checks, function-count reconciliation, and line-range diffing, never
actual compiling. Brannon tests all real behavior in his own Godot editor.

---

## 1. What the game is
Bunker survival/design game, two phases:
- **Pre-Apocalypse** — spend cash, build/buy rooms, wire power, stock supplies.
- **Post-Apocalypse** — survive on what you built (food/water/sleep, power grid upkeep).

Tone: grim but not horror, brutalist/concrete aesthetic, military UI.
Bunker dimensions: width=24, depth=18 (`BunkerLayout.gd`).

---

## 2. Directory map
**(Reorganized July 2026 — see §14 for the full rationale/mapping.)**
```
scripts/
  core/          GameCamera.gd
  player/        Player.gd, PlayerStats.gd, InteractionSystem.gd
  world/
    core/        MainWorld.gd, WorldManager.gd, SaveManager.gd
    power/       PowerManager + all power-system files (15 files, see §6)
    build/       BuildModeController + its Stage-10 extracted slices (7 files, see §8)
    environment/ BunkerLayout.gd, BunkerPregen.gd, RockSurround.gd
    items/       Pickup-able item scripts (CanCase, FoodCan, FuelCan, WaterBottle,
                 WaterCase, PickupItem, TestCrate, HeavyConsumerTest, Flashlight)
    furniture/   Bed.gd, Shelving.gd
  ui/
    power/       PowerTerminalUI, PowerPriorityUI, GeneratorInspectUI
    inventory/   InventoryHUD, InventoryManager, ShelfUI
    hud/         HUD, StatusBars, InteractPrompt, CircleFill
    menus/       AdminSpawnMenu, PauseMenuUI, SleepOverlay, GraphicsSettingsPanel
    build/       BuildModeHUD
    debug/       DebugOverlay
    common/      UIFade (shared cross-panel UI utilities, e.g. fade-in — see §9)
scenes/     .tscn files, one per placeable/world object + core scenes (Player, HUD, MainWorld)
            — NOT reorganized to match (out of scope, still flat under scenes/world|ui|player/)
```
Every file below is referenced by its script name only (not full path) since
subfolder placement is a simple lookup from the map above — ask if a path
isn't obvious rather than guessing.

## 3. Autoloads (project.godot)
- `WorldManager` — (small, 19 lines) global world state.
- `SaveManager` — generic save/load field-registry, see §7.
- `DeviceDatabase` — **(Stage 9, July 2026)** pure config data: `WATT_RATINGS`,
  `DEFAULT_PRIORITY_BY_TYPE`, `GENERATOR_TIERS` (moved verbatim out of
  `PowerManager.gd`). Access from anywhere as `DeviceDatabase.WATT_RATINGS` etc.
  — no PowerManager dependency needed. No `class_name` (accessed via its
  autoload singleton name, same pattern as `SaveManager`).
- `GraphicsSettings` (`scripts/core/GraphicsSettings.gd`) — **(Graphics overhaul
  Phase 1, July 2026)** device-level rendering/quality preferences, separate
  from `SaveManager`'s save-slot system. **NOT YET REGISTERED** — script exists
  but Brannon must add it via Project Settings > Autoload himself (per the
  known class-cache/autoload-ownership gotcha, §15 has detail). See §15.

## 4. Core loop / bootstrap
- **`MainWorld.gd`** (895 lines, was 2,327 before Stage 10) — scene bootstrapper:
  wires up HUD, inventory, bed, build mode, dev/admin menus, lighting, world
  pregen. Has `class_name MainWorld` (added Stage 10 so `WireGraphBuilder` can
  hold a typed back-reference). Holds `_wire_builder: WireGraphBuilder`
  (created in `_ready()`), forwards the 3 externally-triggered entry points to
  it: `_compute_and_rebuild_wires()` (startup), `_on_chunk_deconstructed()` /
  `_on_chunk_restored()` (RockSurround's `chunk_deconstructed`/`chunk_restored`
  signals).
- **`WireGraphBuilder.gd`** (1,506 lines) — **(Stage 10, July 2026)** the
  auto-wire perimeter rebuild engine: `_rebuild_auto_wires()` (incremental
  node/edge diff + breaker-aware ring routing + player-wire culling),
  `_compute_boundary_diff()`, `_compute_node_positions()`,
  `_verify_graph_matches_boundary()` (the Stage-0 correctness oracle),
  `_point_on_span()`, `_spawn_auto_wire_seg()`. Same `_owner` back-reference
  pattern as the PowerManager extractions — no MainWorld state physically
  moved (`_cleared_cells`, `_autofill_nodes`, `_auto_wire_nodes`,
  `_auto_wire_segs`, `_player_wire_segs`, `_boundary_edges_prev`, `_wire_log`,
  `_build_controller`, `rock_surround`, `WIRE_DEBUG` all stay on MainWorld).
  Routes `_owner._wdbg()`, `_owner._wkey()`, `_owner.add_cash()`,
  `_owner.get_tree()`, `_owner.add_child()` since it's `RefCounted` (no scene
  tree access of its own). Confirmed zero external callers anywhere else in
  the repo before extraction — self-contained cluster, same as PowerSolver.
- **`BunkerPregen.gd`** / **`RockSurround.gd`** — procedural bunker carving + rock
  surround alignment (uses `wall_left/right/top/bottom` = `OFFSET_X`/`OFFSET_X+depth`
  directly, not cell-index math; `OFFSET_X=-12.5, OFFSET_Z=4.5`).
- **`BunkerLayout.gd`** — exports `bunker_width=24`, `bunker_depth=18`.
- **`GameCamera.gd`** — camera rig.

## 5. Player systems
- **`Player.gd`** — WASD + sprint, stamina drain/regen. Signals: `stamina_changed`, `interacted`.
- **`PlayerStats.gd`** — food/water/sleep/health, game clock (1 real sec = 1 game min),
  `time_multiplier` for debug time-warp (F12).
- **`InteractionSystem.gd`** (688 lines) — owns ALL pickup/drop/store/scroll logic.
  `_held_from_slot=-1` means world pickup. Sets `from_inventory` flag on items (dual
  follow-speeds: 18 world / 40 inventory), `KNOCK_LINGER_TIME=0.35`, `pickup_grace=0.6`.
- **`InventoryManager.gd`** — 4 slots, `activate_item`/`deactivate_item`/`add_item`/`remove_item`.
- Item scripts (WaterBottle, FoodCan, TestCrate, WaterCase, CanCase, FuelCan, Flashlight,
  PickupItem base) — all share the from_inventory/dual-speed/culling pattern above.

## 6. Power system — the biggest, most complex system
**~7,600 lines across 14 files.** Split into 3 focused files as of Stage 5/8 (July 2026
review-implementation project); further splitting (PowerSolver) not yet done.

| File | Lines | Role |
|---|---|---|
| `PowerManager.gd` | 3,660 | Orchestrator: public API + signals, breaker reg/trip/reset, zones/adjacency/BFS, `_solve_network()` entry point + reachability (`_build_adjacency`, `_run_bfs`, `_apply_reachability`, `_adjacency_bfs_can_reach`), generator/battery tick sim, grid state machine, solver-**policy** setters (`set_generator_running/backup/fuel/health`, `set_battery_enabled`, `set_consumer_priority`). Holds `_graph: PowerGraph`, `_registry: PowerRegistry`, `_solver: PowerSolver` (all created in `_ready()`), forwards public CRUD/solver calls to them. |
| `PowerGraph.gd` | 872 | Wire-node/wire-edge CRUD: register/unregister nodes+edges, breaker mid-span splitting (`_split_wire_edge_at`), visual tube spawn/reuse, snap-key helpers. Reaches into PowerManager's own `_wire_nodes`/`_wire_edges`/`_breakers` dicts via an `_owner` back-reference — **dicts were NOT physically moved**, see §6.1. |
| `PowerRegistry.gd` | 356 | Consumer/generator/battery pure CRUD (register/unregister + getters). Same `_owner` back-reference pattern into `_consumers`/`_generators`/`_batteries`. Deliberately excludes solver-policy methods (see table above) — those stay on PowerManager. |
| `PowerSolver.gd` | 1,218 | **(Stage 8b, July 2026)** The 3-pass zone evaluator (`_evaluate_per_component` → `_evaluate_pass1_local_surplus` → `_evaluate_pass2_cross_zone_sharing` → `_evaluate_pass3_zone_resolution`), component draw/capacity accounting, load shed/unshed/partial-unshed, sustained cross-zone brownout (`_sustained_brownout_component`, `clear_exhausted_brownout`), upgraded-breaker self-trip (`_find_upgraded_breakers_in_component`, `_self_trip_upgraded_breaker`), the two solver-only component-flood BFS helpers (`_flood_component_keys`, `_flood_gen_component_keys`). Same `_owner` back-reference pattern — no dicts/consts moved. PowerManager keeps thin forwarding wrappers only for the 7 functions still called from code living there (`_evaluate_per_component`, `_find_components`, `_get_gen_sharing_zone_pairs`, `_shed_residual_watts`, `_flood_component_keys`, `_flood_gen_component_keys`, `clear_exhausted_brownout`) — every other moved function is only called from within PowerSolver itself. Deliberately excludes `_solve_network`/adjacency/BFS-reachability (kept on PowerManager, conceptually PowerGraph's future territory) and generator/battery tick sim (PowerSimClock territory, not yet extracted). |
| `BreakerBox.gd` | 870 | Standard breaker device: E opens settings panel (pass-through toggles, zone swatches, TRIPPED banner + RESTART button). |
| `UpgradedBreakerBox.gd` | 79 | Extends BreakerBox directly — "smart" breaker, blue accent, self-trips to isolate zones instead of shared brownout. |
| `GeneratorObject.gd` | 422 | Generator device, registers with PowerManager, fuel/health sim. |
| `BatteryBank.gd` | 586 | Battery device + its own hand-drawn panel. |
| `PowerTerminal.gd` (world) + `PowerTerminalUI.gd` (ui, 1,007) | 248 + 1,007 | Wall terminal + full dashboard. Draws 0W, priority 1, cosmetic-only screen glow. |
| `PowerTerminalUI.gd` (world, dead) | — | **Deleted** in Stage 1 cleanup — was an orphaned duplicate, only `ui/` copy was ever loaded. |
| `PowerPriorityInteractable.gd` + `PowerPriorityUI.gd` | 54 + 492 | Priority-adjustment device + panel (◄ N ► arrows, 1=critical…5=first-shed). |
| `WireSegment.gd` / `WireDrawMode.gd` | 213 / 668 | Wire visuals + player wire-drawing tool. |
| `WallLight.gd` | 409 | A consumer device (sets `power_zone`/`power_priority` before `_ready()` registers). `power_priority` defaults to **1** (critical/never-shed, changed from 3 in July 2026) — covers both pregen level-start lights and player-placed lights since both use this same scene/script. Player can still override per-instance via the priority panel. `DeviceDatabase.DEFAULT_PRIORITY_BY_TYPE["wall_light"]` kept in sync at 1. |
| `GeneratorInspectUI.gd` | 432 | Generator detail panel. |
| `PowerGridReconciler.gd` | — | **Deleted** (Stage 7) — was a polling safety-net re-injecting player wires after rebuilds; made obsolete by the June 2026 incremental-wire-graph refactor. |

### 6.1 Why the dicts stayed on PowerManager
Extraction methodology (reusable for future splits, e.g. PowerSolver): never move a dict
referenced from 100+ scattered call sites in the same pass. Instead the dict stays
physically on `PowerManager`, and the new class holds a plain `_owner: PowerManager`
back-reference, reaching in via `_owner._some_dict`. This is why `_wire_nodes`/`_wire_edges`
(PowerGraph) and `_consumers`/`_generators`/`_batteries` (PowerRegistry) still live on
PowerManager despite the class split. `PowerManager` keeps identical-signature forwarding
wrapper methods for every moved public function so none of the ~64 external call sites
elsewhere needed to change.

### 6.2 Grid mechanics
- **States:** `ONLINE → BROWNOUT → OVERLOADED → TRIPPED → OFFLINE`.
- **Zones:** per-room circuit breakers; `trip_zone()`/`reset_zone_breaker()`. Wires visible
  ONLY in build mode.
- **Wire graph:** snap-key based, **incrementally rebuilt** (not full teardown) on
  chunk dig/expand by `MainWorld._rebuild_auto_wires()` — diffs old vs new boundary,
  patches only what changed (completed in the June 2026 grid-refactor project).
- **Cross-zone sharing:** breakers with `pass_battery`/`pass_generator = true` let
  load/generation flow between zones via the 3-pass solver
  (`_evaluate_pass1_local_surplus` → `_evaluate_pass2_cross_zone_sharing` →
  `_evaluate_pass3_zone_resolution`).
- **Load shedding:** priority 1 (critical, never shed) → 5 (luxury, shed first).
  `DEFAULT_PRIORITY_BY_TYPE` gives per-type defaults, player-adjustable via
  `PowerPriorityUI.gd`.
- **Priority-change grace period (July 2026):** `set_consumer_priority()` no
  longer resets shed state + resolves immediately — it queues the change
  (`_pending_priority_reset_ids`) and a `PRIORITY_CHANGE_GRACE_SECS` (0.5s)
  timer in `PowerManager._process()`; the actual `_reset_shed_for_consumer_
  component()` + `_solve_network()` only fires once the timer elapses.
  Multiple priority changes within the window collapse into one resolve.
  Added because a priority change's immediate reset+resolve could visibly
  flash the grid through a transient state before settling. The displayed
  priority value itself (`_consumers[id]["priority"]`) still updates
  instantly for UI purposes — only the grid-affecting reset+resolve is
  delayed.
  **Resolved (July 2026):** what looked like a priority change landing on the
  wrong consumer id was actually WallLight's old default priority (3) — with
  wall lights sharing tier 3 with the load-test object, the observed
  shed/overload behavior was the system working as designed, not a routing
  bug. Explained once WallLight's default moved to priority 1 (see the
  `WallLight.gd` row in §6 above). No bug in `HeavyConsumerTest.gd`'s
  per-instance panel pattern or `InteractionSystem` targeting after all —
  not worth revisiting unless a similar symptom shows up again on its own.

- **Standard breaker exhaustion:** ALL feeding generators trip, BOTH shared zones go
  sustained-brownout. Recovery = manual generator restart only (`_exhausted_brownout_keys` latch).
- **Smart/upgraded breaker exhaustion:** self-trips REACTIVELY to isolate zones —
  generator side stays up, only the deficit zone goes offline. Group-reset via
  shared `trip_group_key`. RESTART button in the shared breaker panel; re-evaluates
  fresh on reset (re-trips if still overpowering).
- **Batteries:** charge from surplus, discharge to cover deficit, charge/discharge
  correctly flows across `pass_generator`/`pass_battery` breakers via BFS component
  flooding (`_flood_gen_component_keys`), not single-zone lookups.
- **Data tables:** `WATT_RATINGS`, `DEFAULT_PRIORITY_BY_TYPE`, `GENERATOR_TIERS` —
  moved to the `DeviceDatabase` autoload (Stage 9, July 2026), see §3. Zero
  other call sites for `WATT_RATINGS`/`GENERATOR_TIERS` existed at extraction
  time (devices hardcode their own watts; BuildModeController's generator
  tiers are a separate, not-yet-unified table); `PowerRegistry.gd`'s
  register_consumer priority-0 fallback was the one real caller of
  `DEFAULT_PRIORITY_BY_TYPE`, updated accordingly.

### 6.3 Typed references (no more string dispatch)
All core power classes have `class_name` (`PowerManager`, `BreakerBox`, `GeneratorObject`,
`BatteryBank`, `UpgradedBreakerBox`, `PowerTerminal`, `PowerGraph`, `PowerRegistry`).
Every external call site converted from `get_first_node_in_group("power_manager")` +
`.call()`/`.has_method()` string dispatch to typed refs + direct method calls (~64 sites,
17 files). Zero remaining string-dispatch on PowerManager repo-wide.

## 7. Save / Pause
- **`SaveManager.gd`** (autoload, 156 lines) — generic field-registry
  (`register_field(key, getter, setter)`), 3 numbered slots →
  `user://save_slot_<n>.json`. Wired fields today: `player_position`, `cash`,
  `game_elapsed`. **Not yet persisted:** power grid, inventory, placed build objects.
- **`PauseMenuUI.gd`** (~335 lines) — ESC-triggered CanvasLayer, blurred backdrop
  shader, Continue / Save×3 / Load×3 / Settings / Exit Game (Yes/No confirm).
  Game does NOT SceneTree-pause (grid/generators keep running) — only player
  movement locks + mouse frees. Visual style deliberately plain. **Settings
  button no longer a stub** (Graphics overhaul Phase 1, July 2026) — opens
  `GraphicsSettingsPanel.gd`, lazy-instantiated the same way MainWorld
  lazy-instantiates PauseMenuUI itself. See §15.

## 8. Build system
- **`BuildModeController.gd`** (2,013 lines, was 3,148 pre-Stage-10 — 36%
  reduction across 5 slices) — placement/construction UI + logic combined:
  grid snapping, placement/deconstruction, wire-draw-mode setup, tile
  footprint/occupancy data. Has `class_name BuildModeController` (added
  Stage 10). Holds `_materials: BuildMaterials`, `_undo_manager:
  BuildUndoStack`, `_ghost_preview: GhostPreview`, `_move_tool:
  MoveDuplicateTool`, and `_wall_snap: WallSnapHelpers` (all created in
  `_ready()`). **Stage 10 god-object cleanup COMPLETE ✅** (July 2026) —
  all 5 planned slices done (materials, undo, ghost preview, move/duplicate,
  wall/breaker-snap). Static `_tile_half_extents()` (tile footprint-size
  lookup) deliberately left in place — unrelated data, not part of any
  slice's scope.
- **`BuildMaterials.gd`** (160 lines) — **(Stage 10 slice, July 2026)**
  ghost-preview + world-surface material builders (`_build_ghost_materials`,
  `_build_world_materials`, `_apply_world_material`,
  `_apply_wall_material_recursive`). Same `_owner` back-reference pattern —
  `_mat_valid`/`_mat_invalid`/`_mat_hover`/`_mat_wall`/`_mat_floor`/`TILE_FLOOR`
  all stay on BuildModeController. Confirmed zero external callers before
  extraction. Deliberately excludes `_apply_material_recursive` (hover-glow
  swap — different feature, stays on BuildModeController).
- **`BuildUndoStack.gd`** (245 lines) — **(Stage 10 slice, July 2026)** the
  undo system: `_undo` (pop/replay for place/remove/dig_rock/move/wire
  action types) + `_push_undo_place/_remove/_dig_rock/_move/_wire` (the 5
  push helpers). Not contiguous in the source — `_push_undo_wire` sat apart
  from the other 5, separated by wire-reconnect/recolor code that stays on
  BuildModeController. Same `_owner` pattern — `_undo_stack`, `MAX_UNDO`,
  `ROCK_DIG_COST`, `TILE_*` consts, `_placed_objects`, `rock_surround`,
  `world_node` all stay on BuildModeController. `_push_undo_wire` is
  connected as a `wire_placed` signal callback (not a direct call) — the
  identical-signature wrapper on BuildModeController is what keeps that
  connection working.
- **`GhostPreview.gd`** (390 lines) — **(Stage 10 slice, July 2026)** the
  ghost/preview system: `_spawn_ghost`/`_destroy_ghost`, `_rebuild_ghost_mesh`
  (per-tile-type mesh: procedural boxes, GLB-sized for lights/shelving,
  MeshLibrary lookups for walls/pillars), `_attach_ghost_direction_arrow`,
  `_update_ghost` (per-frame raycast → snap → wall-snap → validity → tint).
  Same `_owner` pattern — `_ghost`, `_selected_tile(_price)`, `gridmap`,
  `camera`, `world_node`, `build_reach`, `_mat_valid`/`_mat_invalid`,
  `_current_angle_deg`, `_orient_index`, `_ghost_valid`,
  `_ghost_blocked_by_occupation`, `_ghost_world_pos`, `EIGHT_DIR_ANGLES`, all
  `TILE_*`/`*_PLACEMENT_Y` consts stay on BuildModeController.
- **`MoveDuplicateTool.gd`** (286 lines) — **(Stage 10 slice, July 2026)** the
  move/duplicate tool: `_try_duplicate`, `_pick_dupe_source` (dead stub),
  `_try_move_click`, `_move_select`, `_spawn_move_ghost`, `_update_move_ghost`,
  `_move_confirm`, `_cancel_move_confirm`, `_cancel_move`,
  `_destroy_move_ghost`. Same `_owner` pattern — `_placed_objects`,
  `_dupe_source_*`, `_move_phase`, `_move_source_*`, `_move_ghost`, `gridmap`,
  `_mat_valid`, all `TILE_*`/`*_PLACEMENT_Y` consts stay on
  BuildModeController. Routes `_owner._push_undo_move()` (BuildModeController's
  own forwarding wrapper into `BuildUndoStack`).
- **`WallSnapHelpers.gd`** (409 lines) — **(Stage 10 slice, July 2026, final
  one)** wall/breaker-snap raycasting: `_snap_light_to_wall`,
  `_snap_breaker_to_wall` (four-ray cardinal cast to the nearest interior
  wall surface), `_is_pregen_interior_face` (the pregen-boundary
  correctness check both snap functions depend on). Same `_owner` pattern —
  `LIGHT_WALL_SNAP_RANGE`, `LIGHT_WALL_HALF_THICKNESS`, `TILE_WALL`,
  `TILE_PILLAR`, `grid_size`, `rock_surround` stay on BuildModeController.
  `_snap_light_to_wall`/`_snap_breaker_to_wall` are called externally from
  `GhostPreview.gd` via `_owner.<name>()` — BuildModeController keeps
  forwarding wrappers for both so that cross-file call path is unaffected.
- **`BuildModeHUD.gd`** (1,008 lines) — hand-drawn immediate-mode UI for build mode.
- **`PlacementIndicator.gd`**, **`Shelving.gd`** (579), **`ShelfUI.gd`** (475).

## 9. UI conventions
Most panels are **hand-rolled immediate-mode** (`_draw()` + `draw_string`/`draw_rect`/
`draw_line`), not Godot `Control`/`Container` trees — a deliberate style choice but the
reason several files (PowerTerminalUI, BuildModeHUD, PowerPriorityUI) are 500–1000+
lines of manual layout bookkeeping. **New panels going forward should prefer real
Control node trees + a theme resource** to avoid repeating this.

**Fade-in on open (standing convention, July 2026):** every panel that opens
via player interaction fades in via `scripts/ui/common/UIFade.gd`
(`UIFade.fade_in(target, duration := 0.15)`, a tiny shared static-function
utility — call it right after `visible = true` in `open()`/`toggle()`).
Applied to ALL current panels: `PowerTerminalUI`, `PowerPriorityUI`,
`GeneratorInspectUI`, `BreakerBox` (covers `UpgradedBreakerBox` for free via
inheritance), `BatteryBank`, `ShelfUI`, `AdminSpawnMenu`, `PauseMenuUI`,
`GraphicsSettingsPanel`, `BuildModeHUD`. **Every new panel going forward
should call this too.** Deliberately NOT applied to `HUD.gd` (already has
its own working fade-in system) or `SleepOverlay.gd` (its own custom
zzz-fade, not an interaction-opened panel) — don't add a second fade on top
of either. `target` must be a `CanvasItem` (a `Control`/`Panel`, e.g. each
panel's `_canvas`/`_panel`/`_root`), never the `CanvasLayer` itself (no
`modulate` property there).

## 10. Known architecture debt (tracked, not yet done)
- **Stage 8b:** ✅ DONE (July 2026) — `PowerSolver.gd` extracted, see §6 table.
- **Stage 9:** ✅ DONE (July 2026) — `DeviceDatabase` autoload, see §3.
- **Stage 10:** ✅ COMPLETE (July 2026) — `WireGraphBuilder.gd` extracted from
  `MainWorld.gd` (see §4); `BuildMaterials.gd`, `BuildUndoStack.gd`,
  `GhostPreview.gd`, `MoveDuplicateTool.gd`, and `WallSnapHelpers.gd`
  extracted from `BuildModeController.gd` (see §8). `BuildModeController.gd`
  went 3,148 → 2,013 lines (36% reduction) across the 5 slices.
  `BuildModeHUD.gd` (1,008 lines, hand-drawn immediate-mode UI) is a
  possible future god-object candidate if further cleanup is wanted, but
  is not part of any current plan.
- No automated tests (no GUT setup) — power solver is the best candidate once split
  out into pure-value-in/out form.

## 11. Debug logging — keep it, don't strip preemptively
`[PM:*]`, `_pmdbg`, `_wdbg`, `[BreakerBox]`, `[MW:DIAG]`, `[SPLIT]` prints, plus
`WIRE_DEBUG` toggle in `MainWorld.gd`/`PowerManager.gd`/`GeneratorObject.gd`/
`WireDrawMode.gd`. F9 in-game dumps full wire/zone/PM state to `user://wire_debug.txt`.
Only strip prints once Brannon explicitly asks for a given stable system.

## 12. Workflow rules — do not deviate
- **GitHub only.** Repo cloned in sandbox at `/home/user/bunker-game-repo`. All work:
  read from repo → edit in sandbox → commit + push → Brannon pulls in Godot editor.
  **No zip downloads for this project, ever.**
- Use raw `git`/bash with a PAT (`ask_secrets` into `.env`, used as
  `https://x-access-token:$TOKEN@github.com/...`) — not the GitHub pipedream plugin
  (no delete-file action).
- **Credit efficiency (standing instruction, July 2026):** for surgical/targeted
  changes, only read/reference the specific relevant file(s) — don't re-scan the
  whole repo. Use this file as the primary orientation doc instead of re-exploring.
  **Update this file whenever a system's shape changes** (new file, moved
  responsibility, new mechanic) so it stays trustworthy as the cheap-context source.
- Confirm root cause before writing a fix; one change at a time on complex systems
  (power grid especially); prompt Brannon to test + report back rather than stacking
  unverified changes. If several sessions fail to fix a bug, step back and reconsider
  the approach rather than repeating the same fix.
- Response format for code changes: Core Approach → Node Setup → Code → How it Works
  & Customization (loosen for small/obvious fixes).
- **No "god files" (standing instruction, July 2026):** don't let files
  accumulate too many unrelated responsibilities/functions. When adding a
  new feature, prefer creating a new, separate file for it (and calling
  into it) if the functionality is individual/self-contained enough,
  rather than bolting it onto an existing large file. This is the same
  reasoning already behind the Stage 8b/9/10 `PowerManager`/`MainWorld`/
  `BuildModeController` extractions (see §6/§8) and the `scripts/world`↔
  `scripts/ui` folder reorg (§14) — apply it proactively at write-time now,
  don't wait for a file to grow large enough to need a dedicated cleanup
  pass. Use the same `_owner`-back-reference extraction pattern (§6.1) if a
  new file needs to reach into an existing file's state without physically
  moving heavily-referenced dicts/vars.
- **Keep folders well-organized too (standing instruction, July 2026):**
  same "don't wait for a cleanup pass" reasoning applies to WHERE files
  live, not just how big they are. When adding a new file, place it in the
  subfolder that matches its actual responsibility (see the §2 directory
  map) rather than dropping it in a flat/convenient location — extend the
  map with a new subfolder if a new category of file doesn't fit an
  existing one. This is forward-looking only — no existing files were
  moved for this (Brannon confirmed current `scenes/` flat layout and the
  loose root-level asset/doc files stay as-is for now).

## 13. Deferred/optional (pinned, not scheduled)
From the original code-review doc — explicitly NOT part of the numbered
Stage 1–10 plan (that plan is 100% complete), just pinned here for later
reference if ever wanted:
- **GUT automated tests** for the now-isolated `PowerSolver.gd` — the review's
  suggestion once the solver was split out into pure-value-in/out form
  (done, Stage 8b). No test framework in the repo currently.
- **Consolidate debug logging** into one project-wide toggle instead of the
  current per-file `WIRE_DEBUG`/`_pmdbg`/`_wdbg` consts. Cuts against
  Brannon's standing "keep all debug prints as-is" instruction, so left
  alone — only revisit if he explicitly asks.
- **Migrate hand-drawn immediate-mode UI to real `Control` nodes.** The
  review's own wording scoped this to NEW panels going forward, not a
  retrofit of existing ones (`BuildModeHUD.gd`, `PowerTerminalUI.gd`,
  `PowerPriorityUI.gd`, `GeneratorInspectUI.gd`, etc. all stay as-is).

## 14. Folder reorganization (July 2026)
`scripts/world/` (39 files) and `scripts/ui/` (15 files) were flat — too
many files in one folder to scan quickly. Split into functional subfolders,
see §2 for the map. Mechanics of the move:
- Moved via `git mv` (history preserved) — `.gd` files AND their `.gd.uid`
  sidecar files moved together.
- Every `res://scripts/world/...` / `res://scripts/ui/...` reference updated
  across ALL `.tscn` scene files, `project.godot` (autoload paths), and
  internal `load()`/`preload()` calls in `.gd` files — 26 files touched.
  Verified zero stale old-path references remain anywhere afterward.
- `class_name`-based cross-references (the ~15 typed refs added since
  Stage 2) are unaffected by file moves — Godot resolves those by global
  class name, not file path, so no changes needed for those call sites.
- Also deleted 2 orphaned `.uid` sidecar files with no matching script
  (`PowerGridReconciler.gd.uid`, old `world/PowerTerminalUI.gd.uid`) —
  leftovers from files deleted in the earlier review-implementation project
  (Stages 7 and 1) that never got cleaned up.
- **Deliberately NOT reorganized:** `scenes/` stays flat under
  `scenes/world|ui|player/` — out of scope for this pass, only the
  `scripts/` side was requested.
- **New file convention going forward:** place new scripts directly into
  the matching subfolder from the §2 map (e.g. a new power device →
  `scripts/world/power/`), not the old flat `scripts/world/`/`scripts/ui/`
  roots.

## 15. Graphics overhaul (July 2026)
Following `bunker-game-graphics-plan.md`'s 7-phase rollout. **All 7 phases
have been touched now** — Phases 1, 2, 3, 7 are functionally complete;
Phases 4, 5, 6 are deliberately partial (see below for exactly what was cut
and why). Autoload registered and Phase 1/2 confirmed working by Brannon;
Phase 3-7 pass reviewed against an external implementation-review doc and
3 real issues fixed (below) — full end-to-end test still pending.

**Post-implementation-review fixes (July 2026):**
- `GraphicsSettingsPanel.gd`'s FOV slider was calling `GraphicsSettings.
  set_setting()` on every `value_changed` tick — up to ~40 synchronous
  `ConfigFile.save()` disk writes per single drag. Split
  `GraphicsSettings.gd` into `set_setting_live()` (mutate + apply, no disk
  write — used on every `value_changed`) + `save_now()` (just the
  `ConfigFile.save()` — wired to the slider's `drag_ended` signal, fires
  once per completed drag). `set_setting()` still exists, now just calls
  both (used by the checkboxes, which are discrete clicks so no throttling
  needed there).
- `LightingDirector.ALARM_VIGNETTE_COLOR` was `Color(0.7, 0.05, 0.0, 1.0)` —
  nearly indistinguishable from `NORMAL_VIGNETTE_COLOR`'s `Color(0.6, 0.0,
  0.0, 1.0)`, undercutting the design goal of a tripped grid reading as a
  visually distinct alarm from "survival stat critical." Changed to a hot
  amber-orange `Color(0.85, 0.35, 0.0, 1.0)` — same edge-vignette/pulse
  behavior, clearly separable hue+value now, reads as "electrical fault"
  rather than "health danger."
- `GraphicsSettings.apply_preset()` took a typed `Preset` enum parameter
  but its only caller (`GraphicsSettingsPanel._on_preset_selected`) hands
  back a bare `int` from `OptionButton.item_selected` — flagged as a
  known-risk pattern given this exact file already hit a real enum/`as`
  bug once (see the `_apply_to_viewport()` `msaa` fix, above). Retyped
  `apply_preset(preset: int)` and `current_preset` to plain `int`,
  sidestepping the int/enum boundary question entirely rather than relying
  on implicit conversion. Dictionary keys/comparisons against `Preset.*`
  constants are unaffected since enum values are still just ints.

**New files:**
- `scripts/core/GraphicsSettings.gd` — device-quality-preference autoload
  (see §3). Preset enum (LOW/MEDIUM/HIGH/ULTRA/CUSTOM), per-feature toggles,
  persists to `user://graphics_settings.cfg`. Applies to the scene's
  `WorldEnvironment` via the `"world_environment"` group (added to
  `MainWorld.tscn`'s `WorldEnvironment` node) rather than a direct scene
  path, so the autoload stays decoupled from any one scene. **Not yet
  registered as an autoload** — Brannon adds it via Project Settings >
  Autoload after pulling (same reasoning as the recurring class-cache
  gotcha in `HANDOVER.md`).
- `scripts/ui/menus/GraphicsSettingsPanel.gd` — real `Control`-tree panel
  (per §9's "new panels should use Control trees" guidance), code-built
  like PauseMenuUI/BuildModeHUD (no `.tscn`). Preset dropdown + the two
  flashlight-specific opt-in toggles (`flashlight_volumetrics`,
  `flashlight_shadows`). Opened by `PauseMenuUI._on_settings_pressed()`.
  Depends on the `GraphicsSettings` autoload being registered first.
- `scripts/world/environment/LightingDirector.gd` — global atmosphere
  reactor, connects to `PowerManager.grid_state_changed`. Tints the
  `WorldEnvironment`'s volumetric fog and flips the HUD critical vignette
  to an alarm color on grid state changes. Instantiated by
  `MainWorld._setup_lighting_director()` (same `Node.new()`/`set_script()`/
  `add_child()` pattern as `_setup_power_manager()`), called right after it
  so the `"power_manager"` group already has a member to connect to.
  **Deliberately does NOT touch individual `Light3D` energy** — see the
  file's own header comment: `WallLight.gd` already owns per-light energy
  via `set_powered()`/`set_shed()` driven by PER-ZONE reachability (the
  whole cross-zone-brownout/smart-breaker system in §6.2), and a second
  global dimmer keyed off the single overall `grid_state` would fight that
  and wrongly dim healthy zones during an unrelated zone's outage. Only
  ambient fog tint + the HUD vignette are touched, since those ARE
  legitimately global. **Verified `grid_state_changed` signal shape before
  writing this** — it's `(new_state: GridState, old_state: GridState)`
  (enum), not `String` as the original graphics-plan draft assumed.

**Renderer/Environment baseline (`project.godot` + `MainWorld.tscn`):**
explicit `renderer/rendering_method="forward_plus"` (+ `.mobile="mobile"`),
and on the scene's `Environment` sub-resource: `sdfgi_enabled`,
`ssao_enabled`, `volumetric_fog_enabled` (+density), `glow_enabled` (+
intensity/bloom/hdr_threshold), `tonemap_mode=2` (ACES Filmic),
`adjustment_enabled=true`. These are the fixed baseline values; per-player
overrides layer on top via `GraphicsSettings`.

**Housekeeping done alongside:** deleted the two stray
`MainWorld.tscn*.tmp` autosave files, added `*.tmp` to `.gitignore`.

**Phase 2 flashlight wiring done (July 2026):** `Flashlight.gd._build_light()`
now calls `_apply_graphics_settings()` (sets `shadow_enabled` from
`GraphicsSettings.flashlight_shadows`, default stays OFF/opt-in-only as
before, and `light_volumetric_fog_energy` from `flashlight_volumetrics` —
a real per-light Light3D property, separate from the environment-wide fog
toggle), and connects to `GraphicsSettings.settings_changed` so changing the
toggle mid-game while holding the flashlight updates it live.

**Phases 3–7 (July 2026, "plow through" pass) — done, with deliberate scope
cuts on anything that needed real visual iteration or risked the power
system's tested behavior. All of it is UNTESTED by Brannon as of writing —
this whole pass was done in one go per his instruction, single end-of-session
test round.**

- **Phase 3 (dust/atmosphere VFX) — full:**
  `scripts/world/environment/DustMotes.gd` (new) — reusable `GPUParticles3D`
  factory, `create_beam_dust()` / `create_ambient_dust()`. Uses two
  procedurally-generated placeholder textures with real alpha channels:
  `assets/textures/vfx/soft_glow_dot.png`, `smoke_puff.png` (built with PIL,
  NOT the image-gen tool — that tool bakes the transparency checkerboard as
  opaque pixels, no real alpha; don't reuse it for particle textures).
  `Flashlight.gd` gets beam dust motes as a child of `_spot`, gated on both
  on/off state and `GraphicsSettings.flashlight_volumetrics`.
  `MainWorld._setup_ambient_dust()` — one sparse world-space dust volume
  sized off `rock_surround.bunker_width/bunker_depth/OFFSET_X/OFFSET_Z`.
  Deliberately doesn't track chunk expansion/digs — fixed footprint only.
- **Phase 4 (materials) — partial by design:** `DeviceDatabase.gd` gets a
  new `STATE_EMISSION_COLORS` (green/amber/red) + `get_status_emission_color()`
  — pure addition, for NEW devices only. Did **NOT** retrofit
  `BreakerBox.gd`/`BatteryBank.gd`/`GeneratorObject.gd`'s existing tuned LED
  color constants to it — real regression risk on the most tested system in
  the project for a consistency-only win. Real trim-sheet/UV texture work
  skipped entirely (needs visual iteration in-editor, can't verify blind).
- **Phase 5 (HUD/panel polish) — partial by design:** fade-in tweens added
  to `PowerTerminalUI.open()`, `PowerPriorityUI.open()` (purely additive,
  `_on_draw()` layout/content untouched), and `GraphicsSettingsPanel` (which
  also got its plain dark backdrop upgraded to the proven
  `pause_blur.gdshader`, since it's a full-screen takeover panel built this
  same session — safe to touch). Did **NOT** add a full-screen blur
  backdrop to `PowerTerminalUI`/`PowerPriorityUI` — those are small
  floating panels over still-interactive gameplay (`mouse_filter PASS`,
  world stays visible/clickable around them), not full-screen takeovers
  like `PauseMenuUI` — changing that is a design call, not a "simple"
  change. `HUD.gd` already has its own working fade-in system, untouched.
- **Phase 6 (remaining VFX) — partial by design:**
  `BatteryBank.gd` — new `_process()` adds a low-battery flicker (emission
  energy multiplier only, on top of `_sync_led()`/`_sync_strip()`'s
  existing color choice — never changes what color shows or when, only
  pulses brightness while discharging under 15% charge).
  `BreakerBox.gd` — one-shot spark burst (self-freeing `GPUParticles3D`,
  via the `finished` signal) on the false→true trip transition only;
  `UpgradedBreakerBox` inherits it automatically (`extends BreakerBox`).
  `GeneratorObject.gd` — continuous light exhaust smoke while running,
  toggled by `set_running()`. Deliberately NOT scaled to fuel-burn/load
  rate (would need solver draw-accounting wiring, out of scope for this
  pass). Decals SKIPPED — needs real surface-projection work + art assets.
- **Phase 7 (camera polish) — full:** `GameCamera.gd` gets:
  - DOF via `CameraAttributesPractical` (`dof_focus_distance`,
    `dof_far_blur_amount` exports), gated on `GraphicsSettings.dof_enabled`
    AND force-disabled in build mode regardless of the setting (calls
    `_apply_dof_setting()` from `enter_build_mode()`/`exit_build_mode()`).
  - Trauma-based camera shake — `add_trauma(amount)` public API, quadratic
    falloff, decays over time, purely additive on top of the existing
    lerped position/rotation in `_follow_target()` (applied after it in a
    new `_apply_shake()`, never replaces the base transform).
    `MainWorld._on_grid_tripped()` now calls `camera.add_trauma(0.5)` — a
    tripped main breaker is the single biggest "oh no" moment in the power
    system, reusing the grid-signal hookup that already existed there for
    the HUD floating-alert warning.
  - FOV exposed as `GraphicsSettings.camera_fov` (default 75.0, Godot's own
    default) — NOT part of any preset (comfort/motion-sickness preference,
    not a quality tier), read directly by `GameCamera._apply_fov_setting()`
    via its own `settings_changed` connection (same self-driven pattern as
    `Flashlight.gd`). `GraphicsSettingsPanel` got an `HSlider` (60–100°) for it.

**Still not done / deliberately skipped:**
- Placing/using `emergency_light` device type (already exists in
  `DeviceDatabase.WATT_RATINGS`, 8W/priority 1) near breaker boxes —
  design/build-menu task, not code.
- Real trim-sheet/PBR texture + UV work (Phase 4's actual "materials" part).
- Decals (Phase 6).
- Retrofitting `BreakerBox.gd`/`BatteryBank.gd`/`GeneratorObject.gd`'s
  existing LED colors onto `DeviceDatabase.STATE_EMISSION_COLORS`.
- Full-screen blur backdrop on `PowerTerminalUI`/`PowerPriorityUI` (design
  call, not attempted).
- Generator exhaust smoke rate scaling to fuel-burn/load.
