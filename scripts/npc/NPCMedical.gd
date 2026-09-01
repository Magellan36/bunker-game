extends Node
class_name NPCMedical
## NPCMedical.gd
## NPC-side Medical component (Aug 2026) — each NPC gets its own instance,
## fully individualized, exactly mirroring how PlayerMedical.gd is one
## per-player component, never shared. See
## docs/systems/medical/README.md for the full design this ports; see
## PlayerMedical.gd for the player-side sibling this is meant to stay
## synchronized with going forward, per Brannon's explicit instruction.
##
## SCOPE OF THIS PASS: the full six-condition catalog that's implemented
## for the player (Open Wound, Bleeding, Infection, Fractured, Broken,
## Burn) — same tick/heal/treatment logic, same tuning constants, same
## symptom-effect model. What did NOT come along this pass:
##   - Real gameplay TRIGGERS. NPCs have no sprint/heavy-carry-exhaustion
##     equivalent (no stamina system at all), so Fracture escalation has
##     no real trigger here yet — F7-spawned/escalated only, same as
##     where the player system itself started. The two new Burn triggers
##     (cooking, electrical) are also player-only for now — NPCs don't
##     currently perform those specific interactions autonomously.
##   - Chronic/cumulative conditions — player-only per the design doc.
##   - Illness triggers beyond wound-infection — blocked upstream (food
##     spoilage doesn't exist), same as the player side.
## All of this is real future work, not abandoned — see the design doc's
## own "keep the two synchronized" note.
##
## Attach to: one instance as a child of each NPC.tscn / NPC.gd instance
## (see NPC._ready()) — NOT a group-lookup singleton like PlayerMedical.
## Every NPC's active_conditions list, symptom state, and needs-cap
## contribution is entirely its own; nothing here is ever shared across
## NPCs.

signal condition_added(condition: MedicalCondition)
signal condition_removed(condition: MedicalCondition)

# ─── Tuning (mirrors PlayerMedical.gd's own constants exactly — see that
# file's comments for the full reasoning behind each; not re-derived here
# to avoid duplicating the same explanation twice). Keep these in sync by
# hand when PlayerMedical's own values get retuned. ────────────────────────
const BLEEDING_CLIMB_RATE: float = 0.06
const BLEEDING_HP_DRAIN_LOW_PER_DAY: float = 10.0
const BLEEDING_HP_DRAIN_HIGH_PER_DAY: float = 400.0
const OPEN_WOUND_HEAL_TIME_MIN_HOURS: float = 48.0
const OPEN_WOUND_HEAL_TIME_MAX_HOURS: float = 72.0
const BLEEDING_SPAWN_CHANCE: float = 0.66

const INFECTION_HAZARD_MIN_PER_HOUR: float = 0.004
const INFECTION_HAZARD_MAX_PER_HOUR: float = 0.10
const INFECTION_HAZARD_RAMP_HOURS: float = 72.0
const INFECTION_SEVERITY_RISE_PER_HOUR: float = 2.0
const INFECTION_SEVERITY_FALL_PER_HOUR: float = 6.0
const OPEN_WOUND_INFECTED_HEAL_DAMPEN: float = 0.1

const INFECTION_SPEED_MULT_MIN: float = 0.5
const INFECTION_STAMINA_DRAIN_MAX_MULT: float = 3.0
const INFECTION_WORK_SPEED_MULT_MIN: float = 0.5

## Needs-cap curve endpoints at 100% infection severity — mirrors
## PlayerMedical's hunger/water/sleep table, mapped onto the NPC's own
## three needs (hunger/thirst/energy stand in for hunger/water/sleep).
const INFECTION_HUNGER_CAP_REDUCTION_AT_100: float = -75.0
const INFECTION_THIRST_CAP_REDUCTION_AT_100: float = -90.0
const INFECTION_ENERGY_CAP_REDUCTION_AT_100: float = -95.0

