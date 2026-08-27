# Medical System — Implementation Plan (All Passes)

**Read `docs/systems/medical/README.md` in full before this plan, and keep
it open while implementing.** That doc is the design source of truth —
mechanics, numbers, and reasoning. This plan is the *build order* and
*concrete file-level instructions* on top of it. If anything here seems to
contradict that doc, the doc wins — flag it rather than guessing.

**Read `docs/systems/player/README.md`, `docs/systems/npc/README.md`, and
`docs/systems/ui/README.md` before starting** — this system touches
`PlayerStats.gd`, `Player.gd`, `NPC.gd`, `StatusEffectsContainer.gd`/
`StatusEffectIcon.gd`, and `NeedsGauge.gd`, all of which already have real
conventions you need to follow (typed refs, no string-dispatch, the
`_owner` back-reference pattern, etc. — see each doc's "Forbidden edits"
section where present).

Each pass below assumes the previous pass is implemented and working.
Don't skip ahead — later passes depend on earlier plumbing existing.

---

## Pass 0 — Shared foundation (do this once, before any condition)

This is the scaffolding every subsequent pass builds on. Get it right once
rather than growing it ad hoc per-condition.

### 0.1 — `MedicalCondition` resource
New file: `scripts/player/medical/MedicalCondition.gd` (new `medical/`
subfolder under `scripts/player/` — this will also hold the aggregation
component in 0.2; NPC-side wiring in Pass 5 reuses this same resource
class rather than duplicating it).

```gdscript
class_name MedicalCondition
extends Resource

enum SeverityMode { LIVE_BIDIRECTIONAL, LIVE_ONE_DIRECTIONAL, PINNED_MAX }
enum Category { INJURY, ILLNESS }

@export var id: String                      ## e.g. "open_wound", "bleeding", "fractured"
@export var category: Category
@export var body_part: String                ## see 0.3 for the enum this should become
@export var severity_mode: SeverityMode
@export var severity: float = 0.0             ## 0-100
@export var starting_severity_min: float = 0.0
@export var starting_severity_max: float = 0.0 ## if min==max, fixed starting value

@export var has_heal_ring: bool = false
var heal_progress: float = 0.0                 ## 0-100, NOT exported (runtime state)
var heal_time_target_hours: float = 0.0        ## recomputed on severity change if live severity

## Dampening/hastening multipliers applied to heal_progress accrual rate.
## Keys are condition-specific strings checked by whoever owns this
## condition (e.g. "bleeding_active", "infection_active", "splinted").
var heal_rate_modifiers: Dictionary = {}

## symptom modifiers — all default to 1.0 (no effect) / 0.0 (no HP drain)
@export var speed_mult: float = 1.0
@export var stamina_drain_mult: float = 1.0
@export var carry_capacity_mult: float = 1.0
@export var work_speed_mult: float = 1.0
@export var hp_drain_per_second: float = 0.0    ## Bleeding uses this, scaled by severity

## needs_cap_modifiers: { "hunger": Curve, "water": Curve, "sleep": Curve }
## or simpler: a flat dict of severity-breakpoints -> per-need % reduction.
## Only Infection uses this in Pass 3 — leave empty dict elsewhere.
var needs_cap_modifiers: Dictionary = {}

## Set when this condition converts to another at 100% severity
## (e.g. Fractured -> Broken). Empty string = no conversion.
@export var converts_to_id: String = ""

var is_treated: bool = false   ## generic "has the right item been applied" flag;
                                ## exact meaning is condition-specific (see each pass)
```

Don't over-build this in Pass 1 — only wire the fields Pass 1 actually
uses (`id`, `category`, `body_part`, `severity_mode`, `severity`,
`starting_severity_min/max`, `has_heal_ring`, `heal_progress`,
`heal_time_target_hours`, `heal_rate_modifiers`, `speed_mult`,
`hp_drain_per_second`). Leave `needs_cap_modifiers` and `converts_to_id`
present but unused until Pass 3/2 respectively — they're on the resource
now specifically so later passes don't need a data-model migration.

