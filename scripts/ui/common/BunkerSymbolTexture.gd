@tool
extends Texture2D
## Functional UI symbols rendered from Godot primitives, not imported artwork.
## Intended for Button icons and TextureRect KEEP_ASPECT_CENTERED. No tiling,
## atlas cropping or 3D use. Keep decorative artwork separately provenance-tagged.

@export_enum("power", "running", "stopped", "grid", "fuel", "condition", "water", "hydration", "battery", "plant", "warning", "build", "move", "duplicate", "demolish", "undo", "wire", "pipe", "shop", "storage", "trash", "shelter", "tip", "food", "container", "cooking", "search", "plus", "minus", "close", "check", "arrow", "save", "load", "settings", "exit", "log", "clock", "general", "status", "health", "stamina", "sleep", "medical", "bandage", "bleeding", "infection", "fracture", "burn", "temperature", "antibiotics", "splint", "trauma", "overview", "talk", "requests", "relationship", "mood", "skills") var symbol: String = "power":
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
		"hydration":
			lines.append(PackedVector2Array([Vector2(16, 2), Vector2(8, 14), Vector2(7, 20), Vector2(10, 26), Vector2(16, 29), Vector2(22, 26), Vector2(25, 20), Vector2(24, 14), Vector2(16, 2)]))
			lines.append(PackedVector2Array([Vector2(11, 21), Vector2(13, 24), Vector2(17, 26), Vector2(21, 24)]))
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
		"build":
			lines.append(PackedVector2Array([Vector2(16, 3), Vector2(29, 10), Vector2(16, 17), Vector2(3, 10), Vector2(16, 3)]))
			lines.append(PackedVector2Array([Vector2(3, 10), Vector2(3, 23), Vector2(16, 30), Vector2(16, 17)]))
			lines.append(PackedVector2Array([Vector2(29, 10), Vector2(29, 23), Vector2(16, 30)]))
		"move":
			lines.append(PackedVector2Array([Vector2(16, 3), Vector2(16, 29)]))
			lines.append(PackedVector2Array([Vector2(3, 16), Vector2(29, 16)]))
			for points: PackedVector2Array in [PackedVector2Array([Vector2(11, 8), Vector2(16, 3), Vector2(21, 8)]), PackedVector2Array([Vector2(11, 24), Vector2(16, 29), Vector2(21, 24)]), PackedVector2Array([Vector2(8, 11), Vector2(3, 16), Vector2(8, 21)]), PackedVector2Array([Vector2(24, 11), Vector2(29, 16), Vector2(24, 21)])]:
				lines.append(points)
		"duplicate":
			lines.append(PackedVector2Array([Vector2(4, 4), Vector2(21, 4), Vector2(21, 21), Vector2(4, 21), Vector2(4, 4)]))
			lines.append(PackedVector2Array([Vector2(11, 11), Vector2(28, 11), Vector2(28, 28), Vector2(11, 28), Vector2(11, 11)]))
		"arrow":
			lines.append(PackedVector2Array([Vector2(7, 16), Vector2(25, 16)]))
			lines.append(PackedVector2Array([Vector2(18, 9), Vector2(25, 16), Vector2(18, 23)]))
		"demolish":
			lines.append(PackedVector2Array([Vector2(7, 25), Vector2(22, 10)]))
			solids.append(PackedVector2Array([Vector2(18, 4), Vector2(28, 14), Vector2(23, 19), Vector2(13, 9)]))
			lines.append(PackedVector2Array([Vector2(4, 28), Vector2(11, 28)]))
		"undo":
			lines.append(PackedVector2Array([Vector2(12, 8), Vector2(4, 15), Vector2(12, 22)]))
			lines.append(PackedVector2Array([Vector2(5, 15), Vector2(19, 15), Vector2(27, 20), Vector2(27, 27)]))
		"wire":
			solids.append(PackedVector2Array([Vector2(19, 2), Vector2(5, 19), Vector2(14, 19), Vector2(11, 30), Vector2(27, 12), Vector2(18, 12)]))
		"pipe":
			lines.append(PackedVector2Array([Vector2(5, 4), Vector2(5, 17), Vector2(15, 17), Vector2(15, 27), Vector2(28, 27)]))
			lines.append(PackedVector2Array([Vector2(10, 4), Vector2(10, 12), Vector2(20, 12), Vector2(20, 22), Vector2(28, 22)]))
		"shop":
			lines.append(PackedVector2Array([Vector2(3, 5), Vector2(7, 5), Vector2(10, 21), Vector2(25, 21), Vector2(29, 9), Vector2(8, 9)]))
			for center: Vector2 in [Vector2(12, 27), Vector2(24, 27)]:
				var wheel := PackedVector2Array()
				for i: int in range(17):
					wheel.append(center + Vector2.from_angle(TAU * i / 16.0) * 2.5)
				lines.append(wheel)
		"storage", "container":
			lines.append(PackedVector2Array([Vector2(4, 10), Vector2(16, 4), Vector2(28, 10), Vector2(16, 16), Vector2(4, 10), Vector2(4, 25), Vector2(16, 30), Vector2(28, 25), Vector2(28, 10)]))
			lines.append(PackedVector2Array([Vector2(16, 16), Vector2(16, 30)]))
		"trash":
			lines.append(PackedVector2Array([Vector2(8, 9), Vector2(24, 9), Vector2(22, 29), Vector2(10, 29), Vector2(8, 9)]))
			lines.append(PackedVector2Array([Vector2(6, 6), Vector2(26, 6)]))
			lines.append(PackedVector2Array([Vector2(12, 6), Vector2(13, 3), Vector2(19, 3), Vector2(20, 6)]))
			for x: int in [13, 19]:
				lines.append(PackedVector2Array([Vector2(x, 13), Vector2(x, 25)]))
		"shelter":
			var outer_arch := PackedVector2Array()
			for i: int in range(25):
				var outer_angle: float = PI + PI * float(i) / 24.0
				outer_arch.append(Vector2(16, 15) + Vector2(cos(outer_angle) * 13.0, sin(outer_angle) * 12.0))
			lines.append(outer_arch)
			lines.append(PackedVector2Array([Vector2(3, 15), Vector2(3, 29), Vector2(29, 29), Vector2(29, 15)]))
			var door_arch := PackedVector2Array()
			for i: int in range(17):
				var door_angle: float = PI + PI * float(i) / 16.0
				door_arch.append(Vector2(16, 18) + Vector2(cos(door_angle) * 6.0, sin(door_angle) * 6.0))
			lines.append(door_arch)
			lines.append(PackedVector2Array([Vector2(10, 18), Vector2(10, 29), Vector2(22, 29), Vector2(22, 18)]))
			lines.append(PackedVector2Array([Vector2(16, 14), Vector2(16, 26)]))
			lines.append(PackedVector2Array([Vector2(11, 20), Vector2(21, 20)]))
		"tip":
			var bulb := PackedVector2Array()
			for i: int in range(25):
				var bulb_angle: float = TAU * float(i) / 24.0
				bulb.append(Vector2(16, 13) + Vector2(cos(bulb_angle) * 8.0, sin(bulb_angle) * 8.0))
			lines.append(bulb)
			lines.append(PackedVector2Array([Vector2(12, 20), Vector2(12, 24), Vector2(20, 24), Vector2(20, 20)]))
			lines.append(PackedVector2Array([Vector2(12, 27), Vector2(20, 27)]))
			for ray: PackedVector2Array in [PackedVector2Array([Vector2(16, 1), Vector2(16, 4)]), PackedVector2Array([Vector2(5, 4), Vector2(8, 7)]), PackedVector2Array([Vector2(27, 4), Vector2(24, 7)]), PackedVector2Array([Vector2(2, 14), Vector2(6, 14)]), PackedVector2Array([Vector2(26, 14), Vector2(30, 14)])]:
				lines.append(ray)
		"food":
			lines.append(PackedVector2Array([Vector2(16, 3), Vector2(25, 10), Vector2(23, 23), Vector2(16, 29), Vector2(9, 23), Vector2(7, 10), Vector2(16, 3)]))
			lines.append(PackedVector2Array([Vector2(10, 12), Vector2(22, 12)]))
		"cooking":
			lines.append(PackedVector2Array([Vector2(5, 12), Vector2(27, 12), Vector2(25, 28), Vector2(7, 28), Vector2(5, 12)]))
			lines.append(PackedVector2Array([Vector2(10, 8), Vector2(22, 8)]))
			lines.append(PackedVector2Array([Vector2(13, 3), Vector2(13, 8), Vector2(19, 8), Vector2(19, 3)]))
		"search":
			var lens := PackedVector2Array()
			for i: int in range(33):
				lens.append(Vector2(13, 13) + Vector2.from_angle(TAU * i / 32.0) * 9.0)
			lines.append(lens)
			lines.append(PackedVector2Array([Vector2(20, 20), Vector2(29, 29)]))
		"plus":
			lines.append(PackedVector2Array([Vector2(16, 6), Vector2(16, 26)]))
			lines.append(PackedVector2Array([Vector2(6, 16), Vector2(26, 16)]))
		"minus":
			lines.append(PackedVector2Array([Vector2(6, 16), Vector2(26, 16)]))
		"close":
			lines.append(PackedVector2Array([Vector2(7, 7), Vector2(25, 25)]))
			lines.append(PackedVector2Array([Vector2(25, 7), Vector2(7, 25)]))
		"check":
			lines.append(PackedVector2Array([Vector2(5, 16), Vector2(13, 24), Vector2(28, 7)]))
		"save":
			lines.append(PackedVector2Array([Vector2(5, 3), Vector2(24, 3), Vector2(29, 8), Vector2(29, 29), Vector2(5, 29), Vector2(5, 3)]))
			lines.append(PackedVector2Array([Vector2(10, 3), Vector2(10, 12), Vector2(23, 12), Vector2(23, 3)]))
			lines.append(PackedVector2Array([Vector2(10, 19), Vector2(24, 19), Vector2(24, 29), Vector2(10, 29), Vector2(10, 19)]))
		"load":
			lines.append(PackedVector2Array([Vector2(4, 9), Vector2(13, 9), Vector2(16, 13), Vector2(28, 13), Vector2(28, 27), Vector2(4, 27), Vector2(4, 9)]))
			lines.append(PackedVector2Array([Vector2(16, 4), Vector2(16, 21)]))
			lines.append(PackedVector2Array([Vector2(10, 15), Vector2(16, 21), Vector2(22, 15)]))
		"settings":
			var gear := PackedVector2Array()
			for i: int in range(17):
				var radius := 13.0 if i % 2 == 0 else 10.5
				gear.append(Vector2(16, 16) + Vector2.from_angle(TAU * i / 16.0) * radius)
			lines.append(gear)
			var hub := PackedVector2Array()
			for i: int in range(25):
				hub.append(Vector2(16, 16) + Vector2.from_angle(TAU * i / 24.0) * 4.5)
			lines.append(hub)
		"exit":
			lines.append(PackedVector2Array([Vector2(15, 5), Vector2(5, 5), Vector2(5, 27), Vector2(15, 27)]))
			lines.append(PackedVector2Array([Vector2(12, 16), Vector2(29, 16)]))
			lines.append(PackedVector2Array([Vector2(22, 9), Vector2(29, 16), Vector2(22, 23)]))
		"log":
			lines.append(PackedVector2Array([Vector2(7, 3), Vector2(25, 3), Vector2(25, 29), Vector2(7, 29), Vector2(7, 3)]))
			for y: int in [10, 16, 22]:
				lines.append(PackedVector2Array([Vector2(11, y), Vector2(21, y)]))
		"clock":
			var clock_face := PackedVector2Array()
			for i: int in range(33):
				clock_face.append(Vector2(16, 16) + Vector2.from_angle(TAU * i / 32.0) * 13.0)
			lines.append(clock_face)
			lines.append(PackedVector2Array([Vector2(16, 7), Vector2(16, 17), Vector2(23, 21)]))
		"general":
			lines.append(PackedVector2Array([Vector2(12, 3), Vector2(20, 3), Vector2(20, 11), Vector2(27, 27), Vector2(5, 27), Vector2(12, 11), Vector2(12, 3)]))
			lines.append(PackedVector2Array([Vector2(9, 20), Vector2(23, 20)]))
		"status":
			var head := PackedVector2Array()
			for i: int in range(25):
				head.append(Vector2(16, 9) + Vector2.from_angle(TAU * float(i) / 24.0) * 6.0)
			lines.append(head)
			lines.append(PackedVector2Array([Vector2(5, 29), Vector2(6, 23), Vector2(10, 18), Vector2(16, 16), Vector2(22, 18), Vector2(26, 23), Vector2(27, 29), Vector2(5, 29)]))
		"health":
			lines.append(PackedVector2Array([Vector2(16, 28), Vector2(5, 17), Vector2(4, 10), Vector2(8, 5), Vector2(13, 5), Vector2(16, 9), Vector2(19, 5), Vector2(24, 5), Vector2(28, 10), Vector2(27, 17), Vector2(16, 28)]))
			lines.append(PackedVector2Array([Vector2(16, 11), Vector2(16, 21)]))
			lines.append(PackedVector2Array([Vector2(11, 16), Vector2(21, 16)]))
		"stamina":
			var stamina_head := PackedVector2Array()
			for i: int in range(17):
				stamina_head.append(Vector2(20, 6) + Vector2.from_angle(TAU * float(i) / 16.0) * 3.0)
			lines.append(stamina_head)
			lines.append(PackedVector2Array([Vector2(18, 10), Vector2(13, 15), Vector2(18, 18), Vector2(23, 14)]))
			lines.append(PackedVector2Array([Vector2(14, 15), Vector2(9, 22), Vector2(3, 25)]))
			lines.append(PackedVector2Array([Vector2(18, 18), Vector2(14, 24), Vector2(20, 29)]))
		"sleep":
			lines.append(PackedVector2Array([Vector2(22, 3), Vector2(15, 5), Vector2(10, 10), Vector2(8, 17), Vector2(10, 24), Vector2(16, 28), Vector2(23, 27), Vector2(28, 22), Vector2(20, 22), Vector2(15, 18), Vector2(13, 11), Vector2(16, 6), Vector2(22, 3)]))
		"medical":
			solids.append(_box(Vector2(12, 3), Vector2(8, 26)))
			solids.append(_box(Vector2(3, 12), Vector2(26, 8)))
		"bandage":
			lines.append(PackedVector2Array([Vector2(4, 20), Vector2(20, 4), Vector2(28, 12), Vector2(12, 28), Vector2(4, 20)]))
			for center: Vector2 in [Vector2(13, 15), Vector2(17, 19), Vector2(11, 21), Vector2(21, 11)]:
				var hole := PackedVector2Array()
				for i: int in range(13):
					hole.append(center + Vector2.from_angle(TAU * float(i) / 12.0) * 1.2)
				lines.append(hole)
		"bleeding":
			lines.append(PackedVector2Array([Vector2(16, 2), Vector2(8, 14), Vector2(7, 20), Vector2(10, 26), Vector2(16, 29), Vector2(22, 26), Vector2(25, 20), Vector2(24, 14), Vector2(16, 2)]))
			lines.append(PackedVector2Array([Vector2(12, 21), Vector2(14, 24), Vector2(18, 25)]))
		"infection":
			var germ := PackedVector2Array()
			for i: int in range(33):
				var germ_angle: float = TAU * float(i) / 32.0
				germ.append(Vector2(16, 16) + Vector2(cos(germ_angle) * 9.0, sin(germ_angle) * 7.0))
			lines.append(germ)
			for ray: PackedVector2Array in [PackedVector2Array([Vector2(16, 3), Vector2(16, 8)]), PackedVector2Array([Vector2(16, 24), Vector2(16, 29)]), PackedVector2Array([Vector2(3, 16), Vector2(7, 16)]), PackedVector2Array([Vector2(25, 16), Vector2(29, 16)]), PackedVector2Array([Vector2(7, 7), Vector2(10, 10)]), PackedVector2Array([Vector2(22, 22), Vector2(26, 26)]), PackedVector2Array([Vector2(25, 7), Vector2(22, 10)]), PackedVector2Array([Vector2(10, 22), Vector2(7, 25)])]:
				lines.append(ray)
			for center: Vector2 in [Vector2(12, 14), Vector2(19, 13), Vector2(17, 19)]:
				solids.append(_box(center - Vector2.ONE, Vector2(2, 2)))
		"fracture":
			lines.append(PackedVector2Array([Vector2(5, 8), Vector2(8, 5), Vector2(12, 8), Vector2(18, 14), Vector2(14, 18), Vector2(8, 12), Vector2(5, 13), Vector2(2, 10), Vector2(5, 8)]))
			lines.append(PackedVector2Array([Vector2(18, 18), Vector2(24, 24), Vector2(27, 23), Vector2(30, 26), Vector2(27, 29), Vector2(24, 26), Vector2(20, 23), Vector2(14, 18)]))
			lines.append(PackedVector2Array([Vector2(14, 13), Vector2(18, 17), Vector2(15, 19), Vector2(19, 22)]))
		"burn":
			lines.append(PackedVector2Array([Vector2(17, 2), Vector2(10, 11), Vector2(11, 17), Vector2(6, 14), Vector2(5, 21), Vector2(9, 27), Vector2(16, 30), Vector2(23, 27), Vector2(27, 21), Vector2(25, 14), Vector2(20, 8), Vector2(19, 16), Vector2(15, 12), Vector2(17, 2)]))
			lines.append(PackedVector2Array([Vector2(16, 17), Vector2(12, 22), Vector2(14, 27), Vector2(19, 25), Vector2(20, 21), Vector2(16, 17)]))
		"temperature":
			var bulb_circle := PackedVector2Array()
			for i: int in range(25):
				bulb_circle.append(Vector2(13, 24) + Vector2.from_angle(TAU * float(i) / 24.0) * 5.0)
			lines.append(bulb_circle)
			lines.append(PackedVector2Array([Vector2(10, 20), Vector2(10, 6), Vector2(12, 3), Vector2(15, 3), Vector2(17, 6), Vector2(17, 20)]))
			lines.append(PackedVector2Array([Vector2(13.5, 9), Vector2(13.5, 24)]))
			for y: int in [8, 13, 18]:
				lines.append(PackedVector2Array([Vector2(20, y), Vector2(28, y)]))
		"antibiotics":
			lines.append(PackedVector2Array([Vector2(11, 3), Vector2(21, 3), Vector2(21, 8), Vector2(24, 11), Vector2(24, 29), Vector2(8, 29), Vector2(8, 11), Vector2(11, 8), Vector2(11, 3)]))
			lines.append(PackedVector2Array([Vector2(8, 15), Vector2(24, 15)]))
			lines.append(PackedVector2Array([Vector2(13, 20), Vector2(19, 20)]))
			lines.append(PackedVector2Array([Vector2(16, 17), Vector2(16, 23)]))
		"splint":
			lines.append(PackedVector2Array([Vector2(7, 4), Vector2(12, 4), Vector2(12, 28), Vector2(7, 28), Vector2(7, 4)]))
			lines.append(PackedVector2Array([Vector2(20, 4), Vector2(25, 4), Vector2(25, 28), Vector2(20, 28), Vector2(20, 4)]))
			for y: int in [9, 16, 23]:
				lines.append(PackedVector2Array([Vector2(12, y), Vector2(20, y)]))
		"trauma":
			lines.append(PackedVector2Array([Vector2(4, 10), Vector2(28, 10), Vector2(28, 28), Vector2(4, 28), Vector2(4, 10)]))
			lines.append(PackedVector2Array([Vector2(11, 10), Vector2(11, 5), Vector2(21, 5), Vector2(21, 10)]))
			solids.append(_box(Vector2(13, 14), Vector2(6, 10)))
			solids.append(_box(Vector2(11, 16), Vector2(10, 6)))
		"overview":
			lines.append(PackedVector2Array([Vector2(4, 27), Vector2(28, 27)]))
			lines.append(PackedVector2Array([Vector2(7, 24), Vector2(7, 15)]))
			lines.append(PackedVector2Array([Vector2(13, 24), Vector2(13, 8)]))
			lines.append(PackedVector2Array([Vector2(19, 24), Vector2(19, 12)]))
			lines.append(PackedVector2Array([Vector2(25, 24), Vector2(25, 4)]))
		"talk":
			var bubble := PackedVector2Array()
			for i: int in range(25):
				var angle: float = TAU * float(i) / 24.0
				bubble.append(Vector2(15, 14) + Vector2(cos(angle) * 12.0, sin(angle) * 9.0))
			lines.append(bubble)
			lines.append(PackedVector2Array([Vector2(8, 21), Vector2(5, 29), Vector2(14, 23)]))
		"requests":
			lines.append(PackedVector2Array([Vector2(8, 6), Vector2(24, 6), Vector2(27, 29), Vector2(5, 29), Vector2(8, 6)]))
			lines.append(PackedVector2Array([Vector2(12, 3), Vector2(20, 3), Vector2(21, 9), Vector2(11, 9), Vector2(12, 3)]))
			for y: int in [15, 21]:
				lines.append(PackedVector2Array([Vector2(10, y), Vector2(22, y)]))
		"relationship":
			var person_a := PackedVector2Array()
			var person_b := PackedVector2Array()
			for i: int in range(17):
				var angle: float = TAU * float(i) / 16.0
				person_a.append(Vector2(10, 9) + Vector2.from_angle(angle) * 4.0)
				person_b.append(Vector2(22, 9) + Vector2.from_angle(angle) * 4.0)
			lines.append(person_a)
			lines.append(person_b)
			lines.append(PackedVector2Array([Vector2(3, 28), Vector2(4, 22), Vector2(8, 17), Vector2(13, 17), Vector2(16, 21)]))
			lines.append(PackedVector2Array([Vector2(16, 21), Vector2(19, 17), Vector2(24, 17), Vector2(28, 22), Vector2(29, 28)]))
		"mood":
			var face := PackedVector2Array()
			for i: int in range(33):
				face.append(Vector2(16, 16) + Vector2.from_angle(TAU * float(i) / 32.0) * 13.0)
			lines.append(face)
			solids.append(_box(Vector2(10, 11), Vector2(2, 2)))
			solids.append(_box(Vector2(20, 11), Vector2(2, 2)))
			lines.append(PackedVector2Array([Vector2(9, 20), Vector2(12, 23), Vector2(16, 24), Vector2(20, 23), Vector2(23, 20)]))
		"skills":
			lines.append(PackedVector2Array([Vector2(4, 28), Vector2(28, 28)]))
			for data: Array in [[7, 19], [13, 12], [19, 22], [25, 7]]:
				var x: float = float(data[0])
				var top: float = float(data[1])
				lines.append(PackedVector2Array([Vector2(x, 28), Vector2(x, top), Vector2(x + 3, top)]))
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
