extends Control
## SwitchGlyph.gd (Sep 2026)
## A quiet, animated on/off switch drawn over a CheckButton's reserved icon
## space (see QuietControls.gd switch()). Off is an outlined, dim track; on is a
## muted steel-blue track with an ivory knob. The knob eases between ends.
## Engine-drawn geometry only; no textures.

const TRACK_SIZE: Vector2 = Vector2(34.0, 18.0)
## Same values as QuietControls.gd ACCENT / MUTED (kept local: no cyclic preload).
const ACCENT: Color = Color("86a9bf")
const MUTED: Color = Color("aaa596")

var ui_scale: float = 1.0
var _button: BaseButton
var _t: float = 0.0


func _ready() -> void:
	_button = get_parent() as BaseButton
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t = 1.0 if _button.button_pressed else 0.0
	_button.resized.connect(_place)
	_place()


func _process(delta: float) -> void:
	var target := 1.0 if _button.button_pressed else 0.0
	if absf(_t - target) > 0.001:
		_t = lerpf(_t, target, UIMotion.weight(delta, 16.0))
		if absf(_t - target) < 0.01:
			_t = target
		queue_redraw()
	elif _t != target:
		_t = target
		queue_redraw()


func _place() -> void:
	var track := TRACK_SIZE * ui_scale
	var margin := _button.get_theme_stylebox("normal").content_margin_right
	size = track
	position = Vector2(_button.size.x - margin - track.x, (_button.size.y - track.y) * 0.5)
	queue_redraw()


func _draw() -> void:
	var track := Rect2(Vector2.ZERO, size)
	var radius := size.y * 0.5
	var disabled := _button.disabled
	var on_fill := Color(ACCENT, lerpf(0.0, 0.55, _t))
	var edge := MUTED.lerp(ACCENT, _t)
	edge.a = 0.55 if not disabled else 0.25
	var style := StyleBoxFlat.new()
	style.bg_color = on_fill
	style.border_color = edge
	style.set_border_width_all(maxi(1, roundi(ui_scale)))
	style.set_corner_radius_all(roundi(radius))
	style.anti_aliasing = true
	draw_style_box(style, track)
	var knob_r := radius - 3.0 * ui_scale
	var x := lerpf(radius, size.x - radius, _t)
	var knob := BunkerDesign.MUTED.lerp(BunkerDesign.IVORY, _t)
	knob.a = 0.9 if not disabled else 0.35
	draw_circle(Vector2(x, radius), knob_r, knob, true, -1.0, true)
