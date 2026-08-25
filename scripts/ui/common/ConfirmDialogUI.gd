extends CanvasLayer
class_name ConfirmDialogUI
## ConfirmDialogUI.gd
## ─────────────────────────────────────────────────────────────────────────────
## Reusable Yes/No confirmation dialog (Jul 2026, Purifier QoL plan item 3) —
## visually modeled on BuildModeHUD._draw_dig_confirm()'s "EXPAND BUNKER"
## dialog (same full-screen dim, centered rounded panel, kiwi-green border,
## title/subtitle lines, YES/NO button color treatment — reuses those exact
## Color(...) literals so it reads as the same dialog family), but
## PARAMETERIZED (title/subtitle passed to open(), not hardcoded) and usable
## during NORMAL gameplay, not just build mode.
##
## Deliberately a NEW, separate component rather than bending
## BuildModeHUD.gd to work outside its own mode — that file's dig-confirm is
## a real, working, but hardcoded dialog, scoped to build mode
## (_unhandled_input() bails if not visible, and the HUD is only visible
## during build mode). Migrating BuildModeHUD's own dig-confirm to use this
## shared component instead is an explicitly OUT-OF-SCOPE follow-up idea for
## this plan, not done here — flagged in docs/systems/water/README.md so a
## future session doesn't assume that cleanup already happened.
##
## Usage — same lazy-instantiate-on-demand pattern WaterPurifier already
## uses for its own _info_ui:
##     var dlg := ConfirmDialogUI.new()
##     get_tree().get_root().add_child(dlg)
##     dlg.open("REPLACE WITH LOWER-QUALITY FILTER?", "80% -> 40%")
##     dlg.confirmed.connect(func(): ...; dlg.queue_free())
##     dlg.cancelled.connect(dlg.queue_free)
##
## Signals:
##   confirmed() — YES pressed
##   cancelled() — NO pressed, or ESC

signal confirmed()
signal cancelled()

## Sourced from BunkerTheme in _load_theme(); these defaults are the
## fallbacks if the theme resource is missing.
var PANEL_W: float = 360.0
var PANEL_H: float = 140.0
var BTN_W:   float = 110.0
var BTN_H:   float = 38.0
var BTN_GAP: float = 16.0   ## spacing between YES and NO
var CR:      float = 4.0   ## UIKit.CORNER_RADIUS default — matches every other panel's rounding
var BACKDROP_ALPHA: float = 0.55   ## backdrop dim (stored permille in theme, /1000)

## UI colours — NEUTRAL domain (UIKit convention pass, replacing the old
## one-off kiwi-green/amber scheme). Button bg colors stay green/red for
## affirmative/destructive intent (same convention GeneratorInspectUI's
## START/SHUT DOWN button already uses) — only the accent/text/panel
## tokens move onto UIKit's shared palette. NOTE: BuildModeHUD's own
## dig-confirm dialog still hand-rolls the OLD kiwi-green scheme this file
## used to share — migrating it is a separate, not-yet-done follow-up.
var BG_COLOR:     Color = Color(0.08, 0.08, 0.09, 0.97)
var BORDER_COLOR: Color = Color(0.55, 0.58, 0.62, 0.70)
var HEADER_COLOR: Color = Color(0.80, 0.82, 0.86, 1.00)
var DIM_COLOR:    Color = Color(0.50, 0.52, 0.55, 0.80)
var OK_COLOR:     Color = Color(0.35, 0.85, 1.00, 1.00)
var CRIT_COLOR:   Color = Color(1.00, 0.35, 0.30, 1.00)
var YES_BG:       Color = Color(0.06, 0.30, 0.12, 1.0)
var NO_BG:        Color = Color(0.42, 0.08, 0.06, 1.0)

var _canvas: Control = null
var _font: Font = null
var _title: String = ""
var _subtitle: String = ""
var _is_open: bool = false
var _yes_rect: Rect2 = Rect2()
var _no_rect:  Rect2 = Rect2()
## Controller YES/NO selection (Aug 2026): true = YES, false = NO. d-pad
## L/R toggles, A confirms. Reset to YES on open.
var _selection: bool = true

