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
float 0.0–1.0, fully random at spawn (`randomize_personality()`), **fixed
for the NPC's life**. Never shown as numbers — always a descriptive word
banded low/mid/high (`get_trait_word()`, thresholds 0.35/0.65):
`resilience` (Irritable/Even-Tempered/Level-Headed), `sociability`
(Distant/Reserved/Kind), `work_ethic` (Lazy/Steady/Hard Worker),
`neuroticism` (Easygoing/Composed/Neurotic), `optimism`
(Pessimistic/Realistic/Optimistic). Resilience, Optimism, and (as of the
Relationships pass) Sociability drive concrete mechanics — the remaining
two are generated/displayed but mechanically inert (`FUTURE WORK`:
`work_ethic` → skill-gain rate or job willingness; `neuroticism` →
mood volatility). Sociability scales how fast a relationship value moves
in either direction (`_sociability_trait_mult()`, 0.5x–1.5x) — see
Relationships below.

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
by `RELATIONSHIP_PROXIMITY_GAIN_PER_GAME_HOUR = 2.0` per game-hour, scaled
by sociability.

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
pattern in `InteractionSystem.gd` exactly). E transfers nutrition/
hydration into the NPC immediately (`NPC.receive_item_from_player()`).
Single-serving items (Dish/Produce) are fully consumed and destroyed, one
bite/drink at a time for cans/bottles (mirrors self-serve
`NPCItemUser.eat_held_step()` exactly) — a can/bottle persists in the
player's hand across multiple gifts, getting progressively emptier, same
as it would from repeated self-use.

A successful gift applies a +15 relationship bonus (scaled by Sociability
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
(`NPC.on_item_taken_by_player()`); the -15 relationship penalty
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
- The floating "-15"/"+15" loss/gain pulse above an NPC's head — real
  visuals pass, explicitly deferred; the F7 readout is the placeholder.
- NPC-vs-NPC takeaway — structurally impossible right now (the item claim
  system already prevents one NPC from ever targeting another's claimed
  item), so this only ever fires against the player today.

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
    Debug State" / the relationship dump shows -15 toward "player".
    Separately, confirm an NPC holding an item for a non-need reason
    (full hunger/thirst, forced via "Go eat something" while not hungry,
    or a job material) is NOT takeable.
14. Hold a cooked dish or piece of produce, walk up to an NPC — confirm
    "[E] Give <item> to <name>" appears and works, hunger rises, and
    relationship goes up +15. Confirm a FoodCan or water bottle does NOT
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
    +15. Stop giving and watch (or fast-forward via F7's admin tools) —
    confirm "Gift burnout: NN%" in the visualizer decays back toward 0
    over multiple in-game days, not minutes.
18. Give an NPC a full FoodCan or WaterBottle — confirm the relationship
    boost lands, the item stays in your hand afterward (not destroyed),
    and it now shows fewer bites/less fill remaining. Give the SAME
    item to the SAME NPC again — confirm hunger/thirst still rises but
    NO additional relationship boost (check F7 debug dump — delta should
    log as 0.0/"no bonus"). Give that same partially-used item to a
    DIFFERENT NPC — confirm THAT NPC gets a normal +15-scaled boost (once).