const FRACTURE_STARTING_SEVERITY_MIN: float = 15.0
const FRACTURE_STARTING_SEVERITY_MAX: float = 25.0
const FRACTURE_ESCALATION_MIN: float = 10.0
const FRACTURE_ESCALATION_MAX: float = 25.0
const FRACTURE_ESCALATION_SETBACK_MULT: float = 0.7
const FRACTURE_SPLINT_HASTEN_MULT: float = 6.0
const FRACTURE_HEAL_TIME_LOW_HOURS: float = 60.0
const FRACTURE_HEAL_TIME_HIGH_HOURS: float = 240.0
const FRACTURE_SPEED_MULT_MIN: float = 0.4
const FRACTURE_SPEED_MULT_MAX: float = 0.9
const FRACTURE_SPLINT_PENALTY_RELIEF: float = 0.5
const FRACTURE_STAMINA_DRAIN_MAX_MULT: float = 4.0
const FRACTURE_WORK_SPEED_MULT_MIN: float = 0.4
const FRACTURE_WORK_SPEED_MULT_MAX: float = 0.9

const BROKEN_HEAL_TIME_HOURS: float = 240.0
const BROKEN_SPEED_MULT: float = 0.25
const BROKEN_STAMINA_DRAIN_MAX_MULT: float = 5.0
const BROKEN_WORK_SPEED_MULT: float = 0.25
const BROKEN_SPLINT_HASTEN_MULT: float = 6.0
const BROKEN_SPLINT_PENALTY_RELIEF: float = 0.5

const BURN_HEAL_TIME_MIN_HOURS: float = 24.0
const BURN_HEAL_TIME_MAX_HOURS: float = 48.0
const BURN_SPEED_MULT: float = 0.85
const BURN_STAMINA_DRAIN_MAX_MULT: float = 2.0
const BURN_WORK_SPEED_MULT: float = 0.85

# ─── HUD ring colors — same palette as PlayerMedical, for the Talk-menu
# Medical tab's mini-icon dots (per Brannon's ask: reuse the same colors). ──
const OPEN_WOUND_RING_COLOR: Color = Color(0.55, 0.16, 0.14, 1.0)
const BLEEDING_RING_COLOR: Color   = Color(0.82, 0.14, 0.10, 1.0)
const INFECTION_RING_COLOR: Color  = Color(0.55, 0.75, 0.20, 1.0)
const FRACTURED_RING_COLOR: Color  = Color(0.65, 0.45, 0.15, 1.0)
const BROKEN_RING_COLOR: Color     = Color(0.40, 0.28, 0.10, 1.0)
const BURN_RING_COLOR: Color       = Color(0.85, 0.45, 0.10, 1.0)

var active_conditions: Array[MedicalCondition] = []

## Set by NPC._ready() right after instantiating this node — the entity
## this component belongs to. Never a group lookup, unlike PlayerMedical
## (which is a scene-level singleton) — this is a per-instance child, so
## its owner is always known directly.
var npc: Node = null

func setup(owner_npc: Node) -> void:
	npc = owner_npc

func _process(delta: float) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	var h: float = npc.game_hours(delta) if npc.has_method("game_hours") else 0.0
	if h <= 0.0:
		return
	_tick_all_conditions(h)
	_apply_needs_cap_modifiers()

func _tick_all_conditions(game_hours: float) -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for condition in conditions_copy:
		if condition.id == "open_wound":
			_tick_open_wound(condition, game_hours)
		elif condition.id == "bleeding":
			_tick_bleeding(condition, game_hours)
		elif condition.id == "fractured":
			_tick_fractured(condition, game_hours)
		elif condition.id == "broken":
			_tick_broken(condition, game_hours)
		elif condition.id == "burn":
			_tick_burn(condition, game_hours)

## Time-skip catch-up — same shape as PlayerMedical.catch_up(), called by
## NPC.catch_up_time() alongside its own needs/mood catch-up (see
## NPC.gd's own header comment on where every skip source must call this).
func catch_up(hours: float) -> void:
	const SUBSTEP: float = 1.0
	var remaining: float = hours
	while remaining > 0.0:
		var step: float = minf(SUBSTEP, remaining)
		_tick_all_conditions(step)
		remaining -= step
	_apply_needs_cap_modifiers()

# ─── Open Wound / Bleeding / Infection ─────────────────────────────────────
func spawn_open_wound(body_part: int) -> void:
	var wound := MedicalCondition.new()
	wound.id = "open_wound"
	wound.category = MedicalCondition.Category.INJURY
	wound.body_part = body_part
	wound.severity_mode = MedicalCondition.SeverityMode.PINNED_MAX
	wound.severity = 100.0
	wound.has_heal_ring = true
	wound.heal_time_target_hours = randf_range(OPEN_WOUND_HEAL_TIME_MIN_HOURS, OPEN_WOUND_HEAL_TIME_MAX_HOURS)
	add_condition(wound)
	if randf() < BLEEDING_SPAWN_CHANCE:
		spawn_bleeding(body_part)

