extends CanvasLayer
## LoadingScreen.gd (Sep 2026)
## Approved full-screen transition between Character Creation and MainWorld.
## The presentation is intentionally quiet and architectural; the loading
## contract remains the important part: MainWorld is instantiated beneath this
## layer and is not revealed until its startup_ready signal fires.

const WORLD_PATH: String = "res://scenes/world/MainWorld.tscn"
const MIN_DISPLAY_SEC: float = 0.75
const COLUMN_WIDTH: float = 660.0
const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const FONT_BOLD: FontFile = preload("res://assets/fonts/IosevkaCharon-Bold.ttf")
const TIPS: Array[String] = [
	"Keep generators fueled and the grid balanced.",
	"Purify collected water before relying on it.",
	"Leave room around vital systems for repairs and expansion.",
	"Wires and pipes must reach the correct connection points.",
	"A prepared bunker keeps spare food, water, fuel, and medicine.",
]

const S: GDScript = preload("res://scripts/ui/common/BunkerPanelStyle.gd")
const C: GDScript = preload("res://scripts/ui/common/BunkerUIComponents.gd")
const FADE: GDScript = preload("res://scripts/ui/common/UIFade.gd")
const NAV_SCRIPT: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const INDICATOR_SCRIPT: GDScript = preload("res://scripts/ui/loading/LoadingIndicator.gd")

var _root: Control = null
var _content: Control = null
var _column: VBoxContainer = null
var _tip_column: VBoxContainer = null
var _wordmark: Label = null
var _wordmark_font: FontVariation = null
var _subtitle_label: Label = null
var _tip_eyebrow: Label = null
var _tip_label: Label = null
var _indicator: Control = null
var _retry_button: Button = null
var _elapsed: float = 0.0
var _loaded: PackedScene = null
var _swapping: bool = false
var _finishing: bool = false
var _load_failed: bool = false
var _world: Node = null


func _ready() -> void:
	# MainWorld performs preview-pool and world warmup beneath this layer. Keep
	# the transition above every HUD until that work explicitly reports ready.
	layer = 1000
	_build_ui()
	get_viewport().size_changed.connect(_layout_content)
	_layout_content()
	FADE.fade_in(_root, 0.22)
	_request_world_load()


func _process(delta: float) -> void:
	_elapsed += delta
	if _load_failed or _swapping:
		return

	var progress: Array = []
	var status: int = ResourceLoader.load_threaded_get_status(WORLD_PATH, progress)
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			if _loaded == null:
				_loaded = ResourceLoader.load_threaded_get(WORLD_PATH) as PackedScene
				if _loaded == null:
					_show_failure("The bunker world could not be created.")
					return
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# Returning from a live world (game over → reload): the world scene
			# can already be cached, which leaves no threaded task to collect.
			# Use the cached resource instead of failing.
			if _loaded == null and ResourceLoader.has_cached(WORLD_PATH):
				_loaded = load(WORLD_PATH) as PackedScene
			if _loaded == null:
				_show_failure("The bunker world could not be loaded.")
				return

	if _loaded != null and _elapsed >= MIN_DISPLAY_SEC:
		_swapping = true
		_begin_world_startup()


func _request_world_load() -> void:
	_load_failed = false
	_swapping = false
	_finishing = false
	_loaded = null
	_elapsed = 0.0
	_subtitle_label.text = "Preparing your shelter"
	_tip_eyebrow.text = "SURVIVAL TIP"
	_tip_eyebrow.add_theme_color_override("font_color", Q.HEADING)
	_tip_label.text = TIPS[int(randi() % TIPS.size())]
	_retry_button.visible = false
	_indicator.call("set_failed", false)
	var request_error: Error = ResourceLoader.load_threaded_request(WORLD_PATH)
	if request_error != OK:
		_show_failure("The bunker world could not be queued for loading.")


func _begin_world_startup() -> void:
	# change_scene_to_packed() would remove this layer before MainWorld's _ready
	# and asynchronous preview warmup. Instantiate manually and retain the screen
	# until MainWorld signals that the playable world is genuinely ready.
	_subtitle_label.text = "Bringing bunker systems online"
	_world = _loaded.instantiate()
	if _world == null:
		_show_failure("The bunker world could not be created.")
		return
	get_tree().root.add_child(_world)
	if _world.has_signal("startup_ready"):
		_world.startup_ready.connect(_finish_world_startup, CONNECT_ONE_SHOT)
	else:
		call_deferred("_finish_world_startup")


func _finish_world_startup() -> void:
	if _finishing or _world == null or not is_instance_valid(_world):
		return
	_finishing = true
	var slot: int = WorldManager.pending_load_slot
	if slot > 0:
		# Continue/Load from the main menu: restore the save into the freshly
		# started world while this screen still covers it.
		WorldManager.pending_load_slot = 0
		_subtitle_label.text = "Restoring your shelter"
		await get_tree().process_frame
		if not SaveManager.load_game(slot):
			push_warning("LoadingScreen: save slot %d could not be restored." % slot)
	_subtitle_label.text = "Shelter ready"
	FADE.fade_out(_root, 0.18, Callable(self, "_complete_world_handoff"))


