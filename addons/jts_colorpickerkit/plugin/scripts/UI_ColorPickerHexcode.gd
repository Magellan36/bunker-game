# ============================================================
#  © [2025] [JoenTNT]
#  Licensed under the Apache License, Version 2.0
#  http://www.apache.org/licenses/LICENSE-2.0
# ============================================================

class_name UI_ColorPickerHexcode
extends LineEdit

# Events.
signal on_color_submitted(c: Color);

const VALID_INPUT_REGEX: String = "^#?[A-Fa-f0-9]{6}$";

# Properties.
@export var _live_color_changed: bool = true;

# Runtime variable data.
@export_group("Runtime Debug")
@export var _cached_color: Color = Color.RED;
@onready var _color_hex_regex: RegEx = RegEx.new();
var _cached_color_hex_code: String;
var _red_hex: String = "00";
var _green_hex: String = "00";
var _blue_hex: String = "00";

func _enter_tree() -> void:
	# Subscribe events.
	text_changed.connect(_on_hex_changed);
	text_submitted.connect(_on_hex_submitted);

func _exit_tree() -> void:
	# Unsubscribe events.
	text_changed.disconnect(_on_hex_changed);
	text_submitted.disconnect(_on_hex_submitted);

func _on_hex_changed(txt: String) -> void:
	if not _live_color_changed: return;
	_color_hex_regex.clear();
	_color_hex_regex.compile(VALID_INPUT_REGEX);
	if not _color_hex_regex.search(txt): return;
	_on_hex_text_inserted(txt, false);

func _on_hex_submitted(txt: String) -> void:
	_color_hex_regex.clear();
	_color_hex_regex.compile(VALID_INPUT_REGEX);
	if not _color_hex_regex.search(txt):
		text = _cached_color_hex_code;
		return;
	_on_hex_text_inserted(txt, true);

func _on_hex_text_inserted(txt: String, cached_str: bool) -> void:
	txt.to_upper();
	if not txt.begins_with("#"): txt.insert(0, "#");
	if cached_str:
		_cached_color_hex_code = txt;
	_red_hex = txt.substr(1, 2);
	_green_hex = txt.substr(3, 2);
	_blue_hex = txt.substr(5, 2);
	_cached_color.r8 = _red_hex.hex_to_int();
	_cached_color.g8 = _green_hex.hex_to_int();
	_cached_color.b8 = _blue_hex.hex_to_int();
	on_color_submitted.emit(_cached_color);

func set_hex_code(c: Color) -> void:
	_cached_color = c;
	_red_hex = "%02X" % c.r8;
	_green_hex = "%02X" % c.g8;
	_blue_hex = "%02X" % c.b8;
	text = "#" + _red_hex + _green_hex + _blue_hex;
	_cached_color_hex_code = text;
