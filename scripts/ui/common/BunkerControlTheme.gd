class_name BunkerControlTheme
extends RefCounted
## Shared skin for ordinary controls. Does not choose a screen's font family,
## density, layout or custom status-meter colors.
static func _box(bg: Color, edge: Color, radius: int = 5, width: int = 1) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = edge
	style.set_corner_radius_all(radius)
	style.set_border_width_all(width)
	return style

static func install(theme: Theme) -> void:
	for role: String in ["Title", "Body", "Secondary", "Caption", "Hint"]:
		var sizes: Dictionary = {"Title": BunkerDesign.TITLE_SIZE, "Body": BunkerDesign.BODY_SIZE,
			"Secondary": BunkerDesign.SECONDARY_SIZE, "Caption": BunkerDesign.CAPTION_SIZE, "Hint": BunkerDesign.HINT_SIZE}
		theme.set_type_variation("Bunker" + role, "Label")
		theme.set_font_size("font_size", "Bunker" + role, int(sizes[role]))
		theme.set_color("font_color", "Bunker" + role,
			BunkerDesign.IVORY if role in ["Title", "Body"] else BunkerDesign.MUTED)
	for kind: String in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", kind, _box(BunkerDesign.BG, Color.TRANSPARENT, 5, 0))
		theme.set_stylebox("grabber", kind, scrollbar_style("grabber"))
		theme.set_stylebox("grabber_highlight", kind, scrollbar_style("grabber_highlight"))
		theme.set_stylebox("grabber_pressed", kind, scrollbar_style("grabber_pressed"))
		theme.set_stylebox("focus", kind, _box(Color.TRANSPARENT, BunkerDesign.IVORY, 5, 2))
	for kind: String in ["HSlider", "VSlider"]:
		var track: StyleBoxFlat = _box(BunkerDesign.BG, BunkerDesign.BRASS.darkened(0.4), 3)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		track.content_margin_left = 3
		track.content_margin_right = 3
		theme.set_stylebox("slider", kind, track)
		theme.set_stylebox("grabber_area", kind, _box(BunkerDesign.BLUE_DARK, Color.TRANSPARENT, 3, 0))
		theme.set_stylebox("grabber_area_highlight", kind, _box(BunkerDesign.BLUE, Color.TRANSPARENT, 3, 0))
		for icon_state: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
			var knob: GradientTexture2D = GradientTexture2D.new()
			knob.width = 12
			knob.height = 18
			var gradient: Gradient = Gradient.new()
			var tint: Color = BunkerDesign.IVORY if icon_state == "grabber_highlight" else BunkerDesign.BLUE
			if icon_state == "grabber_disabled":
				tint = BunkerDesign.MUTED.darkened(0.4)
			gradient.colors = PackedColorArray([tint, tint])
			knob.gradient = gradient
			theme.set_icon(icon_state, kind, knob)
	for kind: String in ["LineEdit", "TextEdit", "OptionButton", "PopupMenu"]:
		var normal: StyleBoxFlat = _box(BunkerDesign.SURFACE, BunkerDesign.BRASS.darkened(0.24), 7)
		normal.content_margin_left = 10
		normal.content_margin_right = 10
		normal.content_margin_top = 3
		normal.content_margin_bottom = 3
		theme.set_stylebox("panel" if kind == "PopupMenu" else "normal", kind, normal)
		theme.set_stylebox("focus", kind, _box(Color.TRANSPARENT, BunkerDesign.IVORY, 9, 2))
		theme.set_color("font_color", kind, BunkerDesign.IVORY)
		theme.set_color("font_disabled_color", kind, BunkerDesign.MUTED.darkened(0.35))
		theme.set_color("font_placeholder_color", kind, BunkerDesign.MUTED)
		theme.set_color("caret_color", kind, BunkerDesign.BLUE)
		theme.set_color("selection_color", kind, BunkerDesign.BLUE_DARK)
		var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		hover.bg_color = BunkerDesign.BLUE_DARK
		hover.border_color = BunkerDesign.BLUE
		theme.set_stylebox("hover", kind, hover)
		theme.set_stylebox("pressed", kind, hover)
		theme.set_font_size("font_size", kind, BunkerDesign.SECONDARY_SIZE)
	# Tooltips use the same compact text treatment, never a permanent banner.
	var tooltip: StyleBoxFlat = _box(BunkerDesign.SHELL, BunkerDesign.BRASS, 6)
	tooltip.content_margin_left = 9
	tooltip.content_margin_right = 9
	tooltip.content_margin_top = 6
	tooltip.content_margin_bottom = 6
	theme.set_stylebox("panel", "TooltipPanel", tooltip)
	theme.set_color("font_color", "TooltipLabel", BunkerDesign.IVORY)
	theme.set_font_size("font_size", "TooltipLabel", BunkerDesign.SECONDARY_SIZE)


static func scrollbar_style(state: String) -> StyleBoxFlat:
	var tint: Color = BunkerDesign.IVORY
	if state == "grabber":
		tint = tint.darkened(0.18)
	elif state == "grabber_pressed":
		tint = tint.darkened(0.08)
	return _box(tint, Color.TRANSPARENT, 5, 0)
