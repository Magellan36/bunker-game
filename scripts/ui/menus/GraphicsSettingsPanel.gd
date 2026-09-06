extends CanvasLayer
## Graphics settings workspace.
##
## Presentation deliberately mirrors the approved PauseMenuUI: a fixed,
## 1080p-safe desktop shell, a sturdy navigation rail, a divided content
## workspace, and a persistent input-hint footer. All settings still apply
## through the existing GraphicsSettings autoload; this file owns UI only.

const PANEL_MAX := Vector2(1240, 760)
const PANEL_MARGIN := Vector2(56, 42)
const RAIL_WIDTH: float = 284.0
const CONTROL_WIDTH: float = 280.0
const SECTION_KEYS: Array[String] = ["display", "rendering", "effects", "camera"]

const AA_OPTIONS: Array[Dictionary] = [
	{"label": "Off", "msaa": Viewport.MSAA_DISABLED, "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": false},
	{"label": "Fast (FXAA)", "msaa": Viewport.MSAA_DISABLED, "screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA, "use_taa": false},
	{"label": "Balanced (MSAA 2x)", "msaa": Viewport.MSAA_2X, "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": false},
	{"label": "Sharp (MSAA 2x + FXAA)", "msaa": Viewport.MSAA_2X, "screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA, "use_taa": false},
	{"label": "Smooth (TAA)", "msaa": Viewport.MSAA_DISABLED, "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": true},
	{"label": "Max (MSAA 4x + TAA)", "msaa": Viewport.MSAA_4X, "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": true},
]

const PRESET_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra", "Custom"]
const AA_LABELS: Array[String] = ["Off", "Fast (FXAA)", "Balanced (MSAA 2x)", "Sharp (MSAA 2x + FXAA)", "Smooth (TAA)", "Max (MSAA 4x + TAA)"]
const WINDOW_MODE_LABELS: Array[String] = ["Windowed", "Borderless Fullscreen", "Exclusive Fullscreen"]
const WINDOW_MODE_VALUES: Array[int] = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
const RESOLUTION_LABELS: Array[String] = ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"]
const RESOLUTION_VALUES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const FPS_CAP_LABELS: Array[String] = ["Uncapped", "30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS", "240 FPS"]
const FPS_CAP_VALUES: Array[int] = [0, 30, 60, 90, 120, 144, 240]
const RENDERING_DRIVER_LABELS: Array[String] = ["Vulkan", "Direct3D 12"]
const RENDERING_DRIVER_VALUES: Array[String] = ["vulkan", "d3d12"]
const ANISO_LABELS: Array[String] = ["Off", "2×", "4×", "8×", "16×"]
const ANISO_VALUES: Array[int] = [0, 2, 4, 8, 16]
const SHADOW_QUALITY_LABELS: Array[String] = ["Low · 1024", "Medium · 2048", "High · 4096", "Ultra · 4096"]
const SHADOW_QUALITY_VALUES: Array[int] = [1024, 2048, 4096, 4096]
const RENDER_SCALE_MIN: float = 0.5
const RENDER_SCALE_MAX: float = 1.0
const RENDER_SCALE_STEP: float = 0.05

var _is_open: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _panel: PanelContainer = null
var _backdrop: ColorRect = null
var _content_scroll: ScrollContainer = null
var _section_buttons: Dictionary = {}
var _section_anchors: Dictionary = {}
var _first_nav_button: Button = null
var _preset_state: Label = null
var _render_scale_value: Label = null
var _fov_value: Label = null

var _preset_option: OptionButton = null
var _window_mode_option: OptionButton = null
var _resolution_option: OptionButton = null
var _vsync_check: CheckButton = null
var _fps_cap_option: OptionButton = null
var _rendering_driver_option: OptionButton = null
var _aa_option: OptionButton = null
var _aniso_option: OptionButton = null
var _shadow_quality_option: OptionButton = null
var _render_scale_slider: HSlider = null
var _sdfgi_check: CheckButton = null
var _ssao_check: CheckButton = null
var _ssil_check: CheckButton = null
var _vol_fog_check: CheckButton = null
var _glow_check: CheckButton = null
var _dof_check: CheckButton = null
var _vol_check: CheckButton = null
var _shadow_check: CheckButton = null
var _dr_check: CheckButton = null
var _fov_slider: HSlider = null

var _restart_confirm_dialog: ConfirmDialogUI = null
var _restart_driver_connected: bool = false
var _pending_restart_driver: String = ""


func _ready() -> void:
	layer = 210
	_build_ui()
	visible = false
	var controller_nav: ControllerUINavigation = ControllerUINavigation.new()
	controller_nav.ui_root = self
	controller_nav.stick_navigation = true
	controller_nav.close_on_cancel = true
	add_child(controller_nav)
	get_viewport().size_changed.connect(_layout)
	_layout()


func open() -> void:
	if not _is_open:
		_previous_mouse_mode = Input.mouse_mode
	_is_open = true
	visible = true
	_refresh_from_settings()
	_content_scroll.scroll_vertical = 0
	_update_section_buttons("display")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIFade.fade_in(_panel)
	_first_nav_button.call_deferred("grab_focus")


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	## Controller/keyboard slider adjustments do not emit drag_ended, so close
	## is the final persistence boundary for any live-only slider changes.
	GraphicsSettings.save_now()
	if _restart_confirm_dialog != null and is_instance_valid(_restart_confirm_dialog):
		_restart_confirm_dialog.close()
	Input.mouse_mode = _previous_mouse_mode


func is_open() -> bool:
	return _is_open


func _build_ui() -> void:
	_backdrop = UIKit.build_modal_backdrop()
	add_child(_backdrop)
	_backdrop.gui_input.connect(_on_backdrop_input)

	_panel = PanelContainer.new()
	_panel.name = "GraphicsSettingsShell"
	BunkerUIComponents.apply_theme(_panel)
	BunkerUIComponents.shell(_panel, 10)
	add_child(_panel)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(BunkerUIComponents.inset(outer, 18, 16, 18, 12))

	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	outer.add_child(columns)
	columns.add_child(_build_navigation_rail())

	var separator: VSeparator = VSeparator.new()
	columns.add_child(separator)

	var workspace_holder: MarginContainer = MarginContainer.new()
	workspace_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_holder.add_theme_constant_override("margin_left", 8)
	columns.add_child(workspace_holder)
	workspace_holder.add_child(_build_workspace())

	BunkerUIComponents.divider(outer)
	outer.add_child(_build_footer())


func _build_navigation_rail() -> Control:
	var rail: VBoxContainer = VBoxContainer.new()
	rail.name = "GraphicsNavigationRail"
	rail.custom_minimum_size.x = RAIL_WIDTH
	rail.add_theme_constant_override("separation", 9)

	var brand: HBoxContainer = HBoxContainer.new()
	brand.add_theme_constant_override("separation", 9)
	var bunker_icon: TextureRect = TextureRect.new()
	bunker_icon.texture = BunkerPanelStyle.icon("storage")
	bunker_icon.self_modulate = BunkerPanelStyle.BLUE
	bunker_icon.custom_minimum_size = Vector2(40, 40)
	bunker_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bunker_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand.add_child(bunker_icon)
	var bunker_label: Label = Label.new()
	bunker_label.text = "BUNKER"
	bunker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bunker_label.add_theme_font_size_override("font_size", 18)
	bunker_label.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	brand.add_child(bunker_label)
	rail.add_child(brand)

	var settings_label: Label = Label.new()
	settings_label.text = "SETTINGS"
	settings_label.add_theme_font_size_override("font_size", 42)
	settings_label.add_theme_color_override("font_color", BunkerPanelStyle.IVORY)
	rail.add_child(settings_label)

	var nav_caption: Label = Label.new()
	nav_caption.text = "GRAPHICS SECTIONS"
	nav_caption.add_theme_font_size_override("font_size", 11)
	nav_caption.add_theme_color_override("font_color", BunkerPanelStyle.MUTED)
	rail.add_child(nav_caption)

	_first_nav_button = _section_button("Display", "general", "display")
	rail.add_child(_first_nav_button)
	rail.add_child(_section_button("Rendering", "settings", "rendering"))
	rail.add_child(_section_button("Effects", "power", "effects"))
	rail.add_child(_section_button("Camera", "search", "camera"))

	var live_panel: PanelContainer = PanelContainer.new()
	live_panel.add_theme_stylebox_override("panel", BunkerUIComponents.status_style(true))
	var live_row: HBoxContainer = HBoxContainer.new()
	live_row.add_theme_constant_override("separation", 10)
	live_panel.add_child(live_row)
	var live_icon: TextureRect = TextureRect.new()
	live_icon.texture = BunkerPanelStyle.icon("check")
	live_icon.self_modulate = BunkerPanelStyle.GREEN
	live_icon.custom_minimum_size = Vector2(28, 28)
	live_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	live_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	live_row.add_child(live_icon)
	var live_copy: VBoxContainer = VBoxContainer.new()
	live_copy.add_theme_constant_override("separation", 0)
	live_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_row.add_child(live_copy)
	var live_title: Label = Label.new()
	live_title.text = "LIVE SETTINGS"
	live_title.add_theme_font_size_override("font_size", 12)
	live_title.add_theme_color_override("font_color", BunkerPanelStyle.GREEN)
	live_copy.add_child(live_title)
	var live_detail: Label = Label.new()
	live_detail.text = "Changes apply immediately"
	BunkerPanelStyle.muted(live_detail, 12)
	live_copy.add_child(live_detail)
	rail.add_child(live_panel)

	var grow: Control = Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(grow)

	var back_button: Button = Button.new()
	back_button.text = "Back to Pause"
	back_button.custom_minimum_size.y = 54
	BunkerPanelStyle.icon_button(back_button, "arrow")
	back_button.pressed.connect(close)
	rail.add_child(back_button)
	return rail


func _section_button(caption: String, symbol: String, section_key: String) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.icon = BunkerPanelStyle.icon(symbol)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 52
	BunkerUIComponents.style_segment(button)
	button.pressed.connect(_jump_to_section.bind(section_key))
	_section_buttons[section_key] = button
	return button


func _build_workspace() -> Control:
	var workspace: VBoxContainer = VBoxContainer.new()
	workspace.name = "GraphicsWorkspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 10)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	workspace.add_child(header)
	header.add_child(BunkerUIComponents.icon_well("settings", 52.0))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 1)
	header.add_child(titles)
	var eyebrow: Label = Label.new()
	eyebrow.text = "GRAPHICS SETTINGS"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	titles.add_child(eyebrow)
	var title: Label = Label.new()
	title.text = "Display & quality"
	BunkerPanelStyle.title(title, 28)
	titles.add_child(title)
	var description: Label = Label.new()
	description.text = "Tune image quality, performance, effects, and camera comfort."
	BunkerPanelStyle.muted(description, 13)
	titles.add_child(description)

	workspace.add_child(_build_preset_card())

	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "SettingsScroll"
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.follow_focus = true
	workspace.add_child(_content_scroll)

	var content: VBoxContainer = VBoxContainer.new()
	content.name = "SettingsContent"
	content.custom_minimum_size.x = 790
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	_content_scroll.add_child(content)

	_build_display_section(content)
	_build_rendering_section(content)
	_build_effects_section(content)
	_build_camera_section(content)
	_content_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	return workspace


func _build_preset_card() -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.name = "QualityPresetCard"
	card.custom_minimum_size.y = 86
	card.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(
		Color("172328"), BunkerPanelStyle.BLUE.darkened(0.24), 9, 1, 12))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var icon: TextureRect = TextureRect.new()
	icon.texture = BunkerPanelStyle.icon("condition")
	icon.self_modulate = BunkerPanelStyle.BLUE
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	var title: Label = Label.new()
	title.text = "Quality preset"
	BunkerPanelStyle.title(title, 20)
	copy.add_child(title)
	_preset_state = Label.new()
	_preset_state.text = "Balanced baseline"
	BunkerPanelStyle.muted(_preset_state, 12)
	copy.add_child(_preset_state)
	_preset_option = _make_option(PRESET_NAMES)
	_preset_option.tooltip_text = "Choose a complete quality baseline. Adjusting an individual quality setting creates a Custom preset."
	_preset_option.set_item_disabled(GraphicsSettings.Preset.CUSTOM, true)
	_preset_option.item_selected.connect(_on_preset_selected)
	row.add_child(_preset_option)
	return card


