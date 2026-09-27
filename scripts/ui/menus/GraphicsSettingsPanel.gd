extends CanvasLayer
## Graphics settings workspace (Sep 2026 "quiet" polish pass).
##
## Same structure and contracts as before (navigation rail, scrolling
## workspace, footer; every value applies through the GraphicsSettings
## autoload), restyled in the language the main menu introduced: dark,
## text-first, hairline rows instead of bordered cards, one muted steel-blue
## accent, and the shared FocusRail gliding over the focused row.
##
## Polish: segmented quality preset whose underline slides (to "Custom" when
## you adjust anything), animated switches, Left/Right adjusts every value
## (keyboard and d-pad), hover moves focus, eased wheel scrolling and section
## jumps, a contextual one-line hint + cost tag for the focused setting, and
## a quiet "Saved" confirmation. This file owns UI only.

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const FOCUS_RAIL: GDScript = preload("res://scripts/ui/common/FocusRail.gd")
const SMOOTH_SCROLL: GDScript = preload("res://scripts/ui/common/SmoothScroll.gd")
const SEGMENTED: GDScript = preload("res://scripts/ui/common/QuietSegmented.gd")
const FOOTER: GDScript = preload("res://scripts/ui/common/QuietFooter.gd")
const FOCUS: GDScript = preload("res://scripts/ui/common/QuietFocusController.gd")

const PANEL_MAX := Vector2(1240, 760)
const PANEL_MARGIN := Vector2(56, 42)
const RAIL_WIDTH: float = 232.0
const CONTROL_WIDTH: float = 260.0
const TOGGLE_WIDTH: float = 116.0
const ROW_HEIGHT: float = 46.0
const ROW_REST_ALPHA: float = 0.74
const SECTION_KEYS: Array[String] = ["display", "rendering", "effects", "camera"]
const SECTION_TITLES: Dictionary = {
	"display": "Display", "rendering": "Rendering", "effects": "Effects",
	"camera": "Camera & comfort",
}
const IDLE_HINT: String = "Every change applies instantly and is saved for next time."

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
## Sep 2026 lighting review: presets now use Low 2048, Medium/High 4096, Ultra
## 8192 (see GraphicsSettings.SHADOW_ATLAS_QUADRANTS for why), so the labels
## name the tier each size belongs to.
const SHADOW_QUALITY_LABELS: Array[String] = ["Minimum · 512", "Very Low · 1024", "Low · 2048", "Standard · 4096", "Ultra · 8192"]
const SHADOW_QUALITY_VALUES: Array[int] = [512, 1024, 2048, 4096, 8192]
const RENDER_SCALE_MIN: float = 0.5
const RENDER_SCALE_MAX: float = 1.0
const RENDER_SCALE_STEP: float = 0.05

var _is_open: bool = false
## Caption of the rail's return button. Hosts set this before add_child()
## (the main menu uses "Back"; the pause menu keeps the default).
var back_button_text: String = "Back to Pause"
var _previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED
var _panel: PanelContainer = null
var _backdrop: ColorRect = null
var _workspace: Control = null
var _content_scroll: ScrollContainer = null
var _smooth: Node = null
var _row_rail: Control = null
var _nav_rail: Control = null
var _section_buttons: Dictionary = {}
var _section_anchors: Dictionary = {}
var _active_section: String = ""
## Section chosen from the rail; wins over scroll-spy until its jump settles.
var _jump_section: String = ""
var _first_nav_button: Button = null
var _render_scale_value: Label = null
var _fov_value: Label = null
## Shared quiet behaviour (row list, hint line, Saved) — see
## scripts/ui/common/QuietFocusController.gd and QuietFooter.gd.
var _focus: Node = null
var _footer: HBoxContainer = null
var _help_label: Label = null
var _cost_label: Label = null
var _saved_label: Label = null
var _open_tween: Tween = null

var _preset: Control = null
var _preset_buttons: Array[Button] = []
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
var _reduced_motion_check: CheckButton = null

var _restart_confirm_dialog: ConfirmDialogUI = null
var _restart_driver_connected: bool = false
var _pending_restart_driver: String = ""


func _ready() -> void:
	GraphicsSettings.graphics_change_rejected.connect(_on_graphics_change_rejected)
	layer = 210
	_build_ui()
	visible = false
	var controller_nav: ControllerUINavigation = ControllerUINavigation.new()
	controller_nav.ui_root = self
	controller_nav.stick_navigation = false
	controller_nav.close_on_cancel = true
	add_child(controller_nav)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_preset_display()


