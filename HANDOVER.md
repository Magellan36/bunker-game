# Handover — BunkerGame

**Read `AI_CONTEXT.md` in this repo first, then `PROJECT_SUMMARY.md`, then this file.**

## What just shipped (this session)
Water pipe **loop flow-direction** bug, fixed in two passes:

1. **Convergence fix (commit `9a7bfb7`)** — `WaterGraph.compute_flow_
   directions()` used to be a plain BFS spanning tree + naive per-edge
   distance comparison for any "closing" edge that reconnects two
   already-visited nodes (a real loop, not just branching). That local
   comparison pointed the closing edge into whichever endpoint was farther
   from the hookup — but that endpoint usually already had an inflow from
   its own tree parent, so two independent inflows converged on one node
   (arrows visibly meeting at a point instead of circulating one way).
   Fix: treat each closing edge as completing a fundamental cycle relative
   to the spanning tree — find the two branches' LCA via parent-pointer
   walk, compare real-world branch length from the LCA (shorter/more direct
   = "dominant", keeps natural direction), **reverse** the recessive
   branch's spine so the loop circulates one consistent way. Ties broken by
   registration order (new `_edge_creation_order` dict, stamped once per
   edge_id — `edge_id` itself is order-independent by design). `phase_offset`
   (cross-joint scroll continuity) also recomputed via a second pass
   following final resolved directions, since raw hookup-BFS distance is
   wrong once edges are reversed.
2. **Ring-main-through-hookup fix (commit `53db4b6`, same-day follow-up)** —
   pass 1 above reversed a branch's *entire* spine back to its LCA. But when
   a loop wraps all the way back through the hookup itself (the closing
   edge's LCA IS the hookup), that reversal ran an edge backward straight
   into the hookup — giving the source node an inflow, which is physically
   impossible and looked like the whole loop flowing backward toward the
   hookup instead of away from it. Fix: `compute_flow_directions()` now
   special-cases `lca == hookup_key` — skip branch-reversal entirely (both
   branches keep their natural hookup-outward direction), only the closing
   edge's own direction is picked by dominance. This matches real ring-main
   plumbing: fed from one point, flows both ways, meets on the far side —
   a normal merge, not the interior-loop convergence bug pass 1 targeted
   (that bug is specifically about loops that don't touch the hookup).

**Verified:** `tools/godot_check.sh` clean PASS after both commits. Brannon
tested in-editor across multiple loop configurations (including the
original convergence screenshot and the ring-main-through-hookup case) —
confirmed all working correctly.

**Docs:** `docs/systems/water/README.md` — "Loop/cycle flow-direction fix"
and "Ring-main-through-hookup fix" bullets under the water flow-arrow
section, both same-commit as their code changes.

## Known gaps (still open, not touched this session)
- `WaterManager.get_pipe_network_for_save()` only persists `"corner"`/
  `"pipe_joint"` roled nodes — a `"purifier"` node (and both edges touching
  it) is silently dropped by save/load today. Flagged in
  `docs/systems/water/README.md`'s Purification & Quality section and in
  `PROJECT_SUMMARY.md`'s roadmap. Should be closed as part of the save/load
  project below.
- Multiple/nested/overlapping loops in `compute_flow_directions()` are
  resolved deterministically (creation-order processing + reversed-edge
  guard) but not exhaustively proven for every possible nesting — no known
  bug, just not stress-tested beyond what's been manually built so far.

## Next up: Save/Load — full infrastructure carryover
This is still the next planned project (carried over from before the pipe
work above). Per Brannon's request, build out full save/load coverage for
everything currently playable: bunker expansions, exact power setup
(wiring, zones, batteries, generators), and the water pipe network
(including the purifier gap noted above).

**Before touching any code, read (in this order):**
1. `AI_CONTEXT.md` (this repo's own standing rules)
2. `PROJECT_SUMMARY.md`
3. `docs/systems/world-core/README.md` — existing `SaveManager` field-
   registry pattern (`register_field()`, phased ordering 0-4, currently
   covers dug chunks → placed objects+extra state → player wires → water
   pipes → player position/cash/clock)
4. `docs/systems/power/README.md` — Persistence section
5. `docs/systems/water/README.md` — Persistence section + Purification &
   Quality section (esp. the purifier save gap above)
6. Every other `docs/systems/*/README.md` that's directly relevant to
   whatever specific save-gap is being closed first — do NOT re-explore the
   whole codebase; the READMEs + `architecture.json` should be enough.

Ask Brannon clarifying questions before starting — confirm scope (which
gaps to close first) and whether the purifier save fix belongs in this pass
or a follow-up.
