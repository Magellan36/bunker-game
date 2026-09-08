# GPT-HANDOFF

Use this as the starting brief for a new engineering chat. This handoff is for gameplay, simulation, content, tools, persistence, and world systems. The UI consistency pass is already established and should be treated as a protected dependency.

## Repository and branch state

- Repository: <https://github.com/Magellan36/bunker-game>
- Engine: **Godot 4.7.2**. Do not test or judge compatibility as a Godot 4.6 project.
- Active integration branch: `testing`
- Current `testing` checkpoint when this document was written: `07e04a5517634d66e5a3e01c6c77c8619cb7d367`
- `main` was intentionally held at `038ae2981179177a417118af46f2f8b6609250cf` through the UI consistency work. Do not promote additional changes into it without explicit approval.
- Never force-push.
- Start every task by fetching the remote and making a **clean checkout from `testing`**. Do not reuse an old dirty worktree, stale archive, or historical ZIP.
- Commit validated increments and push them directly to `testing` so completed work is never dependent on temporary workspace persistence.

## What the game is

Bunker Game is an isometric bunker survival and management game. Its systems are meant to create understandable physical cause and effect: players construct a bunker, route utilities, store and consume real items, manage people and needs, and deal with failures. It should feel like a game first and a readable simulation second. Prefer interactions the player can see in the world over abstract spreadsheets or invisible bookkeeping.

The broad loop has a preparation/build phase and a survival phase. Power, water, storage, farming, research, medical needs, NPC behavior, jobs, inventory, construction, and environmental systems are interconnected. A local change can therefore affect navigation, utility registration, save order, physical item identity, or another system's solver.

## First things to read

Before editing a subsystem, read its documentation under `docs/systems/<system>/README.md`. These files define ownership, public APIs, persistence, known limitations, and forbidden cross-system responsibilities. Open only the source files relevant to the function being changed, then update the documentation if the implementation or contract changes.

Useful entry points include:

- `docs/systems/world-core/README.md` — bootstrap, cross-system wiring, cash, world reconstruction, and save/load phases.
- `docs/systems/build/README.md` — placement, ghosts, footprints, moving, duplication, demolition, digging, undo, and build tools.
- `docs/systems/power/README.md` and `PowerManager.md` — electrical graph, registry, solver, zones, generators, batteries, breakers, and load shedding.
- `docs/systems/water/README.md` — pipe graph, allocation solver, quality, purification, storage, and consuming devices.
- `docs/systems/player/README.md` — movement, interaction, inventory, needs, and player-owned state.
- `docs/systems/npc/README.md` — utility AI, navigation, needs, jobs, item use, relationships, and persistence.
- `docs/systems/farming/README.md`, `research/README.md`, `medical/README.md`, `environment/README.md`, `furniture-items/README.md`, and `structure/README.md` for their respective domains.
- `docs/AGENT_TOOLS_GUIDE.md` before work involving Godot editor automation, Blender, models, scenes, or textures.
- `docs/ui/CONSISTENCY_PASS.md` before any task that has a visible UI consequence.

## Architecture and ownership rules

Respect the existing source of truth. Extend it instead of creating a parallel manager, duplicate state, or second implementation.

- `MainWorld.gd` bootstraps and connects systems. It should not absorb their internal simulation logic.
- `SaveManager` is the generic field registry. Load is phase ordered because world geometry and placed objects must exist before dependent links can be restored. Any persistence change must preserve that reconstruction order and remain safe for older or missing fields.
- `BuildModeController` owns placement and the placed-object registry. Once a placed device is live, its domain manager owns its behavior.
- `PowerManager`, `PowerGraph`, `PowerRegistry`, and `PowerSolver` collectively own electrical truth. Other systems register devices and consume public state; they do not reproduce the solver.
- `WaterManager`, `WaterGraph`, and `WaterSolver` own plumbing connectivity, demand allocation, and water-system truth.
- Farming deliberately has no central manager. Each tray and grow light participates through the existing water and power contracts.
- NPCs use real navigation, physical world objects, shared items, and the `JobBoard`; avoid shortcuts that create a separate NPC-only version of the world economy.
- Gameplay state, purchasing, treatments, jobs, saves, and simulation logic stay out of presentation helpers. UI reads authoritative state and invokes domain APIs.
- Use `NotificationManager` for player-facing notices. Do not revive or introduce a competing notification path.
- Avoid adding autoloads unless the architecture truly requires global lifetime. Check `project.godot` and the subsystem docs before changing autoload registration.

