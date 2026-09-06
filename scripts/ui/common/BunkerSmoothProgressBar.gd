class_name BunkerSmoothProgressBar
extends ProgressBar
## Presentation-only interpolation for live UI meters. Simulation values and
## labels remain immediate; only the rendered fill eases toward its target.

const RESPONSE: float = 10.0
const SNAP_EPSILON: float = 0.02

var _target_value: float = 0.0
var _received_target: bool = false


func _ready() -> void:
	_target_value = value
	set_process(false)


func set_target_value(next_value: float, snap_first: bool = true) -> void:
	var bounded: float = clampf(next_value, min_value, max_value)
	if not _received_target and snap_first:
		value = bounded
	_received_target = true
	_target_value = bounded
	set_process(not is_equal_approx(value, _target_value))


func snap_to(next_value: float) -> void:
	_received_target = true
	_target_value = clampf(next_value, min_value, max_value)
	value = _target_value
	set_process(false)


func _process(delta: float) -> void:
	var weight: float = 1.0 - exp(-RESPONSE * delta)
	var next_value: float = lerpf(value, _target_value, weight)
	if absf(next_value - _target_value) <= SNAP_EPSILON:
		next_value = _target_value
	value = next_value
	if is_equal_approx(value, _target_value):
		set_process(false)


static func apply(bar: ProgressBar, next_value: float, snap_first: bool = true) -> void:
	if bar is BunkerSmoothProgressBar:
		(bar as BunkerSmoothProgressBar).set_target_value(next_value, snap_first)
	else:
		bar.set_value_no_signal(clampf(next_value, bar.min_value, bar.max_value))
