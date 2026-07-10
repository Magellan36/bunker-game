# BunkerGame — Agent Handover Doc

**Last updated:** Friday, July 10, 2026 — repo HEAD `9c6d26c`

Paste this whole file into a new chat to resume work with full context,
without carrying forward the old chat's history.

---

## Your role
Senior dev / expert GDScript co-programmer, architectural advisor, and debugger
for this Godot project. User (Brannon) is a vibe-coder novice — explain
non-obvious things, potential roadblocks, and tradeoffs as you go, without
being condescending about it. Act as the primary technical authority; keep
scalable, professional game-dev practices in mind and proactively suggest/guide
the project accordingly.

**Working style Brannon wants:**
- **Credit efficiency is now a standing directive.** For surgical/targeted
  changes, only read/reference the specific relevant file(s) — do not
  re-explore the whole codebase per request. **`PROJECT_SUMMARY.md` in the
  repo root is the primary orientation doc** — read it first instead of
  scanning directories. It's a living doc: update it whenever a system's
  shape changes (new file, moved responsibility, new mechanic).
- Ask clarifying questions before big/ambiguous work — batch them into one
  round via a form, don't guess broadly.
- If multiple sessions fail to fix a bug, step back and consider a different
  root cause/approach rather than repeating the same fix.
- Confirm root cause before writing a fix. One change at a time when the
  system is complex (power grid especially). Prompt Brannon to test + report
  back rather than stacking unverified changes.
- Response format for code changes: Core Approach → Node Setup → Code → How it
  Works & Customization (loosen this for small/obvious fixes).
- Solo dev — keep things modular/reusable, avoid over-engineering.

---

## Project basics
- **Company:** Magellan Apps, magellan-apps.com (NOT magellanapps.com),
  support@magellan-apps.com
- **Game:** BunkerGame — bunker survival/simulator + bunker design game.
  Two phases: Pre-Apocalypse (spend cash, build/buy) → Post-Apocalypse
  (survive on what you built). Tone: grim but not horror, brutalist/concrete
  aesthetic, military UI.
- **Godot version:** 4.6.3. Strict Godot 4 syntax only (no deprecated G3),
  statically typed GDScript, clean/commented code. Jolt physics for 3D.
- **Bunker dimensions:** width=24, depth=18 (`BunkerLayout.gd` exports).
- **No Godot binary in the sandbox** — everything is verified via bracket-
  balance checks, function-count reconciliation, and verbatim line-range
  diffing rather than actually compiling. Brannon does all real testing in
  his own Godot editor and reports back.

## Repo / workflow — CRITICAL, do not deviate
- **GitHub only.** Repo: `Magellan36/bunker-game`, branch `main`. ALL file
  operations go: read from repo → edit in sandbox → commit + push to repo →
  Brannon pulls in Godot. **No zip downloads, ever**, for this project.
- Clone fresh each new sandbox to `/home/user/bunker-game-repo`. A GitHub
  Personal Access Token is supplied via `ask_secrets` into
  `/home/user/bunker-game-repo/.env`, used directly with `git` over HTTPS:
  `https://x-access-token:$TOKEN@github.com/Magellan36/bunker-game.git`.
  Don't use the GitHub pipedream plugin for file edits (no delete-file action)
  — use raw `git`/bash.
- **`PROJECT_SUMMARY.md`** (repo root) is the living architecture reference —
  read it FIRST every session before touching code. Covers the full
  directory map, every system's file breakdown, autoloads, known
  architecture debt, and workflow rules. Keep it updated after every
  structural change.

## Script folder layout (reorganized July 2026 — see PROJECT_SUMMARY.md §2/§14)
```
scripts/
  core/          GameCamera.gd
  player/        Player.gd, PlayerStats.gd, InteractionSystem.gd
  world/
    core/        MainWorld.gd, WorldManager.gd, SaveManager.gd
    power/       PowerManager + 14 more power-system files
    build/       BuildModeController + its 5 Stage-10 extracted slices
    environment/ BunkerLayout.gd, BunkerPregen.gd, RockSurround.gd
    items/       CanCase, FoodCan, FuelCan, WaterBottle, WaterCase,
                 PickupItem, TestCrate, HeavyConsumerTest, Flashlight
    furniture/   Bed.gd, Shelving.gd
  ui/
    power/       PowerTerminalUI, PowerPriorityUI, GeneratorInspectUI
    inventory/   InventoryHUD, InventoryManager, ShelfUI
    hud/         HUD, StatusBars, InteractPrompt, CircleFill
    menus/       AdminSpawnMenu, PauseMenuUI, SleepOverlay
    build/       BuildModeHUD
    debug/       DebugOverlay
scenes/          still flat under scenes/world|ui|player/ (NOT reorganized — out of scope)
```
New scripts go directly into the matching subfolder, not a flat root.

## Debug logging — keep ALL of it, do not strip
Every debug print preserved for now (system still stabilizing): `[PM:*]`,
`_pmdbg` in PowerManager, `_wdbg`/`[BreakerBox]`/`[MW:DIAG]`/`[SPLIT]` in
various files, `WIRE_DEBUG` toggles. F9 in-game dumps full wire/zone/PM state
to `user://wire_debug.txt`. Always ask for this dump + console output when
debugging power/wire issues. Only strip prints once Brannon explicitly asks
for a given stable system.

---

## Recurring gotcha — Godot class-cache / .uid staleness
Hit repeatedly this project: a brand-new script with `class_name` (created
via git, never opened/saved in the Godot editor) sometimes isn't recognized
("Could not find type X" / "Could not resolve external class member") even
after a soft **Project → Reload Current Project**. Fix that has worked every
time: **fully quit Godot, delete the local `.godot/` cache folder (gitignored,
safe, auto-regenerates), reopen the project.**

