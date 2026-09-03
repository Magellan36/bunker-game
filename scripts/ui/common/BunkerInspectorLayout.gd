@tool
extends Control
## Opt-in inspector layout. Containers own content; this only scales metrics
## and bounds the outer panel. Does not change project-wide stretch settings.

const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)

func _ready() -> void:
	theme = theme.duplicate(true) as Theme
	resized.connect(_apply_metrics)
	_apply_metrics()

func _apply_metrics() -> void:
	if not is_node_ready():
		return
	var factor: float = clampf(minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y), 0.667, 1.333)
	for node: Node in find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control.has_meta("ui_font_size"):
			control.add_theme_font_size_override("font_size", roundi(float(control.get_meta("ui_font_size")) * factor))
		if control.has_meta("ui_min_height"):
			control.custom_minimum_size.y = roundf(float(control.get_meta("ui_min_height")) * factor)
		if control.has_meta("ui_gap"):
			control.add_theme_constant_override("separation", roundi(float(control.get_meta("ui_gap")) * factor))
		if control.has_meta("ui_padding"):
			for edge: String in ["left", "top", "right", "bottom"]:
				control.add_theme_constant_override("margin_" + edge, roundi(float(control.get_meta("ui_padding")) * factor))
		if control.has_meta("ui_icon_size"):
			var side: float = roundf(float(control.get_meta("ui_icon_size")) * factor)
			control.custom_minimum_size = Vector2(side, side)
	theme.set_constant("icon_max_width", "Button", roundi(32.0 * factor))
	theme.set_constant("h_separation", "Button", roundi(16.0 * factor))
	var panel: PanelContainer = $Panel
	var target_size := Vector2(
		theme.get_constant("panel_width", "GeneratorInspector"),
		theme.get_constant("panel_height", "GeneratorInspector")) * factor
	# Minimum content may grow; ScrollContainer keeps the main body bounded.
	panel.size = target_size.min((size - Vector2(32.0, 32.0)).max(Vector2.ONE))
	panel.position = (size - panel.size) * 0.5
