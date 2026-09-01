class_name MedicalCondition
extends Resource
## MedicalCondition.gd
## Data model for one active medical condition (injury/illness) on either
## the Player or an NPC. See docs/systems/medical/README.md for the full
## design — this resource is deliberately generic/entity-agnostic so both
## PlayerMedical.gd and (later) NPCMedical.gd can use the exact same class.
##
## Pass 0/1 (Aug 2026): only the fields Open Wound + Bleeding actually use
## are wired up by calling code right now. needs_cap_modifiers and
## converts_to_id exist on the resource already so later passes (Infection,
## Fracture->Broken) don't need a data-model migration — see
## plans/medical-system-implementation-plan.md.

## How a condition's severity behaves over time — see "Severity / progress
## model" in the design doc.
enum SeverityMode {
	LIVE_BIDIRECTIONAL,   ## rises while worsening, falls while treated (Bleeding, Infection)
	LIVE_ONE_DIRECTIONAL, ## only ever rises via escalation (Fractured)
	PINNED_MAX,           ## always 100 — binary present/absent (Open Wound, Broken, Burns)
}

enum Category { INJURY, ILLNESS }

## Coarse body-part set — see design doc's "Data model (sketch)". Keep this
## as the ONE place body parts are enumerated; don't use raw strings
## elsewhere for body_part comparisons.
enum BodyPart { HEAD, TORSO, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }

static func body_part_label(part: BodyPart) -> String:
	match part:
		BodyPart.HEAD:      return "Head"
		BodyPart.TORSO:     return "Torso"
		BodyPart.LEFT_ARM:  return "Left Arm"
		BodyPart.RIGHT_ARM: return "Right Arm"
		BodyPart.LEFT_LEG:  return "Left Leg"
		BodyPart.RIGHT_LEG: return "Right Leg"
	return "Unknown"

@export var id: String = ""                 ## e.g. "open_wound", "bleeding", "fractured"
@export var category: Category = Category.INJURY
@export var body_part: BodyPart = BodyPart.TORSO
@export var severity_mode: SeverityMode = SeverityMode.PINNED_MAX

@export var severity: float = 0.0            ## 0-100
@export var starting_severity_min: float = 0.0
@export var starting_severity_max: float = 0.0 ## if min == max, a fixed starting value

## Whether this condition tracks natural-healing progress on its own ring,
## separate from severity (see "Healing (the Healed ring)" in the design
## doc). True for every wound-tier condition; false for the subsystem
## conditions (Bleeding, Infection), whose own severity ring already
## represents both direction and magnitude.
@export var has_heal_ring: bool = false
var heal_progress: float = 0.0                 ## 0-100, runtime only — not exported
var heal_time_target_hours: float = 0.0        ## recomputed on severity change where relevant

## The heal-rate multiplier actually applied on the most recent tick (1.0
## normally; a splint-hasten constant when treated; a dampen constant for
## Open Wound while bleeding/infected — see each condition's own _tick_*()
## in PlayerMedical.gd). Aug 2026 — added so the "Time Left" tooltip
## calculation can divide by the CURRENT rate instead of silently assuming
## a flat 1.0x forever, which previously made a splinted Fracture/Broken's
## displayed time-left several times too long. Not meant to predict a
## future one-off rest bonus (see PlayerMedical.apply_rest_bonus()) — this
## is the sustained, steady-state rate only.
var current_heal_rate_mult: float = 1.0

## Dampening/hastening multipliers applied to heal_progress accrual rate.
## Keys are condition-specific strings checked by whichever tick logic
## owns this condition (e.g. "bleeding_active", "infection_active",
## "splinted"). A key's absence means "no modifier from that source" —
## treat missing as 1.0 (no effect), not 0.0.
var heal_rate_modifiers: Dictionary = {}

## Symptom modifiers. All default to "no effect."
## Body-part-differentiated (Aug 2026, see docs/systems/medical/README.md's
## "Body-part-differentiated symptom effects"): a condition on a leg sets
## speed_mult + stamina_drain_mult_sprint; a condition on an arm sets
## stamina_drain_mult_carry + work_speed_mult (never speed_mult); torso/head
## conditions leave all four at 1.0 (deferred). Infection is the one
## exception — systemic, sets all four regardless of the underlying wound's
## body part. The two stamina-drain fields are separate (not one shared
## field) specifically because Infection needs to contribute to both at
## once, while a limb injury only ever contributes to one.
@export var speed_mult: float = 1.0
@export var stamina_drain_mult_sprint: float = 1.0   ## while sprinting — legs, or Infection
@export var stamina_drain_mult_carry: float = 1.0    ## while carrying heavy — arms, or Infection
@export var carry_capacity_mult: float = 1.0
@export var work_speed_mult: float = 1.0
@export var hp_drain_per_second: float = 0.0    ## Bleeding sets this, scaled by severity

## needs_cap_modifiers: per-need dict, e.g. { "hunger": -5.0, "water": -10.0,
## "sleep": -15.0 } as a percentage reduction of that need's max, looked up/
## interpolated by severity by whichever system reads it. Only Infection
## uses this (Pass 2) — left empty everywhere else.
var needs_cap_modifiers: Dictionary = {}

## Short, human-readable cause for whichever needs_cap_modifiers this
## condition is currently contributing — e.g. "battling an infection".
## Aug 2026, Status Screen — set by whichever condition populates
## needs_cap_modifiers (currently only Infection, in PlayerMedical.
## _update_infection_needs_cap()) so PlayerMedical.get_needs_cap_reason_
## text() can build a plain-language explanation without hardcoding
## per-condition text outside the condition's own tick logic. Empty string
## when this condition isn't currently contributing a cap reduction.
var needs_cap_reason: String = ""

## If non-empty, the condition id this converts into at 100% severity
## (e.g. "fractured" -> "broken"). Empty = no conversion (resolves/removed
## instead, or is already a terminal pinned condition).
@export var converts_to_id: String = ""

## Generic "has the right item/action been applied" flag. Exact meaning is
## condition-specific — see each condition's own tick logic for how it's
## read (e.g. Open Wound: antibiotics applied — works preventatively or
## curatively depending on infection state; Fractured: splinted).
var is_treated: bool = false

## Cosmetic-only label for what caused this condition (e.g. "electrical"
## vs "cooking" for a Burn) — never read by any tick/severity logic, only
## surfaced in tooltips. Empty string = not set / not applicable.
var cause: String = ""

## Open Wound's infection sub-state (Aug 2026, Pass 2) — per
## docs/systems/medical/README.md, infection is a MODIFIER on the same
## Open Wound instance, not a separate condition. Unused by every other
## condition type.
var is_infected: bool = false
var infection_severity: float = 0.0             ## 0-100, live + bidirectional
var infection_roll_elapsed_hours: float = 0.0    ## drives the rising hazard-curve roll
var infection_resolved: bool = false             ## true once cured — no re-roll after this

## Rolls and applies this condition's randomized starting severity from
## starting_severity_min/max. Call once, right after construction, before
## adding the condition to an active_conditions list.
func roll_starting_severity() -> void:
	if starting_severity_min >= starting_severity_max:
		severity = starting_severity_min
	else:
		severity = randf_range(starting_severity_min, starting_severity_max)
