# NPC System (Aug 2026)

**Read this before opening any `scripts/npc/`, `scripts/ui/npc/`, or
`scenes/npc/` file.** Only open the actual source for the specific
function you're changing — this doc should tell you which one that is.

---

## Purpose

Full NPC survivor system: NPCs spawn into the bunker, path around it using
real navmesh-based pathfinding (including dynamic obstacle avoidance for
movable clutter), have needs (Energy/Hunger/Thirst/Health/Mood) that decay
and produce real consequences (slower movement, forgetfulness, job
avoidance, forced collapse), work a small set of real jobs (harvest,
replace purifier filter, refuel generator), eat/drink/rest using the same
world objects and physics the player uses, have a fixed random personality
that shapes how they react to bad conditions, and can be talked to and
directly commanded by the player. Persists through save/load.

---

## Responsibilities

- **`NPC.gd`** (`scripts/npc/`) — the NPC itself: navigation primitives,
  needs/health/mood/irritability state and their tick loops, personality
  generation, movement-lock/stuck-recovery, physics push-through for loose
  items, all status/consequence helper functions, dialogue line selection,
  Talk interaction.
- **`NPCBrain.gd`** (`scripts/npc/`) — the Utility-AI decision loop and
  every `NPCActivity` subclass: `WanderActivity`, `SitActivity`,
  `LieActivity`, `DrinkActivity`, `EatActivity`, `JobActivity`,
  `ForgetfulWanderActivity`, `PassedOutActivity`, `CommandRestActivity`,
  `CommandHarvestActivity`.
- **`NPCItemUser.gd`** (`scripts/npc/`) — shared item-interaction helpers:
  find/claim/grab loose or shelved items, XZ-only proximity checks
  (`flat_distance`), consumable filters.
- **`BunkerNavMesh.gd`** (`scripts/npc/`) — runtime-baked `NavigationMesh`
  parsed from the real physics world (static colliders), rebaked on
  dig/build changes.
- **`JobBoard.gd`** (`scripts/npc/`, autoload) — poll-based job posting for
  HARVEST / REPLACE_FILTER / REFUEL, with claim/release.
- **`NPCDebug.gd`** (`scripts/npc/`) — centralized, toggleable debug
  logging (F7 "Toggle NPC Debug Logging") and the full-state dump (F7
  "Print NPC Debug State").
- **`NPCTalkMenuUI.gd`** (`scripts/ui/npc/`) — the E-panel: live
  Health/Energy/Hunger/Thirst/Mood bars, Status line, Skills, Personality,
  Talk → dialogue + command buttons, Close.
