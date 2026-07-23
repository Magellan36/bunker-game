class_name UIKit
extends RefCounted
## UIKit.gd
## ─────────────────────────────────────────────────────────────────────────────
## Shared UI kit (Jul 2026, "UI Kit + Central Notification System" plan,
## Part 1). Extracted from `WaterDispenserUI.gd` (the confirmed style basis)
## and `PowerTerminalUI.gd` (independently duplicated the same constant
## NAMES with a green palette instead of blue) — this file centralizes the
## structural tokens (colors/fonts) and canvas-draw drawing primitives every
## panel in this project already re-implements per file.
##
## Pure static-style helper (`RefCounted`, all `static func`s, no instance
## state) — matches how `WaterQualityColor.gd` is already correctly scoped
## for exactly this kind of shared-but-stateless logic. Not a manager, no
## scene-tree lifecycle, no autoload registration.
##
## Structural sharing, per-domain color: every migrated panel becomes
## structurally identical (panel shape, font, spacing, bar/button treatment)
## — WATER stays blue, POWER stays green, everything else (NEUTRAL) gets a
## third accent. Water/power theme values below are copied VERBATIM from
## `WaterDispenserUI.gd` / `PowerTerminalUI.gd`'s existing constants — this
## migration is a refactor (identical look), not a redesign. The NEUTRAL
## theme is genuinely new (no existing precedent to copy) — signed off by
## Brannon per the plan's §1.3 recommended default.
##
## Usage (see `WaterDispenserUI.gd` for the reference migration):
##     var theme: UIKit.UITheme = UIKit.theme_for(UIKit.Domain.WATER)
##     UIKit.draw_panel(_canvas, panel_rect, theme)
##     var close_rect: Rect2 = UIKit.draw_close_button(_canvas, panel_rect, theme)

enum Domain { WATER, POWER, NEUTRAL }

## Plain data holder for one domain's palette. Not a Resource/Node — just a
## bag of Colors passed around by value at draw time.
class UITheme:
	var bg:     Color
	var border: Color
	var header: Color
	var text:   Color
	var dim:    Color
	var ok:     Color
	var warn:   Color
	var crit:   Color


# ─── Shared font (Jul 2026: replaces ~20 independent load() calls of the
## exact same file scattered across every UI script) ─────────────────────────
static var _font: Font = null

static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


# ─── Domain themes ───────────────────────────────────────────────────────────
static func theme_for(domain: Domain) -> UITheme:
	match domain:
		Domain.WATER:
			return _water_theme()
		Domain.POWER:
			return _power_theme()
		_:
			return _neutral_theme()


## Copied verbatim from WaterDispenserUI.gd's BG_COLOR..CRIT_COLOR (its
## OK_COLOR is blue, meaning "on target" for the receiving rate — same role
## `ok` plays here).
static func _water_theme() -> UITheme:
	var t: UITheme = UITheme.new()
	t.bg     = Color(0.06, 0.08, 0.10, 0.97)
	t.border = Color(0.35, 0.70, 0.95, 0.80)
	t.header = Color(0.40, 0.75, 1.00, 1.00)
	t.text   = Color(0.85, 0.92, 0.97, 0.95)
	t.dim    = Color(0.50, 0.58, 0.62, 0.80)
	t.ok     = Color(0.35, 0.85, 1.00, 1.00)
	t.warn   = Color(1.00, 0.72, 0.10, 1.00)
	t.crit   = Color(1.00, 0.35, 0.30, 1.00)
	return t


## Copied verbatim from PowerTerminalUI.gd's BG_COLOR..OK_COLOR.
static func _power_theme() -> UITheme:
	var t: UITheme = UITheme.new()
	t.bg     = Color(0.04, 0.07, 0.04, 0.97)
	t.border = Color(0.28, 0.85, 0.32, 0.80)
	t.header = Color(0.22, 0.75, 0.28, 1.00)
	t.text   = Color(0.80, 0.95, 0.82, 0.95)
	t.dim    = Color(0.45, 0.55, 0.45, 0.85)
	t.ok     = Color(0.30, 1.00, 0.45, 1.00)
	t.warn   = Color(1.00, 0.72, 0.10, 1.00)
	t.crit   = Color(1.00, 0.25, 0.18, 1.00)
	return t


## New theme, no existing precedent — proposed default from the plan's
## §1.3, signed off by Brannon before any NEUTRAL-domain file is migrated.
## Warm steel-gray/silver, distinct from both blue (water) and green
## (power). Status colors (ok/warn/crit) intentionally reuse the same hues
## as water/power — "status" should read the same regardless of which
## panel you're looking at; only identity/border/header vary by domain.
static func _neutral_theme() -> UITheme:
	var t: UITheme = UITheme.new()
	t.bg     = Color(0.08, 0.08, 0.09, 0.97)
	t.border = Color(0.55, 0.58, 0.62, 0.70)
	t.header = Color(0.80, 0.82, 0.86, 1.00)
	t.text   = Color(0.85, 0.86, 0.88, 0.95)
	t.dim    = Color(0.50, 0.52, 0.55, 0.80)
	t.ok     = Color(0.35, 0.85, 1.00, 1.00)
	t.warn   = Color(1.00, 0.72, 0.10, 1.00)
	t.crit   = Color(1.00, 0.35, 0.30, 1.00)
	return t


