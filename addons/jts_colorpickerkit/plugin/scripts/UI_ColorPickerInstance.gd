# ============================================================
#  © [2025] [JoenTNT]
#  Licensed under the Apache License, Version 2.0
#  http://www.apache.org/licenses/LICENSE-2.0
# ============================================================

@tool
class_name UI_ColorPickerInstance
extends Control

# Events.
## Event called when color has been confirmed, cached the current choosen color.
signal on_color_picked(c: Color);

@export var _sv_gradient: UI_ColorPickerSV = null;
@export var _hue_slider: UI_ColorPickerHueSlider = null;
@export var _alpha_slider: UI_ColorPickerAlphaSlider = null;
@export var _hexcode_editor: UI_ColorPickerHexcode = null;
@export var _rgb_mode_btn: Button = null;
@export var _hsv_mode_btn: Button = null;

@export_group("Interactive Controls")
@export var _red_slider: UI_ColorPickerHexSlider = null;
@export var _green_slider: UI_ColorPickerHexSlider = null;
@export var _blue_slider: UI_ColorPickerHexSlider = null;
@export var _hue_v_slider: UI_NumberInputSlider = null;
@export var _saturation_v_slider: UI_NumberInputSlider = null;
@export var _value_v_slider: UI_NumberInputSlider = null;
@export var _alpha_v_slider: UI_NumberInputSlider = null;

@export_group("Runtime Optionals")
@export var _picked_color: Color = Color.RED;
@export var _targeted_control: Control = null;
@export var _color_setter_name: StringName = &"set_color";

# Runtime variable data.
@onready var _temp_color: Color = Color(1.0, 1.0, 1.0, 1.0);
var _fixed_hue: float = 0.0;
var _fixed_sat: float = 0.0;
var _fixed_val: float = 0.0;

func _enter_tree() -> void:
	# Subscribe events.
	_sv_gradient.on_sv_changed.connect(_on_sv_changed);
	_hue_slider.on_hue_changed.connect(_on_hue_changed);
	_alpha_slider.on_alpha_changed.connect(_on_alpha_changed);
	_red_slider.on_color_hex_changed.connect(_on_red_hex_changed);
	_green_slider.on_color_hex_changed.connect(_on_green_hex_changed);
	_blue_slider.on_color_hex_changed.connect(_on_blue_hex_changed);
	_hexcode_editor.on_color_submitted.connect(_on_hex_color_submitted);
	_hue_v_slider.on_number_changed.connect(_on_hue_v_slider_changed);
	_saturation_v_slider.on_number_changed.connect(_on_saturation_v_slider_changed);
	_value_v_slider.on_number_changed.connect(_on_value_v_slider_changed);
	_alpha_v_slider.on_number_changed.connect(_on_alpha_v_slider_changed);

func _exit_tree() -> void:
	# Unsubscribe events.
	_sv_gradient.on_sv_changed.disconnect(_on_sv_changed);
	_hue_slider.on_hue_changed.disconnect(_on_hue_changed);
	_alpha_slider.on_alpha_changed.disconnect(_on_alpha_changed);
	_red_slider.on_color_hex_changed.disconnect(_on_red_hex_changed);
	_green_slider.on_color_hex_changed.disconnect(_on_green_hex_changed);
	_blue_slider.on_color_hex_changed.disconnect(_on_blue_hex_changed);
	_hexcode_editor.on_color_submitted.disconnect(_on_hex_color_submitted);
	_hue_v_slider.on_number_changed.disconnect(_on_hue_v_slider_changed);
	_saturation_v_slider.on_number_changed.disconnect(_on_saturation_v_slider_changed);
	_value_v_slider.on_number_changed.disconnect(_on_value_v_slider_changed);
	_alpha_v_slider.on_number_changed.disconnect(_on_alpha_v_slider_changed);