## High-risk integration details

- **Physical identity matters.** Storage slots, placed objects, carried items, shelf links, graph nodes, and NPC claims often point to real instances. Do not replace them with display-only copies or recreate them casually.
- **Registration order matters.** Placed utility devices register with their managers; build, move, duplicate, demolish, save, and load flows must unregister and restore them correctly.
- **Graph rebuilds are specialized.** The automatic wire perimeter uses incremental diffing and breaker-aware routing. Water and power have separate topology rules. Do not replace either with a blanket teardown/rebuild without proving the need.
- **Simulation time is compressed.** Several systems tick by game time rather than wall-clock time. Follow the owning system's clock and pause/save conventions.
- **Navigation is dynamic.** Digging, construction, movable clutter, chairs/beds, and NPC jobs can affect runtime navmesh behavior and occupancy.
- **Known gaps may be intentional.** A documented stub, inactive field, placeholder behavior, or deferred feature is not permission to invent gameplay. Confirm design decisions that change balance, economy, player rules, or established behavior.

## Product and content constraints

- Preserve existing functionality and the identity of each system. Ask before making a meaningful gameplay redesign, balance change, economy change, or destructive data-model change.
- The completed UI consistency work is a polish baseline. Reuse its shared components, tokens, focus behavior, formatting helpers, lifecycle rules, and input-aware hints when a system needs presentation. Do not regress controller navigation, cursor ownership, compact layouts, scrolling, or panel identity.
- Build mode, Shop, Storage, character creation, ordinary device inspectors, inventory HUD, needs gauge, medical/status rings, and NPC debug labels each have deliberate behavior documented in the UI consistency specification.
- Controller input has intentional divisions: player movement and menu navigation are separate, while Build mode has a deliberate right-stick virtual-pointer exception. Consult the current input helpers before binding new actions.
- Temporary icons/models/assets may remain clearly replaceable placeholders. The release target is **zero AI-generated assets**; use original or appropriately licensed replacements and record provenance where applicable.

## Safe workflow for any task

1. Fetch and verify `testing`, `main`, and the clean working tree.
2. Read the relevant subsystem README and trace the runtime owner from scene/bootstrap/autoload wiring.
3. Reproduce the current behavior before editing. Identify adjacent systems, signals, registration calls, persistence fields, and input paths.
4. Make the smallest coherent change through the owner's public API. Avoid broad rewrites during a targeted fix.
5. Add or update tests only where they verify a meaningful contract or regression.
6. Run Godot **4.7.2** parse/import checks and the relevant targeted smoke/contract tests in `tools/tests`.
7. When a change is spatial, visual, physics-sensitive, or controller-sensitive, also verify it in the real editor/game at representative resolutions and input modes. Headless success alone is insufficient for those behaviors.
8. Separate failures from the C# MCP/editor bridge from actual GDScript, import, scene, or gameplay failures.
9. Update the subsystem README when ownership, API, persistence, behavior, tests, or known gaps changed.
10. Review the diff for unrelated edits, commit the validated checkpoint, push to `testing`, and report the exact commit ID and tests. Leave `main` untouched unless the user explicitly requests a promotion or main-only documentation change.

## Definition of done

A change is complete when the intended in-game behavior works, adjacent systems still receive the same valid state, save/load and instance relationships remain sound where relevant, Godot 4.7.2 validation passes, subsystem documentation reflects the result, and the commit is safely pushed to `testing`. Report limitations honestly; do not hide editor/tooling failures or present untested visual behavior as verified.

## Opening instruction for the new agent

> Work from the latest remote `testing` branch and keep `main` untouched unless I explicitly authorize it. First read the README for the subsystem involved, plus `docs/systems/world-core/README.md` when the change crosses systems or affects persistence. Preserve the current UI consistency baseline and all existing behavior outside the requested scope. Trace the authoritative runtime owner, implement through existing APIs, validate in Godot 4.7.2, update the relevant subsystem documentation, then commit and push each validated checkpoint to `testing` without force-pushing. If the request would materially change gameplay rules, balance, economy, or an established design contract, investigate first and ask me before making that design change.
