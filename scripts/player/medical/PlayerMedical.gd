extends Node
class_name PlayerMedical
## PlayerMedical.gd
## Player-side Medical component. Owns the player's active MedicalCondition
## list and ticks their severity/heal_progress each frame, and drives the
## ambient HUD badges via StatusEffectsContainer's medical-mode API. See
## docs/systems/medical/README.md for the full design and
## plans/medical-system-implementation-plan.md for the build order this
## follows (currently: Pass 0 foundation, Pass 1 Open Wound/Bleeding/HUD,
## Pass 2 Infection + Fracture/Broken + needs-cap reduction).
##
## Attach to: a sibling Node on res://scenes/world/MainWorld.tscn, same
## pattern as PlayerStats (NOT a child of Player.tscn — verified against
## the actual scene, not assumed). Added to the "player_medical" group so
## other systems (Player.gd, AdminMenu.gd) can find it via
## get_tree().get_first_node_in_group("player_medical") without a direct
## scene reference, matching PlayerStats/PowerManager's existing convention.

signal condition_added(condition: MedicalCondition)
signal condition_removed(condition: MedicalCondition)
signal condition_changed(condition: MedicalCondition)

# ─── Bleeding tuning (Pass 1, unchanged) ────────────────────────────────────
const BLEEDING_CLIMB_RATE: float = 0.06
const BLEEDING_HP_DRAIN_LOW_PER_DAY: float = 10.0
const BLEEDING_HP_DRAIN_HIGH_PER_DAY: float = 400.0
const OPEN_WOUND_HEAL_TIME_MIN_HOURS: float = 48.0
const OPEN_WOUND_HEAL_TIME_MAX_HOURS: float = 72.0
const BLEEDING_SPAWN_CHANCE: float = 0.66

# ─── Infection tuning (Pass 2) ───────────────────────────────────────────────
## Rising-hazard-curve approximation for whether an untreated Open Wound
## gets infected — a linear ramp from MIN to MAX chance-per-game-hour over
## INFECTION_HAZARD_RAMP_HOURS, rather than a true exponential (simpler to
## reason about; the design doc only calls for "low early, high late," not
## a specific curve shape). Placeholder — tune during playtesting, see
## docs/systems/medical/README.md's "Exact numbers everywhere" open item.
const INFECTION_HAZARD_MIN_PER_HOUR: float = 0.004
const INFECTION_HAZARD_MAX_PER_HOUR: float = 0.10
const INFECTION_HAZARD_RAMP_HOURS: float = 72.0
const INFECTION_SEVERITY_RISE_PER_HOUR: float = 2.0   ## untreated: ~50h to 100%
const INFECTION_SEVERITY_FALL_PER_HOUR: float = 6.0   ## curative antibiotics: faster than it rises
const OPEN_WOUND_INFECTED_HEAL_DAMPEN: float = 0.1     ## matches the existing bleeding dampener

## Infection's symptom contribution (Aug 2026) — systemic, so unlike every
## other wound-tier condition it sets ALL FOUR body-part-gated symptom
## fields at once regardless of which body part the underlying wound is
## on. See docs/systems/medical/README.md's "Body-part-differentiated
## symptom effects". Linear toward *_MIN/MAX_MULT at 100% infection_severity.
const INFECTION_SPEED_MULT_MIN: float = 0.5             ## at 100% infection severity
const INFECTION_STAMINA_DRAIN_MAX_MULT: float = 3.0      ## at 100% infection severity (both sprint + carry)
const INFECTION_WORK_SPEED_MULT_MIN: float = 0.5         ## at 100% infection severity

## Needs-cap curve endpoints at 100% infection severity (see the design
## doc's "Needs cap reduction" table — sleep hit hardest, water next,
## hunger least). Linear from (0, 0) to (100, endpoint); ballpark, not the
## doc's exact table shape — real tuning happens during playtesting.
const INFECTION_HUNGER_CAP_REDUCTION_AT_100: float = -75.0
const INFECTION_WATER_CAP_REDUCTION_AT_100: float = -90.0
const INFECTION_SLEEP_CAP_REDUCTION_AT_100: float = -95.0

# ─── Fracture tuning (Pass 2) ────────────────────────────────────────────────
const FRACTURE_STARTING_SEVERITY_MIN: float = 15.0
const FRACTURE_STARTING_SEVERITY_MAX: float = 25.0
const FRACTURE_ESCALATION_MIN: float = 10.0
const FRACTURE_ESCALATION_MAX: float = 25.0
const FRACTURE_ESCALATION_SETBACK_MULT: float = 0.7   ## heal_progress *= this on escalation
const FRACTURE_SPLINT_HASTEN_MULT: float = 6.0         ## splinted heals ~6x faster than crawling unsplinted
const FRACTURE_HEAL_TIME_LOW_HOURS: float = 60.0       ## ~2.5 days at ~15% severity
const FRACTURE_HEAL_TIME_HIGH_HOURS: float = 240.0     ## ~10 days at ~90%+ severity
const FRACTURE_SPEED_MULT_MIN: float = 0.4             ## worst-case (severity=100) unsplinted speed mult
const FRACTURE_SPEED_MULT_MAX: float = 0.9             ## best-case (low severity) speed mult
const FRACTURE_SPLINT_PENALTY_RELIEF: float = 0.5      ## splint halves the penalty (lerp toward 1.0)

## Body-part-differentiated symptom tuning (Aug 2026) — only used when the
## Fracture is on an ARM (see "Body-part-differentiated symptom effects"
## in the design doc). Same severity-graded / splint-relieved shape as
## FRACTURE_SPEED_MULT_MIN/MAX above, just for the arm-specific symptoms
## instead of the leg-specific speed penalty.
const FRACTURE_STAMINA_DRAIN_MAX_MULT: float = 4.0      ## at severity=100, unsplinted (legs: sprint drain, arms: carry drain)
const FRACTURE_WORK_SPEED_MULT_MIN: float = 0.4         ## worst-case (severity=100) unsplinted, arms only
const FRACTURE_WORK_SPEED_MULT_MAX: float = 0.9         ## best-case (low severity), arms only

