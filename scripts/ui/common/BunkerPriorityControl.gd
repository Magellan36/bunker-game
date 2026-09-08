extends VBoxContainer
## Shared, owner-confirmed 1–5 priority selector; no simulation policy here.
signal priority_requested(value: int)
const W: GDScript = preload("res://scripts/ui/common/BunkerInspectorWidgets.gd")
var _value: int = 3
var _less: Button
var _more: Button
var _caption: Label
var _hint: Label

func _ready() -> void:
	set_meta("ui_gap", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame: MarginContainer = W.frame(self, "PriorityCard")
	var row := HBoxContainer.new()
	row.name = "Controls"
	row.set_meta("ui_gap", 10)
	frame.add_child(row)
	_less = W.button(row, "Decrease", "−", func(): priority_requested.emit(maxi(1, _value - 1)))
	_less.size_flags_horizontal = Control.SIZE_FILL
	_less.custom_minimum_size.x = 48
	_less.tooltip_text = "Move toward CRITICAL (1)"
	_caption = W.label(row, "Value", "3 · STANDARD", 16)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more = W.button(row, "Increase", "+", func(): priority_requested.emit(mini(5, _value + 1)))
	_more.size_flags_horizontal = Control.SIZE_FILL
	_more.custom_minimum_size.x = 48
	_more.tooltip_text = "Move toward LUXURY (5)"
	## Retain the compatibility handle used by existing inspector subclasses,
	## but tutorials now own this explanation; the UI only shows the tier row.
	_hint = W.label(self, "Hint", "", 14, "secondary")
	_hint.hide()
	set_value(3)

func set_value(value: int, available: bool = true) -> void:
	_value = clampi(value, 1, 5)
	_caption.text = "%d · %s" % [_value, UIFormat.allocation_tier(_value)]
	_less.disabled = not available or _value <= 1
	_more.disabled = not available or _value >= 5
	_caption.add_theme_color_override("font_color", W.color(self, "success" if _value <= 2 else ("warning" if _value <= 4 else "critical")))

func set_hint(text: String) -> void:
	_hint.text = text
	_hint.hide()