### 0.2 — `PlayerMedical` component
New file: `scripts/player/medical/PlayerMedical.gd`. Mirrors the shape of
`NPC.gd`'s status aggregation (`get_status_speed_multiplier()`,
`get_status_labels()` — read that section of `NPC.gd` before writing
this, don't reinvent the pattern).

```gdscript
class_name PlayerMedical
extends Node

signal condition_added(condition: MedicalCondition)
signal condition_removed(condition: MedicalCondition)
signal condition_changed(condition: MedicalCondition)  ## severity/heal_progress ticked

var active_conditions: Array[MedicalCondition] = []

func _ready() -> void:
    add_to_group("player_medical")

func _process(delta: float) -> void:
    # Tick every active condition's heal_progress / severity per its rules.
    # Pass 1 only implements Open Wound + Bleeding ticking (see 1.x below);
    # later passes add their own condition-specific tick logic here,
    # dispatched by condition.id or a small per-condition script/strategy —
    # your call on exact dispatch shape, just don't let this function grow
    # into a giant if/elif chain as more conditions are added. Consider a
    # dictionary of id -> Callable registered by each condition's own
    # setup code, or a virtual method the condition itself exposes.
    pass

func get_medical_speed_multiplier() -> float:
    var mult: float = 1.0
    for c in active_conditions:
        mult *= c.speed_mult
    return mult

func get_medical_status_labels() -> Array[String]:
    # Same spirit as NPC.get_status_labels() — human-readable summary.
    # Pass 1: just "Open Wound (Left Arm)" / "Bleeding (Left Arm, 12%)" etc.
    var labels: Array[String] = []
    for c in active_conditions:
        labels.append("%s (%s)" % [c.id.capitalize(), c.body_part])
    return labels

func add_condition(condition: MedicalCondition) -> void:
    active_conditions.append(condition)
    condition_added.emit(condition)

func remove_condition(condition: MedicalCondition) -> void:
    active_conditions.erase(condition)
    condition_removed.emit(condition)

func get_conditions_for_body_part(body_part: String) -> Array[MedicalCondition]:
    return active_conditions.filter(func(c): return c.body_part == body_part)

func get_condition_by_id_and_part(id: String, body_part: String) -> MedicalCondition:
    for c in active_conditions:
        if c.id == id and c.body_part == body_part:
            return c
    return null
```

Attach this the same way `PlayerStats` is attached to the Player scene
(`res://scenes/player/Player.tscn`) — a sibling `Node` with this script,
added to the `"player_medical"` group so other systems can find it via
`get_tree().get_first_node_in_group("player_medical")`, matching the
project's established typed-group-lookup convention (see `PowerManager`'s
`"power_manager"` group for the pattern).

### 0.3 — Body part enum
Add a shared enum — put it on `MedicalCondition.gd` itself as a
static/const, or a tiny standalone `BodyPart.gd` autoload/const file if
other systems will eventually need it too (your call, but don't duplicate
the string literals across files):

```gdscript
enum BodyPart { HEAD, TORSO, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }
```

Use this enum (or its string name via `BodyPart.keys()[value]`) everywhere
a body part is stored/compared — don't use raw strings scattered across
files, that's exactly the kind of thing that causes silent mismatches
later (`"left_arm"` vs `"Left Arm"` vs `"LeftArm"`).

### 0.4 — Wire `get_medical_speed_multiplier()` into `Player.gd`
In `Player.gd`'s `_handle_movement()`, where `target_speed` is computed
(currently `sprint_speed if _is_sprinting else move_speed`), multiply by
`PlayerMedical.get_medical_speed_multiplier()` if a `PlayerMedical` node
is present. Resolve the reference the same way `Player.gd` already
resolves other sibling nodes (`@onready var` + group lookup, or direct
child reference — match whatever pattern `PlayerStats` uses on this
scene). Do this now, in Pass 0, even though Pass 1's conditions won't set
`speed_mult` away from 1.0 yet — it means Pass 1 can immediately prove the
whole pipeline end-to-end the moment a condition sets a real multiplier.

---

## Pass 1 — Open Wound + Bleeding (player-only)

Goal: prove the two foundational ring behaviors (pinned-severity +
Healed-ring overlay, and live-bidirectional single ring) with the
simplest possible conditions. No real item objects yet, no NPC wiring, no
Infection, no Fracture.

