# ============================================================
#  © [2025] [JoenTNT]
#  Licensed under the Apache License, Version 2.0
#  http://www.apache.org/licenses/LICENSE-2.0
# ============================================================

class_name UI_SliderInputTemplate
extends Control

# Requirements.
@export var _slider: Slider = null;
@export var _line_input: LineEdit = null;

# Runtime variable data.
var _ev_mouse_btn: InputEventMouseButton = null;
var _ev_touch: InputEventScreenTouch = null;

func _enter_tree() -> void:
	# Subscribe events.
	_slider.value_changed.connect(_on_slider_value_changed);
	_slider.gui_input.connect(_on_gui_input);
	_line_input.text_submitted.connect(_on_number_input_submit);

func _exit_tree() -> void:
	# Unsubscribe events.
	_slider.value_changed.disconnect(_on_slider_value_changed);
	_slider.gui_input.disconnect(_on_gui_input);
	_line_input.text_submitted.disconnect(_on_number_input_submit);

func _on_gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		_ev_touch = ev as InputEventScreenTouch;
		# Always first index to prevent changes using multiple fingers
		if _ev_touch.index == 0:
			if _ev_touch.pressed:
				_on_gui_selected();
			else:
				_on_gui_released();
	elif ev is InputEventMouseButton:
		_ev_mouse_btn = ev as InputEventMouseButton;
		if _ev_mouse_btn.button_index == MOUSE_BUTTON_LEFT:
			if _ev_mouse_btn.pressed:
				_on_gui_selected();
			else:
				_on_gui_released();

func _on_slider_value_changed(value: float) -> void: return;
func _on_number_input_submit(txt: String) -> void: return;
func _on_gui_selected() -> void: return;
func _on_gui_released() -> void: return;

func get_slider_component() -> Slider:
	return _slider;

func get_line_input_component() -> LineEdit:
	return _line_input;
