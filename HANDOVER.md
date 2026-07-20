# Handover — BunkerGame

**Read `AI_CONTEXT.md` in this repo first, then `PROJECT_SUMMARY.md`, then this file.**

## What just shipped (this session)
Water pipe **corner-pillar clipping** bug — root cause found and fixed
(commits `23b55d1`, `06fd1c6`).

**Root cause:** `WaterPipeDrawMode._adjust_for_pillar_clearance()` (from the
Part B paint-along-wall pass) handled a wall-hugging elbow that landed
inside a pregen corner pillar's clearance radius by shoving it **radially**
straight away from the pillar's center. That moves the point on both X and
Z at once — but a Manhattan elbow is supposed to share its X with the
incoming leg and its Z with the outgoing leg (or vice versa). Radially
nudging it broke that shared-axis alignment, so the two legs touching that
corner were each off by a few centimeters from true 90° — visually a short
diagonal clip right at the four pregen corner pillars specifically (any
other elbow, away from a pillar, was never touched and stayed perfectly
square).

Confirmed via a debug capture: an elbow that should have landed exactly at
`(-12.3, 12.25)` got pushed to `(-12.2876, 2.9, 12.2345)` — 0.32m from the
corner pillar center (inside the 0.34 clearance radius), explaining both
the diagonal look and why it only ever showed up near those four corners.

**Fix — `_dogleg_corner_around_pillars()`:** when an elbow violates a
pillar's clearance, it's now replaced with a small 3-point rectangular
"step" detour instead of one nudged point: extend the incoming leg a bit
further along its own axis, jog sideways one short perpendicular segment,
then correct back onto the outgoing leg's axis before continuing to the
real destination. Every resulting segment stays strictly axis-aligned;
`_PILLAR_DOGLEG_MARGIN` (0.12m) is the buffer added on top of
`PillarRegistry.PILLAR_CLEARANCE_RADIUS` for the two jog segments. Each new
sub-leg is still re-validated through the existing `_leg_clears_all_pillars()`
check exactly as before — old fallback (mark the whole trace invalid /
red ghost) still applies if a dogleg somehow can't clear.

Also removed the now-obsolete TEMP diagnostic print block in
`_trace_wall_hugging_path()` that was added to chase this bug down (its own
comment said to remove once confirmed/fixed).

**Verified:** `tools/godot_check.sh` clean PASS after both commits (real
Godot 4.6.3 headless, no parse/compile errors). **Not yet tested in-editor
by Brannon** — see checklist below.

**Docs:** `docs/systems/water/README.md` pillar-clearance section rewritten
to describe the dogleg approach (replaces the old radial-nudge
description); `architecture.json` regenerated. Both same-commit as the code
fix.

## In-editor test checklist (do this first, before anything else)
1. Place a hookup near one of the 4 pregen corners, enter pipe paint mode.
2. Draw a run that turns near that corner (e.g. down the left wall, across
   the bottom wall — the exact case from the bug report).
3. Confirm the placed pipe shows a small rectangular step/divot around the
   pillar, not a diagonal clip — every segment should read as perfectly
   horizontal/vertical.
4. Repeat approaching from a couple of the other 3 corners/directions (the
   dogleg mirrors based on which leg is incoming, so worth checking more
   than one).
5. Sanity check a normal run nowhere near a pillar — should look completely
   unchanged, no dogleg triggered.

## Known gaps / open threads (not touched this session)
- Earlier in this investigation there was a broader open question: whether
  the Part B paint-along-wall UX changes were even visibly taking effect
  in-game at all (separate from the pillar-clip bug specifically). That
  thread was dropped once the pillar-clip root cause was found and fixed —
  worth explicitly confirming with Brannon after the test checklist above
  whether the rest of Part B's paint-mode behavior (continuous multi-leg
  trace, live cost preview, etc.) is behaving as expected, or if that
  broader question still needs its own investigation.
- `WaterManager.get_pipe_network_for_save()` only persists `"corner"`/
  `"pipe_joint"` roled nodes — a `"purifier"` node (and both edges touching
  it) is silently dropped by save/load today. Flagged in
  `docs/systems/water/README.md`'s Purification & Quality section and in
  `PROJECT_SUMMARY.md`'s roadmap. Should be closed as part of the save/load
  project below.
- Multiple/nested/overlapping loops in `WaterGraph.compute_flow_directions()`
  are resolved deterministically but not exhaustively stress-tested beyond
  what's been manually built so far — no known bug, just noted.

## Next up: Save/Load — full infrastructure carryover
Still the next planned project once the water-pipe thread above is fully
closed out with Brannon. Per his request, build out full save/load coverage
for everything currently playable: bunker expansions, exact power setup
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
