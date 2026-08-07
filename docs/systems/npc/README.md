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
  needs/health/mood/irritability/relationships state and their tick loops,
  personality generation, random name assignment (10-name pool, collision-
  avoided), movement-lock/stuck-recovery, physics push-through for loose
  items, all status/consequence helper functions, dialogue line selection
  (ambient Talk line + relationship Q&A), Talk interaction, stable
  `npc_id` identity.
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
  Talk → dialogue + command buttons + "Ask About" relationship Q&A, Close.
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
float 0.0–1.0, generated at spawn (`randomize_personality()`) and **fixed
for the NPC's life**. Traits are now **presence-based** (Aug 2026): each
slot is present with 55% chance (`TRAIT_PRESENCE_CHANCE`), and any
*present* trait is skewed into the low or high band — never the neutral
middle. **Absent = baseline**: every `_*_trait_mult()` uses
`.get(key, 0.5)`, so an absent trait behaves identically to a mid-band
value mechanically. An NPC therefore shows anywhere from **0 to 5
personality words**, most landing in between; the rare 0-trait NPC shows
"Nothing stands out". Never shown as numbers — always a descriptive word
banded low/mid/high (`get_trait_word()`, thresholds 0.35/0.65; absent
key → no word):
`resilience` (Irritable/Even-Tempered/Level-Headed), `sociability`
(Distant/Reserved/Open), `work_ethic` (Lazy/Steady/Hard Worker),
`neuroticism` (Easygoing/Composed/Neurotic), `optimism`
(Pessimistic/Realistic/Optimistic). All five now drive concrete
mechanics — Resilience, Optimism, Sociability (see below), and as of
the Aug 2026 trait-wiring pass Work Ethic and Neuroticism:
- **Work Ethic** (Lazy/Steady/Hard Worker) — a ±30% score multiplier
  applied symmetrically via `get_work_ethic_job_mult()`/
  `get_work_ethic_passive_mult()`: `JobActivity.score()` ×1.3 at Hard
  Worker (×0.7 at Lazy), while every passive/need activity (Wander, Sit,
  Lie, Eat, Drink) gets the mirror image (×0.7 Hard Worker / ×1.3 Lazy).
  Steady = ×1.0 both ways. Same continuous-bias pattern as Irritability's
  job discouragement — not a discrete roll.
- **Neuroticism** (Easygoing/Composed/Neurotic) — scales mood's random
  per-tick drift (`MOOD_DRIFT_MAX_PER_GAME_HOUR`) via
  `neuroticism_trait_mult()`: ×0.5 Easygoing → ×1.5 Neurotic (Composed
  ×1.0, unchanged). Bigger, more erratic swings for the Neurotic, calmer
  for the Easygoing, no change to the average. Same multiplier also
  scales the one-time mood drop when passing out — see Trait Effects
  Reference below.
- **Sociability** (Distant/Reserved/Open) scales how fast a relationship
  value moves in either direction (`_sociability_trait_mult()`, 0.5x–1.5x) —
  see Relationships below.
- **Canonical, complete list of every trait's mechanical effect:** the
  **Trait Effects Reference** section below is the source of truth and
  is what gets updated whenever a trait gains or changes an effect; the
  bullets above and the scattered mentions below are summaries only.

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

### Trait Effects Reference (living document — update this whenever a trait gains or changes a mechanical effect)

All 5 traits are continuous 0.0-1.0 values; a trait is only ever
GENERATED for an NPC when it lands outside the neutral middle band
(below `TRAIT_BAND_LOW`=0.35 or above `TRAIT_BAND_HIGH`=0.65) — see
Personality section above. Every multiplier below reads
`personality.get(key, 0.5)`, so an absent trait always behaves as if the
NPC scored a perfectly neutral 0.5 — no separate "is this trait present"
branching needed anywhere the multipliers are used.

**Resilience** (Irritable / — / Level-Headed)
- `_irritability_trait_mult()`, 1.5x (Irritable) to 0.5x (Level-Headed).
  Scales how fast irritability rises from need/mood pressure.
- Same multiplier also scales `get_forgetfulness_chance()` — an
  Irritable NPC is both quicker to anger AND more likely to "forget"
  (wander instead of) a job they were about to start.

**Optimism** (Pessimistic / — / Optimistic)
- `_mood_recovery_trait_mult()`, 0.5x to 1.5x. Scales ONLY how fast mood
  recovers back toward 100 when needs are fine — does not affect how
  fast mood falls in the first place.

**Sociability** (Distant / — / Open)
- `_sociability_trait_mult()`, 0.5x to 1.5x. Scales the magnitude of
  EVERY relationship change in both directions, via
  `_adjust_relationship()`'s single mutation point: passive proximity
  drift, Give's bonus, Takeaway's penalty, and the -3 penalty for
  pulling an NPC off a relax session to do a job. (Relationship Snatch's
  outcome is deliberately relationship-NEUTRAL and untouched by this.)
  A high-Sociability NPC's relationship with you moves faster in BOTH
  directions — quicker to warm up, quicker to sour.
