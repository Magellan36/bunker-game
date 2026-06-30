extends VBoxContainer
## StatusBars.gd
## Draws the health and stamina bars procedurally.
## Attach to: the Bars VBoxContainer inside BottomLeft.

@export var bar_width: float  = 160.0
@export var bar_height: float = 10.0
@export var bar_gap: float    = 6.0

# Health bar
var _health: float  = 1.0
# Stamina bar
var _stamina: float = 1.0

const COLOR_HEALTH:       Color = Color(0.85, 0.18, 0.18, 1.0)   # Red
const COLOR_HEALTH_BG:    Color = Color(0.20, 0.06, 0.06, 0.85)
const COLOR_STAMINA:      Color = Color(0.18, 0.45, 0.90, 1.0)   # Blue
const COLOR_STAMINA_BG:   Color = Color(0.06, 0.10, 0.22, 0.85)
const COLOR_PANEL:        Color = Color(0.08, 0.08, 0.08, 0.75)
const COLOR_LABEL:        Color = Color(0.75, 0.75, 0.75, 0.9)

func _ready() -> void:
	custom_minimum_size = Vector2(bar_width + 20, (bar_height + bar_gap) * 2 + 20)

func set_health(v: float) -> void:
	_health = clampf(v, 0.0, 1.0)
	queue_redraw()

func set_stamina(v: float) -> void:
	_stamina = clampf(v, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var panel_h: float = (bar_height + bar_gap) * 2 + 20
	# Background panel
	draw_rect(Rect2(0, 0, bar_width + 20, panel_h), COLOR_PANEL, true)

	_draw_bar(Vector2(10, 8),  _health,  COLOR_HEALTH_BG,  COLOR_HEALTH,  "HP")
	_draw_bar(Vector2(10, 8 + bar_height + bar_gap), _stamina, COLOR_STAMINA_BG, COLOR_STAMINA, "ST")

func _draw_bar(pos: Vector2, fill: float, bg: Color, fg: Color, lbl: String) -> void:
	# Background
	draw_rect(Rect2(pos, Vector2(bar_width, bar_height)), bg, true)
	# Fill
	draw_rect(Rect2(pos, Vector2(bar_width * fill, bar_height)), fg, true)
	# Label
	var font: Font = load("res://assets/fonts/IosevkaCharon-Regular.ttf")
	draw_string(font, pos + Vector2(3, bar_height - 2), lbl,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_LABEL)
