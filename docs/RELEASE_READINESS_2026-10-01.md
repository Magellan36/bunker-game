# Bunker Game: Early Access release assessment

Assessment date: October 1, 2026 (project-local date). Baseline: `testing`, `ea191d4`. This is an assessment and proposed roadmap, not authorization to implement the backlog. No gameplay code was changed.

**Verdict: not ready for a paid Early Access release.** There is substantial implemented simulation, but the normal player journey, save integrity, progression, audio, and release validation are not yet at the standard of a polished commercial product. Start wrapping up by freezing feature breadth and completing one coherent, tested survival experience.

Do not describe this as “just polish remaining.” Several findings affect whether the advertised game is accessible and whether its consequences survive loading. Equally, do not restart systems that already exist: death/game-over, cooking, NPC work, medical treatment, expeditions, controller navigation, and modernized interfaces have real implementations.

**What this assessment establishes**

Evidence comes from subsystem documentation checked against source, the live editor/game state and a current game screenshot, two release asset gates, the existing medical and expedition tests, and an isolated MainWorld save/load/pause probe. Real saves and the user's live play session were not modified. The probe used temporary XDG data/config directories.

This was not a full campaign playthrough, a hardware benchmark, a listening session, a controller hardware certification, or a Steamworks-account audit. Visual observations apply to the captured live build-mode view, not every scene. Test coverage does not establish that the game is fun or balanced. Storefront, price, promised play length, launch platforms, and support capacity remain product decisions. Steam/PC is the planning assumption below; Windows and Deck requirements are conditional on targeting them.

Status terms: **Verified** means source or runtime evidence; **Risk** means a plausible consequence requiring targeted testing; **Gate** means a proposed release acceptance test. Numeric gates below are recommended project targets, not universal industry rules or measured current performance.

**The commercial standard to aim for**

There is no objective universal “2026 polish score.” A polished small game can have modest content and stylized graphics. It must deliver its advertised loop, communicate consequences, preserve investment, respond consistently, run on its advertised hardware, and feel intentionally finished within its scope.

