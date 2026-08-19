# ============================================================
#  © [2025] [JoenTNT]
#  Licensed under the Apache License, Version 2.0
#  http://www.apache.org/licenses/LICENSE-2.0
# ============================================================

class_name UI_ColorPickerSV
extends UI_GUIControlPicker

# Events.
signal on_sv_changed(s: float, v: float);

@export var _handle_object: Control = null;
@export var _handle_tex: TextureRect = null;
@export var _main_color_param: StringName = &"hue_color";
@export var _handle_fill_param: StringName = &"fill_color";

# Runtime variable data.
@export_group("Runtime Debug")
@export var _current_color: Color = Color.RED;
var _temp_color: Color;
var _runtime_handle_mat: ShaderMaterial = null;
var _handle_half_size: Vector2 = Vector2.ZERO;
var _min_pos: Vector2 = Vector2.ZERO;
var _max_pos: Vector2 = Vector2.ZERO;
var _fixed_hue: float = 0.0;
var _saturation: float = 0.0;
var _lvalue: float = 0.0;
var _pos_x: float = 0.0;
var _pos_y: float = 0.0;

func _ready() -> void:
	super._ready();
	if _handle_tex.material != null:
		if _handle_tex.material is ShaderMaterial:
			_runtime_handle_mat = _handle_tex.material as ShaderMaterial;
			_runtime_handle_mat = _runtime_handle_mat.duplicate(true);
			_handle_tex.material = _runtime_handle_mat;

func _on_adjust_by_position(pos: Vector2) -> void:
	_on_handle_interface_change(pos);
	on_sv_changed.emit(1.0 - _saturation, _lvalue);

func _on_handle_interface_change(pos: Vector2) -> void:
	_handle_half_size = _handle_object.size / 2.0;
	_min_pos = -_handle_half_size;
	_max_pos = size - _handle_half_size;
	_pos_x = pos.x - _handle_half_size.x;
	_pos_y = pos.y - _handle_half_size.y;
	if _pos_x < _min_pos.x: _pos_x = _min_pos.x;
	elif _pos_x > _max_pos.x: _pos_x = _max_pos.x;
	if _pos_y < _min_pos.y: _pos_y = _min_pos.y;
	elif _pos_y > _max_pos.y: _pos_y = _max_pos.y;
	_handle_object.position = Vector2(_pos_x, _pos_y);
	_saturation = 1.0 - ((_pos_x - _min_pos.x) / (_max_pos.x - _min_pos.x));
	_lvalue = 1.0 - ((_pos_y - _min_pos.y) / (_max_pos.y - _min_pos.y));
	_current_color.h = _fixed_hue;
	_current_color.s = 1.0 - _saturation;
	_current_color.v = _lvalue;
	_runtime_handle_mat.set_shader_parameter(_handle_fill_param, _current_color);

func set_main_color(c: Color) -> void:
	c.a = 1.0;
	_fixed_hue = c.h;
	_current_color.h = c.h;
	_handle_half_size = _handle_object.size / 2.0;
	_min_pos = -_handle_half_size;
	_max_pos = size - _handle_half_size;
	_pos_x = c.s * (_max_pos.x - _min_pos.x) - _handle_half_size.x;
	_pos_y = (1.0 - c.v) * (_max_pos.y - _min_pos.y) - _handle_half_size.y;
	_handle_object.position = Vector2(_pos_x, _pos_y);
	_runtime_handle_mat.set_shader_parameter(_handle_fill_param, c);
	c.s = 1.0;
	c.v = 1.0;
	_runtime_tex_mat.set_shader_parameter(_main_color_param, c);

func set_solid_main_color_only(c: Color) -> void:
	_runtime_tex_mat.set_shader_parameter(_main_color_param, c);

func set_saturation_position(sat: float) -> void:
	_handle_half_size = _handle_object.size / 2.0;
	_min_pos = -_handle_half_size;
	_max_pos = size - _handle_half_size;
	_pos_x = sat * (_max_pos.x - _min_pos.x) - _handle_half_size.x;
	_handle_object.position = Vector2(_pos_x, _handle_object.position.y);

func set_hue_percentage(hue: float) -> void:
	_fixed_hue = hue;
	_temp_color = Color.RED;
	_temp_color.h = _fixed_hue;
	_current_color.h = _fixed_hue;
	_runtime_handle_mat.set_shader_parameter(_handle_fill_param, _current_color);
	_temp_color.s = 1.0;
	_temp_color.v = 1.0;
	_runtime_tex_mat.set_shader_parameter(_main_color_param, _temp_color);

func set_sv_position(pos: Vector2) -> void:
	_on_handle_interface_change(pos);

func get_fixed_position() -> Vector2:
	return Vector2(_pos_x, _pos_y);