func open() -> void:
	if not _is_open:
		_previous_mouse_mode = Input.mouse_mode
	UIPanelLifecycle.prepare_open(self)
	_is_open = true
	visible = true
	_refresh_from_settings()
	_content_scroll.scroll_vertical = 0
	_active_section = ""
	_jump_section = ""
	_update_section_buttons("display")
	_nav_rail.call("snap")
	_focus.call("reset")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout()
	_play_open()
	_first_nav_button.call_deferred("grab_focus")


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	## Controller/keyboard slider adjustments do not emit drag_ended, so close
	## is the final persistence boundary for any live-only slider changes.
	GraphicsSettings.save_now()
	if _restart_confirm_dialog != null and is_instance_valid(_restart_confirm_dialog):
		_restart_confirm_dialog.close()
	Input.mouse_mode = _previous_mouse_mode
	if is_instance_valid(_open_tween):
		_open_tween.kill()
	create_tween().tween_property(_backdrop, "modulate:a", 0.0, UIMotion.duration(UIMotion.EXIT))
	UIPanelLifecycle.dismiss(self, _panel)


func is_open() -> bool:
	return _is_open


## Opening: the backdrop dims in, the shell rises a few pixels as it fades,
## and the workspace settles in a beat later.
func _play_open() -> void:
	if is_instance_valid(_open_tween):
		_open_tween.kill()
	UIFade.fade_in(_panel, 0.22)
	if UIMotion.reduced():
		_backdrop.modulate.a = 1.0
		_workspace.modulate.a = 1.0
		return
	var rest_y := _panel.position.y
	_panel.position.y = rest_y + 16.0
	_backdrop.modulate.a = 0.0
	_workspace.modulate.a = 0.0
	_open_tween = create_tween().set_parallel(true)
	_open_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.22)
	_open_tween.tween_property(_panel, "position:y", rest_y, 0.36) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_workspace, "modulate:a", 1.0, 0.28).set_delay(0.07)


# ── Build ────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_focus = FOCUS.new()
	_focus.name = "QuietFocus"
	_focus.set("rest_alpha", ROW_REST_ALPHA)
	_focus.set("row_height", ROW_HEIGHT)
	_focus.set("is_active", func() -> bool: return _is_open)
	add_child(_focus)
	_backdrop = UIKit.build_modal_backdrop()
	add_child(_backdrop)
	_backdrop.gui_input.connect(_on_backdrop_input)

	_panel = PanelContainer.new()
	_panel.name = "GraphicsSettingsShell"
	BunkerUIComponents.apply_theme(_panel)
	_panel.add_theme_stylebox_override("panel", Q.shell_box(12))
	add_child(_panel)
	Q.avoid_toasts(_panel, true)

	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_panel.add_child(BunkerUIComponents.inset(outer, 30, 28, 22, 16))

	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 30)
	outer.add_child(columns)
	columns.add_child(_build_navigation_rail())

	var separator: VSeparator = VSeparator.new()
	separator.add_theme_stylebox_override("separator", Q.hairline(true))
	columns.add_child(separator)

	_workspace = _build_workspace()
	columns.add_child(_workspace)

	var footer_line: HSeparator = HSeparator.new()
	footer_line.add_theme_stylebox_override("separator", Q.hairline())
	footer_line.add_theme_constant_override("separation", 22)
	outer.add_child(footer_line)
	outer.add_child(_build_footer())
	_focus.set("surface", _panel)
	_focus.set("rail", _row_rail)
	_focus.set("smooth", _smooth)
	_focus.set("footer", _footer)


