extends Control
## CircleFill.gd
## A draining circle progress indicator with an SVG icon in the center.
## Draws a filled arc that depletes clockwise as value drops.
## Color shifts green → yellow → red as fill drops.
## Attach to: Each circle icon Control node in the HUD.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var radius: float    = 22.0
@export var thickness: float = 5.0
@export var bg_color: Color  = Color(0.15, 0.15, 0.15, 0.7)

## SVG icon drawn in the center of the circle.
## Set this in the Inspector for each HUD circle (steak / water-drop / night-sleep).
@export var icon: Texture2D = null

## Size of the icon drawn in the center (pixels). Tweak per-icon if needed.
@export var icon_size: float = 18.0

# ─── State ────────────────────────────────────────────────────────────────────
var _fill: float = 1.0   # 0.0 to 1.0

# ─── Colors ───────────────────────────────────────────────────────────────────
const COLOR_FULL:     Color = Color(0.35, 0.85, 0.45)   # Green
const COLOR_MID:      Color = Color(0.95, 0.80, 0.10)   # Yellow
const COLOR_LOW:      Color = Color(0.90, 0.25, 0.15)   # Red
const COLOR_CRITICAL: Color = Color(1.00, 0.10, 0.05)   # Bright red

var _pulse_t: float   = 0.0
var _is_critical: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2 + 10, radius * 2 + 10)

func set_fill(value: float) -> void:
	_fill = clampf(value, 0.0, 1.0)
	_is_critical = _fill < 0.2
	queue_redraw()

func _process(delta: float) -> void:
	if _is_critical:
		_pulse_t += delta * 4.0
		queue_redraw()

func _draw() -> void:
	var center: Vector2 = Vector2(radius + 5, radius + 5)

	# ── Background ring ──
	draw_arc(center, radius, 0, TAU, 64, bg_color, thickness, true)

	# ── Filled arc (drains clockwise from top) ──
	var fill_color: Color = _get_fill_color()
	if _is_critical:
		fill_color.a = 0.5 + sin(_pulse_t) * 0.5

	if _fill > 0.0:
		var end_angle: float = -PI / 2.0 + TAU * _fill
		draw_arc(center, radius, -PI / 2.0, end_angle, 64, fill_color, thickness, true)

	# ── Center icon ──
	if icon != null:
		var half: float  = icon_size * 0.5
		var dst: Rect2   = Rect2(center - Vector2(half, half), Vector2(icon_size, icon_size))
		# Tint the icon: full brightness normally, dim when critical
		var icon_color: Color = Color(1, 1, 1, 0.9)
		if _is_critical:
			icon_color.a = 0.45 + sin(_pulse_t) * 0.45
		draw_texture_rect(icon, dst, false, icon_color)

func _get_fill_color() -> Color:
	if _fill > 0.6:
		return COLOR_FULL
	elif _fill > 0.35:
		return COLOR_MID
	elif _fill > 0.2:
		return COLOR_LOW
	else:
		return COLOR_CRITICAL
