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

enum Domain { WATER, POWER, NEUTRAL, FARMING }

## Shared corner radius for every panel in the project (Jul 2026 "rounded
## corners" pass) — Pause/GraphicsSettings already used 4 via
## build_centered_panel(); every hand-drawn panel now matches via
## draw_rounded_rect() below instead of plain square-cornered draw_rect().
const CORNER_RADIUS: float = 4.0

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
	var accent: Color   ## Jul 2026 — domain identity color, used ONLY for the
	                     ## top stripe now that bg/border/etc. are shared
	                     ## across all domains (see draw_domain_stripe below).


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
		Domain.FARMING:
			return _farming_theme()
		_:
			return _neutral_theme()


## Copied verbatim from WaterDispenserUI.gd's BG_COLOR..CRIT_COLOR (its
## OK_COLOR is blue, meaning "on target" for the receiving rate — same role
## `ok` plays here).
static func _water_theme() -> UITheme:
	## Jul 2026 — bg/border/header/text/dim/ok/warn/crit now identical to
	## POWER and NEUTRAL (Brannon's explicit call: "same UI... otherwise
	## exact same"). Only `accent` (used for the top stripe) still differs
	## by domain. The values below are literally NEUTRAL's, copied so this
	## function has no cross-function dependency.
	var t: UITheme = UITheme.new()
	t.bg     = Color(0.08, 0.08, 0.09, 0.97)
	t.border = Color(0.55, 0.58, 0.62, 0.70)
	t.header = Color(0.80, 0.82, 0.86, 1.00)
	t.text   = Color(0.85, 0.86, 0.88, 0.95)
	t.dim    = Color(0.50, 0.52, 0.55, 0.80)
	t.ok     = Color(0.35, 0.85, 1.00, 1.00)
	t.warn   = Color(1.00, 0.72, 0.10, 1.00)
	t.crit   = Color(1.00, 0.35, 0.30, 1.00)
	t.accent = Color(0.40, 0.75, 1.00, 1.00)   ## blue — water's stripe color
	return t


## Copied verbatim from PowerTerminalUI.gd's BG_COLOR..OK_COLOR.
static func _power_theme() -> UITheme:
	## Jul 2026 — bg/border/header/text/dim/ok/warn/crit now identical to
	## WATER and NEUTRAL (Brannon's explicit call: "same UI... otherwise
	## exact same"). Only `accent` (used for the top stripe) still differs
	## by domain.
	var t: UITheme = UITheme.new()
	t.bg     = Color(0.08, 0.08, 0.09, 0.97)
	t.border = Color(0.55, 0.58, 0.62, 0.70)
	t.header = Color(0.80, 0.82, 0.86, 1.00)
	t.text   = Color(0.85, 0.86, 0.88, 0.95)
	t.dim    = Color(0.50, 0.52, 0.55, 0.80)
	t.ok     = Color(0.35, 0.85, 1.00, 1.00)
	t.warn   = Color(1.00, 0.72, 0.10, 1.00)
	t.crit   = Color(1.00, 0.35, 0.30, 1.00)
	t.accent = Color(0.90, 0.80, 0.20, 1.00)   ## Jul 2026 — yellow (was green), power's stripe color
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
	t.accent = t.header   ## unused in practice — NEUTRAL panels (Pause/
	                       ## Settings) don't get a domain stripe — set for
	                       ## completeness so nothing reads a null Color.
	return t


## Jul 2026 — new domain for FarmingTrayUI (1x1 and 2x1 trays, one file
## handles both sizes). Same shared bg/border/header/text/dim/ok/warn/crit
## as every other domain; only `accent` (the stripe color) is unique —
## reusing the green POWER used before this pass moved to yellow.
static func _farming_theme() -> UITheme:
	var t: UITheme = UITheme.new()
	t.bg     = Color(0.08, 0.08, 0.09, 0.97)
	t.border = Color(0.55, 0.58, 0.62, 0.70)
	t.header = Color(0.80, 0.82, 0.86, 1.00)
	t.text   = Color(0.85, 0.86, 0.88, 0.95)
	t.dim    = Color(0.50, 0.52, 0.55, 0.80)
	t.ok     = Color(0.35, 0.85, 1.00, 1.00)
	t.warn   = Color(1.00, 0.72, 0.10, 1.00)
	t.crit   = Color(1.00, 0.35, 0.30, 1.00)
	t.accent = Color(0.38, 0.85, 0.40, 1.00)   ## green — farming's stripe color
	return t