## Broken (post-100%-Fractured) — NOT fully designed yet, see design doc's
## "Broken (post-Fractured) state details" open question. Placeholder
## values so the condition is playable/testable; revisit before treating
## these as final.
const BROKEN_HEAL_TIME_HOURS: float = 240.0
const BROKEN_SPEED_MULT: float = 0.25
## Broken's own arm-side symptom flat values (Aug 2026) — pinned severity,
## so no gradient to scale off, same flat-value pattern as BROKEN_SPEED_MULT
## itself. Worse than Fractured's own max, matching Broken being the more
## severe state.
const BROKEN_STAMINA_DRAIN_MAX_MULT: float = 5.0
const BROKEN_WORK_SPEED_MULT: float = 0.25
## Broken IS splintable, same mechanic as Fractured (Aug 2026 — previously
## an open design question, now resolved: Broken uses the exact same
## Splint item/apply_splint() call, same symptom-relief-while-worn and
## Healed-ring-hasten behavior, just its own tuning constants since Broken
## starts from a worse baseline than Fractured ever does. A fresh splint
## is always required after a Fracture converts to Broken — converting
## still destroys any existing splint, unchanged (see
## _convert_fractured_to_broken()).
const BROKEN_SPLINT_HASTEN_MULT: float = 6.0      ## matches FRACTURE_SPLINT_HASTEN_MULT
const BROKEN_SPLINT_PENALTY_RELIEF: float = 0.5   ## matches FRACTURE_SPLINT_PENALTY_RELIEF

# ─── Burn tuning (Pass 2.5) ─────────────────────────────────────
## Pinned-severity, no escalation, no infection track — the simplest
## wound-tier condition. Both flavors (electrical, cooking) share this
## exact same model per the design doc; only their trigger source differs,
## and neither trigger is wired to real gameplay yet (same as Open Wound
## in Pass 1 — this pass is condition logic + HUD, F7-spawned only; real
## cooking/breaker-reset triggers are a later, cross-system task per
## docs/systems/medical/README.md's "Burns (electrical and cooking)").
const BURN_HEAL_TIME_MIN_HOURS: float = 24.0
const BURN_HEAL_TIME_MAX_HOURS: float = 48.0
const BURN_SPEED_MULT: float = 0.85   ## flat, minor penalty — no severity gradation to scale off of
const BURN_STAMINA_DRAIN_MAX_MULT: float = 2.0   ## flat, minor — matches BURN_SPEED_MULT's severity
const BURN_WORK_SPEED_MULT: float = 0.85         ## flat, minor — matches BURN_SPEED_MULT's severity

## Genuine rest bonus for Broken/Burns (see apply_rest_bonus() below) —
## see docs/systems/medical/README.md's Healing section ("Broken Bone and
## Burns: sped up by genuine rest/sleep"). Fractured (pre-100%), Open
## Wound, and the subsystem conditions are NOT listed there and don't get
## this bonus. Applied via an explicit call from whichever code actually
## triggers real sleep (SleepOverlay.gd) — NOT a PlayerStats signal, since
## real sleep and the admin fast-forward cheat both go through the exact
## same PlayerStats.skip_time_with_drain() function and can't be told
## apart from inside PlayerStats; the caller has to say which one it is.
const SLEEP_HASTEN_MULT: float = 2.0

## catch_up() subdivides a large time-skip into chunks this size so the
## infection hazard-curve roll (a genuine per-hour probability check, not
## a linear formula) behaves the same whether time passes normally via
## _process() or all at once via a skip — see catch_up()'s own comment.
const CATCH_UP_SUBSTEP_HOURS: float = 1.0

# ─── HUD ring colors ─────────────────────────────────────────────────────────
const OPEN_WOUND_RING_COLOR: Color = Color(0.55, 0.16, 0.14, 1.0)
const BLEEDING_RING_COLOR: Color   = Color(0.82, 0.14, 0.10, 1.0)
const INFECTION_RING_COLOR: Color  = Color(0.55, 0.75, 0.20, 1.0)   ## sickly green, distinct from red wound tones
const FRACTURED_RING_COLOR: Color  = Color(0.65, 0.45, 0.15, 1.0)   ## bone/amber
const BROKEN_RING_COLOR: Color     = Color(0.40, 0.28, 0.10, 1.0)   ## darker — worse than Fractured
const BURN_RING_COLOR: Color       = Color(0.85, 0.45, 0.10, 1.0)   ## scorched orange

var active_conditions: Array[MedicalCondition] = []

var _player_stats: PlayerStats = null
var _status_effects: StatusEffectsContainer = null
var _player: Player = null

func _ready() -> void:
	add_to_group("player_medical")
	_player_stats = get_tree().get_first_node_in_group("player_stats") as PlayerStats
	_status_effects = _find_status_effects()
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player != null:
		_player.exhausted.connect(_on_player_exhausted)

func _find_status_effects() -> StatusEffectsContainer:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud == null or not ("medical_effects" in hud):
		return null
	return hud.get("medical_effects") as StatusEffectsContainer

func _process(delta: float) -> void:
	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats") as PlayerStats
		if _player_stats == null:
			return
	if _status_effects == null:
		_status_effects = _find_status_effects()
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player != null and not _player.exhausted.is_connected(_on_player_exhausted):
			_player.exhausted.connect(_on_player_exhausted)

	var seconds_per_game_hour: float = _player_stats._seconds_per_game_hour
	if seconds_per_game_hour <= 0.0:
		return
	var game_hours: float = delta / seconds_per_game_hour

	_tick_all_conditions(game_hours)
	_update_bleeding_badge()
	_apply_needs_cap_modifiers()

## The single shared per-condition tick dispatch — called every real frame
## by _process() (with a tiny delta-derived game_hours), AND by catch_up()
## in fixed-size chunks for a large instant time-skip (sleep, admin
## fast-forward). This is what makes both paths behave identically instead
## of time-skips silently doing nothing to Medical conditions.
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
		condition_changed.emit(condition)
		if condition.id != "bleeding":
			_update_hud_badge(condition)

