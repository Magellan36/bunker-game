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
const PROXY_DISTANCE: float = 6.0
const PROXY_HEIGHT:   float = 1.8

## Smoothing rate (per second, framerate-independent exponential smoothing)
## for both direction and energy — this is what produces "shadow sweeps as
## you walk" instead of a twitchy snap between light-weight zones. Higher =
## snappier response, lower = more languid drift.
const SMOOTH_RATE: float = 3.0

## Below this smoothed total weight, the proxy turns off entirely rather
## than pointing in a near-arbitrary direction with no meaningful nearby
## light to derive it from.
const MIN_TOTAL_WEIGHT: float = 0.05

## First-pass eyeballed values converting aggregate real-light weight into
## this proxy's light_energy, so a character standing well-lit by nearby
## fixtures reads at roughly the brightness they used to when directly lit
## by those fixtures. NOT derived from a physical calculation — this is
## the single most likely thing to need a visual tuning pass once you see
## it in-editor (see the plan doc's "Important side effect" section: this
## proxy is now each character's ONLY direct light source).
const ENERGY_SCALE: float = 0.6
const MAX_ENERGY:    float = 3.0

const SPOT_ANGLE:             float = 25.0
const SPOT_ANGLE_ATTENUATION: float = 0.5
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
	if not GraphicsSettings.shadow_casting_enabled:
		_spot.visible = false
		return

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
	_spot.light_energy  = min(_current_weight * ENERGY_SCALE, MAX_ENERGY)
	global_position      = char_pos - (_current_dir * PROXY_DISTANCE) + Vector3(0.0, PROXY_HEIGHT, 0.0)
	## Aim slightly above the character's own origin (torso height rather
	## than floor-level feet) so the beam doesn't graze the ground on its
	## way in — global_position/look_at both operate in world space, so
	## this is correct regardless of the owning character's own rotation.
	look_at(char_pos + Vector3(0.0, 1.0, 0.0), Vector3.UP)