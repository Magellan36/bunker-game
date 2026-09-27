class_name UIScrollMotion
extends RefCounted
## Accumulated step scrolling. Direct dragging cancels the pending target.
const TWEEN: StringName = &"ui_scroll_tween"
const TARGET: StringName = &"ui_scroll_target"
static func cancel(bar: ScrollBar) -> void:
	if bar.has_meta(TWEEN):
		var tween: Tween = bar.get_meta(TWEEN) as Tween
		if is_instance_valid(tween) and tween.is_valid():
			tween.kill()
		bar.remove_meta(TWEEN)
	bar.set_meta(TARGET, bar.value)

static func step_by(bar: ScrollBar, distance: float) -> void:
	var pending: bool = false
	if bar.has_meta(TWEEN):
		var old: Tween = bar.get_meta(TWEEN) as Tween
		pending = is_instance_valid(old) and old.is_running()
	var start: float = float(bar.get_meta(TARGET, bar.value)) if pending else bar.value
	cancel(bar)
	var destination: float = clampf(start + distance, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
	bar.set_meta(TARGET, destination)
	if UIMotion.reduced():
		bar.value = destination
		return
	var tween: Tween = bar.create_tween()
	bar.set_meta(TWEEN, tween)
	tween.tween_property(bar, "value", destination, UIMotion.SCROLL).set_trans(
		Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func on_drag(event: InputEvent, bar: ScrollBar) -> void:
	if event is InputEventMouseButton and event.pressed:
		cancel(bar)
