extends SceneTree
## Headless presentation/contract smoke for the native Power Terminal.
## Run with:
## godot --headless --path . --script res://tools/tests/power_terminal_ui_smoke.gd

const UI_SCRIPT: GDScript = preload("res://scripts/ui/power/PowerTerminalModernUI.gd")
const GRAPH_SCRIPT: GDScript = preload("res://scripts/ui/power/PowerTerminalLoadGraph.gd")
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui: CanvasLayer = UI_SCRIPT.new() as CanvasLayer
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
	var graph: Control = ui.get("_graph") as Control
	_check(graph != null and graph.get_script() == GRAPH_SCRIPT,
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
	_check(not bool(ui.get("_is_open")) and not ui.visible,
		"close hides without freeing persistent history")
	ui.free()
	if _failures == 0:
		print("POWER_TERMINAL_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("POWER_TERMINAL_UI_SMOKE_FAIL: %s" % message)