### 1.1 — Open Wound condition logic
Add to `PlayerMedical.gd` (or a small helper it calls):

```gdscript
func spawn_open_wound(body_part: String) -> void:
    var wound := MedicalCondition.new()
    wound.id = "open_wound"
    wound.category = MedicalCondition.Category.INJURY
    wound.body_part = body_part
    wound.severity_mode = MedicalCondition.SeverityMode.PINNED_MAX
    wound.severity = 100.0
    wound.has_heal_ring = true
    wound.heal_time_target_hours = randf_range(48.0, 72.0)  ## 2-3 game days
    add_condition(wound)

    ## 66% chance to also spawn Bleeding on the same body part — one-time
    ## roll at creation, per docs/systems/medical/README.md.
    if randf() < 0.66:
        spawn_bleeding(body_part)
```

`heal_progress` ticks up in `_process()` at a rate of
`(delta_hours / heal_time_target_hours) * 100.0`, converted through
whatever the project's real-seconds-per-game-hour value is — reuse
`PlayerStats._seconds_per_game_hour` (read it via the `PlayerStats`
singleton reference, don't duplicate the constant) so Medical's time math
stays in lockstep with the rest of the game's clock.

When `heal_progress >= wound.severity` (per the doc: Healed fill converges
toward, never past, the severity fill — for a pinned condition at 100%
severity, that means `heal_progress >= 100.0`), the Open Wound resolves:
call `remove_condition(wound)`. This is the Pass-1 stand-in for
"spontaneous clearing" — Infection isn't implemented yet, so every Open
Wound in this pass just heals.

### 1.2 — Bleeding condition logic

```gdscript
func spawn_bleeding(body_part: String) -> void:
    var bleed := MedicalCondition.new()
    bleed.id = "bleeding"
    bleed.category = MedicalCondition.Category.INJURY
    bleed.body_part = body_part
    bleed.severity_mode = MedicalCondition.SeverityMode.LIVE_BIDIRECTIONAL
    bleed.severity = randf_range(1.0, 15.0)
    bleed.has_heal_ring = false   ## per doc — subsystem conditions don't get one
    add_condition(bleed)
```

In `_process()`, while untreated, climb `bleed.severity` toward 100 over
roughly 2 in-game days (fixed exponential curve — exact shape is a Pass-1
tuning decision; a simple `severity += k * severity * delta_hours` gives
you the "slow at low severity, fast near 100" exponential shape the doc
describes; tune `k` so ~48 game-hours gets a low-starting wound close to
100). Set `bleed.hp_drain_per_second` as a function of current severity
(low severity ≈ 10 HP/day equivalent, scaling up sharply near 100 — same
exponential relationship). Apply that drain to `PlayerStats.health` via
its existing `health -= ...; health_changed.emit(health)` pattern — don't
bypass `PlayerStats`' own signal emission, other systems (HUD) depend on
that signal firing.

**Bandage stub (not a real item yet):** a single function,
`treat_bleeding(body_part: String) -> void`, that finds the active
`"bleeding"` condition on that body part and calls `remove_condition()` on
it immediately. This is what the F7 debug button and (eventually) the
real Bandage item will both call.

### 1.3 — HUD: extend `StatusEffectsContainer`/`StatusEffectIcon`
Read `scripts/ui/hud/StatusEffectIcon.gd` and `StatusEffectsContainer.gd`
in full first — they're small (~70 and ~85 lines respectively per
`docs/systems/ui/README.md`), so understand the existing `add_effect(id,
icon, duration, ring_color)`/`remove_effect(id)` shape before changing it.

Needed extensions:
- A **live percentage fill** mode, separate from the existing
  duration-countdown mode — `StatusEffectIcon` needs to be able to render
  an arc from 0–360° driven by a `0.0–1.0` fraction that Medical updates
  every tick (via `condition_changed` signal from `PlayerMedical`), not a
  fixed timer counting down on its own.
