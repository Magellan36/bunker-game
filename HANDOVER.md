# Handover — BunkerGame

**Read `AI_CONTEXT.md` in this repo first, then `PROJECT_SUMMARY.md`, then this file.**

> **Doc-drift note (Jul 2026):** this file and a separate lowercase
> `handover.md` had diverged — the lowercase file was actually the more
> current one for a while (real bug fixes weren't being merged back into
> the canonically-cased file). Merged and deleted as of this commit; going
> forward there is only ONE handover file: this one, `HANDOVER.md`.

## Status: pillar-clip fix + pipe-deconstruct-mode pass (this session)

### 1. Corner-pillar clipping — registry gap closed (additive fix)
Root cause investigation (via a separate implementation-spec doc, re-checked
against this session's HEAD): the 4 pregen corner pillars (`BunkerPregen.gd`
Pass 3 — the four true bunker map corners, big structural columns, same
`TILE_PILLAR` mesh as every other pillar) were never pushed into
`PillarRegistry` directly by `BunkerPregen.gd` itself — only
`WireGraphBuilder.gd`'s own outer-corner detection (inside
`_compute_and_rebuild_wires()` / `_on_chunk_deconstructed()` /
`_on_chunk_restored()`, all of which recompute `pillar_positions` from the
FULL current `_cleared_cells` set every solve pass) ever calls
`PillarRegistry.set_all()`.

**Investigated further this session:** traced the actual math — WireGraphBuilder's
"outer corner" loop (`_compute_and_rebuild_wires()`, ~line 85) computes the
exact same 4 world positions as `BunkerPregen`'s `wall_left/right/top/bottom`
corners (confirmed by hand: e.g. `offset_x=-12.5` → same `-12.5` corner key
both ways), and this full recompute runs once at startup right after
`pregen.generate()` (`MainWorld._run_pregen()`), and again on every dig via
the same full-`_cleared_cells` iteration. So in the current live code the
registry likely IS already correctly populated with these 4 corners via that
path, independent of `BunkerPregen` ever touching it — meaning the specific
"gap" may already be self-healing at runtime.

**Fix applied anyway (low-risk, additive, do-no-harm):**
- `PillarRegistry.register_single(pos: Vector3)` — new additive method,
  does not touch/clear anything `set_all()` already wrote.
- `BunkerPregen.gd` Pass 3 now also calls `register_single()` for each of
  the 4 corners, right after spawning each pillar — closes the gap directly
  at the source in case there's ever a startup-ordering or save/load path
  where the full WireGraphBuilder recompute doesn't run before a pipe trace
  needs pillar data.
- Confirmed call ordering is safe: `_setup_pillar_registry()` runs in
  `MainWorld._ready()` (line ~200) well before `_run_pregen()` (deferred to
  next frame via `_setup_build_mode()`), so the registry node always exists
  before `BunkerPregen.generate()` calls into it.

**Honest caveat for next session:** since my own trace suggests this
registry gap may not be the actual live root cause of a fresh clipping
repro (the full recompute already seems to cover it), if Brannon still sees
a pipe clip through one of the 4 true corner pillars after this fix,
**don't assume this fix didn't help** — instead get a fresh repro + the new
`[PipeDebug] routing mode: ...` print (see item 2 below) and look at
`_trace_wall_locked_path()`'s own corner-anchor logic next, per the
"if not confirmed, the bug is elsewhere" fallback in the original
investigation.

### 2. Ghost/placed-path divergence — diagnostic added, NOT yet confirmed/fixed
Investigated the hypothesis that the ghost preview and the actual placed
path could pick different routing modes (wall-locked vs. freeform) for
what should be the same click. **Finding: current code already routes both
through one shared chooser, `_trace_active_path()`** (comment: "Single
shared chooser so `_update_ghost_preview()`'s per-frame call and
`_try_confirm_full_path()`'s confirm-time call can never disagree about
which mode a given click actually used.") — so the specific "anchor-type
branch mismatch" hypothesis doesn't match how the code is currently
structured.

Added the planned diagnostic anyway, gated behind the existing `debug` param
(so it only fires on confirm clicks, not the 60fps preview — matches
existing `PIPE_DEBUG`/`_pdbg()` convention in the file):
```
[PipeDebug] routing mode: wall_locked
[PipeDebug] routing mode: freeform (wall_locked_disabled=... ctrl_held=...)
```
in `_trace_active_path()`.

**Next step (needs Brannon in-editor):** reproduce the "two paths / duplicate
route" bug near an existing node/junction, and report:
1. Does the confirm-time log say `wall_locked` or `freeform`?
2. Is that the mode you'd expect for that click (CTRL not held → should
   always be `wall_locked`)?

