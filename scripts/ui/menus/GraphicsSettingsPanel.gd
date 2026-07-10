extends CanvasLayer
## GraphicsSettingsPanel.gd
## Graphics/quality settings panel — opened from PauseMenuUI's Settings
## button (was a stub, per PROJECT_SUMMARY.md §7 / §13). Built as a real
## Control node tree in code (same pattern PauseMenuUI/BuildModeHUD use),
## per the "new panels should use Control trees, not hand-drawn _draw()"
## guidance in PROJECT_SUMMARY.md §9 — NOT a .tscn scene file.
##
## DEPENDS ON the GraphicsSettings autoload being registered (Project
## Settings > Autoload, name "GraphicsSettings") — will show "Could not
## find type GraphicsSettings" until that's done.
##
## Phase 1 scope: preset selector + the two flashlight-specific opt-in
## toggles the graphics plan calls out as never-preset-driven. Individual
## per-feature checkboxes (SDFGI/SSAO/SSIL/etc, one row each) can be added
## later without touching this file's structure — same _build_ui() pattern,
## same _make_checkbox() helper.
##
## Instantiated lazily by PauseMenuUI._on_settings_pressed() the same way
## MainWorld lazily instantiates PauseMenuUI itself.

var _panel:         Panel = null
var _vbox:          VBoxContainer = null
var _preset_option: OptionButton = null
var _vol_check:     CheckBox = null
var _shadow_check:  CheckBox = null
var _fov_slider:    HSlider = null

const PANEL_W: float = 320.0
const PRESET_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]


func _ready() -> void:
	layer = 210   ## Above PauseMenuUI (layer 200) so it renders on top of it.
	_build_ui()
	visible = false


func open() -> void:
	visible = true
	_refresh_from_settings()
	_panel.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.15)


func close() -> void:
	visible = false


func _build_ui() -> void:
	## Reuses PauseMenuUI's proven blur-backdrop shader/pattern (this panel
	## opens on top of the already-open, already-blurred PauseMenuUI, but
	## PauseMenuUI's own blur only samples what was behind IT, not itself —
	## stacking a second blur here keeps this panel readable over the pause
	## menu's plain dark panel underneath it too).
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var blur_shader: Shader = load("res://assets/shaders/pause_blur.gdshader")
	if blur_shader != null:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = blur_shader
		backdrop.material = mat
	else:
		backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	add_child(backdrop)

	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position -= Vector2(PANEL_W * 0.5, 110.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color     = Color(0.12, 0.12, 0.14, 0.97)
	style.border_color = Color(0.30, 0.30, 0.33, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 10)
	_vbox.position = Vector2(16.0, 16.0)
	_vbox.custom_minimum_size = Vector2(PANEL_W - 32.0, 0.0)
	_panel.add_child(_vbox)

	var title: Label = Label.new()
	title.text = "GRAPHICS SETTINGS"
	title.add_theme_font_size_override("font_size", 14)
	_vbox.add_child(title)
	_vbox.add_child(HSeparator.new())

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

	_vol_check = _make_checkbox("Flashlight beam volumetrics", _on_vol_toggled)
	_vbox.add_child(_vol_check)

	_shadow_check = _make_checkbox("Flashlight shadow casting (perf cost, opt-in)", _on_shadow_toggled)
	_vbox.add_child(_shadow_check)

	_vbox.add_child(HSeparator.new())

	var fov_row: HBoxContainer = HBoxContainer.new()
	_vbox.add_child(fov_row)
	var fov_lbl: Label = Label.new()
	fov_lbl.text = "Camera FOV"
	fov_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fov_row.add_child(fov_lbl)
	_fov_slider = HSlider.new()
	_fov_slider.min_value = 60.0
	_fov_slider.max_value = 100.0
	_fov_slider.step      = 1.0
	_fov_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_fov_slider.value_changed.connect(_on_fov_changed)
	fov_row.add_child(_fov_slider)

	_vbox.add_child(HSeparator.new())
	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(close)
	_vbox.add_child(close_btn)


func _make_checkbox(text: String, cb: Callable) -> CheckBox:
	var box: CheckBox = CheckBox.new()
	box.text = text
	box.toggled.connect(cb)
	return box


func _refresh_from_settings() -> void:
	## Preset OptionButton index maps 1:1 to Preset enum for LOW..ULTRA;
	## CUSTOM has no matching item, so just leave whatever was last selected.
	if GraphicsSettings.current_preset != GraphicsSettings.Preset.CUSTOM:
		_preset_option.selected = GraphicsSettings.current_preset
	_vol_check.button_pressed    = GraphicsSettings.flashlight_volumetrics
	_shadow_check.button_pressed = GraphicsSettings.flashlight_shadows
	_fov_slider.value            = GraphicsSettings.camera_fov


func _on_preset_selected(index: int) -> void:
	## `index` maps 1:1 to the Preset enum (LOW..ULTRA) since the OptionButton
	## items were added in that exact order. No cast needed/possible here —
	## `as` doesn't support enum casts, only Object/class casts (see
	## GraphicsSettings.gd's _apply_to_viewport() comment for the bug this
	## caused elsewhere).
	GraphicsSettings.apply_preset(index)
	_refresh_from_settings()


func _on_vol_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("flashlight_volumetrics", pressed)


func _on_shadow_toggled(pressed: bool) -> void:
	GraphicsSettings.set_setting("flashlight_shadows", pressed)


func _on_fov_changed(value: float) -> void:
	GraphicsSettings.set_setting("camera_fov", value)
