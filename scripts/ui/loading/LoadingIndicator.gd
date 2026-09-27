class_name LoadingIndicator
extends Control

## Honest indeterminate loading indicator. MainWorld's threaded resource load
## and asynchronous preview warmup do not expose one continuous percentage, so
## this communicates activity without claiming false completion progress.

## Sep 2026 quiet pass: a hairline track with a soft ACCENT segment that
## glides across; a muted red line when loading fails.
const TRACK: Color = Color(0.949, 0.910, 0.812, 0.09)
const ACCENT: Color = Color("86a9bf")
const ERROR: Color = Color("df7669")
const PERIOD: float = 2.4

var _elapsed: float = 0.0
var _failed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(660.0, 6.0)
	set_process(true)


func _process(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, PERIOD)
	queue_redraw()


func set_failed(value: bool) -> void:
	_failed = value
	set_process(not value)
	queue_redraw()


func _draw() -> void:
	if size.x <= 2.0:
		return
	var y: float = size.y * 0.5
	draw_line(Vector2(0.0, y), Vector2(size.x, y), TRACK, 2.0, true)
	if _failed:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(ERROR, 0.8), 2.0, true)
		return
	var t: float = _elapsed / PERIOD
	var eased: float = t * t * (3.0 - 2.0 * t)
	var width: float = size.x * 0.28
	var head: float = lerpf(-width, size.x, eased)
	var left: float = clampf(head, 0.0, size.x)
	var right: float = clampf(head + width, 0.0, size.x)
	if right <= left:
		return
	var clear := Color(ACCENT, 0.0)
	var mid := (left + right) * 0.5
	draw_polygon(PackedVector2Array([Vector2(left, y - 1.0), Vector2(mid, y - 1.0),
		Vector2(mid, y + 1.0), Vector2(left, y + 1.0)]),
		PackedColorArray([clear, ACCENT, ACCENT, clear]))
	draw_polygon(PackedVector2Array([Vector2(mid, y - 1.0), Vector2(right, y - 1.0),
		Vector2(right, y + 1.0), Vector2(mid, y + 1.0)]),
		PackedColorArray([ACCENT, clear, clear, ACCENT]))