## Render layer (Aug 2026). Defaults to 70 (above every other panel). Callers
## that open this dialog from another UI raise it above THEMSELVES (e.g.
## PauseMenuUI sets 210, GraphicsSettingsPanel sets 215) so it stacks on top.
@export var stacking_layer: int = 70

## Pulls every palette + geometry value from BunkerTheme so the theme is the
## single source of truth (tweak there, this dialog follows).
func _load_theme() -> void:
	BG_COLOR = UIKit.theme_color("UI", "bg", Color(0.08, 0.08, 0.09, 0.97))
	BORDER_COLOR = UIKit.theme_color("UI", "border", Color(0.55, 0.58, 0.62, 0.70))
	HEADER_COLOR = UIKit.theme_color("UI", "header", Color(0.80, 0.82, 0.86, 1.00))
	DIM_COLOR = UIKit.theme_color("UI", "dim", Color(0.50, 0.52, 0.55, 0.80))
	OK_COLOR = UIKit.theme_color("UI", "ok", Color(0.35, 0.85, 1.00, 1.00))
	CRIT_COLOR = UIKit.theme_color("UI", "crit", Color(1.00, 0.35, 0.30, 1.00))
	YES_BG = UIKit.theme_color("ConfirmDialog", "yes_bg", Color(0.06, 0.30, 0.12, 1.0))
	NO_BG = UIKit.theme_color("ConfirmDialog", "no_bg", Color(0.42, 0.08, 0.06, 1.0))
	PANEL_W = float(UIKit.theme_constant("ConfirmDialog", "panel_w", 360))
	PANEL_H = float(UIKit.theme_constant("ConfirmDialog", "panel_h", 140))
	BTN_W = float(UIKit.theme_constant("ConfirmDialog", "btn_w", 110))
	BTN_H = float(UIKit.theme_constant("ConfirmDialog", "btn_h", 38))
	BTN_GAP = float(UIKit.theme_constant("ConfirmDialog", "btn_gap", 16))
	CR = float(UIKit.theme_constant("ConfirmDialog", "corner_radius", 4))
	BACKDROP_ALPHA = float(UIKit.theme_constant("ConfirmDialog", "backdrop_alpha_permille", 550)) / 1000.0

func _ready() -> void:
	_load_theme()
	layer   = stacking_layer
	visible = false
	## Controller navigation (Aug 2026) — see
	## scripts/ui/common/ControllerUINavigation.gd. close_on_cancel=false:
	## B is handled in _unhandled_input so it emits `cancelled` — the nav's
	## own B-close would only hide the panel, dropping the signal. d-pad
	## falls through too (this is a hand-drawn panel with no focusables).
	var controller_nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	controller_nav.ui_root = self
	controller_nav.close_on_cancel = false
	add_child(controller_nav)

	_font = UIKit.font()   ## shared cached font (was a per-instance load)
	if _font == null:
		_font = ThemeDB.fallback_font

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.name = "ConfirmDialogCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

func open(title: String, subtitle: String) -> void:
	_title     = title
	_subtitle  = subtitle
	_is_open   = true
	_selection = true   ## controller selection defaults to YES
	visible    = true
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false

func is_open() -> bool:
	return _is_open

func _confirm() -> void:
	close()
	confirmed.emit()

func _cancel() -> void:
	close()
	cancelled.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position
		if _yes_rect.has_point(pos):
			_confirm()
			get_viewport().set_input_as_handled()
			return
		elif _no_rect.has_point(pos):
			_cancel()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel()
		get_viewport().set_input_as_handled()
		return
	## Controller (Aug 2026): d-pad L/R toggles the YES/NO selection, A
	## confirms it, B cancels (= NO). The nav's B-close is disabled
	## (close_on_cancel=false) so B reaches this handler and emits cancelled.
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
				_selection = not _selection
				_canvas.queue_redraw()
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_A:
				_confirm() if _selection else _cancel()
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_B:
				_cancel()
				get_viewport().set_input_as_handled()
				return
	## Eat all other input while open — same "intercept everything" behavior
	## as BuildModeHUD's own dig-confirm block.
	get_viewport().set_input_as_handled()