func _build_display_section(parent: VBoxContainer) -> void:
	var section: VBoxContainer = _section(parent, "display", "DISPLAY", "Window and frame delivery")
	_window_mode_option = _make_option(WINDOW_MODE_LABELS)
	_window_mode_option.item_selected.connect(_on_window_mode_changed)
	section.add_child(_setting_card("Window mode", "Choose windowed, borderless, or exclusive fullscreen presentation.", _window_mode_option))
	_resolution_option = _make_option(RESOLUTION_LABELS)
	_resolution_option.item_selected.connect(_on_resolution_changed)
	section.add_child(_setting_card("Resolution", "Available while Windowed mode is active.", _resolution_option))
	_vsync_check = _make_switch(_on_vsync_toggled)
	section.add_child(_setting_card("Vertical sync", "Prevents visible screen tearing by matching display refresh.", _vsync_check))
	_fps_cap_option = _make_option(FPS_CAP_LABELS)
	_fps_cap_option.item_selected.connect(_on_fps_cap_changed)
	section.add_child(_setting_card("Frame-rate cap", "Limit GPU load and frame delivery, or leave uncapped.", _fps_cap_option))


func _build_rendering_section(parent: VBoxContainer) -> void:
	var section: VBoxContainer = _section(parent, "rendering", "RENDERING", "Core image quality")
	_rendering_driver_option = _make_option(RENDERING_DRIVER_LABELS)
	_rendering_driver_option.item_selected.connect(_on_rendering_driver_changed)
	section.add_child(_setting_card("Rendering driver", "Low-level renderer. Changing this setting requires a restart.", _rendering_driver_option, true))
	_aa_option = _make_option(AA_LABELS)
	_aa_option.item_selected.connect(_on_aa_changed)
	section.add_child(_setting_card("Anti-aliasing", "Smooth jagged object edges using a performance-quality profile.", _aa_option))
	_aniso_option = _make_option(ANISO_LABELS)
	_aniso_option.item_selected.connect(_on_aniso_changed)
	section.add_child(_setting_card("Texture filtering", "Keeps surfaces sharper when viewed from an angle.", _aniso_option))
	_shadow_quality_option = _make_option(SHADOW_QUALITY_LABELS)
	_shadow_quality_option.item_selected.connect(_on_shadow_quality_changed)
	section.add_child(_setting_card("Shadow quality", "Controls shadow-map detail and memory use.", _shadow_quality_option))
	_render_scale_slider = HSlider.new()
	_render_scale_slider.min_value = RENDER_SCALE_MIN
	_render_scale_slider.max_value = RENDER_SCALE_MAX
	_render_scale_slider.step = RENDER_SCALE_STEP
	_style_slider(_render_scale_slider)
	_render_scale_slider.value_changed.connect(_on_render_scale_changed)
	_render_scale_slider.drag_ended.connect(_on_render_scale_drag_ended)
	_render_scale_value = _value_label("100%")
	section.add_child(_setting_card("Render scale", "Render the 3D world below native resolution to improve performance.", _slider_control(_render_scale_slider, _render_scale_value)))


