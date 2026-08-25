extends CanvasLayer
## GraphicsSettingsPanel.gd
## Graphics/quality settings panel — opened from PauseMenuUI's Settings
## button. Built as a real Control node tree in code (same pattern
## PauseMenuUI/BuildModeHUD use).
##
## Jul 2026 — restyled onto the shared UIKit menu-builder helpers as part
## of the "unify every menu" pass. This is also the fix for the long-
## standing off-center bug: the panel used to call the bare
## `set_anchors_preset(PRESET_CENTER)` with no explicit offsets BEFORE its
## ~15 settings rows were added, so Godot baked the centering math from the
## panel's near-zero size at that moment instead of its real final size.
## `UIKit.build_centered_panel()` fixes this structurally by always sizing
## the panel to its final fixed width/height up front.
##
## DEPENDS ON the GraphicsSettings autoload being registered (Project
## Settings > Autoload, name "GraphicsSettings") — will show "Could not
## find type GraphicsSettings" until that's done.
##
## Scope: full graphics overhaul (Phase 0-5). Implements:
##   1. Quality Preset selector (Low/Medium/High/Ultra)
##   2. Display section (Window Mode, Resolution, VSync, FPS Cap)
##   3. Rendering section (Rendering Driver, AA combo, Anisotropic, Shadow Quality, Render Scale)
##   4. Advanced Quality (SDFGI, SSAO, SSIL, Volumetric Fog, Glow, DOF)
##   5. Flashlight section (Volumetrics, Shadows)
##   6. Camera (FOV)
## All controls use the shared UIKit NEUTRAL theme + menu builders for
## visual consistency with PauseMenuUI.

var _panel:         Panel = null
var _vbox:          VBoxContainer = null
var _scroll:        ScrollContainer = null
var _preset_option: OptionButton = null
var _close_btn:     Button = null
var _backdrop:      ColorRect = null   ## Jul 2026 — stored directly instead of fetched via get_child(0)
var _theme:         UIKit.UITheme = null

## Display
var _window_mode_option: OptionButton = null
var _resolution_option:  OptionButton = null
var _vsync_check:        CheckBox = null
var _fps_cap_option:     OptionButton = null

## Rendering
var _rendering_driver_option: OptionButton = null
var _aa_option:          OptionButton = null
var _aniso_option:       OptionButton = null
var _shadow_quality_option: OptionButton = null
var _render_scale_slider: HSlider = null

## Aug 2026 — restart-required confirm dialog for the rendering driver
## change, see _show_restart_required_dialog(). Stored so a second attempt
## to open it (e.g. rapid double-click) doesn't stack two — same
## "never stack two" defensiveness PauseMenuUI.gd's own confirm dialog
## uses; this is a separate, self-contained implementation rather than a
## shared UIKit helper, since no such shared helper exists yet and adding
## one is out of scope for this change (see docs/systems/graphics/README.md
## "Rendering driver switch" for the note on why this isn't extracted).
## Lazy-instantiated shared ConfirmDialogUI (Aug 2026 consistency pass) for
## the restart-required prompt — replaces the hand-rolled layer. Layer 215
## (above this panel's 210, below NotificationManager's 220).
var _restart_confirm_dialog: CanvasLayer = null
var _restart_driver_connected: bool = false
## The driver pending a restart — read by the confirmed handler at emit time.
var _pending_restart_driver: String = ""

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

## Dynamic Resolution (Aug 2026) — see GraphicsSettings.dynamic_resolution_enabled.
var _dr_check:             CheckBox = null

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

const PANEL_MAX_H: float = 520.0
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

## Rendering driver options — values must match GraphicsSettings.RENDERING_DRIVERS.
const RENDERING_DRIVER_LABELS: Array[String] = ["Vulkan", "D3D12"]
const RENDERING_DRIVER_VALUES: Array[String] = ["vulkan", "d3d12"]

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