## Public — call this with however many game-hours just got skipped
## (sleep, the admin "Fast-Forward" cheat, anything else that jumps the
## clock) so every condition's severity/infection-roll/heal_progress
## actually advances by that much, instead of only reacting to real
## per-frame delta the way _process() does on its own. Subdivided into
## CATCH_UP_SUBSTEP_HOURS chunks rather than one big step specifically for
## the infection hazard-curve roll's sake — a single roll against
## `hazard_per_hour * 24` for a full day-skip isn't equivalent to 24
## separate hourly rolls compounding, so this keeps that statistically
## faithful to how it already behaves during normal real-time play.
func catch_up(hours: float) -> void:
	var remaining: float = hours
	while remaining > 0.0:
		var step: float = minf(CATCH_UP_SUBSTEP_HOURS, remaining)
		_tick_all_conditions(step)
		remaining -= step
	_update_bleeding_badge()
	_apply_needs_cap_modifiers()

## Explicit "this was genuine rest, not just time passing" bonus for
## Broken/Burns — see SLEEP_HASTEN_MULT's comment above for why this is a
## direct call from the real sleep code (SleepOverlay.gd) rather than a
## signal. Call this IN ADDITION TO catch_up(hours) for the same duration,
## not instead of it — catch_up() gives the base progression every skip
## gets, this adds the extra rest-specific speedup on top for the two
## conditions the design doc calls out.
func apply_rest_bonus(hours: float) -> void:
	for c in active_conditions:
		if c.id != "broken" and c.id != "burn":
			continue
		if c.heal_time_target_hours <= 0.0:
			continue
		## Aug 2026 fix — previously added a FULL extra SLEEP_HASTEN_MULT
		## worth of progress on top of what catch_up(hours) (called
		## immediately before this, for the same duration — see this
		## function's own doc comment above) had ALREADY applied at the
		## condition's own current rate (1.0 normally, or the splint-hasten
		## constant for a splinted Broken — see current_heal_rate_mult).
		## That stacked ADDITIVELY (base_rate + SLEEP_HASTEN_MULT, e.g. 1+2=3x
		## unsplinted, or 6+2=8x splinted) instead of MULTIPLICATIVELY
		## (base_rate × SLEEP_HASTEN_MULT, i.e. 2x or 12x) — which is what
		## "sped up BY genuine rest" actually means, and is exactly what made
		## an 8-hour sleep/fast-forward visibly heal Broken/Burns much faster
		## than 8 real game-hours' worth of the displayed rate. Fix: add only
		## the DELTA above what catch_up() already contributed
		## (current_heal_rate_mult × (SLEEP_HASTEN_MULT − 1)) so the two calls
		## together total exactly current_heal_rate_mult × SLEEP_HASTEN_MULT,
		## not current_heal_rate_mult + SLEEP_HASTEN_MULT.
		var bonus_mult: float = c.current_heal_rate_mult * (SLEEP_HASTEN_MULT - 1.0)
		c.heal_progress = minf(c.severity, c.heal_progress + (hours / c.heal_time_target_hours) * 100.0 * bonus_mult)
		if c.heal_progress >= c.severity:
			remove_condition(c)
	_update_bleeding_badge()

# ─── Open Wound ─────────────────────────────────────────────────────────────
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
	## Healed fill converges toward, and can never exceed, the severity
	## fill's current edge (see docs/systems/medical/README.md).
	wound.heal_progress = minf(wound.heal_progress, wound.severity)

	if wound.heal_progress >= wound.severity:
		remove_condition(wound)

## Rolls the infection outcome for a plain Open Wound (rising hazard
## curve), and ticks Infection Severity once infected — see the
## INFECTION_* consts above and docs/systems/medical/README.md's "Open
## wounds, bleeding, and infection".
func _tick_infection(wound: MedicalCondition, game_hours: float) -> void:
	if wound.is_infected:
		if wound.is_treated:   ## antibiotics applied curatively
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
		## is_treated here means antibiotics applied PREVENTATIVELY on a
		## still-plain wound — zeroes further infection risk outright,
		## simplest reading of "prevents/reduces infection risk."
		_apply_infection_symptoms(wound)
		return

	wound.infection_roll_elapsed_hours += game_hours
	var t: float = clampf(wound.infection_roll_elapsed_hours / INFECTION_HAZARD_RAMP_HOURS, 0.0, 1.0)
	var hazard_per_hour: float = lerp(INFECTION_HAZARD_MIN_PER_HOUR, INFECTION_HAZARD_MAX_PER_HOUR, t)
	if randf() < hazard_per_hour * game_hours:
		wound.is_infected = true
		wound.infection_severity = 1.0   ## just started
	_apply_infection_symptoms(wound)

## Infection's systemic symptom contribution (Aug 2026) — the one
## exception to "body part determines the category" (see
## docs/systems/medical/README.md's "Body-part-differentiated symptom
## effects"): sets ALL FOUR symptom fields on the wound at once, regardless
## of the underlying wound's body part, scaled by infection_severity. Not
## routed through _apply_limb_symptoms() — that helper's whole point is
## body-part GATING, which Infection deliberately bypasses. Resets to 1.0
## when not currently infected, same "clean recompute every tick" pattern.
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

func _update_infection_needs_cap(wound: MedicalCondition) -> void:
	var f: float = wound.infection_severity / 100.0
	wound.needs_cap_modifiers = {
		"hunger": INFECTION_HUNGER_CAP_REDUCTION_AT_100 * f,
		"water":  INFECTION_WATER_CAP_REDUCTION_AT_100 * f,
		"sleep":  INFECTION_SLEEP_CAP_REDUCTION_AT_100 * f,
	}
	wound.needs_cap_reason = "battling an infection"

