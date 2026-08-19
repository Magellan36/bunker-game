# ============================================================
#  © [2025] [JoenTNT]
#  Licensed under the Apache License, Version 2.0
#  http://www.apache.org/licenses/LICENSE-2.0
# ============================================================

class_name UI_ColorPickerHexSlider
extends UI_SliderInputTemplate

# Events.
signal on_color_hex_changed(hexv: int);

# Properties.
@export var _num_regex_str: String = "^(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})$";
## Used to display on line input, you can include either [b]%d[/b] or [b]%f[/b] in text.
@export var _formated_input_str: String = "%d";

# Runtime variable data.
@onready var _hex_regex: RegEx = RegEx.new();
var _cached_hex_string: String = "";
var _is_gui_input: bool = false;

func _on_slider_value_changed(value: float) -> void:
	_cached_hex_string = _formated_input_str % value;
	_line_input.text = _cached_hex_string;
	if _is_gui_input:
		on_color_hex_changed.emit(value);

func _on_number_input_submit(txt: String) -> void:
	_hex_regex.clear();
	_hex_regex.compile(_num_regex_str);
	if not _hex_regex.search(txt):
		_line_input.text = _cached_hex_string;
		return;
	_cached_hex_string = _line_input.text;
	_is_gui_input = true;
	_slider.value = int(_cached_hex_string);

func _on_gui_selected() -> void:
	_is_gui_input = true;

func _on_gui_released() -> void:
	_is_gui_input = false;

## Setting hex value of color from 0 to 255.
func set_hex_value(hex: int) -> void:
	_is_gui_input = false;
	_slider.value = hex;