func _ready() -> void:
	layer = 210   ## Above PauseMenuUI (layer 200)
	_build_ui()
	visible = false
	## Controller navigation (Aug 2026) — d-pad + left stick drive focus
	## (movement is locked while this is open), B closes this UI. See
	## scripts/ui/common/ControllerUINavigation.gd.
	var controller_nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	controller_nav.ui_root = self
	controller_nav.stick_navigation = true
	add_child(controller_nav)

func open() -> void:
	visible = true
	_refresh_from_settings()
	UIFade.fade_in(_panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_ui() -> void:
	_theme = UIKit.theme_for(UIKit.Domain.NEUTRAL)

	## Blur backdrop (same as PauseMenuUI, via the shared builder).
	_backdrop = UIKit.build_modal_backdrop()
	add_child(_backdrop)
	_backdrop.gui_input.connect(_on_backdrop_input)

	## Main panel — fixed size, always correctly centered (Jul 2026 fix,
	## see file header).
	_panel = UIKit.build_centered_panel(UIKit.MENU_PANEL_W, PANEL_MAX_H, _theme)
	add_child(_panel)

	## Scroll container (panel is a fixed height, so overflow content scrolls
	## instead of the panel growing/shrinking to fit it).
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
	_vbox.offset_top = 22   ## Jul 2026 — +6px top-padding pass, was 16
	_vbox.offset_bottom = 16
	_scroll.add_child(_vbox)

	## Title
	var title: Label = Label.new()
	title.text = "GRAPHICS SETTINGS"
	title.add_theme_color_override("font_color", _theme.header)
	title.add_theme_font_size_override("font_size", UIKit.FONT_SIZE_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UIKit.font())
	_vbox.add_child(title)

	## Scrollable content will be added via _build_content()
	_build_content()

	## Close button at bottom
	_close_btn = UIKit.make_button("Close", close, 36.0)
	_vbox.add_child(_close_btn)

	## Apply shared settings theme to the whole panel (so checkboxes, sliders,
	## optionbuttons inherit the dark styling without per-control overrides)
	_panel.theme = UIKit.settings_controls_theme()

## ─── Content builder ──────────────────────────────────────────────────────────
func _build_content() -> void:
	## 1. Quality Preset
	_vbox.add_child(UIKit.make_section_label("QUALITY PRESET", _theme))
	var preset_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(preset_row)
	preset_row.add_child(UIKit.make_row_label("Quality Preset", _theme))
	_preset_option = OptionButton.new()
	for preset_name: String in PRESET_NAMES:
		_preset_option.add_item(preset_name)
	_preset_option.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_preset_option)

	## 2. Display
	_vbox.add_child(HSeparator.new())
	_vbox.add_child(UIKit.make_section_label("DISPLAY", _theme))

	## Window Mode
	var wm_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(wm_row)
	wm_row.add_child(UIKit.make_row_label("Window Mode", _theme))
	_window_mode_option = OptionButton.new()
	for lbl: String in WINDOW_MODE_LABELS:
		_window_mode_option.add_item(lbl)
	_window_mode_option.item_selected.connect(_on_window_mode_changed)
	wm_row.add_child(_window_mode_option)

	## Resolution (Windowed only)
	var res_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(res_row)
	res_row.add_child(UIKit.make_row_label("Resolution", _theme))
	_resolution_option = OptionButton.new()
	for lbl: String in RESOLUTION_LABELS:
		_resolution_option.add_item(lbl)
	_resolution_option.item_selected.connect(_on_resolution_changed)
	res_row.add_child(_resolution_option)

	## VSync
	var vsync_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(vsync_row)
	vsync_row.add_child(UIKit.make_row_label("VSync", _theme))
	_vsync_check = _make_checkbox("Enabled", _on_vsync_toggled)
	vsync_row.add_child(_vsync_check)

	## FPS Cap
	var fps_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(fps_row)
	fps_row.add_child(UIKit.make_row_label("FPS Cap", _theme))
	_fps_cap_option = OptionButton.new()
	for lbl: String in FPS_CAP_LABELS:
		_fps_cap_option.add_item(lbl)
	_fps_cap_option.item_selected.connect(_on_fps_cap_changed)
	fps_row.add_child(_fps_cap_option)

	## 3. Rendering
	_vbox.add_child(HSeparator.new())
	_vbox.add_child(UIKit.make_section_label("RENDERING", _theme))

	## Rendering Driver — Aug 2026. Restart-required setting, see
	## docs/systems/graphics/README.md "Rendering driver switch". Placed
	## first in this section since it's the most consequential/rare change
	## here (everything else below applies live).
	var driver_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(driver_row)
	driver_row.add_child(UIKit.make_row_label("Rendering Driver", _theme))
	_rendering_driver_option = OptionButton.new()
	for lbl: String in RENDERING_DRIVER_LABELS:
		_rendering_driver_option.add_item(lbl)
	_rendering_driver_option.item_selected.connect(_on_rendering_driver_changed)
	driver_row.add_child(_rendering_driver_option)

	## Anti-Aliasing combo
	var aa_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(aa_row)
	aa_row.add_child(UIKit.make_row_label("Anti-Aliasing", _theme))
	_aa_option = OptionButton.new()
	for lbl: String in AA_LABELS:
		_aa_option.add_item(lbl)
	_aa_option.item_selected.connect(_on_aa_changed)
	aa_row.add_child(_aa_option)

	## Anisotropic Filtering
	var aniso_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(aniso_row)
	aniso_row.add_child(UIKit.make_row_label("Anisotropic Filtering", _theme))
	_aniso_option = OptionButton.new()
	for lbl: String in ANISO_LABELS:
		_aniso_option.add_item(lbl)
	_aniso_option.item_selected.connect(_on_aniso_changed)
	aniso_row.add_child(_aniso_option)

	## Shadow Quality
	var shadow_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(shadow_row)
	shadow_row.add_child(UIKit.make_row_label("Shadow Quality", _theme))
	_shadow_quality_option = OptionButton.new()
	for lbl: String in SHADOW_QUALITY_LABELS:
		_shadow_quality_option.add_item(lbl)
	_shadow_quality_option.item_selected.connect(_on_shadow_quality_changed)
	shadow_row.add_child(_shadow_quality_option)

	## Render Scale
	var rs_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(rs_row)
	rs_row.add_child(UIKit.make_row_label("Render Scale", _theme))
	_render_scale_slider = HSlider.new()
	_render_scale_slider.min_value = RENDER_SCALE_MIN
	_render_scale_slider.max_value = RENDER_SCALE_MAX
	_render_scale_slider.step = RENDER_SCALE_STEP
	_render_scale_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_render_scale_slider.value_changed.connect(_on_render_scale_changed)
	_render_scale_slider.drag_ended.connect(_on_render_scale_drag_ended)
	rs_row.add_child(_render_scale_slider)

	## 4. Advanced Quality
	_vbox.add_child(HSeparator.new())
	_vbox.add_child(UIKit.make_section_label("ADVANCED QUALITY", _theme))
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
	## Aug 2026 — generalized from flashlight-only to all dynamic
	## shadow-casting lights (Flashlight, WallLight, GrowLight; see
	## docs/systems/graphics/README.md "Unified dynamic shadow casting").
	## Preset-driven now (LOW/MEDIUM off, HIGH/ULTRA on), so it lives here
	## with the other preset-tier toggles instead of under Flashlight —
	## the "(opt-in)" label is gone since it's an ordinary preset-tier
	## quality setting now, not opt-in-only.
	_shadow_check         = _make_checkbox("Shadow Casting", _on_shadow_toggled)
	_vbox.add_child(_shadow_check)
	## Dynamic Resolution (Aug 2026) — standalone toggle in Advanced Quality
	## so its label can say exactly what it does (this one isn't a preset
	## tier, it's a frame-rate safeguard layered on top of the user's Render
	## Scale ceiling).
	_dr_check            = _make_checkbox("Dynamic Resolution (Auto Frame Rate)", _on_dr_toggled)
	_dr_check.tooltip_text = "Automatically lowers render resolution when frame rate drops and restores it once performance recovers. Uses the Render Scale slider as the quality ceiling."
	_vbox.add_child(_dr_check)

	## 5. Flashlight
	_vbox.add_child(HSeparator.new())
	_vbox.add_child(UIKit.make_section_label("FLASHLIGHT", _theme))
	_vol_check            = _make_checkbox("Beam Volumetrics", _on_vol_toggled)
	_vbox.add_child(_vol_check)

	## 6. Camera
	_vbox.add_child(HSeparator.new())
	_vbox.add_child(UIKit.make_section_label("CAMERA", _theme))
	var fov_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(fov_row)
	fov_row.add_child(UIKit.make_row_label("Camera FOV", _theme))
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 45.0
	_fov_slider.max_value = 75.0
	_fov_slider.step = 1.0
	_fov_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_fov_slider.value_changed.connect(_on_fov_changed)
	_fov_slider.drag_ended.connect(_on_fov_drag_ended)
	fov_row.add_child(_fov_slider)

