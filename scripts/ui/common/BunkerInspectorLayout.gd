@tool
extends Control
## Compact right-docked in-world inspectors; not full-screen menu proportions.
## Containers own content. At small sizes, scroll instead of shrinking text.
## Every style edit is made to this view's private theme, never the shared asset.

const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)
## Zero uses the generator baseline from the theme. Other inspectors only
## override height; width, docking, type and density stay shared.
@export var panel_height: float = 0.0
var _fit_queued: bool = false

func _ready() -> void:
	theme = theme.duplicate(true) as Theme
	resized.connect(_apply_metrics)
	$Panel.resized.connect(_position_panel)
	$Panel.minimum_size_changed.connect(_queue_panel_fit)
	_apply_metrics()

func _apply_metrics() -> void:
	if not is_node_ready():
		return
	var factor: float = _scale_factor()
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
	theme.set_constant("icon_max_width", "Button", roundi(24.0 * factor))
	theme.set_constant("h_separation", "Button", roundi(12.0 * factor))
	theme.set_constant("separation", "HSeparator", roundi(8.0 * factor))
	# Character creation keeps its original large-button spacing. Only this
	# private inspector theme adopts desktop-density content margins.
	for button_type: String in ["Button", "BunkerPrimaryButton", "BunkerDangerButton"]:
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			# Unspecified variation states inherit Button at lookup time. Never
			# edit an engine fallback resource returned for a missing theme item.
			if not theme.has_stylebox(state, button_type):
				continue
			var style: StyleBox = theme.get_stylebox(state, button_type)
			style.content_margin_left = 16.0 * factor
			style.content_margin_right = 16.0 * factor
			style.content_margin_top = 8.0 * factor
			style.content_margin_bottom = 8.0 * factor
	var panel_style: StyleBox = theme.get_stylebox("panel", "PanelContainer")
	panel_style.content_margin_top = 0.0
	panel_style.content_margin_bottom = 0.0
	_fit_panel()

func _queue_panel_fit() -> void:
	# Wrapped labels can temporarily request a very tall panel before their
	# width is known. Refit when that minimum settles, without reapplying
	# theme overrides (which would itself invalidate minimum sizes).
	if _fit_queued:
		return
	_fit_queued = true
	_fit_panel.call_deferred()

func _fit_panel() -> void:
	_fit_queued = false
	if not is_node_ready():
		return
	var factor: float = _scale_factor()
	var panel: PanelContainer = $Panel
	var target_size := Vector2(
		theme.get_constant("panel_width", "GeneratorInspector"),
		panel_height if panel_height > 0.0 else theme.get_constant("panel_height", "GeneratorInspector")) * factor
	var margin: float = theme.get_constant("screen_margin", "GeneratorInspector") * factor
	panel.size = target_size.min((size - Vector2.ONE * margin * 2.0).max(Vector2.ONE))
	_position_panel()

func _scale_factor() -> float:
	# Keep 1080p text/control sizes at 720p. Reserve shrinking for the scroll
	# region, and cap growth on high-resolution/ultrawide monitors.
	return clampf(minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y), 1.0, 1.25)

func _position_panel() -> void:
	if not is_node_ready():
		return
	var panel: PanelContainer = $Panel
	var margin: float = theme.get_constant("screen_margin", "GeneratorInspector") * _scale_factor()
	panel.position = Vector2(
		maxf(margin, size.x - margin - panel.size.x),
		maxf(margin, (size.y - panel.size.y) * 0.5))