func _tick_open_wound(wound: MedicalCondition, game_hours: float) -> void:
	_tick_infection(wound, game_hours)
	var rate_mult: float = 1.0
	if get_condition_by_id_and_part("bleeding", wound.body_part) != null:
		rate_mult *= OPEN_WOUND_INFECTED_HEAL_DAMPEN
	if wound.is_infected:
		rate_mult *= OPEN_WOUND_INFECTED_HEAL_DAMPEN
	wound.current_heal_rate_mult = rate_mult
	if wound.heal_time_target_hours <= 0.0:
		return
	wound.heal_progress += (game_hours / wound.heal_time_target_hours) * 100.0 * rate_mult
	wound.heal_progress = minf(wound.heal_progress, wound.severity)
	if wound.heal_progress >= wound.severity:
		remove_condition(wound)

func _tick_infection(wound: MedicalCondition, game_hours: float) -> void:
	if wound.is_infected:
		if wound.is_treated:
			wound.infection_severity = maxf(0.0, wound.infection_severity - INFECTION_SEVERITY_FALL_PER_HOUR * game_hours)
			if wound.infection_severity <= 0.0:
				wound.is_infected = false
				wound.infection_resolved = true
				wound.is_treated = false
				wound.needs_cap_modifiers = {}
				wound.needs_cap_reason = ""
		else:
			wound.infection_severity = minf(100.0, wound.infection_severity + INFECTION_SEVERITY_RISE_PER_HOUR * game_hours)
			_update_infection_needs_cap(wound)
		_apply_infection_symptoms(wound)
		return
	if wound.infection_resolved or wound.is_treated:
		_apply_infection_symptoms(wound)
		return
	wound.infection_roll_elapsed_hours += game_hours
	var t: float = clampf(wound.infection_roll_elapsed_hours / INFECTION_HAZARD_RAMP_HOURS, 0.0, 1.0)
	var hazard_per_hour: float = lerp(INFECTION_HAZARD_MIN_PER_HOUR, INFECTION_HAZARD_MAX_PER_HOUR, t)
	if randf() < hazard_per_hour * game_hours:
		wound.is_infected = true
		wound.infection_severity = 1.0
	_apply_infection_symptoms(wound)

func _apply_infection_symptoms(wound: MedicalCondition) -> void:
	if not wound.is_infected:
		wound.speed_mult = 1.0
		wound.stamina_drain_mult_sprint = 1.0
		wound.stamina_drain_mult_carry = 1.0
		wound.work_speed_mult = 1.0
		return
	var f: float = wound.infection_severity / 100.0
	wound.speed_mult = lerp(1.0, INFECTION_SPEED_MULT_MIN, f)
	var drain_mult: float = _severity_exp_stamina_drain_mult(wound.infection_severity, INFECTION_STAMINA_DRAIN_MAX_MULT)
	wound.stamina_drain_mult_sprint = drain_mult
	wound.stamina_drain_mult_carry = drain_mult
	wound.work_speed_mult = lerp(1.0, INFECTION_WORK_SPEED_MULT_MIN, f)

## NPC's three needs (hunger/thirst/energy) stand in for the player's
## (hunger/water/sleep) — same curve shape, mapped 1:1 onto whichever
## need is analogous. Written into MedicalCondition.needs_cap_modifiers
## using the SAME key names PlayerMedical uses ("hunger"/"water"/"sleep")
## so a future shared-base-class refactor (see the design doc's "keep
## synchronized" note) wouldn't need to touch this shape — only
## _apply_needs_cap_modifiers() below knows these map onto energy_cap
## instead of a "sleep_cap".
func _update_infection_needs_cap(wound: MedicalCondition) -> void:
	var f: float = wound.infection_severity / 100.0
	wound.needs_cap_modifiers = {
		"hunger": INFECTION_HUNGER_CAP_REDUCTION_AT_100 * f,
		"water":  INFECTION_THIRST_CAP_REDUCTION_AT_100 * f,
		"sleep":  INFECTION_ENERGY_CAP_REDUCTION_AT_100 * f,
	}
	wound.needs_cap_reason = "battling an infection"

