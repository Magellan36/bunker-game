# Handover — BunkerGame

**Read `AI_CONTEXT.md` in this repo first, then `PROJECT_SUMMARY.md`, then this file.**

## Status: purifier clean-pulse + dual quality/purity arrows, and dispenser fill visual — SHIPPED, NOT YET CONFIRMED in-editor

Both features from a plan doc ("Purifier clean-pulse + dual quality/purity
arrows, and dispenser fill animation") are implemented and pushed
(`562b251`). **Neither has been confirmed working in-editor by Brannon yet**
— do the playtest checklists below before touching anything else in the
water system.

> **Process note:** a prior session in this same arc ran out of credits
> between finishing Feature 1's code and actually committing/pushing it —
> Brannon reported "seeing neither feature" on a fresh pull, which traced
> back to exactly that (Feature 1 simply wasn't in the repo yet). If a
> similar "it's not there" report ever comes up again, check `git log`
> against `origin/main` before assuming a code bug.

### Feature 2 — Dispenser fill-level visual
`WaterDispenser.gd`'s body mesh uses a `ShaderMaterial`
(`assets/shaders/tank_fill.gdshader`) instead of a flat color — no new
geometry, the box itself is the gauge. Object-local `VERTEX.y` (works
regardless of placement/rotation) compared against a `fill_pct` uniform:
below the cutoff renders water-blue, above it renders the normal empty-tank
color, thin bright waterline band at the cutoff. Pushed every frame from
`_process()` via `_update_fill_visual()` — same cadence as the existing fill
tick, no new polling loop.

**IMPORTANT, easy to misread as "not working":** the empty-tank color is
deliberately identical to the OLD flat body color, so a fresh, never-filled
dispenser looks visually unchanged except for a barely-visible thin line at
the very base. **The dispenser must actually be connected to a hookup/pipe
and receiving water before the fill visual becomes obviously visible.**

**Playtest checklist:**
1. Build a dispenser, connect it to water, let it fill — confirm the body
   visibly tints blue from the bottom up in real time, matching the numeric
   UI panel.
2. Confirm empty (0%) and full (100%) both look correct at the extremes.
3. If it still reads as invisible/unclear even while actively filling, the
   fallback (a dedicated semi-transparent window panel instead of
   recoloring the whole box) is the next thing to try — flag back rather
   than tuning the current shader blind.

### Feature 1 — Purifier clean-pulse + dual quality/purity arrows
Confirmed design answers (Brannon): pulse EVERY purifier on a flipped
consumer's resolved path (not just the most-recently-mutated one); ONE
pulse total per recompute pass, deduped by purifier; tweened expanding flat
ring only (no particle accent); the two-lane arrow overlay is the PERMANENT
default for every pipe segment in every save, not just purified runs;
extract a shared `WaterQualityColor` helper (was duplicated in
`WaterInfoUI.gd`/`WaterDispenserUI.gd`).

Implemented — see `docs/systems/water/README.md`'s matching section for
full detail. Summary:
- `WaterQualityColor.gd` (new) — shared red/yellow/green threshold helper.
- `WaterManager._process_purity_and_dual_arrows()` — called once per
  `recompute_flow_directions()` pass; forward BFS over the already-resolved
  flow directions computes `is_purified` per edge; diffs current
  per-consumer purity against a persisted `_last_purity_state` to detect
  flips; walks backward from each flipped consumer collecting every
  purifier crossed (deduped set); pulses each once. `_purity_state_seeded`
  prevents a false pulse burst on the first recompute after a save load.
- `WaterManager._find_purifier_by_key()` (new) — purifier nodes have no
  `consumer_ref`, so this scans a new `"water_purifier"` group by `node_key`.
- `WaterPurifier.play_clean_pulse()` (new) — tweened `TorusMesh` ring,
  scale `0.3->2.5` + alpha `->0` over 0.4s.
- `pipe_flow.gdshader` — `quality_color`/`purity_color` uniforms; the
  existing scrolling arrow band splits into two adjacent half-width lanes,
  each remapped to a full 0..1 range so both sample a complete chevron.
- `WaterPipeSegment.gd` — `PURITY_COLOR_RAW`/`PURITY_COLOR_PURIFIED` consts,
  `set_quality_color()`/`set_purified()` setters.

**Playtest checklist:**
1. Place a purifier on a hookup with existing impure downstream consumers —
   confirm a ring pulse fires ONCE at the purifier's location, not once per
   consumer, not elsewhere.
2. Confirm every pipe segment shows two adjacent half-width arrow lanes:
   front lane matches the existing quality red/yellow/green thresholds
   (same colors/logic as the hookup/sink/purifier info panels); back lane is
   white upstream of any purifier, light-blue downstream of one.
3. Delete the purifier (or reintroduce a bypass) — confirm the back lane
   reverts to white and the front lane resumes tracking raw decayed
   quality.
4. Reload a save with an already-purified network — confirm NO false pulse
   burst fires on the first recompute after load.
5. Spot-check performance on a larger pipe network (the per-edge push is
   already O(edges) per mutation, shouldn't regress, but confirm on a real
   save).
6. Known scope note, not yet stress-tested: the forward-BFS purity
   propagation assumes each node has one resolved incoming edge (true for
   the common case) — a rare diamond-merge topology with two genuinely
   different-purity incoming edges takes whichever the BFS visits first.

## Git state
- Local clone: `/home/user/bunker-game-repo/repo`
- `origin/main` at `562b251` (both features pushed, nothing pending).
- Git identity used: `-c user.name="Brannon Henrie" -c user.email="brannon@magellan-apps.com"`
- Push command: `export $(cat ../.env | xargs) && git push https://${GITHUB_TOKEN}@github.com/Magellan36/bunker-game.git main`

## Standing rules (unchanged, still apply)
- Confirm root cause before writing fixes — one change at a time.
- No "god files" — split out new self-contained functionality into its own
  file/folder.
- Doc-update discipline: update the relevant `docs/systems/*/README.md` in
  the *same commit* as any code change touching that system. Treat doc
  drift as a bug.
- Keep all existing debug prints (`PIPE_DEBUG`/`[PipeDebug]`, `[FlowDebug]`,
  power system `[Reconciler:...]`/`[MW:DIAG]`, etc.) — do not strip them.
- No compiler in sandbox — always run
  `tools/godot_check.sh /home/user/godot-bin/Godot_v4.6.3-stable_linux.x86_64`
  before reporting a fix done (re-download the binary if a fresh sandbox
  doesn't have it — `godotengine/godot` GitHub releases, `4.6.3-stable`,
  linux.x86_64 build). This only catches parse/type/autoload errors, NOT
  logic/visual/shader bugs — Brannon still needs an in-editor test pass for
  actual behavior confirmation every time.
- Read `PROJECT_SUMMARY.md` and relevant `docs/systems/*/README.md` first
  before touching source, to keep credit usage down. Reference
  `architecture.json` for shape/signals/API before opening real source
  files.
- Any handover write must go to **this one file only** — `HANDOVER.md`
  (canonical case). Do not create a second lowercase copy.
- **Commit and push BEFORE reporting a feature done** — don't let a session
  end (credits or otherwise) with finished code sitting uncommitted; that's
  exactly what caused the "features missing" false alarm this session.

## Prior work this arc (closed out, kept brief — see docs/systems/water/README.md and docs/systems/structure/README.md for full technical detail on any of these)
- **Corner-pillar clipping / pipe-deconstruct-mode pass:** `PillarRegistry.register_single()` additive fix for the 4 pregen corner pillars; pipe segment deconstruct mode (hover/highlight/refund, mirrors wire deconstruct, reuses `WaterManager.delete_and_refund_edge()`).
- **Wall-locked routing notch/step-skip investigation (3 rounds):** `WallPerimeterRegistry` adjacency rewrite (cell-grid topology instead of raw Euclidean distance) to stop a false shortcut edge across notch/step boundaries; a sign-bug fix in the diagonal-corner adjacency formula (`cell_a + dir_a - dir_b`, not `+ dir_b`); a wrong-Manhattan-corner-choice fix in `_trace_wall_locked_path()`'s wall-to-wall chaining step. **Status: implemented and pushed, but never got an explicit final "confirmed working" from Brannon in this session's context — verify this is still solid before assuming it, especially if any new pillar/notch-routing report comes in.**
- **Water pipe routing (earlier arc, confirmed fixed):** wall-hugging clip fix, diagonal-detour fixes (2 rounds), backward-jog entry-leg fix — see `docs/systems/water/README.md`'s "Wall-locked pipe routing — three follow-up fixes" section.

## NEXT UP (unchanged, still pending — see `PROJECT_SUMMARY.md` §1 roadmap): Save/Load System Overhaul
Expand the existing `SaveManager` field-registry (phase-ordered: dug chunks
→ placed objects+extra state → player wires → water pipes → player
position/cash/clock) to cover:
- Bunker expansions (dug/cleared cells, current bunker footprint)
- Exact power setup: wiring graph, zones (incl. player rename/recolor),
  batteries, generators, breakers (tripped/upgraded state)
- Water system: pipe network graph, hookups, dispensers, sinks, water
  quality/flow state — **including the known purifier save gap**:
  `WaterManager.get_pipe_network_for_save()` only persists `"corner"`/
  `"pipe_joint"` roled nodes today; a `"purifier"` node (and both edges
  touching it) is silently dropped by save/load. Close this as part of the
  save/load pass.

**Before starting that session, read (in order):** `AI_CONTEXT.md` →
`PROJECT_SUMMARY.md` → `docs/systems/world-core/README.md` (existing
`SaveManager` pattern) → `docs/systems/power/README.md` Persistence section
→ `docs/systems/water/README.md` Persistence + Purification & Quality
sections. Ask Brannon to confirm scope before starting.
