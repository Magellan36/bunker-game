extends VBoxContainer
## Shared, owner-confirmed 1–5 priority selector; no simulation policy here.
## Quiet pass (Sep 2026): one row — "Priority" left, "−  3 · STANDARD  +"
## right. The tier word stays uppercase (it is a status tag); colour is
## reserved for the extremes the player should notice.
signal priority_requested(value: int)
const W: GDScript = preload("res://scripts/ui/common/BunkerInspectorWidgets.gd")
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
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
	row.set_meta("ui_gap", 6)
	frame.add_child(row)
	var title: Label = W.label(row, "Caption", "Priority", 15, "secondary")
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_less = W.button(row, "Decrease", "−", func(): priority_requested.emit(maxi(1, _value - 1)))
	_less.size_flags_horizontal = Control.SIZE_SHRINK_END
	_less.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_less.custom_minimum_size.x = 36
	_caption = W.label(row, "Value", "3 · STANDARD", 15)
	_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	_caption.size_flags_horizontal = Control.SIZE_SHRINK_END
	_caption.custom_minimum_size.x = 130
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more = W.button(row, "Increase", "+", func(): priority_requested.emit(mini(5, _value + 1)))
	_more.size_flags_horizontal = Control.SIZE_SHRINK_END
	_more.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_more.custom_minimum_size.x = 36
	for button: Button in [_less, _more]:
		button.clip_text = false
		button.add_theme_font_size_override("font_size", 18)
		button.set_meta("ui_font_size", 18)
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			if style != null:
				style.content_margin_left = 4.0
				style.content_margin_right = 4.0
				button.add_theme_stylebox_override(state, style)
		## Left/Right on either step button nudges the tier (quiet ui_cycle).
		button.set_meta(&"ui_cycle", func(direction: int) -> void:
			priority_requested.emit(clampi(_value + direction, 1, 5)))
	_less.tooltip_text = "Toward CRITICAL (1)"
	_more.tooltip_text = "Toward LUXURY (5)"
	## Retain the compatibility handle used by existing inspector subclasses,
	## but tutorials now own this explanation; the UI only shows the tier row.
	_hint = W.label(self, "Hint", "", 13, "secondary")
	_hint.hide()
	set_value(3)

func set_value(value: int, available: bool = true) -> void:
	_value = clampi(value, 1, 5)
	_caption.text = "%d · %s" % [_value, UIFormat.allocation_tier(_value)]
	_less.disabled = not available or _value <= 1
	_more.disabled = not available or _value >= 5
	_caption.add_theme_color_override("font_color", Q.TEXT if available else Q.FAINT)

func set_hint(text: String) -> void:
	_hint.text = text
	_hint.hide()
