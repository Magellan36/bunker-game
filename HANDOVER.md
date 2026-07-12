# BunkerGame — Agent Handover Doc

**Last updated:** repo HEAD `032dbfe`

Paste this whole file into a new chat to resume work with full context,
without carrying forward the old chat's history.

---

## Your role
Senior dev / expert GDScript co-programmer, architectural advisor, and
debugger for this Godot project. User (Brannon) is a vibe-coder novice —
explain non-obvious things, potential roadblocks, and tradeoffs as you go,
without being condescending about it. Act as the primary technical
authority; keep scalable, professional game-dev practices in mind and
proactively suggest/guide the project accordingly.

## Standing directive: minimize token/context usage, every session
**`PROJECT_SUMMARY.md` §0 is the authoritative version of this rule — read
it, it's short.** Summary: read `PROJECT_SUMMARY.md`'s system index →
go straight to the relevant `docs/systems/*/README.md` → consult
`architecture.json` for shape (dependencies/signals/API) → only THEN open
real source, and only the specific file/function involved. Never re-scan
the whole repo for a targeted change. If a doc is missing something you had
to find in source, add it back to the doc in the same commit — doc drift is
a bug.

## Working style Brannon wants
- Ask clarifying questions before big/ambiguous work — batch them into one
  round via a form, don't guess broadly.
- If multiple sessions fail to fix a bug, step back and consider a different
  root cause/approach rather than repeating the same fix.
- Confirm root cause before writing a fix. One change at a time when the
  system is complex (power grid especially). Prompt Brannon to test + report
  back rather than stacking unverified changes.
- Response format for code changes: Core Approach → Node Setup → Code → How
  it Works & Customization (loosen this for small/obvious fixes).
- Solo dev — keep things modular/reusable, avoid over-engineering.
- **No "god files":** don't let files accumulate too many unrelated
  responsibilities. Prefer a new, separate file for a self-contained new
  feature over bolting it onto an existing large file. Extends to folders
  too — place new files in the subfolder matching their responsibility (see
  `PROJECT_SUMMARY.md` §3), extending it with a new subfolder if nothing
  fits. Apply proactively at write-time, not as a later cleanup pass.

---

## Project basics
- **Company:** Magellan Apps, magellan-apps.com (NOT magellanapps.com),
  support@magellan-apps.com
- **Game:** BunkerGame — bunker survival/simulator + bunker design game. Two
  phases: Pre-Apocalypse (spend cash, build/buy) → Post-Apocalypse (survive
  on what you built). Tone: grim but not horror, brutalist/concrete
  aesthetic, military UI — dark/gloomy/eerie. Full vision/direction detail:
  `PROJECT_SUMMARY.md` §1.
- **Godot version:** 4.6.3. Strict Godot 4 syntax only (no deprecated G3),
  statically typed GDScript, clean/commented code. Jolt physics for 3D.
- **Bunker dimensions:** width=24, depth=18 (`BunkerLayout.gd` exports).

## Repo / workflow — CRITICAL, do not deviate
- **GitHub only.** Repo: `Magellan36/bunker-game`, branch `main`. ALL file
  operations go: read from repo → edit in sandbox → commit + push to repo →
  Brannon pulls in Godot. **No zip downloads, ever**, for this project.
- Clone fresh each new sandbox (e.g. `/home/user/bunker-game-repo-src`). A
  GitHub Personal Access Token is supplied via `ask_secrets` into a `.env`
  file, used directly with `git` over HTTPS:
  `https://x-access-token:$TOKEN@github.com/Magellan36/bunker-game.git`.
  Don't use the GitHub pipedream plugin for file edits (no delete-file
  action) — use raw `git`/bash.
- **`PROJECT_SUMMARY.md`** (repo root) is the living index — read it FIRST
  every session, then follow its §2 system index straight to the relevant
  `docs/systems/*/README.md`. Update both whenever a system's shape changes.