## Recomputes PlayerStats' per-need caps from the worst (most restrictive)
## contribution across every active condition, every tick. Currently only
## an infected Open Wound ever populates needs_cap_modifiers, but this
## scans generically so future conditions can reuse the same mechanic
## without this function changing — see design doc's "Needs cap reduction".
func _apply_needs_cap_modifiers() -> void:
	if _player_stats == null:
		return
	var food_cap: float = 100.0
	var water_cap: float = 100.0
	var sleep_cap: float = 100.0
	for c in active_conditions:
		if c.needs_cap_modifiers.has("hunger"):
			food_cap = minf(food_cap, 100.0 + c.needs_cap_modifiers["hunger"])
		if c.needs_cap_modifiers.has("water"):
			water_cap = minf(water_cap, 100.0 + c.needs_cap_modifiers["water"])
		if c.needs_cap_modifiers.has("sleep"):
			sleep_cap = minf(sleep_cap, 100.0 + c.needs_cap_modifiers["sleep"])
	_player_stats.set_needs_caps(food_cap, water_cap, sleep_cap)

## Status Screen (Aug 2026) — a single plain-language sentence explaining
## WHY needs are currently capped, e.g. "You are currently battling an
## infection." Shown plainly on the Status Screen at all times (not on
## hover) when non-empty — the player can infer the drained needs are the
## reason without also being told which needs by name here (that's
## covered elsewhere — the needs gauge itself). Deliberately dynamic/
## generic rather than hardcoded to Infection specifically: scans every
## active condition's needs_cap_modifiers (same data
## _apply_needs_cap_modifiers() already reads) for whether ANY need is
## currently reduced, and pulls each contributing condition's own
## needs_cap_reason (see MedicalCondition.needs_cap_reason's doc comment)
## rather than re-deriving the reason text here — a future condition that
## populates needs_cap_modifiers automatically gets a correct sentence for
## free as long as it also sets its own needs_cap_reason, no changes
## needed here. Returns "" when nothing is currently capped (caller hides
## the row).
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

## Status Screen (Aug 2026) — public passthroughs for two presentation
## helpers that were previously private, so the new UI can reuse the exact
## same per-condition text/color the ambient HUD badges already use rather
## than inventing a second description of the same data (per the design
## doc's "Once the Status Screen gets built, it should reuse this exact
## same per-limb effect-list data shape"). No logic duplicated — these just
## forward to the existing private functions.
func get_status_detail_text(condition: MedicalCondition) -> String:
	return _tooltip_for(condition)

func get_condition_ring_color(condition: MedicalCondition) -> Color:
	return _ring_color_for(condition)

# ─── Body-part-differentiated symptoms (Aug 2026) ──────────────────────────
## See docs/systems/medical/README.md's "Body-part-differentiated symptom
## effects" for the full design. Shared by every wound-tier condition that
## has body-part-gated symptoms (Fractured, Broken, Burn) plus Infection's
## own systemic case — keeps the body-part gating logic in exactly one
## place instead of duplicated per condition type.

## The exponential "low at low severity, steep near 100" shape the design
## doc calls for on both stamina-drain fields — same curve shape reused by
## every condition that populates a stamina-drain multiplier, just with a
## different max_mult per condition/limb. Placeholder shape (a plain
## squared falloff) per the handover — tune during playtesting like every
## other Medical constant.
func _severity_exp_stamina_drain_mult(severity: float, max_mult: float) -> float:
	return lerp(1.0, max_mult, pow(clampf(severity, 0.0, 100.0) / 100.0, 2.0))

## Resets, then re-derives, a condition's four body-part-gated symptom
## fields (speed_mult, stamina_drain_mult_sprint, stamina_drain_mult_carry,
## work_speed_mult) from this tick's freshly-computed candidate values —
## called every tick so a condition whose body part hasn't changed still
## gets a clean recompute (matching the existing pattern where e.g.
## frac.speed_mult was already being reassigned fresh every tick). Legs get
## speed_candidate + drain_candidate (as stamina_drain_mult_sprint). Arms
## get drain_candidate (as stamina_drain_mult_carry) + work_speed_candidate
## — speed_mult is deliberately left at 1.0, arms never affect movement
## speed per the design doc. Torso/Head are explicitly deferred — every
## field stays at 1.0 there, same as today.
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
			pass   ## TORSO / HEAD — deferred, everything stays 1.0

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

func _tick_bleeding(bleed: MedicalCondition, game_hours: float) -> void:
	if not bleed.is_treated:
		bleed.severity = minf(100.0, bleed.severity + BLEEDING_CLIMB_RATE * bleed.severity * game_hours)

	var severity_frac: float = bleed.severity / 100.0
	var hp_per_day: float = lerp(BLEEDING_HP_DRAIN_LOW_PER_DAY, BLEEDING_HP_DRAIN_HIGH_PER_DAY, severity_frac * severity_frac)
	## Actual HP loss applied this tick — purely game-time-relative
	## (hp_per_day scaled by the elapsed fraction of a 24-game-hour day), so
	## this line is correct and timescale-independent regardless of how
	## compressed the game clock is. This was NEVER the bug.
	var hp_loss: float = hp_per_day * (game_hours / 24.0)
	if _player_stats != null:
		## hp_drain_per_second (Aug 2026 fix) — a DISPLAY-only figure for the
		## tooltip: "how many HP does this feel like it's costing per real
		## second while actually playing." Previously computed as
		## `hp_per_day / 24.0 / 3600.0`, which assumes 1 game day = 86400 REAL
		## seconds (i.e. no time compression at all) — but this project's
		## actual clock (PlayerStats.day_duration_seconds = 1440s = 24 real-
		## minutes/game-day, see PlayerStats.gd's Timescale header) runs 60x
		## faster than that. The old formula was dividing by a number 60x too
		## large, so the displayed rate rounded to "0.00/sec" at every
		## severity, including 100%. Deriving it from the real game clock
		## (_seconds_per_game_hour) instead fixes the display and keeps it
		## correct if the timescale is ever retuned. The HP actually lost
		## (hp_loss above) was never wrong — only this readout was.
		var real_seconds_per_game_day: float = _player_stats._seconds_per_game_hour * 24.0
		bleed.hp_drain_per_second = hp_per_day / real_seconds_per_game_day
		_player_stats.health = maxf(0.0, _player_stats.health - hp_loss)
		_player_stats.health_changed.emit(_player_stats.health)

func treat_bleeding(body_part: int) -> void:
	var bleed: MedicalCondition = get_condition_by_id_and_part("bleeding", body_part)
	if bleed != null:
		remove_condition(bleed)

