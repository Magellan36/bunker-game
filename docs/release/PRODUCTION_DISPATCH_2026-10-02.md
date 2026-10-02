# Production dispatch — October 2, 2026

User-authorized work, delegated to three `gpt-6-astra` agents with `medium` reasoning. All work uses the direct shared checkout on `testing`. The parent agent coordinates boundaries, reviews evidence, serializes commits, and maintains the release picture. The October 1 assessment is historical evidence: current HEAD at dispatch, `f05f586`, already includes survivor selection and preparation/apocalypse changes.

**Shared execution contract**

- Read `AGENTS.md`, `docs/AGENT_GIT_WORKFLOW.md` before git, `AI_CONTEXT.md`, and the relevant subsystem documentation. Reverify current source before assuming any audit finding still applies.
- Work directly on owned files, preserving other agents' changes. No branch switching, stash, reset, clean, broad staging, or worktree. Request a parent commit slot before touching the shared git index; commit explicit paths and push `testing`.
- Use relevant available tools, including Godot inspection and shell test tooling. Discover capabilities rather than assuming they are unavailable. Follow `docs/AGENT_TOOLS_GUIDE.md`, while recognizing that current tool documentation may supersede its historical limitations.
- Never manipulate or stop the user's running game/editor. Isolate all tests from real saves using temporary XDG data/config/cache directories. Coordinate expensive runs and shared imports; benchmark timing gets an exclusive window among these agents.
- Before edits, report intended files and approach. Stop the affected change and contact the parent for ownership conflicts, ambiguous destructive cleanup, unexpected subsystem crossings, save-format policy changes, or intrusive instrumentation. Continue independent safe work while waiting. Routine authorized changes do not require repeated approval.
- Report source-only findings separately from reproduced defects. Do not fabricate hardware measurements or claim tests passed when tooling blocked them. No unrelated refactors or new features.

**Agent 1: save integrity and coverage**

Prompt: Fix the reproduced loose-item duplication on save loading. The original probe observed pickup counts `7 → 14 → 21` after loading the same snapshot twice. Inspect current implementation first. Cover fresh-world and mid-session loading, consumed starting loot, direct-held items, nested containers, inventories, stove contents, and NPC ownership. Preserve item contents and prevent double ownership. Do not redesign the save schema.

Make save/load messages truthful: check return values, show an actionable failure, retain the panel after failure, and never display success when saving failed. Preserve the existing UI language, navigation, and layout.

Protect the previous save through checked temporary writes, safe replacement, and a recoverable previous-good backup. Failure at any step must preserve usable prior data. Do not replace a good backup with a corrupt primary. Preserve numbered slots and existing public APIs; add only minimal diagnostics needed by the UI. Autosave design and broad schema migrations are out of scope.

Produce `SAVE_STATE_COVERAGE.md`: a matrix of floor items, containers, inventories, held items, NPCs, expeditions, infrastructure, world changes, and new run-phase state. Trace persistence ownership, phases, defaults, missing state, and duplicate serialization risks. Distinguish tested behavior from source inspection. Outside the three requested fixes, audit and flag omissions instead of rewriting persistence.

Expected ownership: `SaveManager.gd`, necessary save functions in `MainWorld.gd`, narrow save/load-result handling in `PauseMenuUI.gd`, focused save regression tests, and `docs/release/SAVE_STATE_COVERAGE.md`. Coordinate owned-file conflicts before editing.

Acceptance: repeated loading preserves expected item counts and contents; new-game/preparation/survival state remains compatible; failed writes preserve usable saves/backups; failed operations never report success; meaningful regression/failure tests pass. Report unresolved coverage separately from the fixes.

**Agent 2: input-access audit**

Prompt: Audit every currently advertised gameplay action and its controller/keyboard/mouse path. Cover boot, survivor selection, preparation/apocalypse transition, movement/camera, carrying/inventory/storage, building/wires/pipes, device panels, resident jobs/dialogue, treatment, research, expeditions, settings, save/load/pause, and game-over.

Produce `docs/release/INPUT_ACCESS_AUDIT.md` with action/surface, advertised binding, controller path, hardcoded event versus InputMap, prompt consistency, focus/back/popup behavior, evidence path and line, reproducible defect, severity, owning subsystem, and bounded fix/acceptance test. Separate functional hardcoding from missing controller access and from unverified behavior. Recheck stale controller notes: current status/Select support and simplified character creation differ from older documentation.

Do not implement UI/input changes. Deliver a concrete handoff for the UI owner. Do not inject input into the user's current session; use isolated sessions if dynamic verification is necessary. Recheck any overlapping save-menu claims once Agent 1's changes land.

Ownership: the audit report only, plus an isolated audit harness if justified and approved by the parent. Acceptance: actionable, evidence-backed defects and an honest coverage/limitations matrix, not a speculative wish list.

**Agent 3: performance baseline**

Prompt: Establish a reproducible baseline before optimizing. Inspect existing profiling/capture tooling, then propose bounded representative fixtures: cold/warm boot and menu-to-world loading, fresh bunker, small and established colony, dense devices/storage/farming/networks, construction/network edits, save/load, and repeated transitions with a short memory trend. State preparation versus survival phase and direct-world versus normal new-game route explicitly.

Record hardware, OS, engine, source revision/dirty state, renderer, resolution, quality, VSync/frame cap, fixture counts, warmup, sample length, median/p95/p99 frame time or precisely defined 1% low, CPU/GPU timing when available, process RAM/VRAM when available, loading durations, and save/load hitches. Preserve raw machine-readable evidence and run commands.

Use an independent session and temporary userdata. Do not control the user's existing game or add shipping-code instrumentation. Request an exclusive measurement window after save work stabilizes. Record external workload you cannot control; do not call a headless run a rendered-FPS benchmark or a short sample proof of a leak. If a metric or hardware path is inaccessible, say so and provide the useful measurements that are available. No optimization or settings changes to the production game.

Expected ownership: `tools/performance/baseline.gd`, `tools/performance/run_baseline.py`, `docs/release/PERFORMANCE_BASELINE.md`, and compact evidence under `docs/release/performance/`. Avoid large noisy logs where a summarized result and raw timing samples suffice.

Acceptance: reproducible scenarios with measured results, explicit limitations, and specific justified follow-up investigations. No invented minimum hardware specification or performance guarantee.

**Coordination and review**

The save agent may implement while the other agents inspect source and prepare reports/harnesses. Performance timing begins after save changes and heavy regression runs settle. Shared index operations are serialized. The parent reviews save ownership/failure semantics, checks audit conclusions against current code, and assesses benchmark validity before treating results as production evidence. User decisions are requested only for concrete scope/behavior conflicts that cannot be safely resolved within these assignments.

These agents are subtasks of the production-guidance conversation, not autonomous permanent monitors. Further release work will be prioritized from their results and the existing readiness roadmap.
