extends SceneTree
## Headless presentation/contract smoke for the native Power Terminal.
## Run with:
## godot --headless --path . --script res://tools/tests/power_terminal_ui_smoke.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	var ui_script: GDScript = load("res://scripts/ui/power/PowerTerminalModernUI.gd") as GDScript
	var graph_script: GDScript = load("res://scripts/ui/power/PowerTerminalLoadGraph.gd") as GDScript
	var ui: CanvasLayer = ui_script.new() as CanvasLayer
	root.add_child(ui)
	await process_frame
	await process_frame
	_check(ui != null, "power terminal instantiates")
	var panel: PanelContainer = ui.get("_panel") as PanelContainer
	_check(panel != null, "native dashboard shell exists")
	if panel != null:
		_check(panel.size.x <= 1360.0 and panel.size.y <= 800.0,
			"dashboard keeps approved desktop bounds")
	var tabs: Array = ui.get("_tabs") as Array
	var pages: Array = ui.get("_pages") as Array
	_check(tabs.size() == 4 and pages.size() == 4,
		"overview/devices/load-priority/zone-network tabs exist")
	_check(tabs.all(func(tab: Button) -> bool:
		return tab.custom_minimum_size.y <= 34.0),
		"power workspace tabs use compact desktop density")
	var priority_step: Button = ui.call("_priority_button", "+") as Button
	_check(priority_step.custom_minimum_size.y <= 30.0,
		"load-priority stepping controls avoid oversized rows")
	priority_step.free()
	var graph: Control = ui.get("_graph") as Control
	_check(graph != null and graph.get_script() == graph_script,
		"overview owns the continuous 60-second graph")
	var reset: Button = ui.get("_overview_reset") as Button
	_check(reset != null and reset.disabled,
		"healthy or unavailable grid does not expose a live reset action")
	var nav: Node = ui.get("_controller_nav") as Node
	_check(nav != null and bool(nav.get("right_stick_navigation"))
		and not bool(nav.get("stick_navigation")),
		"d-pad/right-stick navigate while left stick remains world movement")
	ui.call("open")
	await process_frame
	_check(bool(ui.get("_is_open")) and ui.visible,
		"open presents the reusable terminal")
	_check((pages[0] as Control).visible and not (pages[1] as Control).visible,
		"every open returns to a clean Overview state")
	ui.call("_set_tab", 2)
	_check((pages[2] as Control).visible and not (pages[0] as Control).visible,
		"tab switching owns one visible workspace")
	ui.call("close")
	_check(not bool(ui.get("_is_open")) and ui.visible,
		"close ends interaction immediately while retaining the exit presentation")
	await create_timer(UIMotion.EXIT + 0.04).timeout
	_check(not ui.visible, "short exit hides without freeing persistent history")
	ui.free()
	if _failures == 0:
		print("POWER_TERMINAL_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("POWER_TERMINAL_UI_SMOKE_FAIL: %s" % message)