func _ready() -> void:
	_fixed_hue = _picked_color.h;
	_fixed_sat = _picked_color.s;
	_fixed_val = _picked_color.v;
	_sv_gradient.call_deferred(&"set_main_color", _picked_color);
	_hue_slider.call_deferred(&"set_hue_percentage", _picked_color.h);
	_alpha_slider.call_deferred(&"set_base_color", _picked_color);
	_red_slider.call_deferred(&"set_hex_value", _picked_color.r8);
	_green_slider.call_deferred(&"set_hex_value", _picked_color.g8);
	_blue_slider.call_deferred(&"set_hex_value", _picked_color.b8);
	_hexcode_editor.call_deferred(&"set_hex_code", _picked_color);
	_rgb_mode_btn.call_deferred(&"emit_signal", &"pressed");
	_hue_v_slider.call_deferred(&"set_value", _picked_color.h);
	_saturation_v_slider.call_deferred(&"set_value", _picked_color.s);
	_value_v_slider.call_deferred(&"set_value", _picked_color.v)
	_alpha_v_slider.call_deferred(&"set_value", _picked_color.a);

func _on_sv_changed(s: float, v: float) -> void:
	_fixed_sat = s;
	_fixed_val = v;
	_picked_color.h = _fixed_hue;
	_picked_color.s = _fixed_sat;
	_picked_color.v = _fixed_val;
	_hue_slider.set_hue_percentage(_fixed_hue);
	_alpha_slider.set_base_color(_picked_color);
	_red_slider.set_hex_value(_picked_color.r8);
	_green_slider.set_hex_value(_picked_color.g8);
	_blue_slider.set_hex_value(_picked_color.b8);
	_hexcode_editor.set_hex_code(_picked_color);
	_hue_v_slider.set_value(_picked_color.h);
	_saturation_v_slider.set_value(_picked_color.s);
	_value_v_slider.set_value(_picked_color.v);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_hue_changed(c: Color) -> void:
	_fixed_hue = c.h;
	_picked_color.h = _fixed_hue;
	_sv_gradient.set_main_color(_picked_color);
	c.s = 1.0;
	c.v = 1.0;
	_sv_gradient.set_solid_main_color_only(c);
	_alpha_slider.set_base_color(_picked_color);
	_red_slider.set_hex_value(_picked_color.r8);
	_green_slider.set_hex_value(_picked_color.g8);
	_blue_slider.set_hex_value(_picked_color.b8);
	_hexcode_editor.set_hex_code(_picked_color);
	_hue_v_slider.set_value(_picked_color.h);
	_saturation_v_slider.set_value(_picked_color.s);
	_value_v_slider.set_value(_picked_color.v);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_alpha_changed(c: Color) -> void:
	_picked_color.a = c.a;
	_hexcode_editor.set_hex_code(_picked_color);
	_alpha_v_slider.set_value(_picked_color.a);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_red_hex_changed(hexv: int) -> void:
	_picked_color.r8 = hexv;
	_fixed_hue = _picked_color.h;
	_hue_slider.set_hue_percentage(_fixed_hue);
	_sv_gradient.set_main_color(_picked_color);
	_hexcode_editor.set_hex_code(_picked_color);
	_hue_v_slider.set_value(_picked_color.h);
	_saturation_v_slider.set_value(_picked_color.s);
	_value_v_slider.set_value(_picked_color.v);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_green_hex_changed(hexv: int) -> void:
	_picked_color.g8 = hexv;
	_fixed_hue = _picked_color.h;
	_hue_slider.set_hue_percentage(_fixed_hue);
	_sv_gradient.set_main_color(_picked_color);
	_hexcode_editor.set_hex_code(_picked_color);
	_hue_v_slider.set_value(_picked_color.h);
	_saturation_v_slider.set_value(_picked_color.s);
	_value_v_slider.set_value(_picked_color.v);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_blue_hex_changed(hexv: int) -> void:
	_picked_color.b8 = hexv;
	_fixed_hue = _picked_color.h;
	_hue_slider.set_hue_percentage(_fixed_hue);
	_sv_gradient.set_main_color(_picked_color);
	_hexcode_editor.set_hex_code(_picked_color);
	_hue_v_slider.set_value(_picked_color.h);
	_saturation_v_slider.set_value(_picked_color.s);
	_value_v_slider.set_value(_picked_color.v);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_hex_color_submitted(c: Color) -> void:
	_picked_color = c;
	_fixed_hue = _picked_color.h;
	_fixed_sat = _picked_color.s;
	_fixed_val = _picked_color.v;
	_red_slider.set_hex_value(_picked_color.r8);
	_green_slider.set_hex_value(_picked_color.g8);
	_blue_slider.set_hex_value(_picked_color.b8);
	_hue_slider.set_hue_percentage(_fixed_hue);
	_sv_gradient.set_main_color(_picked_color);
	_hue_v_slider.set_value(_picked_color.h);
	_saturation_v_slider.set_value(_picked_color.s);
	_value_v_slider.set_value(_picked_color.v);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_hue_v_slider_changed(v: float) -> void:
	_fixed_hue = v;
	_picked_color.h = _fixed_hue;
	_picked_color.s = _fixed_sat;
	_picked_color.v = _fixed_val;
	_hue_slider.set_hue_percentage(_fixed_hue);
	_sv_gradient.set_main_color(_picked_color);
	_red_slider.set_hex_value(_picked_color.r8);
	_green_slider.set_hex_value(_picked_color.g8);
	_blue_slider.set_hex_value(_picked_color.b8);
	_hexcode_editor.set_hex_code(_picked_color);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_saturation_v_slider_changed(v: float) -> void:
	_fixed_sat = v;
	_picked_color.v = _fixed_val;
	_picked_color.s = _fixed_sat;
	_picked_color.h = _fixed_hue;
	_hue_slider.set_hue_percentage(_fixed_hue);
	_sv_gradient.set_main_color(_picked_color);
	_temp_color.h = _fixed_hue;
	_temp_color.s = 1.0;
	_temp_color.v = 1.0;
	_sv_gradient.set_solid_main_color_only(_temp_color);
	_sv_gradient.set_saturation_position(_fixed_sat);
	_red_slider.set_hex_value(_picked_color.r8);
	_green_slider.set_hex_value(_picked_color.g8);
	_blue_slider.set_hex_value(_picked_color.b8);
	_hexcode_editor.set_hex_code(_picked_color);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_value_v_slider_changed(v: float) -> void:
	_fixed_val = v;
	_picked_color.v = _fixed_val;
	_picked_color.s = _fixed_sat;
	_picked_color.h = _fixed_hue;
	_hue_slider.set_hue_percentage(_fixed_hue);
	_sv_gradient.set_main_color(_picked_color);
	_temp_color.h = _fixed_hue;
	_temp_color.s = 1.0;
	_temp_color.v = 1.0;
	_sv_gradient.set_solid_main_color_only(_temp_color);
	_sv_gradient.set_saturation_position(_fixed_sat);
	_red_slider.set_hex_value(_picked_color.r8);
	_green_slider.set_hex_value(_picked_color.g8);
	_blue_slider.set_hex_value(_picked_color.b8);
	_hexcode_editor.set_hex_code(_picked_color);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

