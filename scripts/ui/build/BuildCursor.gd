class_name BuildCursor
extends Control

## Controller-visible Build Mode pointer. It is drawn entirely with Godot
## primitives so it stays crisp at every resolution and requires no asset.
var over_ui := false:
	set(value):
		if over_ui != value:
			over_ui = value
			queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(34, 34)
	size = Vector2(34, 34)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if over_ui:
		var pointer := PackedVector2Array([
			Vector2(5, 3), Vector2(5, 26), Vector2(11, 20),
			Vector2(16, 30), Vector2(21, 27), Vector2(16, 18),
			Vector2(25, 18), Vector2(5, 3),
		])
		draw_colored_polygon(pointer, Color("0b1113e6"))
		draw_polyline(pointer, BunkerPanelStyle.IVORY, 3.5, true)
		draw_polyline(pointer, BunkerPanelStyle.BLUE, 1.8, true)
	else:
		var center := Vector2(17, 17)
		draw_circle(center, 8.0, Color("0b1113cc"), false, 4.0, true)
		draw_circle(center, 8.0, BunkerPanelStyle.BLUE, false, 2.0, true)
		for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			draw_line(center + direction * 11.0, center + direction * 15.0,
				BunkerPanelStyle.IVORY, 2.0, true)
		draw_circle(center, 1.8, BunkerPanelStyle.IVORY)
