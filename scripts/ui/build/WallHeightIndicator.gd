extends Control

## Wall-height tier indicator drawn beside the Build cursor while drawing
## walls. Three bottom-aligned bars in descending height — full, half,
## quarter — with the current tier in the steel accent and the others faint.
## Q / E (LT / RT) step the selection. Pure code-drawn rectangles: no artwork,
## no motion (state changes are immediate, per the quiet design system).

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

const BAR_WIDTH: float = 5.0
const BAR_GAP: float = 3.0
const FULL_HEIGHT: float = 16.0
const TIER_SCALES: Array[float] = [1.0, 0.5, 0.25]   ## full, half, quarter
const SHADOW_ALPHA: float = 0.55
const REST_ALPHA: float = 0.30   ## unselected bars: Q.TEXT at 30%

## 0 = full, 1 = half, 2 = quarter.
var tier: int = 0:
	set(value):
		value = clampi(value, 0, TIER_SCALES.size() - 1)
		if tier != value:
			tier = value
			queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width: float = TIER_SCALES.size() * BAR_WIDTH + (TIER_SCALES.size() - 1) * BAR_GAP
	custom_minimum_size = Vector2(width + 1.0, FULL_HEIGHT + 1.0)
	size = custom_minimum_size

## Rect of bar `index` in local coordinates (bottom-aligned).
func bar_rect(index: int) -> Rect2:
	var height: float = maxf(2.0, roundf(FULL_HEIGHT * TIER_SCALES[index]))
	var x: float = index * (BAR_WIDTH + BAR_GAP)
	return Rect2(x, FULL_HEIGHT - height, BAR_WIDTH, height)

func _draw() -> void:
	var shadow := Color(Color.BLACK, SHADOW_ALPHA)
	var rest := Color(Q.TEXT, REST_ALPHA)
	for i: int in TIER_SCALES.size():
		var rect: Rect2 = bar_rect(i)
		## A 1 px drop shadow keeps the bars legible over bright floors, the
		## same role the HUD's text shadow plays.
		draw_rect(Rect2(rect.position + Vector2(1.0, 1.0), rect.size), shadow)
		draw_rect(rect, Q.ACCENT if i == tier else rest)