## ─── Helper: control makers ─────────────────────────────────────────────────
## NOTE: section headers and row labels now go through UIKit.make_section_label()/
## UIKit.make_row_label() (called directly at each site above) — this file
## keeps only _make_checkbox(), which UIKit doesn't have an equivalent for yet.
func _make_checkbox(text: String, cb: Callable) -> CheckBox:
	var box: CheckBox = CheckBox.new()
	box.text = text
	box.toggled.connect(cb)
	box.add_theme_font_override("font", UIKit.font())
	box.add_theme_color_override("font_color", _theme.text)
	return box

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
	_rendering_driver_option.selected = RENDERING_DRIVER_VALUES.find(GraphicsSettings.rendering_driver)
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
	_shadow_check.button_pressed    = GraphicsSettings.shadow_casting_enabled
	_dr_check.button_pressed        = GraphicsSettings.dynamic_resolution_enabled

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

## Aug 2026 — Rendering Driver. Saves immediately (so the choice survives
## even if the player never confirms a restart), then shows the restart
## prompt only if this differs from what's ACTUALLY running this session
## (GraphicsSettings.session_start_rendering_driver — see that var's
## comment for why it's the correct comparison point, not
## GraphicsSettings.rendering_driver itself). Picking the driver that's
## already active (e.g. toggling back) needs no restart at all.
func _on_rendering_driver_changed(index: int) -> void:
	var new_driver: String = RENDERING_DRIVER_VALUES[index]
	GraphicsSettings.set_rendering_driver(new_driver)
	if new_driver != GraphicsSettings.session_start_rendering_driver:
		_show_restart_required_dialog(new_driver)