# ─── Drawing primitives ──────────────────────────────────────────────────────
## Full-viewport dim backdrop behind a modal panel. `alpha` defaults to the
## value `WaterDispenserUI`/`WaterInfoUI` already use (0.60) — pass the
## caller's own existing value when migrating a file that used a different
## number (e.g. PowerTerminalUI's 0.65), since this is a refactor, not a
## silent value-unification pass.
static func draw_backdrop(canvas: CanvasItem, vp_size: Vector2, alpha: float = 0.60) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.0, 0.0, 0.0, alpha), true)


## Rounded background+border rect (Jul 2026 "rounded corners" pass) — the
## shared low-level primitive every hand-drawn panel now uses instead of a
## plain square-cornered `draw_rect()` pair. Godot's CanvasItem has no
## built-in rounded-rect draw call, so this builds a throwaway StyleBoxFlat
## and calls its own `.draw()` directly against the canvas — a standard
## Godot trick for getting StyleBox rendering inside immediate-mode `_draw()`.
static func draw_rounded_rect(canvas: CanvasItem, rect: Rect2, bg_color: Color,
		border_color: Color, border_width: float = 2.0, corner_radius: float = CORNER_RADIUS) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(int(round(border_width)))
	sb.set_corner_radius_all(int(round(corner_radius)))
	sb.draw(canvas.get_canvas_item(), rect)


## Panel background + border. Caller owns computing `rect` (this project's
## panels are all screen-centered via `(vp - PANEL_SIZE) * 0.5`, left to the
## caller since PANEL_W/PANEL_H differ per file).
static func draw_panel(canvas: CanvasItem, rect: Rect2, theme: UITheme, border_width: float = 2.0) -> void:
	draw_rounded_rect(canvas, rect, theme.bg, theme.border, border_width)


## Cached once, shared by every close button across the project — the icon
## only gets decoded from disk the first time it's needed.
static var _close_icon: Texture2D = null

static func _get_close_icon() -> Texture2D:
	if _close_icon == null:
		_close_icon = load("res://assets/icons/close_x.png")
	return _close_icon


## Draws the shared × close icon (Jul 2026 — replaces the old 2-line hand-
## drawn × everywhere it appeared). The source PNG is plain white with an
## alpha channel — a mask, not a fixed-color icon — so `modulate` tints it
## to whatever color the caller wants; every existing close button used the
## same light red `(1.0, 0.7, 0.7, 1.0)`, which is the default here so this
## is a pure shape swap, not a color change. Draws centered inside `rect`
## with a small inset margin so it doesn't crowd the button's own border.
static func draw_close_icon(canvas: CanvasItem, rect: Rect2, modulate: Color = Color(1.0, 0.7, 0.7, 1.0)) -> void:
	var icon: Texture2D = _get_close_icon()
	if icon == null:
		return
	var inset: float = 6.0
	var icon_rect: Rect2 = Rect2(
		rect.position + Vector2(inset, inset),
		rect.size - Vector2(inset * 2.0, inset * 2.0))
	canvas.draw_texture_rect(icon, icon_rect, false, modulate)


## Panel background + border. Caller owns computing `rect` (this project's
## panels are all screen-centered via `(vp - PANEL_SIZE) * 0.5`, left to the
## caller since PANEL_W/PANEL_H differ per file).
static func draw_panel(canvas: CanvasItem, rect: Rect2, theme: UITheme, border_width: float = 2.0) -> void:
	draw_rounded_rect(canvas, rect, theme.bg, theme.border, border_width)


## Draws the standard × close button at a panel's top-right corner and
## returns its hit-rect (same rect the caller should position its real
## `Button` node over, and/or hit-test manually) — mirrors
## `WaterDispenserUI.gd`'s current close-button drawing verbatim.
##
## Jul 2026 "top padding" pass: the Y offset moved from 10.0 to 16.0 (a
## uniform +6px applied identically to every panel's top row — title/name
## text, this close button, and PowerTerminalUI's "LOAD" readout — see the
## per-file edits in the same plan for the ones that don't route through
## this shared function). Jul 2026 "rounded corners" pass: now uses
## draw_rounded_rect() instead of a plain square draw_rect().
static func draw_close_button(canvas: CanvasItem, panel_rect: Rect2, theme: UITheme) -> Rect2:
	var close_rect: Rect2 = Rect2(
		panel_rect.position.x + panel_rect.size.x - 40.0,
		panel_rect.position.y + 16.0,
		30.0, 30.0)
	draw_rounded_rect(canvas, close_rect, Color(0.10, 0.06, 0.06, 0.90), theme.crit, 1.5)
	draw_close_icon(canvas, close_rect)
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

