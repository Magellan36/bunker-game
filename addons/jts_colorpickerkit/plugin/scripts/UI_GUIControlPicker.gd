# ============================================================
#  © [2025] [JoenTNT]
#  Licensed under the Apache License, Version 2.0
#  http://www.apache.org/licenses/LICENSE-2.0
# ============================================================

class_name UI_GUIControlPicker
extends TextureRect

# Runtime variable data.
var _ev_mouse_mot: InputEventMouseMotion = null;
var _ev_mouse_btn: InputEventMouseButton = null;
var _runtime_tex_mat: ShaderMaterial = null;
var _is_pressed: bool = false;

func _enter_tree() -> void:
	# Subscribe events.
	gui_input.connect(_on_gui_input);

func _exit_tree() -> void:
	# Unsubscribe events.
	gui_input.disconnect(_on_gui_input);

func _ready() -> void:
	if material != null:
		if material is ShaderMaterial:
			_runtime_tex_mat = material as ShaderMaterial;
			_runtime_tex_mat = _runtime_tex_mat.duplicate(true);
			material = _runtime_tex_mat;

func _on_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_ev_mouse_mot = ev as InputEventMouseMotion;
		if _is_pressed:
			_on_surface_pressed(ev.position);
			_on_adjust_by_position(ev.position);
		else:
			_on_surface_released(ev.position);
	elif ev is InputEventMouseButton:
		_ev_mouse_btn = ev as InputEventMouseButton;
		if _ev_mouse_btn.button_index == MOUSE_BUTTON_LEFT:
			_is_pressed = _ev_mouse_btn.pressed;
			_on_adjust_by_position(ev.position);

func _on_surface_pressed(pos: Vector2) -> void: return;
func _on_surface_released(pos: Vector2) -> void: return;
func _on_adjust_by_position(pos: Vector2) -> void: return;
