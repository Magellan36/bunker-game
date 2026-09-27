extends Control
## Custom-drawn history graph inside the native-Control Power Terminal.

const STYLE: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")

var _draw_history: PackedFloat32Array = PackedFloat32Array()
var _capacity_history: PackedFloat32Array = PackedFloat32Array()
var _display_draw_history: PackedFloat32Array = PackedFloat32Array()
var _display_capacity_history: PackedFloat32Array = PackedFloat32Array()
var _history_initialized: bool = false
const TRACE_RESPONSE: float = 7.0
const WINDOW_SECONDS: float = 60.0
const DASH_LENGTH: float = 6.0
const DASH_GAP: float = 4.0
var _sample_serial: int = -1
var _sample_phase: float = 0.0
var _target_maximum: float = 1000.0
var _display_maximum: float = 1000.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	set_process(false)


func set_history(draw_history: PackedFloat32Array,
		capacity_history: PackedFloat32Array, serial: int = -1, sample_age: float = 0.0) -> void:
	if _history_initialized and serial == _sample_serial \
			and draw_history == _draw_history and capacity_history == _capacity_history:
		return
	_draw_history = draw_history
	_capacity_history = capacity_history
	_sample_serial = serial
	_sample_phase = clampf(sample_age, 0.0, 1.0)
	var highest: float = 0.0
	for value: float in _draw_history:
		highest = maxf(highest, value)
	for value: float in _capacity_history:
		highest = maxf(highest, value)
	var required: float = maxf(1000.0, ceilf(highest * 1.1 / 250.0) * 250.0)
	if required >= _target_maximum or required <= _target_maximum * 0.75:
		_target_maximum = required
	if not _history_initialized:
		_display_maximum = _target_maximum
		_display_draw_history = draw_history.duplicate()
		_display_capacity_history = capacity_history.duplicate()
		_history_initialized = true
	else:
		_display_draw_history = _aligned_display(_display_draw_history, draw_history)
		_display_capacity_history = _aligned_display(
			_display_capacity_history, capacity_history
		)
	set_process(is_visible_in_tree())
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		set_process(false)
		return
	var weight: float = UIMotion.weight(delta, TRACE_RESPONSE)
	var changed: bool = false
	changed = _approach_series(_display_draw_history, _draw_history, weight) or changed
	changed = _approach_series(
		_display_capacity_history, _capacity_history, weight
	) or changed
	var next_maximum: float = lerpf(_display_maximum, _target_maximum, weight)
	if absf(next_maximum - _target_maximum) < 0.1:
		next_maximum = _target_maximum
	changed = changed or not is_equal_approx(next_maximum, _display_maximum)
	_display_maximum = next_maximum
	if not UIMotion.reduced() and not _draw_history.is_empty() and _sample_phase < 1.0:
		_sample_phase = minf(1.0, _sample_phase + delta)
		changed = true
	if changed:
		queue_redraw()
	else:
		set_process(false)


func _draw() -> void:
	var bounds: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(_box(Color("101615"), STYLE.BRASS.darkened(0.55), 5, 1), bounds)
	var plot: Rect2 = Rect2(46.0, 12.0, maxf(1.0, size.x - 64.0), maxf(1.0, size.y - 38.0))
	if plot.size.x <= 1.0 or plot.size.y <= 1.0:
		return
	var maximum: float = _display_maximum
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
	for marker: Array in [[0.0, "−60s"], [0.5, "−30s"], [1.0, "Now"]]:
		var x: float = plot.position.x + plot.size.x * float(marker[0])
		draw_string(UIKit.font(), Vector2(x - (22.0 if float(marker[0]) == 1.0 else 0.0), plot.end.y + 18.0),
			String(marker[1]), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, STYLE.MUTED)


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
	var points := _series_points(values, plot, maximum)
	if not dashed:
		if points.size() >= 2:
			var fill := points.duplicate()
			fill.append(Vector2(points[-1].x, plot.end.y))
			fill.append(Vector2(points[0].x, plot.end.y))
			var has_area: bool = false
			for point: Vector2 in points:
				has_area = has_area or point.y < plot.end.y - 0.1
			if has_area:
				draw_colored_polygon(fill, Color(color, 0.07))
			draw_polyline(points, Color(color, 0.12), width + 3.0, true)
			draw_polyline(points, color, 2.0, true)
		if not points.is_empty():
			draw_circle(points[-1], 3.0, color, true, -1.0, true)
		return
	var dashes := _dash_segments(points)
	if not dashes.is_empty():
		draw_multiline(dashes, color, width, true)


func _series_points(values: PackedFloat32Array, plot: Rect2, maximum: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var phase: float = 0.0 if UIMotion.reduced() else _sample_phase
	var previous := Vector2.ZERO
	for index: int in values.size():
		var age: float = float(values.size() - 1 - index) + phase
		var point := Vector2(plot.end.x - plot.size.x * age / WINDOW_SECONDS,
			plot.end.y - plot.size.y * clampf(values[index] / maximum, 0.0, 1.0))
		if point.x >= plot.position.x:
			if points.is_empty() and index > 0 and previous.x < plot.position.x:
				var fraction: float = (plot.position.x - previous.x) / maxf(0.001, point.x - previous.x)
				points.append(previous.lerp(point, fraction))
			points.append(point)
		previous = point
	if not points.is_empty() and points[-1].x < plot.end.x:
		# Hold the latest observed value to Now, without inventing readings.
		points.append(Vector2(plot.end.x, points[-1].y))
	return points


func _dash_segments(points: PackedVector2Array) -> PackedVector2Array:
	var segments := PackedVector2Array()
	var phase: float = 0.0
	var period: float = DASH_LENGTH + DASH_GAP
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var offset: Vector2 = points[index + 1] - start
		var length: float = offset.length()
		if length < 0.001:
			continue
		var direction: Vector2 = offset / length
		var distance: float = 0.0
		while distance < length - 0.001:
			var lit: bool = phase < DASH_LENGTH
			var run: float = minf(length - distance, (DASH_LENGTH if lit else period) - phase)
			if lit and run > 0.001:
				segments.append(start + direction * distance)
				segments.append(start + direction * (distance + run))
			distance += run
			phase = fposmod(phase + run, period)
	return segments


func _box(background: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _axis_value(value: int) -> String:
	if value == 0:
		return "0 W"
	if value >= 1000:
		return "%.1fk" % (float(value) / 1000.0)
	return str(value)
