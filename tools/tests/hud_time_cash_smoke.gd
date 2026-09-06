extends SceneTree
## Headless presentation/contract smoke for the compact clock and cash HUD.
## Run with:
## godot --headless --path . --script res://tools/tests/hud_time_cash_smoke.gd

const HUD_SCENE: PackedScene = preload("res://scenes/ui/HUD.tscn")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	root.add_child(hud)
	await process_frame

	var time_root: Control = hud.get_node("HUDRoot/TopCenter") as Control
	var clock_icon: TextureRect = hud.get_node(
		"HUDRoot/TopCenter/ClockPanel/ClockRow/ClockIcon") as TextureRect
	var clock_label: Label = hud.get_node(
		"HUDRoot/TopCenter/ClockPanel/ClockRow/TimeStack/ClockLabel") as Label
	var day_label: Label = hud.get_node(
		"HUDRoot/TopCenter/ClockPanel/ClockRow/TimeStack/DayLabel") as Label
	var cash_panel: PanelContainer = hud.get_node("HUDRoot/TopRight") as PanelContainer
	var cash_label: Label = hud.get_node("HUDRoot/TopRight/CashLabel") as Label

	_check(time_root.size == Vector2(152.0, 42.0),
		"time plate keeps the approved smaller 1080p footprint")
	_check(clock_icon.texture != null and clock_icon.custom_minimum_size == Vector2(22.0, 22.0),
		"time plate uses the compact native clock symbol")
	_check(cash_panel.custom_minimum_size == Vector2(154.0, 40.0),
		"cash balance remains a compact top-right plate")
	_check(cash_panel.get_child_count() == 1 and cash_panel.get_child(0) == cash_label,
		"cash plate contains only the bordered balance—no icon or subtitle")

	hud.call("set_clock", "11:45 PM")
	hud.call("set_day", 18)
	hud.call("set_cash", 123456)
	_check(clock_label.text == "11:45 PM", "existing set_clock contract is preserved")
	_check(day_label.text == "DAY 18", "existing set_day contract is preserved")
	_check(cash_label.text == "$123,456", "existing set_cash formatting is preserved")

	hud.free()
	if _failures == 0:
		print("HUD_TIME_CASH_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("HUD_TIME_CASH_SMOKE_FAIL: %s" % message)
