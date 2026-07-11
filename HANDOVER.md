# BunkerGame — Agent Handover Doc

**Last updated:** repo HEAD `82e618b`

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
- **Credit efficiency is a standing directive.** For surgical/targeted
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
- **No "god files" (standing instruction, July 2026):** don't let files
  accumulate too many unrelated responsibilities. Prefer a new, separate file
  for a self-contained new feature over bolting it onto an existing large
  file. Extends to folders too — place new files in the subfolder matching
  their responsibility (see the directory map below), extending it with a
  new subfolder if nothing fits, rather than dropping things in flat/
  convenient locations. Apply this proactively at write-time, not as a
  later cleanup pass. See `PROJECT_SUMMARY.md` §12 for the full wording.

---

## Project basics
- **Company:** Magellan Apps, magellan-apps.com (NOT magellanapps.com),
  support@magellan-apps.com
- **Game:** BunkerGame — bunker survival/simulator + bunker design game.
  Two phases: Pre-Apocalypse (spend cash, build/buy) → Post-Apocalypse
  (survive on what you built). Tone: grim but not horror, brutalist/concrete
  aesthetic, military UI — **dark/gloomy/eerie**, not bright (see the
  lighting-blowout fix below; this was a real regression that got fixed).
- **Godot version:** 4.6.3. Strict Godot 4 syntax only (no deprecated G3),
  statically typed GDScript, clean/commented code. Jolt physics for 3D.
- **Bunker dimensions:** width=24, depth=18 (`BunkerLayout.gd` exports).
- **No Godot binary in the sandbox** — everything is verified via bracket-
  balance checks, function-count reconciliation, and verbatim line-range
  diffing rather than actually compiling. Brannon does all real testing in
  his own Godot editor and reports back. **This means every fix needs an
  actual in-editor eyeball/test pass before being considered done** —
  several recent fixes were "confirmed working" only after Brannon tested,
  not assumed from the code alone.

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
  structural change. It is currently ~620 lines and well-maintained —
  trust it over re-exploring.

## Script folder layout (see PROJECT_SUMMARY.md §2 for the authoritative map)
```
scripts/
  core/          GameCamera.gd, GraphicsSettings.gd (autoload, not yet
                 registered by name in project.godot — see gotcha below)
  player/        Player.gd, PlayerStats.gd, InteractionSystem.gd
  world/
    core/        MainWorld.gd, WorldManager.gd, SaveManager.gd
    power/       PowerManager + 15 more power-system files (see §6)
    build/       BuildModeController + its Stage-10 extracted slices
    environment/ BunkerLayout.gd, BunkerPregen.gd, RockSurround.gd,
                 LightingDirector.gd, DustMotes.gd
    items/       Pickup-able item scripts incl. Flashlight.gd
    furniture/   Bed.gd, Shelving.gd
  ui/
    power/       PowerTerminalUI, PowerPriorityUI, GeneratorInspectUI
    inventory/   InventoryHUD, InventoryManager, ShelfUI
    hud/         HUD, StatusBars, InteractPrompt, CircleFill
    menus/       AdminSpawnMenu, PauseMenuUI, SleepOverlay, GraphicsSettingsPanel
    build/       BuildModeHUD
    debug/       DebugOverlay
    common/      UIFade.gd (shared fade-in helper, see UI conventions below)
scenes/          still flat under scenes/world|ui|player/ (NOT reorganized — out of scope)
```

## Debug logging — keep ALL of it, do not strip
Every debug print preserved (system still stabilizing): `[PM:*]`, `_pmdbg` in
PowerManager, `_wdbg`/`[BreakerBox]`/`[MW:DIAG]`/`[SPLIT]` in various files,
`WIRE_DEBUG` toggles. F9 in-game dumps full wire/zone/PM state to
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
the project.**

**New autoloads specifically:** `GraphicsSettings.gd` (see below) is a real
autoload-pattern script but is **NOT yet registered by name** in
`project.godot`'s `[autoload]` section — per this same gotcha, Brannon adds
new autoloads himself via Project Settings → Autoload in the editor (already
done for `GraphicsSettings`, confirmed working), rather than the agent
hand-editing `project.godot`'s autoload list directly (the editor owns that
section and can silently overwrite hand-edits).

Separately: **`project.godot`'s `[autoload]` section is owned by the Godot
editor** — if hand-edited via git while Godot has the project open, Godot can
silently overwrite the change back to its stale in-memory state on next
save/close.

---

