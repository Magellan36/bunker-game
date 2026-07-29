extends CanvasLayer
## GraphicsSettingsPanel.gd
## Graphics/quality settings panel — opened from PauseMenuUI's Settings
## button. Built as a real Control node tree in code (same pattern
## PauseMenuUI/BuildModeHUD use), per the "new panels should use Control
## trees, not hand-drawn _draw()" guidance in PROJECT_SUMMARY.md §9.
##
## DEPENDS ON the GraphicsSettings autoload being registered (Project
## Settings > Autoload, name "GraphicsSettings") — will show "Could not
## find type GraphicsSettings" until that's done.
##
## Scope: full graphics overhaul (Phase 0-5). Implements:
##   1. Quality Preset selector (Low/Medium/High/Ultra)
##   2. Display section (Window Mode, Resolution, VSync, FPS Cap)
##   3. Rendering section (AA combo, Anisotropic, Shadow Quality, Render Scale)
##   4. Advanced Quality (SDFGI, SSAO, SSIL, Volumetric Fog, Glow, DOF)
##   5. Flashlight section (Volumetrics, Shadows)
##   6. Camera (FOV)
## All controls follow the shared UIKit theme for visual consistency with
## PauseMenuUI/WaterDispenserUI/PowerTerminalUI.

var interaction_system: Node = null
var inventory: Node = null
var inventory_hud: Node = null

var _panel:         Panel = null
var _vbox:          VBoxContainer = null
var _scroll:        ScrollContainer = null
var _preset_option: OptionButton = null
var _close_btn:     Button = null

## Display
var _window_mode_option: OptionButton = null
var _resolution_option:  OptionButton = null
var _vsync_check:        CheckBox = null
var _fps_cap_option:     OptionButton = null

## Rendering
var _aa_option:          OptionButton = null
var _aniso_option:       OptionButton = null
var _shadow_quality_option: OptionButton = null
var _render_scale_slider: HSlider = null

## Advanced Quality
var _sdfgi_check:          CheckBox = null
var _ssao_check:           CheckBox = null
var _ssil_check:           CheckBox = null
var _vol_fog_check:        CheckBox = null
var _glow_check:           CheckBox = null
var _dof_check:            CheckBox = null

## Flashlight
var _vol_check:            CheckBox = null
var _shadow_check:         CheckBox = null

## Camera
var _fov_slider:           HSlider = null

## AA combo mapping (friendly name -> raw values)
const AA_OPTIONS: Array[Dictionary] = [
	{ "label": "Off",                    "msaa": Viewport.MSAA_DISABLED, "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": false },
	{ "label": "Fast (FXAA)",            "msaa": Viewport.MSAA_DISABLED, "screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA, "use_taa": false },
	{ "label": "Balanced (MSAA 2x)",     "msaa": Viewport.MSAA_2X, "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": false },
	{ "label": "Sharp (MSAA 2x + FXAA)", "msaa": Viewport.MSAA_2X, "screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA, "use_taa": false },
	{ "label": "Smooth (TAA)",           "msaa": Viewport.MSAA_DISABLED, "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": true },
	{ "label": "Max (MSAA 4x + TAA)",    "msaa": Viewport.MSAA_4X, "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": true },
]

const PANEL_W: float = 340.0
const PANEL_MAX_H: float = 520.0
const PANEL_PAD: float = 16.0
const PANEL_RADIUS: float = 4.0
const SECTION_GAP: float = 10.0
const ITEM_GAP: float = 6.0
const PRESET_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]

## AA combo labels in same order as AA_OPTIONS
const AA_LABELS: Array[String] = ["Off", "Fast (FXAA)", "Balanced (MSAA 2x)", "Sharp (MSAA 2x + FXAA)", "Smooth (TAA)", "Max (MSAA 4x + TAA)"]

## Window mode labels (match DisplayServer.WINDOW_MODE_* enum order)
const WINDOW_MODE_LABELS: Array[String] = ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
const WINDOW_MODE_VALUES: Array[int] = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]

## Resolution options (16:9 common)
const RESOLUTION_LABELS: Array[String] = ["1280x720", "1600x900", "1920x1080", "2560x1440"]
const RESOLUTION_VALUES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

