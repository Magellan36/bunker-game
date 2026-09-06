extends Control
class_name StatusEffectIcon
## Compact ambient status badge shared by ordinary timed effects and externally
## driven medical conditions. This pass deliberately preserves the original
## 50px footprint, ring math, medical layering, tooltip API, and expiry signal;
## it only brings the presentation into the approved bunker UI family.

signal expired(effect_id: String)

const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")

const BADGE_SIDE: float = 50.0
const RADIUS: float = 22.0
const THICKNESS: float = 4.0
const ICON_SIZE: float = 21.0
const BG_RING_COLOR: Color = Color("111716f2")
const TRACK_EDGE_COLOR: Color = Color("5c4c35a8")
const PANEL_SHADOW: Color = Color("050706bd")
const PANEL_COLOR: Color = Color("181d1df5")
const PANEL_INNER: Color = Color("202625f0")
const INNER_KEYLINE: Color = Color("88734e70")
const ICON_COLOR: Color = Color("f2e8cf")
const ICON_SHADOW: Color = Color("050706b8")
const RUGGED_BORDER_COLOR: Color = Color("050706b8")
const RUGGED_BORDER_WIDTH: float = 1.15

## Healing still overlays the beginning of the severity arc. The cool blue is
## the one established HUD meaning retained across every medical condition.
const HEAL_COLOR: Color = Color("66bfff")
const HEAL_SHEEN: Color = Color("d5f0ffb8")

const OUTER_RING_GAP: float = 0.0
const OUTER_RING_THICKNESS: float = 3.0
const CRITICAL_THRESHOLD: float = 0.80
const EXPIRY_PULSE_THRESHOLD: float = 0.15
const ARRIVAL_DURATION: float = 0.16
const DISMISS_DURATION: float = 0.12
const RING_RESPONSE: float = 10.0
const LAYOUT_DURATION: float = 0.18

var effect_id: String = ""
var _icon: Texture2D = null
var _ring_color: Color = Color("db9130")

## Timer-mode state.
var _total_duration: float = 1.0
var _remaining: float = 1.0
var _display_remaining: float = 1.0

## Medical-mode state. Severity and healing deliberately share one track.
var _is_medical: bool = false
var _severity_frac: float = 1.0
var _heal_frac: float = 0.0
var _display_severity_frac: float = 1.0
var _display_heal_frac: float = 0.0
var _has_heal_ring: bool = false
var _received_medical_update: bool = false

## A genuinely separate ring, currently used for infection severity.
var _has_outer_ring: bool = false
var _outer_frac: float = 0.0
var _display_outer_frac: float = 0.0
var _outer_color: Color = Color("bf8c26")
var _received_outer_update: bool = false

## Presentation-only animation state. None of these values alter simulation.
var _animation_time: float = 0.0
var _arrival_flash: float = 0.0
var _has_been_setup: bool = false
var _dismissing: bool = false
var _layout_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = Vector2(BADGE_SIDE, BADGE_SIDE)
	pivot_offset = Vector2(BADGE_SIDE * 0.5, BADGE_SIDE * 0.5)
	var grime_mat := ShaderMaterial.new()
	grime_mat.shader = load("res://assets/shaders/grunge_overlay.gdshader")
	material = grime_mat
	mouse_filter = Control.MOUSE_FILTER_STOP


## Starts or refreshes a timer badge. Reapplying an existing effect resets its
## duration in place, but the entrance animation only plays on first creation.
func setup(id: String, icon: Texture2D, duration: float, ring_color: Color) -> void:
	var first_setup: bool = not _has_been_setup
	effect_id = id
	_icon = icon
	_total_duration = maxf(duration, 0.01)
	_remaining = _total_duration
	if first_setup:
		_display_remaining = _remaining
	_ring_color = ring_color
	_is_medical = false
	_play_arrival_once()
	queue_redraw()