## Verifying changes — real headless Godot check available
A real Godot 4.6.3 headless binary + check script exist — no more relying
only on bracket-balance checks.
- Binary: download once per sandbox from
  `https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip`
  (matches Brannon's editor version exactly). Not committed to the repo
  (130MB+ engine binary) — re-download into the sandbox each fresh session,
  e.g. to `/home/user/godot-bin/`.
- Check script: `tools/godot_check.sh <path-to-godot-binary>` — runs
  `--headless --import` then `--headless --quit` against the real project,
  greps for `SCRIPT ERROR`/`Parse Error`/`Compile Error`/`Failed to load
  script`. See `PROJECT_SUMMARY.md` §16 for full detail.
- **Run this before reporting any fix as done.** Catches script parse/type
  errors and broken autoload/`class_name` references — the exact class of
  bug that used to only surface when Brannon pulled and hit it in his own
  editor.
- **What it still can't catch:** actual gameplay/runtime logic bugs and
  anything GPU-visual (no render/screenshot capability headless, no GPU in
  this sandbox) — those still need Brannon's own in-editor test pass.

## Debug logging — keep ALL of it, do not strip
Every debug print preserved (system still stabilizing): `[PM:*]`, `_pmdbg`
in PowerManager, `_wdbg`/`[BreakerBox]`/`[MW:DIAG]`/`[SPLIT]` in various
files, `WIRE_DEBUG` toggles. F9 in-game dumps full wire/zone/PM state to
`user://wire_debug.txt`. Always ask for this dump + console output when
debugging power/wire issues. Only strip prints once Brannon explicitly asks
for a given stable system.

---

## Recurring gotcha — Godot class-cache / .uid staleness
Hit repeatedly this project: a brand-new script with `class_name` (created
via git, never opened/saved in the Godot editor) sometimes isn't recognized
("Could not find type X") even after a soft **Project → Reload Current
Project**. Fix that has worked every time: **fully quit Godot, delete the
local `.godot/` cache folder (gitignored, safe, auto-regenerates), reopen
the project.** `tools/godot_check.sh` now catches this specific symptom
ahead of time for anything already pushed.

**New autoloads specifically:** `project.godot`'s `[autoload]` section is
owned by the Godot editor — hand-editing it via git while Godot has the
project open can get silently overwritten back to stale in-memory state on
next save/close. **Default rule:** Brannon adds new autoloads himself via
Project Settings → Autoload in the editor, not the agent hand-editing
`project.godot` directly.
**Exception made once (repo HEAD `00938b5`):** `GraphicsSettings` was
committed directly into `project.godot`'s `[autoload]` list because Brannon
hit trouble adding it manually — verified with a clean headless boot before
pushing. This is a one-off exception, not a new standing rule; still follow
the default (editor-side registration) for any *future* new autoload unless
Brannon explicitly asks for the same workaround again. If a future
`project.godot` edit does get silently reverted by the editor, that's the
signal to fall back to walking Brannon through the manual editor steps
instead of re-pushing the same hand-edit.

## Windows-side pull gotcha (new, this session)
Brannon hit a git-pull failure on Windows/PowerShell: newly-committed
`.uid`/`.import` files (generated locally by his own editor, untracked)
collided with the same files now landing from a push. Fixed via:
```powershell
git stash -u
git pull
git stash pop
```
Separately, `git stash -u` itself once failed with `Unlink of file ...
failed` on an unrelated locked `.dll` (Windows file-lock/AV scan issue, nota
git bug) — resolved by closing Godot fully / retrying. Worth remembering if
similar Windows-side lock errors show up again: usually means a running
process (often Godot itself, sometimes AV) has a handle open on the file
git is trying to touch — close Godot, retry, escalate to closing AV or
running PowerShell as admin if it persists.

## GDScript gotchas hit for real this project (don't repeat these)
Full list + detail: `PROJECT_SUMMARY.md` §10. Headlines: `as` does NOT
support enum casts (retype to plain `int` instead); `MeshLibrary` has no
`has_item()` (use `get_item_list()` + `.has(id)`); the image-gen tool bakes
transparency as opaque pixels for VFX textures (use PIL directly instead).

## Extraction methodology — reusable playbook for any future file split
Full detail: `PROJECT_SUMMARY.md` §12. Summary: map dependencies first,
never move a heavily-referenced dict (use an `_owner` back-reference
instead), slice function bodies verbatim (never retype from memory), keep
forwarding wrapper methods for every moved public function, verify zero
external callers before extracting, run `tools/godot_check.sh` as the final
correctness check instead of manual bracket-counting.

---

## Where everything else is now
Per-system detail (Power, World Core, UI — with more systems migrating
incrementally as they're touched) lives in `docs/systems/*/README.md`, NOT
in this file. Do not re-add system-specific status writeups here — they
belong in the relevant system's README (add a `## History` subsection there
if genuinely historical detail is worth keeping). This file stays
role/workflow/gotchas only, so it doesn't regrow to its old ~620-line
length.

## Current status
- Docs restructure (per-system `docs/systems/*/README.md` +
  `architecture.json` + slimmed `PROJECT_SUMMARY.md`/`HANDOVER.md`):
  **complete**, confirmed working.
- Headless Godot compile-check tool (`tools/godot_check.sh`): **complete**,
  confirmed working, catching real issues. Re-download the Godot 4.6.3
  binary into `/home/user/godot-bin/` at the start of every fresh sandbox
  (not committed — 130MB+ engine binary, see §16 in `PROJECT_SUMMARY.md`).
- `GraphicsSettings` autoload: **confirmed working** in Brannon's editor
  after pulling `00938b5` (resolved cleanly, no class-cache issue that
  time).
- **Expanded-area wall/breaker snap bug: fixed and confirmed working**
  (`WallSnapHelpers.gd` + `BuildModeController.spawn_structure()` +
  `BunkerPregen.gd` — added an `_is_true_pregen` tag distinct from the
  broader `_is_pregen` tag so only the ORIGINAL 4 boundary walls get the
  strict original-rectangle interior-face check; autofill walls in
  expanded/dug areas now snap the same simple way player-placed walls do).
  See `docs/systems/build/README.md` (Build Mode is now migrated).
- **Zone rename + recolor (July 2026): shipped and confirmed working.**
  Power Terminal can rename/recolor the single zone it's wired into
  (`ZoneCustomization.gd`, `ZoneCustomizeUI.gd`, `DeviceDatabase.
  ZONE_PLAYER_COLOR_CHOICES`, `PowerManager.zone_display_color()` — see
  `docs/systems/power/README.md` Public API section). One follow-up bug
  found + fixed during testing: the "ZONE FLOW" line in `PowerTerminalUI.gd`
  had a pre-existing from/to label-color swap (a zone's own recolor showed
  up on its NEIGHBOR's label instead) — fixed, each zone's label now always
  shows that zone's own true color.
- **Pause menu / graphics panel blurred backdrop: fixed and confirmed
  working.** Both `PauseMenuUI.gd` and `GraphicsSettingsPanel.gd`'s backdrop
  `ColorRect` now always sets a dim `Color(0,0,0,0.55)` base before layering
  the blur shader material on top — previously only set in the "shader
  failed to LOAD" branch, so a shader that loaded fine but failed to
  actually RENDER (GPU/driver-specific) showed solid opaque white instead
  of any kind of overlay.
- **`GridState.BROWNOUT`/`TRIPPED` unreachable-state bug: fixed and
  confirmed working.** `_start_flicker_offline()` had zero call sites, so
  total grid failure jumped straight from OVERLOADED to a hard OFFLINE cut
  with zero warning — no flicker, no "breaker tripped" moment, even though
  `LightingDirector.gd`/HUD were already fully wired to react to those
  states. Now: `PowerSolver.gd`'s total-failure branch triggers
  `_start_flicker_offline()`, and `_go_offline()`'s "no local battery left"
  tail now calls the already-complete `_trip_main_grid()` (→ `TRIPPED`,
  recoverable via `reset_main_breaker()`) instead of hard-setting
  `GridState.OFFLINE`. See `docs/systems/power/README.md` Known
  tradeoffs — **two related follow-up items were found but deliberately
  NOT fixed** (out of scope for that pass, noted there for a future one):
  `_go_offline_true()` has the same "zero call sites" shape, and the
  per-zone "sustained brownout" system was never re-audited for a similar
  orphaned trigger.
- **Wire-mode stale hover-label leak: fixed and confirmed working.**
  `WireDrawMode._cancel()` (called on every wire-mode/build-mode exit) now
  also clears `_hover_label` — previously, exiting while hovering a wire
  node/generator/wall light left its floating `Label3D` orphaned in the
  scene permanently, and repeated build-mode entry/exit while hovering
  could stack up multiple stuck labels.
- **Water system Phase 1 groundwork: built, headless-compile-clean, NOT YET
  TESTED IN-EDITOR (July 2026).** New standalone `scripts/world/water/`
  system per the groundwork plan — `WaterGraph`/`WaterManager` (data model +
  BFS connectivity, mirrors `PowerGraph`/`PowerManager`'s split from day one),
  `WaterHookup` (wall-mounted source, never deletable, auto-tracks the
  outermost wall in its facing direction via the SAME
  `RockSurround.chunk_deconstructed/restored` boundary-change event
  `WireGraphBuilder` already uses), `WaterPipeSegment`/`WaterPipeElbow`
  (always-visible pipe visuals, corners are real graph nodes),
  `WaterPipeDrawMode` (placement tool), `WaterTestSink` (end-to-end
  acceptance test device). New tile IDs `TILE_WATER_HOOKUP=17`/
  `TILE_WATER_SINK=18`, new tool `TOOL_WATER_PIPE=6` — wired into
  `BuildModeController`/`BuildModeHUD`/`MainWorld`. Also added a generic
  `WallSnapHelpers._snap_to_nearest_wall()` (purely additive — the two
  existing snap functions were NOT modified) and fixed the real
  Move-tool-doesn't-wall-snap gap the plan called out for `TILE_LIGHT`/
  `TILE_BREAKER`/`TILE_BREAKER_SMART` too (previously moving any of these
  just re-snapped to the flat grid, never re-checking for a wall — now
  reuses the existing proven `_snap_light_to_wall`/`_snap_breaker_to_wall`
  during a move, zero risk to their initial-placement behavior).
  **Full detail: `docs/systems/water/README.md`.**
  **Flagged deliberately per the plan's own pre-approved fallback:**
  `WaterPipeDrawMode` ships with the segment-at-a-time + auto-elbow
  interaction model, NOT the full single-drag continuous-paint experience —
  see that doc's Known tradeoffs for the exact reasoning and upgrade path.
  **Verification status:** `tools/godot_check.sh` passes clean (one real bug
  caught and fixed by it: `WaterManager.has_node()` collided with `Node`'s
  own built-in method — renamed to `has_water_node()`). Zero in-editor
  testing has been done — Brannon needs to pull and verify: hookup
  placement/wall-snap/move/never-deletable, pipe placement around at least
  one corner, the test sink turning green, and the hookup correctly
  following an expanded dig boundary.
- **Water system playtest-feedback pass (July 2026, NOT YET TESTED
  IN-EDITOR — this is a response to Brannon's first round of in-editor
  testing, itself unverified so far):** 4 fixes/changes on top of the
  groundwork above, all headless-compile-clean: (1) `WaterPipeSegment.PIPE_RADIUS` raised to match
  `WaterHookup.STUB_RADIUS` (0.09) so pipes and the hookup read as one
  continuous pipe — `WaterPipeElbow.JOINT_RADIUS` bumped to 0.105 to match;
  (2) **pipe routing model rewritten** from the original wall-hugging
  magnetic-snap to strictly axis-aligned (90°-only) Manhattan routing along
  a fixed near-ceiling height (`WaterPipeDrawMode.WATER_CEILING_Y = 2.8`) —
  `_find_wall_hug_point()` and the wall-snap constants are gone entirely,
  replaced by pure-geometry `_build_manhattan_path()`; a destination that
  snaps onto an existing lower graph node (e.g. a sink) gets one final
  vertical drop segment automatically; (3) `WaterHookup`'s placement height
  raised near the ceiling (`BuildModeController.WATER_HOOKUP_PLACEMENT_Y =
  2.8`, kept in manual sync with `WaterPipeDrawMode.WATER_CEILING_Y`),
  above wall-light height, so the hookup and its pipes visually run along
  the ceiling; (4) `TILE_WATER_HOOKUP`/`TILE_WATER_SINK` added to
  `BuildModeController`'s connectable-dot system (`CONNECTABLE_TILES`/
  `CONNECTABLE_TILES_QUICK`) — same blue dot overlay lights/generators
  already get in build mode. Also: `WaterTestSink` now registers its graph
  node at the TOP of its box (its real physical connection point) instead
  of its base — this is what makes pipe-to-sink connections (and the
  sink's CONNECTED/NOT CONNECTED label) actually work; previously
  `_resolve_destination()` never checked for nearby existing nodes at all,
  so a pipe could never actually reach the sink. Full detail:
  `docs/systems/water/README.md` (updated throughout).

- **Doc migration (July 2026): complete.** All 8 systems now have a
  `docs/systems/*/README.md` (Player, Furniture/Items, Build Mode,
  Environment, Graphics/Camera joined the existing Power/World Core/UI).
  `PROJECT_SUMMARY.md` §2/§3/§5 and §6/§7/§8 updated to point at the new
  docs instead of duplicating content. One doc-drift bug caught and noted
  while writing the Graphics doc: `GraphicsSettings.gd`'s own header
  comment still says "NOT YET REGISTERED AS AN AUTOLOAD" even though it IS
  registered in the committed `project.godot` (repo HEAD `00938b5`) — flagged
  in `docs/systems/graphics/README.md`, not yet fixed in the source comment
  itself (low-risk, cosmetic-only, fix opportunistically next time that
  file is touched for something else).

## Next up
**Immediate:** Brannon needs to pull and test the water system
playtest-feedback pass (pipe/hookup diameter match, 90°-only ceiling
routing, pipe-to-sink connection + CONNECTED label, connectable dots on
hookup/sink) — nothing further should be built on top of the water system
until this round is confirmed working.

See `PROJECT_SUMMARY.md` §1 "Roadmap priorities" for the rest of the list
(water system Phase 2, Main Menu, Death/game-over state, emergency_light
placement, generator exhaust smoke scaling, remaining graphics-overhaul
deferred items). No systems pending doc migration anymore (all 9 — including
the new Water system — done as of July 2026).

Two specific follow-up investigations flagged during recent work (both
noted in `docs/systems/power/README.md` Known tradeoffs, neither started):
- `_go_offline_true()` (`PowerManager.gd`) has zero call sites anywhere —
  same dead-code shape as the just-fixed BROWNOUT/TRIPPED bug. Its
  intended trigger context (`PowerManager.gd` ~line 3343/3385, the
  per-battery-group drain loop) explicitly comments "do NOT call
  `_go_offline_true()` here", so this needs its own investigation of
  whether it's still needed at all or fully superseded by `_go_offline()`'s
  per-sub-grid local-battery check — don't assume, confirm first.
- The per-zone "sustained brownout" system
  (`PowerSolver._sustained_brownout_component()`, `_exhausted_brownout_keys`)
  uses a different trigger mechanism than the one just fixed and was never
  re-checked for a similar orphaned-trigger problem.
