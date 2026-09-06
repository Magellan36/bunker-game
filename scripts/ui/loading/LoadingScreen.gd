extends CanvasLayer
## LoadingScreen.gd (Sep 2026)
## Approved full-screen transition between Character Creation and MainWorld.
## The presentation is intentionally quiet and architectural; the loading
## contract remains the important part: MainWorld is instantiated beneath this
## layer and is not revealed until its startup_ready signal fires.

const WORLD_PATH: String = "res://scenes/world/MainWorld.tscn"
const MIN_DISPLAY_SEC: float = 0.75
const CONTENT_SIZE: Vector2 = Vector2(760.0, 720.0)
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
const BACKDROP_SCRIPT: GDScript = preload("res://scripts/ui/loading/LoadingBackdropArt.gd")
const INDICATOR_SCRIPT: GDScript = preload("res://scripts/ui/loading/LoadingIndicator.gd")

var _root: Control = null
var _content: Control = null
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
	_tip_label.text = detail + " Check the game log, then try again."
	_retry_button.visible = true
	_retry_button.grab_focus()
	_indicator.call("set_failed", true)
	push_error("LoadingScreen: " + detail)


func _layout_content() -> void:
	if _content == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var fit_scale: float = minf(viewport_size.x / 1920.0, viewport_size.y / 1080.0)
	fit_scale = clampf(fit_scale, 0.64, 1.0)
	_content.size = CONTENT_SIZE
	_content.scale = Vector2.ONE * fit_scale
	_content.position = (viewport_size - CONTENT_SIZE * fit_scale) * 0.5


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "LoadingPresentation"
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	C.apply_theme(_root)

	var backdrop: Control = BACKDROP_SCRIPT.new()
	backdrop.name = "ArchitecturalBackdrop"
	_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_content = Control.new()
	_content.name = "LoadingContent"
	_content.custom_minimum_size = CONTENT_SIZE
	_root.add_child(_content)

	var column := VBoxContainer.new()
	column.name = "ContentColumn"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	_content.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	column.add_child(_ornament())
	column.add_child(_spacer(20.0))

	var logo_center := CenterContainer.new()
	logo_center.custom_minimum_size.y = 138.0
	column.add_child(logo_center)
	var logo := TextureRect.new()
	logo.name = "ShelterMark"
	logo.custom_minimum_size = Vector2(132.0, 132.0)
	logo.texture = S.icon("shelter")
	logo.self_modulate = S.BLUE
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_center.add_child(logo)

	column.add_child(_spacer(2.0))
	var title := Label.new()
	title.name = "BrandTitle"
	title.text = "BUNKER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 78)
	title.add_theme_color_override("font_color", S.IVORY)
	column.add_child(title)

	column.add_child(_spacer(2.0))
	_subtitle_label = Label.new()
	_subtitle_label.name = "LoadingStage"
	_subtitle_label.text = "Preparing your shelter"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 25)
	_subtitle_label.add_theme_color_override("font_color", S.MUTED)
	column.add_child(_subtitle_label)

	column.add_child(_spacer(22.0))
	var indicator_margin := MarginContainer.new()
	indicator_margin.add_theme_constant_override("margin_left", 30)
	indicator_margin.add_theme_constant_override("margin_right", 30)
	column.add_child(indicator_margin)
	_indicator = INDICATOR_SCRIPT.new()
	_indicator.name = "IndeterminateLoadingIndicator"
	indicator_margin.add_child(_indicator)

	column.add_child(_spacer(32.0))
	column.add_child(_build_tip_card())
	column.add_child(_spacer(30.0))
	column.add_child(_ornament())

	var navigation: ControllerUINavigation = NAV_SCRIPT.new() as ControllerUINavigation
	navigation.ui_root = _root
	navigation.close_on_cancel = false
	navigation.stick_navigation = true
	_root.add_child(navigation)


func _build_tip_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "SurvivalTipCard"
	card.custom_minimum_size = Vector2(700.0, 170.0)
	card.add_theme_stylebox_override("panel", C.panel_box(
		Color("151b1af5"), S.BRASS.darkened(0.08), 10, 1, 0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)

	var icon_center := CenterContainer.new()
	icon_center.custom_minimum_size.x = 92.0
	row.add_child(icon_center)
	var tip_icon := TextureRect.new()
	tip_icon.custom_minimum_size = Vector2(76.0, 76.0)
	tip_icon.texture = S.icon("tip")
	tip_icon.self_modulate = S.BLUE
	tip_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(tip_icon)

	var divider := VSeparator.new()
	divider.add_theme_constant_override("separation", 1)
	row.add_child(divider)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 8)
	row.add_child(copy)

	_tip_eyebrow = Label.new()
	_tip_eyebrow.text = "SURVIVAL TIP"
	_tip_eyebrow.add_theme_font_size_override("font_size", 13)
	_tip_eyebrow.add_theme_color_override("font_color", S.BLUE)
	copy.add_child(_tip_eyebrow)

	_tip_label = Label.new()
	_tip_label.text = TIPS[0]
	_tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_size_override("font_size", 23)
	_tip_label.add_theme_color_override("font_color", S.IVORY)
	copy.add_child(_tip_label)

	_retry_button = Button.new()
	_retry_button.name = "RetryLoading"
	_retry_button.text = "Try again"
	_retry_button.custom_minimum_size = Vector2(170.0, 44.0)
	_retry_button.visible = false
	S.icon_button(_retry_button, "undo", true)
	_retry_button.pressed.connect(_request_world_load)
	copy.add_child(_retry_button)
	return card


func _ornament() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 22.0
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var left := ColorRect.new()
	left.color = S.BRASS.darkened(0.18)
	left.custom_minimum_size.y = 1.0
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var diamond := Label.new()
	diamond.text = "◆"
	diamond.add_theme_font_size_override("font_size", 12)
	diamond.add_theme_color_override("font_color", S.BRASS)
	diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(diamond)
	var right := ColorRect.new()
	right.color = S.BRASS.darkened(0.18)
	right.custom_minimum_size.y = 1.0
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	return row


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