func _apply_needs_cap_modifiers() -> void:
	if npc == null or not is_instance_valid(npc):
		return
	var hunger_cap: float = 100.0
	var thirst_cap: float = 100.0
	var energy_cap: float = 100.0
	for c in active_conditions:
		if c.needs_cap_modifiers.has("hunger"):
			hunger_cap = minf(hunger_cap, 100.0 + c.needs_cap_modifiers["hunger"])
		if c.needs_cap_modifiers.has("water"):
			thirst_cap = minf(thirst_cap, 100.0 + c.needs_cap_modifiers["water"])
		if c.needs_cap_modifiers.has("sleep"):
			energy_cap = minf(energy_cap, 100.0 + c.needs_cap_modifiers["sleep"])
	npc.hunger_cap = hunger_cap
	npc.thirst_cap = thirst_cap
	npc.energy_cap = energy_cap

## Same plain-sentence shape as PlayerMedical.get_needs_cap_reason_text()
## — see that function's own comment. Consumed by NPCTalkMenuUI's Medical
## tab.
func get_needs_cap_reason_text() -> String:
	var reasons: Array[String] = []
	for need_key in ["hunger", "water", "sleep"]:
		for c in active_conditions:
			if c.needs_cap_modifiers.has(need_key) and c.needs_cap_modifiers[need_key] < 0.0:
				if c.needs_cap_reason != "" and not reasons.has(c.needs_cap_reason):
					reasons.append(c.needs_cap_reason)
	if reasons.is_empty():
		return ""
	return "You are currently %s." % " and ".join(reasons)

# ─── Body-part-differentiated symptoms — verbatim port of
# PlayerMedical's own two shared helpers, see that file's comments. ────────
func _severity_exp_stamina_drain_mult(severity: float, max_mult: float) -> float:
	return lerp(1.0, max_mult, pow(clampf(severity, 0.0, 100.0) / 100.0, 2.0))

func _apply_limb_symptoms(condition: MedicalCondition, speed_candidate: float, drain_candidate: float, work_speed_candidate: float) -> void:
	condition.speed_mult = 1.0
	condition.stamina_drain_mult_sprint = 1.0
	condition.stamina_drain_mult_carry = 1.0
	condition.work_speed_mult = 1.0
	match condition.body_part:
		MedicalCondition.BodyPart.LEFT_LEG, MedicalCondition.BodyPart.RIGHT_LEG:
			condition.speed_mult = speed_candidate
			condition.stamina_drain_mult_sprint = drain_candidate
		MedicalCondition.BodyPart.LEFT_ARM, MedicalCondition.BodyPart.RIGHT_ARM:
			condition.stamina_drain_mult_carry = drain_candidate
			condition.work_speed_mult = work_speed_candidate
		_:
			pass

# ─── Bleeding ───────────────────────────────────────────────────────────────
func spawn_bleeding(body_part: int) -> void:
	var bleed := MedicalCondition.new()
	bleed.id = "bleeding"
	bleed.category = MedicalCondition.Category.INJURY
	bleed.body_part = body_part
	bleed.severity_mode = MedicalCondition.SeverityMode.LIVE_BIDIRECTIONAL
	bleed.starting_severity_min = 1.0
	bleed.starting_severity_max = 15.0
	bleed.roll_starting_severity()
	bleed.has_heal_ring = false
	add_condition(bleed)

## HP drain writes directly to npc.health, mirroring PlayerMedical's write
## to PlayerStats.health — same timescale-correct formula (hp_per_day
## scaled by elapsed game-day fraction, entirely game-time-relative, no
## real-time conversion needed for the actual damage applied).
func _tick_bleeding(bleed: MedicalCondition, game_hours: float) -> void:
	if not bleed.is_treated:
		bleed.severity = minf(100.0, bleed.severity + BLEEDING_CLIMB_RATE * bleed.severity * game_hours)
	var severity_frac: float = bleed.severity / 100.0
	var hp_per_day: float = lerp(BLEEDING_HP_DRAIN_LOW_PER_DAY, BLEEDING_HP_DRAIN_HIGH_PER_DAY, severity_frac * severity_frac)
	var hp_loss: float = hp_per_day * (game_hours / 24.0)
	if npc != null and is_instance_valid(npc):
		npc.health = maxf(0.0, npc.health - hp_loss)

