# Handover — BunkerGame

**Read `AI_CONTEXT.md` in this repo first, then `PROJECT_SUMMARY.md`, then this file.**

## What just shipped (this session)
Full "Water System — Quality Decay, Purifier, Dispenser Blending, Flow
Indicator" pass, all 8 steps of the implementation spec, in one pass:

1. **Hookup quality decay** — `WaterHookup._process()` drains `water_quality`
   at `-1%/game-day` (`QUALITY_DRAIN_PER_GAME_HOUR = 1.0/24.0`), same
   "units per game hour" convention as `PlayerStats`. One-directional, floors
   at 0.
2. **Purification algorithm** — `WaterGraph.get_unpurified_reachable_keys()`
   (filtered BFS, "contaminated set"), wired into
   `WaterManager.get_received_rate_mL()`'s `"quality"` field (100.0 if pure,
   else the hookup's raw quality).
3. **`WaterPurifier.gd` + `WaterPurifierAttach.gd`** — new construct-menu
   tile (`TILE_WATER_PURIFIER=20`, $240, Water submenu) that attaches
   directly onto an existing pipe run (no floor/wall snap — candidate-find +
   graph-split math duplicated from `WaterPipeDrawMode`'s shape into a new
   file, per design decision, rather than touching that fragile original).
   Wired through `GhostPreview`/`BuildModeController._spawn_placed_object()`/
   `BuildUndoStack`.
4. **Purifier interact UI** — `WaterInfoUI.gd`'s old `_is_source: bool` was
   refactored to `_mode: String` (`"hookup"`/`"sink"`/`"purifier"`); new
   read-only purifier branch (input/output quality, no priority row).
5. **Deletion/refund** — `WaterPurifier.revert_to_corner()` (deconstruct
   reverts graph role `"purifier"` → `"corner"` in place, pipe stays intact,
   no pipe refund, only $240 device refund) + generalized
   `WaterManager.delete_and_refund_edge()` (refuses to delete an edge
   touching a still-`"purifier"` node — enforces "remove purifier first").
6. **Dispenser blending** — `WaterDispenser.stored_water_quality` now blends
   volume-weighted every tick water is actually added (clamped-to-headroom
   `added_mL` used in the blend formula, not the pre-clamp value).
7. **Flow-direction arrows** — `WaterGraph.compute_flow_directions()` (BFS
   hop-distance from hookup) → `WaterManager.recompute_flow_directions()`
   (called after every pipe/purifier mutation, not every frame) →
   `WaterPipeSegment.set_flow_sign()`. Rendered by new
   `assets/shaders/pipe_flow.gdshader` (this project's first spatial shader)
   on a second, additive overlay mesh — base pipe stays always-visible,
   untouched. Visible only in build mode
   (`set_build_mode_visible()`, toggled from `BuildModeController.enter_
   build_mode()`/`exit_build_mode()`).
8. **Docs** — `docs/systems/water/README.md` gained a full "Purification &
   Quality (Jul 2026)" section (Responsibilities, not Extension points
   anymore) + updated file table + `PROJECT_SUMMARY.md` roadmap note.

**Verified:** `tools/godot_check.sh` (headless Godot 4.6-stable — the exact
4.6.3 binary wasn't available in this sandbox, closest stable was used) —
clean PASS, no parse/compile errors. Only pre-existing unrelated warnings
(`WaterCase.tscn` UID, `ObjectDB` leak-at-exit notice).

### Known gap — NOT fixed this pass
`WaterManager.get_pipe_network_for_save()` only persists `"corner"`/
`"pipe_joint"` roled nodes. A `"purifier"` node (and both edges touching it)
is silently dropped by save/load today — flagged in
`docs/systems/water/README.md`'s Purification & Quality section and in
`PROJECT_SUMMARY.md`'s roadmap, not silently left undocumented. Should
likely be closed as part of the save/load project below.

## Next up: Save/Load — full infrastructure carryover
Per Brannon's request (before this water pass), the next session should
build out full save/load coverage for everything currently playable:
bunker expansions, exact power setup (wiring, zones, batteries, generators),
and the water pipe network (including the purifier gap noted above).

**Before touching any code, read (in this order):**
1. `AI_CONTEXT.md` (this repo's own standing rules)
2. `PROJECT_SUMMARY.md`
3. `docs/systems/world-core/README.md` — existing `SaveManager` field-
   registry pattern (`register_field()`, phased ordering 0-4, currently
   covers dug chunks → placed objects+extra state → player wires → water
   pipes → player position/cash/clock)
4. `docs/systems/power/README.md` — Persistence section
5. `docs/systems/water/README.md` — Persistence section + this session's
   Purification & Quality section (esp. the purifier save gap)
6. Every other `docs/systems/*/README.md` that's directly relevant to
   whatever specific save-gap is being closed first — do NOT re-explore the
   whole codebase; the READMEs + `architecture.json` should be enough.

Ask Brannon clarifying questions before starting — confirm scope (which
gaps to close first) and whether the purifier fix belongs in this pass or a
follow-up.
