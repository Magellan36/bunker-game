extends Control
class_name InteractionPromptChrome
## A deliberately restrained polish layer for world prompts.
##
## The prompt remains a small world-space label. This node only adds a short,
## one-shot full-edge bloom when a target first becomes visible. It never
## leaves a persistent rail/partial outline beside the input glyph and never
## competes with specialised prompts such as CookingPot previews.

const BLUE: Color = Color(0.36, 0.73, 0.96, 1.0)
const BLOOM_SECONDS: float = 0.18

var _bloom: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func trigger_acquire() -> void:
	_bloom = 1.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_bloom = maxf(0.0, _bloom - delta / BLOOM_SECONDS)
	queue_redraw()
	if _bloom <= 0.0:
		set_process(false)


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0 or _bloom <= 0.0:
		return

	# Acquisition feedback is a single 180 ms COMPLETE outline flash. No idle
	# rail, half-border, pulsing, bouncing, or scanning animation remains.
	var eased: float = _bloom * _bloom
	var bloom_color: Color = Color(BLUE.r, BLUE.g, BLUE.b, 0.34 * eased)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), bloom_color, false, 1.0, true)
