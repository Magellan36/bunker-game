class_name LoadingBackdropArt
extends Control

## Quiet, code-rendered bunker schematics for the approved loading screen.
## The shapes deliberately stay below the text hierarchy and require no
## imported image asset, so they scale cleanly at every supported resolution.

const BG: Color = Color("0d1515")
const BLUE_LINE: Color = Color("3154663d")
const BLUE_FAINT: Color = Color("27455224")
const BRASS_LINE: Color = Color("88734e35")
const BRASS_FAINT: Color = Color("88734e1b")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if size.x <= 1.0 or size.y <= 1.0:
		return

	# A restrained pool of blue behind the mark, built from translucent rings.
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.43)
	for ring: int in range(10, 0, -1):
		var radius: float = minf(size.x, size.y) * (0.055 + float(ring) * 0.026)
		var alpha: float = 0.0045 * float(11 - ring)
		draw_circle(center, radius, Color(0.20, 0.55, 0.70, alpha))

	_draw_wing(Rect2(size.x * 0.035, size.y * 0.16, size.x * 0.27, size.y * 0.66), false)
	_draw_wing(Rect2(size.x * 0.695, size.y * 0.16, size.x * 0.27, size.y * 0.66), true)

	# Subtle top and bottom edge structure keeps the center feeling embedded in
	# the bunker rather than floating over a blank splash screen.
	draw_line(Vector2(size.x * 0.10, size.y * 0.075), Vector2(size.x * 0.90, size.y * 0.075), BRASS_FAINT, 1.0, true)
	draw_line(Vector2(size.x * 0.10, size.y * 0.925), Vector2(size.x * 0.90, size.y * 0.925), BRASS_FAINT, 1.0, true)


func _draw_wing(bounds: Rect2, mirror: bool) -> void:
	var rooms: Array[Rect2] = [
		Rect2(0.02, 0.07, 0.38, 0.22),
		Rect2(0.45, 0.03, 0.48, 0.18),
		Rect2(0.10, 0.36, 0.52, 0.25),
		Rect2(0.66, 0.29, 0.30, 0.30),
		Rect2(0.00, 0.69, 0.44, 0.22),
		Rect2(0.50, 0.67, 0.43, 0.27),
	]
	for normalized_room: Rect2 in rooms:
		var room: Rect2 = _mapped_rect(normalized_room, bounds, mirror)
		draw_rect(room, BLUE_FAINT, false, 1.0, true)
		_draw_room_detail(room, mirror)

	var pipe_x: float = bounds.end.x if not mirror else bounds.position.x
	var outer_x: float = bounds.position.x + bounds.size.x * (0.84 if not mirror else 0.16)
	var mid_y: float = bounds.position.y + bounds.size.y * 0.51
	var pipe: PackedVector2Array = PackedVector2Array([
		Vector2(pipe_x, bounds.position.y + bounds.size.y * 0.16),
		Vector2(outer_x, bounds.position.y + bounds.size.y * 0.16),
		Vector2(outer_x, mid_y),
		Vector2(pipe_x, mid_y),
	])
	draw_polyline(pipe, BRASS_LINE, 1.35, true)
	for point: Vector2 in pipe:
		draw_circle(point, 2.5, BRASS_LINE)


func _mapped_rect(normalized: Rect2, bounds: Rect2, mirror: bool) -> Rect2:
	var x: float = normalized.position.x
	if mirror:
		x = 1.0 - normalized.position.x - normalized.size.x
	return Rect2(
		bounds.position + Vector2(x * bounds.size.x, normalized.position.y * bounds.size.y),
		Vector2(normalized.size.x * bounds.size.x, normalized.size.y * bounds.size.y))


func _draw_room_detail(room: Rect2, mirror: bool) -> void:
	var inset: Rect2 = room.grow(-maxf(5.0, room.size.x * 0.055))
	draw_rect(inset, BRASS_FAINT, false, 1.0, true)
	var split_x: float = inset.position.x + inset.size.x * (0.64 if mirror else 0.36)
	draw_line(Vector2(split_x, inset.position.y), Vector2(split_x, inset.end.y), BLUE_FAINT, 1.0, true)
	var door_y: float = inset.end.y - minf(18.0, inset.size.y * 0.25)
	draw_line(Vector2(split_x - 5.0, door_y), Vector2(split_x + 5.0, door_y), BRASS_FAINT, 2.0, true)
