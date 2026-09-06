extends Control
## Custom-drawn history graph inside the native-Control Power Terminal.

const STYLE: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")

var _draw_history: PackedFloat32Array = PackedFloat32Array()
var _capacity_history: PackedFloat32Array = PackedFloat32Array()
var _display_draw_history: PackedFloat32Array = PackedFloat32Array()
var _display_capacity_history: PackedFloat32Array = PackedFloat32Array()
var _history_initialized: bool = false
const TRACE_RESPONSE: float = 7.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(false)


func set_history(draw_history: PackedFloat32Array,
		capacity_history: PackedFloat32Array) -> void:
	_draw_history = draw_history
	_capacity_history = capacity_history
	if not _history_initialized:
		_display_draw_history = draw_history.duplicate()
		_display_capacity_history = capacity_history.duplicate()
		_history_initialized = true
	else:
		_display_draw_history = _aligned_display(_display_draw_history, draw_history)
		_display_capacity_history = _aligned_display(
			_display_capacity_history, capacity_history
		)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-TRACE_RESPONSE * delta)
	var changed: bool = false
	changed = _approach_series(_display_draw_history, _draw_history, weight) or changed
	changed = _approach_series(
		_display_capacity_history, _capacity_history, weight
	) or changed
	if changed:
		queue_redraw()
	else:
		set_process(false)


func _draw() -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(_box(Color("101615"), STYLE.BRASS.darkened(0.55), 5, 1), bounds)
	var plot: Rect2 = Rect2(46.0, 10.0, maxf(1.0, size.x - 64.0), maxf(1.0, size.y - 30.0))
	if plot.size.x <= 1.0 or plot.size.y <= 1.0:
		return
	var maximum: float = 1000.0
	for value: float in _display_draw_history:
		maximum = maxf(maximum, value)
	for value: float in _display_capacity_history:
		maximum = maxf(maximum, value)
	maximum = ceilf(maximum / 250.0) * 250.0
	for row: int in range(5):
		var fraction: float = float(row) / 4.0
		var y: float = plot.position.y + plot.size.y * fraction
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color("293231"), 1.0)
		var label_value: int = int(round(maximum * (1.0 - fraction)))
		draw_string(UIKit.font(), Vector2(4.0, y + 4.0), _axis_value(label_value),
			HORIZONTAL_ALIGNMENT_LEFT, 38.0, 11, STYLE.MUTED.darkened(0.12))
	for column: int in range(7):
		var fraction: float = float(column) / 6.0
		var x: float = plot.position.x + plot.size.x * fraction
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color("252d2c"), 1.0)
	_draw_series(_display_capacity_history, plot, maximum, STYLE.BRASS.lightened(0.35), 2.0, true)
	_draw_series(_display_draw_history, plot, maximum, STYLE.BLUE, 3.0, false)


func _aligned_display(previous: PackedFloat32Array,
		target: PackedFloat32Array) -> PackedFloat32Array:
	var aligned: PackedFloat32Array = target.duplicate()
	if aligned.is_empty() or previous.is_empty():
		return aligned
	# Historical points stay exact; only the newest sample grows from the
	# previous endpoint so the graph never falsifies older data.
	aligned[aligned.size() - 1] = previous[previous.size() - 1]
	return aligned


func _approach_series(display: PackedFloat32Array, target: PackedFloat32Array,
		weight: float) -> bool:
	if display.size() != target.size():
		return false
	var changed: bool = false
	for index: int in range(display.size()):
		var next_value: float = lerpf(display[index], target[index], weight)
		if absf(next_value - target[index]) < 0.05:
			next_value = target[index]
		if not is_equal_approx(display[index], next_value):
			changed = true
		display[index] = next_value
	return changed


func _draw_series(values: PackedFloat32Array, plot: Rect2, maximum: float,
		color: Color, width: float, dashed: bool) -> void:
	if values.size() < 2:
		return
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(values.size()):
		var x_fraction: float = float(index) / float(maxi(values.size() - 1, 1))
		var y_fraction: float = clampf(values[index] / maximum, 0.0, 1.0)
		points.append(Vector2(plot.position.x + plot.size.x * x_fraction,
			plot.end.y - plot.size.y * y_fraction))
	if not dashed:
		draw_polyline(points, color, width, true)
		return
	for index: int in range(points.size() - 1):
		if index % 2 == 0:
			draw_line(points[index], points[index + 1], color, width, true)


func _box(background: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _axis_value(value: int) -> String:
	if value >= 1000:
		return "%.1fk" % (float(value) / 1000.0)
	return str(value)
