extends Node3D
class_name CharacterShadowProxy
## CharacterShadowProxy.gd
## Aug 2026 — replaces per-character real shadow reception from every
## individual WallLight/GrowLight with ONE aggregated shadow-casting
## SpotLight3D per character (player or NPC). See
## docs/systems/graphics/README.md "Aggregated character shadows" for full
## design rationale — short version: with the game's fixed top-down
## isometric camera, every shadow from every nearby real light is visible
## at once (unlike an over-the-shoulder camera where most would be
## off-screen), so 6+ real lights near a character reads as clutter rather
## than depth. Instead, every real light's light_cull_mask now excludes
## GraphicsSettings.CHARACTER_SHADOW_LAYER_BIT (see WallLight.gd/
## GrowLight.gd/Flashlight.gd), and this node's SpotLight3D is the only
## light that INCLUDES that bit — so it becomes this character's sole
## direct light source too, not just its shadow (GI/SDFGI ambient is
## unaffected and still applies underneath).
##
## Instantiated dynamically by Player._ready()/NPC._ready() (same pattern
## MainWorld._setup_tilt_shift_dof() already uses) — not scene-defined, so
## it never needs a .tscn edit.
##
## Scoped to WallLight/GrowLight only — Flashlight is deliberately excluded
## from the aggregate (it's a held/aimed light on the same entity it would
## be lighting; its own self-shadow exclusion already covers the wielder).
## See the plan doc's "Scope decisions" section before treating that as a
## bug.

## Fixed offset for the proxy light's position relative to the character —
## NOT derived from real light distances, deliberately. Guarantees a
## consistently dramatic long shadow regardless of how far the real lights
## actually are, rather than only getting a long one when a real light
## happens to be far away. Direction comes from the aggregate; these are
## "how dramatic should this look" art-direction knobs.
##
## Aug 2026 fix v3 — the v2 values (2.5m offset, near-level aim) fixed
## dimness but caused a harsh "camera flash" look: a close point light on
## a small object always produces a hard bright-near/black-far gradient
## (basic Lambertian shading — same reason a desk lamp looks harsher than
## the sun on a small object), and aiming roughly level with the character
## reads as a flash to the face rather than room lighting, which comes
## from above. PROXY_HEIGHT raised well above PROXY_DISTANCE now, so the
## light comes from a ~45° overhead angle (classic soft "natural" portrait
## lighting angle) instead of level. Real point-to-point distance
## (~5.7m via horizontal+vertical offset) is back in the same range as the
## original v1 6.0m, this time paired with a properly reasoned energy
## curve below instead of a flat linear scale.
const PROXY_DISTANCE: float = 4.0
const PROXY_HEIGHT:   float = 4.0

## Smoothing rate (per second, framerate-independent exponential smoothing)
## for both direction and energy — this is what produces "shadow sweeps as
## you walk" instead of a twitchy snap between light-weight zones. Higher =
## snappier response, lower = more languid drift.
const SMOOTH_RATE: float = 3.0

## Below this smoothed total weight, the proxy turns off entirely rather
## than pointing in a near-arbitrary direction with no meaningful nearby
## light to derive it from.
const MIN_TOTAL_WEIGHT: float = 0.05

## Aug 2026 fix v3 — replaces the old linear-scale-then-hard-clamp energy
## formula (ENERGY_SCALE * weight, capped at MAX_ENERGY) with a smooth
## saturating curve (see _process() below:
## MAX_ENERGY * (1.0 - exp(-weight * ENERGY_CURVE_RATE))). The hard clamp
## was why every character in a room with several real lights nearby (their
## weights SUM together) looked identically maxed-out regardless of exact
## distance — in a lit room, total weight easily blew past the clamp for
## almost everyone. A saturating curve still has a ceiling (MAX_ENERGY,
## approached asymptotically) but differentiates "near 1 light" from "near
## 4 lights" far better than a hard cutoff does. MAX_ENERGY itself is
## lower than v2's 6.0 since a curve doesn't need the same headroom a hard
## clamp does.
const ENERGY_CURVE_RATE: float = 0.6
const MAX_ENERGY: float = 3.0

## Aug 2026 fix v3 — widened significantly (was 25°) so the beam reads as
## soft area coverage rather than a narrow flashlight beam; cone width
## itself doesn't affect the harsh near/far shading gradient (that's
## PROXY_DISTANCE/PROXY_HEIGHT's job above), but a narrow cone combined
## with a close light compounds the "flashlight in your face" read.
const SPOT_ANGLE: float = 50.0
## Reverted to Godot's own default (1.0) — v2 lowered this to 0.5 as an
## untested guess at "softer," but the direction/scale of this parameter's
## effect wasn't verified against the actual renderer. Using the engine
## default here is the safer choice while the angle/distance/curve changes
## above do the actual work of softening the look.
const SPOT_ANGLE_ATTENUATION: float = 1.0
## Gentler than v2's already-gentler-than-default 0.5 — softer distance
## falloff so brightness varies more gradually across the character's own
## small size instead of one hard-lit side and one dark side.
const SPOT_ATTENUATION: float = 0.3
## Aug 2026 fix v3 — new. Godot's light_size approximates an area light
## (rather than an infinitesimal point), which directly softens the
## lit/shadow transition into a gradient instead of a hard edge — this is
## the single most direct lever for "dramatic hard dropoff to dark shadow"
## specifically, independent of the angle/distance changes above.
const SPOT_LIGHT_SIZE: float = 0.8
## Deliberately near-white/neutral (not warm-amber like WallLight or
## grow-white like GrowLight) so it doesn't visually fight whichever real
## light is actually dominant nearby — it's meant to read as "this
## character's shadow," not as a light source in its own right.
const LIGHT_COLOR: Color = Color(1.0, 0.95, 0.85, 1.0)

