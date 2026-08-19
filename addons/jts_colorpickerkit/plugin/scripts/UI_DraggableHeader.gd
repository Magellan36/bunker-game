# ============================================================
#  © [2025] [JoenTNT]
#  Licensed under the Apache License, Version 2.0
#  http://www.apache.org/licenses/LICENSE-2.0
# ============================================================

class_name UI_DraggableHeader
extends Control

# Requirements.
@export var _target_root: Control = null;

# Runtime variable data.
var _mouse_btn: InputEventMouseButton = null;
var _mouse_mot: InputEventMouseMotion = null;

var _grab_offset: Vector2 = Vector2.ZERO;
var _is_grabbed: bool = false;

func _enter_tree() -> void:
	# Subscribe events.
	gui_input.connect(_on_gui_input);

func _exit_tree() -> void:
	# Subscribe events.
	gui_input.disconnect(_on_gui_input);

func _on_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_mouse_mot = ev as InputEventMouseMotion;
		_on_mouse_motion();
	elif ev is InputEventMouseButton:
		_mouse_btn = ev as InputEventMouseButton;
		_on_mouse_button();

func _on_mouse_button() -> void:
	_is_grabbed = _mouse_btn.pressed;
	if _is_grabbed:
		_grab_offset = _target_root.global_position - _mouse_btn.global_position;

func _on_mouse_motion() -> void:
	if not _is_grabbed: return;
	_target_root.global_position = _mouse_mot.global_position + _grab_offset;