Early Access can reasonably defer additional scenarios, more equipment, broader research, extra destinations, and expanded storytelling. It should not be used to excuse duplication on load, inaccessible core systems, misleading progression, absent basic feedback, or an untested retail build. Valve explicitly frames Early Access around the value of the currently playable product rather than promises about its future. See [Steam Early Access](https://partner.steamgames.com/doc/store/earlyaccess).

| Area | Assessment | Main remaining work |
|---|---|---|
| New-player colony loop | Release-blocking gap | Accessible initial residents/recruitment; first-session guidance |
| Persistence | Release-blocking defects | Item duplication, safe writes, error handling, migrations and recovery |
| Power/water/building | Substantial implementation | Explain failures, verify cross-system edits and late-run behavior |
| NPCs/social/medical | Substantial implementation | Access through normal play; long-run reliability and balance |
| Farming/cooking/storage | Implemented loops | Resource economy, automation reliability, transfer consistency |
| Expeditions | Functional bounded feature | Normal resident access, economy integration, presentation |
| Progression/run structure | Incomplete product definition | Actual preparation/survival contract and meaningful milestones |
| UI/input/accessibility | Strong foundations, incomplete coverage | Real pause, usable controls/settings, readability and recovery |
| Art/animation | Mixed completion; limited visual sample | Replace remaining placeholders, finish recurring transitions, provenance |
| Audio | Major implementation/content gap | Authored assets, gameplay cues, spatial ambience, mixer/settings |
| Performance/stability | Not signed off | Reference hardware, representative colonies, soak and transition tests |
| Distribution/support | Not signed off | Retail exports, clean installs, storefront accuracy, patch/rollback process |

**1. Complete the game a new customer actually receives — P0**

**Verified:** a fresh MainWorld contained **zero NPCs** after `startup_ready` and 120 additional frames. `MainWorld.tscn` has no resident instances. Reviewed creation paths instantiate residents through developer shortcuts/admin tools, save restoration, or returning expeditions. No normal starting-colony/recruitment path was found. The character-creation flow selects the player body and loads the world.

That means the substantial resident/social/work simulation and resident-based scavenging cannot currently be reached normally from a fresh game through the inspected flow. Developer spawning is not a commercial onboarding path.

Required work:

- Define the minimum launch scenario: starting residents, relationships, supplies, infrastructure, cash, and opening pressures.
- Provide a normal route to those residents. The smallest solution is a deliberate starting group; a complex visitor/recruitment system is optional.
- Ensure initial personalities and skills permit basic survival without a favorable random roll.
- Handle zero remaining residents explicitly: viable solo survival, a clear loss state, or a deliberate recovery route. Do not leave the hatch as a permanently empty interface without explanation.
- Define the pre-/post-apocalypse promise. Project vision describes preparation followed by survival, but no explicit phase-transition controller or shop cutoff was found in the reviewed gameplay source. Either finish that transition and its consequences or launch honestly as an already-collapsed bunker scenario.
- Create a fresh-start route that works without F7, F12, console commands, a prepared developer save, or verbal coaching.

Gate: a stranger can launch the retail build, establish essentials, meet/assign a resident, experience a resource problem, resolve it, send an expedition, save, exit, and continue entirely through normal controls.

Evidence: `scripts/world/core/MainWorld.gd`, `scenes/world/MainWorld.tscn`, `scripts/ui/character_creation/SurvivorScreen.gd`, `scripts/world/hatch/SurfaceHatch.gd`.

**2. Protect player investment — P0**

**Verified runtime defect:** the isolated world had 7 loose pickups. Save slot 1 succeeded; loading it increased pickups to 14; loading it again increased them to 21. Both loads returned success. `_restore_world_items()` spawns saved items without clearing the existing loose population. This is a reproducible integrity failure and an economy exploit, not a cosmetic edge case.

**Verified source defects/omissions:**

- `SaveManager.save_game()` opens the destination directly in WRITE mode. There is no temporary-file/replace transaction or previous-good backup.
- The manager has three numbered slots and no autosave rotation or explicit schema/build version.
- `load_game()` validates that JSON is a dictionary, then invokes setters; it does not validate a complete world snapshot or provide transaction rollback.
- `PauseMenuUI._on_slot_pressed()` ignores save/load return values. It flashes a success message even if saving returned false; it closes the panel after a failed load.
- Skipping unknown/missing keys is useful compatibility behavior, but it is not a migration strategy for changed meanings, renamed resources, or partial snapshots.
- NPC held activity state is intentionally not serialized as a carry state. Loose items are separately captured, so this is not proof that all held items disappear. Cross-container ownership needs an explicit conservation test.

Required work:

- Make load idempotent: loading the same snapshot repeatedly must not change counts, money, progress, or graph connectivity.
- Cover fresh-boot and mid-session loading, consumed starting loot, pregen storage, nested containers, held items, NPC-held items, stove pots, ammunition, corpses, away residents, and moved infrastructure.
- Use stable ownership/identity where needed to prevent one item being restored by two owners.
- Write a temporary snapshot, check write completion, replace safely, retain recovery copies; show actionable disk/full/permission/corruption errors.
- Add rotating autosaves and manual saves with clear overwrite confirmation. Avoid overwriting the only recoverable pre-failure state.
- Add a save schema and supported upgrade policy. Validate before applying; handle missing resources and future-version files clearly.
- Document whether Early Access updates preserve saves. Warn before any genuinely incompatible update.

Gate: 100 automated round trips across representative fixtures with no unexpected item/value/state changes; interrupted writes preserve a usable prior save; corrupted files never silently replace a live world; N−1 release saves load or are explicitly rejected before mutation.

Evidence: `scripts/world/core/SaveManager.gd:109`, `scripts/world/core/MainWorld.gd:503`, `scripts/world/core/MainWorld.gd:525`, `scripts/ui/menus/PauseMenuUI.gd:372`.

**3. Finish the economy and progression contract — P0/P1**

**Verified:** new worlds start with $50,000. Supply-shop prices are described in source as unreviewed placeholders; all six weapons cost $10. A fresh firearm carries six rounds plus twelve reserve rounds. This makes repeatedly buying a fresh gun an obvious balance case to test. These numbers are not automatically wrong, but they are not evidence of a validated survival economy.

Research has one real upgrade resource: water-hookup output, with three completions and a 10-second duration per completion. The UI also draws Purifier Throughput, Reservoir Capacity, and Future Research as static nodes labeled “REQUIRES PRIOR RESEARCH.” Those nodes imply an unlock path that the inspected UI does not implement. Player Skills/NPC Skills tabs are also not evidence of complete research progression; NPC skill simulation elsewhere is a separate feature.

Required work:

- Decide where cash comes from, what remains purchasable, and why scavenging/farming are preferable to shopping when each is intended to matter.
- Build a resource budget for food, clean water, power, fuel, filters, medicine, seeds/soil/fertilizer, salvage, and ammunition. Include acquisition, consumption, storage, waste, and the cost of resident labor.
- Measure the actual cost of one day of survival for solo/small/target-size colonies; compare it with starting reserves and expedition returns.
- Test cheap-stockpile, purchase-and-salvage, refund/undo, gun-repurchase, repeated-load, and maximum-water-upgrade strategies.
- Remove unimplemented research nodes from the launch UI or label them clearly unavailable in this version. Prefer a small complete tree to fake depth.
- Choose launch milestones: first self-sustaining food loop, resilient power/water, successful medical recovery, first dangerous expedition, and a settled functioning home. Add only progression that creates choices between priorities.
- Validate deterioration as pressure with recoveries, rather than an inevitable timer or repetitive chores. The existing generator degradation, water-quality decline, and surface depletion are starting material.

Gate: at least three distinct viable strategies reach the intended midgame; a blind player can explain what changes after the opening hour; an experienced player cannot remove all meaningful decisions with one trivial purchase/upgrade. Establish the intended run length before estimating “enough content.”

Evidence: `scripts/world/core/MainWorld.gd:184`, `scripts/world/build/FarmingShopHelper.gd`, `scripts/ui/research/ResearchStationModernUI.gd:455`, `data/upgrades/bunker_water_output_2x.tres`, `scripts/core/upgrades/WaterOutput2xUpgrade.gd`.

**4. Teach the systems and make failures explainable — P0/P1**

Loading tips, prompts, and rich inspectors exist. I did not find an implemented staged onboarding system in the reviewed boot/world flow. Developer tutorial documents are not an in-game tutorial.

Teach a short sequence through real play: move/camera → pick up/use/store → build → wire/fuel → pipe/purify → assign a job → save → respond to a manageable shortage. Make help skippable, replayable, and available at the point of failure. Protect the opening from untelegraphed lethal scarcity while the player learns.

Every critical failure needs “what happened / why / next useful action.” Distinguish no wire from no generation, no fuel from tripped equipment, no pipe from insufficient allocation, dirty water from no water, no seed from an inaccessible tray, and an unwilling worker from an unreachable task. Use links/highlights to the affected object where practical. Do not require learning graph implementation details.

The notification history is capped at 20 entries and is not registered among world save fields. Individual NPC logs and hatch reports do have persistence mechanisms. For a game about the history of a bunker, decide which major events deserve a durable run record; do not mistake a short transient notification feed for that history.

Gate: in an initial cohort of 10–15 unfamiliar players, target at least 80% completing essential setup without coaching. After their first serious failure, ask them what caused it and how they could respond. Treat recurring wrong answers as UX defects, even when the simulation is technically correct.

Evidence: `scripts/ui/loading/LoadingScreen.gd`, `scripts/ui/notifications/NotificationManager.gd`, `scripts/world/core/MainWorld.gd`.

**5. Make session controls trustworthy — P0/P1**

**Verified:** PauseMenu locks player movement but does not stop simulation. The isolated probe observed elapsed time advance ~1.005 seconds and food decline ~0.0233 during one second with the pause menu open. The UI itself says the bunker keeps running. This is deliberate current behavior; the release concern is that a single-player survival game's “pause” cannot safely be used to step away.

Provide a genuine simulation pause from normal play, including build mode, or explicitly rename the running panel and expose a separate real pause. Test needs, AI, jobs, research, expeditions, medical progression, power, and water together. Define behavior for settings, window focus loss, suspend/resume, and controller disconnect. Do not solve it by stopping only the player clock.

The pause menu has Continue, Save, Load, Settings, and Exit to desktop; it lacks Return to Main Menu. Game-over already has reload/main-menu/quit. Add consistent save/discard/cancel navigation and test repeated new-game/load/menu cycles for stale autoload state. Add a useful cause-of-death/run summary if the present simple death screen does not explain the loss.

Developer F7/F12 and numpad spawn/power shortcuts are not gated by a release/debug check in the inspected MainWorld handler. Remove them from ordinary release input or expose a deliberate sandbox/cheats mode. Single-player cheats are not inherently wrong; accidental developer actions and undisclosed balance bypasses are.

**6. Validate colony autonomy and recurring interactions — P1**

NPCs already have utility scheduling, needs, work, relationships, thoughts, medicine, combat consequences, reservation cleanup, and stuck recovery. Existing simulation harnesses cover multiple scenarios. This deserves credit; “build NPC tasks” is stale roadmap advice.

The release work is reliability under ordinary player chaos:

- Rearrange/demolish a bed, stove, dispenser, shelf, door, generator, or tray during an active job.
- Interrupt carry/use/treatment with player pickup, gifting, snatching, combat, sleep, expedition departure, save/load, and death.
- Test congested layouts and unreachable targets without infinite retries, stolen reservations, or endless teleport recovery.
- Make job priority, refusal, missing supplies, and the cost of keeping more residents understandable.
- Confirm automation reduces repetitive handling, rather than making the player redo or babysit every task.
- Test scarcity, critical needs, recovery after interruption, and prolonged stable operation across multiple seeds/populations.
- Persist identity and lasting consequences; ensure serious losses are communicated beyond a transient toast.

Gate: scenario/seed sweeps with zero unrecovered stuck jobs or ownership violations, followed by real-time unattended colony sessions and human playtests. Test at the chosen maximum supported colony size. Harness success alone does not prove natural behavior.

Medical/exertion's isolated suite passed 60 checks, zero failures. That does not validate all treatment UI, probabilities, pacing, or interactions with the complete colony. Avoid adding more illnesses until players can understand and recover from the existing ones.

**7. Finish building, storage, and infrastructure as daily tools — P1**

Power allocation, breaker zones, batteries, generators, raised wires, water demand, quality blending, purifiers, farming, cooking, storage, move/duplicate/demolish/undo, and item previews are substantial existing systems. Their remaining release gate is composition.

Test complete player operations across all relevant owners: place → connect → operate → move → disconnect/reconnect → undo → save/load → demolish. Include split wire runs, water-hookup relocation, doors, narrow access, elevated connections, container contents, active cooking, growing crops, and insufficient money/materials.

Require clear invalid-placement reasons, honest ghost orientation/footprints, predictable refunds, no invisible connection requirements, and no duplicate value after undo. Verify that costs and destructive consequences are shown before commitment. Any inconsistent E/F/G behavior must either be standardized or made unambiguous in context.

Battery health is explicitly an inactive 100% stub; do not spend a new feature cycle implementing it merely because the UI contains it. Hide the irrelevant field or keep an honest unavailable explanation. Similar “complete or remove from launch presentation” decisions should close the remaining test-device and placeholder surfaces.

**8. Complete sound and recurring visual feedback — P1, required for the requested polish bar**

**Verified asset/source gap:** the project assets tree contains zero WAV/OGG/MP3/FLAC files. Menu music, wind, thunder, UI sounds, and weapon sounds have optional AudioStream hooks; the inspected menu/backdrop/weapon scenes do not assign those streams. This is strong evidence of unfinished audio integration. I did not listen to the live game, and this count does not exclude every possible embedded/generated audio representation.

A minimal launch sound pass should include movement/footsteps; pickup/drop/store; build/invalid/confirm; doors; generator start/run/stop/fault; water/purifier; cooking; critical health/power alerts; expedition return; weapon actions; and restrained bunker/surface ambience. Give important cues distinct meanings. Add distance/occlusion or attenuation where appropriate, variation for repetitive events, and avoid alarm fatigue.

Add master/effects/ambience/music controls, persistence, sensible defaults, and mute-on-focus-loss behavior if offered. No expensive orchestral soundtrack or voice acting is required. Important information must also be available visually.

The captured live view has a coherent concrete/industrial direction and restrained UI. It also has a very large low-information floor area, a small low-contrast player silhouette, tiny toolbar labels at the captured zoom, and resident presentation that merits animation/state review. These are visual observations, not proven bugs: the captured session was in build mode, not a pristine new game, and screenshots cannot establish animation quality. Verify at native resolution and all camera distances before prescribing an art redesign.

Prioritize object recognition and state changes: healthy/broken/off/on, clean/dirty/empty/full, placement validity, held-item visibility, collision grounding, and camera occlusion. Complete the frequently seen transitions—sit/stand/sleep, work/use, carry/drop, climb/depart/return, hit/death, weapon attack/reload. The hatch currently uses instant departure and a procedural placeholder per its subsystem documentation. A brief intentional transition is sufficient; a cinematic system is unnecessary.

**9. Close the art/provenance release gate — P0/P1**

The UI placeholder gate passes: **0 tracked development placeholders**. This is not proof that all artwork is final or compliant with the project's zero-AI-art policy; its scope is the tracked manifest.

The menu backdrop release gate fails: **21 filled slots, 2 greybox slots** (`LeaningPole`, `WreckedCar`), plus incomplete author/source/license entries for `ruin_malik_facade.glb`, `shack_low.glb`, and six Destroyed City asset paths (road slab, rocks, debris, columns 1/2/3). Repeated findings across composed scenes refer to the same underlying assets.

Replace or intentionally remove unused greybox slots; acquire and document proper final assets. Resolve provenance from actual source records, rather than filling unknown fields with assumptions. Audit the complete shipped art/font/audio set, not just menu scenes. Existing weapon documentation also identifies unfinished models/effects/animation/audio; inspect actual current assets before assigning replacement tickets because this area is actively changing.

Gate: both existing release scripts pass, every shipped third-party asset has a traceable source/license and required credit, and a human final-content review confirms the project's zero-AI-art rule. Adding sound must include its provenance.

**10. Finish controls, readability, and accessibility — P1**

The game already supports controller navigation, device switching, contextual prompts, compact inspectors, and reduced UI motion. Older controller docs contain obsolete gaps: Select/Tab now opens Status, and the active simplified character-creation screen does not have the old name field. Do not recreate retired customization or an unnecessary keyboard flow to satisfy stale notes.

I found no general player-facing rebinding or audio settings in the inspected settings implementation. Complete configurable keyboard/mouse actions and accurate rebound prompts, controller sensitivity/deadzones where needed, understandable hold/toggle behavior, and conflict/reset handling. Avoid hardcoded keys leaking into help after remapping.

Test the entire supported input journey, not just movement: all menus, build tools, sliders/dropdowns, inventory/container transfers, treatment, research, expedition selection, save/load, and game-over. Test hotplug/disconnect and switching between input devices. Require visible focus and reliable back/cancel behavior without simultaneous world actions.

Check 720p/800p, 1080p, 1440p, ultrawide, window resizing, and high-DPI text. Include long labels and large numbers. Provide readable UI scaling; render scaling is not UI scaling. Do not encode critical state by color alone. Verify reduced motion covers disruptive camera/world effects where appropriate; provide control over shake, flashing, blur, and other comfort-sensitive presentation.

English-only EA is a valid scope if disclosed; multiple languages and a full localization campaign need not block it. Leave room for longer strings and future localization. Voice acting and screen-reader support are product-scope choices, not automatically mandatory deliverables.

If claiming Deck/full-controller compatibility, treat it as a separate tested promise. Valve's criteria include complete controller access, readable text, suitable display settings, and controller-accessible text entry where required. See [Steam hardware compatibility review](https://partner.steamgames.com/doc/steamhardware/compat) and [Valve's recommendations](https://partner.steamgames.com/doc/steamhardware/recommendations).

**11. Establish performance and stability evidence — P0/P1**

Do not infer performance from the existence of low/medium/high presets, optimization commits, or one live screenshot. No representative frame-time/hardware matrix was measured in this assessment.

Define minimum/recommended hardware and a supported colony/layout envelope. Record cold start, new world, established colony, overloaded grid, dense plumbing/storage/farming, many residents, mass alerts, building edits, save/load, and menu transitions. Measure CPU/GPU frame time, 1% lows or high-percentile frame times, RAM/VRAM, loading duration, save hitches, and allocation trends. Use exported release builds.

Suggested desktop target: stable 60 fps at the chosen recommended 1080p preset, with p99 frame time below 33 ms outside disclosed loading operations. If supporting weaker hardware/Deck, define and measure an explicit 30/40 fps tier. These are proposed acceptance budgets, not measurements of this build.

Run several-hour soak tests; repeat load/menu/new-game cycles; compare memory after warmup. Exercise Alt-Tab, resolution changes, display/renderer preference restart, device disconnect, disk failures, and suspend/resume. Triage engine warnings by customer impact. Do not dismiss all headless leak errors as harmless, but do not equate them automatically with a live memory leak either.

Validation findings: the standard `tools/godot_check.sh` stopped at import because its error detector found errors. Sandbox socket failures were removed by an unrestricted rerun; shutdown resource/RID/PagedAllocator errors remained. Thus the complete import/boot/world/migration gate did **not** pass. The observed failure is distinct from a gameplay parse error. Resolve or explicitly isolate tooling shutdown noise and obtain a genuinely trustworthy release gate; do not simply remove the error detector.

**12. Produce a retail build and supportable release — P0/P1**

Only a Linux export preset is present in the inspected file. If Windows is a target, create and test its retail pipeline. macOS, consoles, and Deck certification can be deferred if not promised. A Linux development session does not certify Windows, Proton, or an exported Linux build.

Build from a known commit with a pinned engine/toolchain and correct resource imports. Inspect the actual package for required dynamically loaded resources and credits, plus unwanted development material. The Godot AI addon has an export plugin intended to strip its runtime helper; verify that behavior in the actual package rather than reporting the helper's editor autoload as a confirmed shipped defect.

Run clean-machine install → first launch → play → save → exit → relaunch → update → load. Verify no dependency on editor caches, untracked files, vendor source folders, or machine-specific paths. Maintain release build/version identifiers in bug reports.

For Steam, prepare accurate current-state description, screenshots/trailer of real launch gameplay, capsules, supported languages/input/platforms, system requirements, content survey, Early Access Q&A, and a support route. Steamworks configuration and existing marketing work were not inspected, so these are unverified deliverables rather than claims that none exists. Store/build review tests basic functionality and presentation accuracy; it does not certify polish. See [Steam review process](https://partner.steamgames.com/doc/store/review_process).

Cloud saves are valuable but not automatic: decide scope and validate conflict/recovery behavior before advertising support. Achievements are optional. Have a reproducible build, rollback procedure, hotfix path, known-issues page, save-compatibility policy, bug-report template with logs/build ID, and realistic update commitments before charging customers. Early Access begins a support obligation; it does not conclude all development.

**Proposed release sequence**

| Milestone | Work to close | Exit evidence | Dependency |
|---|---|---|---|
| M0: freeze the product | Define launch scenario, platforms, audience, run/value target, scope cuts; reconcile stale overview | One agreed launch contract and finite blocker list | First |
| M1: complete a normal run | Starting colony/access, phase/shop rules, guidance, real pause/session flow; repair saves and errors | Fresh customer journey completed without cheats; conservation/recovery tests pass | M0 |
| M2: make survival hold together | Economy, research honesty, meaningful milestones, automation reliability, death/recovery, long-run pressure | Seeded scenario tests plus unfamiliar-player runs reaching midgame | M1; save integrity before balance signoff |
| M3: finish the presentation | Audio, interaction/animation feedback, remaining art/provenance, input/accessibility/readability | Native-resolution visual/input/audio checklist; asset gates pass | Content/controls sufficiently stable |
| M4: qualify the product | Platform exports, performance budgets, soaks, clean installs, old-save migration, package checks | All supported configurations pass release matrix; no unresolved critical defects | M1–M3 |
| M5: closed playtest and release candidate | Blind-user sessions, long runs, store/build review, support/rollback drill | Repeated external playtests pass; final build/store claims match | M4 |

Art procurement and storefront preparation can proceed alongside engineering. Do not sign off balance before fixing duplication or tune all onboarding before settling the launch scenario. Do not add a new subsystem during M3–M5 unless it removes a documented release blocker.

**Backlog ready to turn into tasks**

| ID | Priority | Deliverable | Acceptance criterion |
|---|---|---|---|
| R01 | P0 | Launch scenario/phase contract | Normal starting population, supplies, economy and phase rules specified |
| R02 | P0 | Resident access | Fresh game reaches jobs/social/expeditions without admin commands |
| R03 | P0 | Idempotent load | Repeated loads preserve identical expected inventory/world state |
| R04 | P0 | Save safety/recovery | Interrupted write retains previous good save; user sees truthful result |
| R05 | P0 | Snapshot validation/migration | Corrupt/incompatible saves cannot partially mutate a live run |
| R06 | P0 | Real pause and safe session navigation | All simulation stops when requested; leave/reload/menu paths are reliable |
| R07 | P0 | Honest progression UI | Every displayed unlock works or is explicitly absent from this version |
| R08 | P0 | Provenance completion | Release gates and complete shipped-asset ledger pass |
| R09 | P0 | Trustworthy build gate | Import, boot, world and migration checks produce reviewed clean results |
| R10 | P0 | Supported-platform retail builds | Clean-machine install/play/save/update cycle passes |
| R11 | P1 | Staged onboarding/help | Blind testers meet setup targets without coaching |
| R12 | P1 | Survival economy pass | Day/resource budgets and multiple viable strategies demonstrated |
| R13 | P1 | Meaningful launch progression | Opening/midgame/pressure milestones supported by real play |
| R14 | P1 | Colony regression/soak suite | No unrecovered job/reservation/ownership failures in agreed matrix |
| R15 | P1 | Construction/network lifecycle suite | Place/move/undo/load/demolish conserve value and connectivity |
| R16 | P1 | Container/cooking/farming transfer audit | No lost/duplicated items or unexplained targeting behavior |
| R17 | P1 | Failure diagnostics and durable key events | Players can explain major losses and find useful next actions |
| R18 | P1 | Complete launch sound pass | Core actions/state changes have mixed, configurable authored feedback |
| R19 | P1 | Final recurring visuals/animations | Reviewed identity, grounding, state readability and common transitions |
| R20 | P1 | Input/settings/accessibility pass | All advertised actions accessible; focus, remapping, scaling, comfort checked |
| R21 | P1 | Performance qualification | Agreed frame-time/memory/loading budgets met in representative colonies |
| R22 | P1 | Release-only input/package audit | Developer actions intentional; required resources/credits present |
| R23 | P1 | Store/support readiness | Accurate promises, bug-report path, rollback and compatibility policy |
| R24 | P1 | External acceptance cohort | Fresh users and long-run testers pass journey and reliability gates |

P0 means a hard correctness, access, trust, or distribution blocker. P1 means required for the requested high-polish launch unless explicitly cut from the advertised product; it does not mean “safe to ignore.” Scope decisions should remove features cleanly rather than leave misleading stubs.

**Defer by default**

Additional medical conditions, a larger weapon arsenal, raids, multiplayer, elaborate diplomacy, surface exploration, complex visitor events, two-person expedition teams, more destination types, deep skill trees, battery degradation, realistic fluid transit, exhaustive decor, voice acting, mod support, and achievements. Add any of these only if external playtesting shows the current scoped loop lacks an essential decision. More content will not compensate for inaccessible residents, unsafe saves, opaque failure, or absent feedback.

**How to schedule this honestly**

Do not assign a percentage complete or a launch date from this audit. Completion time depends heavily on the selected scenario, required asset work, launch platforms, and external test results. First close M0 and reproduce/size R02–R06 with the subsystem owners; use that throughput to estimate the rest. Separate engineering work, art/audio acquisition, and playtest/calendar lead time. The critical path is normal player access → trustworthy saves → economy/onboarding validation → complete presentation → exported-build qualification → external acceptance.

For launch approval, require: zero known save-corruption/duplication/access blockers; all required assets and commercial provenance complete; ordinary controls and true pause working; representative exported builds passing the platform/performance matrix; and external players able to enjoy the current product without developer intervention. A suggested final confidence sample is at least 100 aggregate external player-hours, including several full intended runs, with zero observed crash/data-loss/softlock incidents. This is a practical signoff target, not a statistical guarantee.

**Verification record and reproduction**

- `python3 tools/tests/check_ui_placeholders.py --release`: PASS, 0 tracked development placeholders.
- `python3 tools/tests/check_menu_backdrop_slots.py --release`: FAIL, two greybox slots and incomplete provenance as detailed above.
- `tools/tests/expedition_resolver_smoke.gd`: PASS. Includes deterministic rules, risk/haul comparisons, depletion, discovery, eligibility, and loyalty outcomes.
- `python3 tools/tests/run_medical.py --godot <Godot 4.7.2 binary>` outside the socket-restricted sandbox: PASS, 60 checks, 0 failures. Initial sandbox attempt stopped on socket errors before gameplay assertions.
- `bash tools/godot_check.sh <Godot 4.7.2 binary>`: FAIL at import/shutdown, including resource/RID/PagedAllocator errors on the unrestricted rerun; later phases not certified.
- Isolated MainWorld probe: `new_game_npcs=0`, `save_ok=true`, `load_ok=true`, loose pickups `7 → 14 → 21`; time and food continue changing with pause open.
- Live game log sample had no reported gameplay errors; editor log included tooling parse errors/warnings. Neither sample is a clean-session certification.
- Live screenshot obtained at 1920×1080, viewed resized to 1100×618; no full visual or audio signoff performed.

Reproduce the item issue in a disposable user-data directory: instantiate MainWorld, await `startup_ready`, let deferred startup finish, count `pickup` group nodes, save slot 1, load it, allow deferred operations to settle, recount, load again, recount. Do not use real saves. Expected release behavior: the counts and serialized contents match the saved snapshot after each load. Probe/log files from this assessment are under `/tmp/bunker-release-*`; they are transient evidence, not shipped resources.

The existing high-level summaries are materially stale: they list death/game-over and several already-built systems as future work, and older UI/controller notes describe retired flows. Use this audit's source-verified findings and acceptance gates as the roadmap baseline; reconcile those overview documents as a planning task, not as a reason to rebuild working features.
