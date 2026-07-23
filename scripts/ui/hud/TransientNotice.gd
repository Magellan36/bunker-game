extends CanvasLayer
class_name TransientNotice
## TransientNotice.gd
## ─────────────────────────────────────────────────────────────────────────────
## Minimal one-off notification popup (Jul 2026, Purifier QoL plan item 4) —
## this codebase has no notification/toast system yet (checked: HUD.gd has no
## transient-message mechanism to hook into), and this plan is deliberately
## NOT the place a full one gets built speculatively. One string in, no
## queueing/stacking system, no icon — shown for a few seconds then fades out
## and frees itself.
##
## If a second notice needs to show while one is already up, just spawn a
## second instance (stacked/overlapping is an accepted rough edge for this
## first pass — not solving notice-queueing here, out of scope for a QoL
## pass this size).
##
## Usage:
##     var notice := TransientNotice.new()
##     get_tree().get_root().add_child(notice)
##     notice.show_message("Purifier filter below 50%")

const DISPLAY_DURATION: float = 3.0
const FADE_DURATION:    float = 0.4
const BG_COLOR:     Color = Color(0.08, 0.09, 0.06, 0.92)
const BORDER_COLOR: Color = Color(0.95, 0.75, 0.20, 0.85)   ## warning amber — matches Flashlight.COL_LOW
const TEXT_COLOR:   Color = Color(0.95, 0.92, 0.85, 1.0)

var _canvas: Control = null
var _font: Font = null
var _text: String = ""

func _ready() -> void:
	layer = 65

	_font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	if _font == null:
		_font = ThemeDB.fallback_font

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE   ## purely informational — never blocks input
	_canvas.name = "TransientNoticeCanvas"
	add_child(_canvas)
	_canvas.draw.connect(_on_draw)

func show_message(text: String) -> void:
	_text = text
	_canvas.queue_redraw()
	## Reuses UIFade's fade-in convention (July 2026 standing pattern) plus
	## the new fade_out() counterpart added alongside this file.
	UIFade.fade_in(_canvas)
	var timer: SceneTreeTimer = get_tree().create_timer(DISPLAY_DURATION)
	timer.timeout.connect(func() -> void:
		UIFade.fade_out(_canvas, FADE_DURATION, queue_free)
	)

func _on_draw() -> void:
	if _text.is_empty():
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tsz: Vector2 = _font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var pad: Vector2 = Vector2(20.0, 14.0)
	var panel_size: Vector2 = tsz + pad * 2.0
	## Top-center, below where most water/power panels open (those are
	## screen-centered) — reads as a passive notice, not a blocking dialog.
	var px: float = (vp_size.x - panel_size.x) * 0.5
	var py: float = 70.0
	var rect: Rect2 = Rect2(px, py, panel_size.x, panel_size.y)
	_canvas.draw_rect(rect, BG_COLOR, true)
	_canvas.draw_rect(rect, BORDER_COLOR, false, 1.5)
	_canvas.draw_string(_font, Vector2(px + pad.x, py + pad.y + tsz.y * 0.7),
		_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TEXT_COLOR)
