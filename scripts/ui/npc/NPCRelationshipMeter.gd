extends Control
class_name NPCRelationshipMeter
## Compact -100..100 relationship scale for the resident profile. The meter
## is entirely Godot-drawn so it remains crisp, tintable, and asset-free.

const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")
const RESPONSE: float = 9.0

var value: float = 0.0:
	set(next_value):
		value = clampf(next_value, -100.0, 100.0)
		if not is_inside_tree():
			return
		if not _received_value:
			_display_value = value
			_received_value = true
		set_process(not is_equal_approx(_display_value, value))
		queue_redraw()
var _display_value: float = 0.0
var _received_value: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 20.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display_value = value
	_received_value = false
	set_process(false)


func set_target_value(next_value: float) -> void:
	value = next_value


func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-RESPONSE * delta)
	_display_value = lerpf(_display_value, value, weight)
	if absf(_display_value - value) < 0.02:
		_display_value = value
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var track: Rect2 = Rect2(4.0, 7.0, maxf(size.x - 8.0, 1.0), 7.0)
	var track_style: StyleBoxFlat = StyleBoxFlat.new()
	track_style.bg_color = Color("111615")
	track_style.border_color = S.BRASS.darkened(0.38)
	track_style.set_border_width_all(1)
	track_style.set_corner_radius_all(4)
	track_style.draw(get_canvas_item(), track)

	var segment_colors: Array[Color] = [
		S.RED,
		Color("c98455"),
		Color("d7c86b"),
		S.GREEN,
	]
	var inner: Rect2 = track.grow(-1.0)
	var segment_width: float = inner.size.x / float(segment_colors.size())
	for index: int in range(segment_colors.size()):
		var segment: Rect2 = Rect2(
			inner.position + Vector2(segment_width * float(index), 0.0),
			Vector2(segment_width + 0.5, inner.size.y)
		)
		draw_rect(segment, Color(segment_colors[index], 0.86), true)

	var fraction: float = inverse_lerp(-100.0, 100.0, _display_value)
	var marker_x: float = inner.position.x + inner.size.x * fraction
	draw_circle(Vector2(marker_x, track.get_center().y), 7.0, Color("111615"))
	draw_circle(Vector2(marker_x, track.get_center().y), 5.0, S.IVORY)
	draw_arc(Vector2(marker_x, track.get_center().y), 6.0, 0.0, TAU, 24,
		S.BRASS.lightened(0.12), 1.0, true)
