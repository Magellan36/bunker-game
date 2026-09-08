extends SceneTree
## Headless presentation and gameplay-contract smoke for the native Research
## Station workspace.
## Run with:
## godot --headless --path . --script res://tools/tests/research_station_ui_smoke.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	var ui_script: GDScript = load("res://scripts/ui/research/ResearchStationModernUI.gd") as GDScript
	var path_script: GDScript = load("res://scripts/ui/research/ResearchPathCanvas.gd") as GDScript
	var station_script: GDScript = GDScript.new()
	station_script.source_code = """extends \"res://scripts/world/furniture/ResearchStation.gd\"
func _ready() -> void:
	pass
"""
	_check(station_script.reload() == OK, "research station test double compiles")
	var ui: CanvasLayer = ui_script.new() as CanvasLayer
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
		path_canvas != null and path_canvas.get_script() == path_script,
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

	var station: Node = station_script.new() as Node
	station.stored_materials = {"metal": 8, "plastic": 7, "paper": 3, "organic": 6}
	root.add_child(station)
	await process_frame
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
	station.set_process(false)
	var progress: BunkerSmoothProgressBar = ui.get("_research_progress_bar") as BunkerSmoothProgressBar
	progress.snap_to(0.0)
	for percent: int in range(1, 10):
		station._elapsed = station.active_upgrade.duration_seconds * (float(percent) + 0.01) / 100.0
		var owner_elapsed: float = station._elapsed
		ui.set("_refresh_elapsed", 0.0)
		ui.call("_process", 0.001)
		_check(progress == ui.get("_research_progress_bar") and progress._target_value == percent,
			"each 1% update reaches the retained progress bar between coarse refreshes")
		var previous: float = progress.value
		progress.call("_process", 0.04)
		_check(progress.value > previous and progress.value < percent,
			"research fill eases toward each percent")
		_check(station._elapsed == owner_elapsed, "presentation does not advance research time")
	ui.call("_on_research_action")
	action = ui.get("_action_button") as Button
	_check(
		station.is_paused and action.text == "Resume Research",
		"pause state remains functional and explicit"
	)
	ui.call("_on_research_action")
	_check(not station.is_paused, "resume delegates to the established station backend")
	await process_frame
	ui.call("close")
	_check(not bool(ui.get("is_open")) and ui.visible,
		"close ends interaction immediately while retaining the exit presentation")
	await create_timer(UIMotion.EXIT + 0.04).timeout
	_check(not ui.visible, "short exit hides the reusable workspace")
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
