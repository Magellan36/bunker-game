extends RefCounted
## QuietLegacyStyle.gd (Sep 2026, quiet redesign Pass 4)
## Drop-in replacement for `const S := preload(BunkerPanelStyle)` in screens
## written against the "redesign v1" vocabulary. Same constant and function
## names, quiet values (docs/ui/QUIET_DESIGN_SYSTEM.md §2): the hero blue
## becomes the steel ACCENT, green calms to sage, ivory/muted follow the quiet
## text tokens. Swapping the alias migrates every colour use in a file
## deterministically; structural changes (pills, icons, footers) are still
## made in the file itself.

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

const BG: Color = BunkerDesign.BG
const SURFACE: Color = BunkerDesign.SURFACE
const SURFACE_ALT: Color = BunkerDesign.SURFACE_ALT
const IVORY: Color = Q.TEXT
const MUTED: Color = Q.MUTED
const BRASS: Color = BunkerDesign.BRASS
const BLUE: Color = Q.ACCENT
const BLUE_DARK: Color = Q.ACCENT_DIM
## "Good" only where it must stand apart from neutral; calm sage, not neon.
const GREEN: Color = Color("9fb39c")
const RED: Color = BunkerDesign.RED

static func icon(kind: String) -> Texture2D:
	return BunkerPanelStyle.icon(kind)

static func button(control: Button, accent: bool = false, danger: bool = false,
		compact: bool = false, borderless: bool = false) -> void:
	BunkerPanelStyle.button(control, accent, danger, compact, borderless)

static func icon_button(control: Button, kind: String, accent: bool = false,
		danger: bool = false, compact: bool = false, borderless: bool = false) -> void:
	BunkerPanelStyle.icon_button(control, kind, accent, danger, compact, borderless)

static func field(control: LineEdit) -> void:
	BunkerPanelStyle.field(control)

static func title(label: Label, size: int = 26) -> void:
	BunkerPanelStyle.title(label, size)
	label.add_theme_color_override("font_color", Q.TEXT)

static func muted(label: Label, size: int = 14) -> void:
	BunkerPanelStyle.muted(label, size)
	label.add_theme_color_override("font_color", Q.MUTED)
