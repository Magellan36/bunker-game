extends SceneTree
## Headless presentation/contract smoke for ZoneCustomizeModernUI.
## Run with:
## godot --headless --path . --script res://tools/tests/zone_customize_ui_smoke.gd

const UI_SCRIPT: GDScript = preload("res://scripts/ui/power/ZoneCustomizeModernUI.gd")
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui: CanvasLayer = UI_SCRIPT.new() as CanvasLayer
	root.add_child(ui)
	await process_frame
	_check(ui != null, "zone customization companion instantiates")
	var panel: PanelContainer = ui.get("_panel") as PanelContainer
	_check(panel != null, "native companion shell exists")
	var swatches: Array = ui.get("_swatch_buttons") as Array
	_check(swatches.size() == DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES.size(),
		"every established player zone color remains selectable")
	var navigation: Node = ui.get("_controller_nav") as Node
	_check(navigation != null and bool(navigation.get("right_stick_navigation"))
		and not bool(navigation.get("stick_navigation")),
		"d-pad/right-stick navigate while left stick remains player movement")

	ui.call("open_rename", "test-zone", "Medical Wing")
	await process_frame
	_check(ui.visible and bool(ui.get("_is_open")), "rename mode opens")
	_check((ui.get("_rename_content") as Control).visible
		and not (ui.get("_color_content") as Control).visible,
		"rename mode owns one focused workflow")
	var field: LineEdit = ui.get("_name_edit") as LineEdit
	_check(field.max_length == 18 and field.text == "Medical Wing",
		"existing name and 18-character contract are preserved")
	ui.call("close")

	ui.call("open_color", "test-zone", DeviceDatabase.ZONE_PLAYER_COLOR_CHOICES[9])
	await process_frame
	_check((ui.get("_color_content") as Control).visible
		and not (ui.get("_rename_content") as Control).visible,
		"color mode owns one focused workflow")
	var selected: Button = swatches[9] as Button
	_check(selected.text == "✓", "current color has an explicit selected state")
	_check(panel.size.x <= 570.0 and panel.size.y <= 690.0,
		"companion remains inside approved compact desktop bounds")
	ui.call("close")
	ui.free()
	if _failures == 0:
		print("ZONE_CUSTOMIZE_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("ZONE_CUSTOMIZE_UI_SMOKE_FAIL: %s" % message)