func _build_effects_section(parent: VBoxContainer) -> void:
	var section: VBoxContainer = _section(parent, "effects", "EFFECTS", "Lighting, atmosphere, and performance safeguards")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	section.add_child(grid)
	_sdfgi_check = _make_switch(_on_sdfgi_toggled)
	grid.add_child(_effect_card("Real-time GI", "Dynamic bounced light throughout the bunker.", _sdfgi_check))
	_ssao_check = _make_switch(_on_ssao_toggled)
	grid.add_child(_effect_card("Ambient occlusion", "Adds grounding shadows around nearby surfaces.", _ssao_check))
	_ssil_check = _make_switch(_on_ssil_toggled)
	grid.add_child(_effect_card("Indirect lighting", "Adds screen-space bounced-light detail.", _ssil_check))
	_vol_fog_check = _make_switch(_on_vol_fog_toggled)
	grid.add_child(_effect_card("Volumetric fog", "Enables atmospheric depth and light scattering.", _vol_fog_check))
	_glow_check = _make_switch(_on_glow_toggled)
	grid.add_child(_effect_card("Glow & bloom", "Lets bright lights gently spill into nearby pixels.", _glow_check))
	_dof_check = _make_switch(_on_dof_toggled)
	grid.add_child(_effect_card("Depth of field", "Adds cinematic focus blur where supported.", _dof_check))
	_shadow_check = _make_switch(_on_shadow_toggled)
	grid.add_child(_effect_card("Dynamic shadows", "Allows placed lights to cast nearby shadows.", _shadow_check))
	_dr_check = _make_switch(_on_dr_toggled)
	_dr_check.tooltip_text = "Automatically lowers render resolution when frame rate drops and restores it once performance recovers. Render Scale remains the quality ceiling."
	grid.add_child(_effect_card("Dynamic resolution", "Lowers resolution temporarily to protect frame rate.", _dr_check))
	_vol_check = _make_switch(_on_vol_toggled)
	grid.add_child(_effect_card("Flashlight beams", "Enables volumetric light inside flashlight beams.", _vol_check))


