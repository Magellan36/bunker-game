@tool
extends MarginContainer
## Screen-local scaling; never changes project-wide stretch or UI settings.
## Containers still own positions and scrolling. Metadata records 1080p sizes.

const REDESIGN_THEME: Theme = preload("res://assets/ui/themes/BunkerRedesignTheme.tres")
const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)

func _ready() -> void:
	theme = REDESIGN_THEME.duplicate(true) as Theme
	resized.connect(_apply_metrics)
	_apply_metrics()

func _apply_metrics() -> void:
	if not is_node_ready():
		return
	var factor: float = clampf(minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y), 0.667, 1.333)
	var controls: Array[Node] = find_children("*", "Control", true, false)
	controls.append(self)
	for node: Node in controls:
		var control: Control = node as Control
		if control.has_meta("ui_font_size"):
			control.add_theme_font_size_override("font_size", roundi(float(control.get_meta("ui_font_size")) * factor))
		if control.has_meta("ui_min_height"):
			control.custom_minimum_size.y = roundf(float(control.get_meta("ui_min_height")) * factor)
		if control.has_meta("ui_gap"):
			control.add_theme_constant_override("separation", roundi(float(control.get_meta("ui_gap")) * factor))
		if control.has_meta("ui_padding"):
			var padding: int = roundi(float(control.get_meta("ui_padding")) * factor)
			for edge: String in ["left", "top", "right", "bottom"]:
				control.add_theme_constant_override("margin_" + edge, padding)
		if control.has_meta("ui_icon_size"):
			var side: float = roundf(float(control.get_meta("ui_icon_size")) * factor)
			control.custom_minimum_size = Vector2(side, side)
		if control.has_meta("ui_edge_icon_size"):
			var side: float = roundf(float(control.get_meta("ui_edge_icon_size")) * factor)
			control.offset_left = -24.0 * factor - side
			control.offset_right = -24.0 * factor
			control.offset_top = -side / 2.0
			control.offset_bottom = side / 2.0
	# Keep ultrawide monitors from stretching a choice into a metre-wide row.
	var side_margin: int = roundi(48.0 * factor + maxf(0.0, (size.x - DESIGN_SIZE.x * factor) / 2.0))
	add_theme_constant_override("margin_left", side_margin)
	add_theme_constant_override("margin_right", side_margin)
	theme.set_constant("icon_max_width", "Button", roundi(40.0 * factor))
	theme.set_constant("h_separation", "Button", roundi(20.0 * factor))
	# Reserve space for trailing selection/arrow icons; they must never cover text.
	for button_type: String in ["Button", "BunkerPrimaryButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			if not theme.has_stylebox(state, button_type):
				continue
			var style: StyleBox = theme.get_stylebox(state, button_type)
			style.content_margin_left = (72.0 if button_type == "BunkerPrimaryButton" else 24.0) * factor
			style.content_margin_right = 72.0 * factor