func _on_alpha_v_slider_changed(v: float) -> void:
	_picked_color.a = v;
	_hexcode_editor.set_hex_code(_picked_color);
	_alpha_slider.set_alpha_percentage(_picked_color.a);
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
	on_color_picked.emit(_picked_color);

## Setting current picked color.
## This function won't call the event.
func set_picked_color(c: Color) -> void:
	_picked_color = c;
	_fixed_hue = c.h;
	_fixed_sat = c.s;
	_fixed_val = c.v;
	_temp_color.h = c.h;
	_temp_color.s = 1.0;
	_temp_color.v = 1.0;
	_sv_gradient.set_main_color(_picked_color);
	_hue_slider.set_hue_percentage(_fixed_hue);
	_alpha_slider.set_base_color(_picked_color);
	_red_slider.set_hex_value(_picked_color.r8);
	_green_slider.set_hex_value(_picked_color.g8);
	_blue_slider.set_hex_value(_picked_color.b8);
	_hue_v_slider.set_value(_picked_color.h);
	_saturation_v_slider.set_value(_picked_color.s);
	_value_v_slider.set_value(_picked_color.v);
	_alpha_v_slider.set_value(_picked_color.a);

## Get current cached picked color.
func get_picked_color() -> Color:
	return _picked_color;

## Setting the target control node for color instance to live send the color.
func set_targeted_control(target: Control) -> void:
	_targeted_control = target;
	if _targeted_control != null:
		if _targeted_control.has_method(_color_setter_name):
			_targeted_control.call(_color_setter_name, _picked_color);
