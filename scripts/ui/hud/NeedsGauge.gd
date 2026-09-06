extends Control
class_name NeedsGauge
## Compact five-need HUD gauge. Health and stamina face into the lower-left
## corner; food, water, and sleep fan outward. Values deplete directionally,
## while medical need caps lock equal portions at both ends of an affected arc.

const CENTER: Vector2 = Vector2(90.0, 90.0)
const GAUGE_ROTATION: float = -PI / 4.0
const RING1_RADIUS: float = 40.0
const RING2_RADIUS: float = 56.0
const RING3_RADIUS: float = 74.0
const RING1_THICKNESS: float = 10.0
const RING2_THICKNESS: float = 10.0
const RING3_THICKNESS: float = 9.0
const CENTER_CIRCLE_RADIUS: float = 32.0
const GAP_ANGLE_DEG: float = 14.0
const ARC_SEGMENTS: int = 48
const VALUE_RESPONSE: float = 10.0
const CAP_RESPONSE: float = 7.0
const CENTER_CIRCLE_COLOR: Color = Color(0.13, 0.13, 0.13, 0.88)
const TRACK_COLOR: Color = Color(0.08, 0.08, 0.08, 0.90)
const CAPPED_TRACK_COLOR: Color = Color(0.35, 0.12, 0.10, 0.55)
const ICON_WELL_COLOR: Color = Color("171c1b")
const ICON_KEYLINE_COLOR: Color = Color("6f6045")
const ICON_COLOR: Color = Color("f2e8cf")
const RUGGED_BORDER_COLOR: Color = Color(0.02, 0.02, 0.02, 0.55)
const RUGGED_BORDER_WIDTH: float = 1.4

# Original HUD palette, intentionally preserved around the new geometry.
const COLOR_HEALTH: Color = Color(0.81, 0.17, 0.17, 1.0)
const COLOR_FOOD: Color = Color(0.90, 0.52, 0.14, 1.0)
const COLOR_STAMINA: Color = Color(0.29, 0.81, 0.24, 1.0)
const COLOR_WATER: Color = Color(0.24, 0.52, 0.90, 1.0)
const COLOR_SLEEP: Color = Color(0.57, 0.33, 0.81, 1.0)

var _health: float = 1.0
var _food: float = 1.0
var _stamina: float = 1.0
var _water: float = 1.0
var _sleep: float = 1.0
var _food_cap: float = 1.0
var _water_cap: float = 1.0
var _sleep_cap: float = 1.0
var _display_health: float = 1.0
var _display_food: float = 1.0
var _display_stamina: float = 1.0
var _display_water: float = 1.0
var _display_sleep: float = 1.0
var _display_food_cap: float = 1.0
var _display_water_cap: float = 1.0
var _display_sleep_cap: float = 1.0
var _received_health: bool = false
var _received_food: bool = false
var _received_stamina: bool = false
var _received_water: bool = false
var _received_sleep: bool = false
var _received_food_cap: bool = false
var _received_water_cap: bool = false
var _received_sleep_cap: bool = false
var _health_icon: Texture2D
var _food_icon: Texture2D
var _stamina_icon: Texture2D
var _water_icon: Texture2D
var _sleep_icon: Texture2D


