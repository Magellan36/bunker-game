class_name BunkerInputHint
extends HBoxContainer
## Input-aware hint, updated in place. Caller supplies real per-screen bindings.
var keyboard_key: String = ""
var controller_key: String = ""
var key_label: Label
var keycap: PanelContainer
var _last_mode: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_hint()

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_update_hint()

func _update_hint() -> void:
	var mode: int = 1 if InputMode.is_controller() else 0
	if _last_mode == mode or key_label == null:
		return
	_last_mode = mode
	key_label.text = controller_key if mode == 1 else keyboard_key
	keycap.custom_minimum_size.x = maxf(34.0, float(key_label.text.length()) * 8.0 + 14.0)