## Bandage's injury-selection submenu query (Aug 2026) — every body part
## with an active Bleeding condition, worst-severity-first, per
## docs/systems/medical/README.md's "Injury-selection submenu". Each entry
## is { body_part: int, label: String, detail: String } — InteractionSystem
## reads exactly this shape generically (see its _build_medical_submenu_
## text()), so any future item's own eligible-targets query should return
## the same three keys.
func get_eligible_bleeding_targets() -> Array:
	var bleeding: Array[MedicalCondition] = []
	for c in active_conditions:
		if c.id == "bleeding":
			bleeding.append(c)
	bleeding.sort_custom(func(a: MedicalCondition, b: MedicalCondition) -> bool: return a.severity > b.severity)
	var out: Array = []
	for c in bleeding:
		out.append({
			"body_part": c.body_part,
			"label": MedicalCondition.body_part_label(c.body_part),
			"detail": "Severity: %d%%" % int(c.severity),
		})
	return out

## Antibiotics (Pass 2) — dual role per the design doc's "Item roles":
## applied to a plain Open Wound, prevents further infection risk outright.
## Applied to an already-infected wound, starts curing it (flips Infection
## Severity's trend from rising to falling in _tick_infection()). Same
## function handles both — the wound's own is_infected state decides which
## behavior applies, matching the item's real dual role.
func treat_open_wound_antibiotics(body_part: int) -> void:
	var wound: MedicalCondition = get_condition_by_id_and_part("open_wound", body_part)
	if wound != null:
		wound.is_treated = true

## Antibiotics' injury-selection submenu query (Aug 2026) — every body
## part with an active Open Wound, infected or not (Antibiotics works on
## either — preventatively on a plain wound, curatively on an infected
## one, same treat_open_wound_antibiotics() call either way). Sorted by
## current Infection Severity descending — an actively-infected wound is
## more urgent than a plain untreated one, which sorts to the bottom
## (severity 0). See docs/systems/medical/README.md's "Injury-selection
## submenu".
func get_eligible_antibiotic_targets() -> Array:
	var wounds: Array[MedicalCondition] = []
	for c in active_conditions:
		if c.id == "open_wound":
			wounds.append(c)
	wounds.sort_custom(func(a: MedicalCondition, b: MedicalCondition) -> bool:
		return a.infection_severity > b.infection_severity)
	var out: Array = []
	for c in wounds:
		var detail: String = ("Severity: %d%%" % int(c.infection_severity)) if c.is_infected else "Untreated"
		out.append({
			"body_part": c.body_part,
			"label": MedicalCondition.body_part_label(c.body_part),
			"detail": detail,
		})
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
	if frac.is_treated:   ## splinted — relieves part of the penalty
		base_mult = lerp(base_mult, 1.0, FRACTURE_SPLINT_PENALTY_RELIEF)
	return base_mult

## Arm-side candidates (Aug 2026) — only ever actually applied when the
## Fracture is on an arm, via _apply_limb_symptoms()'s body-part gate; the
## leg-side candidate is _fracture_speed_mult() above. Splinting relieves
## these the same way it relieves the leg speed penalty — "reduces symptom
## penalties while worn" applies generally, not just to speed, per the
## design doc.
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
	## Aug 2026 fix — previously accrued heal_progress against a flat 100.0
	## scale regardless of severity ("heal_progress += (game_hours /
	## heal_time_target_hours) * 100.0 * rate_mult"), but heal_progress is
	## CAPPED at frac.severity (below), not 100 — Fractured is the only
	## wound-tier condition whose severity isn't pinned at 100, so this was
	## the one condition where the bug actually surfaced. Concretely: a
	## fresh 15%-severity Fracture with heal_time_target_hours=60 (the
	## design doc's own "~2-3 day baseline" example) hit its cap of 15 in
	## just 9 real game-hours at the old formula — severity/100 = 15% of the
	## intended 60-hour baseline, not the full 60 hours the design doc and
	## _fracture_heal_time_for_severity()'s own naming promise. Scaling by
	## frac.severity instead of a hardcoded 100.0 makes heal_progress reach
	## exactly frac.severity after precisely heal_time_target_hours hours (at
	## rate_mult=1), matching "heal_time_target_hours IS the real heal
	## time" for every severity, not just severity=100 (which is why Broken/
	## Burn/Open Wound — always pinned at severity=100 — never showed this;
	## their hardcoded 100.0 happened to already equal their own severity).
	var hasten_mult: float = FRACTURE_SPLINT_HASTEN_MULT if frac.is_treated else 1.0
	frac.current_heal_rate_mult = hasten_mult
	frac.heal_progress += (game_hours / frac.heal_time_target_hours) * frac.severity * hasten_mult
	frac.heal_progress = minf(frac.heal_progress, frac.severity)

	if frac.heal_progress >= frac.severity:
		remove_condition(frac)   ## fully healed

## Triggered by Player.gd's exhausted signal (sustained 0-stamina) — the
## deterministic trigger for Fracture escalation. The signal's own
## once-per-episode semantics (only fires on the false->true transition)
## already give this the "one escalation roll per exertion episode"
## behavior the design doc calls for, with no extra cooldown bookkeeping
## needed here. Aug 2026 — extended to arms: Player.gd now reports WHICH
## drain source(s) actually caused this exhaustion (sprinting vs. carrying
## a Heavy item — see that signal's own doc comment), so the escalation
## itself stays body-part-causal per the design doc's "reason over
## randomness" pillar — sprinting escalates leg fractures (sprint/stamina
## is leg-driven, matching the design doc's original leg-only wording),
## carrying something heavy escalates arm fractures (arms are what's
## actually under load), and both fire in the same episode if the player
## was sprinting WHILE carrying something heavy.
func _on_player_exhausted(from_sprint: bool, from_heavy_carry: bool) -> void:
	if from_sprint:
		_escalate_fractures_on_parts([MedicalCondition.BodyPart.LEFT_LEG, MedicalCondition.BodyPart.RIGHT_LEG])
	if from_heavy_carry:
		_escalate_fractures_on_parts([MedicalCondition.BodyPart.LEFT_ARM, MedicalCondition.BodyPart.RIGHT_ARM])

