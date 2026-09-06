class_name LoadingIndicator
extends Control

## Honest indeterminate loading indicator. MainWorld's threaded resource load
## and asynchronous preview warmup do not expose one continuous percentage, so
## this communicates activity without claiming false completion progress.

const TRACK: Color = Color("1a2728")
const TRACK_EDGE: Color = Color("50605a")
const BLUE: Color = Color("66bfff")
const BLUE_GLOW: Color = Color("66bfff42")
const ERROR: Color = Color("df7669")

var _elapsed: float = 0.0
var _failed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(700.0, 18.0)
	set_process(true)


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, 3.0)
	queue_redraw()


func set_failed(value: bool) -> void:
	_failed = value
	set_process(not value)
	queue_redraw()


func _draw() -> void:
	if size.x <= 2.0:
		return
	var center_y: float = size.y * 0.5
	var left: Vector2 = Vector2(7.0, center_y)
	var right: Vector2 = Vector2(size.x - 7.0, center_y)
	draw_line(left, right, TRACK_EDGE, 8.0, true)
	draw_line(left, right, TRACK, 5.0, true)
	if _failed:
		draw_line(left, right, ERROR.darkened(0.25), 5.0, true)
		return

	var travel: float = size.x + 180.0
	var head: float = (_elapsed / 3.0) * travel - 90.0
	var segment_left: float = clampf(head - 115.0, 7.0, size.x - 7.0)
	var segment_right: float = clampf(head + 115.0, 7.0, size.x - 7.0)
	if segment_right <= segment_left:
		return
	draw_line(Vector2(segment_left, center_y), Vector2(segment_right, center_y), BLUE_GLOW, 13.0, true)
	draw_line(Vector2(segment_left, center_y), Vector2(segment_right, center_y), BLUE, 5.0, true)