- `get_contagion_sociability_mult()`, 0.67x to 1.33x, is a SEPARATE,
  smaller-range multiplier (same trait value, distinct function) for
  **mood contagion receptivity** — how much this NPC's own mood gets
  pulled toward the room's average mood each contagion tick, not how
  much they influence others. Applied to both the live per-tick
  contagion (`_tick_mood()`) and the time-skip catch-up blend
  (`_catch_up_mood()`); `_mood_contagion_delta` (used by the Action
  Log's threshold logging) automatically reflects the scaled value.
  Tutorial-friendly phrasing: *"Sociability: 0.5x-1.5x on how fast this
  NPC's relationships change (both directions); separately, 0.67x-1.33x
  on how much this NPC's own mood gets pulled by the room's average mood
  (mood contagion)."*

**Work Ethic** (Lazy / — / Hard Worker)
- `get_work_ethic_job_mult()`, 0.7x-1.3x, applied directly to
  `JobActivity.score()`.
- `get_work_ethic_passive_mult()`, the mirror image (1.3x-0.7x), applied
  to Wander/Sit/Lie/Eat/Drink/Relax/Talk/Give-to-Friend's scores.
- Lazy specifically (not Hard Worker) gets DOUBLE the daily Relaxing
  budget (2hr vs the 1hr baseline) — this is a deliberate asymmetry, not
  an oversight: Hard Worker does NOT get a reduced relax budget, only
  the score bias above.

**Neuroticism** (Easygoing / — / Neurotic)
- `neuroticism_trait_mult()`, 0.5x to 1.5x. Scales mood's random
  per-tick drift (`MOOD_DRIFT_MAX_PER_GAME_HOUR`) — bigger/smaller
  swings, not a different average.
- Same multiplier scales the ONE-TIME mood drop applied the instant an
  NPC passes out: `randf_range(1.0, 10.0 * neuroticism_trait_mult())`.
  Baseline range 1-10%, Neurotic 1-15%, Easygoing 1-5%. Lower bound is
  always 1% regardless of trait. Reachable two ways now (same formula):
  the live `PassedOutActivity.enter()` path AND the time-skip catch-up
  path (`_catch_up_energy()`, which fires it when the estimated energy
  drain would have crossed 0 mid-skip).

### Non-Trait NPC Mechanics Worth Noting Alongside Traits

- **Passing out** (0 Energy): forces `PassedOutActivity`, non-
  interruptible, energy regenerates at 15/game-hour (slower than a chair
  at 25 or a bed at 45 — passing out is a bad outcome, not a rest
  strategy). Wakes at 15 Energy (not full) — deliberately leaves them
  still needing real rest afterward, and is the intended hook for a
  future "administer an energy item" player action. Applies the
  Neuroticism-scaled mood drop above once, at the moment of collapse.

### Relationships (groundwork — Aug 2026)

Directional, from each NPC's own perspective only: `NPC.relationships`
(`Dictionary`, key → either another NPC's `npc_id` or the literal string
`"player"`, value → float -100..100, absent key reads as 0/neutral via
`get_relationship()`). No reciprocal Player→NPC value is stored anywhere —
out of scope this pass (would require touching `Player.gd`, outside this
subsystem).

Every NPC now has a stable `npc_id` (`"npc_%d"`, auto-assigned on first
`_ready()`, persisted, restored ids re-sync the counter via
`NPC._register_id()` so a same-session freshly-spawned NPC can never
collide with a loaded one). This didn't exist before — `generation_seed`
is random-but-not-guaranteed-unique and is for personality/skill RNG only,
never used as an identity key.

**Baseline driver (the only one live this pass):** passive proximity.
Ticks on the same 5s cadence as mood/irritability (`_tick_relationships()`,
called from `_tick_mood_and_irritability()`), nudging affinity up toward
every other NPC and the player within 4m (XZ-only, `NPCItemUser.flat_distance`)
by `RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR = 0.15` per game-hour (reduced
from an initial 2.0, Aug 2026 — see Testing Checklist item 19 and the
Give/Takeaway paragraph below for the rebalanced ±7.5 event magnitudes),
scaled by sociability. Deliberately slow — relationships here are meant
to read as built from consistent habit over a long (100+ day)
playthrough, not from a handful of interactions.

**Sociability trait** (previously generated/displayed only) is now wired:
`_sociability_trait_mult()` returns 0.5x (low sociability) to 1.5x (high),
multiplying every relationship delta in either direction — low-sociability
NPCs drift toward Hostile or Close more slowly than high-sociability ones,
symmetric for both bonding and souring.

**Bands** (`get_relationship_label()`, thresholds -60/-20/20/60): Hostile /
Cold / Neutral / Friendly / Close.

**Single mutation point:** every relationship change, present and future,
must go through `_adjust_relationship(target_id, delta)` — it's what
applies the sociability multiplier and the clamp. Never write to
`relationships` directly.

**Player-facing readout:** see the new Names & "Ask About" Dialogue section
below — this is what turns the previously debug-only `relationships` data
into something the player can actually learn in play.

**`FUTURE WORK` — explicitly deferred, not built. Brannon's brainstormed
list, kept here so future passes wire into `_adjust_relationship()` the
same way proximity does rather than reinventing the plumbing:**
- ~~Player handing an NPC food/water directly~~ — done (Give, Aug 2026),
  see the new Give/Takeaway section below. ~~An NPC noticing it lost out
  on a scarce item to another NPC~~ — deliberately NOT built this way in
  the end (see that section for why: no reliable "who wanted it" signal
  existed without inferring desire, which felt arbitrary). Takeaway
  shipped instead, a different and more legible mechanic covering
  overlapping ground.
- Who helps a passed-out NPC/player vs. who beelines past — doubles as a
  precursor signal for the still-deferred Crisis Response system.
- Player commands (`force_command()`) landing well vs. being ignored/
  delayed shifting player→NPC standing specifically.
- Pairwise mood-style contagion between relationship values themselves
  (two NPCs already fond of each other reinforcing faster).
- Personal-space avoidance radius scaling by relationship (wider berth for
  low relationship, tighter tolerance for high) — a `NavigationAgent3D`
  tuning question, not a data-model one.
- Unprompted "gift" item drop-off between NPCs with surplus/deficit.
- ~~`get_dialogue_line()` reading relationship value/label to color
  tone~~ — done, but narrower than originally scoped: a dedicated
  `get_relationship_dialogue_line(target_id)` Q&A ("What do you think of
  X?", see the Names & Ask-About section below) reads relationship state.
  The *ambient* `get_dialogue_line()` Talk line itself is still
  relationship-blind — still future work if a broader tone-shift is wanted.
- A stored Player→NPC reciprocal value, if a future UI pass needs to show
  "how NPCs feel about you" from the player's own side rather than just
  reading `npc.relationships["player"]` per NPC.
- `work_ethic`/`neuroticism` wiring — unrelated to relationships, tracked
  here only because they're the other two still-inert traits.

- `work_ethic`/`neuroticism` wiring — unrelated to relationships, tracked
  here only because they're the other two still-inert traits.

### Names & "Ask About" Dialogue (Aug 2026)

**Names.** `NPC.NPC_NAMES` — a fixed 10-name pool (Mara, Dez, Colton,
Priya, Finch, Sable, Nolan, Ruth, Kwame, Vera). Assigned by
`_assign_random_name()` at `_ready()` whenever `npc_name` is still its
export default `"Survivor"` (a save-restored or scene-placed NPC with a
real name already set is left alone). Collision-avoided against every
other currently-live NPC (`"npc"` group) so two NPCs can never share a
name at once — this matters because the Ask-About feature below refers to
NPCs by name, and an ambiguous name would break that. If the pool is fully
exhausted (an 11th+ NPC), repeats are allowed rather than failing. No
persistence changes were needed — `npc_name` was already a saved field.

**Ask About.** The E-panel's Talk flow gained a third revealed section
(alongside the existing dialogue line and command buttons): "ASK ABOUT",
one button per currently-live NPC other than the one you're talking to
(`NPC.get_other_npc_topics()`), plus a fixed "What do you think of me?"
for the player. Pressing one calls
`NPC.get_relationship_dialogue_line(target_id)` — picks a flavor-text
line from a pool keyed to `get_relationship_label(target_id)`
(Hostile/Cold/Neutral/Friendly/Close, from the Relationships pass) and
shows it in the same dialogue label the ambient Talk line uses. This is
the player's window into relationship state that previously only existed
in `NPCDebug` output.

Deliberately minimal: replies are generic per-band flavor text (e.g.
"I hate them." / "They're alright, I guess." / "They're really cool!"),
not name-specific — the question already names the target, so pools stay
reusable for any target. No acquaintance/gating system exists — every
live NPC is always askable regardless of whether they've actually been
near each other.

**`FUTURE WORK`:**
- Acquaintance gating (can't ask about — or get an honest answer about —
  someone this NPC has never actually been near).
- Ambient `get_dialogue_line()` Talk-line pools reading relationship
  toward the player and coloring tone (currently only the explicit
  Ask-About Q&A does this — see the note in Relationships above).
- Named replies (e.g. weaving the target's name into the answer itself,
  not just the question) once a real dialogue system replaces the small
  hardcoded pools.
- Visual/portrait identity per name — names are text-only right now.

### Give / Takeaway (Aug 2026)

**Give.** Player holds any giveable item — `DishItem`, `FarmProduceItem`,
`FoodCan`, or `WaterBottle` (`NPCItemUser.is_giveable()`, reuses the same
`is_edible()`/`is_drinkable_bottle()` classifiers self-serve
eating/drinking already use) — and walks up to an NPC: `[E] Give <item>
to <name>` appears (mirrors the Basket/Cooking Pot held-item prompt
pattern in `InteractionSystem.gd` exactly). E performs a REAL transfer
through the single shared
`InteractionSystem.release_held_item_to_npc()` (wrapped for NPC-side use
by `Player.release_held_item_to_npc()`): the item physically leaves the
player's hand, becomes the NPC's `held_item`, and is consumed over the
NPC's normal eating/drinking duration via
`GivenEatActivity`/`GivenDrinkActivity` (subclasses of the self-serve
activities that key off `held_item`, so the NPC visibly "eats"/"drinks"
it exactly like something it picked up itself — the overhead label shows
"Eating"/"Drinking"). Nutrition/hydration is NOT applied instantly;
consumption happens async inside those activities' `tick()`, and a
can/bottle persists in the NPC's hand across bites/drinks (drops when
finished, or is dropped if the NPC is interrupted), same as self-serve.

**Give sequencing (the Player side owns the transfer now):**
`_try_give_to_nearest_npc()` first calls `NPC.can_receive_item(item)`
(a pure check: hands free + giveable), then
`release_held_item_to_npc()` (the actual physical transfer, which also
clears the inventory slot and HUD selection exactly like `_quick_drop()`
does), then `NPC.on_item_given(item)` (relationship/burnout bookkeeping
+ wiring the consumption activity). `NPC.receive_item_from_player()`
no longer exists — replaced by that check + consequence split, because
only the Player side has the inventory-slot context needed to clear it
correctly. Sequencing is still safe: `can_receive_item()`'s hands-full
guard is checked first, and nothing changes `held_item` between it and
`on_item_given()` since the whole sequence is synchronous.

A successful gift applies a +7.5 relationship bonus (scaled by Sociability
like everything else, via `_adjust_relationship()`, and by gift
burnout — see below). **Per-(item, NPC) boost gating:** each item
instance tracks which NPCs it's already boosted
(`item.get_meta("npc_gift_recipients")`, an Array of `npc_id`s) — giving
the same can/bottle to the same NPC again still feeds them but grants NO
further relationship reward. The same item CAN still boost several
different NPCs once each — only a repeat to the same NPC is blocked. This
was unreachable for single-serving items before (destroyed on first use)
but matters now that cans/bottles persist across gifts.

**Gift burnout (Aug 2026, Part 25).** Repeated gifts in a short window
give progressively smaller boosts: each NPC tracks `gift_saturation`
(0..1), +0.25 per successful gift, decaying back to 0 over ~5 game-days
(`GIFT_SATURATION_DECAY_PER_GAME_HOUR`, same `game_hours()` clock every
other NPC system uses — day-scale, matching Mood). The actual boost is
`GIVE_RELATIONSHIP_BONUS * lerp(1.0, GIFT_BONUS_FLOOR_MULT, gift_saturation)`
— never fully zero (floor 0.15x) so a burned-out gift still visibly does
something rather than feeling broken. Stacks with (multiplies against)
the Sociability multiplier `_adjust_relationship()` already applies.
Closes the "stand there feeding them nonstop" exploit.

**Per-item gift marking.** Each item instance can only ever produce a
boost once (`item.set_meta("npc_gift_used", true)`, checked before
allowing a repeat). Currently unreachable in practice — a single-serving
Give item is destroyed on its first successful gift
(`consume_as_food()` frees the node), so no instance survives to be
re-offered — but this closes the exploit path in advance for whenever
Give expands to multi-charge items, where the same bottle/can genuinely
could otherwise be re-given after a refill or after being taken back.

**Takeaway.** Any item an NPC is holding, for any reason, is now a valid
`[F] Pick up` target for the player — the earlier need-triggered pickup
gate (Aug 2026) was removed (Part 25) in favor of relying only on the
relationship consequence, not access, to keep this fair. Taking it clears
the NPC's stale `held_item` reference always
(`NPC.on_item_taken_by_player()`); the -7.5 relationship penalty
(`TAKEAWAY_RELATIONSHIP_PENALTY`) still only fires when the item was a
genuinely need-triggered food/water consumption
(`NPC.is_consuming_from_need()`, hunger/thirst < 55, the same threshold
Eat/DrinkActivity themselves auto-trigger on) — taking a job material
(fuel can, purifier filter, harvest fetch) away has no relationship
consequence. A player-forced "Go eat something" command issued while the
NPC wasn't actually hungry still doesn't count as need-triggered.

Known accepted quirk: stealing a job material mid-carry doesn't abort the
job — `JobActivity`'s `held_item` references are all null-checked, so it
can't crash, but the job silently "completes" without its actual effect
landing (no fuel added, no filter replaced). Not fixed this pass — see
Future Work.

Both directions log through `NPCDebug.log_relationship_event()`
(distinct from `log_relationship_tick`'s continuous proximity logging —
these are discrete, always-worth-a-line player actions).

**F7 relationship visualizer.** Piggybacks the existing "Toggle NPC Debug
Logging" row rather than adding a new one — while `NPCDebug.enabled` is
on, every NPC shows a floating pale-blue text readout above their head
(`NPC._update_relationship_debug_label()`, above the Part-5 name/activity
label) listing every relationship they've formed and its band. Debug-only
stand-in for a real in-fiction relationship UI later, per Brannon.

**`FUTURE WORK`:**
- ~~Multi-use item Give (FoodCan/WaterBottle)~~ — done (Aug 2026): one
  bite/drink per gift, item persists across gifts exactly like self-serve
  consumption, per-(item, NPC) recipient tracking prevents repeat boosts
  to the same NPC from the same item.
- JobActivity doesn't detect or react to a stolen job material — the job
  silently "completes" without its effect (see the Takeaway paragraph
  above). A real fix means JobActivity checking for the theft and
  aborting instead of completing.
- A visible interrupt/flinch reaction when an item is taken mid-bite,
  instead of the NPC finishing its ~2s consumption animation
  empty-handed (a cosmetic gap, not a logic bug — see
  `on_item_taken_by_player()`'s comment).
- The floating "-7.5"/"+7.5" loss/gain pulse above an NPC's head — real
  visuals pass, explicitly deferred; the F7 readout is the placeholder.
- NPC-vs-NPC takeaway — structurally impossible right now (the item claim
  system already prevents one NPC from ever targeting another's claimed
  item), so this only ever fires against the player today.

### Relationship Snatch (Aug 2026, generalized to any target)

A badly-relationship'd NPC has a chance to target the PLAYER **or another
NPC** (instead of a normal world item) when searching for food/water,
forcibly taking a held item right out of the target's hands. It is the
one intentional, narrowly-gated exception to the strict no-theft ethos.

The target pool is now unified: `NPC.find_snatch_target()`
considers the player and every other NPC side-by-side as
interchangeable candidates — anyone holding a matching item whose
relationship with the snatcher is ≤ -50 qualifies, with ties broken by
nearest (`NPCItemUser.flat_distance`). The player is just another member
of that pool; there is no player-first branching. The old
`find_player_snatch_target()` is gone; its one remaining backward-compat
wrapper, `get_snatch_chance()` (kept for the player-only F7 debug flow),
just delegates to the generalized `get_snatch_chance_toward(id)`.

Runs as its own **dedicated, non-interruptible `SnatchActivity`** — not a
mode folded inside EatActivity/DrinkActivity. That earlier design (Part
29) failed almost every time in practice: as far as `NPCBrain` was
concerned it was still an ordinary interruptible `EatActivity`/
`DrinkActivity` (whose `interruptible()` only returns `false` once the
drink/eat timer is actively counting down, which never happens during
the walk-over), so the normal 1-second think-cycle could and did cancel
the pursuit mid-approach — the "walks toward the player, then midway just
wanders off" behavior. Now: `SnatchActivity.interruptible()` returns
`false` always, so once the NPC commits it cannot be preempted.

The flow: EatActivity/DrinkActivity call
`NPC.find_snatch_target()` in `enter()`/`_reacquire_or_finish()`.
On a hit, the activity stores the target in `_pending_snatch` and hands
off to `SnatchActivity` on the next tick via the new
`NPCActivity.take_handoff()` mechanism (checked by `NPCBrain.tick()`
right after `tick()` runs — deliberately NOT `force_command()` from
inside an activity's own `tick()`, which would be reentrantly unsafe
against the brain's `_current = null` line). `SnatchActivity` walks to
the target (SNATCH_RANGE), and on a successful
`NPCItemUser.snatch_from()` immediately hands off to
`GivenEatActivity`/`GivenDrinkActivity` to consume what was grabbed —
again via `take_handoff()`, so the item is eaten/drunk over the normal
duration, never instantly.

Both `EatActivity.score()` and `DrinkActivity.score()` also consult
`NPC.is_npc_snatch_eligible()` (a deterministic, roll-free check) so
they return nonzero — and get selected by `_think()` — even when the only
matching item in the bunker is currently in another character's hands.
Without this, score() returned 0 whenever no normal world target existed,
the activity never got chosen, `enter()` never ran, and the NPC just
wandered despite hunger/thirst and a hostile relationship. The actual
probability roll still only happens inside `find_snatch_target()` once the
activity is entered.

Snatch uses a slightly larger `SNATCH_RANGE` (1.6) than the loose-item
`PICKUP_RANGE` (1.2) — the player has real collision geometry, so the
tight pickup distance walked the NPC into physical contact before its
range check ever satisfied.

`SnatchActivity` **continuously re-aims at the target every tick** while
the item is still in their hands (not just once at `enter()`), so a
moving character is chased live. If the target drops the tracked item
(the same item, now loose on the ground) instead of stowing/using/giving
it away, it switches to chasing the dropped item and grabs it there. A
`MAX_CHASE_TIME` (20s) safety valve makes it give up cleanly (logged)
rather than pursuing forever — since `interruptible()` is false, nothing
else could ever interrupt an indefinite chase. The decision path is
fully logged via `find_snatch_target()` (not-considered reasons,
roll attempts, roll success/failure) plus `SnatchActivity`'s own staged
lines. The victim's side of the log mirrors the player version at NPC
scale: `NPC.on_item_snatched_by_npc()`, invoked by `snatch_from()` for an
NPC target, clears the victim's `held_item`, releases the claim, and logs
"%s snatched an item from %s" (relationship-neutral).

**Snatch uses the exact same transfer path as Give.**
`snatch_from()` no longer does its own pickup/inventory logic — for a
player target it calls `Player.release_held_item_to_npc()`, the same
shared function Give's `_try_give_to_nearest_npc()` uses (which wraps
`InteractionSystem.release_held_item_to_npc()`, the `_quick_drop()`-
mirroring transfer that clears the inventory slot and HUD selection too).
The player-side `get_held_item()`/`release_held_item_to_npc()` are
reachable via the `"player"` group node. For an NPC target there's no
inventory system to reconcile — `snatch_from()` directly reassigns the
item to the thief's `hold_point` and clears the victim's `held_item`.
`Player.on_item_snatched()`/`InteractionSystem.clear_held_item_external()`
from the earlier contract are now un-called by Snatch (the shared
transfer handles everything) — left in place as dead code.

- **Gated on hostility.** Only ever considered when the relationship
  with the target is ≤ -50 (`SNATCH_RELATIONSHIP_THRESHOLD`), whether
  the target is the player or another NPC.
- **Chance scales with hostility.** At exactly -50: 5% per attempt
  (`SNATCH_CHANCE_AT_THRESHOLD`). At -100 (fully hostile): 50%
  (`SNATCH_CHANCE_AT_MIN`). Linear between, via
  `get_snatch_chance_toward(target_id)`.
- **Evaluated on target search only** — once per Eat/DrinkActivity entry
  and after finishing a previous item (via `find_snatch_target()`),
  matching the cadence of every other target search, never continuously.
- **Relationship-neutral.** A successful snatch does not further ding the
  relationship — it is already a consequence of an existing bad one, not
  a new event worth logging as its own relationship change.
- **Held item only.** It only ever targets a currently target-HELD item
  (via `target.get_held_item()`); it never reaches into inventory or
  stored items. The item must be a matching food/water item (edible for
  Eat, drinkable bottle for Drink).
- **Deliberately separate from `grab_loose()`.** The guarded `grab_loose()`
  (for legitimate item-finding, with its `is_held` guard added to stop
  accidental theft) stays strict. `snatch_from()` is the one
  intentional exception, reached only through `SnatchActivity`.
- **Staged debug logging** via `NPCDebug.log_snatch()` — `started`/
  `success`/`aborted`/`failed` each get their own console line (only when
  NPC debug logging is on), so a silent failure is never silent again.
- **F7 debug buttons.** "Force Nearest NPC to Snatch Player Item" targets
  the nearest NPC to the player, bypasses both the relationship gate and
  the probability roll, but still requires the player to be actually
  holding a matching food/water item. "Force Nearest NPC to Snatch NPC
  Item" tries the same for an NPC target (bypasses gates, requires a
  disliked NPC holding a matching item). "Relationship -25 / +25 (All
  NPCs ↔ Player)" set every spawned NPC's relationship with the player
  by an exact ±25, bypassing the Sociability multiplier
  (`debug_adjust_player_relationship()` writes `relationships["player"]`
  directly), so the ±25 is predictable for testing.