var _owner_char: Node3D    = null
var _spot: SpotLight3D     = null
var _current_dir: Vector3  = Vector3.FORWARD
var _current_weight: float = 0.0

## Called once by Player._ready()/NPC._ready() immediately after
## instantiation, before add_child() finishes running this node's own
## _ready(). Just stores the reference — _ready() below does the rest.
func setup(owner_char: Node3D) -> void:
	_owner_char = owner_char

func _ready() -> void:
	_spot = SpotLight3D.new()
	_spot.light_color            = LIGHT_COLOR
	_spot.spot_angle             = SPOT_ANGLE
	_spot.spot_angle_attenuation = SPOT_ANGLE_ATTENUATION
	_spot.spot_attenuation       = SPOT_ATTENUATION
	_spot.light_size             = SPOT_LIGHT_SIZE
	_spot.spot_range             = PROXY_DISTANCE * 1.5
	_spot.light_cull_mask        = GraphicsSettings.CHARACTER_SHADOW_LAYER_BIT
	## Don't double up with the room's own real GI — this proxy isn't meant
	## to bounce light around, just directly light/shadow its one character.
	_spot.light_indirect_energy  = 0.0
	_spot.visible                = false
	add_child(_spot)
	GraphicsSettings.settings_changed.connect(_apply_graphics_settings)
	_apply_graphics_settings()

func _apply_graphics_settings() -> void:
	if _spot == null:
		return
	_spot.shadow_enabled = GraphicsSettings.shadow_casting_enabled

func _process(delta: float) -> void:
	if _owner_char == null or _spot == null:
		return
	## Aug 2026 fix — this used to also early-return (light off entirely)
	## when GraphicsSettings.shadow_casting_enabled was false. That was a
	## bug: this proxy is the character's ONLY direct light source now
	## (every real light unconditionally excludes characters from its
	## light_cull_mask, regardless of this setting — see WallLight.gd/
	## GrowLight.gd/Flashlight.gd), so gating the light itself on the
	## shadow-casting toggle made players/NPCs pitch black at the default
	## Medium preset (shadow_casting_enabled defaults false). Whether this
	## light casts an actual SHADOW already correctly follows the setting
	## via _apply_graphics_settings() above (_spot.shadow_enabled) — that's
	## the only thing that setting should control. Illumination must stay
	## unconditional. (Separately, see PROXY_DISTANCE/ENERGY_SCALE above
	## for the other half of this fix — the character was also badly
	## underlit even with shadow_casting_enabled on, before this same
	## session's constant recalibration.)

	var char_pos: Vector3 = _owner_char.global_position
	var accum: Vector3    = Vector3.ZERO
	var total_weight: float = 0.0

	var candidates: Array = []
	candidates.append_array(get_tree().get_nodes_in_group("wall_lights"))
	candidates.append_array(get_tree().get_nodes_in_group("grow_light"))

	for light: Node in candidates:
		if not light.has_method("get_shadow_weight"):
			continue
		var w: float = light.call("get_shadow_weight", char_pos)
		if w <= 0.0:
			continue
		var dir: Vector3 = char_pos - (light as Node3D).global_position
		dir.y = 0.0
		if dir.length() > 0.01:
			accum += dir.normalized() * w
		total_weight += w

	var smooth_t: float = 1.0 - exp(-SMOOTH_RATE * delta)
	_current_weight = lerp(_current_weight, total_weight, smooth_t)

	if _current_weight < MIN_TOTAL_WEIGHT:
		_spot.visible = false
		return

	if accum.length() > 0.001:
		var target_dir: Vector3 = accum.normalized()
		_current_dir = _current_dir.lerp(target_dir, smooth_t).normalized()

	_spot.visible       = true
	## Aug 2026 fix v3 — smooth saturating curve instead of
	## min(weight * ENERGY_SCALE, MAX_ENERGY). See ENERGY_CURVE_RATE/
	## MAX_ENERGY above for why — this differentiates "near 1 light" from
	## "near several summed lights" instead of both pegging identically to
	## the same hard-clamped ceiling.
	_spot.light_energy  = MAX_ENERGY * (1.0 - exp(-_current_weight * ENERGY_CURVE_RATE))
	global_position      = char_pos - (_current_dir * PROXY_DISTANCE) + Vector3(0.0, PROXY_HEIGHT, 0.0)
	## Aim slightly above the character's own origin (torso height rather
	## than floor-level feet) so the beam doesn't graze the ground on its
	## way in — global_position/look_at both operate in world space, so
	## this is correct regardless of the owning character's own rotation.
	look_at(char_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)