## Starts or refreshes an externally driven medical badge.
func setup_medical(id: String, icon: Texture2D, ring_color: Color, has_heal_ring: bool) -> void:
	effect_id = id
	_icon = icon
	_ring_color = ring_color
	_has_heal_ring = has_heal_ring
	_is_medical = true
	_severity_frac = 1.0
	_heal_frac = 0.0
	_display_severity_frac = 1.0
	_display_heal_frac = 0.0
	_received_medical_update = false
	_play_arrival_once()
	queue_redraw()


func update_medical(severity_frac: float, heal_frac: float, tooltip: String) -> void:
	_severity_frac = clampf(severity_frac, 0.0, 1.0)
	_heal_frac = clampf(heal_frac, 0.0, 1.0)
	if not _received_medical_update:
		_display_severity_frac = _severity_frac
		_display_heal_frac = _heal_frac
		_received_medical_update = true
	tooltip_text = tooltip
	queue_redraw()


func set_outer_ring(has_outer: bool, frac: float, color: Color) -> void:
	_has_outer_ring = has_outer
	_outer_frac = clampf(frac, 0.0, 1.0) if has_outer else 0.0
	if not _received_outer_update:
		_display_outer_frac = _outer_frac
		_received_outer_update = true
	_outer_color = color
	queue_redraw()


## Used by StatusEffectsContainer on removal. The data structure updates
## immediately; this short visual settle never delays gameplay state.
func dismiss() -> void:
	if _dismissing:
		return
	_dismissing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, DISMISS_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(0.94, 0.94), DISMISS_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free, CONNECT_ONE_SHOT)


## Container-driven layout movement. New badges snap into their reserved slot
## before fading in; surviving badges glide into vacated slots on removal.
func set_layout_position(target: Vector2, animated: bool) -> void:
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()
	if not animated or position.is_equal_approx(target):
		position = target
		return
	_layout_tween = create_tween()
	_layout_tween.tween_property(self, "position", target, LAYOUT_DURATION).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)


func _play_arrival_once() -> void:
	if _has_been_setup:
		return
	_has_been_setup = true
	_arrival_flash = 0.34
	modulate.a = 0.0
	scale = Vector2(0.92, 0.92)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, ARRIVAL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, ARRIVAL_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_animation_time = fmod(_animation_time + delta, 20.0)
	var ring_weight: float = 1.0 - exp(-RING_RESPONSE * delta)
	var ring_changed: bool = _approach_ring_values(ring_weight)
	if _arrival_flash > 0.0:
		_arrival_flash = maxf(0.0, _arrival_flash - delta)

	if _is_medical:
		if ring_changed or _arrival_flash > 0.0 or (_has_heal_ring and _display_heal_frac > 0.0) or _critical_strength() > 0.0:
			queue_redraw()
		return

	if _remaining <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - delta)
	queue_redraw()
	if _remaining <= 0.0:
		expired.emit(effect_id)


func _draw() -> void:
	var center: Vector2 = Vector2(BADGE_SIDE * 0.5, BADGE_SIDE * 0.5)
	_draw_state_glow(center)
	if _has_outer_ring or _display_outer_frac > 0.001:
		_draw_outer_ring(center)

	# Layered charcoal face and restrained brass keyline match the approved
	# panels without turning this tiny HUD element into a miniature card.
	draw_circle(center + Vector2(0.0, 1.5), RADIUS - 0.5, PANEL_SHADOW)
	draw_circle(center, RADIUS - THICKNESS * 0.45, PANEL_COLOR)
	draw_circle(center, RADIUS - THICKNESS - 1.2, PANEL_INNER)
	draw_arc(center, RADIUS - THICKNESS - 0.7, 0.0, TAU, 48, INNER_KEYLINE, 1.0, true)

	# A dark-brass under-track creates readable edge separation at 50px while
	# the original fill thickness and arc fractions stay unchanged.
	draw_arc(center, RADIUS, 0.0, TAU, 48, TRACK_EDGE_COLOR, THICKNESS + 1.4, true)
	draw_arc(center, RADIUS, 0.0, TAU, 48, BG_RING_COLOR, THICKNESS, true)
	if _is_medical:
		_draw_medical_rings(center)
	else:
		_draw_timer_ring(center)

	_draw_icon(center)
	UIKit.draw_rugged_circle(self, center, RADIUS + THICKNESS * 0.5,
		RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 700.0)
	UIKit.draw_rugged_circle(self, center, RADIUS - THICKNESS * 0.5,
		RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 850.0)