## FPS cap options
const FPS_CAP_LABELS: Array[String] = ["Uncapped", "30", "60", "90", "120", "144", "240"]
const FPS_CAP_VALUES: Array[int] = [0, 30, 60, 90, 120, 144, 240]

## Anisotropic filtering options
const ANISO_LABELS: Array[String] = ["Off", "2x", "4x", "8x", "16x"]
const ANISO_VALUES: Array[int] = [0, 2, 4, 8, 16]

## Shadow quality options
const SHADOW_QUALITY_LABELS: Array[String] = ["Low (1024)", "Medium (2048)", "High (4096)", "Ultra (4096)"]
const SHADOW_QUALITY_VALUES: Array[int] = [1024, 2048, 4096, 4096]

## Render scale slider bounds
const RENDER_SCALE_MIN: float = 0.5
const RENDER_SCALE_MAX: float = 1.0
const RENDER_SCALE_STEP: float = 0.05

var inventory: Node = null
var inventory_hud: Node = null

var _panel:         Panel = null
var _scroll:        ScrollContainer = null
var _vbox:          VBoxContainer = nil

var _preset_option: OptionButton = null
var _close_btn:     Button = null

## Display
var _window_mode_option: OptionButton = null
var _resolution_option:  OptionButton = null
var _vsync_check:        CheckBox = null
var _fps_cap_option:     OptionButton = null

## Rendering
var _aa_option:          OptionButton = null
var _aniso_option:       OptionButton = null
var _shadow_quality_option: OptionButton = null
var _render_scale_slider: HSlider = null

## Advanced Quality
var _sdfgi_check:          CheckBox = null
var _ssao_check:           CheckBox = null
var _ssil_check:           CheckBox = null
var _vol_fog_check:        CheckBox = null
var _glow_check:           CheckBox = null
var _dof_check:            CheckBox = null

## Flashlight
var _vol_check:            CheckBox = null
var _shadow_check:         CheckBox = null

## Camera
var _fov_slider:           HSlider = nil

## Close button
var _close_btn: Button = null

func _ready() -> void:
	layer = 210   ## Above PauseMenuUI (layer 200)
	_build_ui()
	visible = false