func treat_bleeding(body_part: int) -> void:
	var bleed: MedicalCondition = get_condition_by_id_and_part("bleeding", body_part)
	if bleed != null:
		remove_condition(bleed)

func get_eligible_bleeding_targets() -> Array:
	var bleeding: Array[MedicalCondition] = []
	for c in active_conditions:
		if c.id == "bleeding":
			bleeding.append(c)
	bleeding.sort_custom(func(a: MedicalCondition, b: MedicalCondition) -> bool: return a.severity > b.severity)
	var out: Array = []
	for c in bleeding:
		out.append({"body_part": c.body_part, "label": MedicalCondition.body_part_label(c.body_part), "detail": "Severity: %d%%" % int(c.severity)})
	return out

func treat_open_wound_antibiotics(body_part: int) -> void:
	var wound: MedicalCondition = get_condition_by_id_and_part("open_wound", body_part)
	if wound != null:
		wound.is_treated = true

func get_eligible_antibiotic_targets() -> Array:
	var wounds: Array[MedicalCondition] = []
	for c in active_conditions:
		if c.id == "open_wound":
			wounds.append(c)
	wounds.sort_custom(func(a: MedicalCondition, b: MedicalCondition) -> bool: return a.infection_severity > b.infection_severity)
	var out: Array = []
	for c in wounds:
		var detail: String = ("Severity: %d%%" % int(c.infection_severity)) if c.is_infected else "Untreated"
		out.append({"body_part": c.body_part, "label": MedicalCondition.body_part_label(c.body_part), "detail": detail})
	return out

# ─── Fracture / Broken ───────────────────────────────────────────────────────
func spawn_fractured(body_part: int) -> void:
	var frac := MedicalCondition.new()
	frac.id = "fractured"
	frac.category = MedicalCondition.Category.INJURY
	frac.body_part = body_part
	frac.severity_mode = MedicalCondition.SeverityMode.LIVE_ONE_DIRECTIONAL
	frac.starting_severity_min = FRACTURE_STARTING_SEVERITY_MIN
	frac.starting_severity_max = FRACTURE_STARTING_SEVERITY_MAX
	frac.roll_starting_severity()
	frac.has_heal_ring = true
	frac.heal_time_target_hours = _fracture_heal_time_for_severity(frac.severity)
	add_condition(frac)

func _fracture_heal_time_for_severity(severity: float) -> float:
	var t: float = clampf((severity - FRACTURE_STARTING_SEVERITY_MIN) / (100.0 - FRACTURE_STARTING_SEVERITY_MIN), 0.0, 1.0)
	return lerp(FRACTURE_HEAL_TIME_LOW_HOURS, FRACTURE_HEAL_TIME_HIGH_HOURS, t)

func _fracture_speed_mult(frac: MedicalCondition) -> float:
	var base_mult: float = lerp(FRACTURE_SPEED_MULT_MAX, FRACTURE_SPEED_MULT_MIN, frac.severity / 100.0)
	if frac.is_treated:
		base_mult = lerp(base_mult, 1.0, FRACTURE_SPLINT_PENALTY_RELIEF)
	return base_mult

func _fracture_stamina_drain_mult(frac: MedicalCondition) -> float:
	var mult: float = _severity_exp_stamina_drain_mult(frac.severity, FRACTURE_STAMINA_DRAIN_MAX_MULT)
	if frac.is_treated:
		mult = lerp(mult, 1.0, FRACTURE_SPLINT_PENALTY_RELIEF)
	return mult

func _fracture_work_speed_mult(frac: MedicalCondition) -> float:
	var base_mult: float = lerp(FRACTURE_WORK_SPEED_MULT_MAX, FRACTURE_WORK_SPEED_MULT_MIN, frac.severity / 100.0)
	if frac.is_treated:
		base_mult = lerp(base_mult, 1.0, FRACTURE_SPLINT_PENALTY_RELIEF)
	return base_mult

