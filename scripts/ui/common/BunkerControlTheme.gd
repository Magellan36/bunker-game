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
		# Quiet scrollbars (Sep 2026): no track, slim faint grabber.
		theme.set_stylebox("scroll", kind, _box(Color.TRANSPARENT, Color.TRANSPARENT, 3, 0))
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
	# Quiet popup surface (Sep 2026): near-opaque charcoal, faint brass edge.
	var tooltip: StyleBoxFlat = _box(Color(0.067, 0.086, 0.082, 0.99),
		Color(BunkerDesign.BRASS, 0.3), 6)
	tooltip.content_margin_left = 9
	tooltip.content_margin_right = 9
	tooltip.content_margin_top = 6
	tooltip.content_margin_bottom = 6
	theme.set_stylebox("panel", "TooltipPanel", tooltip)
	theme.set_color("font_color", "TooltipLabel", BunkerDesign.IVORY)
	theme.set_font_size("font_size", "TooltipLabel", BunkerDesign.SECONDARY_SIZE)


## Quiet grabber (Sep 2026, same look as QuietControls.scrollbar()): a 6 px
## faint ivory bar drawn inside a controller-sized 16 px hit area via
## transparent side borders.
static func scrollbar_style(state: String) -> StyleBoxFlat:
	var alpha: float = 0.13
	if state == "grabber_highlight":
		alpha = 0.26
	elif state == "grabber_pressed":
		alpha = 0.34
	var style: StyleBoxFlat = _box(Color(BunkerDesign.IVORY, alpha), Color(0, 0, 0, 0), 3, 0)
	style.border_width_left = 5
	style.border_width_right = 5
	return style
