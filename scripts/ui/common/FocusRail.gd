extends Control
## FocusRail.gd (Sep 2026)
## Shared focus/selection indicator for the quiet 2026 UI language (main
## menu, settings). A slim rail plus a soft wash that fades out to the right.
## It glides between targets with its leading edge moving faster than its
## trailing edge, so travel reads as a brief elastic stretch rather than a
## teleport. Pure presentation: it never owns focus.
##
## Place it as a full-rect sibling *behind* the controls it decorates (inside
## any clipping parent, e.g. next to a ScrollContainer) and call
## set_target(). With `require_focus` the rail hides whenever the target does
## not hold keyboard focus (main menu); without it the host decides (settings
## rows, the active section in a navigation list).

const LEAD_RESPONSE: float = 30.0
const TRAIL_RESPONSE: float = 13.0
const FADE_RESPONSE: float = 10.0

var ui_scale: float = 1.0
## Rail distance left of the target's left edge, in 1080p pixels.
var rail_offset: float = 20.0
var rail_width: float = 3.0
## Wash reach as a fraction of the target width, and its peak opacity.
var wash_extent: float = 0.78
var wash_alpha: float = 0.13
## Vertical inset of the rail as a fraction of the target height.
var inset_fraction: float = 0.16
var glow: bool = true
var require_focus: bool = true
var color: Color = BunkerDesign.BLUE

var _target: Control = null
var _top: float = 0.0
var _bottom: float = 0.0
var _left: float = 0.0
var _width: float = 0.0
var _alpha: float = 0.0
var _pulse: float = 0.0
var _color: Color = BunkerDesign.BLUE
var _placed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color = color


func set_target(target: Control) -> void:
	_target = target


func get_target() -> Control:
	return _target


## Jump without gliding (first placement, or after a hard layout change).
func snap() -> void:
	_placed = false


## Brief acknowledgement flash of the wash (a value just changed).
func pulse() -> void:
	_pulse = 1.0


func _process(delta: float) -> void:
	var valid := _target != null and is_instance_valid(_target) and _target.is_visible_in_tree()
	if valid and require_focus:
		valid = _target.has_focus()
	var target_alpha := 0.0
	if valid:
		var rect := get_global_transform().affine_inverse() * _target.get_global_rect()
		var inset := rect.size.y * inset_fraction
		var top := rect.position.y + inset
		var bottom := rect.end.y - inset
		var accent: Variant = _target.get("accent")
		_color = _color.lerp(accent if accent is Color else color,
			UIMotion.weight(delta, FADE_RESPONSE))
		target_alpha = _effective_alpha(_target)
		if not _placed or _alpha < 0.02:
			_top = top
			_bottom = bottom
			_left = rect.position.x
			_width = rect.size.x
			_placed = true
		else:
			var moving_up := top < _top
			var lead := UIMotion.weight(delta, LEAD_RESPONSE)
			var trail := UIMotion.weight(delta, TRAIL_RESPONSE)
			_top = lerpf(_top, top, lead if moving_up else trail)
			_bottom = lerpf(_bottom, bottom, trail if moving_up else lead)
			_left = lerpf(_left, rect.position.x, lead)
			_width = lerpf(_width, rect.size.x, lead)
	_alpha = lerpf(_alpha, target_alpha, UIMotion.weight(delta, FADE_RESPONSE))
	_pulse = maxf(_pulse - delta * 3.0, 0.0)
	queue_redraw()


## Follows the target's fades (view transitions, intro stagger) so the rail
## never floats over an item that is still invisible.
func _effective_alpha(node: Node) -> float:
	var alpha := 1.0
	var common := get_parent()
	while node != null and node != common:
		if node is CanvasItem:
			alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
		node = node.get_parent()
	return alpha


func _draw() -> void:
	if _alpha <= 0.003 or _bottom <= _top:
		return
	var rail_x := _left - rail_offset * ui_scale
	var rail_w := rail_width * ui_scale
	var wash_right := _left + _width * wash_extent
	var wash_top := _top - 4.0 * ui_scale
	var wash_bottom := _bottom + 4.0 * ui_scale
	var strong := Color(_color, (wash_alpha + _pulse * 0.08) * _alpha)
	var clear := Color(_color, 0.0)
	draw_polygon(PackedVector2Array([
		Vector2(rail_x, wash_top), Vector2(wash_right, wash_top),
		Vector2(wash_right, wash_bottom), Vector2(rail_x, wash_bottom),
	]), PackedColorArray([strong, clear, clear, strong]))
	if glow:
		for i: int in range(3):
			var spread := float(i + 1) * 2.0 * ui_scale
			draw_rect(Rect2(rail_x - spread, _top - spread * 0.5, rail_w + spread * 2.0,
				_bottom - _top + spread), Color(_color, 0.07 * _alpha))
	draw_rect(Rect2(rail_x, _top, rail_w, _bottom - _top), Color(_color, _alpha))