func _build_camera_section(parent: VBoxContainer) -> void:
	var section: VBoxContainer = _section(parent, "camera", "CAMERA", "View comfort")
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 45.0
	_fov_slider.max_value = 75.0
	_fov_slider.step = 1.0
	_style_slider(_fov_slider)
	_fov_slider.value_changed.connect(_on_fov_changed)
	_fov_slider.drag_ended.connect(_on_fov_drag_ended)
	_fov_value = _value_label("60°")
	section.add_child(_setting_card("Camera field of view", "Adjust the visible scene area without changing the quality preset.", _slider_control(_fov_slider, _fov_value)))
	var bottom_space: Control = Control.new()
	bottom_space.custom_minimum_size.y = 4
	section.add_child(bottom_space)


func _section(parent: VBoxContainer, section_key: String, title_text: String, meta_text: String) -> VBoxContainer:
	var section: VBoxContainer = VBoxContainer.new()
	section.name = title_text.capitalize().replace(" ", "") + "Section"
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 8)
	parent.add_child(section)
	_section_anchors[section_key] = section
	BunkerUIComponents.section_header(section, title_text, meta_text)
	return section


func _setting_card(title_text: String, description_text: String, control: Control, warning: bool = false) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size.y = 74
	var edge_color: Color = BunkerPanelStyle.BRASS.darkened(0.35)
	if warning:
		edge_color = BunkerPanelStyle.BRASS.lightened(0.08)
	card.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(Color("1b211f"), edge_color, 8, 1, 11))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	var title: Label = Label.new()
	title.text = title_text
	BunkerPanelStyle.title(title, 17)
	copy.add_child(title)
	var description: Label = Label.new()
	description.text = description_text
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BunkerPanelStyle.muted(description, 12)
	copy.add_child(description)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, CONTROL_WIDTH)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return card