func _tick_fractured(frac: MedicalCondition, game_hours: float) -> void:
	_apply_limb_symptoms(frac, _fracture_speed_mult(frac), _fracture_stamina_drain_mult(frac), _fracture_work_speed_mult(frac))
	if frac.heal_time_target_hours <= 0.0:
		return
	var hasten_mult: float = FRACTURE_SPLINT_HASTEN_MULT if frac.is_treated else 1.0
	frac.current_heal_rate_mult = hasten_mult
	frac.heal_progress += (game_hours / frac.heal_time_target_hours) * frac.severity * hasten_mult
	frac.heal_progress = minf(frac.heal_progress, frac.severity)
	if frac.heal_progress >= frac.severity:
		remove_condition(frac)

func _escalate_fracture(frac: MedicalCondition) -> void:
	var bump: float = randf_range(FRACTURE_ESCALATION_MIN, FRACTURE_ESCALATION_MAX)
	frac.severity = minf(100.0, frac.severity + bump)
	frac.heal_progress *= FRACTURE_ESCALATION_SETBACK_MULT
	frac.heal_time_target_hours = _fracture_heal_time_for_severity(frac.severity)
	if frac.severity >= 100.0:
		_convert_fractured_to_broken(frac)

func _convert_fractured_to_broken(frac: MedicalCondition) -> void:
	var body_part: int = frac.body_part
	remove_condition(frac)
	var broken := MedicalCondition.new()
	broken.id = "broken"
	broken.category = MedicalCondition.Category.INJURY
	broken.body_part = body_part
	broken.severity_mode = MedicalCondition.SeverityMode.PINNED_MAX
	broken.severity = 100.0
	broken.has_heal_ring = true
	broken.heal_time_target_hours = BROKEN_HEAL_TIME_HOURS
	add_condition(broken)

func _tick_broken(broken: MedicalCondition, game_hours: float) -> void:
	var speed_candidate: float = BROKEN_SPEED_MULT
	var drain_candidate: float = _severity_exp_stamina_drain_mult(broken.severity, BROKEN_STAMINA_DRAIN_MAX_MULT)
	var work_speed_candidate: float = BROKEN_WORK_SPEED_MULT
	if broken.is_treated:
		speed_candidate = lerp(speed_candidate, 1.0, BROKEN_SPLINT_PENALTY_RELIEF)
		drain_candidate = lerp(drain_candidate, 1.0, BROKEN_SPLINT_PENALTY_RELIEF)
		work_speed_candidate = lerp(work_speed_candidate, 1.0, BROKEN_SPLINT_PENALTY_RELIEF)
	_apply_limb_symptoms(broken, speed_candidate, drain_candidate, work_speed_candidate)
	if broken.heal_time_target_hours <= 0.0:
		return
	var rate_mult: float = BROKEN_SPLINT_HASTEN_MULT if broken.is_treated else 1.0
	broken.current_heal_rate_mult = rate_mult
	broken.heal_progress = minf(broken.severity, broken.heal_progress + (game_hours / broken.heal_time_target_hours) * 100.0 * rate_mult)
	if broken.heal_progress >= broken.severity:
		remove_condition(broken)

# ─── Burns ────────────────────────────────────────────────────────────────────
func spawn_burn(body_part: int, cause: String = "") -> void:
	var burn := MedicalCondition.new()
	burn.id = "burn"
	burn.category = MedicalCondition.Category.INJURY
	burn.body_part = body_part
	burn.severity_mode = MedicalCondition.SeverityMode.PINNED_MAX
	burn.severity = 100.0
	burn.has_heal_ring = true
	burn.heal_time_target_hours = randf_range(BURN_HEAL_TIME_MIN_HOURS, BURN_HEAL_TIME_MAX_HOURS)
	burn.cause = cause
	add_condition(burn)

func _tick_burn(burn: MedicalCondition, game_hours: float) -> void:
	_apply_limb_symptoms(burn, BURN_SPEED_MULT, _severity_exp_stamina_drain_mult(burn.severity, BURN_STAMINA_DRAIN_MAX_MULT), BURN_WORK_SPEED_MULT)
	if burn.heal_time_target_hours <= 0.0:
		return
	burn.current_heal_rate_mult = 1.0
	burn.heal_progress = minf(burn.severity, burn.heal_progress + (game_hours / burn.heal_time_target_hours) * 100.0)
	if burn.heal_progress >= burn.severity:
		remove_condition(burn)