func _ready() -> void:
	custom_minimum_size = Vector2(180.0, 180.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_icon = BunkerPanelStyle.icon("health")
	_food_icon = BunkerPanelStyle.icon("food")
	_stamina_icon = BunkerPanelStyle.icon("stamina")
	_water_icon = BunkerPanelStyle.icon("hydration")
	_sleep_icon = BunkerPanelStyle.icon("sleep")
	var grime_mat: ShaderMaterial = ShaderMaterial.new()
	grime_mat.shader = load("res://assets/shaders/grunge_overlay.gdshader")
	material = grime_mat
	set_process(true)


func _process(delta: float) -> void:
	var value_weight: float = 1.0 - exp(-VALUE_RESPONSE * delta)
	var cap_weight: float = 1.0 - exp(-CAP_RESPONSE * delta)
	var changed: bool = false
	changed = _approach_values(value_weight) or changed
	changed = _approach_caps(cap_weight) or changed
	if changed:
		queue_redraw()


# Public API: values are 0.0-1.0 fractions. The first update snaps so the HUD
# never animates from fabricated defaults when a save/world first appears.
func set_health(frac: float) -> void:
	var next: float = clampf(frac, 0.0, 1.0)
	if not _received_health:
		_display_health = next
		_received_health = true
	_health = next
	queue_redraw()


func set_food(frac: float) -> void:
	var next: float = clampf(frac, 0.0, 1.0)
	if not _received_food:
		_display_food = next
		_received_food = true
	_food = next
	queue_redraw()


func set_stamina(frac: float) -> void:
	var next: float = clampf(frac, 0.0, 1.0)
	if not _received_stamina:
		_display_stamina = next
		_received_stamina = true
	_stamina = next
	queue_redraw()


func set_water(frac: float) -> void:
	var next: float = clampf(frac, 0.0, 1.0)
	if not _received_water:
		_display_water = next
		_received_water = true
	_water = next
	queue_redraw()


func set_sleep(frac: float) -> void:
	var next: float = clampf(frac, 0.0, 1.0)
	if not _received_sleep:
		_display_sleep = next
		_received_sleep = true
	_sleep = next
	queue_redraw()


func set_food_cap(frac: float) -> void:
	_food_cap = clampf(frac, 0.0, 1.0)
	if not _received_food_cap:
		_display_food_cap = _food_cap
		_received_food_cap = true
	queue_redraw()


func set_water_cap(frac: float) -> void:
	_water_cap = clampf(frac, 0.0, 1.0)
	if not _received_water_cap:
		_display_water_cap = _water_cap
		_received_water_cap = true
	queue_redraw()


func set_sleep_cap(frac: float) -> void:
	_sleep_cap = clampf(frac, 0.0, 1.0)
	if not _received_sleep_cap:
		_display_sleep_cap = _sleep_cap
		_received_sleep_cap = true
	queue_redraw()


func _draw() -> void:
	var gap: float = deg_to_rad(GAP_ANGLE_DEG)
	draw_circle(CENTER, CENTER_CIRCLE_RADIUS, CENTER_CIRCLE_COLOR)
	UIKit.draw_rugged_circle(self, CENTER, CENTER_CIRCLE_RADIUS, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 500.0)
	_draw_left_half(RING1_RADIUS, RING1_THICKNESS, gap, _display_health, COLOR_HEALTH)
	_draw_right_half(RING1_RADIUS, RING1_THICKNESS, gap, _display_food, COLOR_FOOD, _display_food_cap)
	_draw_left_half(RING2_RADIUS, RING2_THICKNESS, gap, _display_stamina, COLOR_STAMINA)
	_draw_right_half(RING2_RADIUS, RING2_THICKNESS, gap, _display_water, COLOR_WATER, _display_water_cap)
	_draw_right_half(RING3_RADIUS, RING3_THICKNESS, gap, _display_sleep, COLOR_SLEEP, _display_sleep_cap)
	var left_mid: float = PI + GAUGE_ROTATION
	var right_mid: float = GAUGE_ROTATION
	_draw_need_icon(RING1_RADIUS, left_mid, _health_icon, COLOR_HEALTH)
	_draw_need_icon(RING1_RADIUS, right_mid, _food_icon, COLOR_FOOD)
	_draw_need_icon(RING2_RADIUS, left_mid, _stamina_icon, COLOR_STAMINA)
	_draw_need_icon(RING2_RADIUS, right_mid, _water_icon, COLOR_WATER)
	_draw_need_icon(RING3_RADIUS, right_mid, _sleep_icon, COLOR_SLEEP)


func _draw_left_half(radius: float, thickness: float, gap: float, fill: float, color: Color) -> void:
	var zero_edge: float = PI / 2.0 + gap + GAUGE_ROTATION
	var full_edge: float = 3.0 * PI / 2.0 - gap + GAUGE_ROTATION
	_draw_track(radius, thickness, zero_edge, full_edge)
	var normalized: float = clampf(fill, 0.0, 1.0)
	if normalized > 0.0:
		var current_end: float = lerpf(zero_edge, full_edge, normalized)
		_draw_value_arc(radius, thickness, zero_edge, current_end, color)
	_draw_rugged_edges(radius, thickness, zero_edge, full_edge, radius)


# Medical caps close equally from both ends. Normal value loss remains
# directional inside the surviving interval.
func _draw_right_half(radius: float, thickness: float, gap: float, fill: float, color: Color, cap: float) -> void:
	var full_edge: float = -PI / 2.0 + gap + GAUGE_ROTATION
	var zero_edge: float = PI / 2.0 - gap + GAUGE_ROTATION
	var sweep: float = zero_edge - full_edge
	var safe_cap: float = clampf(cap, 0.0, 1.0)
	var lock_each_end: float = sweep * (1.0 - safe_cap) * 0.5
	var available_full_edge: float = full_edge + lock_each_end
	var available_zero_edge: float = zero_edge - lock_each_end
	if lock_each_end > 0.0001:
		_draw_capped_arc(radius, thickness, full_edge, available_full_edge)
		_draw_capped_arc(radius, thickness, available_zero_edge, zero_edge)
	if available_zero_edge > available_full_edge:
		_draw_track(radius, thickness, available_full_edge, available_zero_edge)
	var normalized: float = 0.0
	if safe_cap > 0.0001:
		normalized = clampf(fill / safe_cap, 0.0, 1.0)
	if normalized > 0.0 and available_zero_edge > available_full_edge:
		var current_start: float = lerpf(available_zero_edge, available_full_edge, normalized)
		_draw_value_arc(radius, thickness, current_start, available_zero_edge, color)
	_draw_rugged_edges(radius, thickness, full_edge, zero_edge, radius + 200.0)


func _draw_track(radius: float, thickness: float, start_angle: float, end_angle: float) -> void:
	draw_arc(CENTER, radius, start_angle, end_angle, ARC_SEGMENTS, TRACK_COLOR, thickness, true)


func _draw_capped_arc(radius: float, thickness: float, start_angle: float, end_angle: float) -> void:
	draw_arc(CENTER, radius, start_angle, end_angle, ARC_SEGMENTS, CAPPED_TRACK_COLOR, thickness, true)


func _draw_value_arc(radius: float, thickness: float, start_angle: float, end_angle: float, color: Color) -> void:
	draw_arc(CENTER, radius, start_angle, end_angle, ARC_SEGMENTS, color, thickness, true)


func _draw_rugged_edges(radius: float, thickness: float, start_angle: float, end_angle: float, seed: float) -> void:
	UIKit.draw_rugged_arc(self, CENTER, radius + thickness * 0.5, start_angle, end_angle, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, seed)
	UIKit.draw_rugged_arc(self, CENTER, radius - thickness * 0.5, start_angle, end_angle, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, seed + 100.0)


func _draw_need_icon(radius: float, angle: float, texture: Texture2D, accent: Color) -> void:
	if texture == null:
		return
	var position: Vector2 = CENTER + Vector2.from_angle(angle) * radius
	draw_circle(position, 7.4, ICON_KEYLINE_COLOR.darkened(0.18))
	draw_circle(position, 6.3, ICON_WELL_COLOR)
	var icon_rect: Rect2 = Rect2(position - Vector2(4.5, 4.5), Vector2(9.0, 9.0))
	draw_texture_rect(texture, icon_rect, false, ICON_COLOR.lerp(accent.lightened(0.28), 0.16))


func _approach_values(weight: float) -> bool:
	var changed: bool = false
	var next_health: float = lerpf(_display_health, _health, weight)
	var next_food: float = lerpf(_display_food, _food, weight)
	var next_stamina: float = lerpf(_display_stamina, _stamina, weight)
	var next_water: float = lerpf(_display_water, _water, weight)
	var next_sleep: float = lerpf(_display_sleep, _sleep, weight)
	changed = not is_equal_approx(next_health, _display_health) or changed
	changed = not is_equal_approx(next_food, _display_food) or changed
	changed = not is_equal_approx(next_stamina, _display_stamina) or changed
	changed = not is_equal_approx(next_water, _display_water) or changed
	changed = not is_equal_approx(next_sleep, _display_sleep) or changed
	_display_health = _snap_near(next_health, _health)
	_display_food = _snap_near(next_food, _food)
	_display_stamina = _snap_near(next_stamina, _stamina)
	_display_water = _snap_near(next_water, _water)
	_display_sleep = _snap_near(next_sleep, _sleep)
	return changed


func _approach_caps(weight: float) -> bool:
	var changed: bool = false
	var next_food_cap: float = lerpf(_display_food_cap, _food_cap, weight)
	var next_water_cap: float = lerpf(_display_water_cap, _water_cap, weight)
	var next_sleep_cap: float = lerpf(_display_sleep_cap, _sleep_cap, weight)
	changed = not is_equal_approx(next_food_cap, _display_food_cap) or changed
	changed = not is_equal_approx(next_water_cap, _display_water_cap) or changed
	changed = not is_equal_approx(next_sleep_cap, _display_sleep_cap) or changed
	_display_food_cap = _snap_near(next_food_cap, _food_cap)
	_display_water_cap = _snap_near(next_water_cap, _water_cap)
	_display_sleep_cap = _snap_near(next_sleep_cap, _sleep_cap)
	return changed


func _snap_near(value: float, target: float) -> float:
	return target if absf(value - target) < 0.0005 else value


# Testable geometry helper: [full edge, usable full edge, usable zero edge,
# zero edge], all in clockwise radians.
func symmetric_cap_segments(cap: float, gap: float = -1.0) -> PackedFloat32Array:
	if gap < 0.0:
		gap = deg_to_rad(GAP_ANGLE_DEG)
	var full_edge: float = -PI / 2.0 + gap + GAUGE_ROTATION
	var zero_edge: float = PI / 2.0 - gap + GAUGE_ROTATION
	var sweep: float = zero_edge - full_edge
	var lock_each_end: float = sweep * (1.0 - clampf(cap, 0.0, 1.0)) * 0.5
	return PackedFloat32Array([full_edge, full_edge + lock_each_end, zero_edge - lock_each_end, zero_edge])
