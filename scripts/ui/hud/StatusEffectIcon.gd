extends Control
class_name StatusEffectIcon
## StatusEffectIcon.gd
## ─────────────────────────────────────────────────────────────────────────────
## Single reusable status-effect badge: a small icon centered inside a ring
## that depletes CLOCKWISE as the effect's remaining duration counts down
## (Jul 2026 "Needs Gauge Redesign" plan, status-effect skeleton). Mirrors
## CircleFill.gd's existing depleting-ring drawing approach, but the fill
## here represents TIME REMAINING, not a stat value, and ticks down on its
## own via _process() rather than being pushed externally every frame.
##
## SKELETON ONLY — no real status effects are wired to this in this pass.
## Nothing calls setup() anywhere yet. This file + StatusEffectsContainer.gd
## exist purely so a future plan can call
## StatusEffectsContainer.add_effect(...) without building this plumbing
## from scratch — same "structure now, real content later" precedent as
## NotificationManager.gd's first pass.
##
## Usage (future callers):
##     var badge := StatusEffectIcon.new()
##     badge.setup("poisoned", some_icon_texture, 12.0, Color(0.85, 0.3, 0.2))

signal expired(effect_id: String)

const RADIUS: float    = 22.0
const THICKNESS: float = 4.0
const BG_RING_COLOR: Color = Color(0.15, 0.15, 0.15, 0.85)
const PANEL_COLOR:   Color = Color(0.10, 0.10, 0.10, 0.90)
const ICON_SIZE: float = 22.0
const PLACEHOLDER_COLOR: Color = Color(0.55, 0.55, 0.55, 0.90)   ## blank grey "no icon yet" fill
const RUGGED_BORDER_COLOR: Color = Color(0.02, 0.02, 0.02, 0.55)
const RUGGED_BORDER_WIDTH: float = 1.2

var effect_id: String = ""
var _icon: Texture2D = null
var _ring_color: Color = Color(0.9, 0.6, 0.2, 1.0)
var _total_duration: float = 1.0
var _remaining: float = 1.0

func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0 + 6.0, RADIUS * 2.0 + 6.0)
	var grime_mat: ShaderMaterial = ShaderMaterial.new()
	grime_mat.shader = load("res://assets/shaders/grunge_overlay.gdshader")
	material = grime_mat

## Starts (or restarts) this badge showing `icon` (may be null — blank center)
## with a depletion ring in `ring_color`, counting down from `duration`
## seconds. Emits `expired` with `id` once remaining time hits 0 — the
## container is responsible for removing/freeing this node when it does.
func setup(id: String, icon: Texture2D, duration: float, ring_color: Color) -> void:
	effect_id       = id
	_icon           = icon
	_total_duration = maxf(duration, 0.01)
	_remaining      = _total_duration
	_ring_color     = ring_color
	queue_redraw()

func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(0.0, _remaining - delta)
	queue_redraw()
	if _remaining <= 0.0:
		expired.emit(effect_id)

func _draw() -> void:
	var center: Vector2 = Vector2(RADIUS + 3.0, RADIUS + 3.0)
	draw_circle(center, RADIUS - THICKNESS * 0.5, PANEL_COLOR)
	draw_arc(center, RADIUS, 0.0, TAU, 48, BG_RING_COLOR, THICKNESS, true)
	if _total_duration > 0.0:
		var frac: float = _remaining / _total_duration
		if frac > 0.0:
			var end_angle: float = -PI / 2.0 + TAU * frac
			draw_arc(center, RADIUS, -PI / 2.0, end_angle, 48, _ring_color, THICKNESS, true)
	if _icon != null:
		var half: float = ICON_SIZE * 0.5
		var dst: Rect2 = Rect2(center - Vector2(half, half), Vector2(ICON_SIZE, ICON_SIZE))
		draw_texture_rect(_icon, dst, false)
	else:
		## Blank grey placeholder — no real icon art exists yet (Jul 2026).
		draw_circle(center, ICON_SIZE * 0.5, PLACEHOLDER_COLOR)
	UIKit.draw_rugged_circle(self, center, RADIUS + THICKNESS * 0.5, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 700.0)
	UIKit.draw_rugged_circle(self, center, RADIUS - THICKNESS * 0.5, RUGGED_BORDER_COLOR, RUGGED_BORDER_WIDTH, 850.0)