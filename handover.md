# Handover — Water Pipe Routing Bugs Closed Out, Save/Load System Up Next

## Status: Water pipe wall-locked routing bugs are DONE ✅ (this session, confirmed fixed by user in-editor)

Three separate root causes were found and fixed this session in the wall-locked pipe
routing path (`scripts/world/water/WaterPipeDrawMode.gd` +
`scripts/world/structure/WallPerimeterRegistry.gd`). All three are committed, pushed,
and confirmed working by Brannon in-editor.

### Bug 1 — diagonal detour artifact (round 1, prior session, commit `b81b6e3`)
Added `_collapse_collinear_points()` to strip spurious near-zero-length legs that were
creating visible diagonal jogs.

### Bug 2 — real diagonal segments (round 2, this session, commit `3e2ccc8`)
Two distinct root causes in `WaterPipeDrawMode.gd`:
1. `_build_manhattan_path()` — when an axis delta was `<= MIN_POINT_GAP` (0.05), corner
   insertion was skipped but the tiny non-zero drift on that axis was still appended,
   producing a subtle real diagonal leg. Fixed by snapping that axis to exactly match
   `start` when skipped.
2. `_collapse_collinear_points()` — the degenerate-length guard was deleting real corner
   points whose adjoining leg was `< MIN_POINT_GAP`, bridging two non-adjacent,
   non-axis-aligned neighbors into a genuine diagonal. Fixed by restructuring into two
   passes: spatial dedupe of near-duplicate points first, then direction-based collapse
   only on the deduped list.

### Bug 3 — backward-jog entry leg near hookup (this session, commit `fe6626d`, LATEST)
**Root cause:** `WallPerimeterRegistry.get_nearest_segment_key()` picked the
absolute-nearest wall segment to the source in isolation, with no awareness of which
direction the destination actually was. This could land on a segment behind the source
relative to the destination, forcing the wall-BFS path to jog backward before turning
around and heading the correct way (visible as a small "up-then-down" detour right at
the hookup in the user's screenshot).

**Fix:**
- Added `WallPerimeterRegistry.get_nearby_segment_keys()` — returns multiple nearby
  candidate segments instead of a single absolute-nearest pick.
- Added `WaterPipeDrawMode._pick_shortest_wall_path()` — evaluates nearby candidates at
  *both* the source and destination ends, and picks whichever from/to combination
  yields the fewest BFS hops. This naturally excludes the backward pick since it never
  produces the shortest path.
- `docs/systems/water/README.md` updated in the same commit.

**Verification:** `tools/godot_check.sh` → PASS (no parse/compile errors), re-run again
just now on current `HEAD` (`fe6626d`) → still PASS. User retested in-editor and
confirmed: **"fixed."**

### Open/deferred item from this bug hunt
- A second click/leg in the original repro log failed `_is_path_in_bounds` at point
  `(-2.0, 2.9, 12.78)`. This was **not triaged** — unclear if related or a separate
  incidental issue during testing. Not confirmed as fixed or as a real bug. Flag to
  Brannon if any similar out-of-bounds rejection shows up again during save/load testing
  or general pipe placement — revisit then rather than guessing now.

## Git state
- Local clone: `/home/user/bunker-game-repo/repo`
- `origin/main` is at `fe6626d` (up to date, nothing pending).
- Commits this session: `3e2ccc8`, `fe6626d` (both pushed).
- Git identity used: `-c user.name="Brannon Henrie" -c user.email="brannon@magellan-apps.com"`
- Push command: `export $(cat ../.env | xargs) && git push https://${GITHUB_TOKEN}@github.com/Magellan36/bunker-game.git main`

## Standing rules (unchanged, still apply)
- Confirm root cause before writing fixes — one change at a time.
- No "god files" — split out new self-contained functionality into its own file/folder.
- Doc-update discipline: update the relevant `docs/systems/*/README.md` in the *same
  commit* as any code change touching that system. Treat doc drift as a bug.
- Keep all existing debug prints (`PIPE_DEBUG`/`[PipeDebug]`, `[FlowDebug]`, power system
  `[Reconciler:...]`/`[MW:DIAG]`, etc.) — do not strip them.
- No compiler in sandbox — always run
  `tools/godot_check.sh /home/user/Godot_v4.6.3-stable_linux.x86_64` before reporting a
  fix done, but this only catches parse/type/autoload errors, NOT logic bugs — Brannon
  still needs to do an in-editor test pass for actual behavior confirmation.
- Read `PROJECT_SUMMARY.md` and relevant `docs/systems/*/README.md` first before touching
  source, to keep credit usage down. Reference `architecture.json` for
  shape/signals/API before opening real source files.
- **New standing instruction (this session):** any future `handover.md` — this one
  included — must also direct the next agent session to read the repo's `AI_CONTEXT`
  file, in addition to `PROJECT_SUMMARY.md` and relevant system READMEs.

## NEXT UP: Save/Load System Overhaul

Brannon wants the existing save/load system (`SaveManager` autoload, currently only
persists player position, cash, and game clock elapsed seconds — see Pause Menu + Save
System notes) expanded to carry over **all current game systems**, specifically:
- Bunker expansions (dug/cleared cells, current bunker footprint)
- Exact power setup: wiring graph, zones (including any player rename/recolor via
  `ZoneCustomization.gd`), batteries (charge levels), generators (fuel/health/running
  state), breakers (tripped/upgraded state)
- Water system: pipe network graph, hookups, dispensers, sinks, water quality/flow state
- (Confirm with Brannon in the next session whether there's anything beyond these three
  categories he wants included — the original ask was cut short by a related bug report
  before scope was fully nailed down.)

### Before starting next session, the agent MUST:
1. Read `AI_CONTEXT` in the repo root (new standing instruction, see above).
2. Read `PROJECT_SUMMARY.md`.
3. Read `docs/systems/water/README.md` (just updated this session — reflects current
   pipe routing behavior).
4. Read `docs/systems/power/README.md` (or equivalent power system doc) for the full
   current power subsystem shape before attempting to serialize it — the power system is
   large and stateful (PowerManager ~1000+ lines, PowerGraph.gd extraction in progress
   per Codebase Cleanup notes — check if that extraction finished).
5. Locate and read the current `SaveManager` autoload source to understand the existing
   generic field-registry pattern (getter/setter pairs under string keys) before adding
   new registrations — new systems should plug into this existing pattern, not
   reinvent it.
6. Ask Brannon whether the hookup-reposition-on-expansion fix (session before last —
   pipe deletion bug tied to hookup repositioning during bunker expansion) needs any
   special save/load handling, since expansion state and pipe state are now both in
   scope for persistence together.

### A known related fix already in place (context for save/load work)
- Hookup repositioning during bunker auto-expansion was previously deleting the attached
  pipe (game mistakenly thought it was "deleting behind the hookup"). This was fixed to
  only trigger repositioning logic when the hookup is genuinely being repositioned
  (auto-expansion or manual move), not on every expansion. Relevant if expansion +
  pipe-graph save/load interact — worth a quick sanity check once save/load work begins.

## Other recent context (not blocking, FYI for next session)
- F8 admin menu was requested (button to inject +1000w infinite fake generator power,
  and a button to remove it) — check if this was completed or is still pending; not
  confirmed in this handover's scope, flag to Brannon if unclear.
- Dispenser/hookup priority UI was reworked this session-cycle to match the Test Sink
  device's UI structure instead of the pause-menu-style UI initially used — confirmed
  done per prior handover already committed.