## Splint — same dual Fractured/Broken support as PlayerMedical.apply_splint().
func apply_splint(body_part: int) -> void:
	var frac: MedicalCondition = get_condition_by_id_and_part("fractured", body_part)
	if frac != null:
		frac.is_treated = true
		return
	var broken: MedicalCondition = get_condition_by_id_and_part("broken", body_part)
	if broken != null:
		broken.is_treated = true

func get_eligible_splint_targets() -> Array:
	var targets: Array[MedicalCondition] = []
	for c in active_conditions:
		if c.id == "fractured" or c.id == "broken":
			targets.append(c)
	targets.sort_custom(func(a: MedicalCondition, b: MedicalCondition) -> bool: return a.severity > b.severity)
	var out: Array = []
	for c in targets:
		var detail: String = ("Severity: %d%%" % int(c.severity)) if c.id == "fractured" else "Broken"
		out.append({"body_part": c.body_part, "label": MedicalCondition.body_part_label(c.body_part), "detail": detail})
	return out

func treat_all_bleeding_and_fractures() -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for c in conditions_copy:
		if c.id == "bleeding":
			treat_bleeding(c.body_part)
		elif c.id == "fractured":
			apply_splint(c.body_part)

# ─── Aggregators — mirrors PlayerMedical's four exactly. Only speed is
# actually consumed by NPC.gd this pass (get_status_speed_multiplier()) —
# the other three are correct and ready, same "unwired until a base
# mechanic exists" pattern PlayerMedical itself went through for sprint/
# carry-drain and work-speed before those existed on the player side. ──────
func get_medical_speed_multiplier() -> float:
	var mult: float = 1.0
	for c in active_conditions:
		mult *= c.speed_mult
	return mult

func get_medical_sprint_stamina_drain_multiplier() -> float:
	var mult: float = 1.0
	for c in active_conditions:
		mult *= c.stamina_drain_mult_sprint
	return mult

func get_medical_carry_stamina_drain_multiplier() -> float:
	var mult: float = 1.0
	for c in active_conditions:
		mult *= c.stamina_drain_mult_carry
	return mult

func get_medical_job_speed_multiplier() -> float:
	var mult: float = 1.0
	for c in active_conditions:
		mult *= c.work_speed_mult
	return mult

func add_condition(condition: MedicalCondition) -> void:
	active_conditions.append(condition)
	condition_added.emit(condition)

func remove_condition(condition: MedicalCondition) -> void:
	active_conditions.erase(condition)
	condition_removed.emit(condition)

func get_conditions_for_body_part(body_part: int) -> Array[MedicalCondition]:
	var result: Array[MedicalCondition] = []
	for c in active_conditions:
		if c.body_part == body_part:
			result.append(c)
	return result

func get_condition_by_id_and_part(id: String, body_part: int) -> MedicalCondition:
	for c in active_conditions:
		if c.id == id and c.body_part == body_part:
			return c
	return null

func get_ring_color_for_condition(condition: MedicalCondition) -> Color:
	match condition.id:
		"bleeding": return BLEEDING_RING_COLOR
		"fractured": return FRACTURED_RING_COLOR
		"broken": return BROKEN_RING_COLOR
		"burn": return BURN_RING_COLOR
		_: return OPEN_WOUND_RING_COLOR

## Every currently non-1.0 symptom effect — verbatim port of
## PlayerMedical._symptom_effect_lines(), same display shape.
func _symptom_effect_lines(condition: MedicalCondition) -> Array[String]:
	var lines: Array[String] = []
	if not is_equal_approx(condition.speed_mult, 1.0):
		lines.append("%.2fx Movement Speed" % condition.speed_mult)
	if not is_equal_approx(condition.stamina_drain_mult_sprint, 1.0):
		lines.append("%.2fx Stamina Drain (While Sprinting)" % condition.stamina_drain_mult_sprint)
	if not is_equal_approx(condition.stamina_drain_mult_carry, 1.0):
		lines.append("%.2fx Stamina Drain (While Carrying)" % condition.stamina_drain_mult_carry)
	if not is_equal_approx(condition.work_speed_mult, 1.0):
		lines.append("%.2fx Work Speed" % condition.work_speed_mult)
	return lines

