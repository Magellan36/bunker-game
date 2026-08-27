# Medical System

**Status: design reference — not yet implemented.** No `scripts/` files for
this system exist yet. This doc is the single source of truth for what the
Medical system is supposed to be before any code is written, per the
"Feature Evaluation Checklist" in `GAME_PHILOSOPHY.md`. Read this in full
before writing the first line of implementation. This doc went through
several rounds of real revision during design (see git history if curious)
— treat everything here as the current best understanding, not as
untouchable law. If a future idea genuinely conflicts with something below,
that's a reason to revisit this doc, not a reason to force-fit the idea.

## Purpose
Models physical injury and illness for both the player and NPCs — open
wounds, bleeding, infection, broken bones, burns, and (player-only)
chronic-neglect conditions — as a slow-burn, legible pressure that runs
underneath the whole 100+ day game, then becomes mechanically decisive
during the rare, high-stakes combat encounters that can end a run outright.

This system leans hardest on **Pillar 3 (readable cause and effect)** and
**Pillar 10 (preserve hope)** from `GAME_PHILOSOPHY.md`. See "Design
pillars" below for how those (and the rest of the project's pillars)
translate into this system's own specific principles, now that the design
has actually settled through several real rounds of revision.

## Design pillars
These are Medical's own working principles, distilled from everything
locked in through design — not a restatement of `GAME_PHILOSOPHY.md`'s
pillars, but each is anchored to one where relevant. An earlier version of
this section was written too early, before the design had been tested
against enough real ideas — this one reflects what actually survived.

1. **Reason over randomness.** Every ailment traces to a clear, expected
   cause. Only the specific parameters within an already-understood risk
   carry bounded randomness — never whether something happens for no
   reason. (Pillar 3.)
2. **Healing is always happening.** Every wound-tier condition heals
   naturally the moment it exists, by default, whether the player does
   anything or not. Treatment changes the *rate*, never *whether*
   recovery is possible — nothing in this system is a dead end. (Pillar
   10.)
3. **Severity and healing are separate, visually nested axes.** A
   condition's badness and its progress toward resolution are tracked
   independently, with the Healed fill always contained within — never
   exceeding — the severity fill on the same ring.
4. **Felt through needs, not just stats.** The sharpest way a condition
   should register isn't a speed penalty, it's a shrinking ceiling on
   hunger/water/sleep — a condition that's easy to shrug off mechanically
   should still visibly change what a normal day requires.
5. **Legible over subtle.** This system is allowed to be visually rich
   (multiple icons, layered rings, greyed-out need caps) because full
   player understanding matters more than ambient minimalism. Restraint
   is a styling choice layered on top, not a ceiling on clarity.
6. **One mechanical truth, two decision-makers.** The player and NPCs run
   on the exact same underlying condition logic — the same triggers, the
   same severity/healing model, the same items. Only *who decides when to
   act on it* differs (see "NPC scope").
7. **Scarcity creates the tension, not babysitting.** NPCs manage their
   own conditions autonomously; the interesting pressure is competing for
   limited bandages/antibiotics/splints, not remembering to check on
   someone.
8. **Complexity pays rent by reusing what exists.** Medical leans on
   `PlayerStats`' needs, NPC's existing status-label/scoring patterns, and
   `StatusEffectsContainer`'s HUD skeleton rather than building parallel
   systems — extending them only where a real gap exists. (Pillars 2 and
   5.)

## Responsibilities
- Own the catalog of medical conditions (injuries + illnesses), their
  severity/progress model, symptom effects, and escalation/healing rules.
- Own the per-entity (player or NPC) list of active conditions and the
  aggregation functions that turn "active conditions" into concrete
  gameplay effects — movement speed, carry capacity, sprint availability,
  interact/work speed, HP drain, and needs-cap reduction.
- Decide when a condition is created and how its severity/progress and
  healing-progress values move over time.
- Drive the ambient HUD status-effect icons (severity ring(s) + healing
  ring where applicable + hover detail) and the deeper inspectable
  status/medical screen (see "Presentation" below).
- Define what each treatment item (bandage, antibiotics, splint, trauma
  kit) actually does to a condition's state.