func _escalate_fractures_on_parts(parts: Array) -> void:
	for part in parts:
		var frac: MedicalCondition = get_condition_by_id_and_part("fractured", part)
		if frac != null:
			_escalate_fracture(frac)

## Shared escalation math — one bounded-random severity bump, a Healed-
## ring setback, a recomputed heal-time target, and a Broken conversion if
## this push reaches 100%. Used by the real trigger above AND
## debug_force_escalate_all_fractures() below, so this math lives in
## exactly one place instead of two copies drifting apart.
func _escalate_fracture(frac: MedicalCondition) -> void:
	var bump: float = randf_range(FRACTURE_ESCALATION_MIN, FRACTURE_ESCALATION_MAX)
	frac.severity = minf(100.0, frac.severity + bump)
	frac.heal_progress *= FRACTURE_ESCALATION_SETBACK_MULT
	frac.heal_time_target_hours = _fracture_heal_time_for_severity(frac.severity)
	if frac.severity >= 100.0:
		_convert_fractured_to_broken(frac)

## Fractured reaching 100% severity converts to Broken — a distinct, worse
## condition, not just a label change (see design doc's "100% severity can
## trigger a state change"). Destroys any splint (Broken starts untreated
## regardless of the Fracture's prior splint state).
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
	if broken.is_treated:   ## splinted — relieves symptom penalties, same as Fractured (Aug 2026)
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
## Simplest wound-tier condition: pinned severity, Healed ring, no
## subsystems. `cause` is cosmetic only (shown in the tooltip) — mechanics
## are identical for both flavors per the design doc.
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
	burn.current_heal_rate_mult = 1.0   ## no real-time hasten modifier exists for Burn — only the one-off rest bonus (apply_rest_bonus())
	burn.heal_progress = minf(burn.severity, burn.heal_progress + (game_hours / burn.heal_time_target_hours) * 100.0)
	if burn.heal_progress >= burn.severity:
		remove_condition(burn)

## Real Burn triggers (Aug 2026) — previously F7-only. Both flavors are a
## bounded chance rolled at the exact moment of a real, causal player
## action (plating a dish; resetting a hazardous breaker/generator), per
## the design doc's "reason over randomness" pillar — the CHANCE itself
## varies with real, visible game state (grid state / generator health),
## never a flat unexplained number. Body part is always an arm (50/50
## left/right) — matches the established pattern that hands-on work is
## arm-attributed elsewhere in this system (heavy carry, work speed).
const COOKING_BURN_CHANCE: float = 0.04

const ELECTRICAL_BURN_CHANCE_ONLINE: float = 0.02
const ELECTRICAL_BURN_CHANCE_BROWNOUT: float = 0.05
const ELECTRICAL_BURN_CHANCE_OVERLOADED: float = 0.07
const ELECTRICAL_BURN_CHANCE_TRIPPED: float = 0.10
const ELECTRICAL_BURN_CHANCE_OFFLINE: float = 0.12
## Added on top of the grid-state chance above when restarting a
## generator that's below half health — a failing generator is a more
## dangerous thing to manually restart, independent of the grid's own state.
const ELECTRICAL_BURN_CHANCE_LOW_HEALTH_BONUS: float = 0.05
const ELECTRICAL_BURN_LOW_HEALTH_THRESHOLD: float = 50.0

func _roll_burn(chance: float, cause: String) -> void:
	if randf() < chance:
		var part: int = MedicalCondition.BodyPart.LEFT_ARM if randf() < 0.5 else MedicalCondition.BodyPart.RIGHT_ARM
		spawn_burn(part, cause)

## Called by InteractionSystem._finish_take_dish()/_finish_take_dish_from_
## held_pot() right after a dish is successfully served ("plating a dish
## can occasionally cause a burn", per the design doc). Flat chance —
## unlike electrical, there's no analogous "how hazardous was this
## specific moment" state to scale off of yet.
func roll_cooking_burn() -> void:
	_roll_burn(COOKING_BURN_CHANCE, "cooking")

## Called by BreakerBox._request_restart()'s job completion and
## GeneratorObject._on_power_toggled()'s restart-from-trip/low-health
## path. `grid_state_string` matches PowerManager.get_grid_state_string()'s
## exact return values ("ONLINE"/"BROWNOUT"/"OVERLOADED"/"TRIPPED"/
## "OFFLINE") — captured by the caller BEFORE the reset/restart actually
## changes it, so the chance reflects the hazard the player was actually
## reaching into, not the post-fix state. `generator_health` defaults to
## 100 (irrelevant/full) for the breaker-reset call site, which has no
## generator of its own.
func roll_electrical_burn(grid_state_string: String, generator_health: float = 100.0) -> void:
	var chance: float = ELECTRICAL_BURN_CHANCE_ONLINE
	match grid_state_string:
		"BROWNOUT": chance = ELECTRICAL_BURN_CHANCE_BROWNOUT
		"OVERLOADED": chance = ELECTRICAL_BURN_CHANCE_OVERLOADED
		"TRIPPED": chance = ELECTRICAL_BURN_CHANCE_TRIPPED
		"OFFLINE": chance = ELECTRICAL_BURN_CHANCE_OFFLINE
	if generator_health < ELECTRICAL_BURN_LOW_HEALTH_THRESHOLD:
		chance += ELECTRICAL_BURN_CHANCE_LOW_HEALTH_BONUS
	_roll_burn(chance, "electrical")

## Splint (Pass 2, extended Aug 2026) — per the design doc, NOT required
## for Fractured to heal at all (natural healing always happens), but
## dramatically hastens it and relieves symptom penalties while worn.
## Destroyed implicitly when Fractured converts to Broken (the new Broken
## instance starts with is_treated = false regardless). ALSO applies to
## Broken directly (Aug 2026 — previously an open design question, now
## resolved, see BROKEN_SPLINT_HASTEN_MULT's own comment) — checks for a
## Fractured on this body part first, falls back to Broken if none.
func apply_splint(body_part: int) -> void:
	var frac: MedicalCondition = get_condition_by_id_and_part("fractured", body_part)
	if frac != null:
		frac.is_treated = true
		return
	var broken: MedicalCondition = get_condition_by_id_and_part("broken", body_part)
	if broken != null:
		broken.is_treated = true