## ─── Shared Theme resource for real Control widgets (CheckBox/OptionButton/
## HSlider) inside settings-style panels, so they stop using Godot's
## default grey theme. Built once, applied via `_panel.theme = ...` so
## every child Control inherits it automatically.
static func settings_controls_theme() -> Theme:
	var theme: Theme = Theme.new()


	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.14, 0.16, 0.95)
	normal.border_color = Color(0.30, 0.30, 0.33, 0.85)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)


	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.20, 0.20, 0.23, 0.98)
	hover.border_color = Color(0.55, 0.55, 0.60, 1.0)


	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.10, 0.12, 0.98)


	theme.set_stylebox("normal", "CheckBox", normal)
	theme.set_stylebox("hover", "CheckBox", hover)
	theme.set_stylebox("pressed", "CheckBox", pressed)


	theme.set_stylebox("normal", "OptionButton", normal)
	theme.set_stylebox("hover", "OptionButton", hover)
	theme.set_stylebox("pressed", "OptionButton", pressed)


	var slider_bg: StyleBoxFlat = StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.08, 0.08, 0.09, 0.9)
	slider_bg.set_corner_radius_all(2)
	theme.set_stylebox("slider", "HSlider", slider_bg)


	var grabber_style: StyleBoxFlat = StyleBoxFlat.new()
	grabber_style.bg_color = Color(0.55, 0.58, 0.62, 1.0)
	grabber_style.set_corner_radius_all(6)
	theme.set_stylebox("grabber_area", "HSlider", grabber_style)


	return theme


## ─── Rugged/worn border helper (Jul 2026 "gritty bunker" pass) ──────────────
## Draws a hand-inked, slightly wobbly stroke along a circular arc instead of
## a perfectly smooth `draw_arc` line — used for the worn-metal border
## treatment on HUD ring/circle visuals (NeedsGauge, StatusEffectIcon). The
## jitter is a FIXED hash of each point's angle (not per-frame randomness),
## so the wobble is identical every redraw — no flicker, just reads as
## rough/hand-drawn rather than a clean vector circle. Keep `width` small
## (1.0-2.0) and `color` low-alpha near-black — this is meant to be subtle.
static func draw_rugged_arc(canvas: CanvasItem, center: Vector2, radius: float,
		start_angle: float, end_angle: float, color: Color, width: float,
		seed_offset: float = 0.0) -> void:
	var segments: int = 40
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var angle: float = lerp(start_angle, end_angle, t)
		var n: float = _rugged_hash(angle * 37.0 + seed_offset)
		var jitter: float = (n - 0.5) * (width * 1.6)
		var r: float = radius + jitter
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	canvas.draw_polyline(points, color, maxf(width * 0.4, 1.0), true)


## Same wobble treatment for a full closed circle (e.g. NeedsGauge's blank
## center, StatusEffectIcon's outer/inner edges). A tiny seam where the
## loop closes (angle 0 meets angle TAU) is expected and fine — it reads as
## part of the hand-inked imperfection, not a bug.
static func draw_rugged_circle(canvas: CanvasItem, center: Vector2, radius: float,
		color: Color, width: float, seed_offset: float = 0.0) -> void:
	draw_rugged_arc(canvas, center, radius, 0.0, TAU, color, width, seed_offset)


static func _rugged_hash(x: float) -> float:
	var v: float = sin(x * 12.9898) * 43758.5453
	return v - floor(v)


## ─── Domain identity stripe (Jul 2026 "power + water unification" pass) ────
## A thin colored bar across the top of a panel, inset from the true top
## edge by `gap` — the ONLY visual difference left between domains once a
## panel is on the shared palette (see _water_theme/_power_theme above).

## For hand-drawn immediate-mode panels (PowerTerminalUI, PowerPriorityUI,
## GeneratorInspectUI, WaterInfoUI, WaterDispenserUI) — call this right
## after drawing the panel's background+border, passing the same
## `panel_rect` used for those.
static func draw_domain_stripe(canvas: CanvasItem, panel_rect: Rect2, accent: Color,
		gap: float = 6.0, height: float = 4.0) -> void:
	var stripe_rect: Rect2 = Rect2(
		panel_rect.position.x,
		panel_rect.position.y + gap,
		panel_rect.size.x,
		height)
	canvas.draw_rect(stripe_rect, accent, true)


