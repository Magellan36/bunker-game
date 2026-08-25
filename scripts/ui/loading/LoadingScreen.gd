extends CanvasLayer
## LoadingScreen.gd (Aug 2026)
## Lightweight loading screen shown between Character Creation and the
## bunker world. Threaded-loads MainWorld.tscn in the background, draws a
## progress bar + rotating tip, and swaps to the world after a fixed
## MIN_DISPLAY_SEC so it never flashes too fast. The world's synchronous
## _ready() work (bunker generation, manager wiring, and the build-mode
## preview prebuild that MainWorld kicks off) all runs behind this screen.

const WORLD_PATH: String = "res://scenes/world/MainWorld.tscn"
## Fixed minimum display time so the screen always reads as intentional
## (a .tscn's threaded progress can sit at ~0 until it pops to loaded).
const MIN_DISPLAY_SEC: float = 1.2
## Loading tips, cycled on a timer while the screen shows.
const TIPS: Array[String] = [
	"Keep generators fueled and the grid balanced.",
	"Purify water before you drink it.",
	"Expand the bunker by digging into the rock.",
	"Wires and pipes need to connect to the right nodes.",
]

var _bar: ProgressBar = null
var _tip_label: Label = null
var _elapsed: float = 0.0
var _tip_timer: float = 0.0
var _tip_index: int = 0
var _loaded: PackedScene = null
var _swapping: bool = false

func _ready() -> void:
	_build_ui()
	## Kick off the threaded load — MainWorld.tscn + its sub-resources stream
	## in on a background thread while this screen draws.
	ResourceLoader.load_threaded_request(WORLD_PATH)

func _process(delta: float) -> void:
	_elapsed += delta
	_tip_timer -= delta
	if _tip_timer <= 0.0:
		_tip_timer = 2.5
		_tip_index = (_tip_index + 1) % TIPS.size()
		_tip_label.text = TIPS[_tip_index]

	## Real load progress (0..1), plus a time-based ramp so the bar completes
	## visually in sync with MIN_DISPLAY_SEC even before the load reports done.
	var prog: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(WORLD_PATH, prog)
	if status == ResourceLoader.THREAD_LOAD_LOADED and _loaded == null:
		_loaded = ResourceLoader.load_threaded_get(WORLD_PATH) as PackedScene
	var real_pct: float = (prog[0] if not prog.is_empty() else 0.0) * 100.0
	_bar.value = maxf(real_pct, _elapsed / MIN_DISPLAY_SEC * 100.0)

	if _loaded != null and _elapsed >= MIN_DISPLAY_SEC and not _swapping:
		_swapping = true
		get_tree().change_scene_to_packed(_loaded)

func _build_ui() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	## Backdrop — near-black, same family as Build Mode's banner.
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.07, 0.08, 1.0)
	root.add_child(bg)

	var center_wrap: CenterContainer = CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center_wrap)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	center_wrap.add_child(vbox)

	## Title — teal accent, matching Build Mode's identity color.
	var title: Label = Label.new()
	title.text = "BUNKER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIKit.font())
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.251, 0.443, 0.435, 1.0))
	vbox.add_child(title)

	var sub: Label = Label.new()
	sub.text = "PREPARING THE SHELTER"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", UIKit.font())
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.60, 0.62, 0.65, 1.0))
	vbox.add_child(sub)

	## Progress bar — dark groove + teal fill, matching the game's aesthetic.
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(320.0, 12.0)
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	var groove: StyleBoxFlat = StyleBoxFlat.new()
	groove.bg_color = Color(0.10, 0.12, 0.14, 1.0)
	groove.set_corner_radius_all(3)
	groove.set_border_width_all(1)
	groove.border_color = Color(0.25, 0.27, 0.30, 1.0)
	_bar.add_theme_stylebox_override("background", groove)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color(0.251, 0.443, 0.435, 1.0)
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	vbox.add_child(_bar)

	_tip_label = Label.new()
	_tip_label.text = TIPS[0]
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_tip_label.custom_minimum_size = Vector2(380.0, 0.0)
	_tip_label.add_theme_font_override("font", UIKit.font())
	_tip_label.add_theme_font_size_override("font_size", 12)
	_tip_label.add_theme_color_override("font_color", Color(0.50, 0.52, 0.55, 0.90))
	vbox.add_child(_tip_label)