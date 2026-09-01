extends Control
class_name HoldProgressIcon
## HoldProgressIcon.gd (Aug 2026)
## Draws a key/button icon (F keycap or Xbox X button, per the current
## InputMode) with a WHITE ring that sweeps clockwise from 12 o'clock as
## `progress` fills 0→1. Used by the Research Station chute's hold-to-feed
## prompt. The ring hugs the icon's own outline — circular for the X button,
## rounded-square for the F keycap — ~2.5px thick, no gap. Invisible when
## progress is 0 (icon only).

const ICON_DIR:      String = "res://assets/ui/prompts/"
const RING_THICKNESS: float = 2.5
const ICON_SIZE:     Vector2 = Vector2(16.0, 16.0)
## XBOX_X.png's visible disc is 14px (alpha bounds x[1..14] y[1..14]) — radius 7.
const X_BUTTON_RADIUS: float = 7.0
## F.png's visible keycap is ~14px tall / 13px wide with soft corners — a
## rounded square of half-extent 7 and corner radius 3 hugs it.
const F_HALF:       float = 7.0
const F_CORNER_R:   float = 3.0

var progress: float = 0.0   ## 0..1 ring fill

func set_progress(v: float) -> void:
	progress = clampf(v, 0.0, 1.0)
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var controller: bool = InputMode.is_controller()
	var tex: Texture2D = load(ICON_DIR + ("XBOX_X.png" if controller else "F.png"))
	var center: Vector2 = size * 0.5
	if tex != null:
		draw_texture_rect(tex, Rect2(center - ICON_SIZE * 0.5, ICON_SIZE), false)
	if progress <= 0.0:
		return
	## Both rings are drawn as FILLED BANDS (a polygon between the outer and
	## inner outline of the swept fraction), NOT as thick line segments. The
	## previous approach drew 2.5px-wide lines between perimeter points only
	## ~1px apart — adjacent thick strokes overlapped into a solid white blob,
	## flickering depending on the fill fraction. A filled band is clean at
	## every progress value.
	if controller:
		_draw_circle_band(center, X_BUTTON_RADIUS, progress)
	else:
		_draw_rounded_square_band(center, F_HALF, F_CORNER_R, progress)

## Filled circular ring hugging the X button — an annular sector sweeping
## clockwise from 12 o'clock.
func _draw_circle_band(center: Vector2, radius: float, frac: float) -> void:
	if frac <= 0.0:
		return
	var outer_r: float = radius + RING_THICKNESS * 0.5
	var inner_r: float = radius - RING_THICKNESS * 0.5
	const SEGS: int = 48
	var sweep: float = TAU * frac
	var pts := PackedVector2Array()
	for i in SEGS + 1:
		var a: float = -PI / 2.0 + sweep * float(i) / float(SEGS)
		pts.append(center + Vector2(cos(a), sin(a)) * outer_r)
	for i in SEGS + 1:
		var a: float = -PI / 2.0 + sweep * float(SEGS - i) / float(SEGS)
		pts.append(center + Vector2(cos(a), sin(a)) * inner_r)
	draw_colored_polygon(pts, Color.WHITE)

## Filled rounded-square ring hugging the F keycap — the swept fraction of the
## band between the outer and inner rounded-square outlines, clockwise from
## 12 o'clock.
func _draw_rounded_square_band(center: Vector2, half: float, cr: float, frac: float) -> void:
	if frac <= 0.0:
		return
	var outer: PackedVector2Array = _rounded_square_perimeter(center, half + RING_THICKNESS * 0.5, cr + RING_THICKNESS * 0.5)
	var inner: PackedVector2Array = _rounded_square_perimeter(center, half - RING_THICKNESS * 0.5, cr - RING_THICKNESS * 0.5)
	var n: int = maxi(2, int(round(float(outer.size()) * frac)))
	var pts := PackedVector2Array()
	for i in n:
		pts.append(outer[i])
	for i in range(n - 1, -1, -1):
		pts.append(inner[i])
	draw_colored_polygon(pts, Color.WHITE)

## Perimeter points of a rounded square, ordered clockwise starting at 12
## o'clock (top-center) — taking the first `progress` fraction of these and
## drawing a polyline produces a ring that sweeps clockwise hugging the F
## keycap.
func _rounded_square_perimeter(center: Vector2, half: float, cr: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x0: float = center.x - half + cr
	var x1: float = center.x + half - cr
	var y0: float = center.y - half + cr
	var y1: float = center.y + half - cr
	var top: float = center.y - half
	var bottom: float = center.y + half
	const E: int = 6   ## samples per straight edge
	const A: int = 8   ## samples per corner arc
	## Top edge (right half): 12 o'clock → top-right corner
	for i in E:
		pts.append(Vector2(lerpf(center.x, x1, float(i) / float(E - 1)), top))
	## Top-right corner arc: center (x1, y0), angle -PI/2 → 0
	for i in A:
		var a: float = lerpf(-PI / 2.0, 0.0, float(i) / float(A - 1))
		pts.append(Vector2(x1 + cr * cos(a), y0 + cr * sin(a)))
	## Right edge (top → bottom)
	for i in E:
		pts.append(Vector2(center.x + half, lerpf(y0, y1, float(i) / float(E - 1))))
	## Bottom-right corner arc: center (x1, y1), angle 0 → PI/2
	for i in A:
		var a: float = lerpf(0.0, PI / 2.0, float(i) / float(A - 1))
		pts.append(Vector2(x1 + cr * cos(a), y1 + cr * sin(a)))
	## Bottom edge (right → left)
	for i in E:
		pts.append(Vector2(lerpf(x1, x0, float(i) / float(E - 1)), bottom))
	## Bottom-left corner arc: center (x0, y1), angle PI/2 → PI
	for i in A:
		var a: float = lerpf(PI / 2.0, PI, float(i) / float(A - 1))
		pts.append(Vector2(x0 + cr * cos(a), y1 + cr * sin(a)))
	## Left edge (bottom → top)
	for i in E:
		pts.append(Vector2(center.x - half, lerpf(y1, y0, float(i) / float(E - 1))))
	## Top-left corner arc: center (x0, y0), angle PI → 3PI/2
	for i in A:
		var a: float = lerpf(PI, PI * 1.5, float(i) / float(A - 1))
		pts.append(Vector2(x0 + cr * cos(a), y0 + cr * sin(a)))
	## Top edge (left half): top-left corner → 12 o'clock (closes the loop)
	for i in E:
		pts.append(Vector2(lerpf(x0, center.x, float(i) / float(E - 1)), top))
	return pts