- A **Healed-fill overlay**: a second color drawn on the *same* ring arc,
  from a separate `0.0–1.0` fraction, capped so it never visually exceeds
  the severity fraction. Concretely: if severity fraction is 1.0 (pinned)
  and heal fraction is 0.4, draw 40% of the full circle in the Healed
  color and the remaining 60% in the severity color. If severity fraction
  is 0.4 (a live condition below 100%) and heal fraction (relative to that
  0.4) is 0.4, draw 16% of the full circle (0.4 × 0.4) in Healed color,
  24% in severity color, and the remaining 60% stays empty/background.
- `StatusEffectsContainer` needs to accept multiple simultaneous icons
  without layout breaking — verify it currently does (it may already,
  since it's presumably a simple `HBoxContainer`/`GridContainer` of
  children; just confirm before assuming).
- A hover tooltip on `StatusEffectIcon` (may not exist yet — check) that
  shows: condition name + body part, current severity %, and (if
  `has_heal_ring`) "Time Left" computed from
  `(severity - heal_progress) / severity * heal_time_target_hours`
  converted to a display string, or "Bleeding: X HP/sec" for the Bleeding
  icon specifically.

This is real UI work, not a stub — budget real time for it, since every
later pass depends on this rendering path working correctly.

### 1.4 — F7 debug menu: "MEDICAL" section
In `scripts/ui/menus/AdminMenu.gd`, add a new section to the `_sections`
array (in `_ready()`, alongside `POWER`/`TIME`/`WATER`/etc. — follow the
exact `{ "name": "MEDICAL", "rows": [...] }` pattern already used for
every other section). Add a `_get_player_medical() -> PlayerMedical`
helper mirroring `_get_player_stats()`/`_get_status_effects()`.

Pass 1 rows (add more per condition in later passes — see each pass's own
"F7 additions" subsection below, all landing in this same `"MEDICAL"`
section):

```gdscript
{ "name": "MEDICAL", "rows": [
    ["Spawn Open Wound (Left Arm)",  _on_spawn_wound_left_arm_pressed],
    ["Spawn Open Wound (Right Arm)", _on_spawn_wound_right_arm_pressed],
    ["Spawn Open Wound (Left Leg)",  _on_spawn_wound_left_leg_pressed],
    ["Spawn Open Wound (Right Leg)", _on_spawn_wound_right_leg_pressed],
    ["Spawn Open Wound (Torso)",     _on_spawn_wound_torso_pressed],
    ["Spawn Open Wound (Head)",      _on_spawn_wound_head_pressed],
    ["Force-Bandage All Bleeding",   _on_force_bandage_all_pressed],
    ["Clear All Medical Conditions", _on_clear_all_medical_pressed],
    ["Print Medical Debug State",    _on_print_medical_debug_pressed],
]},
```

Each `_on_spawn_wound_*_pressed()` calls
`_get_player_medical().spawn_open_wound(BodyPart.LEFT_ARM)` (etc.) — note
this deliberately does **not** roll the 66% Bleeding chance differently
for testing purposes; that's the real behavior, and it's fine for a debug
button to sometimes produce a bleeding wound and sometimes not, matching
actual gameplay. If you want a way to guarantee a bleeding wound for
testing, add a *separate* row ("Spawn Open Wound + Bleeding (Guaranteed)")
that calls `spawn_open_wound()` then explicitly `spawn_bleeding()` if the
roll didn't happen — don't change the underlying function's odds.

`_on_print_medical_debug_pressed()` should `print()` every active
condition's id, body part, severity, heal_progress, and heal_time_target —
this is your primary tool for verifying the tick math is doing what you
expect without needing to watch the HUD.

