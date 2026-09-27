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
	_check((tabs[2] as Button).text == "LOAD ORDER",
		"power allocation workspace omits redundant priority wording")
	var power_scrolls: Array[Node] = panel.find_children("*", "ScrollContainer", true, false)
	_check(not power_scrolls.is_empty() and power_scrolls.all(func(node: Node) -> bool:
		var scroll := node as ScrollContainer
		return scroll.get_child_count() == 1 \
			and scroll.get_child(0).name == "ScrollContentGutter" \
			and (scroll.get_child(0) as MarginContainer).get_theme_constant("margin_right") >= 20),
		"every Power Terminal list reserves the shared scrollbar gutter")
	var priority_step: Button = ui.call("_priority_button", "+") as Button
	_check(priority_step.custom_minimum_size.y <= 30.0,
		"load-priority stepping controls avoid oversized rows")
	priority_step.free()
	var sample_consumer := {"id": "smoke", "type": "water_dispenser", "watts": 120.0,
		"priority": 3, "active": true, "powered": true, "shed": false}
	ui.call("_add_priority_row", sample_consumer, [sample_consumer])
	var sample_rows: Dictionary = ui.get("_priority_rows") as Dictionary
	var sample_row: Dictionary = sample_rows.get("smoke", {}) as Dictionary
	var sample_detail: Label = sample_row.get("detail") as Label
	var sample_card: PanelContainer = sample_detail.get_parent().get_parent().get_parent().get_parent() as PanelContainer \
		if sample_detail != null else null
	_check(sample_detail != null and sample_detail.get_parent() is HBoxContainer \
		and sample_card != null and sample_card.custom_minimum_size.y <= 40.0,
		"load name and draw share one compact line")
	var graph: Control = ui.get("_graph") as Control
	_check(ui.call("_watts", 0.0) == "0 W" and ui.call("_watts", -0.01) == "0 W",
		"zero power has consistent units without negative zero")
	ui.call("_refresh_metrics", {"batteries": []})
	_check((ui.get("_battery_value") as Label).text == "0 W",
		"absent battery supply shows 0 W instead of NONE")
	ui.call("_refresh_zone", {}, {})
	ui.call("_refresh_network", {}, {}, [])
	for field: String in ["_zone_counts", "_zone_brownout", "_network_counts", "_network_brownout"]:
		var copy: String = (ui.get(field) as Label).text.to_lower()
		_check(not copy.contains("nodes") and not copy.contains("edges") and not copy.contains("reachable"),
			"power summaries omit solver/debug vocabulary")
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
	await process_frame
	await process_frame
	tabs[2].grab_focus()
	nav.set("_move_cooldown", 0.0)
	nav.call("_move_focus", Vector2.RIGHT)
	_check(root.gui_get_focus_owner() == tabs[3], "right from Load Order selects Zone Network")
	var bumper := InputEventJoypadButton.new()
	bumper.button_index = JOY_BUTTON_RIGHT_SHOULDER
	bumper.pressed = true
	root.push_input(bumper)
	_check(int(ui.get("_active_tab")) == 3, "RB cycles the active tab")
	bumper.button_index = JOY_BUTTON_LEFT_SHOULDER
	root.push_input(bumper)
	_check(int(ui.get("_active_tab")) == 2, "LB cycles back to Load Order")
	ui.call("_add_priority_row", sample_consumer, [sample_consumer])
	await process_frame
	await process_frame
	var rows: Dictionary = ui.get("_priority_rows")
	var minus: Button = rows["smoke"]["decrement"]
	var plus: Button = rows["smoke"]["increment"]
	minus.grab_focus()
	nav.set("_move_cooldown", 0.0)
	nav.call("_move_focus", Vector2.RIGHT)
	_check(root.gui_get_focus_owner() == plus, "right within a load row moves from minus to plus")
	nav.set("_move_cooldown", 0.0)
	nav.call("_move_focus", Vector2.LEFT)
	_check(root.gui_get_focus_owner() == minus, "left within a load row returns to minus, not a tab")
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