#### Snatch → Gift Cooldown (Aug 2026)

Per **attacker ↔ specific victim** pair, blocks the NPC or player who was
just snatched FROM from gifting back to that SAME attacker for
`SNATCH_GIFT_COOLDOWN_SEC` **60 seconds** — NOT a general "this NPC is
scary" flag. An uninvolved third party's ability to gift the attacker is
completely unaffected (they were never in that attacker's cooldown list).

- `NPC.start_snatch_cooldown_against(victim_id)` is called by
  `SnatchActivity.tick()` every active tick, so the 60s always counts
  from the LAST moment of active pursuit against that victim (attempts
  that fail or get abandoned still count as "just tried to snatch").
- `NPC.is_gift_blocked_from(giver_id)` is consulted inside
  `can_receive_item()` (its new `giver_id` param defaults to
  `"player"`, so `InteractionSystem.gd`'s existing Give call site needs
  zero changes). When blocked, `can_receive_item()` returns false and
  any Give toward the victim fails.

### NPC↔NPC Talking (Aug 2026)

Opportunistic, scored like Relaxing — but the score is multiplied by a
relationship curve. Flat 1.0x between relationship −15 and +15 (the
"neutral" band), scaling continuously up to 2.5x by +100
(`TALK_SCORE_MULT_MAX`) and down to 0.2x by −100 (`TALK_SCORE_MULT_MIN`)
via `get_talk_score_mult(other_id)`. Only ever considered between NPCs
already within `TALK_RANGE` (3.0) — deliberately **no travel phase**, so
both parties lock in place immediately rather than walking to meet. This
sidesteps the "cancelled mid-approach" failure mode Snatch originally
had. Non-interruptible once both parties are locked in.

Mechanics (`TalkActivity`, registered in `_candidates`):
- `score()` is zero unless a free partner exists (`find_talk_partner()`),
  then `TALK_BASE_SCORE (5.5) × work-ethic passive mult` (see Trait
  Effects Reference). A partner is eligible via `is_available_to_talk()`
  (not relaxing, not already talking, and interruptible).
- On `enter()`, the initiator picks the nearest eligible partner and
  calls `partner.start_talk_session(initiator)`, which `force_command()`s
  a **separate, one-shot partner-side `TalkActivity`**
  (`is_initiator = false`) onto the partner. Both `lock_movement()` and
  face each other (`look_at`), so both stand locked for the whole
  session.
- Session duration `SESSION_MIN..MAX` (8–20 real seconds). When the
  initiator's timer ends, it calls `partner.end_talk_session()`, which
  logs **"Talked to X"** from the partner's own perspective and clears
  its `_partner` so its forced activity finishes. The initiator logs its
  own "Talked to X".
- Interaction (F7 force someone else mid-conversation) triggers
  `exit()` → `partner.end_talk_session()` on the partner side too, so
  neither party is stranded waiting.
- **FUTURE WORK (deliberately not built):** relationship-based random
  conversation OUTCOMES. This pass is groundwork only — both NPCs
  occupied, facing each other, logged.

**F7 debug button:** "Force Nearest NPC to Talk to NPC" calls
`nearest.debug_force_talk()`, which finds a free partner and forces the
initiator's `TalkActivity` (partners still must be eligible).

### Give-to-Friend (Aug 2026)

A well-fed, friendly NPC (relationship ≥ +25 with a friend whose matching
need is low) fetches a loose food/water item and delivers it to that
friend. Chance-to-attempt scales with relationship strength above +25,
mirroring Snatch's curve shape in the opposite direction: 5% at exactly
+25 (`GIVE_TO_FRIEND_CHANCE_AT_THRESHOLD`), 50% at +100
(`GIVE_TO_FRIEND_CHANCE_AT_MAX`), linear between via
`get_give_to_friend_chance(rel)`.

Mechanics (`GiveToFriendActivity`, registered in `_candidates`):
- `score()` uses `has_needy_friend()` (cheap, deterministic — no search
  or roll) so the full search only runs on `enter()`:
  `GIVE_TO_FRIEND_BASE_SCORE × work-ethic passive mult`.
- `find_friend_to_help()` picks the **nearest** eligible needy friend
  (relationship ≥ +25, matching need < 55), picks the matching item type
  (lowest need: `edible` if hunger is lower, `drinkable_bottle` if
  thirst is lower),
  finds a matching loose item, then gates on one probability roll scaled
  to that friend's relationship.
- Fetch phase mirrors `JobActivity` exactly (find/claim/`grab_loose`).
  Travel phase mirrors `SnatchActivity`'s continuous re-aim at a moving
  target. Interruptible throughout (`interruptible() → true`) — this is
  an altruistic errand, fine to abandon if something more urgent comes
  up.
- On arrival (`SNATCH_RANGE`), `can_receive_item()` gates the hand-off:
  the item is `pickup`'d onto the friend's `hold_point`, the friend's
  `held_item` set, and `friend.on_item_given(item, npc.npc_id,
  npc.npc_name)` — so the **relationship boost lands on the donor**, not
  always the player. The donor's own log: "Gave {item} to {friend}". The
  recipient's existing Give log now reads "{donor} gave {item} to
  {npc_name}", generalized from the player-only wording.
- `exit()` releases any unconsumed claimed item; if interrupted while
  actually carrying the item, the NPC keeps it (they'll finish
  delivering or use it next re-entry — reusable fetch).

**F7 debug button:** "Force Nearest NPC to Give to Friend" calls
`nearest.debug_force_give_to_friend()` — bypasses the chance roll but
still needs an eligible needy friend and matching loose item.

### Skills & Jobs
Four skills (`farming`/`plumbing`/`electrical`/`construction`), floats
0.6–2.0 (displayed ×10, rounded, in the E-panel — e.g. `0.73` → `7`),
randomized at spawn, +0.01 on relevant job completion. `JobBoard`
(autoload) polls every 2s for HARVEST (any tray with a ready plant),
REPLACE_FILTER (purifier < 30% AND a spare unused filter exists anywhere),
REFUEL (generator < 40% AND a non-empty fuel can exists anywhere) — jobs
only post when actually completable. As of the Aug 2026 per-plant pass,
**HARVEST posts ONE job per READY PLANT** (not one per tray) — a 2x1
tray with both cells ready produces two independent, separately-claimable
jobs (even by two NPCs at once); the job `target` is the plant itself.
`JobActivity` runs fetch → travel → work phases; travel targets a
standoff point near the object (not its exact center, which sits inside
its own collision and off the navmesh) computed from whichever direction
the NPC is approaching from.

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

### Relaxing (Aug 2026)
A scheduled break, distinct from Wander/Idle: `RelaxActivity` delegates
entirely to `SitActivity`/`LieActivity` for the actual arrival/seating
mechanics (same composition `CommandRestActivity` already uses), or just
stands in place if neither a chair nor a bed is free. Self-limiting via a
**daily time budget** rather than precise scheduling — it scores a flat
baseline (6.0, just above Wander's 5.0, × Work Ethic passive mult)
whenever budget remains, burns budget down in ~20–40 min sessions
(`SESSION_MIN`/`SESSION_MAX` game-hours), and naturally yields a handful
of sessions per day. Budget = **1 game-hour/day baseline, 2 for Lazy**
(`RELAX_BUDGET_BASELINE`/`RELAX_BUDGET_LAZY`, via
`NPC.get_relax_time_remaining_today()`), reset once per in-game day by
`_tick_relax_day()` on the same 5s tick as mood. Fully interruptible —
a genuine need (hunger/thirst/energy/forgetfulness) still preempts it
normally. Asking an NPC to do a job while relaxing ("Harvest the plants")
is refused the first time that relax session (`get_relaxing_refusal_line()`
shown in the E-panel dialogue); the second ask in the same session
complies at a **-3 relationship cost** (`request_job_while_relaxing()`).

**Inter-session cooldown + spawn stagger (Aug 2026):** sessions are now
separated by a randomized `RELAX_MIN_GAP_HOURS`–`RELAX_MAX_GAP_HOURS`
(3–6 game-hours) cooldown (`start_relax_cooldown()`, checked by
`RelaxActivity.score()` via `NPC.is_relax_on_cooldown()`; decremented in
`_tick_relax_day()`). The cooldown only starts if a session actually
happened — an `enter()` that immediately found no chair/bed doesn't
trigger it. Fresh NPCs also get a randomized 1–3h head-start cooldown in
`_ready()`. Why: without these, a fresh NPC (full needs, nothing else
competing) wins the very first think-cycle and can chain sessions
back-to-back until the whole daily budget is gone in one sitting —
front-loading the entire day's relaxation at spawn.

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

### Time-Skip Catch-Up (Aug 2026)
`NPC.catch_up_all(hours)` is the single entry point simulating how NPCs
spend a time-skip (F7 Fast-Forward, sleep). It is called explicitly by
each skip source right next to its existing
`player_stats.skip_time_with_drain()` call — **any future skip source
must call it too; nothing hooks into the game clock automatically**.
Clamped to a hard `MAX_CATCHUP_HOURS` (72) so no single call can simulate
unbounded consumption. Per NPC, in order:
- **Needs (hunger/thirst):** full drain for the duration, then an
  ESTIMATE of how many real meals/drinks would have offset it
  (`CATCHUP_MEAL_RESTORE_ESTIMATE` ≈ 45 hunger, `CATCHUP_DRINK_RESTORE_ESTIMATE`
  ≈ 21.5 thirst, averaging the giveable item types), actually consumed
  from real available world items via their own
  `consume_as_food()`/`take_bite()`/`take_drink()` calls — capped by
  what's actually there. An empty bunker means the NPC just goes hungry,
  same as reality. When to eat isn't simulated, only roughly how many
  real items would have been used.
- **Energy:** full drain; if it would have crossed 0 mid-skip, the same
  neuroticism-scaled mood drop `PassedOutActivity` uses fires once, and
  the remainder regenerates at `PassedOutActivity`'s rate
  (`CATCHUP_PASSED_OUT_REGEN_PER_GAME_HOUR` = 15/game-hour, kept in sync
  with `NPCBrain`'s constant).
- **Relaxing:** today's budget is deducted proportionally to the skip's
  fraction of a day (`_catch_up_relax_budget()`), after a day-boundary
  reset via `_tick_relax_day()` — a 6h skip removes 25% of the daily
  budget (baseline 60min → 45min remaining), a 12h skip 50% (→ 30min).
  Stops an NPC "banking" a full untouched hour across a skip and dumping
  it all in one greedy session right after waking.
- **Mood:** the needs-driven pull and random drift are `_tick_mood()`'s
  own formulas evaluated once with a large `h`. The needs target uses a
  blend of pre-/post-catch-up needs (a rough stand-in for how needs
  behaved across the whole window, not just the endpoint). Contagion is
  a single blended pull toward the bunker's PRE-skip average mood
  (`avg_mood_before`, snapshotted once in `catch_up_all()`), scaled by
  elapsed time and clamped so it can't overshoot — deliberately
  approximate, not a real per-NPC-pair simulation.
- **Harvest:** every plant that `is_ready()` at the moment the skip is
  triggered is snapshotted once into a shared pool; each NPC harvests up
  to `floor(hours)` of them from that pool (one harvested plant = one
  "job", not one JobBoard tray-job — a tray can hold several ready
  plants). Plants that were NOT ready before the skip do NOT get
  auto-harvested (farming growth isn't tied to skips at all).

### Action Log (Aug 2026)
Per-NPC, player-facing, **curated** log of MEANINGFUL things this NPC has
done — deliberately NOT a record of routine activity switching
(Wander→Eat→Wander etc.). `NPC.log_action()` is the single append point
(`get_action_log()` returns newest-first), scoped to one NPC (each NPC's
own E-panel shows only their own log, unlike the global
`NotificationManager` feed it mirrors in structure). Both timestamp
flavors are captured at append time: `fired_at_msec` for the live "Xs
ago" display, `game_time` (a snapshot of the HUD clock string) for the
hover tooltip. Capped at `ACTION_LOG_MAX_LEN` (100).

**Every current log-triggering event:**
- Give (`on_item_given()`) — new gift: "Player gave you X (+N relationship)",
  with the actual post-Sociability applied delta (returned by
  `_adjust_relationship()`, which now reports what it did); repeat-gift:
  "fed only, no relationship change".
- Takeaway (`on_item_taken_by_player()`) — need-triggered only; taking a
  job material is deliberately not logged.
- Snatch success (`SnatchActivity.tick()`) — "Snatched an item from your
  hands". Aborted/failed attempts and the dropped-item-chase variant are
  deliberately not logged.
- Relax session completed (`RelaxActivity.exit()`) — "Relaxed for N min"
  (skipped if the session never actually started).
- Job/Harvest completion — "Job (Harvest)" (Part A's per-plant change
  touches this same anchor).
- Pass-out / wake (`PassedOutActivity`) — "Passed out (0 energy)" on
  collapse, "Woke up" on recovery.
- Mood contagion (`_check_contagion_log()`) — "Mood rose/fell N% (Mood
  Contagion)", only once cumulative drift since the last entry crosses
  ±`CONTAGION_LOG_THRESHOLD` (2%).
- Irritability / relationship band crossings (`_check_label_crossings()`)
  — "Became \"X\" (irritability)", "Calmed down (irritability)",
  "Relationship with you became \"X\"", logged only at the actual
  crossing, not every tick the band is held.

"Talked to [NPC]" is an aspirational future entry (no NPC-to-NPC
dialogue exists yet) the log format already supports without changes.

**UI:** the E-panel has a "Show Activity Log" toggle that expands the
panel by `LOG_SECTION_H` (and re-centers it via `_apply_panel_height()`)
revealing a fixed-height scroll area (`LOG_AREA_H`) rebuilt live off the
`action_logged` signal; timestamps tick over as "Xs/m/h ago" every frame
while expanded. Collapsed by default on every open, not remembered.

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
  other. Mood contagion and (as of the Relationships pass) proximity-based
  relationship drift are the only inter-NPC effects that exist; neither
  involves actual communication.
- **Relationship-reactive dialogue/behavior** — `get_dialogue_line()` and
  every existing activity/scoring function are relationship-blind for now;
  relationships are tracked but nothing reads them yet outside debug
  tooling. See Relationships' Future Work below.
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
11. Spawn 2-3 NPCs — confirm each gets a different name from the 10-name
    pool (no duplicates) shown in the E-panel title and debug dump.
12. Open one NPC's E-panel, press Talk — confirm "ASK ABOUT" shows "What
    do you think of me?" plus one button per other live NPC by name.
    Press a few — confirm the dialogue line updates to relationship-
    appropriate flavor text matching that NPC's current
    Hostile/Cold/Neutral/Friendly/Close band (cross-check against F7
    "Print NPC Debug State").
11. Spawn 2+ NPCs close together (or walk the player next to one) and wait
    several real minutes with debug logging on (F7 "Toggle NPC Debug
    Logging") — confirm `[NPC:<name>] relationships: {...}` prints every ~5s
    with rising values for whoever's in range, and F7 "Print NPC Debug
    State" shows the same values with correct Hostile/Cold/Neutral/Friendly/
    Close labels.
12. Save and reload — confirm relationship values and each NPC's `npc_id`
    survive; spawn a brand-new NPC after reload and confirm its
    auto-assigned id doesn't collide with a restored one (distinct ids in
    the debug dump).
13. Get an NPC's hunger or thirst below 55 (F7 "Drain NPC Needs -40"),
    let them start eating/drinking, then walk up mid-consumption and
    press F — confirm the normal "[F] Pick up" prompt appears and taking
    it works, the NPC doesn't error or double-consume, and F7 "Print NPC
    Debug State" / the relationship dump shows -7.5 toward "player".
    Separately, confirm an NPC holding an item for a non-need reason
    (full hunger/thirst, forced via "Go eat something" while not hungry,
    or a job material) is NOT takeable.
14. Hold a cooked dish or piece of produce, walk up to an NPC — confirm
    "[E] Give <item> to <name>" appears and works, hunger rises, and
    relationship goes up +7.5. Confirm a FoodCan or water bottle does NOT
    show a Give prompt (out of scope this pass).
15. Toggle F7 "Toggle NPC Debug Logging" on — confirm every NPC shows a
    floating relationship readout above their head; toggle off — confirm
    it disappears.
16. Confirm an NPC holding a non-need item (job material, or food/water
    while hunger/thirst are both above 55) is now ALSO takeable via F —
    and confirm F7's relationship dump shows NO relationship change for
    that specific takeaway (only need-triggered takeaways should ding).
17. Give the same NPC 4-5 dishes/produce in quick succession — confirm
    each successive relationship gain is visibly smaller than the last in
    the F7 debug dump/visualizer, bottoming out around 15% of the base
    +7.5. Stop giving and watch (or fast-forward via F7's admin tools) —
    confirm "Gift burnout: NN%" in the visualizer decays back toward 0
    over multiple in-game days, not minutes.
18. Give an NPC a full FoodCan or WaterBottle — confirm the relationship
    boost lands, the item stays in your hand afterward (not destroyed),
    and it now shows fewer bites/less fill remaining. Give the SAME
    item to the SAME NPC again — confirm hunger/thirst still rises but
    NO additional relationship boost (check F7 debug dump — delta should
    log as 0.0/"no bonus"). Give that same partially-used item to a
    DIFFERENT NPC — confirm THAT NPC gets a normal +7.5-scaled boost (once).
19. Confirm relationship pacing feels appropriately slow: stand an NPC
    and the player together continuously and use F7 admin fast-forward —
    relationship should NOT reach "Close" within the first several
    in-game days from proximity alone. A single Give/Takeaway should move
    the number by 7.5 (pre-Sociability-scaling), not 15.
20. Use F7 admin tools to push an NPC's relationship with the player to
    -60 or lower (or wait for enough negative interactions). Drain that
    NPC's hunger or thirst below 55, hold a matching item, stay nearby —
    over several attempts, confirm the NPC sometimes paths to the player
    and snatches instead of finding a normal item; confirm relationship
    does NOT change from a successful snatch.
21. Press F7 "Force Nearest NPC to Snatch Player Item" while holding a
    matching item near an NPC with a perfectly fine relationship —
    confirm it snatches anyway. Press it while NOT holding anything (or
    holding a non-food/water item) — confirm it fails gracefully (console
    message, no crash, nothing happens).
22. Give any item type to an NPC — confirm it visibly leaves your hand,
    appears in the NPC's, and gets "eaten"/"drunk" over the normal
    duration (overhead label shows "Eating"/"Drinking"), not instantly.
23. With debug logging on, use F7 "Force Nearest NPC to Snatch Player
    Item" repeatedly while holding a matching item near an NPC — confirm
    it succeeds reliably now (not ~1-in-many), and confirm the console
    shows staged SNATCH log lines (started/success, or a specific
    aborted/failed reason) every time, never silent.
24. Confirm F7 relationship ±25 buttons move every spawned NPC's
    relationship with the player by exactly 25 (check via the F7
    relationship visualizer), regardless of Sociability.
25. Give an item to an NPC, then immediately check the HUD — no lingering
    eat/drop prompt should remain, and scrolling the inventory should not
    re-populate the now-empty slot.
26. Repeat the "NPC pathing to an item, player grabs it first" test —
    confirm the NPC now visibly gives up (or grabs something else) well
    before reaching the item's last position, not after (the `is_held`
    early-abort guard + `grab_loose()`'s own guard).
27. With debug logging on, drain an NPC's need and hold a matching item
    at a fine relationship — confirm the console explicitly shows
    "not considered" every search with the actual reason, instead of
    nothing.
28. Push relationship to -60 or below (F7), drain the matching need, hold
    the item, stay still — confirm roll attempts are logged, and
    eventually a "roll succeeded" leading to a real chase.
29. Once a snatch attempt starts, walk away — confirm the NPC keeps
    adjusting course toward your CURRENT position, not a fixed point.
30. Drop the tracked item mid-chase instead of stowing it — confirm the
    NPC switches to walking to the dropped item and picks it up rather
    than giving up.
31. Keep running from a chasing NPC for over 20 seconds — confirm it
    eventually gives up cleanly (logged) rather than following forever.
32. Repeat the exact root-cause scenario for the scoring blind spot:
    player holds the ONLY water bottle in the bunker, an NPC at -100
    relationship with 0 thirst, standing still — confirm the NPC now
    actually enters "Getting water"/pursues within a few seconds rather
    than wandering, and the debug log shows roll attempts, not silence
    (this is the `is_player_snatch_eligible()` fix in both
    `EatActivity.score()`/`DrinkActivity.score()`).
33. Trigger a successful snatch — confirm the item now visibly transfers
    to and STAYS in the NPC's hand (followed by the normal ~2s
    "Drinking"/"Eating" hold) instead of falling to the floor (this is
    `release_held_item_to_npc()` switching to `clear_slot()`, which runs
    AFTER `pickup()` instead of `remove_item()`'s pre-pickup `drop()`).
34. Trigger a snatch chase — confirm the NPC stops at a small but clearly
    visible gap before grabbing rather than making physical contact with
    the player (this is `SNATCH_RANGE` 1.6 vs the loose-item `PICKUP_RANGE`
    1.2, used both in `SnatchActivity.tick()` and
    `NPCItemUser.snatch_from_player()`).
35. Start a snatch pursuit (F7 force or organic), then SWAP to a
    different inventory slot mid-chase instead of dropping the item —
    confirm the NPC aborts (console shows the "aborted" log) instead of
    walking to your old position and pulling the item out of storage
    (this is the `collision_layer == 1` extra condition — swapped-away
    items sit at layer 0, only a genuine drop sets layer 1).
36. Start a pursuit, then actually DROP the item (not swap) — confirm the
    NPC still correctly diverts to the dropped item on the ground and
    picks it up (genuine drops pass the same check).
37. Spawn two NPCs, force one to Lazy and one to Hard Worker (F7 or
    respawn until you get the words you want in the E-panel). With an
    open job and normal needs on both, confirm the Hard Worker picks the
    job noticeably more often/faster, and the Lazy one prefers wandering/
    sitting/eating over it.
38. Watch mood drift over several in-game hours on a Neurotic vs an
    Easygoing NPC with stable needs — confirm the Neurotic one's mood
    visibly swings more per tick (F7 debug mood log) than the Easygoing
    one, without either trending toward a different average.
39. Spawn several NPCs — confirm the E-panel shows anywhere from 0 to 5
    personality words per NPC (not always exactly 5), and "Nothing
    stands out" for the rare 0-trait case.
40. Watch an NPC over a full in-game day (F7 fast-forward) — confirm it
    enters "Relaxing" roughly once or twice, ~20-40 min each, sitting/
    lying if a chair/bed is free. Confirm a Lazy NPC's relax budget is
    roughly double a non-Lazy NPC's over the same period.
41. While an NPC is Relaxing, press "Harvest the plants" — confirm the
    first press gets a refusal line and does NOT start the job. Press
    again in the same relax session — confirm the job now starts AND
    relationship drops by 3. Confirm a fresh relax session later resets
    back to a first-press refusal.
42. Max an NPC's energy to 100 (F7), force/wait for a relax session with a
    free chair or bed nearby — confirm they sit/lie down and STAY there
    for the session duration, no in-and-out loop.
43. Confirm energy still very slowly climbs (if not already at 100) while
    relaxing in a chair/bed, at a visibly slower rate than normal
    resting/sleeping.
44. Confirm normal (non-relax) Sit/Lie behavior is completely unchanged —
    this only touches the new Relax-prefixed classes.
45. Drop an NPC's energy to 0 (F7) and let them pass out — confirm they
    wake up once energy reaches 15, not 100, and remain passed out (still
    lying there, energy climbing) below that.
46. Compare a Neurotic NPC's collapse to an Easygoing one's (same F7
    energy-drain test) — confirm the Neurotic one's mood drop is
    noticeably larger on average (up to 15%) than the Easygoing one's (up
    to 5%), with F7 debug logging showing the exact roll each time.
47. Set an NPC's hunger/thirst low, ensure real food/water exists nearby,
    fast-forward 24h — confirm hunger/thirst end up in a reasonable range
    (not maxed, not zeroed) and that real items in the world were
    actually consumed/depleted (check counts before/after).
48. Empty the bunker of food/water entirely, fast-forward — confirm the
    NPC's hunger/thirst just drain fully with no error, nothing crashes
    trying to consume items that don't exist.
49. Drain an NPC's energy most of the way down, fast-forward 24h — confirm
    if it crosses 0 during the estimate, mood drops once (F7 log shows
    it) and energy ends up partially recovered, not stuck at 0 or jumped
    to full.
50. Note an NPC's remaining relax budget, sleep 6 hours — confirm the
    remaining budget drops by ~25% of the daily total, not to zero and
    not unchanged.
51. Have 2+ ready-to-harvest plants across trays before a fast-forward —
    confirm they get harvested during the skip (real produce appears),
    and that plants which were NOT ready before the skip do NOT get
    auto-harvested even if the skip's growth would have made them ready
    (since growth isn't currently tied to skips at all, this should
    already hold true, but worth confirming directly).
52. Harvest a 2x1 (or larger) tray with multiple ready plants — confirm
    it now posts as multiple independent jobs (check F7 job debug dump
    if available) and can be split across two NPCs working simultaneously.
53. Open an NPC's E-panel, press "Show Activity Log" — confirm the panel
    visibly grows taller and the log area appears with correct rows;
    press again — confirm it shrinks back to the original size.
54. Trigger a Give, a Takeaway, a successful Snatch, a completed Relax
    session, and a Harvest job on one NPC — confirm each produces exactly
    one clear, correctly-worded log entry, newest at the top.
55. Leave two NPCs near each other with meaningfully different moods for
    several minutes — confirm a "Mood rose/fell X% (Mood Contagion)"
    entry appears only occasionally (once cumulative drift crosses ±2%),
    not every few seconds.
56. Push a relationship down past a band boundary (F7) — confirm a
    "Relationship with you became "X"" entry appears exactly once at the
    crossing, not repeated every tick while it stays in that band.
57. Scroll through a log with 20+ entries — confirm the scrollbar
    appears and behaves normally, and hovering a row's timestamp shows
    the in-game clock time in a tooltip.
58. Push two NPCs' relationship well above +15 and place them near each
    other — confirm they talk noticeably more often than a neutral pair;
    push another pair below -15 — confirm noticeably less often.
59. Confirm a talking session locks BOTH NPCs in place, facing each
    other, for the session, and both get a "Talked to X" log entry.
60. Interrupt one NPC mid-conversation (F7 force-command something else)
    — confirm the partner doesn't get stuck waiting forever.
61. Set two NPCs' relationship to +40+, drain one's hunger, ensure a
    matching item exists — confirm the well-fed one occasionally fetches
    and delivers it; confirm the recipient's relationship toward the
    DONOR (not the player) goes up, and the donor's own log shows "Gave
    X to Y".
62. Set two NPCs' relationship to -60, drain the hostile one's hunger,
    give the disliked one a matching held item — confirm the hostile one
    snatches from the OTHER NPC (not the player) when eligible, and both
    sides' logs show it correctly.
63. With the player ALSO eligible (bad relationship, holding a matching
    item) alongside an eligible NPC target, confirm the nearest of the
    two gets picked, regardless of which type it is.
64. Harvest multiple ready plants back-to-back with 2+ NPCs farming
    actively — confirm no "freed instance" errors in the console, even
    under repeated rapid harvesting.
65. Press F7 "NPC↔NPC Relationship +25 (All Pairs)" a few times — confirm
    every NPC's relationship toward every OTHER NPC rises (check via each
    NPC's F7 relationship visualizer), not just toward the player.