## Non-responsibilities
- **Does not own the needs/stat systems it reads from or modifies caps
  on** — `PlayerStats.gd` (food/water/sleep/health) and `Player.gd`'s
  `stamina` stay the source of truth for those values; Medical reads them
  to decide when a condition triggers/escalates, and applies cap
  reductions to them, but doesn't own their core tick/drain logic.
- **Does not own NPC needs-driven effects that already exist, or the
  NPC-side decision/prioritization layer built on top of Medical's
  data** — low sleep/hunger/thirst already affects NPC mood and behavior
  today via `NPC.gd`'s own needs system, independent of Medical, and stays
  that way. Medical does not duplicate this for NPCs (no player-style
  hidden chronic-condition tracking on NPCs). Deciding *when* an NPC acts
  on a Medical condition (prioritization, pathing to items) is
  `NPCBrain`/`JobBoard`'s job. **What Medical does own on the NPC side:**
  the full port of condition triggering, severity/Healed-ring progression,
  symptoms, and status — see "NPC scope" for the exact division; this is a
  deliberate, explicit exception to the usual scope boundary, not an
  oversight.
- **Does not own the power-grid or water-quality hazard states** it keys
  off of (`PowerManager`'s `GridState`, water quality wherever that's
  tracked) — it only reads their current state to decide whether a
  hazardous action is actually hazardous right now.
- **Does not (yet) own build-mode medical items or their models** —
  bandages, antibiotics, splints, and trauma kits are referenced here by
  role/name only. Their item definitions, icons, models, and
  crafting/acquisition path are explicitly out of scope for this doc's
  first pass — see "Deferred scope."
- **Does not own the ambient status-icon widget itself** —
  `StatusEffectsContainer`/`StatusEffectIcon` (`scripts/ui/hud/`) already
  exist as a general-purpose badge strip; Medical is a *consumer* of that
  API, not its owner. See "Presentation."
