class_name JobProgressGlyph
extends Control
## Compact code-drawn work mark for the shared player/NPC job indicator.
## Kept procedural so the prompt overhaul adds no generated raster asset.

@export var glyph_color: Color = Color(0.34, 0.70, 0.93, 1.0):
	set(value):
		glyph_color = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(18.0, 18.0)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var scale_factor := minf(size.x, size.y) / 18.0
	## Small wrench silhouette: open jaw, diagonal shaft, and handle eye.
	var jaw := PackedVector2Array([
		center + Vector2(-6.5, -6.0) * scale_factor,
		center + Vector2(-2.5, -5.0) * scale_factor,
		center + Vector2(-1.0, -2.5) * scale_factor,
		center + Vector2(-3.0, -0.5) * scale_factor,
		center + Vector2(-6.0, -2.0) * scale_factor,
	])
	draw_polyline(jaw, glyph_color, 1.7 * scale_factor, true)
	draw_line(center + Vector2(-2.0, -1.5) * scale_factor,
		center + Vector2(5.5, 6.0) * scale_factor,
		glyph_color, 2.2 * scale_factor, true)
	draw_arc(center + Vector2(6.0, 6.5) * scale_factor,
		2.2 * scale_factor, 0.0, TAU, 14,
		glyph_color, 1.5 * scale_factor, true)