func _on_aa_changed(index: int) -> void:
	var opt: Dictionary = AA_OPTIONS[index]
	GraphicsSettings.set_setting("msaa", opt.msaa)
	GraphicsSettings.set_setting("screen_space_aa", opt.screen_space_aa)
	GraphicsSettings.set_setting("use_taa", opt.use_taa)

func _on_aniso_changed(index: int) -> void:
	GraphicsSettings.set_setting("anisotropic_filtering", ANISO_VALUES[index])

func _on_shadow_quality_changed(index: int) -> void:
	GraphicsSettings.set_setting("shadow_quality", SHADOW_QUALITY_VALUES[index])


# ─── Rendering driver: restart-required confirm dialog + relaunch ───────────
## Aug 2026 — now routed through the shared ConfirmDialogUI (the old
## hand-rolled restart-required layer is gone).
func _show_restart_required_dialog(pending_driver: String) -> void:
	_ensure_restart_confirm_dialog()
	_restart_confirm_dialog.open("RESTART REQUIRED",
		"Switch rendering driver to %s and restart now?" % pending_driver)
	## Spawn-once/reuse — connect confirmed to the relaunch exactly once.
	if not _restart_driver_connected:
		_restart_confirm_dialog.confirmed.connect(
			func() -> void: _relaunch_with_driver(_pending_restart_driver))
		_restart_driver_connected = true
	_pending_restart_driver = pending_driver