func _build_navigation_rail() -> Control:
	var rail: VBoxContainer = VBoxContainer.new()
	rail.name = "GraphicsNavigationRail"
	rail.custom_minimum_size.x = RAIL_WIDTH
	rail.add_theme_constant_override("separation", 0)

	var brand: Label = Q.eyebrow("Bunker Game", 12)
	brand.name = "Brand"
	rail.add_child(brand)
	rail.add_child(_gap(6.0))
	var title: Label = Q.label("Settings", 40, Q.TEXT)
	title.name = "Title"
	rail.add_child(title)
	rail.add_child(_gap(30.0))

	# The active-section rail glides behind the entries as you scroll.
	var nav_host: Control = Control.new()
	nav_host.name = "SectionLinks"
	nav_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav_host.custom_minimum_size.y = SECTION_KEYS.size() * 36.0
	rail.add_child(nav_host)
	_nav_rail = FOCUS_RAIL.new()
	_nav_rail.name = "ActiveSectionRail"
	_configure_rail(_nav_rail, 0.0, 0.92, 0.07, 0.24)
	nav_host.add_child(_nav_rail)
	_nav_rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var links: VBoxContainer = VBoxContainer.new()
	links.add_theme_constant_override("separation", 6)
	nav_host.add_child(links)
	links.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for section_key: String in SECTION_KEYS:
		var button: Button = _section_button(str(SECTION_TITLES[section_key]), section_key)
		links.add_child(button)
		if _first_nav_button == null:
			_first_nav_button = button

	var grow: Control = Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(grow)

	var back_button: Button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "←   " + back_button_text
	Q.nav_button(back_button, 15)
	back_button.pressed.connect(close)
	rail.add_child(back_button)
	return rail


func _section_button(caption: String, section_key: String) -> Button:
	var button: Button = Button.new()
	button.name = caption.to_pascal_case() + "Link"
	button.text = caption
	Q.nav_button(button, 16)
	button.toggle_mode = true
	button.pressed.connect(_jump_to_section.bind(section_key))
	button.set_meta(&"ui_tab", true)
	button.mouse_entered.connect(func() -> void:
		if not button.has_focus() and InputMode.is_keyboard():
			button.grab_focus())
	_section_buttons[section_key] = button
	return button


func _build_workspace() -> Control:
	var workspace: VBoxContainer = VBoxContainer.new()
	workspace.name = "GraphicsWorkspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 0)
	workspace.add_child(_build_preset_row())
	var line: HSeparator = HSeparator.new()
	line.add_theme_stylebox_override("separator", Q.hairline())
	line.add_theme_constant_override("separation", 18)
	workspace.add_child(line)

	# Clip host: the row rail must be cut off by the scroll viewport exactly
	# like the rows, so it lives beside (behind) the ScrollContainer.
	var clip: Control = Control.new()
	clip.name = "ScrollClip"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_child(clip)
	_row_rail = FOCUS_RAIL.new()
	_row_rail.name = "RowRail"
	_configure_rail(_row_rail, -3.0, 0.62, 0.075, 0.2)
	clip.add_child(_row_rail)
	_row_rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "SettingsScroll"
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	clip.add_child(_content_scroll)
	_content_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Q.scrollbar(_content_scroll.get_v_scroll_bar())
	_smooth = SMOOTH_SCROLL.attach(_content_scroll)

	var content: VBoxContainer = VBoxContainer.new()
	content.name = "SettingsContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	BunkerUIComponents.scroll_content(_content_scroll, content, 0, 0, 24)

	_build_display_section(content)
	_build_rendering_section(content)
	_build_effects_section(content)
	_build_camera_section(content)
	_content_scroll.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	return workspace


func _configure_rail(rail: Control, offset: float, extent: float, wash: float,
		inset: float) -> void:
	rail.set("require_focus", false)
	rail.set("rail_offset", offset)
	rail.set("rail_width", 2.0)
	rail.set("wash_extent", extent)
	rail.set("wash_alpha", wash)
	rail.set("inset_fraction", inset)
	rail.set("glow", false)
	rail.set("color", Q.ACCENT)


## Segmented quality preset (QuietSegmented). The underline slides to the
## active preset, and to the read-only "Custom" entry as soon as any single
## setting is changed.
func _build_preset_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "QualityPresetRow"
	row.add_theme_constant_override("separation", 20)
	row.custom_minimum_size.y = 52.0
	var copy: VBoxContainer = VBoxContainer.new()
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(Q.eyebrow("Quality preset", 12))
	_preset = SEGMENTED.new()
	_preset.name = "PresetSegments"
	var read_only: Array[int] = [GraphicsSettings.Preset.CUSTOM]
	_preset.call("setup", PRESET_NAMES, read_only, 15)
	_preset.call("describe", "A complete quality baseline. Changing any single setting below switches to Custom.")
	_preset.connect("segment_pressed", _on_preset_selected)
	row.add_child(_preset)
	_preset_buttons = _preset.call("get_buttons")
	return row


