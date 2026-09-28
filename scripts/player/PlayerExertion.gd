extends RefCounted
## Active-time exertion state. Player remains the owner of stamina; Medical
## consumes exposure doses and decides injuries. No game-clock or RNG here.

const GRACE_SECONDS: float = 2.0
const FULL_STRAIN_SECONDS: float = 30.0
const RECOVERY_RATE: float = 2.0
const ACCIDENT_COOLDOWN: float = 12.0

var exhausted: bool = false
var just_exhausted: bool = false
var legs_active: bool = false
var arms_active: bool = false
var leg_seconds: float = 0.0
var arm_seconds: float = 0.0
var leg_dose: float = 0.0
var arm_dose: float = 0.0
var accident_cooldown: float = 0.0

func advance(delta: float, stamina: float, sprinting: bool, carrying: bool,
		drain: float, regen: float, recover_threshold: float) -> float:
	just_exhausted = false
	leg_dose = 0.0
	arm_dose = 0.0
	var previous_stamina: float = stamina
	if drain > 0.0:
		stamina = maxf(0.0, stamina - drain * delta)
	else:
		stamina = minf(100.0, stamina + regen * delta)
	if stamina <= 0.0 and drain > 0.0 and not exhausted:
		exhausted = true
		just_exhausted = true
	elif drain <= 0.0 and stamina >= recover_threshold:
		exhausted = false
	legs_active = exhausted and sprinting
	arms_active = exhausted and carrying
	# Only count the part of this step actually spent beyond empty stamina.
	var exposure_delta: float = delta
	if just_exhausted:
		exposure_delta = maxf(0.0, delta - previous_stamina / maxf(drain, 0.001))
	var cooldown_at_exposure: float = maxf(0.0, accident_cooldown - (delta - exposure_delta))
	var protected_delta: float = minf(exposure_delta, cooldown_at_exposure)
	accident_cooldown = maxf(0.0, accident_cooldown - delta)
	if legs_active:
		leg_dose = _dose_integral(leg_seconds + exposure_delta) - _dose_integral(leg_seconds + protected_delta)
		leg_seconds += exposure_delta
	else:
		leg_seconds = maxf(0.0, leg_seconds - delta * RECOVERY_RATE)
	if arms_active:
		arm_dose = _dose_integral(arm_seconds + exposure_delta) - _dose_integral(arm_seconds + protected_delta)
		arm_seconds += exposure_delta
	else:
		arm_seconds = maxf(0.0, arm_seconds - delta * RECOVERY_RATE)
	return stamina

## Integral of a linear risk ramp, zero during the grace period and capped
## after FULL_STRAIN_SECONDS. Subdividing a frame preserves the same dose.
static func _dose_integral(seconds: float) -> float:
	var t: float = maxf(0.0, seconds - GRACE_SECONDS)
	var ramp: float = FULL_STRAIN_SECONDS - GRACE_SECONDS
	var rising: float = minf(t, ramp)
	return 0.1 * rising + 0.9 * rising * rising / (2.0 * ramp) + maxf(0.0, t - ramp)

func intensity() -> float:
	return clampf(maxf(leg_seconds, arm_seconds) / FULL_STRAIN_SECONDS, 0.0, 1.0)

func movement_multiplier(sprinting: bool) -> float:
	if not legs_active and not arms_active:
		return 1.0
	if arms_active:
		return lerpf(0.65, 0.45, intensity())
	return lerpf(0.78, 0.60, intensity()) if sprinting else 1.0

func note_accident() -> void:
	accident_cooldown = ACCIDENT_COOLDOWN

func suspend() -> void:
	# A modal/job cannot conceal an accident or provide free load recovery.
	legs_active = false
	arms_active = false
	leg_dose = 0.0
	arm_dose = 0.0
	just_exhausted = false

func get_save_data(stamina: float) -> Dictionary:
	return {"stamina": stamina, "exhausted": exhausted, "legs": leg_seconds,
		"arms": arm_seconds, "cooldown": accident_cooldown}

func restore(data: Dictionary) -> float:
	exhausted = bool(data.get("exhausted", false))
	leg_seconds = clampf(float(data.get("legs", 0.0)), 0.0, 3600.0)
	arm_seconds = clampf(float(data.get("arms", 0.0)), 0.0, 3600.0)
	accident_cooldown = clampf(float(data.get("cooldown", 0.0)), 0.0, ACCIDENT_COOLDOWN)
	legs_active = false
	arms_active = false
	just_exhausted = false
	leg_dose = 0.0
	arm_dose = 0.0
	return clampf(float(data.get("stamina", 100.0)), 0.0, 100.0)
