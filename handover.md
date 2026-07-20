# Handover — BunkerGame Water Pipe System

**Read first:** `AI_CONTEXT` (repo root), `PROJECT_SUMMARY.md`, `docs/systems/water/README.md`.
Standing rules (credit efficiency, no god files, doc-update discipline, ask-before-broad-fix) apply — see `AI_CONTEXT`.

## Where things stand

Flow-arrow overlay work from the last few sessions is DONE and confirmed
working:
- Cross-joint continuity fix (vertex-space `v_ab_uv` coordinate) — confirmed.
- Direction/scroll-backwards follow-up (swapped `along_uv` ternary branches) — confirmed ("better").
- Speed bumped 1.5x (`ARROW_SCROLL_SPEED` in `WaterPipeSegment.gd`) and arrow
  density halved (`tile_world_length` 0.4→0.8 in `pipe_flow.gdshader`) — just
  committed (`a5d9364`), **not yet user-tested**.

## Open bug — corner/pillar clipping (NOT started, root cause not confirmed)

User's latest report (2 screenshots attached, same message as the arrow
speed/density request): at some wall corners, the **ghost/preview pipe**
(light blue, `GHOST_COLOR_VALID` in `WaterPipeDrawMode.gd`) is cutting
straight through a pillar/corner instead of routing around it, while an
already-placed pipe (white dashed chevron overlay) correctly hugs the wall
at other corners nearby. Second screenshot: a "1/4 section" outer-corner
case where the pipe isn't going around the pillar's outer corner either.

**I was mid-way through asking a clarifying question when `ask_questions`
started erroring repeatedly (tool failure, not resolved this session) — the
question was never answered.** The key open question, ask it first thing
next session:

> Are the red-circled corners one of the **4 true bunker map corners**
> (the big pregen quarter-round/structural columns from `BunkerPregen.gd`/
> `RockSurround.gd`), or a **regular interior wall-junction pillar** (the
> small square `TILE_PILLAR` that auto-spawns wherever two build-mode walls
> meet at 90°, via `WireGraphBuilder.gd`)? Also ask roughly where in the
> bunker this corridor is.

This matters a lot for the fix — confirmed via code read this session:

- `PillarRegistry.gd` is fed **only** by `WireGraphBuilder.gd`'s own
  computed wall-junction corner positions (`_push_pillar_registry()`,
  called from both the initial pregen solve and every incremental chunk
  rebuild). It has **zero knowledge** of `BunkerPregen.gd`/`RockSurround.gd`'s
  four true map-corner structural columns — grepped both files for any
  `PillarRegistry`/`pillar_registry` reference, found none.
- So: if the clipped corner is one of the 4 true map corners, the water
  pipe system has NO clearance data for it at all — dogleg logic never even
  runs, it's a straight-up missing-registration gap. Fix would be
  registering those 4 column positions (and their probably-different real
  footprint/shape — "1/4 section"/quarter-round, likely NOT the same 0.24m
  half-extent square `TILE_PILLAR` assumption `PillarRegistry.
  PILLAR_CLEARANCE_RADIUS` (0.34) is calibrated against) into
  `PillarRegistry` or a sibling registry.
- If instead it's a regular `WireGraphBuilder` wall-junction pillar, then
  the existing `_dogleg_corner_around_pillars()` / `_leg_clears_all_pillars()`
  machinery in `WaterPipeDrawMode.gd` SHOULD already be catching it — that
  would point to a real bug in that logic (e.g. the wall-locked routing
  chain in `_trace_wall_locked_path()` producing a corner point that lands
  just outside `PILLAR_CLEARANCE_RADIUS` some other way, or the ghost
  preview falling through to `_trace_wall_hugging_path()`'s freeform mode
  instead of wall-locked because the destination anchors to an existing
  node — freeform mode does NOT apply the wall-inward offset chain at all,
  only per-corner pillar dogleg, so a direct short Manhattan hop through a
  narrow corridor could clip a pillar without ever getting flagged if the
  elbow point it computes doesn't land inside the 0.34 clearance radius by
  a small margin).
- Either root cause is plausible from the screenshots alone; did not want to
  guess and burn a session on the wrong one.

**Also unconfirmed:** whether the second screenshot's "outer corner" case is
the same root cause as the first, or a separate one (outer corners vs inner
corners may hit different code paths in `WireGraphBuilder.gd`'s pillar
placement logic — see its own comments around "Outer corner pillar
positions" vs "Inward corner pillars", lines ~693-730).

## Next steps

1. Ask the clarifying question above (retry `ask_questions` — it was
   erroring, unclear if transient).
2. Based on the answer:
   - If true map corner: read `BunkerPregen.gd`/`RockSurround.gd` for the
     actual column position/footprint, add a registration path into
     `PillarRegistry` (or a new sibling registry if the shape/size
     assumption differs enough to warrant it — don't force a mismatched
     shape into the existing square-pillar radius math).
   - If wall-junction pillar: add targeted debug prints in
     `_trace_wall_locked_path()`/`_trace_wall_hugging_path()`/
     `_dogleg_corner_around_pillars()` to see which routing mode actually
     fired for this specific ghost placement and why the dogleg didn't
     trigger, before writing a fix.
3. Once fixed, get user to test in-editor: (a) new speed/density on flow
   arrows, (b) corner-pillar routing at both circled spots in both
   screenshots.
4. Doc update discipline: once root cause + fix are confirmed, update
   `docs/systems/water/README.md` in the SAME commit (existing "Pillar
   clearance"/"Corner-pillar dogleg fix" sections are the right place to
   extend, not a new section, unless the true-map-corner case turns out to
   be a genuinely separate system).

## Files touched this session

- `assets/shaders/pipe_flow.gdshader` — direction-flip fix + doc note,
  `tile_world_length` 0.4→0.8. Committed (`272a2c3`, `a5d9364`).
- `scripts/world/water/WaterPipeSegment.gd` — `ARROW_SCROLL_SPEED` *1.5.
  Committed (`a5d9364`).
- `docs/systems/water/README.md` — closed out the cross-joint continuity
  section's flagged risk with the confirmed direction-flip fix. Committed
  (`272a2c3`).
- Nothing touched yet for the corner/pillar clipping bug — investigation
  only (this doc), no code changes.