## Splint's injury-selection submenu query — every body part with an
## active Fractured OR Broken condition (Aug 2026 — Broken added; see
## apply_splint()'s own comment). Worst-severity-first, same convention as
## get_eligible_bleeding_targets() — Broken is always pinned at 100%
## severity, so it naturally sorts to the very top alongside/above any
## Fractured entries, matching "point the player at the most urgent one."
func get_eligible_splint_targets() -> Array:
	var targets: Array[MedicalCondition] = []
	for c in active_conditions:
		if c.id == "fractured" or c.id == "broken":
			targets.append(c)
	targets.sort_custom(func(a: MedicalCondition, b: MedicalCondition) -> bool: return a.severity > b.severity)
	var out: Array = []
	for c in targets:
		var detail: String = ("Severity: %d%%" % int(c.severity)) if c.id == "fractured" else "Broken"
		out.append({
			"body_part": c.body_part,
			"label": MedicalCondition.body_part_label(c.body_part),
			"detail": detail,
		})
	return out

## Trauma Kit's mass-apply (Aug 2026) — bandages EVERY active Bleeding
## condition and splints EVERY active Fractured condition, all at once, no
## target selection. Deliberately simple/open-ended baseline: Trauma Kit
## doesn't have a full role yet since this game hasn't touched more
## serious injuries (gunshots, chronic diseases, etc.) that would give it
## a more distinct job from Bandage/Splint combined — see
## docs/systems/medical/README.md's Trauma Kit scope note. Calls the same
## real treat_bleeding()/apply_splint() functions everything else uses.
func treat_all_bleeding_and_fractures() -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for c in conditions_copy:
		if c.id == "bleeding":
			treat_bleeding(c.body_part)
		elif c.id == "fractured":
			apply_splint(c.body_part)

func get_medical_speed_multiplier() -> float:
	var mult: float = 1.0
	for c in active_conditions:
		mult *= c.speed_mult
	return mult

## Aug 2026 — mirrors get_medical_speed_multiplier() above for the two new
## body-part-gated stamina-drain fields. See
## docs/systems/medical/README.md's "Body-part-differentiated symptom
## effects". get_medical_sprint_stamina_drain_multiplier() is wired into
## Player.gd's real sprint-drain line; get_medical_carry_stamina_drain_
## multiplier() is wired into Player.gd's heavy-carry-drain line (Aug
## 2026, once that base mechanic existed for it to multiply).
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

## Aug 2026 — aggregate getter for `work_speed_mult`, added once the Job
## Progress Bar system (docs/systems/player/README.md) gave it a real
## consumer. Mirrors the three getters above exactly — multiplicative
## across every active condition, 1.0 (no effect) when nothing's active.
## Consulted by InteractionSystem._job_speed_mult() every job-tick, scaling
## how fast the progress bar fills.
func get_medical_job_speed_multiplier() -> float:
	var mult: float = 1.0
	for c in active_conditions:
		mult *= c.work_speed_mult
	return mult

func get_medical_status_labels() -> Array[String]:
	var labels: Array[String] = []
	for c in active_conditions:
		var part_label: String = MedicalCondition.body_part_label(c.body_part)
		if c.id == "bleeding":
			labels.append("Bleeding (%s, %d%%)" % [part_label, int(c.severity)])
		elif c.id == "open_wound":
			if c.is_infected:
				labels.append("Open Wound (Infected) (%s, %d%%)" % [part_label, int(c.infection_severity)])
			else:
				labels.append("Open Wound (%s)" % part_label)
		elif c.id == "fractured":
			labels.append("Fractured (%s, %d%%)" % [part_label, int(c.severity)])
		elif c.id == "broken":
			labels.append("Broken (%s)" % part_label)
		elif c.id == "burn":
			labels.append("Burn (%s)" % part_label)
		else:
			labels.append("%s (%s)" % [c.id.capitalize(), part_label])
	return labels

func add_condition(condition: MedicalCondition) -> void:
	active_conditions.append(condition)
	condition_added.emit(condition)
	if condition.id != "bleeding":
		_add_hud_badge(condition)

func remove_condition(condition: MedicalCondition) -> void:
	active_conditions.erase(condition)
	condition_removed.emit(condition)
	if condition.id != "bleeding":
		_remove_hud_badge(condition)

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

# ─── HUD ──────────────────────────────────────────────────────────────────────
## Fixed id for the single, consolidated Bleeding badge — deliberately NOT
## per-body-part, unlike every other condition's badge. See
## docs/systems/medical/README.md's "Ambient display rule": multiple
## simultaneously bleeding wounds share ONE ambient icon showing only the
## worst one, so the player is always pointed at the most urgent wound
## first. Each wound's own bleeding status is still visible in that
## wound's own Open Wound tooltip — see _tooltip_for()'s "open_wound" case.
const BLEEDING_BADGE_ID: String = "bleeding"
var _bleeding_badge_present: bool = false

func _hud_badge_id(condition: MedicalCondition) -> String:
	return "%s_%d" % [condition.id, condition.body_part]

func _ring_color_for(condition: MedicalCondition) -> Color:
	match condition.id:
		"bleeding":
			return BLEEDING_RING_COLOR
		"fractured":
			return FRACTURED_RING_COLOR
		"broken":
			return BROKEN_RING_COLOR
		"burn":
			return BURN_RING_COLOR
		_:
			return OPEN_WOUND_RING_COLOR   ## default/fallback, covers open_wound

func _add_hud_badge(condition: MedicalCondition) -> void:
	if _status_effects == null:
		_status_effects = _find_status_effects()
		if _status_effects == null:
			return
	_status_effects.add_medical_effect(
		_hud_badge_id(condition), null, _ring_color_for(condition), condition.has_heal_ring
	)
	_update_hud_badge(condition)   ## push initial fill immediately, don't wait for next _process tick

