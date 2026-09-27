extends Control
class_name HoldProgressIcon
## HoldProgressIcon.gd (Aug 2026)
## Draws a key/button icon (F keycap or Xbox X button, per the current
## InputMode) with a bunker-blue ring that sweeps clockwise from 12 o'clock as
## `progress` fills 0→1. Used by the Research Station chute's hold-to-feed
## prompt. The ring hugs the icon's own outline — circular for the X button,
## rounded-square for the F keycap — ~2.5px thick, no gap. Invisible when
## progress is 0 (icon only).

const F_TEXTURE: Texture2D = preload("res://assets/ui/prompts/F.png")
const XBOX_X_TEXTURE: Texture2D = preload("res://assets/ui/prompts/XBOX_X.png")
const RING_THICKNESS: float = 2.5
const ICON_SIZE:     Vector2 = Vector2(16.0, 16.0)
## XBOX_X.png's visible disc is 14px (alpha bounds x[1..14] y[1..14]) — radius 7.
const X_BUTTON_RADIUS: float = 7.0
## F.png's visible keycap is ~14px tall / 13px wide with soft corners — a
## rounded square of half-extent 7 and corner radius 3 hugs it.
const F_HALF:       float = 7.0
const F_CORNER_R:   float = 3.0
const RING_TRACK: Color = Color(0.12, 0.16, 0.16, 0.96)
const RING_FILL: Color = Color(0.36, 0.73, 0.96, 1.0)

var progress: float = 0.0   ## 0..1 ring fill

func set_progress(v: float) -> void:
	progress = clampf(v, 0.0, 1.0)
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var controller: bool = InputMode.is_controller()
	var tex: Texture2D = XBOX_X_TEXTURE if controller else F_TEXTURE
	var center: Vector2 = size * 0.5
	if progress > 0.0:
		## Draw each band as independent convex quads. A single polygon with an
		## outer contour followed by a reversed inner contour relies on an
		## implicit hole, which draw_colored_polygon() does not support. At some
		## fill fractions its triangulation crossed that hole and covered the
		## input glyph with a solid square/disc. The segmented strip has no hole
		## ambiguity and is stable for every intermediate hold value.
		if controller:
			_draw_circle_band(center, X_BUTTON_RADIUS, 1.0, RING_TRACK)
			_draw_circle_band(center, X_BUTTON_RADIUS, progress, RING_FILL)
		else:
			_draw_rounded_square_band(center, F_HALF, F_CORNER_R, 1.0, RING_TRACK)
			_draw_rounded_square_band(center, F_HALF, F_CORNER_R, progress, RING_FILL)
	## Keep the actual binding art on top of the ring. Even a future ring-style
	## regression cannot obscure which keyboard/gamepad button is being held.
	if tex != null:
		draw_texture_rect(tex, Rect2(center - ICON_SIZE * 0.5, ICON_SIZE), false)

## Filled circular ring hugging the X button — an annular sector sweeping
## clockwise from 12 o'clock.
func _draw_circle_band(center: Vector2, radius: float, frac: float, color: Color) -> void:
	if frac <= 0.0:
		return
	var outer_r: float = radius + RING_THICKNESS * 0.5
	var inner_r: float = radius - RING_THICKNESS * 0.5
	const SEGS: int = 48
	var sweep: float = TAU * frac
	var segment_count: int = maxi(1, int(ceil(float(SEGS) * frac)))
	for i in segment_count:
		var a0: float = -PI / 2.0 + sweep * float(i) / float(segment_count)
		var a1: float = -PI / 2.0 + sweep * float(i + 1) / float(segment_count)
		var radial0 := Vector2(cos(a0), sin(a0))
		var radial1 := Vector2(cos(a1), sin(a1))
		draw_colored_polygon(PackedVector2Array([
			center + radial0 * outer_r,
			center + radial1 * outer_r,
			center + radial1 * inner_r,
			center + radial0 * inner_r,
		]), color)

## Filled rounded-square ring hugging the F keycap — the swept fraction of the
## band between the outer and inner rounded-square outlines, clockwise from
## 12 o'clock.
func _draw_rounded_square_band(center: Vector2, half: float, cr: float, frac: float, color: Color) -> void:
	if frac <= 0.0:
		return
	var outer: PackedVector2Array = _rounded_square_perimeter(center, half + RING_THICKNESS * 0.5, cr + RING_THICKNESS * 0.5)
	var inner: PackedVector2Array = _rounded_square_perimeter(center, half - RING_THICKNESS * 0.5, cr - RING_THICKNESS * 0.5)
	var available_segments: int = mini(outer.size(), inner.size()) - 1
	var exact_segments: float = float(available_segments) * clampf(frac, 0.0, 1.0)
	var full_segments: int = int(floor(exact_segments))
	for i in full_segments:
		_draw_band_quad(outer[i], outer[i + 1], inner[i + 1], inner[i], color)
	var partial: float = exact_segments - float(full_segments)
	if partial > 0.0001 and full_segments < available_segments:
		_draw_band_quad(
			outer[full_segments],
			outer[full_segments].lerp(outer[full_segments + 1], partial),
			inner[full_segments].lerp(inner[full_segments + 1], partial),
			inner[full_segments],
			color)

func _draw_band_quad(outer_start: Vector2, outer_end: Vector2,
		inner_end: Vector2, inner_start: Vector2, color: Color) -> void:
	## Rounded-square edge/arc joins intentionally share one perimeter point.
	## Ignore those zero-length joins instead of submitting degenerate geometry.
	if outer_start.is_equal_approx(outer_end) and inner_start.is_equal_approx(inner_end):
		return
	draw_colored_polygon(PackedVector2Array([
		outer_start, outer_end, inner_end, inner_start,
	]), color)

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
