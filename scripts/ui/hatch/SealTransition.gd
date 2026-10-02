extends CanvasLayer
## SealTransition.gd (Oct 2026)
## The moment the player leaves through the Surface Hatch (archetype D, the
## same language as the new-game survivor selection): the bunker fades to
## black, the world pauses, BunkerPhase.seal() runs behind the black (shop
## closed, build locked, survivors brought in at the ladder, clock reset to
## Day 1), a short message names who came in, and the black lifts on Day 1.
##
## Copy here is functional and flagged for Brannon to rewrite
## (docs/systems/phase/README.md "Copy").

signal finished

const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")

const LAYER: int = 1001
const EYEBROW_TEXT: String = "Day 1"
const TITLE_TEXT: String = "The hatch is sealed."
## Motion (seconds). Black falls a little slower than it lifts back, so the
## seal reads as a decision and the reveal as a breath.
const BLACK_IN: float = 0.9
const TEXT_IN: float = 0.6
const HOLD: float = 2.6
const TEXT_OUT: float = 0.6
const REVEAL: float = 1.4

var phase: BunkerPhase = null

var _s: float = 1.0
var _black: ColorRect
var _column: VBoxContainer
var _eyebrow: Label
var _title: Label
var _rule: ColorRect
var _line: Label


## Starts the seal. Returns the running transition.
static func play(tree: SceneTree, bunker_phase: BunkerPhase) -> CanvasLayer:
	var script: GDScript = load("res://scripts/ui/hatch/SealTransition.gd")
	var t: CanvasLayer = script.new()
	t.set("phase", bunker_phase)
	tree.root.add_child(t)
	return t


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_run()


## Freed early (quit, tests): never leave the game paused.
func _exit_tree() -> void:
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


func _build() -> void:
	_black = ColorRect.new()
	_black.name = "Black"
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_STOP   ## nothing reaches the world
	_black.modulate.a = 0.0
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", 0)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.modulate.a = 0.0
	add_child(_column)
	C.apply_theme(_column)
	_eyebrow = Q.eyebrow(EYEBROW_TEXT)
	_eyebrow.name = "Eyebrow"
	_column.add_child(_eyebrow)
	_title = Q.label(TITLE_TEXT, 40, Q.TEXT)
	_title.name = "Title"
	_column.add_child(_title)
	var rule_holder := Control.new()
	rule_holder.custom_minimum_size.y = 22.0
	_column.add_child(rule_holder)
	_rule = ColorRect.new()
	_rule.color = Color(Q.HEADING, 0.85)
	_rule.position = Vector2(2.0, 10.0)
	_rule.size = Vector2(0.0, 1.0)
	rule_holder.add_child(_rule)
	_line = Q.label("", 16, Q.MUTED)
	_line.name = "Line"
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_line)


func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_s = clampf(minf(vp.y / 1080.0, vp.x / 1920.0 * 1.15), 0.66, 1.4)
	_title.add_theme_font_size_override("font_size", maxi(12, int(round(40.0 * _s))))
	_eyebrow.add_theme_font_size_override("font_size", maxi(12, int(round(12.0 * _s))))
	_line.add_theme_font_size_override("font_size", maxi(12, int(round(16.0 * _s))))
	_column.position = Vector2(vp.x * 0.085, vp.y * 0.42)
	_column.size = Vector2(minf(720.0 * _s, vp.x * 0.8), 0.0)


func _run() -> void:
	var reduced: bool = UIMotion.reduced()
	var t := create_tween()
	t.tween_property(_black, "modulate:a", 1.0, 0.0 if reduced else BLACK_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(_seal_behind_black)
	t.tween_property(_column, "modulate:a", 1.0, 0.0 if reduced else TEXT_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_rule, "size:x", 56.0 * _s, 0.0 if reduced else 0.7) \
		.set_delay(0.0 if reduced else 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_interval(HOLD)   ## readable even with reduced motion
	t.tween_property(_column, "modulate:a", 0.0, 0.0 if reduced else TEXT_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void: get_tree().paused = false)
	t.tween_property(_black, "modulate:a", 0.0, 0.0 if reduced else REVEAL) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void:
		finished.emit()
		queue_free())


## Runs once the screen is fully black: the rules change where nobody sees
## residents pop in or the clock jump.
func _seal_behind_black() -> void:
	get_tree().paused = true
	var arrived: Array[Node] = []
	if phase != null and is_instance_valid(phase):
		arrived = phase.seal()
	var names: Array[String] = []
	for npc: Node in arrived:
		names.append(String(npc.get("npc_name")))
	_line.text = arrival_text(names)


## "Mara, Finch and Ode came in with you." / "It's just you." (flagged copy)
static func arrival_text(names: Array[String]) -> String:
	if names.is_empty():
		return "It's just you."
	if names.size() == 1:
		return "%s came in with you." % names[0]
	return "%s and %s came in with you." % [", ".join(names.slice(0, names.size() - 1)), names[-1]]