- **`NPC.tscn`** (`scenes/npc/`) — `CharacterBody3D`, capsule mesh/collision
  (radius 0.4, matches `BunkerNavMesh`'s `agent_radius`).
- **`PickupableItem.gd`** (`scripts/world/items/`) — heavy items
  (mass ≥ 3.0) get an auto-sized `NavigationObstacle3D` child so NPCs route
  around them dynamically; toggled off while held.
- **`Chair.gd` / `Bed.gd`** (`scripts/world/furniture/`) — additive NPC
  occupancy API (`npc_try_sit`/`npc_try_lie`, `is_seat_free`/`is_bed_free`,
  seat/lie transforms) alongside the untouched player flow.
- **`MainWorld.gd`** (`scripts/world/core/`) — cleared-cell accessors for
  navmesh baking/wander targets; phase-4 `SaveManager` field for NPC
  persistence.
- **`AdminMenu.gd`** (`scripts/ui/menus/`) — full NPC test-tooling section
  (spawn, per-need adjusters, skill randomize, despawn-all, force-rebake,
  debug toggle/dump).

---

## Key Systems

### Navigation
`BunkerNavMesh` bakes from the **real physics world** —
`NavigationServer3D.parse_source_geometry_data` walks the scene and picks
up every static collider on mask bit 1 (floor tiles at their true height,
walls/pillars/furniture/devices at their true footprints), plus a safety-
net floor (cleared-cell quads at the correct floor height, y=0.5) as a
belt-and-suspenders fallback. RigidBody3D items and CharacterBody3D
(player/NPCs) are excluded automatically. Rebakes are debounced and async,
triggered by dig/restore signals and a placed-object fingerprint poll.

`NPCAgent` (`NavigationAgent3D` on each NPC) uses `path_desired_distance`/
`target_desired_distance = 1.1` — not the more obvious ~0.5 — because path
points sit on the floor (y≈0.5) while the NPC's own origin is its capsule
CENTER (y≈1.4), a ~0.9 constant vertical offset that a tighter threshold
could never satisfy. `set_nav_target()` snaps targets to y=0.5 to keep
that offset consistent.

Real-time dynamic avoidance (not just static navmesh) is enabled via
`avoidance_enabled = true` + the `velocity_computed` signal — `nav_steer()`
submits a *preferred* velocity, Godot returns a locally-adjusted *safe*
velocity accounting for every nearby `NavigationObstacle3D` (heavy loose
items) and other NPC agents, and that's what actually gets applied.

### Physics Clutter (Push-Through / Avoidance / Resistance)
Loose items are `RigidBody3D` and were never part of the navmesh (only
static colliders are parsed). Tier is read from the item's own `mass`:
- **Light** (mass < 3.0 — cans, bottles, produce, filters, fuel cans):
  `NPC._handle_physics_pushes()` shoves them aside and corrects the NPC's
  blocked motion back — walking through barely registers.
- **Heavy** (mass ≥ 3.0 — crates, baskets, cooking pots, water/can cases):
  get a `NavigationObstacle3D` child (`PickupableItem.gd`, auto-sized from
  the item's actual collision geometry via `Shape3D.get_debug_mesh()`,
  toggled off while held) — NPCs route around their *current* position
  proactively via real-time avoidance, not a reactive post-collision hack.
  A small residual shove still applies if one is ever grazed anyway.

### Needs, Health, Status Consequences
Five NPC-side stats, all 0–100: `energy`, `hunger`, `thirst`, `health`,
`mood` (+ `irritability`, 0–100%, tracked separately — see Personality
below). Energy/Hunger/Thirst drain on the shared compressed game-clock
(`NPC.game_hours()`), matching `PlayerStats`' own rates exactly
(`HUNGER_DRAIN_PER_GAME_HOUR = 1.39`, `THIRST_DRAIN_PER_GAME_HOUR = 2.08`).

**Health** drains only while Hunger OR Thirst sits at literal 0 (not
25%/50%) — both zeroed simultaneously stacks the drain. Health = 0 has no
further consequence yet (`FUTURE WORK`, same as the Crisis Response note
below).

**Speed** (`NPC.get_status_speed_multiplier()`): Energy contributes ONE
progressive tier (25% tier *replaces* the 50% tier's penalty, doesn't
stack with it); Hunger/Thirst/Mood each contribute their own small,
independent multiplier below their own threshold — all multiply together,
so several low at once compounds (explicit design requirement).

**Forgetfulness** (`NPC.get_forgetfulness_chance()`): a chance, rolled by
`NPCBrain._think()` only at the exact moment a `JobActivity` would
otherwise be picked, to instead force a **20-second, non-interruptible**
`ForgetfulWanderActivity` detour. Hunger, Thirst, Mood, and (mildly) Energy
each contribute a tiered chance value; **averaged**, not OR-combined
(Part 21 — OR-combination made moderate sources compound too aggressively;
averaging is the deliberately gentler curve), then scaled by the
Resilience personality trait.

**Pass-out** (`is_passed_out()` = `energy <= 0`): checked every physics
frame ahead of everything else in `NPCBrain.tick()`, force-starts
`PassedOutActivity` (non-interruptible, regenerates Energy slower than a
bed or chair, only ends at Energy = 100) regardless of what the NPC was
doing — cleanly exits/releases whatever was running via its own `exit()`.

**Status labels** (`get_status_labels()`, shown in the E-panel's Status
line only — never the overhead hover prompt): Forgetfulness and Slowing
each collapse to **one** label with every contributing cause listed in
parentheses (e.g. `"Very Forgetful (Starving, Dehydrated, Miserable)"`),
not one line per cause. Irritability shows as its own word
(Grumpy/Frustrated/Mad/Rage); the `(NN%)` suffix is debug-only
(`NPCDebug.enabled`), removed for the final game.

### Personality, Mood & Irritability
**5 traits** (`NPC.personality`, keys in `PERSONALITY_TRAIT_KEYS`), each a
float 0.0–1.0, fully random at spawn (`randomize_personality()`), **fixed
for the NPC's life**. Never shown as numbers — always a descriptive word
banded low/mid/high (`get_trait_word()`, thresholds 0.35/0.65):
`resilience` (Irritable/Even-Tempered/Level-Headed), `sociability`
(Distant/Reserved/Kind), `work_ethic` (Lazy/Steady/Hard Worker),
`neuroticism` (Easygoing/Composed/Neurotic), `optimism`
(Pessimistic/Realistic/Optimistic). Only Resilience and Optimism drive
concrete mechanics this pass — the other three are generated/displayed
but mechanically inert (`FUTURE WORK`: `work_ethic` → skill-gain rate or
job willingness; `sociability` → contagion strength; `neuroticism` →
mood volatility).

**Mood** (real E-panel bar) moves *slowly* by design — a brief dip
shouldn't register, sustained bad conditions over real time should.
Ticks every 5s (`_tick_mood_and_irritability`, not per-frame) from three
additive sources, each independently inspectable via `NPCDebug.log_mood`:
1. **Needs pull** — target = 100 if the Energy/Hunger/Thirst average is
   ≥ 70 ("fine"), else the average itself. Recovery rate (only when
   *rising* toward the target) is scaled by the Optimism trait AND
   (Part 21) mildly by how far into "fine" territory needs actually are
   — barely-fine needs recover ~15% slower than comfortably-fine ones.
2. **Global social contagion** — every tick, each NPC's mood is pulled
   3%/game-hour toward the mood *average of every other NPC in the game*
   (`"npc"` group, no distance limit — deliberately global; bunkers are
   small, and this is meant to compound into spirals either direction).
3. **Random drift** — small symmetric noise, "more than nothing, not
   drastic."

Mood = 0 is the future Crisis Response trigger (see below) — not built;
mood just clamps at 0.

**Irritability** (0–100%, `NPC.irritability`) is a *separate*, faster-
reacting value — deliberately **no UI bar**, backend-only. Ticks on the
same 5s cadence. Target = `(needs_deficit × 1.2 + mood_deficit × 0.4) ×
resilience_trait_mult`, moved toward at 20/game-hour (much faster than
mood). The Resilience trait multiplies generation continuously
(`lerp(1.5, 0.5, resilience)` — Irritable NPCs react more drastically to
the same conditions) *and* separately shifts the label breakpoints: NPCs
with the Irritable trait (resilience < 0.35) cross into each label 5%
sooner; everyone else's breakpoints are raised 10%. Confirmed effects:
folds into forgetfulness (mildly), reduces job willingness (a separate,
continuous, unlogged scoring multiplier in `JobActivity.score()` — half
willingness at max irritability), and drives the status label + dialogue
tone.

**Dialogue** (`get_dialogue_line()`) picks a mood/irritability-aware line
fresh each time Talk is pressed — small hardcoded pools per tier
(angry/frustrated/grumpy/low-mood/happy/neutral). First-pass groundwork,
not a real dialogue system.

**`FUTURE WORK` — Crisis Response, explicitly deferred, not built:**
personality-driven reactions to dire bunker states. Per the original
design note: some NPCs break down/become unhelpful or unpredictable, some
buckle down into overdrive, some spiral toward irritable/rage (the rage/
aggression piece specifically was flagged as a materially bigger system —
combat, hostility, consequences — than anything built so far, and was
deliberately scoped out even further than the rest of Crisis Response).
Trigger point is intended to be Mood reaching 0, likely an end-game-
adjacent scenario. Everything in this system (needs consequences,
irritability, personality traits, mood) exists specifically to give that
future pass real state to react to.

### Skills & Jobs
Four skills (`farming`/`plumbing`/`electrical`/`construction`), floats
0.6–2.0 (displayed ×10, rounded, in the E-panel — e.g. `0.73` → `7`),
randomized at spawn, +0.01 on relevant job completion. `JobBoard`
(autoload) polls every 2s for HARVEST (any tray with a ready plant),
REPLACE_FILTER (purifier < 30% AND a spare unused filter exists anywhere),
REFUEL (generator < 40% AND a non-empty fuel can exists anywhere) — jobs
only post when actually completable. `JobActivity` runs fetch → travel →
work phases; travel targets a standoff point near the object (not its
exact center, which sits inside its own collision and off the navmesh)
computed from whichever direction the NPC is approaching from.

### Items & Consumption
NPCs eat/drink using the exact same world APIs the player does —
`take_bite()`/`take_drink()`/`consume_as_food()` are the single shared
mutation point between player and NPC paths, so values can never drift
apart. A lightweight claim system (`NPCItemUser.claim_item`/
`release_item`) prevents two NPCs converging on the same loose/shelved
item. `DrinkActivity`/`EatActivity` continue automatically across multiple
items within one activity run (grab → consume → immediately look for the
next one if the need isn't yet satisfied) rather than fully exiting and
restarting between each item. All proximity/range checks use
`NPCItemUser.flat_distance()` (XZ-only) — raw 3D distance between the
NPC's capsule-center origin and a floor-level item silently fails range
checks otherwise (this exact bug recurred across chairs, job-site
approach, and item pickup before being centralized here).

### Resting
Two options, competing naturally via the brain's normal scoring:
`SitActivity` (chairs, Energy → 90, regen 25/game-hour) and `LieActivity`
(beds, Energy → 100, regen 45/game-hour, capsule rotated horizontal via
`Bed.get_lie_transform()`). Both use `NPC.lock_movement()` at the seat/
lie-down transition instant (a one-time hard stop, distinct from the
per-frame `halt_movement()` every other stationary phase uses).

### Player Commands
Via the E-panel: press Talk, four buttons appear — "Go eat something",
"Go drink something", "Take a load off", "Harvest the plants". Each force-
starts an existing activity class directly (`NPCBrain.force_command()`),
bypassing normal need-based scoring: `EatActivity`/`DrinkActivity`
directly, `CommandRestActivity` (tries `LieActivity` then falls back to
`SitActivity`), `CommandHarvestActivity` (finds the nearest open HARVEST
job). Identical real-world behavior to the automatic versions. Pass-out's
force-check still preempts a command every frame — commanding a passed-out
NPC does nothing until it recovers.

### Persistence
Phase-4 `SaveManager` field (`MainWorld._get_npcs_for_save`/
`_restore_npcs`) — position, name, needs, skills, generation seed
persist; held items and in-progress job claims do not (NPCs reload
empty-handed and re-decide; `JobBoard` auto-releases claims from freed
NPCs, so this is always safe).

### Debug Tooling
`NPCDebug.enabled` (F7 toggle) gates continuous logging: activity
switches, job lifecycle, stuck-recovery firing, forgetfulness roll
outcomes (every roll, not just successful diversions), and mood/
irritability breakdowns every 5s tick — each printed with its individual
contributing sources so no change is ever ambiguous about why it
happened. `NPCDebug.dump_all()` (F7 "Print NPC Debug State") gives a full
multi-line snapshot per NPC on demand: position, activity, held item,
movement-lock state, stuck-recovery count, all needs + health, speed
multiplier, pass-out state, forgetfulness chance, full status label text,
skills, personality words, seed, mood, and irritability + label.

---

## Non-responsibilities (still genuinely out of scope)

- **Crisis Response** (breakdown/overdrive/rage-as-aggression) — see the
  `FUTURE WORK` note above. Nothing built.
- **NPC-to-NPC dialogue/social interaction** — NPCs don't talk to each
  other; social contagion (mood) is the only inter-NPC effect that exists.
- **Death / end states below 0 health or mood** — both stats clamp at 0
  and currently do nothing further.
- **NPC variety** — single "Survivor" capsule/name; multiple visual/
  named NPC types are not implemented.
- **A real dialogue system** — `get_dialogue_line()` is small hardcoded
  pools, not branching dialogue or NPC-specific writing.
- **Planting, cooking, water-collection, or repair jobs** — `JobBoard`
  is built so each is one new `_scan_*()` function + one `JobActivity`
  type-branch; none of the four exist yet beyond Harvest/Filter/Refuel.

---

## Known Tradeoffs / Tech Debt

- `JobActivity`'s standoff distance (`APPROACH_DISTANCE = 1.0`) is one
  shared constant across all job types, not tuned per-object-footprint —
  a visually large future device might need its own bump.
- `PassedOutActivity`'s "collapsed" pose is a simple in-place rotation,
  not a real animation or floor-level position — first-pass only.
- `Bed.gd`'s `LIE_SURFACE_Y`/lie-rotation values were estimated from the
  scene's known placement convention, not measured directly against the
  rendered mesh — may need visual retuning.
- Dialogue pools are small and hardcoded per tier; expect to replace
  wholesale when a real dialogue system is built.
- `NPCTalkMenuUI.PANEL_H` has been bumped several times as content was
  added (currently 760) via estimation rather than exact measurement —
  worth a real pass once the panel's final content is settled.

---

## Testing Checklist (for in-editor verification)

1. Open project in Godot — zero script errors/warnings.
2. F7 → NPC section → Spawn a couple of NPCs.
3. Watch normal behavior: wandering, routing around furniture and heavy
   loose items without touching them, occasionally sitting/lying down.
4. Drain needs via F7 rows — confirm speed changes, forgetfulness diverts
   from jobs occasionally (check console with debug logging on), and at
   Energy = 0 the NPC collapses immediately and only recovers at full 100.
5. Open an NPC's E-panel (E to interact) — confirm all five bars, the
   Status line (single collapsed Forgetful/Slowed lines with reasons in
   parens, plus irritability word if applicable), Skills, and Personality
   (5 words) all populate and update live.
6. Press Talk — dialogue line + four command buttons appear; try each
   command and confirm real-world effects (consumption, resting, harvest).
7. Force a HARVEST/REPLACE_FILTER/REFUEL job — confirm fetch→travel→work
   completes with a real world effect and no wall/object-collision fighting.
8. F7 "Print NPC Debug State" — confirm the full multi-line dump per NPC
   matches what the E-panel shows for the same NPC.
9. Save and reload — NPCs reappear with correct position/needs/skills.
10. Two+ NPCs over several real minutes with one deliberately starved via
    F7 — confirm the other's mood is measurably pulled down by contagion
    (visible in `log_mood`'s contagion delta).