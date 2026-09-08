class_name ItemStateMeter
extends Control
## Shared inventory/Storage meter drawing; reads presentation values only.

const SLOT_SIZE: float = 72.0
const BORDER: Color = Color("66583f")
const WATER_BLUE: Color = Color("54b9ed")
const GREEN: Color = Color("75d48a")
const AMBER: Color = Color("dda42e")
const RED: Color = Color("df5a52")
const EMPTY: Color = Color("48504d")
var state: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(72, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_state(Rect2(Vector2.ZERO, Vector2(72, 30)), state)

func draw_state(rect: Rect2, value: Dictionary) -> void:
	match String(value.get("kind", "none")):
		"liquid": _draw_liquid_gauge(self, rect, value)
		"battery": _draw_battery_meter(self, rect, value)
		"charges": _draw_charge_pips(self, rect, value)

static func _draw_liquid_gauge(canvas: Control, rect: Rect2, state: Dictionary) -> void:
	var center: Vector2 = rect.position + Vector2(SLOT_SIZE - 17.0, 17.0)
	var fraction: float = clampf(float(state.get("fraction", 0.0)), 0.0, 1.0)
	var quality: float = clampf(float(state.get("quality", 0.0)), 0.0, 100.0)
	canvas.draw_circle(center, 12.0, Color("101514ed"))
	canvas.draw_arc(center, 9.0, -PI * 0.5, PI * 1.5, 32, EMPTY, 2.5, true)
	if fraction > 0.0:
		canvas.draw_arc(center, 9.0, -PI * 0.5, -PI * 0.5 + TAU * fraction,
			maxi(4, int(32.0 * fraction)), WATER_BLUE, 2.5, true)
	_draw_drop(canvas, center, _quality_color(quality) if fraction > 0.0 else EMPTY)


static func _draw_drop(canvas: Control, center: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -5.0), center + Vector2(4.0, 1.0),
		center + Vector2(3.0, 4.0), center + Vector2(0.0, 5.0),
		center + Vector2(-3.0, 4.0), center + Vector2(-4.0, 1.0),
	])
	canvas.draw_colored_polygon(points, color)


static func _draw_battery_meter(canvas: Control, rect: Rect2, state: Dictionary, phase: float = 0.0) -> void:
	var fraction: float = clampf(float(state.get("fraction", 0.0)), 0.0, 1.0)
	var lit_bars: int = ceili(fraction * 4.0) if fraction > 0.0 else 0
	var origin: Vector2 = rect.position + Vector2(SLOT_SIZE - 33.0, 10.0)
	var shell: Rect2 = Rect2(origin, Vector2(24.0, 12.0))
	UIKit.draw_rounded_rect(canvas, shell, Color("101514ed"), BORDER, 1.0, 3.0)
	canvas.draw_rect(Rect2(origin + Vector2(24.0, 3.0), Vector2(2.0, 6.0)), BORDER, true)
	for i: int in 4:
		var bar: Rect2 = Rect2(origin + Vector2(3.0 + float(i) * 5.0, 3.0), Vector2(3.0, 6.0))
		var color: Color = EMPTY
		if i < lit_bars:
			if lit_bars == 1:
				var pulse: float = 0.72 + sin(phase) * 0.20
				color = Color(RED.r, RED.g, RED.b, pulse)
			elif lit_bars == 2:
				color = AMBER
			else:
				color = GREEN
		canvas.draw_rect(bar, color, true)


static func _draw_charge_pips(canvas: Control, rect: Rect2, state: Dictionary) -> void:
	var current: int = maxi(0, int(state.get("current", 0)))
	var maximum: int = maxi(1, int(state.get("maximum", 1)))
	var visible_pips: int = mini(maximum, 4)
	var start_x: float = rect.end.x - 10.0 - float(visible_pips - 1) * 9.0
	for i: int in visible_pips:
		var center: Vector2 = Vector2(start_x + float(i) * 9.0, rect.position.y + 14.0)
		canvas.draw_circle(center, 3.2, GREEN if i < current else EMPTY)
		canvas.draw_arc(center, 3.2, 0.0, TAU, 16, Color("0b100f"), 1.0, true)


static func _quality_color(quality: float) -> Color:
	if quality <= 50.0:
		return RED
	if quality <= 75.0:
		return AMBER
	return GREEN