func _remove_hud_badge(condition: MedicalCondition) -> void:
	if _status_effects == null:
		_status_effects = _find_status_effects()
		if _status_effects == null:
			return
	_status_effects.remove_effect(_hud_badge_id(condition))

## Scans every active Bleeding condition (regardless of body part) and
## drives the single consolidated badge from whichever currently has the
## highest severity — see BLEEDING_BADGE_ID's comment above. Called once
## per _process() tick, after every individual condition has already been
## ticked, so it always reflects this frame's freshest severities.
func _update_bleeding_badge() -> void:
	if _status_effects == null:
		_status_effects = _find_status_effects()
		if _status_effects == null:
			return
	var worst: MedicalCondition = null
	for c in active_conditions:
		if c.id == "bleeding" and (worst == null or c.severity > worst.severity):
			worst = c
	if worst == null:
		if _bleeding_badge_present:
			_status_effects.remove_effect(BLEEDING_BADGE_ID)
			_bleeding_badge_present = false
		return
	if not _bleeding_badge_present:
		_status_effects.add_medical_effect(BLEEDING_BADGE_ID, null, BLEEDING_RING_COLOR, false)
		_bleeding_badge_present = true
	_status_effects.update_medical_effect(BLEEDING_BADGE_ID, worst.severity / 100.0, 0.0, _tooltip_for(worst))

func _update_hud_badge(condition: MedicalCondition) -> void:
	if _status_effects == null:
		return
	var severity_frac: float = condition.severity / 100.0
	var heal_frac: float = condition.heal_progress / 100.0 if condition.has_heal_ring else 0.0
	var id: String = _hud_badge_id(condition)
	_status_effects.update_medical_effect(id, severity_frac, heal_frac, _tooltip_for(condition))
	if condition.id == "open_wound":
		_status_effects.update_medical_outer_ring(
			id, condition.is_infected, condition.infection_severity / 100.0, INFECTION_RING_COLOR
		)

## Every currently non-1.0 symptom effect this condition contributes, in
## Brannon's exact display shape ("0.25x Movement Speed", "0.5x Stamina
## Drain (While Carrying)", "0.75x Stamina Drain (While Sprinting)") — see
## docs/systems/medical/README.md's "Body-part-differentiated symptom
## effects". A condition with no active effect (Bleeding, a plain
## uninfected Open Wound) returns an empty array — callers must NOT pad
## with 1.0x no-op lines. The header line above already names the
## body-part-labeled condition (e.g. "Fractured (Left Leg)"), so these
## lines don't repeat the source, only the effect.
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

func _tooltip_for(condition: MedicalCondition) -> String:
	var part_label: String = MedicalCondition.body_part_label(condition.body_part)
	if condition.id == "bleeding":
		return "Bleeding (%s)\nSeverity: %d%%\nHP loss: %.2f/sec" % [part_label, int(condition.severity), condition.hp_drain_per_second]
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
			lines.append("Bleeding: %d%% (%.2f HP/sec)" % [int(bleed.severity), bleed.hp_drain_per_second])
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

func debug_print_state() -> void:
	if active_conditions.is_empty():
		print("[PlayerMedical] No active conditions.")
		return
	print("[PlayerMedical] %d active condition(s):" % active_conditions.size())
	for c in active_conditions:
		var extra: String = ""
		if c.id == "open_wound" and c.is_infected:
			extra = " infected=%.1f" % c.infection_severity
		print("  - %s (%s): severity=%.1f heal_progress=%.1f target=%.1fh treated=%s%s" % [
			c.id, MedicalCondition.body_part_label(c.body_part), c.severity, c.heal_progress,
			c.heal_time_target_hours, c.is_treated, extra
		])
	if _player_stats != null:
		print("  caps: food=%.1f water=%.1f sleep=%.1f" % [_player_stats.food_cap, _player_stats.water_cap, _player_stats.sleep_cap])

func debug_clear_all() -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for c in conditions_copy:
		remove_condition(c)

# ─── F7 debug helpers (Pass 2) ──────────────────────────────────────────────
## Every debug helper below calls the exact same underlying functions real
## gameplay will eventually use — see plans/medical-system-implementation-
## plan.md's "Cross-cutting notes" rule. Public specifically so AdminMenu.gd
## can call them without reaching into private (_-prefixed) internals.

## Forces infection on the first active, not-yet-infected Open Wound found
## (any body part) — bypasses the rising-hazard-curve roll for testing.
func debug_force_infect_nearest_wound() -> void:
	for c in active_conditions:
		if c.id == "open_wound" and not c.is_infected and not c.infection_resolved:
			c.is_infected = true
			c.infection_severity = 1.0
			return

## Adjusts Infection Severity on every currently-infected Open Wound by
## `delta` (clamped 0-100) — for testing the needs-cap curve and the
## dual-ring HUD without waiting on the real rise/fall rate.
func debug_adjust_infection_severity(delta: float) -> void:
	for c in active_conditions:
		if c.id == "open_wound" and c.is_infected:
			c.infection_severity = clampf(c.infection_severity + delta, 0.0, 100.0)

## Forces one Fracture-escalation roll on every active Fractured condition,
## regardless of body part (the real trigger fires separately per limb via
## Player.gd's exhausted signal — legs from sprint-exhaustion, arms from
## heavy-carry-exhaustion — this is deliberately broader for testing, both
## at once). Converts to Broken if the roll pushes severity to 100, same
## as the real path. Shares its math with the real trigger via
## _escalate_fracture().
func debug_force_escalate_all_fractures() -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for frac in conditions_copy:
		if frac.id == "fractured":
			_escalate_fracture(frac)

## Forces every active Fractured condition straight to 100% severity and
## converts it to Broken immediately — for testing Broken's own behavior
## without waiting through several real/forced escalation steps.
func debug_force_break_all_fractures() -> void:
	var conditions_copy: Array[MedicalCondition] = active_conditions.duplicate()
	for frac in conditions_copy:
		if frac.id != "fractured":
			continue
		frac.severity = 100.0
		_convert_fractured_to_broken(frac)
