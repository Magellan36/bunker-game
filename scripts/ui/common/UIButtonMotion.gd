class_name UIButtonMotion
extends Control
## A very small highlight fade, independent of the immediate semantic theme
## state. Never animates button geometry, font scale, or its focus rectangle.
var _amount: float = 0.0:
	set(next):
		_amount = next
		queue_redraw()
var _tween: Tween
var _button: BaseButton

static func attach(button: BaseButton) -> void:
	if button.has_meta(&"bunker_button_motion"):
		return
	button.set_meta(&"bunker_button_motion", true)
	var feedback: UIButtonMotion = UIButtonMotion.new()
	feedback.name = "ButtonFeedback"
	button.add_child(feedback)

func _ready() -> void:
	_button = get_parent() as BaseButton
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_button.mouse_entered.connect(_refresh)
	_button.mouse_exited.connect(_refresh)
	_button.focus_entered.connect(_refresh)
	_button.focus_exited.connect(_refresh)
	_button.button_down.connect(_refresh)
	_button.button_up.connect(_refresh)
	_button.visibility_changed.connect(_refresh)

func _refresh() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	var highlighted: bool = _button.is_hovered() or _button.has_focus()
	var target: float = 0.025 if highlighted and not _button.disabled else 0.0
	if not _button.is_visible_in_tree() or UIMotion.reduced():
		_amount = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "_amount", target, UIMotion.FEEDBACK).set_trans(
		Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	if _amount <= 0.0:
		return
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(BunkerDesign.IVORY, _amount)
	style.set_corner_radius_all(BunkerDesign.CONTROL_RADIUS)
	draw_style_box(style, Rect2(Vector2.ZERO, size))
