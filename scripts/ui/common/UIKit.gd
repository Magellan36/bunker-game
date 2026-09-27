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
##
## ─── Which style to use for a new panel ─────────────────────────────────────
## Hand-drawn (_draw() + this file's draw_* primitives): the default for any
## panel that's just showing info + simple buttons — GeneratorInspectUI,
## ConfirmDialogUI, BatteryBank are the reference examples.
## Real Control/Panel/Button tree (this file's build_*/make_* helpers):
## required whenever the panel needs text INPUT (LineEdit), SCROLLING
## (ScrollContainer), or focus-based NAVIGATION (controller support via
## ControllerUINavigation.gd needs real focusable Controls to move between)
## — PauseMenuUI, GraphicsSettingsPanel, NPCTalkMenuUI, ZoneCustomizeUI are
## the reference examples. Don't hand-roll scrolling/focus in a hand-drawn
## panel — use a real Control tree instead. (Real-Control panels use
## make_close_button(); hand-drawn ones use draw_close_button().)

enum Domain { WATER, POWER, NEUTRAL, FARMING, INVENTORY }

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


# ─── BunkerTheme (the single source of truth for every panel's design tokens) ─
## All code-drawn panels load their palette + geometry from
## `assets/fonts/BunkerTheme.tres` via these helpers. `fallback` values keep a
## panel working even if the theme resource is missing or a key is absent.
static var _bunker_theme: Theme = null

static func bunker_theme() -> Theme:
	if _bunker_theme == null:
		_bunker_theme = load("res://assets/fonts/BunkerTheme.tres") as Theme
	return _bunker_theme

static func theme_color(type: String, name: String, fallback: Color) -> Color:
	var t := bunker_theme()
	if t == null:
		return fallback
	return t.get_color(name, type)

static func theme_constant(type: String, name: String, fallback: int) -> int:
	var t := bunker_theme()
	if t == null:
		return fallback
	return t.get_constant(name, type)

static func theme_font_size(type: String, name: String, fallback: int) -> int:
	var t := bunker_theme()
	if t == null:
		return fallback
	return t.get_font_size(name, type)


# ─── Domain themes ───────────────────────────────────────────────────────────
static func theme_for(domain: Domain) -> UITheme:
	match domain:
		Domain.WATER:
			return _water_theme()
		Domain.POWER:
			return _power_theme()
		Domain.FARMING:
			return _farming_theme()
		Domain.INVENTORY:
			return _inventory_theme()
		_:
			return _neutral_theme()


## Shared bg/border/header/text/dim/ok/warn/crit — now read from
## BunkerTheme's UI section (the single source of truth). Only `accent`
## (the domain stripe color) differs per domain.
static func _shared_theme() -> UITheme:
	var t: UITheme = UITheme.new()
	t.bg     = theme_color("UI", "bg", Color(0.08, 0.08, 0.09, 0.97))
	t.border = theme_color("UI", "border", Color(0.55, 0.58, 0.62, 0.70))
	t.header = theme_color("UI", "header", Color(0.80, 0.82, 0.86, 1.00))
	t.text   = theme_color("UI", "text", Color(0.85, 0.86, 0.88, 0.95))
	t.dim    = theme_color("UI", "dim", Color(0.50, 0.52, 0.55, 0.80))
	t.ok     = theme_color("UI", "ok", Color(0.35, 0.85, 1.00, 1.00))
	t.warn   = theme_color("UI", "warn", Color(1.00, 0.72, 0.10, 1.00))
	t.crit   = theme_color("UI", "crit", Color(1.00, 0.35, 0.30, 1.00))
	return t


static func _water_theme() -> UITheme:
	var t := _shared_theme()
	t.accent = theme_color("UI", "water_accent", Color(0.40, 0.75, 1.00, 1.00))
	return t


static func _power_theme() -> UITheme:
	var t := _shared_theme()
	t.accent = theme_color("UI", "power_accent", Color(0.90, 0.80, 0.20, 1.00))
	return t


static func _inventory_theme() -> UITheme:
	var t: UITheme = _shared_theme()
	t.accent = theme_color("UI", "inventory_accent", Color(0.86, 0.67, 0.36, 1.00))
	return t


## Warm steel-gray/silver NEUTRAL accent (same as header — no stripe drawn).
static func _neutral_theme() -> UITheme:
	var t := _shared_theme()
	t.accent = theme_color("UI", "neutral_accent", Color(0.80, 0.82, 0.86, 1.00))
	return t


## Farming domain — green stripe.
static func _farming_theme() -> UITheme:
	var t := _shared_theme()
	t.accent = theme_color("UI", "farming_accent", Color(0.38, 0.85, 0.40, 1.00))
	return t


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


## ─── Rugged/worn border helper (Jul 2026 "gritty bunker" pass) ──────────────
## Restored Sep 2026 at Brannon's request (HUD ruggedness).
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