func _draw_icon(center: Vector2) -> void:
	var half: float = ICON_SIZE * 0.5
	var destination := Rect2(center - Vector2(half, half), Vector2(ICON_SIZE, ICON_SIZE))
	if _icon != null:
		draw_texture_rect(_icon, destination, false)
		return
	var fallback: Texture2D = S.icon(_symbol_for_effect())
	var shadow_destination := Rect2(destination.position + Vector2(0.8, 1.2), destination.size)
	draw_texture_rect(fallback, shadow_destination, false, ICON_SHADOW)
	draw_texture_rect(fallback, destination, false, ICON_COLOR)


func _symbol_for_effect() -> String:
	var id: String = effect_id.to_lower()
	if _is_medical:
		if (_has_outer_ring or _display_outer_frac > 0.001) and _display_outer_frac > 0.0:
			return "infection"
		if id.contains("bleed"):
			return "bleeding"
		if id.contains("fractur") or id.contains("broken"):
			return "fracture"
		if id.contains("burn"):
			return "burn"
		if id.contains("infect"):
			return "infection"
		if id.contains("wound"):
			return "bandage"
		return "medical"
	if id.contains("warm") or id.contains("cold") or id.contains("temperature") or id.contains("heat"):
		return "temperature"
	if id.contains("work") or id.contains("repair") or id.contains("efficien") or id.contains("build"):
		return "settings"
	if id.contains("sleep") or id.contains("fatigue") or id.contains("tired") or id.contains("rest"):
		return "sleep"
	if id.contains("poison") or id.contains("toxic") or id.contains("sick"):
		return "warning"
	return "status"


func _draw_state_glow(center: Vector2) -> void:
	if _arrival_flash > 0.0:
		var arrival_alpha: float = clampf(_arrival_flash / 0.34, 0.0, 1.0) * 0.16
		draw_circle(center, RADIUS + 4.0, Color(S.BLUE.r, S.BLUE.g, S.BLUE.b, arrival_alpha))
	var critical: float = _critical_strength()
	if critical <= 0.0:
		return
	var pulse: float = 0.5 + 0.5 * sin(_animation_time * TAU * 0.72)
	var alpha: float = critical * (0.035 + pulse * 0.055)
	draw_circle(center, RADIUS + 4.0, Color(S.RED.r, S.RED.g, S.RED.b, alpha))


func _critical_strength() -> float:
	if not _is_medical or _display_severity_frac < CRITICAL_THRESHOLD:
		return 0.0
	var unresolved: float = maxf(0.0, _display_severity_frac - _display_heal_frac)
	if unresolved < 0.42:
		return 0.0
	return clampf((_display_severity_frac - CRITICAL_THRESHOLD) / (1.0 - CRITICAL_THRESHOLD), 0.0, 1.0)


func _draw_outer_ring(center: Vector2) -> void:
	var outer_radius: float = RADIUS + THICKNESS * 0.5 + OUTER_RING_GAP + OUTER_RING_THICKNESS * 0.5
	draw_arc(center, outer_radius, 0.0, TAU, 48, BG_RING_COLOR, OUTER_RING_THICKNESS, true)
	if _display_outer_frac > 0.0:
		var end_angle: float = -PI / 2.0 + TAU * _display_outer_frac
		draw_arc(center, outer_radius, -PI / 2.0, end_angle, 48, _outer_color, OUTER_RING_THICKNESS, true)
	UIKit.draw_rugged_circle(self, center, outer_radius + OUTER_RING_THICKNESS * 0.5,
		RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 1000.0)
	UIKit.draw_rugged_circle(self, center, outer_radius - OUTER_RING_THICKNESS * 0.5,
		RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 1150.0)