If it says `wall_locked` correctly every time, the bug is downstream inside
`_trace_wall_locked_path()` itself (e.g. the `WallPerimeterRegistry` BFS
finding two equally-short candidate routes near a T-junction) — don't guess
further without that confirmation first.

### 3. Doc-drift cleanup (this commit)
Merged `handover.md` (was actually the more current file, last written
2026-07-20 22:42 vs. this file's older 2026-07-20 01:21) into this
canonically-cased `HANDOVER.md`, then deleted the lowercase file. See the
"Water pipe routing — 3 rounds of fixes" section below for what was in it.

### 4. New feature — pipe segment deconstruct mode
Mirrors `BuildModeController._try_deconstruct_wire()`/
`_get_hovered_wire_segment()` almost exactly (same "highlight red on hover,
click to delete + refund, block pregen" shape), reusing `WireSegment
.COLOR_DELETE`'s literal value via cross-class const access.

- `WaterPipeSegment.set_highlight_delete(on: bool)` — new method, mirrors
  `WireSegment.gd`'s implementation.
- `BuildModeController.gd`: added `_hovered_pipe_segment`, tracked the same
  way as `_hovered_wire_segment` in `_process()`'s deconstruct-tool branch;
  `_get_hovered_pipe_segment()` scans the existing `"water_pipe_visual"`
  group (real placed pipes already join this — no new group needed) instead
  of a physics raycast (pipes are `Node3D`, no collision body, same as
  wires).
- `_try_deconstruct_pipe(seg)` — **reuses the already-generalized
  `WaterManager.delete_and_refund_edge(edge_id)`** (built earlier this
  project for the hookup-reposition and purifier-deletion paths) instead of
  hand-rolling refund/unregister/prune logic a 4th time. That one function
  already handles: purifier guard (refuses to delete an edge touching a
  still-live purifier node), `seg.queue_free()`, `unregister_edge()`,
  `prune_orphan_waypoint()` on both endpoints, refund + floating label, and
  `recompute_flow_directions()`.
- Wired into `_try_deconstruct()`'s existing dispatch chain, same priority
  order as the wire check (pipe check added right alongside it).
- Never touches the water hookup device itself (already separately
  protected, unrelated code path) — only pipe segments are deconstructible.

**Playtest checklist for Brannon:**
1. Enter Deconstruct tool, hover a placed pipe segment — confirm same red
   highlight shade as wire deconstruct.
2. Click it — confirm it deletes, refunds length × cost/m, rest of the run
   stays connected (check flow arrows/water quality on the remaining
   network).
3. Hover near a corner/elbow — confirm only the adjacent straight segment
   highlights, never spanning the turn.
4. Confirm a pipe touching the hookup is still deconstructible on its own
   (the hookup device itself stays protected separately).

**Also verify (godot_check.sh + in-editor):** none of this session's 4
changes broke parse/compile — run `tools/godot_check.sh` before handing
back, then Brannon's own in-editor pass for behavior (items 1/2/4's actual
gameplay confirmation, since #1/#2 both still need a live repro to fully
close out).

---

## Wall-locked routing notch/step skip — adjacency rewrite (this session, follow-up)

After the pillar-registry/deconstruct-mode pass above shipped, Brannon
reported the corner-pillar dogleg detour looked WORSE at a specific spot —
turned out to be two separate things conflated in one screenshot:
- A regular interior/dig-created pillar with 3 sides exposed, where the
  dogleg WAS correctly firing (working as designed, just visually larger
  than expected in a tight space).
- The real bug: a larger notch/step in the boundary (3 corners, 5 turns to
  hug properly) where wall-locked routing skipped the whole section with a
  single straight leg, as if it didn't exist.

Root cause + fix — see `docs/systems/structure/README.md`'s
`WallPerimeterRegistry.gd` entry and `docs/systems/water/README.md`'s
"Wall-locked routing notch/step skip" section for full detail:
`WallPerimeterRegistry._rebuild_adjacency()` used pure Euclidean distance
(`ADJACENCY_RADIUS = 1.1`), which could falsely link two wall segments on
opposite sides of a notch whenever they ended up close together in world
space once pulled inward — a shortcut edge with no real wall path behind
it. Rewrote adjacency to derive from cleared-cell grid topology instead
(each segment now carries its `"cell"`/`"dir"` — see
`_cells_are_wall_adjacent()`) — a notch's two sides are never grid-adjacent
regardless of world-space proximity, so the BFS can no longer shortcut
across one. `_dogleg_corner_around_pillars()` itself was untouched (it
wasn't the bug — see the investigation plan's Section 0).

Also added a `[PipeDebug] wall_keys (...)` diagnostic dump in
`_trace_wall_locked_path()` (confirm-time only, `debug`-gated) — left in as
standing insurance.

### Follow-up fix — sign bug in the diagonal-corner adjacency formula
Brannon reported the notch/peninsula corner (his "3 corners, 5 turns"
description — a single wall-face cell exposing 3 faces, e.g. a peninsula/
nub, not 3 separate cells) was STILL being skipped after the adjacency
rewrite above. Traced it by hand-verifying the adjacency formula against two
concrete examples: the diagonal-corner case's formula was
`cell_b == cell_a + dir_a + dir_b`, which is off by a sign — the correct
relation is `cell_b == cell_a + dir_a - dir_b`. The `+ dir_b` version
computed the wrong diagonal cell entirely, so it silently produced ZERO
adjacency for every real notch/peninsula corner (not a false shortcut this
time — a total disconnect), which made `find_path_along_wall()` return
empty and fall back to freeform routing — reproducing the exact same
"skips the notch/straight line" symptom the whole adjacency rewrite was
supposed to fix. Fixed in `WallPerimeterRegistry._cells_are_wall_adjacent()`.
See that function's own comment and `docs/systems/structure/README.md` for
the worked examples.

**Playtest checklist (needs Brannon in-editor — none of this is confirmed
working yet):**
1. Reproduce the exact notch/step placement from the screenshot — confirm
   the ghost is blue/valid and visibly routes around all 3 corners (5
   turns), hugging the wall/pillar geometry the way a simple single-pillar
   corner already does.
2. Confirm the route doesn't overshoot into open room space unnecessarily —
   should read as a snug hug, not a wide detour.
3. Click to confirm — confirm it places, costs correctly for the longer
   real path (will cost MORE than the old straight-through skip — expected,
   not a bug), and connects cleanly on both sides.
4. Re-test the already-working single-pillar corner cases (including the
   original 4 pregen corners) — confirm no regression.
5. Test any other notch-shaped corners in the current save, if any exist.
6. Sanity-check flow-direction arrows and water quality on the finished run.
7. If it's still wrong, grab the `[PipeDebug] wall_keys` dump from a repro
   click and report the key list + positions — that's the fastest way to
   pin down whether the adjacency fix is incomplete vs. the bug having moved
   somewhere else (e.g. `_collapse_collinear_points()` — see the
   investigation plan's Section 3.2 fallback).

---

## Water pipe routing — 3 rounds of fixes (prior session, closed out)
All confirmed fixed by Brannon in-editor before this session started.

### Round 1 — corner-pillar dogleg (commits `23b55d1`, `06fd1c6`)
`WaterPipeDrawMode._adjust_for_pillar_clearance()` used to shove an elbow
**radially** away from a pillar center when it violated the clearance
radius — that moves both X and Z at once, breaking the shared-axis alignment
a Manhattan elbow needs (should share X with the incoming leg, Z with the
outgoing leg, or vice versa). Confirmed via debug capture: an elbow that
should've landed at `(-12.3, 12.25)` got pushed to
`(-12.2876, 2.9, 12.2345)` — a visible short diagonal clip at the four
pregen corner pillars specifically.

**Fix:** `_dogleg_corner_around_pillars()` replaces the radial nudge with a
small 3-point rectangular "step" detour — extend the incoming leg further
along its own axis, jog sideways one short perpendicular segment, correct
back onto the outgoing leg's axis. Every resulting segment stays strictly
axis-aligned. `_PILLAR_DOGLEG_MARGIN` (0.12m) buffers on top of
`PillarRegistry.PILLAR_CLEARANCE_RADIUS` (0.34m) for the two jog segments.

### Round 2 — diagonal detour artifacts (commits `b81b6e3`, `3e2ccc8`)
Two separate root causes in `WaterPipeDrawMode.gd`:
1. `_build_manhattan_path()` — an axis delta `<= MIN_POINT_GAP` (0.05) skipped
   corner insertion but still appended the tiny non-zero drift on that axis,
   producing a subtle real diagonal leg. Fixed by snapping that axis to
   exactly match `start` when skipped.
2. `_collapse_collinear_points()` — the degenerate-length guard deleted real
   corner points whose adjoining leg was `< MIN_POINT_GAP`, bridging two
   non-adjacent, non-axis-aligned neighbors into a genuine diagonal. Fixed by
   restructuring into two passes: spatial dedupe of near-duplicate points
   first, then direction-based collapse only on the deduped list.

### Round 3 — backward-jog entry leg near hookup (commit `fe6626d`)
**Root cause:** `WallPerimeterRegistry.get_nearest_segment_key()` picked the
absolute-nearest wall segment to the source in isolation, with no awareness
of which direction the destination actually was — could land on a segment
behind the source relative to the destination, forcing the wall-BFS path to
jog backward before turning around (visible as a small "up-then-down"
detour right at the hookup).

**Fix:** added `WallPerimeterRegistry.get_nearby_segment_keys()` (multiple
nearby candidates instead of one absolute-nearest pick) +
`WaterPipeDrawMode._pick_shortest_wall_path()` (evaluates nearby candidates
at both source and destination ends, picks whichever combination yields the
fewest BFS hops — naturally excludes the backward pick since it never
produces the shortest path).

### Open/deferred item from this bug hunt
A second click/leg in the original repro log failed `_is_path_in_bounds` at
point `(-2.0, 2.9, 12.78)`. **Not triaged** — unclear if related or a
separate incidental issue during testing. Flag to Brannon if any similar
out-of-bounds rejection shows up again during save/load testing or general
pipe placement — revisit then rather than guessing now.

## Git state
- Local clone: `/home/user/bunker-game-repo/repo`
- Git identity used: `-c user.name="Brannon Henrie" -c user.email="brannon@magellan-apps.com"`
- Push command: `export $(cat ../.env | xargs) && git push https://${GITHUB_TOKEN}@github.com/Magellan36/bunker-game.git main`

## Standing rules (unchanged, still apply)
- Confirm root cause before writing fixes — one change at a time.
- No "god files" — split out new self-contained functionality into its own
  file/folder.
- Doc-update discipline: update the relevant `docs/systems/*/README.md` in
  the *same commit* as any code change touching that system. Treat doc
  drift as a bug (see item 3 above — this exact rule almost got broken by
  this file's own drift).
- Keep all existing debug prints (`PIPE_DEBUG`/`[PipeDebug]`, `[FlowDebug]`,
  power system `[Reconciler:...]`/`[MW:DIAG]`, etc.) — do not strip them.
- No compiler in sandbox — always run
  `tools/godot_check.sh /home/user/Godot_v4.6.3-stable_linux.x86_64` before
  reporting a fix done, but this only catches parse/type/autoload errors,
  NOT logic bugs — Brannon still needs to do an in-editor test pass for
  actual behavior confirmation.
- Read `PROJECT_SUMMARY.md` and relevant `docs/systems/*/README.md` first
  before touching source, to keep credit usage down. Reference
  `architecture.json` for shape/signals/API before opening real source
  files.
- Any future handover write must go to **this one file only** — `HANDOVER.md`
  (canonical case). Do not create a second lowercase copy again.

## NEXT UP: Save/Load System Overhaul
Brannon wants the existing save/load system (`SaveManager` autoload,
field-registry pattern — `register_field()`, phase-ordered load: dug chunks
→ placed objects+extra state → player wires → water pipes → player
position/cash/clock) expanded to carry over **all current game systems**,
specifically:
- Bunker expansions (dug/cleared cells, current bunker footprint)
- Exact power setup: wiring graph, zones (including any player
  rename/recolor via `ZoneCustomization.gd`), batteries (charge levels),
  generators (fuel/health/running state), breakers (tripped/upgraded state)
- Water system: pipe network graph, hookups, dispensers, sinks, water
  quality/flow state, **and the purifier save gap** — `WaterManager
  .get_pipe_network_for_save()` currently only persists `"corner"`/
  `"pipe_joint"` roled nodes; a `"purifier"` node (and both edges touching
  it) is silently dropped by save/load today (flagged in
  `docs/systems/water/README.md`'s Purification & Quality section and in
  `PROJECT_SUMMARY.md`'s roadmap — should be closed as part of this pass).
- (Confirm with Brannon whether there's anything beyond these categories he
  wants included.)

### Before starting that session, the agent MUST:
1. Read `AI_CONTEXT.md` (standing rules) and `PROJECT_SUMMARY.md`.
2. Read `docs/systems/world-core/README.md` — existing `SaveManager` field-
   registry pattern.
3. Read `docs/systems/power/README.md` — Persistence section.
4. Read `docs/systems/water/README.md` — Persistence section + Purification
   & Quality section (esp. the purifier save gap above).
5. Locate and read the current `SaveManager` autoload source to understand
   the existing generic getter/setter-pair pattern before adding new
   registrations — new systems should plug into this existing pattern, not
   reinvent it.
6. Ask Brannon whether the hookup-reposition-on-expansion fix (pipe deletion
   bug tied to hookup repositioning during bunker expansion, already fixed)
   needs any special save/load handling, since expansion state and pipe
   state are now both in scope for persistence together.

## Other recent context (not blocking, FYI for next session)
- F8 admin menu was requested (button to inject +1000w infinite fake
  generator power, and a button to remove it) — check if this was completed
  or is still pending; not confirmed in this handover's scope, flag to
  Brannon if unclear.
- Dispenser/hookup priority UI was reworked to match the Test Sink device's
  UI structure instead of the pause-menu-style UI initially used — confirmed
  done per a prior handover already committed.