func open() -> void:
	visible = true
	_refresh_from_settings()
	UIFade.fade_in(_panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	visible = false
	if interaction_system != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_ui() -> void:
	## Blur backdrop (same as PauseMenuUI)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	var blur_shader: Shader = load("res://assets/shaders/pause_blur.gdshader")
	if blur_shader != null:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = blur_shader
		backdrop.material = mat
	add_child(backdrop)

	## Main panel
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_panel.custom_maximum_size = Vector2(PANEL_W, PANEL_MAX_H)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = Color(0.07, 0.07, 0.08, 0.94)
	style.border_color = Color(0.35, 0.35, 0.38, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	## Scroll container (fixed max height so it never runs off-screen)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0.0, 0.0)
	_panel.add_child(_scroll)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vbox.offset_left = 16
	_vbox.offset_right = 16
	_vbox.offset_top = 16
	_vbox.offset_bottom = 16
	_scroll.add_child(_vbox)

	## Title
	var title: Label = Label.new()
	title.text = "GRAPHICS SETTINGS"
	title.add_theme_color_override("font_color", UIKit.theme_for(UIKit.Domain.NEUTRAL).header)
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(title)

	## Scrollable content will be added via _build_content()
	_build_content()

	## Close button at bottom
	var close_btn: Button = _make_button("Close", close)
	_vbox.add_child(close_btn)
	_close_btn = close_btn

	## Apply shared settings theme to the whole panel (so checkboxes, sliders,
	## optionbuttons inherit the dark styling without per-control overrides)
	_panel.theme = UIKit.settings_controls_theme()

	## Wire backdrop click-to-close
	var backdrop: ColorRect = get_child(0)  ## First child is the ColorRect backdrop
	if backdrop:
		backdrop.gui_input.connect(_on_backdrop_input)

## ─── Content builder ──────────────────────────────────────────────────────────
func _build_content() -> void:
	## 1. Quality Preset
	_add_section_header("QUALITY PRESET")
	var preset_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(preset_row)
	var preset_lbl: Label = Label.new()
	preset_lbl.text = "Quality Preset"
	preset_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_row.add_child(preset_lbl)
	_preset_option = OptionButton.new()
	for preset_name: String in PRESET_NAMES:
		_preset_option.add_item(preset_name)
	_preset_option.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_preset_option)

	## 2. Display
	_add_section_header("DISPLAY")
	
	## Window Mode
	var wm_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(wm_row)
	var wm_lbl: Label = Label.new()
	wm_lbl.text = "Window Mode"
	wm_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wm_row.add_child(wm_lbl)
	_window_mode_option = OptionButton.new()
	for lbl: String in WINDOW_MODE_LABELS:
		_window_mode_option.add_item(lbl)
	_window_mode_option.item_selected.connect(_on_window_mode_changed)
	wm_row.add_child(_window_mode_option)

	## Resolution (Windowed only)
	var res_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(res_row)
	var res_lbl: Label = Label.new()
	res_lbl.text = "Resolution"
	res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_row.add_child(res_lbl)
	_resolution_option = OptionButton.new()
	for lbl: String in RESOLUTION_LABELS:
		_resolution_option.add_item(lbl)
	_resolution_option.item_selected.connect(_on_resolution_changed)
	res_row.add_child(_resolution_option)

	## VSync
	var vsync_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(vsync_row)
	var vsync_lbl: Label = Label.new()
	vsync_lbl.text = "VSync"
	vsync_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vsync_row.add_child(vsync_lbl)
	_vsync_check = _make_checkbox("Enabled", _on_vsync_toggled)
	vsync_row.add_child(_vsync_check)

	## FPS Cap
	var fps_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(fps_row)
	var fps_lbl: Label = Label.new()
	fps_lbl.text = "FPS Cap"
	fps_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_row.add_child(fps_lbl)
	_fps_cap_option = OptionButton.new()
	for lbl: String in FPS_CAP_LABELS:
		_fps_cap_option.add_item(lbl)
	_fps_cap_option.item_selected.connect(_on_fps_cap_changed)
	fps_row.add_child(_fps_cap_option)

	## 3. Rendering
	_add_section_header("RENDERING")

	## Anti-Aliasing combo
	var aa_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(aa_row)
	var aa_lbl: Label = Label.new()
	aa_lbl.text = "Anti-Aliasing"
	aa_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aa_row.add_child(aa_lbl)
	_aa_option = OptionButton.new()
	for lbl: String in AA_LABELS:
		_aa_option.add_item(lbl)
	_aa_option.item_selected.connect(_on_aa_changed)
	aa_row.add_child(_aa_option)

	## Anisotropic Filtering
	var aniso_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(aniso_row)
	var aniso_lbl: Label = Label.new()
	aniso_lbl.text = "Anisotropic Filtering"
	aniso_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aniso_row.add_child(aniso_lbl)
	_aniso_option = OptionButton.new()
	for lbl: String in ANISO_LABELS:
		_aniso_option.add_item(lbl)
	_aniso_option.item_selected.connect(_on_aniso_changed)
	aniso_row.add_child(_aniso_option)

	## Shadow Quality
	var shadow_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(shadow_row)
	var shadow_lbl: Label = Label.new()
	shadow_lbl.text = "Shadow Quality"
	shadow_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shadow_row.add_child(shadow_lbl)
	_shadow_quality_option = OptionButton.new()
	for lbl: String in SHADOW_QUALITY_LABELS:
		_shadow_quality_option.add_item(lbl)
	_shadow_quality_option.item_selected.connect(_on_shadow_quality_changed)
	shadow_row.add_child(_shadow_quality_option)

	## Render Scale
	var rs_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(rs_row)
	var rs_lbl: Label = Label.new()
	rs_lbl.text = "Render Scale"
	rs_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs_row.add_child(rs_lbl)
	_render_scale_slider = HSlider.new()
	_render_scale_slider.min_value = RENDER_SCALE_MIN
	_render_scale_slider.max_value = RENDER_SCALE_MAX
	_render_scale_slider.step = RENDER_SCALE_STEP
	_render_scale_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_render_scale_slider.value_changed.connect(_on_render_scale_changed)
	_render_scale_slider.drag_ended.connect(_on_render_scale_drag_ended)
	rs_row.add_child(_render_scale_slider)

	## 4. Advanced Quality
	_add_section_header("ADVANCED QUALITY")
	_sdfgi_check          = _make_checkbox("SDFGI (Real-time GI)", _on_sdfgi_toggled)
	_vbox.add_child(_sdfgi_check)
	_ssao_check           = _make_checkbox("SSAO", _on_ssao_toggled)
	_vbox.add_child(_ssao_check)
	_ssil_check           = _make_checkbox("SSIL (Indirect Lighting)", _on_ssil_toggled)
	_vbox.add_child(_ssil_check)
	_vol_fog_check        = _make_checkbox("Volumetric Fog", _on_vol_fog_toggled)
	_vbox.add_child(_vol_fog_check)
	_glow_check           = _make_checkbox("Glow/Bloom", _on_glow_toggled)
	_vbox.add_child(_glow_check)
	_dof_check            = _make_checkbox("Depth of Field", _on_dof_toggled)
	_vbox.add_child(_dof_check)

	## 5. Flashlight
	_add_section_header("FLASHLIGHT")
	_vol_check            = _make_checkbox("Beam Volumetrics", _on_vol_toggled)
	_vbox.add_child(_vol_check)
	_shadow_check         = _make_checkbox("Shadow Casting (opt-in)", _on_shadow_toggled)
	_vbox.add_child(_shadow_check)

	## 6. Camera
	_add_section_header("CAMERA")
	var fov_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(fov_row)
	var fov_lbl: Label = Label.new()
	fov_lbl.text = "Camera FOV"
	fov_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fov_row.add_child(fov_lbl)
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 60.0
	_fov_slider.max_value = 100.0
	_fov_slider.step = 1.0
	_fov_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_fov_slider.value_changed.connect(_on_fov_changed)
	_fov_slider.drag_ended.connect(_on_fov_drag_ended)
	fov_row.add_child(_fov_slider)

	## Close button
	var close_btn: Button = _make_button("Close", close)
	_vbox.add_child(close_btn)

func _add_section_header(text: String) -> void:
	var sep: HSeparator = HSeparator.new()
	_vbox.add_child(sep)
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58, 1.0))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(lbl)

