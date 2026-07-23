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

const PANEL_W: float = 360.0
const PANEL_H: float = 140.0
const BTN_W:   float = 110.0
const BTN_H:   float = 38.0
const CR:      float = 8.0

var _canvas: Control = null
var _font: Font = null
var _title: String = ""
var _subtitle: String = ""
var _is_open: bool = false
var _yes_rect: Rect2 = Rect2()
var _no_rect:  Rect2 = Rect2()

func _ready() -> void:
	layer   = 70   ## above every other panel (WaterInfoUI/WaterDispenserUI use layer 60)
	visible = false

	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.name = "ConfirmDialogCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

func open(title: String, subtitle: String) -> void:
	_title    = title
	_subtitle = subtitle
	_is_open  = true
	visible   = true
	## Standing convention (July 2026) — see UIFade.gd.
	UIFade.fade_in(_canvas)
	_canvas.queue_redraw()

func close() -> void:
	_is_open = false
	visible  = false

func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = event.position
		if _yes_rect.has_point(pos):
			close()
			confirmed.emit()
			get_viewport().set_input_as_handled()
			return
		elif _no_rect.has_point(pos):
			close()
			cancelled.emit()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		cancelled.emit()
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

	## Dark semi-transparent full-screen dim — same treatment as _draw_dig_confirm().
	_canvas.draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.0, 0.0, 0.0, 0.55), true)

	## Panel background + kiwi-green border (same literals as _draw_dig_confirm()).
	_draw_rounded(panel_rect, CR, Color(0.08, 0.10, 0.07, 0.96))
	_draw_rounded_outline(panel_rect, CR, Color(0.42, 0.87, 0.15, 0.80), 2.0)

	## Title
	var tsz: Vector2 = _font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	_canvas.draw_string(_font,
		Vector2(px + PANEL_W * 0.5 - tsz.x * 0.5, py + 28.0),
		_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.52, 0.97, 0.20, 1.0))

	## Subtitle
	var ssz: Vector2 = _font.get_string_size(_subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	_canvas.draw_string(_font,
		Vector2(px + PANEL_W * 0.5 - ssz.x * 0.5, py + 52.0),
		_subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.75, 0.30, 1.0))

	## YES button
	var gap: float = 16.0
	var total_btns_w: float = BTN_W * 2.0 + gap
	var yes_x: float = px + (PANEL_W - total_btns_w) * 0.5
	var btn_y: float = py + PANEL_H - BTN_H - 18.0
	_yes_rect = Rect2(yes_x, btn_y, BTN_W, BTN_H)
	_draw_rounded(_yes_rect, 6.0, Color(0.12, 0.30, 0.08, 0.90))
	_draw_rounded_outline(_yes_rect, 6.0, Color(0.42, 0.87, 0.15, 0.90), 1.5)
	var yes_lbl: String = "YES"
	var ylsz: Vector2 = _font.get_string_size(yes_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	_canvas.draw_string(_font,
		Vector2(yes_x + BTN_W * 0.5 - ylsz.x * 0.5, btn_y + BTN_H * 0.5 + 5.0),
		yes_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.80, 1.0, 0.60, 1.0))

	## NO button
	var no_x: float = yes_x + BTN_W + gap
	_no_rect = Rect2(no_x, btn_y, BTN_W, BTN_H)
	_draw_rounded(_no_rect, 6.0, Color(0.25, 0.08, 0.08, 0.90))
	_draw_rounded_outline(_no_rect, 6.0, Color(0.85, 0.22, 0.18, 0.80), 1.5)
	var no_lbl: String = "NO"
	var nlsz: Vector2 = _font.get_string_size(no_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	_canvas.draw_string(_font,
		Vector2(no_x + BTN_W * 0.5 - nlsz.x * 0.5, btn_y + BTN_H * 0.5 + 5.0),
		no_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.75, 0.70, 1.0))

# ─── Rounded-rect draw helpers (copied verbatim from BuildModeHUD.gd's own,
# same math, just bound to this dialog's own _canvas instead of taking a
# CanvasItem param — this component only ever draws to one) ──────────────────
func _draw_rounded(rect: Rect2, cr: float, col: Color) -> void:
	_canvas.draw_rect(Rect2(rect.position + Vector2(cr, 0), Vector2(rect.size.x - cr * 2, rect.size.y)), col, true)
	_canvas.draw_rect(Rect2(rect.position + Vector2(0, cr), Vector2(rect.size.x, rect.size.y - cr * 2)), col, true)
	_canvas.draw_circle(rect.position + Vector2(cr, cr), cr, col)
	_canvas.draw_circle(rect.position + Vector2(rect.size.x - cr, cr), cr, col)
	_canvas.draw_circle(rect.position + Vector2(cr, rect.size.y - cr), cr, col)
	_canvas.draw_circle(rect.position + Vector2(rect.size.x - cr, rect.size.y - cr), cr, col)

func _draw_rounded_outline(rect: Rect2, cr: float, col: Color, w: float) -> void:
	_canvas.draw_line(rect.position + Vector2(cr, 0),           rect.position + Vector2(rect.size.x - cr, 0),          col, w)
	_canvas.draw_line(rect.position + Vector2(cr, rect.size.y), rect.position + Vector2(rect.size.x - cr, rect.size.y), col, w)
	_canvas.draw_line(rect.position + Vector2(0, cr),           rect.position + Vector2(0, rect.size.y - cr),           col, w)
	_canvas.draw_line(rect.position + Vector2(rect.size.x, cr), rect.position + Vector2(rect.size.x, rect.size.y - cr), col, w)
	_canvas.draw_polyline(_arc(rect.position + Vector2(cr, cr), cr, PI, PI * 1.5), col, w, true)
	_canvas.draw_polyline(_arc(rect.position + Vector2(rect.size.x - cr, cr), cr, PI * 1.5, TAU), col, w, true)
	_canvas.draw_polyline(_arc(rect.position + Vector2(cr, rect.size.y - cr), cr, PI * 0.5, PI), col, w, true)
	_canvas.draw_polyline(_arc(rect.position + Vector2(rect.size.x - cr, rect.size.y - cr), cr, 0.0, PI * 0.5), col, w, true)

func _arc(center: Vector2, radius: float, from_a: float, to_a: float) -> Array:
	const STEPS: int = 10
	var pts: Array = []
	for s in range(STEPS + 1):
		var a: float = from_a + (to_a - from_a) * float(s) / STEPS
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	return pts
