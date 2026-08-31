# Medical System — Handover (Aug 2026)

**Read this whole document before touching anything.** This session ran
long and covered a lot of ground — this doc exists specifically so a
fresh agent (or a fresh context window) can pick up with full context
without re-reading the entire prior conversation. Nothing here is
optional background; treat it as load-bearing.

## Where everything lives (read in this order)

1. **`docs/systems/medical/README.md`** — the design source of truth.
   Read this in FULL before writing any code. It covers the randomness
   principle, the severity/Healed-ring model, the full condition catalog,
   needs-cap reduction, item mechanics, and NPC scope. It has been kept
   accurate through several real rounds of revision — trust it over
   memory of "how Medical works," including this handover doc wherever
   the two ever disagree (this doc is a snapshot; README.md is living).
2. **`plans/medical-system-implementation-plan.md`** — the original
   pass-by-pass build plan. **Partially stale** — several passes shipped
   in a different shape than originally planned (Trauma Kit's design
   changed entirely mid-implementation, for one). Useful for historical
   context on *why* things are structured the way they are, not a
   reliable checklist of what's left.
3. **This doc** — session history, current exact status, and the one
   concrete task you should do first.

## What's actually implemented right now (verified, not aspirational)

**Core condition system** (`scripts/player/medical/MedicalCondition.gd`,
`PlayerMedical.gd`):
- Open Wound, Bleeding (66% co-spawn chance), Infection (a modifier on
  Open Wound, not a separate condition — dual-ring HUD), Fractured →
  Broken (escalation via `Player.gd`'s `exhausted` signal), Burns
  (electrical/cooking flavor, cosmetic only).
- The severity/Healed-ring model described in README.md — live-
  bidirectional (Bleeding/Infection), live-one-directional (Fractured),
  pinned (Open Wound/Broken/Burn) — is fully working, including the
  Healed fill sharing the severity ring's track rather than being a
  separate ring.
- Needs-cap reduction: `PlayerStats.food_cap/water_cap/sleep_cap`,
  written by `PlayerMedical.set_needs_caps()`, rendered as a warm-red
  "locked off" zone on `NeedsGauge.gd`'s rings. Infection is currently
  the only condition using this.
- Time-skip correctness: `PlayerMedical.catch_up(hours)` and
  `apply_rest_bonus(hours)` are wired into BOTH the admin fast-forward
  cheat (`AdminMenu._on_fast_forward_pressed()`) and real sleep
  (`SleepOverlay._do_time_skip()`). This was a real bug fix mid-session —
  conditions used to silently not advance during any time-skip.

**HUD** (`StatusEffectIcon.gd`, `StatusEffectsContainer.gd`, `HUD.tscn`):
- Live percentage rings, Healed-fill overlay, Infection's genuine second
  concentric ring (rugged-bordered to match, touching the main ring, no
  gap).
- A dedicated `HUDRoot/MedicalEffects` vertical-stack container, separate
  from the ordinary status-effects triangle — left-aligned above the
  needs gauge, zig-zag stagger continues indefinitely (not just 3 slots),
  sized for ~10 simultaneous badges.
- The single consolidated Bleeding badge (shows only the worst-bleeding
  wound; every wound's own bleeding status is in its Open Wound tooltip).

**Items** (`scripts/world/items/Bandage.gd`/`Antibiotics.gd`/`Splint.gd`/
`TraumaKit.gd`, matching `.tscn` scenes):
- All four are real `PickupableItem`s — pickup/drop/store (F/E/G), light-
  item storage groups (`inventory_item` + `basket_storable`).
- **Bandage**: 2 charges, stops Bleeding, destroyed at 0 charges.
- **Antibiotics**: 2 charges, dual preventative/curative role, becomes a
  persistent "Empty Bottle" at 0 charges (FoodCan-style, NOT destroyed).
- **Splint**: 1 charge, splints Fractured only (never Broken), destroyed
  on use.
- **Trauma Kit**: 1 charge, **no submenu at all** — E immediately treats
  every active Bleeding wound and every active Fracture at once, then
  destroys itself regardless of outcome. Deliberately open-ended — see
  "Trauma Kit" in README.md's Item roles table.
- **Injury-selection submenu**: reuses `InteractPrompt`'s existing world-
  space rendering (NOT `ControllerUINavigation`) — keyboard 1-9,
  controller D-pad+A with a theme-blue highlighted line
  (`UI/colors/accent_toggle`). Lives in `InteractionSystem.gd`.
- **Research Station chute**: `get_research_yield() -> Dictionary`
  extends the old single-material `get_trash_material()` contract
  (checked first, old contract untouched for every pre-Medical item).
  All four items' yields are implemented per the table in README.md.

**F7 debug menu** (`AdminMenu.gd`, `MEDICAL` section): every condition
spawnable, every item spawnable, force-infect/escalate/break, sleep
simulation, print-state — all calling the exact same functions real
gameplay uses.

## What's NOT built yet
- Chronic/cumulative conditions (sleep neglect, etc.) — zero code.
- Real gameplay triggers — every condition is still F7-spawned only.
  Nothing in the actual game (combat, cooking, hazardous breakers) causes
  an injury yet.
- The deep-dive Status Screen (Layer 3) — not designed or scaffolded.
- NPC-side port — Medical owns this per README.md's "NPC scope," not
  started.
- **Body-part-differentiated symptom effects** — see below. This is the
  freshest design decision and is NOT in the code OR in README.md yet.

---

## YOUR FIRST TASK — do this before anything else

Brannon's explicit instruction: implement the body-part-differentiated
symptom system below, and make sure **every active effect on the player
is clearly communicated in the hover tooltip** (and, later, the Status
Screen) — the player must always be able to see exactly what's happening
to them and which specific injury is causing it. Concrete target format,
Brannon's own examples: `"0.25x Movement Speed"`, `"0.5x Stamina Drain
(While Carrying)"`, `"0.75x Stamina Drain (While Sprinting)"`.

### The design (locked Aug 2026, not yet in README.md — put it there)

Symptom effects now differ by **which body part** a condition sits on,
replacing the current flat "every condition's `speed_mult` multiplies
into one global number regardless of body part" behavior:

- **Legs** (Fractured/Broken/Burn on `LEFT_LEG`/`RIGHT_LEG`):
  - Reduce movement speed (this part already exists — `speed_mult` is
    already read globally; it just needs to become leg-specific).
  - **New:** exponentially increase stamina drain while sprinting,
    scaled by the condition's severity.
- **Arms** (Fractured/Broken/Burn on `LEFT_ARM`/`RIGHT_ARM`):
  - **Does NOT affect movement speed at all.**
  - **New:** exponentially increase stamina drain while carrying HEAVY
    objects, scaled by severity.
  - **New:** negatively impacts work speed (see "Work speed is blocked
    on a dependency" below).
  - **Explicitly does NOT affect which objects can be carried** — no
    carry-capacity gating, ever, per this design. Don't populate
    `carry_capacity_mult` for this.
- **Torso / Head:** explicitly deferred — "we'll address later," per
  Brannon directly. Conditions can still occur there (Open Wound/Burn can
  be spawned on any body part today); they should simply carry no
  movement/stamina/work-speed effect until this gets designed, same as
  today.
- **Infection is the one exception to "body part determines the
  category":** it's systemic, not localized. Regardless of which body
  part the underlying Open Wound is on, Infection contributes to **all
  four** effects at once — movement speed, sprint-stamina-drain, carry-
  stamina-drain, AND work speed. Don't gate any of Infection's effects by
  body part.
- **Bleeding and plain (uninfected) Open Wound currently have zero
  symptom effect of their own** — this was already true before this
  session and nobody has asked to change it. Don't invent an effect for
  either; leave them as pure HP-drain/no-effect respectively unless
  explicitly asked.

### Work speed is blocked on a dependency

`MedicalCondition.work_speed_mult` already exists as a field (from the
original data-model sketch) but has never been read anywhere — because
**work speed itself doesn't exist as a game mechanic yet.** This isn't
Medical's gap to fill; some other system needs to define what "work
speed" governs (crafting? interacting? both?) before this multiplier
means anything. Populate the field correctly on Arm/Infection conditions
regardless — just don't expect it to visibly do anything until that
dependency lands, and say so plainly in the tooltip work rather than
pretending it's live.

### Heavy-carry stamina drain is also a dependency, but a lighter one

The *base* mechanic — carrying heavy items causes ongoing stamina drain
at all — was already locked in README.md's "Planned future extensions"
before this session, and still doesn't exist. Arm/Infection's carry-
stamina-drain multiplier should be built and ready (a real aggregation
function, correct math), but it has nothing to multiply until that base
mechanic exists. Same situation as work speed — build the multiplier
side now, wire it in once the base exists.

### Concrete implementation steps

1. **`MedicalCondition.gd`**: the single generic `stamina_drain_mult`
   field isn't enough anymore — a condition might need to contribute to
   sprint-drain and carry-drain independently (Infection does both at
   once). Add distinct fields, e.g. `stamina_drain_mult_sprint` and
   `stamina_drain_mult_carry` (naming is yours), both defaulting to 1.0.
   Keep `work_speed_mult` (already exists, currently unused).
2. **`PlayerMedical.gd`** tick functions for Fractured/Broken/Burn: branch
   on `condition.body_part`. Leg → set `speed_mult` (as today) AND
   `stamina_drain_mult_sprint` (new, exponential curve vs. severity, e.g.
   something like `lerp(1.0, MAX_MULT, (severity/100)^2)` — placeholder
   shape, tune during playtesting like every other Medical constant). Arm
   → leave `speed_mult` at 1.0, set `stamina_drain_mult_carry` (same
   exponential shape) and `work_speed_mult`. Torso/Head → leave everything
   at 1.0 for now.
3. **`_tick_infection()`**: unconditionally set all four — `speed_mult`,
   `stamina_drain_mult_sprint`, `stamina_drain_mult_carry`,
   `work_speed_mult` — regardless of the wound's body part.
4. Add aggregation functions on `PlayerMedical.gd` mirroring the existing
   `get_medical_speed_multiplier()`: `get_medical_sprint_stamina_drain_
   multiplier()` and `get_medical_carry_stamina_drain_multiplier()`.
5. Wire `get_medical_sprint_stamina_drain_multiplier()` into `Player.gd`'s
   existing sprint-stamina-drain line (`stamina -= sprint_stamina_drain *
   delta`) — this one's real and should visibly do something today. Leave
   the carry-drain and work-speed multipliers unwired in gameplay (no base
   mechanic to attach to yet) but fully correct and ready.
6. **Rewrite `PlayerMedical._tooltip_for()`** (and the Bleeding-badge
   tooltip path) so every condition's tooltip lists every currently
   non-1.0 effect it contributes, in Brannon's exact display shape:
   `"0.25x Movement Speed"`, `"0.5x Stamina Drain (While Carrying)"`,
   `"0.75x Stamina Drain (While Sprinting)"`. A condition with no active
   effect (Bleeding, plain Open Wound) shows none of these lines — don't
   pad with "1.0x" no-op lines. The tooltip's existing body-part-labeled
   header (e.g. "Fractured (Left Leg)") already makes the causal source
   clear; keep that.
7. **Update `docs/systems/medical/README.md`**: add this whole system as
   its own real section (not buried in a footnote), and update the "Data
   model (sketch)" section to reflect the split stamina-drain fields.
   This doc must never fall behind the code again — update it as part of
   the same change, not after.
8. Not required for this first task, but keep in mind: once the Status
   Screen (Layer 3) gets built, it needs this exact same effect list per
   limb — design that surface with this data shape in mind rather than
   inventing a second way to describe the same thing.

---

## Full session history (condensed, for context you can't get from the code alone)

This is the order things actually happened in, including reversals — useful
for understanding *why* something is shaped the way it is, not just what
it does.

1. **Original brainstorm**: broken bones/diseases/infections, explicitly
   avoiding pure random-chance injuries, inspired partly by RimWorld
   (compared and deliberately diverged from its randomness).
2. **Core mechanics locked**: the "randomness principle" (reason always
   clear, only parameters/magnitudes get bounded randomness — this
   replaced an earlier, more rigid boundary framework that kept needing
   patches). The severity/Healed-ring model (Healed fill shares the
   severity ring's track, converges toward but never past its edge) came
   from a multi-round back-and-forth about ring visuals — don't reinvent
   this, it's settled.
3. **Design pillars** written, explicitly marked as "written too early" by
   Brannon at one point, then rewritten once the design had actually been
   tested against real ideas. The current 8 pillars in README.md are the
   settled version.
4. **NPC scope decision**: Medical owns the full NPC-side port (triggering,
   severity, symptoms) even though NPC *behavior*/decision-making is a
   different system's job — an explicit, deliberate exception to normal
   scope boundaries, "consistency > clean agent turf." NPC work has not
   started.
5. **Implementation began**: Pass 0 (foundation) → Pass 1 (Open Wound/
   Bleeding/HUD) → Pass 2 (Infection/Fracture/Broken/needs-cap) → Burns →
   a real bug fix (time-skips silently not advancing conditions — fixed
   via `catch_up()`/`apply_rest_bonus()`) → needs-cap HUD rendering →
   items + submenu + controller support + Research Station chute
   integration.
6. **UI iteration on the medical HUD stack** took several rounds: initial
   placement (wrong — reused the ordinary status-effects area), corrected
   to a dedicated area above the needs gauge, corrected again for exact
   left-alignment, zig-zag pattern extended past 3 slots, Infection ring
   visual polish (rugged borders, zero gap, touching the main ring).
7. **Items pass**: built Bandage first as the reference, tested, then
   corrected several things (submenu detail line format, use-prompt
   wording, per-item destroy-vs-persist behavior, controller highlight
   color pulled from the real theme) before copying the pattern to the
   other three. Trauma Kit's design changed **entirely** mid-session — it
   was originally meant to use the same submenu as the others; Brannon
   redirected it to a submenu-free mass-apply action once it became clear
   Trauma Kit doesn't have enough distinct purpose yet (no serious-injury
   content like gunshots/chronic disease exists to justify more).
8. **Research Station chute**: had to genuinely extend
   `ResearchStation.gd`'s feed contract (the old one only supported one
   material at a fixed quantity of 1) — added `get_research_yield()` as a
   strictly more expressive alternative, checked first, old contract
   untouched for every other item in the game.
9. **This handover**: triggered by body-part-differentiated symptom
   effects being locked in, plus a general "outline the whole player-
   effects picture" request that surfaced a real gap (README.md implied
   Infection reduces speed; the code never actually did that). Session
   judged too bloated to keep extending — hence this document.

## Known process notes worth carrying forward
- **Godot MCP validator flakiness**: `godot:script-create`/`script-update`
  can reject genuinely valid code with a generic ParseError, sometimes
  even rejecting content that just succeeded moments earlier unchanged.
  Workaround: write the file via the filesystem tool directly, then
  validate separately with `godot:script-validate` (reliable) and
  reimport with `godot:filesystem-reimport`. This is also recorded in
  project memory (`/areas/bunker-game.md`).
- **Every debug F7 button must call the same function real gameplay
  uses** — never a separate debug-only code path. This has held for
  every condition and item so far; keep it that way.
- **Update README.md in the same change that changes behavior**, not as
  an afterthought — it fell behind at least once already this session
  (the Infection-speed gap this handover exists partly to fix).
- Brannon corrects design decisions mid-stream often (charge counts,
  Trauma Kit's whole mechanic, controller highlight color, HUD
  positioning) — when a correction arrives, check whether it invalidates
  something already written into README.md and fix that in the same
  turn, not just the code.
