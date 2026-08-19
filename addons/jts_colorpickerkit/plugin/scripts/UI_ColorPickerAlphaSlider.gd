# ============================================================
#  © [2025] [JoenTNT]
#  Licensed under the Apache License, Version 2.0
#  http://www.apache.org/licenses/LICENSE-2.0
# ============================================================

class_name UI_ColorPickerAlphaSlider
extends UI_GUIControlPicker

# Events.
signal on_alpha_changed(c: Color);

@export var _handle_root: Control = null;
@export var _handle_tex: TextureRect = null;
## Handle fill color parameter.
@export var _handle_color_param: StringName = &"fill_color";

@export_group("Runtime Debug")
@export var _current_color: Color = Color.RED;
var _runtime_handle_mat: ShaderMaterial = null;
var _temp_handle_pos: Vector2 = Vector2.ZERO;
var _handle_half_size: Vector2 = Vector2.ZERO;
var _min_pos_y: float = 0.0;
var _max_pos_y: float = 0.0;
var _percent: float = 0.0;

func _ready() -> void:
	super._ready();
	# Generate Runtime Unique Material Instance
	if _handle_tex.material != null:
		if _handle_tex.material is ShaderMaterial:
			_runtime_handle_mat = _handle_tex.material as ShaderMaterial;
			_runtime_handle_mat = _runtime_handle_mat.duplicate(true);
			_handle_tex.material = _runtime_handle_mat;

func _on_adjust_by_position(pos: Vector2) -> void:
	_on_handle_interface_change(pos);
	_current_color.a = 1.0 - _percent;
	on_alpha_changed.emit(_current_color);

func _on_handle_interface_change(pos: Vector2) -> void:
	_handle_half_size = _handle_root.size / 2.0;
	_min_pos_y = -_handle_half_size.y;
	_max_pos_y = size.y - _handle_half_size.y;
	_temp_handle_pos = _handle_root.position;
	_temp_handle_pos.y = pos.y - _handle_half_size.y;
	if _temp_handle_pos.y > _max_pos_y:
		_temp_handle_pos.y = _max_pos_y;
	elif _temp_handle_pos.y < _min_pos_y:
		_temp_handle_pos.y = _min_pos_y;
	_handle_root.position = _temp_handle_pos;
	_percent = (_temp_handle_pos.y - _min_pos_y) / (_max_pos_y - _min_pos_y);
	_current_color.a = 1.0 - _percent;
	_runtime_handle_mat.set_shader_parameter(_handle_color_param, _current_color);

func set_base_color(c: Color) -> void:
	_current_color = c;
	self_modulate.r = _current_color.r;
	self_modulate.g = _current_color.g;
	self_modulate.b = _current_color.b;
	self_modulate.a = 1.0;
	set_alpha_percentage(_current_color.a);

func set_alpha_percentage(a: float) -> void:
	_handle_half_size = _handle_root.size / 2.0;
	_temp_handle_pos = _handle_root.position;
	_temp_handle_pos.y = size.y * clampf(1.0 - a, 0.0, 1.0);
	_on_handle_interface_change(_temp_handle_pos);
