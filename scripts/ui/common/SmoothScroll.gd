extends Node
## SmoothScroll.gd (Sep 2026)
## Eased scrolling for any ScrollContainer: mouse-wheel and touchpad steps
## glide instead of jumping, `scroll_to()` animates programmatic jumps (e.g.
## section links), and `reveal()` keeps a focused control in view with a
## comfortable margin (use it instead of the container's follow_focus, which
## snaps). Dragging the scrollbar stays direct. Honours UIMotion.reduced().
##
##   var smooth := SmoothScroll.attach(scroll)   # returns the helper node

const WHEEL_STEP: float = 96.0
const RESPONSE: float = 14.0

var scroll: ScrollContainer
var _target: float = 0.0
var _animating: bool = false


static func attach(container: ScrollContainer) -> Node:
	var helper: Node = (load("res://scripts/ui/common/SmoothScroll.gd") as GDScript).new()
	helper.name = "SmoothScroll"
	helper.set("scroll", container)
	container.add_child(helper, false, Node.INTERNAL_MODE_BACK)
	return helper


func _ready() -> void:
	if scroll == null:
		scroll = get_parent() as ScrollContainer
	scroll.follow_focus = false
	scroll.gui_input.connect(_on_gui_input)


func scroll_to(y: float) -> void:
	_target = clampf(y, 0.0, _max_scroll())
	if UIMotion.reduced():
		scroll.scroll_vertical = roundi(_target)
		_animating = false
		return
	_animating = true


## Scrolls just enough to show `control` with `margin` pixels around it.
func reveal(control: Control, margin: float = 48.0) -> void:
	if control == null or not scroll.is_ancestor_of(control):
		return
	var top := control.get_global_rect().position.y - scroll.get_global_rect().position.y \
		+ float(scroll.scroll_vertical)
	var bottom := top + control.size.y
	var current := _target if _animating else float(scroll.scroll_vertical)
	if top - margin < current:
		scroll_to(top - margin)
	elif bottom + margin > current + scroll.size.y:
		scroll_to(bottom + margin - scroll.size.y)


func is_animating() -> bool:
	return _animating


func _process(delta: float) -> void:
	if not _animating:
		return
	var current := float(scroll.scroll_vertical)
	var next := lerpf(current, _target, UIMotion.weight(delta, RESPONSE))
	# scroll_vertical is an int: always move at least one pixel, or the eased
	# tail rounds back to the same value forever.
	if absf(next - current) < 1.0:
		next = current + signf(_target - current)
	if absf(_target - next) < 1.0:
		next = _target
		_animating = false
	scroll.scroll_vertical = roundi(next)
	# The container clamps at its ends; stop if the value could not move.
	if scroll.scroll_vertical == roundi(current) and _animating:
		_animating = false


func _on_gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	var direction := 0.0
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1.0
	elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1.0
	if direction == 0.0:
		return
	var base := _target if _animating else float(scroll.scroll_vertical)
	var factor := mouse.factor if mouse.factor > 0.0 else 1.0
	scroll_to(base + direction * WHEEL_STEP * factor)
	scroll.accept_event()


func _max_scroll() -> float:
	var bar := scroll.get_v_scroll_bar()
	return maxf(bar.max_value - bar.page, 0.0)