func _on_draw() -> void:
	if not _is_open:
		return

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var px: float = (vp_size.x - PANEL_W) * 0.5
	var py: float = (vp_size.y - PANEL_H) * 0.5
	var panel_rect: Rect2 = Rect2(px, py, PANEL_W, PANEL_H)

	## Full-screen dim backdrop — shared UIKit primitive (alpha 0.55
	## preserved from the original value, per UIKit.draw_backdrop's own
	## "pass the caller's existing value when migrating" guidance).
	UIKit.draw_backdrop(_canvas, vp_size, BACKDROP_ALPHA)

	## Panel background + border — shared UIKit primitive/palette, replaces
	## the old hand-rolled _draw_rounded()/_draw_rounded_outline() + kiwi-
	## green literals.
	UIKit.draw_rounded_rect(_canvas, panel_rect, BG_COLOR, BORDER_COLOR, 2.0, CR)

	## Title
	var tsz: Vector2 = _font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	_canvas.draw_string(_font,
		Vector2(px + PANEL_W * 0.5 - tsz.x * 0.5, py + 28.0),
		_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, HEADER_COLOR)

	## Subtitle
	var ssz: Vector2 = _font.get_string_size(_subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	_canvas.draw_string(_font,
		Vector2(px + PANEL_W * 0.5 - ssz.x * 0.5, py + 52.0),
		_subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM_COLOR)

	## YES button
	var total_btns_w: float = BTN_W * 2.0 + BTN_GAP
	var yes_x: float = px + (PANEL_W - total_btns_w) * 0.5
	var btn_y: float = py + PANEL_H - BTN_H - 18.0
	_yes_rect = Rect2(yes_x, btn_y, BTN_W, BTN_H)
	## Green bg / OK_COLOR accent — same affirmative-action pattern
	## GeneratorInspectUI's START button already uses.
	UIKit.draw_rounded_rect(_canvas, _yes_rect, YES_BG, OK_COLOR, 1.5, 6.0)
	var yes_lbl: String = "YES"
	var ylsz: Vector2 = _font.get_string_size(yes_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	_canvas.draw_string(_font,
		Vector2(yes_x + BTN_W * 0.5 - ylsz.x * 0.5, btn_y + BTN_H * 0.5 + 5.0),
		yes_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, OK_COLOR)

	## NO button
	var no_x: float = yes_x + BTN_W + BTN_GAP
	_no_rect = Rect2(no_x, btn_y, BTN_W, BTN_H)
	## Red bg / CRIT_COLOR accent — same destructive-action pattern
	## GeneratorInspectUI's SHUT DOWN button already uses.
	UIKit.draw_rounded_rect(_canvas, _no_rect, NO_BG, CRIT_COLOR, 1.5, 6.0)
	var no_lbl: String = "NO"
	var nlsz: Vector2 = _font.get_string_size(no_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	_canvas.draw_string(_font,
		Vector2(no_x + BTN_W * 0.5 - nlsz.x * 0.5, btn_y + BTN_H * 0.5 + 5.0),
		no_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CRIT_COLOR)

	## Controller selection outline (Aug 2026) — white ring on the d-pad
	## selected button (YES by default), so A confirms exactly what's lit.
	if InputMode.is_controller():
		var sel_rect: Rect2 = _yes_rect if _selection else _no_rect
		UIKit.draw_rounded_rect(_canvas, sel_rect, Color(0, 0, 0, 0),
			Color(1, 1, 1, 0.92), 2.5, 6.0)

## Rounded-rect drawing now goes through UIKit.draw_rounded_rect() (see
## _on_draw() above) — the old hand-rolled _draw_rounded()/
## _draw_rounded_outline()/_arc() helpers this file used to carry are gone.