func _build_display_section(parent: VBoxContainer) -> void:
	var section: VBoxContainer = _section(parent, "display")
	_window_mode_option = _make_option(WINDOW_MODE_LABELS)
	_window_mode_option.item_selected.connect(_on_window_mode_changed)
	_focus.call("make_row", section, "Window mode", _window_mode_option,
		"How the game occupies your display.")
	_resolution_option = _make_option(RESOLUTION_LABELS)
	_resolution_option.item_selected.connect(_on_resolution_changed)
	_focus.call("make_row", section, "Resolution", _resolution_option,
		"Window size. Available in windowed mode.")
	_vsync_check = _make_switch(_on_vsync_toggled)
	_focus.call("make_row", section, "Vertical sync", _vsync_check,
		"Matches frames to your display to prevent tearing. Can add slight input delay.")
	_fps_cap_option = _make_option(FPS_CAP_LABELS)
	_fps_cap_option.item_selected.connect(_on_fps_cap_changed)
	_focus.call("make_row", section, "Frame-rate cap", _fps_cap_option,
		"Limits frames per second to reduce heat, noise and power use.")


func _build_rendering_section(parent: VBoxContainer) -> void:
	var section: VBoxContainer = _section(parent, "rendering")
	_rendering_driver_option = _make_option(RENDERING_DRIVER_LABELS)
	for index in RENDERING_DRIVER_VALUES.size():
		_rendering_driver_option.set_item_disabled(index, not GraphicsSettings.is_rendering_driver_supported(RENDERING_DRIVER_VALUES[index]))
	_rendering_driver_option.item_selected.connect(_on_rendering_driver_changed)
	_focus.call("make_row", section, "Rendering driver", _rendering_driver_option,
		"The graphics API the game draws with.", "Restart required")
	_aa_option = _make_option(AA_LABELS)
	_aa_option.item_selected.connect(_on_aa_changed)
	_focus.call("make_row", section, "Anti-aliasing", _aa_option,
		"Smooths jagged edges. TAA is softest; MSAA is sharper and costs more.", "Moderate cost")
	_aniso_option = _make_option(ANISO_LABELS)
	_aniso_option.item_selected.connect(_on_aniso_changed)
	_focus.call("make_row", section, "Texture filtering", _aniso_option,
		"Keeps floors and walls crisp at glancing angles.", "Low cost")
	_shadow_quality_option = _make_option(SHADOW_QUALITY_LABELS)
	_shadow_quality_option.item_selected.connect(_on_shadow_quality_changed)
	_focus.call("make_row", section, "Shadow quality", _shadow_quality_option,
		"Shadow resolution. Higher is sharper and uses more video memory.", "Moderate cost")
	_render_scale_slider = HSlider.new()
	_render_scale_slider.min_value = RENDER_SCALE_MIN
	_render_scale_slider.max_value = RENDER_SCALE_MAX
	_render_scale_slider.step = RENDER_SCALE_STEP
	Q.slider(_render_scale_slider)
	_render_scale_slider.value_changed.connect(_on_render_scale_changed)
	_render_scale_slider.drag_ended.connect(_on_render_scale_drag_ended)
	_render_scale_value = _value_label("100%")
	_focus.call("make_row", section, "Render scale", _slider_control(_render_scale_slider, _render_scale_value),
		"Internal resolution. Lower values raise frame rate at the cost of sharpness.",
		"High impact", _render_scale_slider)


func _build_effects_section(parent: VBoxContainer) -> void:
	var section: VBoxContainer = _section(parent, "effects")
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 0)
	section.add_child(grid)
	_sdfgi_check = _make_switch(_on_sdfgi_toggled)
	_focus.call("make_row", grid, "Real-time GI", _sdfgi_check,
		"Light that bounces between surfaces.", "High cost")
	_ssao_check = _make_switch(_on_ssao_toggled)
	_focus.call("make_row", grid, "Ambient occlusion", _ssao_check,
		"Soft contact shadows in corners and crevices.", "Moderate cost")
	_ssil_check = _make_switch(_on_ssil_toggled)
	_focus.call("make_row", grid, "Indirect lighting", _ssil_check,
		"Screen-space colour bleed from nearby lit surfaces.", "Moderate cost")
	_vol_fog_check = _make_switch(_on_vol_fog_toggled)
	_focus.call("make_row", grid, "Volumetric fog", _vol_fog_check,
		"Haze and light shafts in the air.", "High cost")
	_glow_check = _make_switch(_on_glow_toggled)
	_focus.call("make_row", grid, "Glow & bloom", _glow_check,
		"A soft halo around bright lights.", "Low cost")
	_dof_check = _make_switch(_on_dof_toggled)
	_focus.call("make_row", grid, "Depth of field", _dof_check,
		"Blurs what the camera is not focused on.", "Moderate cost")
	_shadow_check = _make_switch(_on_shadow_toggled)
	_focus.call("make_row", grid, "Dynamic shadows", _shadow_check,
		"Moving objects and characters cast shadows.", "Moderate cost")
	_dr_check = _make_switch(_on_dr_toggled)
	_focus.call("make_row", grid, "Dynamic resolution", _dr_check,
		"Lowers render resolution when frame rate drops and restores it once performance recovers. Render scale stays the ceiling.")
	_vol_check = _make_switch(_on_vol_toggled)
	_focus.call("make_row", grid, "Flashlight beams", _vol_check,
		"A visible flashlight beam in dusty air.", "Moderate cost")


