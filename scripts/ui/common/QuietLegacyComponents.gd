extends RefCounted
## QuietLegacyComponents.gd (Sep 2026, quiet redesign Pass 4)
## Drop-in replacement for `const C := preload(BunkerUIComponents)` in the
## v1 workspaces. Delegates everything, except that panel_box() — the
## bordered card/pill/well style those screens build by hand — becomes a
## quiet group surface: faint ivory wash, no border, radius ≤ 8, the same
## content padding (so layouts do not move). A border survives only where it
## marked selection (hero blue → 1 px ACCENT at 60 %).

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const SCROLLBAR_CONTENT_GUTTER: int = BunkerUIComponents.SCROLLBAR_CONTENT_GUTTER

static func apply_theme(root: Control) -> void:
	BunkerUIComponents.apply_theme(root)

static func shell(panel: PanelContainer, radius: int = 12) -> void:
	BunkerUIComponents.shell(panel, radius)

static func panel_box(bg: Color, border: Color, radius: int = 8,
		width: int = 1, padding: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	## Dark card fills flatten to one faint wash; transparent stays clear.
	## Bright fills carry meaning (meter fills, swatches) and are kept.
	if bg.a > 0.3 and bg.get_luminance() > 0.35:
		style.bg_color = bg
	else:
		style.bg_color = Color(Q.TEXT, 0.028) if bg.a > 0.05 else Color(0, 0, 0, 0)
	style.set_corner_radius_all(mini(radius, 8))
	style.anti_aliasing = true
	var selection: bool = width > 0 and _is_blue(border)
	style.set_border_width_all(1 if selection else 0)
	style.border_color = Color(Q.ACCENT, 0.6)
	if padding > 0:
		style.set_content_margin_all(float(padding))
	return style

static func _is_blue(color: Color) -> bool:
	return color.a > 0.3 and color.b > color.r + 0.18 and color.b > 0.45

static func inset(child: Control, left: int = 18, top: int = 16,
		right: int = 18, bottom: int = 16) -> MarginContainer:
	return BunkerUIComponents.inset(child, left, top, right, bottom)

static func scroll_content(scroll: ScrollContainer, child: Control,
		left: int = 2, top: int = 2, bottom: int = 2,
		right: int = SCROLLBAR_CONTENT_GUTTER) -> MarginContainer:
	Q.scrollbar(scroll.get_v_scroll_bar())
	return BunkerUIComponents.scroll_content(scroll, child, left, top, bottom, right)

static func icon_well(symbol: String, side: float = 48.0,
		tint: Color = BunkerPanelStyle.BLUE) -> PanelContainer:
	return BunkerUIComponents.icon_well(symbol, side, tint)

static func section_header(parent: Container, title_text: String,
		meta_text: String = "") -> Dictionary:
	return BunkerUIComponents.section_header(parent, title_text, meta_text)

static func divider(parent: Container) -> HSeparator:
	return BunkerUIComponents.divider(parent)

static func style_segment(button: Button, compact: bool = false,
		borderless: bool = false) -> void:
	BunkerUIComponents.style_segment(button, compact, borderless)
