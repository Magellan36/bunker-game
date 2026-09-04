@tool
extends Texture2D
## Functional UI symbols rendered from Godot primitives, not imported artwork.
## Intended for Button icons and TextureRect KEEP_ASPECT_CENTERED. No tiling,
## atlas cropping or 3D use. Keep decorative artwork separately provenance-tagged.

@export_enum("power", "running", "stopped", "grid", "fuel", "condition", "water", "battery", "plant", "warning") var symbol: String = "power":
	set(value):
		symbol = value
		emit_changed()

func _get_width() -> int:
	return 32

func _get_height() -> int:
	return 32

func _has_alpha() -> bool:
	return true

func _draw(item: RID, pos: Vector2, tint: Color, transpose: bool) -> void:
	_draw_rect(item, Rect2(pos, Vector2(32, 32)), false, tint, transpose)

func _draw_rect_region(item: RID, rect: Rect2, _source: Rect2, tint: Color, transpose: bool, _clip_uv: bool) -> void:
	# Some native controls use the region entry point even for a whole icon.
	# These UI-only symbols are whole images, never cropped atlas regions.
	_draw_rect(item, rect, false, tint, transpose)

func _draw_rect(item: RID, rect: Rect2, _tile: bool, tint: Color, transpose: bool) -> void:
	var lines: Array[PackedVector2Array] = []
	var solids: Array[PackedVector2Array] = []
	match symbol:
		"power":
			solids.append(PackedVector2Array([Vector2(19, 2), Vector2(5, 19), Vector2(14, 19), Vector2(11, 30), Vector2(27, 12), Vector2(18, 12)]))
		"running", "stopped":
			var circle := PackedVector2Array()
			for i: int in range(49):
				circle.append(Vector2(16, 16) + Vector2.from_angle(TAU * i / 48.0) * 13.0)
			lines.append(circle)
			if symbol == "running":
				solids.append(PackedVector2Array([Vector2(13, 9), Vector2(23, 16), Vector2(13, 23)]))
			else:
				solids.append(_box(Vector2(11, 11), Vector2(10, 10)))
		"grid":
			lines.append(PackedVector2Array([Vector2(7, 7), Vector2(25, 7), Vector2(25, 25), Vector2(7, 25), Vector2(7, 7)]))
			for center: Vector2 in [Vector2(7, 7), Vector2(25, 7), Vector2(7, 25), Vector2(25, 25)]:
				solids.append(_box(center - Vector2(4, 4), Vector2(8, 8)))
		"fuel":
			lines.append(PackedVector2Array([Vector2(8, 6), Vector2(8, 3), Vector2(19, 3), Vector2(19, 8), Vector2(25, 11), Vector2(25, 28), Vector2(6, 28), Vector2(6, 10), Vector2(8, 6), Vector2(20, 6)]))
			lines.append(PackedVector2Array([Vector2(11, 15), Vector2(20, 24)]))
			lines.append(PackedVector2Array([Vector2(20, 15), Vector2(11, 24)]))
		"condition":
			lines.append(PackedVector2Array([Vector2(16, 2), Vector2(28, 7), Vector2(26, 20), Vector2(22, 26), Vector2(16, 30), Vector2(10, 26), Vector2(6, 20), Vector2(4, 7), Vector2(16, 2)]))
			lines.append(PackedVector2Array([Vector2(10, 15), Vector2(15, 20), Vector2(23, 11)]))
		"water":
			lines.append(PackedVector2Array([Vector2(5, 4), Vector2(5, 27), Vector2(27, 27), Vector2(27, 4)]))
			lines.append(PackedVector2Array([Vector2(6, 17), Vector2(11, 15), Vector2(16, 17), Vector2(21, 15), Vector2(26, 17)]))
			solids.append(_box(Vector2(7, 21), Vector2(18, 4)))
		"battery":
			lines.append(PackedVector2Array([Vector2(4, 9), Vector2(26, 9), Vector2(26, 25), Vector2(4, 25), Vector2(4, 9)]))
			solids.append(_box(Vector2(27, 13), Vector2(3, 8)))
			for x: int in [8, 14, 20]:
				solids.append(_box(Vector2(x, 13), Vector2(3, 8)))
		"plant":
			lines.append(PackedVector2Array([Vector2(16, 29), Vector2(16, 12)]))
			solids.append(PackedVector2Array([Vector2(16, 19), Vector2(6, 17), Vector2(3, 7), Vector2(13, 9)]))
			solids.append(PackedVector2Array([Vector2(16, 13), Vector2(20, 4), Vector2(30, 2), Vector2(27, 11)]))
		"warning":
			lines.append(PackedVector2Array([Vector2(16, 3), Vector2(30, 28), Vector2(2, 28), Vector2(16, 3)]))
			lines.append(PackedVector2Array([Vector2(16, 11), Vector2(16, 19)]))
			solids.append(_box(Vector2(15, 23), Vector2(2, 2)))
	var width: float = maxf(1.0, minf(absf(rect.size.x), absf(rect.size.y)) / 16.0)
	for points: PackedVector2Array in solids:
		RenderingServer.canvas_item_add_polygon(item, _mapped(points, rect, transpose), PackedColorArray([tint]))
	for points: PackedVector2Array in lines:
		RenderingServer.canvas_item_add_polyline(item, _mapped(points, rect, transpose), PackedColorArray([tint]), width, true)

func _box(pos: Vector2, dimensions: Vector2) -> PackedVector2Array:
	return PackedVector2Array([pos, pos + Vector2(dimensions.x, 0), pos + dimensions, pos + Vector2(0, dimensions.y)])

func _mapped(points: PackedVector2Array, rect: Rect2, transpose: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		var p: Vector2 = Vector2(point.y, point.x) if transpose else point
		result.append(rect.position + p / 32.0 * rect.size)
	return result