func _effect_card(title_text: String, description_text: String, toggle: CheckButton) -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(385, 92)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", BunkerUIComponents.panel_box(Color("1b211f"), BunkerPanelStyle.BRASS.darkened(0.38), 8, 1, 10))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)
	var title: Label = Label.new()
	title.text = title_text
	BunkerPanelStyle.title(title, 16)
	copy.add_child(title)
	var description: Label = Label.new()
	description.text = description_text
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 190
	BunkerPanelStyle.muted(description, 11)
	copy.add_child(description)
	toggle.custom_minimum_size.x = 106
	row.add_child(toggle)
	return card


func _make_option(labels: Array[String]) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.custom_minimum_size = Vector2(CONTROL_WIDTH, 46)
	option.alignment = HORIZONTAL_ALIGNMENT_LEFT
	for label_text: String in labels:
		option.add_item(label_text)
	BunkerPanelStyle.button(option)
	return option


func _make_switch(callback: Callable) -> CheckButton:
	var toggle: CheckButton = CheckButton.new()
	toggle.text = "OFF"
	toggle.custom_minimum_size = Vector2(118, 46)
	toggle.alignment = HORIZONTAL_ALIGNMENT_CENTER
	BunkerPanelStyle.button(toggle)
	toggle.add_theme_stylebox_override("pressed", BunkerUIComponents.panel_box(BunkerPanelStyle.BLUE_DARK, BunkerPanelStyle.BLUE, 7, 2, 6))
	toggle.add_theme_stylebox_override("hover_pressed", BunkerUIComponents.panel_box(BunkerPanelStyle.BLUE_DARK.lightened(0.06), BunkerPanelStyle.BLUE, 7, 2, 6))
	toggle.toggled.connect(func(pressed: bool) -> void:
		toggle.text = "ON" if pressed else "OFF")
	toggle.toggled.connect(callback)
	return toggle