## For real Control-node panels (ZoneCustomizeUI) — builds and returns a
## ColorRect the caller adds as a child of the Panel, positioned relative
## to the panel's own top-left corner (NOT the screen), so it moves with
## the panel automatically.
static func add_domain_stripe(panel_width: float, accent: Color,
		gap: float = 6.0, height: float = 4.0) -> ColorRect:
	var stripe: ColorRect = ColorRect.new()
	stripe.color = accent
	stripe.position = Vector2(0.0, gap)
	stripe.size = Vector2(panel_width, height)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return stripe


## ─── Real Control-node menu builders (Jul 2026 "unify every menu" pass) ────
## For panels built from real Control/Container node trees (PauseMenuUI,
## GraphicsSettingsPanel, and any future menu built the same way) — distinct
## from the hand-drawn `_draw()` primitives above, which are for the older
## immediate-mode panels (PowerTerminalUI, etc., not yet migrated).

## Shared font-size scale — replaces each menu file picking its own numbers
## for what should be the same 3 roles everywhere.
const FONT_SIZE_TITLE:   int = 20   ## panel title ("PAUSED", "GRAPHICS SETTINGS")
const FONT_SIZE_SECTION: int = 11   ## section divider labels ("Save", "DISPLAY", ...)
const FONT_SIZE_BODY:    int = 13   ## buttons, row labels, dialog text

## Shared modal width for paired menus (Jul 2026 — PauseMenuUI was 360,
## GraphicsSettingsPanel was 340; unified so panels that open from one
## another read as the same system).
const MENU_PANEL_W: float = 380.0


## Builds the standard blurred full-screen backdrop used by every modal menu
## panel — same shader + dim-color-fallback pattern `PauseMenuUI`/
## `GraphicsSettingsPanel` were each separately duplicating. Caller still
## owns `add_child()`-ing the result and wiring up its `gui_input` if it
## wants click-outside-to-close.
static func build_modal_backdrop(alpha: float = 0.55) -> ColorRect:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.color = Color(0.0, 0.0, 0.0, alpha)
	var blur_shader: Shader = load("res://assets/shaders/pause_blur.gdshader")
	if blur_shader != null:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = blur_shader
		backdrop.material = mat
	return backdrop


## Builds a Panel that is ALWAYS correctly centered regardless of what gets
## added to it afterward — the fix for the "off-center panel" bug class.
## Sets a FIXED width/height box via explicit offsets computed up front,
## instead of relying on Godot to recompute PRESET_CENTER's offsets from
## whatever size the panel happens to have at the moment this is called
## (which is wrong if content is still being added). Any future panel that
## needs to be screen-centered should use this instead of calling
## `set_anchors_preset(PRESET_CENTER)` directly.
static func build_centered_panel(width: float, height: float, theme: UITheme) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = Vector2(width, height)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = -width * 0.5
	panel.offset_right  =  width * 0.5
	panel.offset_top    = -height * 0.5
	panel.offset_bottom =  height * 0.5
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = theme.bg
	style.border_color = theme.border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	return panel


## Shared 3-state button factory for real Control-node menus — distinct
## from `button_stylebox()` above (which only builds one StyleBoxFlat at a
## time for hand-drawn panels). Used by PauseMenuUI/GraphicsSettingsPanel
## so every button in both menus looks and behaves identically, including
## actually using the shared project font (PauseMenuUI's buttons never did
## before this pass).
static func make_button(text: String, cb: Callable, min_height: float = 32.0) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0.0, min_height)
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	btn.add_theme_font_override("font", font())

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = Color(0.14, 0.14, 0.16, 0.95)
	style.border_color = Color(0.30, 0.30, 0.33, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", style)

	var hover: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover.bg_color     = Color(0.20, 0.20, 0.23, 0.98)
	hover.border_color = Color(0.55, 0.55, 0.60, 1.0)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.10, 0.10, 0.12, 0.98)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.pressed.connect(cb)
	return btn


## Shared section-divider label (dim small text used to break a menu into
## groups — "Save"/"Load" in PauseMenuUI, "DISPLAY"/"RENDERING"/etc. in
## GraphicsSettingsPanel) and shared plain row-label factory (for e.g.
## GraphicsSettingsPanel's "Window Mode"/"VSync"/etc. labels, which
## previously had no font/color override at all and rendered in Godot's
## raw default theme).
static func make_section_label(text: String, theme: UITheme) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FONT_SIZE_SECTION)
	lbl.add_theme_color_override("font_color", theme.dim)
	lbl.add_theme_font_override("font", font())
	return lbl

static func make_row_label(text: String, theme: UITheme) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", FONT_SIZE_BODY)
	lbl.add_theme_color_override("font_color", theme.text)
	lbl.add_theme_font_override("font", font())
	return lbl