func _build_camera_section(parent: VBoxContainer) -> void:
	var section: VBoxContainer = _section(parent, "camera")
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 45.0
	_fov_slider.max_value = 75.0
	_fov_slider.step = 1.0
	Q.slider(_fov_slider)
	_fov_slider.value_changed.connect(_on_fov_changed)
	_fov_slider.drag_ended.connect(_on_fov_drag_ended)
	_fov_value = _value_label("60°")
	_focus.call("make_row", section, "Camera field of view", _slider_control(_fov_slider, _fov_value),
		"How much of the bunker the camera shows.", "", _fov_slider)
	_reduced_motion_check = _make_switch(_on_reduced_motion_toggled)
	_focus.call("make_row", section, "Reduced motion", _reduced_motion_check,
		"Removes interface animation, camera drift and rapid lightning flashes.")
	section.add_child(_gap(8.0))


func _section(parent: VBoxContainer, section_key: String) -> VBoxContainer:
	var section: VBoxContainer = VBoxContainer.new()
	var title_text: String = str(SECTION_TITLES[section_key])
	section.name = title_text.to_pascal_case() + "Section"
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 0)
	parent.add_child(section)
	_section_anchors[section_key] = section
	if parent.get_child_count() > 1:
		section.add_child(_gap(30.0))
	var heading: Label = Q.eyebrow(title_text, 12)
	heading.name = "Heading"
	section.add_child(heading)
	section.add_child(_gap(6.0))
	return section


func _make_option(labels: Array[String]) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	for label_text: String in labels:
		option.add_item(label_text)
	Q.option(option, 15, CONTROL_WIDTH)
	return option


func _make_switch(callback: Callable) -> CheckButton:
	var toggle: CheckButton = CheckButton.new()
	toggle.custom_minimum_size.x = TOGGLE_WIDTH
	Q.switch(toggle, 15)
	# Right = On, Left = Off, for keyboard and d-pad.
	toggle.set_meta(&"ui_cycle", func(direction: int) -> void:
		if not toggle.disabled and (direction > 0) != toggle.button_pressed:
			toggle.button_pressed = direction > 0)
	toggle.toggled.connect(callback)
	return toggle


func _slider_control(slider: HSlider, value_label: Label) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.x = CONTROL_WIDTH
	row.add_theme_constant_override("separation", 14)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _value_label(initial_text: String) -> Label:
	var label: Label = Q.label(initial_text, 15, Q.MUTED)
	label.custom_minimum_size.x = 48
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _gap(height: float) -> Control:
	var gap: Control = Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _build_footer() -> Control:
	_footer = FOOTER.new()
	_footer.set("idle_hint", IDLE_HINT)
	_footer.call("add_key_hint", "ENTER", "Select", "ENTER", "A")
	_footer.call("add_key_hint", "← →", "Adjust", "← →", "D-PAD")
	_footer.call("add_key_hint", "ESC", "Back", "ESC", "B")
	_help_label = _footer.get("hint_label")
	_cost_label = _footer.get("cost_label")
	_saved_label = _footer.get("saved_label")
	return _footer


func _layout() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	UIPanelLayout.fit(_panel, viewport_size, PANEL_MAX, PANEL_MARGIN)


# ── Focus, hover, feedback ───────────────────────────────────────────────────

func _jump_to_section(section_key: String) -> void:
	var anchor: Control = _section_anchors.get(section_key) as Control
	if anchor == null:
		return
	_update_section_buttons(section_key)
	_jump_section = section_key
	_smooth.call("scroll_to", anchor.position.y)