## ─── Helper: section-aware checkbox maker ──────────────────────────────────
func _make_checkbox(text: String, cb: Callable) -> CheckBox:
	var box: CheckBox = CheckBox.new()
	box.text = text
	box.toggled.connect(cb)
	box.add_theme_font_override("font", UIKit.font())
	return box

func _make_button(text: String, cb: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0.0, 36.0)
	btn.pressed.connect(cb)
	btn.add_theme_font_override("font", UIKit.font())
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.14, 0.16, 1.0)
	sb.border_color = Color(0.28, 0.28, 0.32, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.20, 0.20, 0.23, 1.0)
	btn.add_theme_stylebox_override("hover", hover_sb)
	var pressed_sb: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.pressed.connect(func(): cb.call())
	return btn

## ─── Refresh from live settings ─────────────────────────────────────────────
func _refresh_from_settings() -> void:
	## Preset
	if GraphicsSettings.current_preset != GraphicsSettings.Preset.CUSTOM:
		_preset_option.selected = GraphicsSettings.current_preset

	## Display
	_window_mode_option.selected = WINDOW_MODE_VALUES.find(GraphicsSettings.window_mode)
	_resolution_option.selected = RESOLUTION_VALUES.find(DisplayServer.window_get_size())
	_vsync_check.button_pressed = GraphicsSettings.vsync_enabled
	_fps_cap_option.selected = FPS_CAP_VALUES.find(GraphicsSettings.fps_cap)

	## Rendering
	## AA combo: find matching entry
	for i: int in AA_OPTIONS.size():
		var opt: Dictionary = AA_OPTIONS[i]
		if opt.msaa == GraphicsSettings.msaa and opt.screen_space_aa == GraphicsSettings.screen_space_aa and opt.use_taa == GraphicsSettings.use_taa:
			_aa_option.selected = i
			break

	_aniso_option.selected = ANISO_VALUES.find(GraphicsSettings.anisotropic_filtering)
	_shadow_quality_option.selected = SHADOW_QUALITY_VALUES.find(GraphicsSettings.shadow_quality)
	_render_scale_slider.value = GraphicsSettings.render_scale

	## Advanced Quality
	_sdfgi_check.button_pressed     = GraphicsSettings.sdfgi_enabled
	_ssao_check.button_pressed      = GraphicsSettings.ssao_enabled
	_ssil_check.button_pressed      = GraphicsSettings.ssil_enabled
	_vol_fog_check.button_pressed   = GraphicsSettings.volumetric_fog_enabled
	_glow_check.button_pressed      = GraphicsSettings.glow_enabled
	_dof_check.button_pressed       = GraphicsSettings.dof_enabled

	## Flashlight
	_vol_check.button_pressed       = GraphicsSettings.flashlight_volumetrics
	_shadow_check.button_pressed    = GraphicsSettings.flashlight_shadows

	## Camera
	_fov_slider.value = GraphicsSettings.camera_fov