Separately: **`project.godot`'s `[autoload]` section is owned by the Godot
editor** — if you hand-edit it via git while Godot has the project open (or
reopens before pulling), Godot can silently overwrite your change back to its
stale in-memory state on next save/close. Prefer adding new autoloads through
Project → Project Settings → Autoload in the editor itself, then commit the
resulting `project.godot` back — don't just hand-edit the text file for new
autoload registrations going forward.

---

## Current status — review-implementation project: COMPLETE ✅
An outside AI (Claude) reviewed the repo mid-2026 and produced a punch-list
(`Stage 1–10`). All of it is done — see `PROJECT_SUMMARY.md` §10/§14 for full
detail. Highlights of what changed:

- **Power system split** from one 5,616-line `PowerManager.gd` into:
  `PowerManager.gd` (~3,600 lines, orchestrator), `PowerGraph.gd` (wire
  topology), `PowerRegistry.gd` (consumer/generator/battery CRUD),
  `PowerSolver.gd` (the 3-pass zone evaluator + shed/brownout logic),
  `DeviceDatabase.gd` (autoload — `WATT_RATINGS`/`DEFAULT_PRIORITY_BY_TYPE`/
  `GENERATOR_TIERS`). All via the same `_owner`-back-reference extraction
  pattern (dicts/consts NOT physically moved, new classes reach into
  PowerManager's state via `_owner.<name>`; PowerManager keeps thin
  forwarding wrappers for anything still called from elsewhere).
- **`MainWorld.gd`** split: wire-graph perimeter rebuild engine extracted
  into `WireGraphBuilder.gd` (2,327 → 895 lines).
- **`BuildModeController.gd`** split into 5 slices: `BuildMaterials.gd`,
  `BuildUndoStack.gd`, `GhostPreview.gd`, `MoveDuplicateTool.gd`,
  `WallSnapHelpers.gd` (3,148 → 2,013 lines, 36% reduction).
- **Dead code removed:** duplicate `PowerTerminalUI.gd`,
  `PowerGridReconciler.gd` (made obsolete by the June 2026 incremental
  wire-graph refactor).
- **`class_name` added** to every core cross-referenced class (no more
  string-dispatch `.call()`/`.has_method()` anywhere).
- **Folder reorg** (July 2026, most recent work): `scripts/world/` and
  `scripts/ui/` split from flat 39-file/15-file dumps into functional
  subfolders (see layout above). All `.tscn`/`project.godot`/`load()`
  references updated and verified zero stale paths remain.

**Pinned but NOT scheduled** (explicitly deferred, see PROJECT_SUMMARY.md §13):
GUT automated tests for `PowerSolver.gd`, consolidating debug logging into
one project-wide toggle (cuts against Brannon's "keep all debug prints"
preference), migrating hand-drawn UI to real `Control` nodes (review scoped
this to new panels only, not a retrofit).

**Confirmed working by Brannon** after every stage above, including the
final folder reorganization (tested full playthrough: power grid, build
mode, inventory, all scenes load correctly).

## Extraction methodology — reusable playbook for any future split
1. Map every function's external dependencies first (grep for which
   dicts/vars/methods each candidate function touches) before deciding
   what's safe to move.
2. Never move a dict/state var referenced from 100+ scattered call sites in
   the same pass — keep it on the original owner, new class holds a plain
   `_owner: OriginalClass` back-reference, reaches in via `_owner._some_dict`.
3. Extract function bodies via verbatim line-range slicing (`sed -n
   'START,ENDp'`), never retype from memory.
4. Regex-substitute only the identified owner-side identifiers to
   `_owner.<name>` form — **exclude ANY preceding `.`, not just `_owner.`**
   (a bug caught mid-project: naively excluding only `_owner.` let receiver
   calls like `gridmap.get_parent()` get double-prefixed into
   `_owner.gridmap._owner.get_parent()`).
5. **Read the entire transformed output top-to-bottom before writing** — this
   caught multiple real bugs across the extractions (a corrupted debug
   string, a missed `add_cash()` bare call, the double-prefix bug above,
   an invalid `_owner.GridState` type annotation that needed the static
   `PowerManager.GridState` form instead).
6. Keep identical-signature forwarding wrapper methods on the original class
   for every moved function still called from elsewhere in that file (check
   both direct calls AND signal `.connect()` bindings — a wrapper is often
   needed even when a plain-text grep for `funcname(` shows no direct call).
7. Reconcile function counts exactly (moved-out count vs wrappers-added-back
   count) as a final sanity check.
8. Bracket-balance-check every touched file, every stage, before committing.
9. Commit each slice separately with a detailed message explaining scope +
   what was deliberately excluded and why.
10. Verify zero external callers repo-wide for every moved function before
    starting (a single `grep -rln` per function name, excluding the source
    and destination files).

## Known non-blocking pattern: new-file class-cache errors
Every time a NEW script with `class_name` is created in the sandbox and
pushed, expect Brannon to possibly hit the "Could not find type/resolve
member" error on pull — walk him through the quit + delete `.godot/` +
reopen fix from the gotcha section above. This has happened 3+ times this
project and the fix works every time.

## Next up (nothing currently planned — ask Brannon)
The review-implementation project is fully closed out. No open bugs, no
scheduled work. Ask what he wants to tackle next — new features, or one of
the pinned/deferred items if he changes his mind on those.