func _style_slider(slider: HSlider) -> void:
	slider.custom_minimum_size = Vector2(220, 34)
	slider.focus_mode = Control.FOCUS_ALL
	slider.add_theme_stylebox_override("slider", BunkerUIComponents.panel_box(Color("111615"), BunkerPanelStyle.BRASS.darkened(0.42), 5, 1))
	slider.add_theme_stylebox_override("grabber_area", BunkerUIComponents.panel_box(BunkerPanelStyle.BLUE_DARK, BunkerPanelStyle.BLUE.darkened(0.25), 5, 1))
	slider.add_theme_stylebox_override("grabber_area_highlight", BunkerUIComponents.panel_box(BunkerPanelStyle.BLUE_DARK.lightened(0.07), BunkerPanelStyle.BLUE, 5, 1))


func _slider_control(slider: HSlider, value_label: Label) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.x = CONTROL_WIDTH
	row.add_theme_constant_override("separation", 10)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _value_label(initial_text: String) -> Label:
	var label: Label = Label.new()
	label.text = initial_text
	label.custom_minimum_size.x = 52
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", BunkerPanelStyle.BLUE)
	return label


func _build_footer() -> Control:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 24)
	BunkerUIComponents.key_hint(footer, "A / ENTER", "Select")
	BunkerUIComponents.key_hint(footer, "D-PAD / R-STICK", "Navigate")
	BunkerUIComponents.key_hint(footer, "SCROLLBAR", "Scroll")
	BunkerUIComponents.key_hint(footer, "B / ESC", "Back")
	return footer


func _layout() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var safe_width: float = maxf(640.0, viewport_size.x - PANEL_MARGIN.x * 2.0)
	var safe_height: float = maxf(480.0, viewport_size.y - PANEL_MARGIN.y * 2.0)
	var panel_size: Vector2 = Vector2(minf(PANEL_MAX.x, safe_width), minf(PANEL_MAX.y, safe_height))
	_panel.position = (viewport_size - panel_size) * 0.5
	_panel.size = panel_size


func _jump_to_section(section_key: String) -> void:
	var anchor: Control = _section_anchors.get(section_key) as Control
	if anchor == null:
		return
	_update_section_buttons(section_key)
	_content_scroll.ensure_control_visible(anchor)


func _on_scroll_changed(scroll_value: float) -> void:
	var active_key: String = "display"
	for section_key: String in SECTION_KEYS:
		var anchor: Control = _section_anchors.get(section_key) as Control
		if anchor != null and anchor.position.y <= scroll_value + 52.0:
			active_key = section_key
	_update_section_buttons(active_key)


func _update_section_buttons(active_key: String) -> void:
	for section_key: String in _section_buttons:
		var button: Button = _section_buttons[section_key] as Button
		button.set_pressed_no_signal(section_key == active_key)


