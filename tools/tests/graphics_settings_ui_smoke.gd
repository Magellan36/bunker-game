extends SceneTree
## Headless presentation/contract smoke for GraphicsSettingsPanel.
## Run with:
## godot --headless --path . --script res://tools/tests/graphics_settings_ui_smoke.gd

const PANEL_SCRIPT: GDScript = preload("res://scripts/ui/menus/GraphicsSettingsPanel.gd")
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var panel: CanvasLayer = PANEL_SCRIPT.new() as CanvasLayer
	root.add_child(panel)
	await process_frame
	await process_frame

	_check(panel != null, "graphics panel instantiates")
	var shell: PanelContainer = panel.get("_panel") as PanelContainer
	_check(shell != null, "pause-family shell is present")
	if shell != null:
		_check(shell.size.x <= 1240.0 and shell.size.y <= 760.0,
			"shell keeps approved desktop bounds")

	var navigation: Dictionary = panel.get("_section_buttons") as Dictionary
	_check(navigation.size() == 4, "display/rendering/effects/camera navigation exists")
	for section_key: String in ["display", "rendering", "effects", "camera"]:
		_check(navigation.has(section_key), "navigation includes %s" % section_key)

	var scroll: ScrollContainer = panel.get("_content_scroll") as ScrollContainer
	_check(scroll != null and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
		"settings content uses a bounded vertical scroll region")
	var preset: OptionButton = panel.get("_preset_option") as OptionButton
	_check(preset != null and preset.item_count == 5 and preset.is_item_disabled(4),
		"preset control represents read-only Custom state")

	var switches: Array[CheckButton] = []
	for property_name: String in [
		"_vsync_check", "_sdfgi_check", "_ssao_check", "_ssil_check",
		"_vol_fog_check", "_glow_check", "_dof_check", "_shadow_check",
		"_dr_check", "_vol_check",
	]:
		var toggle: CheckButton = panel.get(property_name) as CheckButton
		if toggle != null:
			switches.append(toggle)
	_check(switches.size() == 10, "all live boolean settings remain connected")

	var render_scale: HSlider = panel.get("_render_scale_slider") as HSlider
	var field_of_view: HSlider = panel.get("_fov_slider") as HSlider
	_check(render_scale != null and render_scale.min_value == 0.5 and render_scale.max_value == 1.0,
		"render scale contract is preserved")
	_check(field_of_view != null and field_of_view.min_value == 45.0 and field_of_view.max_value == 75.0,
		"camera FOV contract is preserved")

	panel.free()
	if _failures == 0:
		print("GRAPHICS_SETTINGS_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("GRAPHICS_SETTINGS_UI_SMOKE_FAIL: %s" % message)