## Current status — Graphics Overhaul: COMPLETE + STABILIZED ✅
A full 7-phase graphics overhaul (`bunker-game-graphics-plan.md`) was
implemented, reviewed twice (external implementation-review docs), and then
went through a real bug hunt after Brannon reported the bunker looking
blown-out/washed-out instead of dark/gloomy/eerie. **All of this is now
confirmed working by Brannon** as of repo HEAD `82e618b`. Full detail lives
in `PROJECT_SUMMARY.md` §15 (long section, read it directly rather than
re-deriving from this summary) — highlights:

- **Phases 1/2/3/7** (renderer/environment baseline, `GraphicsSettings`
  autoload + settings panel, `LightingDirector.gd` fog/vignette reactor,
  flashlight dust motes + ambient dust, camera DOF/shake/FOV) — functionally
  complete.
- **Phases 4/5/6** (materials, HUD polish, remaining VFX) — deliberately
  PARTIAL by design, not bugs: real trim-sheet/PBR/UV texture work was never
  attempted (needs visual iteration in-editor, can't do blind); decals
  skipped; existing device LED colors (`BreakerBox`/`BatteryBank`/
  `GeneratorObject`) were NOT retrofitted onto the shared
  `DeviceDatabase.STATE_EMISSION_COLORS` convention (real regression risk on
  the most-tested system in the project, no functional payoff); generator
  exhaust smoke exists but is NOT scaled to fuel-burn/load (always on/off at
  a fixed intensity — this was explicitly considered and then explicitly
  deferred again, see "Next up" below).
- **Lighting blowout fix** (real bug hunt, not just polish): the bunker was
  reading bright/washed-out (warm yellow rooms, big soft bloom halos, cream
  walls) instead of dark/gloomy. Root-caused to 5 compounding settings via
  an external review doc, fixed in order: `tonemap_white` was never set
  (now `5.0`), `tonemap_mode` was Filmic despite a comment claiming ACES (now
  genuinely ACES, `= 3`), every `WallLight` was scattering full brightness
  into volumetric fog (now capped via `light_volumetric_fog_energy = 0.2`),
  `WallLight.LIGHT_ENERGY` was tuned pre-post-processing-stack (`4.5 → 2.0`),
  `glow_hdr_threshold` was catching nearly every lit surface (`1.0 → 1.4`).
- **Follow-up taste pass**: `adjustment_brightness = 0.87`,
  `adjustment_saturation = 0.9`, `sdfgi_energy = 0.7` (all previously
  neutral/default and doing nothing).
- **Pregen floor/wall/pillar material fix**: the STARTING bunker's GridMap
  tiles (`bunker_tiles.meshlib`) are a completely separate asset from
  Build Mode's player-placed walls (which already had a darkened concrete
  tint). Fixed via `BunkerPregen.gd`'s new `_retint_meshlib()` — duplicates
  the MeshLibrary at runtime (never touches the shared binary `.meshlib` on
  disk) and darkens the floor/wall/pillar items' existing materials by the
  same factor Build Mode uses. Hit one real bug fixing this:
  `MeshLibrary.has_item()` doesn't exist — real API is
  `get_item_list() -> PackedInt32Array`, fixed and confirmed working.
- **3 issues from an implementation-review pass**, also fixed and confirmed:
  FOV slider was writing to disk on every drag tick (split
  `GraphicsSettings.set_setting()` into `set_setting_live()` + `save_now()`,
  wired to `Slider.drag_ended`); the grid-fault alarm vignette color was
  nearly identical to the survival-stat warning color (changed to a
  distinct hot amber); `apply_preset()` took a typed `Preset` enum param
  where its only caller hands back a bare `int` — retyped to plain `int`
  throughout rather than relying on implicit int→enum passing.
- **New standing UI convention**: every panel that opens via player
  interaction now fades in via a shared `scripts/ui/common/UIFade.gd`
  helper (`UIFade.fade_in(target)`) — applied to ALL current panels
  (Power Terminal, Power Priority, Generator Inspect, Breaker settings +
  Upgraded Breaker for free via inheritance, Battery Bank, Shelf UI, Admin
  Spawn Menu, Pause Menu, Graphics Settings, Build Mode HUD). **Every new
  panel going forward should call this too** — it's documented as a
  standing rule in `PROJECT_SUMMARY.md` §9, not just this pass's scope.

## Other recent fixes (power system)
- **Priority-change grace period** (0.5s): `set_consumer_priority()` no
  longer resets shed state + resolves immediately on click — it queues the
  change and only fires the actual reset+resolve once
  `PRIORITY_CHANGE_GRACE_SECS` elapses in `PowerManager._process()`.
  Prevents a priority change from visibly flashing the grid through a
  transient state before settling. Multiple changes within the window
  collapse into one resolve.
