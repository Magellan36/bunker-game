# BunkerGame — Agent Handover Doc

**Last updated:** repo HEAD `b9d6ef8`

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

## Verifying changes — real headless Godot check now available
**As of July 2026, a real Godot 4.6.3 headless binary + check script exist**
— this replaces the old "no compiler, only bracket-balance checks" era.
- Binary: download once per sandbox from
  `https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_linux.x86_64.zip`
  (matches Brannon's editor version exactly). Not committed to the repo
  (it's a 130MB+ engine binary) — re-download into the sandbox each fresh
  session, e.g. to `/home/user/godot-bin/`.
- Check script: `tools/godot_check.sh <path-to-godot-binary>` — runs
  `--headless --import` then `--headless --quit` against the real project,
  greps for `SCRIPT ERROR`/`Parse Error`/`Compile Error`/`Failed to load
  script`. Auto-patches in the locally-registered `GraphicsSettings`
  autoload for the run only (see gotcha below), restores `project.godot`
  exactly afterward — never commits that patch. See
  `PROJECT_SUMMARY.md` §16 for full detail.
- **Run this before reporting any fix as done.** It catches script
  parse/type errors and broken autoload/`class_name` references — the
  exact class of bug that used to only surface when Brannon pulled and hit
  it in his own editor.
- **What it still can't catch:** actual gameplay/runtime logic bugs (e.g.
  "the zone shed the wrong item") and anything GPU-visual (no
  render/screenshot capability headless, no GPU in this sandbox either) —
  those still need Brannon's own in-editor test pass and report-back.

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
ahead of time for anything already pushed (see above).

**New autoloads specifically:** a real autoload-pattern script (e.g.
`GraphicsSettings.gd`) is sometimes **NOT yet registered by name** in
`project.godot`'s `[autoload]` section — per this same gotcha, Brannon adds
new autoloads himself via Project Settings → Autoload in the editor, rather
than the agent hand-editing `project.godot`'s autoload list directly (the
editor owns that section and can silently overwrite hand-edits).

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
As of the July 2026 docs restructure, per-system detail (Power, World Core,
UI — with more systems migrating incrementally as they're touched) lives in
`docs/systems/*/README.md`, NOT in this file. Do not re-add system-specific
status writeups here — they belong in the relevant system's README (add a
`## History` subsection there if genuinely historical detail is worth
keeping). This file stays role/workflow/gotchas only, so it doesn't regrow
to its old ~620-line length.

## Next up (nothing currently in progress — ask Brannon)
See `PROJECT_SUMMARY.md` §1 "Roadmap priorities" for the current list
(Main Menu, Death/game-over state, emergency_light placement, generator
exhaust smoke scaling, remaining graphics-overhaul deferred items). Also 5
systems still pending doc migration (`PROJECT_SUMMARY.md` §2) — migrate
opportunistically per §0's rule, not as a dedicated pass unless asked.