func _ensure_restart_confirm_dialog() -> void:
	if _restart_confirm_dialog != null and is_instance_valid(_restart_confirm_dialog):
		return
	var dlg_script: GDScript = load("res://scripts/ui/common/ConfirmDialogUI.gd")
	if dlg_script == null:
		push_warning("[GraphicsSettingsPanel] ConfirmDialogUI.gd not found")
		return
	_restart_confirm_dialog = CanvasLayer.new()
	_restart_confirm_dialog.set_script(dlg_script)
	_restart_confirm_dialog.name = "ConfirmDialogUI"
	_restart_confirm_dialog.set("stacking_layer", 215)
	add_child(_restart_confirm_dialog)


## Spawns a new instance of this same executable with the driver override
## on the command line, then quits the current one. `OS.create_process()`
## (not `OS.execute()` — that call blocks waiting for the child process to
## exit, which would hang here) returns a PID immediately and does not tie
## the new process's lifetime to this one, which is exactly what's needed
## for "launch my replacement, then get out of the way." Godot applies
## --rendering-driver as a CLI-level override regardless of what's baked
## into project.godot — this is the same override mechanism already
## proven by this bug's own fix (driver.windows="vulkan" pinned there).
##
## Guards against a failed spawn: if create_process() returns -1, the new
## instance never launched — do NOT quit in that case, or the player is
## left with no game running at all. Also best-effort writes an
## override.cfg next to the executable so the choice survives a future
## PLAIN restart too, not just this one — see
## docs/systems/graphics/README.md "Rendering driver switch" Tier 2 for
## why this is separate from, and less certain than, the relaunch itself;
## failure here is logged but never blocks the relaunch.
func _relaunch_with_driver(driver: String) -> void:
	_write_override_cfg(driver)

	var exe_path: String = OS.get_executable_path()
	var args: PackedStringArray = ["--rendering-driver", driver]
	var pid: int = OS.create_process(exe_path, args)
	if pid == -1:
		push_error("[GraphicsSettingsPanel] Failed to relaunch with --rendering-driver %s — staying on current session." % driver)
		return
	get_tree().quit()


## Tier 2 durability (see docs/systems/graphics/README.md "Rendering
## driver switch") — an override.cfg next to the executable, read by
## Godot at the very start of boot, before rendering device selection,
## without touching the tracked/committed project.godot. Best-effort: a
## failed write (e.g. no permission in the install directory) is logged
## and otherwise ignored — Tier 1 (the immediate relaunch above) already
## fully applies the choice for right now regardless of whether this
## succeeds.
func _write_override_cfg(driver: String) -> void:
	var dir: String = OS.get_executable_path().get_base_dir()
	var override_path: String = dir.path_join("override.cfg")
	var cfg: ConfigFile = ConfigFile.new()
	## Loading first (ignoring failure — file may not exist yet) preserves
	## any other override values a future feature might add here, instead
	## of clobbering the whole file.
	cfg.load(override_path)
	cfg.set_value("rendering", "rendering_device/driver.windows", driver)
	var err: int = cfg.save(override_path)
	if err != OK:
		push_warning("[GraphicsSettingsPanel] Could not write override.cfg (err %d) — rendering driver choice will only apply via in-app restart, not a plain relaunch." % err)

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
	GraphicsSettings.set_setting("shadow_casting_enabled", pressed)

func _on_dr_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("dynamic_resolution_enabled", pressed)

func _on_fov_changed(value: float) -> void:
	GraphicsSettings.set_setting_live("camera_fov", value)

func _on_fov_drag_ended(_value_changed: bool) -> void:
	GraphicsSettings.save_now()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		get_viewport().set_input_as_handled()
