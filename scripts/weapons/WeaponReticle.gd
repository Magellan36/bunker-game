extends Control
## Small aim-only reticle; no input capture or changes to the shared HUD.
var aim_position: Vector2
var rounds: String = ""
var hit_time: float = 0.0
var empty: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func _process(delta: float) -> void:
	hit_time = maxf(0.0, hit_time - delta)
	if visible:
		queue_redraw()

func _draw() -> void:
	var color := Color(1.0, 0.84, 0.63, 0.95) if empty else Color(0.9, 0.96, 1.0, 0.9)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(aim_position + direction * 5, aim_position + direction * 10, Color(0, 0, 0, 0.65), 3, true)
		draw_line(aim_position + direction * 5, aim_position + direction * 10, color, 1, true)
	if hit_time > 0.0:
		for direction: Vector2 in [Vector2(-1,-1), Vector2(1,-1), Vector2(-1,1), Vector2(1,1)]:
			draw_line(aim_position + direction * 12, aim_position + direction * 16, Color(1, 0.85, 0.5, hit_time / 0.15), 1.5, true)
	if not rounds.is_empty():
		draw_string(ThemeDB.fallback_font, aim_position + Vector2(15, 24), rounds, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
