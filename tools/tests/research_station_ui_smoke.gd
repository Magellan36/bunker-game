extends SceneTree
## Headless presentation and gameplay-contract smoke for the native Research
## Station workspace.
## Run with:
## godot --headless --path . --script res://tools/tests/research_station_ui_smoke.gd

const UI_SCRIPT: GDScript = preload("res://scripts/ui/research/ResearchStationModernUI.gd")
const PATH_SCRIPT: GDScript = preload("res://scripts/ui/research/ResearchPathCanvas.gd")
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui: CanvasLayer = UI_SCRIPT.new() as CanvasLayer
	root.add_child(ui)
	await process_frame
	await process_frame
	_check(ui != null, "research station workspace instantiates")
	var panel: PanelContainer = ui.get("_panel") as PanelContainer
	_check(panel != null, "native research shell exists")
	if panel != null:
		_check(
			panel.size.x <= 1360.0 and panel.size.y <= 800.0,
			"workspace keeps approved desktop bounds"
		)
	var tabs: Array = ui.get("_tabs") as Array
	var pages: Array = ui.get("_pages") as Array
	_check(tabs.size() == 3 and pages.size() == 3, "all three established research tabs exist")
	var material_counts: Dictionary = ui.get("_material_counts") as Dictionary
	_check(material_counts.size() == 4, "all four research material stores remain visible")
	var path_canvas: Control = ui.get("_path_canvas") as Control
	_check(
		path_canvas != null and path_canvas.get_script() == PATH_SCRIPT,
		"research pathways use the native dependency canvas"
	)
	var navigation: Node = ui.get("_controller_nav") as Node
	_check(
		(
			navigation != null
			and bool(navigation.get("right_stick_navigation"))
			and not bool(navigation.get("stick_navigation"))
		),
		"d-pad/right-stick navigate while left stick remains player movement"
	)

	var station: ResearchStation = ResearchStation.new()
	station.stored_materials = {"metal": 8, "plastic": 7, "paper": 3, "organic": 6}
	ui.call("open", station)
	await process_frame
	_check(bool(ui.get("is_open")) and ui.visible, "open presents the reusable workspace")
	var action: Button = ui.get("_action_button") as Button
	_check(
		action != null and action.text == "Begin Research" and not action.disabled,
		"affordable research exposes the approved primary action"
	)
	ui.call("_on_research_action")
	action = ui.get("_action_button") as Button
	_check(
		station.active_upgrade != null and action.text == "Pause Research",
		"begin action delegates to the established station backend"
	)
	ui.call("_on_research_action")
	action = ui.get("_action_button") as Button
	_check(
		station.is_paused and action.text == "Resume Research",
		"pause state remains functional and explicit"
	)
	ui.call("_on_research_action")
	_check(not station.is_paused, "resume delegates to the established station backend")
	ui.call("close")
	_check(not bool(ui.get("is_open")) and not ui.visible, "close hides the reusable workspace")
	station.free()
	ui.free()
	if _failures == 0:
		print("RESEARCH_STATION_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("RESEARCH_STATION_UI_SMOKE_FAIL: %s" % message)