func _refresh_from_settings() -> void:
	_refresh_preset_display()
	_select_if_valid(_window_mode_option, WINDOW_MODE_VALUES.find(GraphicsSettings.window_mode))
	var resolution_index: int = RESOLUTION_VALUES.find(DisplayServer.window_get_size())
	_select_if_valid(_resolution_option, resolution_index)
	_resolution_option.disabled = GraphicsSettings.window_mode != DisplayServer.WINDOW_MODE_WINDOWED
	_set_switch(_vsync_check, GraphicsSettings.vsync_enabled)
	_select_if_valid(_fps_cap_option, FPS_CAP_VALUES.find(GraphicsSettings.fps_cap))
	_select_if_valid(_rendering_driver_option, RENDERING_DRIVER_VALUES.find(GraphicsSettings.rendering_driver))
	for i: int in AA_OPTIONS.size():
		var option_data: Dictionary = AA_OPTIONS[i]
		var option_msaa: int = int(option_data.get("msaa", Viewport.MSAA_DISABLED))
		var option_screen_aa: int = int(option_data.get("screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED))
		var option_taa: bool = bool(option_data.get("use_taa", false))
		if option_msaa == GraphicsSettings.msaa and option_screen_aa == GraphicsSettings.screen_space_aa and option_taa == GraphicsSettings.use_taa:
			_aa_option.select(i)
			break
	_select_if_valid(_aniso_option, ANISO_VALUES.find(GraphicsSettings.anisotropic_filtering))
	_select_if_valid(_shadow_quality_option, SHADOW_QUALITY_VALUES.find(GraphicsSettings.shadow_quality))
	_render_scale_slider.set_value_no_signal(GraphicsSettings.render_scale)
	_render_scale_value.text = "%d%%" % roundi(GraphicsSettings.render_scale * 100.0)
	_set_switch(_sdfgi_check, GraphicsSettings.sdfgi_enabled)
	_set_switch(_ssao_check, GraphicsSettings.ssao_enabled)
	_set_switch(_ssil_check, GraphicsSettings.ssil_enabled)
	_set_switch(_vol_fog_check, GraphicsSettings.volumetric_fog_enabled)
	_set_switch(_glow_check, GraphicsSettings.glow_enabled)
	_set_switch(_dof_check, GraphicsSettings.dof_enabled)
	_set_switch(_vol_check, GraphicsSettings.flashlight_volumetrics)
	_set_switch(_shadow_check, GraphicsSettings.shadow_casting_enabled)
	_set_switch(_dr_check, GraphicsSettings.dynamic_resolution_enabled)
	_fov_slider.set_value_no_signal(GraphicsSettings.camera_fov)
	_fov_value.text = "%d°" % roundi(GraphicsSettings.camera_fov)


func _refresh_preset_display() -> void:
	var preset_index: int = GraphicsSettings.current_preset
	if preset_index < 0 or preset_index >= PRESET_NAMES.size():
		preset_index = GraphicsSettings.Preset.CUSTOM
	_preset_option.select(preset_index)
	match preset_index:
		GraphicsSettings.Preset.LOW:
			_preset_state.text = "Maximum performance"
		GraphicsSettings.Preset.MEDIUM:
			_preset_state.text = "Balanced baseline"
		GraphicsSettings.Preset.HIGH:
			_preset_state.text = "Enhanced lighting & detail"
		GraphicsSettings.Preset.ULTRA:
			_preset_state.text = "Maximum visual quality"
		_:
			_preset_state.text = "Individually tuned"


func _select_if_valid(option: OptionButton, index: int) -> void:
	if index >= 0 and index < option.item_count:
		option.select(index)


func _set_switch(toggle: CheckButton, pressed: bool) -> void:
	toggle.set_pressed_no_signal(pressed)
	toggle.text = "ON" if pressed else "OFF"


func _mark_preset_custom() -> void:
	_refresh_preset_display()


func _on_preset_selected(index: int) -> void:
	if index == GraphicsSettings.Preset.CUSTOM:
		return
	GraphicsSettings.apply_preset(index)
	_refresh_from_settings()


func _on_window_mode_changed(index: int) -> void:
	GraphicsSettings.set_setting("window_mode", WINDOW_MODE_VALUES[index])
	_resolution_option.disabled = WINDOW_MODE_VALUES[index] != DisplayServer.WINDOW_MODE_WINDOWED
	_mark_preset_custom()


func _on_resolution_changed(index: int) -> void:
	GraphicsSettings.set_setting("window_mode", DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(RESOLUTION_VALUES[index])
	_window_mode_option.select(WINDOW_MODE_VALUES.find(DisplayServer.WINDOW_MODE_WINDOWED))
	_resolution_option.disabled = false
	_mark_preset_custom()


func _on_vsync_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("vsync_enabled", pressed)
	_mark_preset_custom()


func _on_fps_cap_changed(index: int) -> void:
	GraphicsSettings.set_setting("fps_cap", FPS_CAP_VALUES[index])
	_mark_preset_custom()


func _on_rendering_driver_changed(index: int) -> void:
	var new_driver: String = RENDERING_DRIVER_VALUES[index]
	GraphicsSettings.set_rendering_driver(new_driver)
	if new_driver != GraphicsSettings.session_start_rendering_driver:
		_show_restart_required_dialog(new_driver)


func _on_aa_changed(index: int) -> void:
	var option_data: Dictionary = AA_OPTIONS[index]
	GraphicsSettings.set_setting("msaa", int(option_data.get("msaa", Viewport.MSAA_DISABLED)))
	GraphicsSettings.set_setting("screen_space_aa", int(option_data.get("screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED)))
	GraphicsSettings.set_setting("use_taa", bool(option_data.get("use_taa", false)))
	_mark_preset_custom()


func _on_aniso_changed(index: int) -> void:
	GraphicsSettings.set_setting("anisotropic_filtering", ANISO_VALUES[index])
	_mark_preset_custom()


func _on_shadow_quality_changed(index: int) -> void:
	GraphicsSettings.set_setting("shadow_quality", SHADOW_QUALITY_VALUES[index])
	_mark_preset_custom()


func _show_restart_required_dialog(pending_driver: String) -> void:
	_ensure_restart_confirm_dialog()
	if _restart_confirm_dialog == null:
		return
	_pending_restart_driver = pending_driver
	_restart_confirm_dialog.open(
		"Restart required",
		"Switch the rendering driver to %s and restart the game now?" % pending_driver,
		"Restart now",
		"Not now",
		"warning",
		"settings"
	)
	if not _restart_driver_connected:
		_restart_confirm_dialog.confirmed.connect(func() -> void: _relaunch_with_driver(_pending_restart_driver))
		_restart_driver_connected = true


func _ensure_restart_confirm_dialog() -> void:
	if _restart_confirm_dialog != null and is_instance_valid(_restart_confirm_dialog):
		return
	_restart_confirm_dialog = ConfirmDialogUI.new()
	_restart_confirm_dialog.name = "ConfirmDialogUI"
	_restart_confirm_dialog.stacking_layer = 215
	add_child(_restart_confirm_dialog)


func _relaunch_with_driver(driver: String) -> void:
	_write_override_cfg(driver)
	var executable_path: String = OS.get_executable_path()
	var arguments: PackedStringArray = ["--rendering-driver", driver]
	var process_id: int = OS.create_process(executable_path, arguments)
	if process_id == -1:
		push_error("[GraphicsSettingsPanel] Failed to relaunch with --rendering-driver %s — staying on current session." % driver)
		return
	get_tree().quit()


func _write_override_cfg(driver: String) -> void:
	var executable_directory: String = OS.get_executable_path().get_base_dir()
	var override_path: String = executable_directory.path_join("override.cfg")
	var config: ConfigFile = ConfigFile.new()
	config.load(override_path)
	config.set_value("rendering", "rendering_device/driver.windows", driver)
	var error_code: int = config.save(override_path)
	if error_code != OK:
		push_warning("[GraphicsSettingsPanel] Could not write override.cfg (err %d) — rendering driver choice will only apply via in-app restart, not a plain relaunch." % error_code)


func _on_render_scale_changed(value: float) -> void:
	GraphicsSettings.set_setting_live("render_scale", value)
	_render_scale_value.text = "%d%%" % roundi(value * 100.0)
	_mark_preset_custom()


func _on_render_scale_drag_ended(_value_changed: bool) -> void:
	GraphicsSettings.save_now()


func _on_sdfgi_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("sdfgi_enabled", pressed)
	_mark_preset_custom()


func _on_ssao_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("ssao_enabled", pressed)
	_mark_preset_custom()


func _on_ssil_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("ssil_enabled", pressed)
	_mark_preset_custom()


func _on_vol_fog_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("volumetric_fog_enabled", pressed)
	_mark_preset_custom()


func _on_glow_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("glow_enabled", pressed)
	_mark_preset_custom()


func _on_dof_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("dof_enabled", pressed)
	_mark_preset_custom()


func _on_vol_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("flashlight_volumetrics", pressed)
	_mark_preset_custom()


func _on_shadow_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("shadow_casting_enabled", pressed)
	_mark_preset_custom()


func _on_dr_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("dynamic_resolution_enabled", pressed)


func _on_fov_changed(value: float) -> void:
	GraphicsSettings.set_setting_live("camera_fov", value)
	_fov_value.text = "%d°" % roundi(value)


func _on_fov_drag_ended(_value_changed: bool) -> void:
	GraphicsSettings.save_now()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			close()
			get_viewport().set_input_as_handled()