func _complete_world_handoff() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	get_tree().current_scene = _world
	queue_free()


func _show_failure(detail: String) -> void:
	_load_failed = true
	_swapping = false
	_subtitle_label.text = "Loading interrupted"
	_tip_eyebrow.text = "SHELTER UNAVAILABLE"
	_tip_eyebrow.add_theme_color_override("font_color", BunkerDesign.RED)
	_tip_label.text = detail + " Check the game log, then try again."
	_retry_button.visible = true
	_retry_button.grab_focus()
	_indicator.call("set_failed", true)
	push_error("LoadingScreen: " + detail)


func _layout_content() -> void:
	if _content == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var s: float = clampf(minf(viewport_size.y / 1080.0, viewport_size.x / 1920.0 * 1.15), 0.66, 1.4)
	var left: float = clampf(viewport_size.x * 0.085, 48.0 * s, 420.0 * s)
	_content.position = Vector2.ZERO
	_content.size = viewport_size
	_column.position = Vector2(left, viewport_size.y * 0.36)
	_column.size = Vector2(COLUMN_WIDTH * s, 0.0)
	_tip_column.position = Vector2(left, viewport_size.y - 150.0 * s)
	_tip_column.size = Vector2(COLUMN_WIDTH * s, 0.0)
	_fit_wordmark(COLUMN_WIDTH * s, s)


## Largest wordmark (up to 96 px @1080p) that fits the column, tracked like
## the main menu's.
func _fit_wordmark(max_width: float, s: float) -> void:
	var font_size: int = roundi(96.0 * s)
	while font_size > roundi(40.0 * s):
		_wordmark_font.spacing_glyph = roundi(font_size * 0.15)
		if _wordmark_font.get_string_size("BUNKER GAME", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			break
		font_size -= 2
	_wordmark.add_theme_font_size_override("font_size", font_size)


## Sep 2026 quiet pass: the main-menu language — near-black field, a
## left-weighted column (wordmark, brass rule, stage line, hairline progress)
## and one quiet survival tip at the bottom left. No ornaments or icons.
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "LoadingPresentation"
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	C.apply_theme(_root)

	var field := ColorRect.new()
	field.name = "Field"
	field.color = Color("0b0f0e")
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(field)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_content = Control.new()
	_content.name = "LoadingContent"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_content)

	_column = VBoxContainer.new()
	_column.name = "ContentColumn"
	_column.add_theme_constant_override("separation", 0)
	_content.add_child(_column)
	_wordmark_font = FontVariation.new()
	_wordmark_font.base_font = FONT_BOLD
	_wordmark = Q.label("BUNKER GAME", 96, Q.TEXT)
	_wordmark.name = "BrandTitle"
	_wordmark.add_theme_font_override("font", _wordmark_font)
	_column.add_child(_wordmark)
	var rule_holder := Control.new()
	rule_holder.custom_minimum_size.y = 24.0
	rule_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(rule_holder)
	var rule := ColorRect.new()
	rule.color = BunkerDesign.BRASS
	rule.position = Vector2(4.0, 8.0)
	rule.size = Vector2(56.0, 2.0)
	rule_holder.add_child(rule)
	_subtitle_label = Q.label("Preparing your shelter", 19, Q.MUTED)
	_subtitle_label.name = "LoadingStage"
	_column.add_child(_subtitle_label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 26.0
	_column.add_child(gap)
	_indicator = INDICATOR_SCRIPT.new()
	_indicator.name = "IndeterminateLoadingIndicator"
	_column.add_child(_indicator)

	_tip_column = VBoxContainer.new()
	_tip_column.name = "SurvivalTip"
	_tip_column.add_theme_constant_override("separation", 6)
	_content.add_child(_tip_column)
	_tip_eyebrow = Q.eyebrow("Survival tip", 12)
	_tip_column.add_child(_tip_eyebrow)
	_tip_label = Q.label(TIPS[0], 17, Color(Q.TEXT, 0.86))
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_column.add_child(_tip_label)
	_retry_button = Button.new()
	_retry_button.name = "RetryLoading"
	_retry_button.text = "Try again"
	_retry_button.visible = false
	_retry_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	Q.primary_action(_retry_button, 15, 40.0)
	_retry_button.pressed.connect(_request_world_load)
	_tip_column.add_child(_retry_button)

	var navigation: ControllerUINavigation = NAV_SCRIPT.new() as ControllerUINavigation
	navigation.mouse_cursor_required = false
	navigation.ui_root = _root
	navigation.close_on_cancel = false
	navigation.stick_navigation = false
	_root.add_child(navigation)

func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
