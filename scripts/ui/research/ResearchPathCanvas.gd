extends Control
class_name ResearchPathCanvas

## Lightweight presentation canvas for the modern Research Station.  The
## upgrade buttons remain ordinary Godot Controls owned by the parent UI;
## this node only draws the restrained blueprint grid and dependency lines
## behind them.

const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")

var connections: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_connections(value: Array[Dictionary]) -> void:
	connections = value
	queue_redraw()


func _draw() -> void:
	var dot_color: Color = S.BRASS.darkened(0.55)
	dot_color.a = 0.28
	var spacing: float = 24.0
	var y: float = 12.0
	while y < size.y:
		var x: float = 12.0
		while x < size.x:
			draw_circle(Vector2(x, y), 1.0, dot_color)
			x += spacing
		y += spacing

	for connection: Dictionary in connections:
		var points: PackedVector2Array = (
			connection.get("points", PackedVector2Array()) as PackedVector2Array
		)
		if points.size() < 2:
			continue
		var active: bool = bool(connection.get("active", false))
		var line_color: Color = S.BLUE if active else S.BRASS.darkened(0.32)
		line_color.a = 0.88 if active else 0.62
		draw_polyline(points, line_color, 2.0 if active else 1.5, true)
		var end: Vector2 = points[points.size() - 1]
		draw_circle(end, 3.0, line_color)
