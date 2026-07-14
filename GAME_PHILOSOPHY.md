# Game Philosophy & Design Pillars
**Scope note (read this first):** this is a **human design-reference document**, not part of the standard per-task AI context chain (`PROJECT_SUMMARY.md` §0 → `docs/systems/*/README.md` → `architecture.json` → source). AI agents should **not** read this file for routine engineering tasks — it costs real tokens and adds no value to "fix this bug" or "add this device type" work. Consult it specifically when evaluating whether a *new mechanic or feature* fits the game's intended direction, or when Brannon explicitly asks for that kind of evaluation.

This document is not a design spec or feature list. Its purpose is to establish the principles that guide major design and engineering decisions. If a future mechanic conflicts with this document, reconsider the feature before changing the philosophy.

---

## Vision

Bunker Game is a colony survival game about building and sustaining a home after the collapse of civilization.

The game combines systemic resource management with human storytelling. Players are challenged to balance interconnected systems while forming attachments to the bunker they built and the people who inhabit it.

The objective is not to perfectly simulate reality, but to create meaningful decisions that produce memorable stories.

## Core experience

Players should finish a run remembering:
- the people they lived with
- the difficult choices they made
- the history of their bunker
- the compromises that kept it alive
- the slow transformation of their home over time

Players should remember stories before statistics.

## Simulation philosophy

Simulation exists to create meaningful decisions. It should be deep enough to produce emergent interactions, but no system should exist solely because it's realistic. Complexity is justified only when it creates new strategic choices or memorable outcomes.

The player's primary role is not to manage systems — it's to make tradeoffs. Interesting decisions are more valuable than detailed simulation.

## Home

The bunker should feel like a place rather than a machine. Decoration, layout, routines, and survivor relationships should gradually transform it into something the player values beyond its mechanical usefulness. A well-built bunker should reflect the player's priorities and history.

## Entropy

The primary long-term threat is entropy: infrastructure deteriorates, resources become harder to obtain, machines become less reliable, the environment becomes harder to sustain. Challenge should come from responding to gradual decline through interacting systems, rather than primarily from hostile scripted events.

## Optimization

Optimization is rewarded but not required. Players who invest time optimizing systems should gain flexibility, resilience, and opportunities to pursue secondary goals. Optimization should create breathing room, not eliminate challenge.

## Emergent storytelling

Stories should emerge naturally from interacting systems. Avoid scripting emotional moments whenever systemic interactions can produce them organically — the most memorable stories are the ones unique to a particular bunker and playthrough.

## Lifecycle of a bunker

Early game is planning and construction. Mid game is growth, adaptation, and increasing complexity. Late game is difficult tradeoffs as interconnected systems become harder to sustain.

Most playthroughs will eventually end in collapse — not because the game demands it, but because small failures compound into larger ones. Exceptional planning, optimization, and adaptation may allow a bunker to persist indefinitely, but permanence should always feel earned, never expected.

---

## Design Pillars

**1. Decisions over actions** — the player should spend more time deciding than performing repetitive actions. Busywork is a design failure.

**2. Interconnected systems** — systems should gain depth by interacting with other systems, not by becoming internally complex.

**3. Readable cause and effect** — players should understand *why* something happened, even if they couldn't have prevented it. Failures should be traceable. *(This project has hit real, concrete violations of this pillar in code before — see "A note on Pillar 3" below.)*

**4. Reward optimization, don't require it** — optimizing players should get resilience, more strategic options, free time, and longer survival, but optimization should never be required for basic survival.

**5. Complexity must pay rent** — every layer of complexity must introduce new decisions or meaningful interactions. Complexity that only adds realism or bookkeeping should be reconsidered.

**6. Support multiple playstyles** — optimization, planning, decoration, survivor relationships, experimentation, and storytelling should all be simultaneously viable. No playstyle should invalidate another.

**7. Lasting consequences** — major decisions should have persistent consequences. The bunker should gradually tell the story of previous successes and failures.

**8. Emergence over scripting** — memorable situations should emerge from interacting systems whenever possible, rather than being scripted.

**9. Respect player investment** — players may lose to poor planning, accumulated tradeoffs, calculated risk, or unavoidable uncertainty. They should never lose because information was hidden or systems behaved inconsistently.

**10. Preserve hope** — pressure should continuously increase, but hope should never disappear. Players should always feel there's one more decision that could stabilize the bunker.

### A note on Pillar 3, for future reference
This project already found a real example of Pillar 3 being violated in the wild — worth remembering as a concrete case, not just an abstract principle: the electrical grid's `BROWNOUT`/`TRIPPED` states were structurally unreachable due to a dead code path (`_start_flicker_offline()` had zero call sites), so total grid failure jumped straight from `OVERLOADED` to a hard blackout with **zero warning** — no flicker, no "breaker tripped, go reset it" moment — even though the intended design (and the UI/lighting code already built to support it) assumed players would get that escalating, readable warning. From a player's seat, that read as arbitrary and unfair, which is exactly what this pillar exists to prevent. Fixed as of July 2026 (see `docs/systems/power/README.md` Known tradeoffs) — kept here as a reminder of what a real Pillar 3 violation looks like in this codebase specifically, not just in the abstract.

---

## Feature Evaluation Checklist

When evaluating any new mechanic, system, or feature, ask:

**Design**
- Does it create a meaningful tradeoff?
- Does it interact with existing systems rather than existing in isolation?
- Does it avoid repetitive busywork?
- Does it support existing playstyles rather than invalidating them?

**Player experience**
- Does it strengthen attachment to the bunker or its inhabitants?
- Does it create opportunities for memorable, emergent stories?
- Can players understand its consequences after the fact (Pillar 3)?

**Technical**
- Is its complexity justified by the decisions it creates (Pillar 5)?
- Does it fit cleanly into an existing subsystem, or does it need a genuinely new one? (Check the relevant `docs/systems/*/README.md`'s "Extension points" section before assuming a new system is needed.)
- Does it preserve subsystem ownership boundaries (see the relevant system's "Non-responsibilities" section)?