# ─── Drawing primitives ──────────────────────────────────────────────────────
## Full-viewport dim backdrop behind a modal panel. `alpha` defaults to the
## value `WaterDispenserUI`/`WaterInfoUI` already use (0.60) — pass the
## caller's own existing value when migrating a file that used a different
## number (e.g. PowerTerminalUI's 0.65), since this is a refactor, not a
## silent value-unification pass.
static func draw_backdrop(canvas: CanvasItem, vp_size: Vector2, alpha: float = 0.60) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.0, 0.0, 0.0, alpha), true)


## Panel background + border. Caller owns computing `rect` (this project's
## panels are all screen-centered via `(vp - PANEL_SIZE) * 0.5`, left to the
## caller since PANEL_W/PANEL_H differ per file).
static func draw_panel(canvas: CanvasItem, rect: Rect2, theme: UITheme, border_width: float = 2.0) -> void:
	canvas.draw_rect(rect, theme.bg, true)
	canvas.draw_rect(rect, theme.border, false, border_width)


## Draws the standard × close button at a panel's top-right corner and
## returns its hit-rect (same rect the caller should position its real
## `Button` node over, and/or hit-test manually) — mirrors
## `WaterDispenserUI.gd`'s current close-button drawing verbatim.
static func draw_close_button(canvas: CanvasItem, panel_rect: Rect2, theme: UITheme) -> Rect2:
	var close_rect: Rect2 = Rect2(
		panel_rect.position.x + panel_rect.size.x - 40.0,
		panel_rect.position.y + 10.0,
		30.0, 30.0)
	canvas.draw_rect(close_rect, Color(0.10, 0.06, 0.06, 0.90), true)
	canvas.draw_rect(close_rect, theme.crit, false, 1.5)
	var cp: Vector2 = close_rect.position
	var cs: Vector2 = close_rect.size
	var x_col: Color = Color(1.0, 0.7, 0.7, 1.0)
	canvas.draw_line(cp + Vector2(6, 6), cp + cs - Vector2(6, 6), x_col, 2.0)
	canvas.draw_line(cp + Vector2(cs.x - 6, 6), cp + Vector2(6, cs.y - 6), x_col, 2.0)
	return close_rect


## Labeled progress bar (background groove + colored fill + border) — the
## exact "visual fill display" pattern already reused for the dispenser
## tank storage bar and, per the purifier plans, filter quality.
## `fill_color_override` (alpha 0 = unset) lets callers use a value other
## than `theme.ok` (e.g. quality-graduated red/yellow/green) without this
## primitive needing to know about that logic itself.
static func draw_bar(canvas: CanvasItem, rect: Rect2, fill_pct: float, theme: UITheme,
		fill_color_override: Color = Color(0, 0, 0, 0)) -> void:
	var frac: float = clampf(fill_pct, 0.0, 1.0)
	canvas.draw_rect(rect, Color(0.08, 0.10, 0.12, 0.85), true)
	if frac > 0.0:
		var fill_col: Color = theme.ok if fill_color_override.a <= 0.0 else fill_color_override
		var fill_rect: Rect2 = Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y))
		canvas.draw_rect(fill_rect, Color(fill_col.r, fill_col.g, fill_col.b, 0.85), true)
	canvas.draw_rect(rect, Color(theme.border.r, theme.border.g, theme.border.b, 0.55), false, 1.0)


## Header title text + the divider line every panel draws directly below it.
static func draw_header(canvas: CanvasItem, pos: Vector2, text: String, theme: UITheme,
		divider_width: float = 0.0, size: int = 16) -> void:
	draw_shadowed_text(canvas, pos, text, size, theme.header)
	if divider_width > 0.0:
		var line_y: float = pos.y + 28.0
		canvas.draw_line(Vector2(pos.x, line_y), Vector2(pos.x + divider_width, line_y),
			Color(theme.border.r, theme.border.g, theme.border.b, 0.45), 1.0)


## Text with a drop-shadow — every panel's `_draw_str()` helper does exactly
## this (shadow copy offset (1,1) at 0.65 alpha black, then the real text).
static func draw_shadowed_text(canvas: CanvasItem, pos: Vector2, text: String, size: int, color: Color) -> void:
	canvas.draw_string(font(), pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.65))
	canvas.draw_string(font(), pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## StyleBoxFlat for the few places using real Control buttons (e.g.
## WaterDispenserUI's priority ◄►arrows / PowerPriorityUI's equivalents).
static func button_stylebox(theme: UITheme, enabled: bool, hover: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	if hover and enabled:
		sb.bg_color = Color(0.14, 0.20, 0.24, 1.0)
	else:
		sb.bg_color = Color(0.08, 0.11, 0.13, 1.0) if enabled else Color(0.08, 0.09, 0.10, 1.0)
	sb.border_color = Color(theme.border.r, theme.border.g, theme.border.b, 0.55 if enabled else 0.2)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	return sb