**Don't build a body-part picker sub-UI for Pass 1** — one row per body
part per action is fine at this scale (6 body parts × a handful of
actions). If this becomes unwieldy in later passes as more conditions are
added, consider collapsing to a single "Spawn [Condition]" row that always
targets a fixed test body part (e.g. always Left Arm), and rely on the
per-part rows only for the conditions where part actually matters for
testing (Fracture's arm-vs-leg symptom difference, for instance). Use your
judgment once you see how many rows this grows to — don't over-engineer a
picker UI for a debug menu.

### 1.5 — What NOT to build in Pass 1
No real Bandage item/inventory entry. No Infection. No Fracture. No NPC
wiring. No real injury-cause triggers (over-exertion, hazards) — conditions
only come from the F7 debug buttons in this pass. No deep-dive status
screen. All of this is later passes, listed below.

---

## Pass 2 — Infection + Fracture (player-only, independent of each other)

Both build directly on Pass 1's foundation. Can be done in either order,
or in parallel if two people are working on this — they don't depend on
each other, only on Pass 0/1.

### 2A — Infection (extends Open Wound)

**2A.1 — Data:** Open Wound needs two new runtime fields (add to
`MedicalCondition.gd` or track alongside the wound in `PlayerMedical`,
your call): `infection_roll_elapsed_hours: float` and
`is_infected: bool`. While `!is_infected` and the wound is still active,
accumulate `infection_roll_elapsed_hours` each tick and roll infection
odds against the rising hazard curve described in the doc (~80%
cumulative by 72 game-hours, low at first, exponential rise) — implement
as a per-tick probability check whose instantaneous chance increases with
elapsed time, not a single roll at creation. Antibiotics (2A.3) reduce
this roll's odds when applied preventatively.

**2A.2 — On infection:** don't create a new `MedicalCondition` — per the
doc, Infection is a **modifier on the same Open Wound instance**. Add
`infection_severity: float` to the wound's tracked state (starts low,
climbs at a fixed rate while `is_infected` and untreated), and change its
displayed label to "Open Wound (Infected)". The wound's own `heal_progress`
accrual rate now also checks `is_infected` as one of the two dampening
conditions (the other being active Bleeding, already in Pass 1) —
multiply the accrual rate by a heavy dampening factor (e.g. `0.1`, tune to
taste — "nearly imperceptible" per the doc, not literally zero) whenever
either is true.