- **`WallLight.gd` default priority: `3 → 1`** (critical/never-shed) — both
  pregen level-start lights and player-placed lights use the same script,
  so this one default change covers both. Investigated what initially
  looked like a "priority change applied to the wrong consumer" bug via
  deep debug-dump log analysis — turned out to be Brannon's own confusion
  about how shared-tier shedding was interacting (wall lights + a load-test
  object sharing tier 3), not an actual routing bug. No code fix was needed
  for that part; closed out in `PROJECT_SUMMARY.md` §6.2.

## Extraction methodology — reusable playbook for any future file split
(Unchanged from prior handover — still the right process if a file needs
splitting.)
1. Map every function's external dependencies first (grep for which
   dicts/vars/methods each candidate function touches) before deciding
   what's safe to move.
2. Never move a dict/state var referenced from 100+ scattered call sites in
   the same pass — keep it on the original owner, new class holds a plain
   `_owner: OriginalClass` back-reference, reaches in via `_owner._some_dict`.
3. Extract function bodies via verbatim line-range slicing (`sed -n
   'START,ENDp'`), never retype from memory.
4. Regex-substitute only the identified owner-side identifiers to
   `_owner.<name>` form — exclude ANY preceding `.`, not just `_owner.`.
5. Read the entire transformed output top-to-bottom before writing.
6. Keep identical-signature forwarding wrapper methods on the original class
   for every moved function still called from elsewhere (check signal
   `.connect()` bindings too, not just direct calls).
7. Reconcile function counts exactly as a final sanity check.
8. Bracket-balance-check every touched file before committing (a
   `bracket_check.py`-style paren/bracket/brace count script is fast and
   catches most structural mistakes given there's no Godot binary here to
   actually compile).
9. Commit each slice separately with a detailed message.
10. Verify zero external callers repo-wide for every moved function first.

## Known non-blocking pattern: new-file class-cache errors
Every time a NEW script with `class_name` is created and pushed, expect
Brannon to possibly hit "Could not find type/resolve member" on pull — walk
him through quit + delete `.godot/` + reopen (see gotcha section above).

## GDScript gotchas hit for real this project (don't repeat these)
- **`as` does NOT support enum casts** — only Object/class casts (`x as
  SomeClass`). Enums are plain ints in GDScript; assign/pass them directly,
  no cast needed or possible. Hit this exact bug twice already
  (`GraphicsSettings.gd`'s `msaa`/`_apply_to_viewport()`, and
  `GraphicsSettingsPanel.gd`'s preset dropdown) — when in doubt, retype the
  parameter/var to plain `int` instead of fighting the cast.
- **`MeshLibrary` has no `has_item()` method** — use
  `get_item_list() -> PackedInt32Array` and `.has(id)` on that instead.
- **Image-gen tool output has no real alpha channel** for particle/VFX
  textures needing transparency — it bakes the transparency-checkerboard
  preview as opaque pixels. Build these with PIL directly instead
  (`assets/textures/vfx/soft_glow_dot.png`, `smoke_puff.png` were done this
  way and confirmed to have real alpha).

---

## Next up (nothing currently in progress — ask Brannon)
Two items were on the table this session and were explicitly **not** done
(Brannon said "nevermind" mid-implementation) — ask before assuming either
is still wanted:
- **Generator exhaust smoke scaled to fuel-burn/load.** Design was worked
  out but reverted before committing: scale `GeneratorObject.gd`'s exhaust
  `ParticleProcessMaterial` velocity/scale range + smoke sprite alpha using
  the exact same `share * (0.2 + 0.8 * load_ratio())` formula
  `PowerManager._tick_generators()` already uses for fuel drain (`share =
  this_generator's_watts / total_capacity_watts`), polled on a ~0.5s timer
  rather than every frame. Deliberately does NOT touch
  `GPUParticles3D.amount` at runtime (can visibly restart/hitch the
  system) — only material properties, which are safe to change
  continuously. No code currently exists for this; would start fresh.
- **Placing `emergency_light` device instances near breaker boxes.** This
  device type already exists in `DeviceDatabase.WATT_RATINGS` (8W,
  priority 1) — it's a design/build-menu placement task, not code.

Beyond those two, also still open from the graphics overhaul (see "Current
status" above for full detail): real trim-sheet/PBR materials + UV work,
decals. And still-pinned-but-not-scheduled from the original architecture
review: GUT automated tests (no test framework in the repo at all
currently), consolidating debug logging into one toggle (cuts against
Brannon's own "keep all debug prints" preference — only do this if he
explicitly asks), migrating hand-drawn immediate-mode UI to real `Control`
nodes (scoped to new panels only per the original review, not a retrofit).

Also mentioned much earlier in the project's life and never picked back up
— confirm with Brannon whether these are still wanted before starting:
**Main Menu scene**, **Death/game-over state**. No trace of either in the
repo currently.