- **Does not own passive HP regeneration** — planned (see "Planned future
  extensions"), but it's fundamentally a `PlayerStats`-level mechanic
  (needs reaching true, uncapped 100%) that Medical only interacts with
  indirectly, by virtue of its cap reductions making that harder to reach.

---

## The randomness principle

This replaced an earlier, more rigid "randomness boundary" framework that
tried to enumerate specific allowed exceptions — that framework kept
needing new exceptions added as the design evolved, which was a sign it was
the wrong shape. The actual principle underneath it, now stated plainly:

**The *reason* something happens to the player should always be clear and
expected — never random or out of nowhere. The *specific parameters* within
an already-understood risk are allowed a bounded degree of randomness.**

The purpose of the randomness is explicitly to avoid monotonous,
fully-predictable outcomes while staying planned-for and fair — not to
introduce surprise. A player who gets an open wound should never be
surprised *that* they might bleed or get infected; they can be reasonably
surprised by exactly how bad the bleeding starts at, exactly when infection
lands, or exactly how much a fracture worsens on a given bad step.

This is a living principle, not a closed whitelist — new conditions can
introduce their own bounded randomness on their own parameters as they're
designed, as long as the reason for the condition itself stays legible.
Current examples, for reference (not exhaustive):
- Whether an Open Wound also spawns a Bleeding status at all (a bounded
  66% roll at creation), and Bleeding's starting severity if it does
  (randomized, low range).
- Fracture's starting severity, and its escalation step size per
  over-exertion event (both randomized within bounded ranges) — the
  over-exertion trigger itself is deterministic and visible.
- Open Wound infection: *whether* infection happens at all is genuinely
  uncertain (not just timing) — see "Open wounds, bleeding, and infection"
  below — bounded by a real probability curve the player can reason about
  (roughly 80% cumulative by day 3 if untreated), not an open-ended chance.
- The randomized natural heal-time rolled for a wound at creation (see
  "Healing (the Healed ring)" below).
- Cooking and resetting a hazardous breaker/generator carry a bounded burn
  chance, scaled visibly by the actual hazard state involved.

---

## Severity / progress model

Each condition instance tracks a severity value (its main ring's fill),
and conditions split into two categories along **two independent axes**:
whether severity itself moves (live vs. pinned), and whether the condition
additionally tracks natural healing progress on its own separate ring (see
"Healing (the Healed ring)," the next section — this is the bigger
structural addition and worth reading in full before assuming how a given
condition behaves).

**Live-severity conditions** — severity genuinely moves over time between
0–100%. Two different flavors exist here, which matters a lot:
- **Subsystem conditions** (Bleeding, Infection) — severity is fully
  **bidirectional**: it rises while worsening/untreated, and falls while
  correctly treated, all on the *same* ring. These do **not** get a
  separate Healed ring — their own severity ring already fully represents
  both "how bad" and "how close to resolved."
- **Fractured** — severity is **one-directional**: it only ever rises
  (via the bounded-random escalation steps on over-exertion), it never
  falls. Resolution/recovery for Fractured is handled entirely by its
  separate Healed ring, not by severity decreasing. See "Broken bones /
  fractures" and "Healing (the Healed ring)" below.

**Pinned-severity conditions** — the injury itself has no "less severe"
version; it either exists at its full magnitude or it doesn't, so it
displays permanently at 100%. Examples: Open Wound, Broken Bone, Burns
(electrical and cooking). These all get a Healed ring (see below) as the
thing that actually represents their progress toward resolution — the
severity ring staying at 100% only ever tells you the injury is present,
never how close it is to being over.

**100% severity can trigger a full state conversion**, not just a worse
label — Fractured reaching 100% *becomes* Broken (a different condition
with its own symptoms/treatment), and an Open Wound's infection outcome
either removes the wound (spontaneous clearing) or converts it to Open
Wound (Infected) — see below for both.

---

## Healing (the Healed ring)

This is the mechanism that makes a wound's eventual recovery feel earned
and expected rather than random or unexplained — and it's a genuinely
separate concept from severity, but **it shares the same physical ring
track as severity rather than being a separate concentric ring.** The
Healed fill is a sub-portion within whatever arc the severity ring is
currently showing — it converges toward the severity fill's current edge
and can never extend past it. For a pinned condition (severity always a
full circle), that means the whole ring is available to close across. For
a live-severity condition like Fractured, only the portion of the ring
severity has actually filled is available — if severity later rises, the
ceiling the Healed fill is chasing moves out too (see below).

**Applies to:** the "wound-tier" conditions only — Open Wound, Fractured,
Broken Bone, and Burns. **Does not apply to** Bleeding or Infection — those
remain single-ring, fully bidirectional, and don't need a second dimension
since their own ring already shows both direction and magnitude.

**The core rule: every wound-tier condition heals naturally over time,
always, by default** — this is the "hence the ring" idea. A random
heal-time is rolled the moment the condition is created (baseline ~2–3
days for a low-severity/no-severity condition), and the Healed ring closes
from empty toward full as that time elapses, regardless of whether the
player does anything at all. Reaching full Healed-ring completion resolves
the condition — for Open Wound specifically, this Healed ring completing
*is* what "spontaneous clearing" (see below) actually is; they're the same
mechanic, now with a visible countdown instead of an invisible timer.

**Treatment changes the *rate*, not whether healing happens at all:**
- **Fractured/Broken:** natural healing occurs even unsplinted, but
  requires the limb to stay under the same exertion threshold that
  governs escalation — in practice, close to no movement at all, for
  several days, to progress at a meaningful rate without risking a
  worsening event. **Splinting** is the practical choice whenever
  available: it substantially reduces the condition's symptom penalties
  while worn *and* dramatically speeds up the Healed ring. Splinting does
  not disable the escalation trigger — over-exertion can still happen
  while splinted (see "Broken bones / fractures").
- **Open Wound:** heals at its normal baseline rate by default. If the
  wound is currently **actively bleeding and/or infected**, Healed-ring
  progress continues but at a heavily dampened rate — "still moving, but
  nearly imperceptible" — until the Bleeding is bandaged and/or the
  Infection is cured. This is a real, felt cost of leaving either
  untreated, beyond their own direct dangers (HP drain, needs-cap
  reduction): they also stall the wound's own path to being over.
- **Broken Bone and Burns:** sped up by genuine rest/sleep, same as
  described previously — the Healed ring is simply the visible form of
  that.

**Severity changes interact with the Healed ring for conditions whose
severity can move:** for Fractured specifically, each escalation event
(a) sets the Healed ring back somewhat (a real, immediate setback, not
just a slower future rate) and (b) extends the *total* target heal-time,
recomputed from the new, higher severity — a low-severity Fracture (say
~15%) targets roughly the same 2–3 day baseline as other wound-tier
conditions, while a severely escalated one (say ~90%) should take on the
order of ~10 days. This is precomputed at creation and dynamically
recomputed on every escalation event, not fixed once and forgotten.

**Why this doesn't reopen "no ETA for event-triggered worsening"
(previously an open question):** because natural healing is now *always*
progressing regardless of whether the condition is currently worsening,
there's always a live "Time Left" figure available from the Healed ring's
current progress vs. its current target — even for Fractured, whose
severity escalation itself is still event-triggered and unpredictable.
This resolves that open question; see "Open questions" for what's still
genuinely unresolved.

---

## Condition catalog

### Open wounds, bleeding, and infection
The richest interaction in the catalog — three related effects, each
behaving differently:

**Open Wound** — created by whatever injury event causes it. Pinned at
100% severity for its whole life. Gets a Healed ring per the section above
— natural healing always progressing, dampened while actively bleeding
and/or infected. At the moment an Open Wound is created, there's a **66%
chance it also spawns its own separate Bleeding status** on the same body
part (a one-time roll at creation, not re-rolled over time). From the
moment it exists, an Open Wound is racing between two outcomes:
- **Infection** — a genuinely uncertain (not merely timing-uncertain)
  outcome: roughly an **80% cumulative chance across the first 1–3 days**
  if left untreated with antibiotics, starting low on day 1 and rising
  exponentially through day 3.
- **Spontaneous clearing** — if infection hasn't happened by the time the
  Healed ring completes (roughly the same day 2–3 window), the wound
  resolves on its own. This is literally the Healed ring finishing, not a
  separate hidden timer.

Whichever resolves first wins. **Antibiotics** work on both sides of this:
applied to a plain (not-yet-infected) Open Wound, they act
**preventatively**, reducing/removing the infection chance; applied after
infection has already taken hold, they act **curatively** (see Infection
below).

**Bleeding** — a fully separate status effect from Open Wound, with its
own live, fully bidirectional severity ring (no Healed ring of its own —
see "Severity / progress model"). Starts at a randomized low severity
(~1–15%), and if left untreated, climbs on a fixed exponential curve over
roughly 2 in-game days toward 100%. Severity directly sets HP drain rate —
very low at low severity (roughly ~10 HP/day at the low end), scaling up
exponentially so severity near 100% drains HP rapidly. **Bandaging** the
affected body part is Bandage's entire job and stops Bleeding outright —
it does not affect Infection risk at all (that's Antibiotics' job
specifically, not shared).
- **Ambient display rule:** if an entity has multiple simultaneously
  bleeding wounds, the single Bleeding icon shows only the **worst**
  currently-bleeding wound, so the player is always pointed at the most
  urgent one first. Each wound's own bleeding status is still fully
  available in its own hover tooltip and the future status screen.

**Infection** — once the infection outcome above actually happens, the
Open Wound is modified into **"Open Wound (Infected)"** — same underlying
status effect, not a separate one, now additionally carrying its own live,
fully bidirectional **Infection Severity** (0–100%, no Healed ring of its
own — same reasoning as Bleeding). Displayed as a genuine two-ring icon: the Open Wound's own
severity/Healed ring (severity pinned at 100%, with the Healed fill
progressing within it, heavily dampened while infection is active), plus
a separate, larger **Infection Severity ring** layered around it as its
own distinct concentric ring — this is the one case where two truly
separate ring tracks exist on the same icon (if the wound is also still
bleeding, that shows on the separate Bleeding icon, not this one).
Infection severity climbs while untreated and falls once **Antibiotics**
are applied (curative use) — severity rises at a fixed rate while
untreated, treatment flips the sign. Rising infection severity adds
compounding detriments beyond Open Wound's base penalty — reduced speed,
and (see "Needs cap reduction" below) a shrinking maximum cap on hunger,
water, and sleep. At 100% infection severity, need caps are reduced so
severely that survival without treatment becomes close to impossible.

### Broken bones / fractures
- **Fractured** (the initial state) triggers deterministically (e.g.
  sustained 0-stamina over-exertion, or a real physical event). Starting
  severity is randomized within a low-to-moderate range (roughly 15–25%),
  with a correspondingly minor initial speed penalty. Severity is
  **one-directional** here — it only rises, never falls; recovery is
  entirely the Healed ring's job (see "Healing (the Healed ring)" above).
- **Escalation:** further sustained over-exertion (stamina at empty) while
  already Fractured is a deterministic trigger for a severity increase —
  the *size* of each increase is randomized within a bounded range
  (roughly 10–25% per event), repeating on each qualifying event until
  severity reaches 100%. Each escalation also sets back the Healed ring
  and extends its target time (see above).
- **At 100%, Fractured converts into Broken** — a distinct, worse
  condition, pinned at 100% severity, with its own (more detrimental)
  symptoms and its own (presumably more advanced) treatment requirement.
  Broken also gets its own Healed ring per the general wound-tier rule.
  Exact Broken-state symptoms/treatment are not yet designed — see "Open
  questions."
- **Splinting** does not gate whether healing happens (natural healing
  always progresses, per "Healing" above) — it dramatically **hastens**
  the Healed ring and **reduces symptom penalties** while worn. Without a
  splint, meaningful healing progress requires the limb to stay almost
  entirely still for an extended period, since any qualifying
  over-exertion still risks triggering an escalation.
- **Splinting does not prevent escalation** — over-exertion while splinted
  can still trigger a severity increase by the same rule as above. If a
  splinted Fracture is pushed all the way to 100% anyway, it still
  converts to Broken, and doing so **removes/breaks the splint**,
  requiring new treatment from scratch.

### Burns (electrical and cooking)
- **Pinned-severity condition** — always displays severity at 100% while
  active; no escalation path, no infection track. Gets a Healed ring per
  the general wound-tier rule — natural healing always progressing, sped
  up by genuine rest/sleep.
- Triggered by cooking, or by resetting a hazardous breaker/generator —
  both bounded, reason-clear randomness per "The randomness principle,"
  never from an unrelated action.

### Chronic / cumulative conditions (player-only)
- Example: prolonged sleep neglect → a persistent stat-penalty condition.
- The accrual counter (e.g. "nights under-rested") is **hidden from the
  HUD entirely** while it builds — no Healed ring, no severity ring, no
  visible meter at all until it manifests.
- Once manifested, its cause is shown explicitly — reusing the exact
  pattern `NPC.gd`'s `_forgetfulness_reasons()`/`get_status_labels()`
  already uses for parenthetical cause lists (e.g. "Chronic Back Strain (4
  nights under-rested, 2 days heavy carrying)"). Once manifested, it can
  use the same wound-tier presentation (pinned severity + Healed ring) as
  everything else for its own resolution.
- **Player-only** — NPCs already get an equivalent effect through their
  existing needs→mood system (low sleep already affects NPC mood/behavior
  today); duplicating a hidden chronic-condition track on top of that
  would be redundant. See "NPC scope."

---

## Needs cap reduction
Alongside speed/stamina/work modifiers, conditions can reduce the
*maximum* value of a need (hunger, water, sleep — **never Health's cap**;
see "Planned future extensions" for why) rather than draining the need
directly. This is a primary way the player is meant to *feel* a worsening
condition, not a secondary flourish.

- Shown on the needs bar (`NeedsGauge.gd`) as a **greyed-out portion** at
  the top of the bar — the usable range visibly shrinks as the cap drops.
- Currently, Infection is the only condition using this. Proportional but
  not equal across the three needs — sleep takes the largest cut, water
  next, hunger least, at any given infection severity. Rough ballpark
  (proportions matter more than the exact numbers, which need real
  tuning):

  | Infection severity | Hunger cap | Water cap | Sleep cap |
  |---|---|---|---|
  | 15% | −5% | −10% | −15% |
  | 100% | −75% | −90% | −95% |

- Modeled generally on `MedicalCondition` (a `needs_cap_modifiers` dict,
  per-need, keyed by severity) so future conditions can reuse the same
  mechanic — Infection is just the first.
- **Real extension point on `PlayerStats.gd`:** needs currently clamp to a
  hardcoded `100.0` ceiling in several places (`replenish_food`,
  `_tick_needs`, etc.). A dynamic, Medical-adjustable per-need cap is new
  plumbing that doesn't exist today.

---

## Item roles

| Item | What it does |
|---|---|
| **Bandage** | Stops the Bleeding status effect outright on the treated body part. That's its entire job — no effect on infection risk, no effect on a wound's Healed-ring rate directly (though stopping Bleeding removes one of the two things that dampen it). |
| **Antibiotics** | Dual role: applied to a plain Open Wound, **prevents/reduces** infection risk. Applied after infection has taken hold, **cures** it — flips Infection Severity from rising to falling (and removes the other Healed-ring dampener once cured). |
| **Splint** | Fracture-specific. Not required for healing to occur at all (natural healing always happens — see "Healing"), but dramatically hastens the Healed ring and reduces symptom penalties while worn. Destroyed if the fracture reaches 100% and converts to Broken. |
| **Trauma Kit** | High-severity combined case (e.g. a combat wound like "Gunshot (Torso)") — does the job of both Bandage and Antibiotics at once, sized for wounds the lesser two items can't keep up with alone. |

---

## Data model (sketch)

Not yet implemented — the intended shape, generalizing the pattern
`NPC.gd` already proved out for needs (`get_status_speed_multiplier()`,
`get_status_labels()`), extended to also run on the player and to be
body-part-aware.

- **`MedicalCondition`** (resource): `id`, `category` (Injury / Illness),
  `body_part`, `severity_mode` (`live_bidirectional` / `live_one_directional`
  / `pinned_max` — see "Severity / progress model"), `severity: float`
  (0–100), `starting_severity_range` (fixed value or min/max pair),
  `has_heal_ring: bool` (true for all wound-tier conditions — Open Wound,
  Fractured, Broken, Burns; false for Bleeding/Infection), `heal_progress:
  float`, `heal_time_target` (rolled at creation, dynamically recomputed
  on severity change for conditions where severity moves — see
  "Healing"), `heal_rate_modifiers` (dampening/hastening multipliers —
  e.g. active-bleeding dampener, active-infection dampener, splinted
  hastener), `symptoms` (dict of modifiers — speed mult, stamina-drain
  mult, carry-capacity mult, work-speed mult, HP-drain-per-severity curve
  where applicable), `needs_cap_modifiers` (optional dict, per-need, keyed
  by severity), an `escalation_model` (none / time-based curve /
  event-triggered with randomized step size), a `converts_to` (optional —
  the condition id it becomes at 100% severity, e.g. Fractured → Broken),
  and a treatment requirement where applicable.
- **Open Wound is a special case worth modeling explicitly:** it doesn't
  use `converts_to` the way Fractured→Broken does — instead its own Healed
  ring completing *is* the "spontaneous clearing" resolution, racing
  against a separate `infection_roll_window` (days 1–3, ~80% cumulative,
  exponential shape). Once infected, it gains its own
  `infection_severity: float` field rather than becoming a wholly
  separate condition instance.
- Both `PlayerStats`-adjacent player code and `NPC.gd` hold an array of
  active conditions and expose the same shape of aggregation function NPC
  already has, generalized: `get_medical_speed_multiplier()`,
  `get_medical_status_labels()` (or these get folded into the existing NPC
  functions rather than duplicated — an implementation-time decision, not
  a design one).
- **Body-part granularity:** coarser than RimWorld's model, deliberately —
  head, torso, left/right arm, left/right leg, with hand treated as a
  sub-part of arm only if "can't hold items/tools" ends up wanting to be a
  distinct effect from "can't carry as much." Not yet finalized — settle
  before implementation starts, since the whole data model is keyed off
  it (see "Open questions").

---

## Presentation

Three layers of increasing detail, all showing the same underlying data:

**Layer 1 — Ambient HUD icons (always visible).** The most surface-level,
pertinent info at a glance: bleeding severity (worst wound only — see
above), infection severity, wound presence/healing progress, and so on for
whatever conditions are active. Reuses the existing
`StatusEffectsContainer`/`StatusEffectIcon` skeleton (`scripts/ui/hud/`),
extended for live percentage rings, a distinct Healed-ring overlay color
(blue) sharing the severity ring's track for wound-tier conditions, and —
for Open Wound (Infected) specifically — a genuine second, separate
concentric ring for Infection severity. **Multiple simultaneous icons are
intentional** —
several wound icons appearing at once after a bad fight is meant to be
alarming, not something to visually minimize away.

**Layer 2 — Hover tooltip.** Full detail for the *individual* status being
hovered: current severity, Healed-ring progress and "Time Left" where
applicable (now always computable for wound-tier conditions — see
"Healing"), treated/untreated state, and condition-specific info (e.g.
Bleeding's current HP-loss-per-second at present severity).

**Layer 3 — Future Status Screen (not yet designed/scaffolded).** The
overall info hub: a visual body diagram, per-limb status, all wounds and
their individual bleeding rates simultaneously, and deeper detail on
whichever limb is hovered/selected.

**On subtlety vs. legibility:** the system's visual richness (a Healed
fill overlaying the severity ring, Infection's added second ring on
infected wounds, greyed-out need caps, one icon per wound) is a real
departure from "purely ambient/easy to miss." That's accepted — the
governing principle is that the player must be able to understand and
reference what's happening to them easily, consistent with the
"simulation" feel of the rest of the game. Visual restraint and thematic
consistency with the rest of the HUD are real goals, but as a styling
layer applied on top of full legibility, not a constraint that reduces it.

**Known extension points needed (not yet built):**
- `StatusEffectsContainer.add_effect()` currently assumes a fixed-duration
  countdown ring, not a live percentage value — needs a real severity-ring
  rendering path.
- A ring-fill overlay mode (Healed fill sharing the severity ring's track,
  converging toward but never past the severity fill's current edge) for
  every wound-tier condition, plus a genuine second, separate concentric
  ring specifically for Open Wound (Infected)'s Infection severity. This
  is a bigger UI lift than originally scoped and deserves real legibility
  testing once built.
- `StatusEffectsContainer` needs to comfortably hold several simultaneous
  icons at once (e.g. 3–4 separate wounds after a fight).
- `NeedsGauge.gd`'s `set_food/water/sleep(frac)` API takes a 0–1 fraction
  against an implicit fixed 100 max — needs extending to also render a
  reduced cap (the greyed-out portion).

---

## NPC scope

NPCs get **full parity** with the player on the event-driven physical
conditions in this catalog — Open Wound, Bleeding, Infection, Fractured/
Broken, Burns — triggered and healed by the same rules as the player. The
core idea (NPCs autonomously handle their own issues, competing with the
player for scarce resources rather than needing to be babysat) is
unchanged. What's now explicit is **where the line sits between this
system and whoever owns NPC behavior**, since the two need to interlock
tightly:

- **Medical owns the full NPC-side port** — not just the player's version
  of the system. That means: how conditions trigger on an NPC, their
  severity/Healed-ring progression, symptom effects, and status — the
  same underlying mechanical truth as the player, applied to NPCs. This
  is a real build responsibility for whoever implements this system, not
  just a design note for someone else to pick up.
- **The NPC-behavior side (`NPCBrain`/`JobBoard`) owns the decision layer
  built on top of that data** — prioritization logic (why treat now vs.
  keep working, how severe a given condition needs to be to interrupt a
  job), pathing/execution to reach medical items (seek antibiotics if
  infected, bandage if bleeding), and needs-based behaviors like avoiding
  poor sleep or finding a bed (mostly already in place independent of
  Medical). That side then tunes NPC behavior against whatever Medical
  exposes.
- **This is a deliberate exception to normal system-ownership
  boundaries** — Medical is explicitly expected to reach into NPC-side
  work here (rather than staying strictly scoped to `PlayerStats`/
  `Player.gd`) because consistency between the player and NPC versions of
  this system matters more than keeping the two agents' scopes clean.
  Some blind collaboration between the two sides is expected; Medical is
  the one with full context on how the system is supposed to work and
  should keep both sides honest to it.
- A **future task** (explicitly not now): write a priority-tier reference
  — severity, required action, urgency/timing, all of it — as a single
  clean lookup Medical is best positioned to author, to feed directly into
  NPC's scoring logic.
- **Chronic/cumulative conditions stay player-only** — NPCs already get an
  equivalent effect through their own needs→mood system; see "Chronic /
  cumulative conditions" above.

---

## Planned future extensions
Not part of this pass, but explicitly locked in as real future work for
this system, not just floated ideas:

- **Heavy-carry stamina drain.** Holding/carrying heavy items should cause
  its own slow, ongoing stamina drain. While an entity is fighting an
  infection, or has a broken/fractured arm or a wound on an arm, that
  drain rate should scale up **exponentially** with the relevant
  condition's severity.
- **Passive HP regeneration.** Not currently implemented anywhere in the
  game. Health should slowly regenerate only when at least one need is at
  its true, uncapped 100% — slowly for one need at 100%, meaningfully
  faster for three needs simultaneously at 100%. This is why Health's cap
  is never itself reduced by Medical (see "Needs cap reduction") — a
  reduced need cap already blocks this regeneration path as a natural
  consequence.
- **NPC medical priority-tier reference** — see "NPC scope" above.
- **Forward-compatibility note on sleep:** the current sleep mechanic is a
  time-skip simulation (`PlayerStats.skip_time()`), expected to eventually
  become a real sped-up simulation rather than a skip. Anything in this
  doc that hooks into "healing sped up during sleep" should be built
  against whatever the current mechanism is without assuming it's
  permanent.

---

## Open questions (resolve before/during implementation)
- **Body-part list:** finalize the exact set before writing
  `MedicalCondition` — the whole model is keyed off it.
- **Broken (post-Fractured) state details:** symptoms and treatment
  requirement not yet designed beyond "more advanced treatment, more
  detrimental effects."
- **Deep-dive status screen:** UI layout/flow not yet designed.
- **`StatusEffectsContainer` extensions:** live severity ring, the
  Healed-fill overlay mode, Infection's second concentric ring, and
  multi-icon capacity — see "Presentation" above.
- **`NeedsGauge` cap-reduction rendering:** see "Presentation" above.
- **Exertion-threshold definition:** what counts as "resting" vs.
  "exertion" for fracture healing/escalation — likely keys off
  `Player.gd`'s existing stamina-drain/sprint signals, exact threshold
  needs tuning at implementation time.
- **Exact numbers everywhere:** starting severities, escalation steps,
  the infection probability curve, heal-time baselines/scaling, the
  needs-cap curve, HP drain rates, Healed-ring dampening/hastening
  multipliers — all given as ballparks/proportions in this doc. Real
  tuning happens during implementation.
- **Illness triggers beyond wound-infection:** contaminated water/spoiled
  food as illness vectors — depends on whatever water-quality/food-
  freshness tracking exists elsewhere; verify against
  `docs/systems/water/README.md` and `docs/systems/farming/README.md`
  first.
- **TODO — food spoilage:** a food-freshness/spoilage mechanic doesn't
  exist yet anywhere in the codebase — likely its own scoped feature (with
  its own storage/inventory implications) rather than something this doc
  should design in full. Revisit scope with Brannon before building.

## Deferred scope (explicitly not this pass)
- Medical-related build-mode items and their models (bandage, antibiotics,
  splint, trauma kit item definitions, icons, acquisition/crafting path).
- Scarring / permanent injury outcomes (would need its own evaluation
  against Pillar 10 before being added — not assumed here).
- Any UI/UX visual design pass for the deep-dive status screen beyond "it
  should exist and be body-part-based."
- The NPC medical priority-tier reference and the actual NPCBrain/JobBoard
  wiring for self-treatment (see "NPC scope" and "Planned future
  extensions").
