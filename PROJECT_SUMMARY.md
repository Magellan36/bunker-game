# BunkerGame — Project Summary
**Keep this file current.** Update it whenever a system's structure, file layout,
or responsibilities change. This is the first thing to read in a new session —
reference it instead of re-scanning the codebase, to keep credit usage low.

**Last updated:** Friday, July 10, 2026 — repo HEAD `95e79b4`
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
```
scripts/
  core/     GameCamera.gd
  player/   Player.gd, PlayerStats.gd, InteractionSystem.gd
  world/    World objects, power system, build system, save system, MainWorld
  ui/       HUD / panel scripts (mostly hand-drawn immediate-mode _draw())
scenes/     .tscn files, one per placeable/world object + core scenes (Player, HUD, MainWorld)
```

## 3. Autoloads (project.godot)
- `WorldManager` — (small, 19 lines) global world state.
- `SaveManager` — generic save/load field-registry, see §7.

## 4. Core loop / bootstrap
- **`MainWorld.gd`** (2,319 lines) — scene bootstrapper: wires up HUD, inventory,
  bed, build mode, dev/admin menus, lighting, world pregen. **Also owns the wire-graph
  incremental rebuild** (`_rebuild_auto_wires()`, boundary-diff, `_verify_graph_matches_boundary()`
  oracle) — this is really power-system logic living in a scene-setup file (flagged as
  a god-object candidate, Stage 10, not yet split out).
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
| `PowerManager.gd` | 4,745 | Orchestrator: public API + signals, breaker reg/trip/reset, zones/adjacency/BFS, the solver (`_evaluate_per_component` → 3 labeled-pass functions), generator/battery tick sim, grid state machine, solver-**policy** setters (`set_generator_running/backup/fuel/health`, `set_battery_enabled`, `set_consumer_priority`). Holds `_graph: PowerGraph` and `_registry: PowerRegistry` (created in `_ready()`), forwards public CRUD calls to them. |
| `PowerGraph.gd` | 872 | Wire-node/wire-edge CRUD: register/unregister nodes+edges, breaker mid-span splitting (`_split_wire_edge_at`), visual tube spawn/reuse, snap-key helpers. Reaches into PowerManager's own `_wire_nodes`/`_wire_edges`/`_breakers` dicts via an `_owner` back-reference — **dicts were NOT physically moved**, see §6.1. |
| `PowerRegistry.gd` | 356 | Consumer/generator/battery pure CRUD (register/unregister + getters). Same `_owner` back-reference pattern into `_consumers`/`_generators`/`_batteries`. Deliberately excludes solver-policy methods (see table above) — those stay on PowerManager. |
| `BreakerBox.gd` | 870 | Standard breaker device: E opens settings panel (pass-through toggles, zone swatches, TRIPPED banner + RESTART button). |
| `UpgradedBreakerBox.gd` | 79 | Extends BreakerBox directly — "smart" breaker, blue accent, self-trips to isolate zones instead of shared brownout. |
| `GeneratorObject.gd` | 422 | Generator device, registers with PowerManager, fuel/health sim. |
| `BatteryBank.gd` | 586 | Battery device + its own hand-drawn panel. |
| `PowerTerminal.gd` (world) + `PowerTerminalUI.gd` (ui, 1,007) | 248 + 1,007 | Wall terminal + full dashboard. Draws 0W, priority 1, cosmetic-only screen glow. |
| `PowerTerminalUI.gd` (world, dead) | — | **Deleted** in Stage 1 cleanup — was an orphaned duplicate, only `ui/` copy was ever loaded. |
| `PowerPriorityInteractable.gd` + `PowerPriorityUI.gd` | 54 + 492 | Priority-adjustment device + panel (◄ N ► arrows, 1=critical…5=first-shed). |
| `WireSegment.gd` / `WireDrawMode.gd` | 213 / 668 | Wire visuals + player wire-drawing tool. |
| `WallLight.gd` | 409 | A consumer device (sets `power_zone`/`power_priority` before `_ready()` registers). |
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
  currently `const Dictionary` blocks at top of `PowerManager.gd` (candidate for a
  `DeviceDatabase` autoload — Stage 9, not started).

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
- **`PauseMenuUI.gd`** (325 lines) — ESC-triggered CanvasLayer, blurred backdrop
  shader, Continue / Save×3 / Load×3 / Settings (stub, no behavior yet) / Exit Game
  (Yes/No confirm). Game does NOT SceneTree-pause (grid/generators keep running) —
  only player movement locks + mouse frees. Visual style deliberately plain.

## 8. Build system
- **`BuildModeController.gd`** (3,148 lines) — placement/construction UI + logic
  combined. **God-object candidate, not yet split** (Stage 10 target, same treatment
  as PowerManager: separate placement-logic from UI-drawing from data tables).
- **`BuildModeHUD.gd`** (1,008 lines) — hand-drawn immediate-mode UI for build mode.
- **`PlacementIndicator.gd`**, **`Shelving.gd`** (579), **`ShelfUI.gd`** (475).

## 9. UI conventions
Most panels are **hand-rolled immediate-mode** (`_draw()` + `draw_string`/`draw_rect`/
`draw_line`), not Godot `Control`/`Container` trees — a deliberate style choice but the
reason several files (PowerTerminalUI, BuildModeHUD, PowerPriorityUI) are 500–1000+
lines of manual layout bookkeeping. **New panels going forward should prefer real
Control node trees + a theme resource** to avoid repeating this.

## 10. Known architecture debt (tracked, not yet done)
- **Stage 8b:** extract `PowerSolver.gd` (the 3-pass solver + load-shedding + brownout
  logic) out of `PowerManager.gd` — most entangled piece, do last/carefully.
- **Stage 9:** move `WATT_RATINGS`/`DEFAULT_PRIORITY_BY_TYPE`/`GENERATOR_TIERS` into a
  `DeviceDatabase` autoload or `.tres` resources.
- **Stage 10:** same god-object treatment for `MainWorld.gd` (extract the wire-rebuild
  engine into its own class, e.g. `WireGraphBuilder.gd`) and a follow-up scan of
  `BuildModeController.gd`.
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