**2A.3 — Antibiotics stub:** `treat_infection_or_prevent(body_part:
String) -> void` — if the wound at that body part isn't infected, reduces/
zeroes its infection-roll odds going forward (`is_treated_preventatively =
true` flag, checked in 2A.1's roll). If it is infected, flips
`infection_severity`'s trend from rising to falling (a `bool
infection_being_treated` flag the tick logic checks).

**2A.4 — Needs cap reduction:** this is the first (and, for now, only)
consumer of `needs_cap_modifiers`. This requires the real
`PlayerStats.gd` extension work — **flag this to Brannon before starting**
if it's not already done, since it's a genuine change to `PlayerStats`'
clamping behavior (`replenish_food`/`_tick_needs` currently hardcode
`100.0`). Add a `food_cap`/`water_cap`/`sleep_cap` float (default `100.0`)
to `PlayerStats`, use it everywhere the code currently clamps to the
literal `100.0`, and expose a setter Medical can call
(`set_food_cap(value)` etc.) or, cleaner, have `PlayerStats` expose the
caps as public vars and have `PlayerMedical` write to them directly each
tick based on the worst active `needs_cap_modifiers` across all
conditions (in case more than one condition contributes later — always
take the most restrictive cap per need, don't just overwrite). Implement
the proportional curve from the doc's table (sleep hit hardest, water
next, hunger least) as a simple lerp/curve keyed on `infection_severity`.

**2A.5 — HUD:** the second, separate concentric ring around the Open
Wound icon specifically for `infection_severity` (live, bidirectional,
same fill-arc logic as Bleeding's ring in Pass 1, just drawn as a second
ring layer rather than the icon's only ring). Extend `NeedsGauge.gd`'s
`set_food/water/sleep(frac)` calls (or add new setters) to also accept/
render the current cap as a greyed-out portion at the top of the bar —
read `docs/systems/ui/README.md`'s `NeedsGauge` entry before touching
this file.

**2A.6 — F7 additions** (same `"MEDICAL"` section):
```gdscript
["Force-Infect Nearest Open Wound",     _on_force_infect_pressed],
["Infection Severity +20 (all)",        _on_infection_sev_up_pressed],
["Infection Severity -20 (all)",        _on_infection_sev_down_pressed],
["Force-Cure All Infections",           _on_force_cure_infection_pressed],
```

### 2B — Fracture / Broken

**2B.1 — Fractured condition:**
```gdscript
func spawn_fractured(body_part: String) -> void:
    var frac := MedicalCondition.new()
    frac.id = "fractured"
    frac.category = MedicalCondition.Category.INJURY
    frac.body_part = body_part
    frac.severity_mode = MedicalCondition.SeverityMode.LIVE_ONE_DIRECTIONAL
    frac.severity = randf_range(15.0, 25.0)
    frac.has_heal_ring = true
    frac.speed_mult = 0.9   ## tune — "minor" penalty at low severity, should scale
                             ## with severity in the tick logic, not be a flat constant
    frac.heal_time_target_hours = _fracture_heal_time_for_severity(frac.severity)
    frac.converts_to_id = "broken"
    add_condition(frac)

func _fracture_heal_time_for_severity(severity: float) -> float:
    # ~15% -> ~60hrs (2.5 days baseline), ~90% -> ~240hrs (10 days).
    # Simple lerp is fine for Pass 2; revisit if it doesn't feel right in testing.
    return lerp(60.0, 240.0, (severity - 15.0) / (100.0 - 15.0))
```

**2B.2 — Escalation trigger:** hook into `Player.gd`'s existing
stamina-exhaustion detection (the `_sprint_locked = true` branch in
`_handle_movement()` is the existing "player is at 0 stamina" signal —
reuse it, don't build a parallel exertion detector). While
`_sprint_locked` is true (or on the transition into it — decide based on
testing which feels more "sustained over-exertion" rather than a single
frame spike) **and** the entity has an active Fractured condition on a
relevant body part (legs for now, since sprint/stamina is leg-driven —
extend to arms later if a carry-weight exertion trigger gets built), roll
a bounded random severity bump (`randf_range(10.0, 25.0)`), apply it,
recompute `heal_time_target_hours` via `_fracture_heal_time_for_severity()`
again, and set back `heal_progress` by some fraction (tune — e.g.
`heal_progress *= 0.7`, "a real setback" per the doc, not a full reset).
If `severity >= 100.0` after this, convert to Broken (2B.4).

Add a per-condition cooldown so a single sustained 0-stamina period
doesn't trigger the escalation roll every single frame — e.g. only allow
one escalation roll per continuous 0-stamina "episode" (reset the
eligibility flag once stamina recovers above the sprint-recovery
threshold, matching `Player.gd`'s existing `sprint_recover_threshold`
logic).

**2B.3 — Splint stub:** `apply_splint(body_part: String) -> void` sets
`is_treated = true` on the Fractured condition there. While
`is_treated`, apply a `heal_rate_modifiers["splinted"] = <hastening
multiplier>` (tune — "dramatically speeds up," try something like `5.0`–
`10.0`× the unsplinted rate) and reduce `speed_mult`'s penalty (splinting
"reduces symptom penalties while worn" per the doc — e.g. halve whatever
the current speed penalty is while splinted). Splinting does **not**
prevent 2B.2's escalation check from still firing.

**2B.4 — Broken conversion:**
```gdscript
func _convert_fractured_to_broken(frac: MedicalCondition) -> void:
    remove_condition(frac)
    var broken := MedicalCondition.new()
    broken.id = "broken"
    broken.category = MedicalCondition.Category.INJURY
    broken.body_part = frac.body_part
    broken.severity_mode = MedicalCondition.SeverityMode.PINNED_MAX
    broken.severity = 100.0
    broken.has_heal_ring = true
    broken.heal_time_target_hours = 240.0  ## placeholder — Broken's exact
                                             ## symptoms/treatment aren't
                                             ## designed yet, see doc's
                                             ## Open Questions. Flag this
                                             ## to Brannon before Pass 2B
                                             ## ships if still undecided.
    add_condition(broken)
    # If frac.is_treated (was splinted), the splint is destroyed —
    # broken.is_treated starts false regardless of the fracture's prior state.
```

**Flag to Brannon before finishing 2B.4:** Broken's exact symptom
severity and treatment requirement are explicitly listed as an open
question in the design doc. The placeholder above (pinned 100%, a long
flat heal time, no special treatment beyond "heals slowly like everything
else") is a reasonable stand-in but not a real design — don't treat it as
final without confirming.

**2B.5 — F7 additions:**
```gdscript
["Spawn Fractured (Left Leg)",   _on_spawn_fracture_left_leg_pressed],
["Spawn Fractured (Right Leg)",  _on_spawn_fracture_right_leg_pressed],
["Force Escalate Nearest Fracture", _on_force_escalate_fracture_pressed],
["Apply Splint to Nearest Fracture", _on_apply_splint_pressed],
["Force-Convert Nearest Fracture to Broken", _on_force_break_pressed],
```

---

## Pass 3 — NPC-side port

Per the design doc's "NPC scope" section: **Medical owns this entire
port** — the same condition triggering, severity/Healed-ring progression,
symptoms, and status that the player has, applied to NPCs. The
NPC-behavior side (`NPCBrain`/`JobBoard`) owns *deciding when to act* on
top of what you build here — that's explicitly not your job, don't build
prioritization logic, just make the data and status genuinely available
for that layer to consume later.

### 3.1 — `NPCMedical` (or extend `NPC.gd` directly)
Two viable approaches — read `NPC.gd` in full before deciding:
- **Option A:** a sibling `NPCMedical.gd` node attached to the NPC scene,
  essentially a copy of `PlayerMedical.gd`'s shape (same
  `active_conditions: Array[MedicalCondition]`, same `add_condition`/
  `remove_condition`, same tick logic). This keeps Medical's NPC-side code
  physically separate from `NPC.gd`'s existing ~2000+ lines.
  **Recommended**, since `NPC.gd` is already large and this avoids
  growing it further, and it mirrors `PlayerMedical` closely enough that
  the two are easy to keep in sync mentally.
- **Option B:** fold the same fields/methods directly into `NPC.gd`.
  Only do this if Option A turns out to fight the NPC scene's existing
  structure in some way you discover during implementation.

Either way: expose `get_medical_speed_multiplier()` on the NPC the same
shape as `PlayerMedical`'s, and **fold it into `NPC.gd`'s existing
`get_status_speed_multiplier()`** (multiply it in, alongside the
existing energy/hunger/thirst/mood multipliers already there) rather than
having two separate, uncombined speed-multiplier sources — `NPC.gd`'s
movement code should only ever need to call one function. Same for
`get_status_labels()` — merge Medical's condition labels into that
existing array rather than exposing a second, separate label list.

### 3.2 — Trigger wiring
NPCs need the same trigger conditions as the player (over-exertion causing
Fracture, the Open Wound spawn point, etc.). `NPC.gd` already tracks
`energy` (its stamina-equivalent) — find wherever it detects
energy-exhaustion (mirroring `Player.gd`'s `_sprint_locked` pattern) and
hook the same escalation logic from Pass 2B.2 there. Reuse the exact same
`MedicalCondition`-producing functions from `PlayerMedical`/2B — don't
duplicate the spawn/escalation logic, factor it into a shared
static/utility if it isn't already naturally shareable (e.g. a
`MedicalConditionFactory` static class both `PlayerMedical` and
`NPCMedical` call into, so tuning numbers only ever live in one place).

### 3.3 — What's explicitly NOT yours in this pass
- Deciding *when* an NPC should stop working to treat itself — that's
  `NPCBrain`/`JobBoard` scoring, a separate task for whoever owns that
  system (per the doc, this may eventually be you too if Brannon asks,
  but don't assume it for this pass unless told).
- Pathing to medical items.
- Tuning how severe a condition needs to be before it visibly affects NPC
  behavior beyond the speed multiplier already merged in 3.1.

### 3.4 — F7 additions
```gdscript
["Give Nearest NPC Open Wound",     _on_npc_spawn_wound_pressed],
["Give Nearest NPC Fracture",       _on_npc_spawn_fracture_pressed],
["Force-Infect Nearest NPC's Wound", _on_npc_force_infect_pressed],
["Clear All NPC Medical Conditions", _on_npc_clear_medical_pressed],
["Print Nearest NPC Medical Debug State", _on_npc_print_medical_debug_pressed],
```
Reuse `_nearest_npc_to_player()` — already exists in `AdminMenu.gd` (used
by the Snatch/Talk/Give force-action rows) — for target resolution.

---

## Pass 4 — Burns, Chronic Conditions, Trauma Kit, real items

### 4.1 — Burns (electrical + cooking)
Simplest remaining condition — pinned severity, Healed ring, no
subsystems, no escalation. Copy the Open Wound pattern from 1.1 almost
directly (pinned 100%, `has_heal_ring = true`, no infection/bleeding
sub-logic). Trigger points: hook into the cooking interaction and the
breaker/generator reset interaction per the doc's randomness rules (low
probability on cooking; probability scaled by `PowerManager`'s
`GridState` — `TRIPPED` near-zero, `OVERLOADED` meaningfully higher — on
breaker/generator reset). Read `docs/systems/power/README.md`'s
`GridState` section before wiring the power-side trigger; **flag to
whoever owns the power/cooking interaction code** before hooking into
their interaction handlers directly, since that's outside Medical's own
files.

F7: `["Spawn Electrical Burn (random part)", ...]`,
`["Spawn Cooking Burn (random part)", ...]`.

### 4.2 — Chronic conditions (player-only)
Hidden accrual counter (e.g. nights-under-rested) tracked on
`PlayerMedical` but **not** as a `MedicalCondition` instance while
building — it's explicitly meant to be invisible until it manifests. Once
a threshold is crossed, create a real `MedicalCondition` (pinned severity
+ Healed ring, same presentation as everything else) with a label that
lists contributing causes in parentheses, matching `NPC.gd`'s
`_forgetfulness_reasons()`/`get_status_labels()` pattern exactly — read
that code before writing this, don't invent a different format.

F7: since the whole point is a hidden counter, add a debug-only way to
*peek* at the current accrual value without it being visible in normal
play (`["Print Chronic Accrual Debug State", ...]`), plus a force-manifest
button (`["Force-Manifest Chronic Condition", ...]`) for testing without
waiting out real accrual.

### 4.3 — Real items (Bandage, Antibiotics, Splint, Trauma Kit)
This is the first pass that touches the inventory/item system rather than
using debug stubs. Read `docs/systems/ui/README.md`'s `InventoryManager`
section and whatever `docs/systems/*/README.md` covers item definitions
(check `farming`/`furniture-items` for the closest existing pattern to
follow) before starting — **this is likely to need collaboration with
whoever owns items/inventory**, flag it rather than guessing at
conventions. Each item's `use()`/interaction should call directly into
the same `PlayerMedical`/`NPCMedical` functions the F7 debug buttons
already call (`treat_bleeding()`, `treat_infection_or_prevent()`,
`apply_splint()`) — the debug buttons and the real items should share
the exact same underlying functions, never diverge.

Trauma Kit calls both `treat_bleeding()` and
`treat_infection_or_prevent()` in one action.

### 4.4 — Deep-dive Status Screen
Not scoped in detail here — this is genuinely undesigned UI work per the
doc's own "Open questions." Coordinate with whoever owns `scripts/ui/`
before starting; likely wants its own separate planning pass once Passes
1–3 are proven and there's a real body of conditions/data to design a
screen around.

---

## Cross-cutting notes for every pass

- **Tuning numbers throughout this plan are placeholders**, explicitly
  flagged where they appear. Playtest and adjust — don't treat any
  specific constant here as final.
- **Every debug F7 action must call the same underlying functions real
  gameplay will eventually call** — never write debug-only logic that
  bypasses `PlayerMedical`/`NPCMedical`'s real methods. The point of the
  F7 menu is testing the real system, not a parallel fake one.
- **Update `docs/systems/medical/README.md`'s "Open questions" section**
  as you resolve things during implementation — if a placeholder number
  or an undecided detail (like Broken's symptoms) gets a real answer
  during this work, that answer belongs back in the design doc, not just
  in code comments.
- If anything in this plan turns out to be wrong once you're actually
  implementing it (a signal doesn't exist where expected, a pattern
  doesn't fit the way described), that's expected — flag it plainly
  rather than silently working around it, per this project's Pillar 3
  spirit applied to the dev process itself.