## ─── Callbacks ────────────────────────────────────────────────────────────────
func _on_preset_selected(index: int) -> void:
	GraphicsSettings.apply_preset(index)
	_refresh_from_settings()

func _on_window_mode_changed(index: int) -> void:
	GraphicsSettings.set_setting("window_mode", WINDOW_MODE_VALUES[index])
	## Resolution only relevant in Windowed mode
	_resolution_option.disabled = (WINDOW_MODE_VALUES[index] != DisplayServer.WINDOW_MODE_WINDOWED)

func _on_resolution_changed(index: int) -> void:
	GraphicsSettings.set_setting("window_mode", DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(RESOLUTION_VALUES[index])

func _on_vsync_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("vsync_enabled", pressed)

func _on_fps_cap_changed(index: int) -> void:
	GraphicsSettings.set_setting("fps_cap", FPS_CAP_VALUES[index])

func _on_aa_changed(index: int) -> void:
	var opt: Dictionary = AA_OPTIONS[index]
	GraphicsSettings.set_setting("msaa", opt.msaa)
	GraphicsSettings.set_setting("screen_space_aa", opt.screen_space_aa)
	GraphicsSettings.set_setting("use_taa", opt.use_taa)

func _on_aniso_changed(index: int) -> void:
	GraphicsSettings.set_setting("anisotropic_filtering", ANISO_VALUES[index])

func _on_shadow_quality_changed(index: int) -> void:
	GraphicsSettings.set_setting("shadow_quality", SHADOW_QUALITY_VALUES[index])

func _on_render_scale_changed(value: float) -> void:
	GraphicsSettings.set_setting_live("render_scale", value)

func _on_render_scale_drag_ended(_value_changed: bool) -> void:
	GraphicsSettings.save_now()

func _on_sdfgi_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("sdfgi_enabled", pressed)

func _on_ssao_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("ssao_enabled", pressed)

func _on_ssil_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("ssil_enabled", pressed)

func _on_vol_fog_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("volumetric_fog_enabled", pressed)

func _on_glow_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("glow_enabled", pressed)

func _on_dof_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("dof_enabled", pressed)

func _on_vol_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("flashlight_volumetrics", pressed)

func _on_shadow_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("flashlight_shadows", pressed)

func _on_fov_changed(value: float) -> void:
	GraphicsSettings.set_setting_live("camera_fov", value)

func _on_fov_drag_ended(_value_changed: bool) -> void:
	GraphicsSettings.save_now()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		get_viewport().set_input_as_handled()

func _make_checkbox(text: String, cb: Callable) -> CheckBox:
	var box: CheckBox = CheckBox.new()
	box.text = text
	box.toggled.connect(cb)
	box.add_theme_font_override("font", UIKit.font())
	return box

func _make_button(text: String, cb: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0.0, 36.0)
	btn.pressed.connect(cb)
	btn.add_theme_font_override("font", UIKit.font())
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.14, 0.16, 1.0)
	sb.border_color = Color(0.28, 0.28, 0.32, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sb)
	var hover_sb: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.20, 0.20, 0.23, 1.0)
	btn.add_theme_stylebox_override("hover", hover_sb)
	var pressed_sb: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	pressed_sb.bg_color = Color(0.12, 0.12, 0.14, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_sb)
	btn.pressed.connect(func(): cb.call())
	return btn