func _draw_timer_ring(center: Vector2) -> void:
	if _total_duration <= 0.0:
		return
	var fraction: float = _display_remaining / _total_duration
	if fraction <= 0.0:
		return
	var display_color: Color = _ring_color
	if fraction <= EXPIRY_PULSE_THRESHOLD:
		var pulse: float = 0.5 + 0.5 * sin(_animation_time * TAU * 1.15)
		display_color = _ring_color.lightened(pulse * 0.16)
	var end_angle: float = -PI / 2.0 + TAU * fraction
	draw_arc(center, RADIUS, -PI / 2.0, end_angle, 48, display_color.darkened(0.32), THICKNESS + 1.0, true)
	draw_arc(center, RADIUS, -PI / 2.0, end_angle, 48, display_color, THICKNESS, true)


func _draw_medical_rings(center: Vector2) -> void:
	if _display_severity_frac > 0.0:
		var severity_end: float = -PI / 2.0 + TAU * _display_severity_frac
		draw_arc(center, RADIUS, -PI / 2.0, severity_end, 48,
			_ring_color.darkened(0.34), THICKNESS + 1.0, true)
		draw_arc(center, RADIUS, -PI / 2.0, severity_end, 48, _ring_color, THICKNESS, true)
	if not _has_heal_ring or _display_heal_frac <= 0.0:
		return
	var heal_end: float = -PI / 2.0 + TAU * _display_heal_frac
	draw_arc(center, RADIUS, -PI / 2.0, heal_end, 48, HEAL_COLOR.darkened(0.30), THICKNESS + 1.0, true)
	draw_arc(center, RADIUS, -PI / 2.0, heal_end, 48, HEAL_COLOR, THICKNESS, true)
	_draw_healing_sheen(center)


func _draw_healing_sheen(center: Vector2) -> void:
	var heal_sweep: float = TAU * _display_heal_frac
	if heal_sweep <= 0.035:
		return
	var travel_fraction: float = fmod(_animation_time * 0.28, 1.0)
	var sheen_center: float = -PI / 2.0 + heal_sweep * travel_fraction
	var half_width: float = minf(0.10, heal_sweep * 0.28)
	var sheen_start: float = maxf(-PI / 2.0, sheen_center - half_width)
	var sheen_end: float = minf(-PI / 2.0 + heal_sweep, sheen_center + half_width)
	if sheen_end > sheen_start:
		draw_arc(center, RADIUS, sheen_start, sheen_end, 8, HEAL_SHEEN, THICKNESS + 0.8, true)


func _approach_ring_values(weight: float) -> bool:
	var before_remaining: float = _display_remaining
	var before_severity: float = _display_severity_frac
	var before_heal: float = _display_heal_frac
	var before_outer: float = _display_outer_frac
	_display_remaining = _snap_near(lerpf(_display_remaining, _remaining, weight), _remaining)
	_display_severity_frac = _snap_near(
		lerpf(_display_severity_frac, _severity_frac, weight), _severity_frac
	)
	_display_heal_frac = _snap_near(lerpf(_display_heal_frac, _heal_frac, weight), _heal_frac)
	_display_outer_frac = _snap_near(lerpf(_display_outer_frac, _outer_frac, weight), _outer_frac)
	return (
		not is_equal_approx(before_remaining, _display_remaining)
		or not is_equal_approx(before_severity, _display_severity_frac)
		or not is_equal_approx(before_heal, _display_heal_frac)
		or not is_equal_approx(before_outer, _display_outer_frac)
	)


func _snap_near(value: float, target: float) -> float:
	return target if absf(value - target) < 0.0005 else value