## Same per-condition detail text as PlayerMedical._tooltip_for(), reused
## verbatim by the NPCTalkMenuUI Medical tab's nested dropdowns — same
## "reuse the exact same per-condition data" principle the Status Screen
## already follows for the player side.
func get_status_detail_text(condition: MedicalCondition) -> String:
	var part_label: String = MedicalCondition.body_part_label(condition.body_part)
	if condition.id == "bleeding":
		return "Bleeding (%s)\nSeverity: %d%%\nHP loss/day: %.1f" % [part_label, int(condition.severity), lerp(BLEEDING_HP_DRAIN_LOW_PER_DAY, BLEEDING_HP_DRAIN_HIGH_PER_DAY, pow(condition.severity / 100.0, 2.0))]
	if condition.id == "open_wound":
		var lines: Array[String] = []
		if condition.is_infected:
			lines.append("Open Wound (Infected) (%s)" % part_label)
			lines.append("Infection Severity: %d%%" % int(condition.infection_severity))
			lines.append("Treated" if condition.is_treated else "Untreated")
		else:
			lines.append("Open Wound (%s)" % part_label)
			lines.append("Treated (antibiotics applied)" if condition.is_treated else "Antibiotics not yet applied")
		lines.append_array(_symptom_effect_lines(condition))
		var bleed: MedicalCondition = get_condition_by_id_and_part("bleeding", condition.body_part)
		if bleed != null:
			lines.append("Bleeding: %d%%" % int(bleed.severity))
		if condition.has_heal_ring and condition.severity > 0.0:
			var frac_left: float = 1.0 - (condition.heal_progress / condition.severity)
			var hours_left: float = frac_left * condition.heal_time_target_hours / maxf(condition.current_heal_rate_mult, 0.0001)
			lines.append("Time Left: ~%.0fh" % maxf(hours_left, 0.0))
		return "\n".join(lines)
	if condition.id == "fractured":
		var lines2: Array[String] = ["Fractured (%s)" % part_label, "Severity: %d%%" % int(condition.severity)]
		lines2.append("Splinted" if condition.is_treated else "Not splinted")
		lines2.append_array(_symptom_effect_lines(condition))
		if condition.severity > 0.0:
			var frac_left2: float = 1.0 - (condition.heal_progress / condition.severity)
			var hours_left2: float = frac_left2 * condition.heal_time_target_hours / maxf(condition.current_heal_rate_mult, 0.0001)
			lines2.append("Time Left: ~%.0fh" % maxf(hours_left2, 0.0))
		return "\n".join(lines2)
	if condition.id == "broken":
		var lines3: Array[String] = ["Broken (%s)" % part_label]
		lines3.append("Splinted" if condition.is_treated else "Not splinted")
		lines3.append_array(_symptom_effect_lines(condition))
		var frac_left3: float = 1.0 - (condition.heal_progress / 100.0)
		lines3.append("Time Left: ~%.0fh" % maxf(frac_left3 * condition.heal_time_target_hours / maxf(condition.current_heal_rate_mult, 0.0001), 0.0))
		return "\n".join(lines3)
	if condition.id == "burn":
		var label: String = "%s Burn" % condition.cause.capitalize() if condition.cause != "" else "Burn"
		var lines4: Array[String] = ["%s (%s)" % [label, part_label]]
		lines4.append_array(_symptom_effect_lines(condition))
		var frac_left4: float = 1.0 - (condition.heal_progress / 100.0)
		lines4.append("Time Left: ~%.0fh" % maxf(frac_left4 * condition.heal_time_target_hours / maxf(condition.current_heal_rate_mult, 0.0001), 0.0))
		return "\n".join(lines4)
	return "%s (%s)" % [condition.id.capitalize(), part_label]

# ─── F7 debug helpers — same shape as PlayerMedical's own, for testing an
# individual NPC's Medical state without a real trigger existing yet. ──────
func debug_force_escalate_all_fractures() -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for frac in conditions_copy:
		if frac.id == "fractured":
			_escalate_fracture(frac)

func debug_force_break_all_fractures() -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for frac in conditions_copy:
		if frac.id != "fractured":
			continue
		frac.severity = 100.0
		_convert_fractured_to_broken(frac)

func debug_clear_all() -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for c in conditions_copy:
		remove_condition(c)