func _on_scroll_changed(scroll_value: float) -> void:
	if not _jump_section.is_empty():
		# Keep the picked section lit (the last ones can't reach the top).
		if _smooth.call("is_animating"):
			return
		_jump_section = ""
		return
	var active_key: String = "display"
	for section_key: String in SECTION_KEYS:
		var anchor: Control = _section_anchors.get(section_key) as Control
		if anchor != null and anchor.position.y <= scroll_value + 60.0:
			active_key = section_key
	# At the very bottom the last section is the one being read.
	var bar: VScrollBar = _content_scroll.get_v_scroll_bar()
	if scroll_value >= bar.max_value - bar.page - 2.0:
		active_key = SECTION_KEYS[SECTION_KEYS.size() - 1]
	_update_section_buttons(active_key)


func _update_section_buttons(active_key: String) -> void:
	if active_key == _active_section:
		return
	_active_section = active_key
	for section_key: String in _section_buttons:
		var button: Button = _section_buttons[section_key] as Button
		button.set_pressed_no_signal(section_key == active_key)
	if _nav_rail != null:
		_nav_rail.call("set_target", _section_buttons.get(active_key))


# ── Settings sync + handlers (behaviour unchanged) ────────────────────────────

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
	_set_switch(_reduced_motion_check, UIMotion.reduced())
	_fov_slider.set_value_no_signal(GraphicsSettings.camera_fov)
	_fov_value.text = "%d°" % roundi(GraphicsSettings.camera_fov)
	_focus.call("sync_row_states")


func _refresh_preset_display() -> void:
	var preset_index: int = GraphicsSettings.current_preset
	if preset_index < 0 or preset_index >= PRESET_NAMES.size():
		preset_index = GraphicsSettings.Preset.CUSTOM
	_preset.call("set_active", preset_index, _is_open)


## The preset currently shown as active (tests and hosts).
func get_displayed_preset() -> int:
	return int(_preset.call("get_active"))


func _select_if_valid(option: OptionButton, index: int) -> void:
	if index >= 0 and index < option.item_count:
		option.select(index)


func _set_switch(toggle: CheckButton, pressed: bool) -> void:
	toggle.set_pressed_no_signal(pressed)
	Q.set_switch_text(toggle)


func _mark_preset_custom() -> void:
	_refresh_preset_display()


func _on_graphics_change_rejected(reason: String) -> void:
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, reason)
	# Restore the dropdown/toggle after its event handler finishes.
	_refresh_from_settings.call_deferred()


func _on_preset_selected(index: int) -> void:
	if index == GraphicsSettings.Preset.CUSTOM:
		return
	GraphicsSettings.apply_preset(index)
	_refresh_from_settings()


func _on_window_mode_changed(index: int) -> void:
	GraphicsSettings.set_setting("window_mode", WINDOW_MODE_VALUES[index])
	_resolution_option.disabled = WINDOW_MODE_VALUES[index] != DisplayServer.WINDOW_MODE_WINDOWED
	_focus.call("sync_row_states")
	_mark_preset_custom()


func _on_resolution_changed(index: int) -> void:
	GraphicsSettings.set_setting("window_mode", DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(RESOLUTION_VALUES[index])
	_window_mode_option.select(WINDOW_MODE_VALUES.find(DisplayServer.WINDOW_MODE_WINDOWED))
	_resolution_option.disabled = false
	_focus.call("sync_row_states")
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
	if not GraphicsSettings.is_rendering_driver_supported(driver):
		return
	_write_override_cfg(driver)
	var executable_path: String = OS.get_executable_path()
	var arguments: PackedStringArray = ["--rendering-driver", driver]
	if OS.has_feature("editor"):
		arguments.append_array(["--path", ProjectSettings.globalize_path("res://")])
	var process_id: int = OS.create_process(executable_path, arguments)
	if process_id == -1:
		push_error("[GraphicsSettingsPanel] Failed to relaunch with --rendering-driver %s — staying on current session." % driver)
		return
	get_tree().quit()


func _write_override_cfg(driver: String) -> void:
	# Never write beside a shared editor installation or set Windows keys on Linux.
	if OS.has_feature("editor") or OS.get_name() != "Windows":
		return
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


func _on_reduced_motion_toggled(pressed: bool) -> void:
	var error_code: Error = UIMotion.set_reduced(pressed)
	if error_code != OK:
		push_warning("[GraphicsSettingsPanel] Could not save reduced UI motion preference (err %d)." % error_code)
	if pressed:
		UIFade.cancel(_panel)
		_panel.modulate.a = 1.0


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
