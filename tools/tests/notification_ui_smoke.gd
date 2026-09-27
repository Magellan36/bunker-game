extends SceneTree
## Headless notification/pause presentation contracts. Run with:
## godot --headless --path . --script res://tools/tests/notification_ui_smoke.gd

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	var notifications: Node = root.get_node("NotificationManager")
	var constants: Dictionary = (notifications.get_script() as Script).get_script_constant_map()
	var severity: Dictionary = constants.get("Severity", {}) as Dictionary
	var warning: int = int(severity.get("WARNING", 1))
	var info: int = int(severity.get("INFO", 0))
	notifications.set("_queue", [])
	notifications.set("_history", [])
	notifications.call("notify", UIKit.Domain.POWER, warning, "Generator L fuel reserve low")
	notifications.call("notify", UIKit.Domain.POWER, warning, "Generator L fuel reserve low")
	var queue: Array = notifications.get("_queue")
	var history: Array[Dictionary] = notifications.call("get_history") as Array[Dictionary]
	_check(queue.size() == 1 and int(queue[0].count) == 2,
		"duplicate live alerts collapse with a count")
	_check(history.size() == 1 and int(history[0].count) == 2,
		"duplicate journal events collapse with a count")
	notifications.call("feedback", UIKit.Domain.NEUTRAL, info, "Item moved")
	_check((notifications.call("get_history") as Array).size() == 1,
		"temporary feedback stays out of Bunker Log")
	notifications.call("notify", UIKit.Domain.INVENTORY, warning, "Inventory full")
	_check((notifications.call("get_history") as Array).size() == 2,
		"inventory warnings are journaled in Bunker Log")
	_check(float(constants.get("TOAST_WIDTH", 0.0)) == 520.0
		and float(constants.get("TOAST_HEIGHT", 0.0)) == 48.0,
		"toast uses approved compact geometry")
	_check(int(constants.get("MAX_VISIBLE_TOASTS", 0)) == 3,
		"visible stack remains capped")
	# History is already captured; keep the headless renderer from repeatedly
	# drawing live toasts while the log view is exercised.
	notifications.set("_queue", [])
	var history_script: GDScript = load("res://scripts/ui/notifications/NotificationHistoryUI.gd") as GDScript
	var history_ui: Control = history_script.new() as Control
	root.add_child(history_ui)
	await process_frame
	_check(history_ui.get("_filter_buttons").size() == 6,
		"Log exposes all approved filters")
	_check(_tree_contains_text(history_ui, "Log")
		and not _tree_contains_text(history_ui, "Bunker Log")
		and not _tree_contains_text(history_ui, "Recent shelter activity"),
		"pause history uses the compact Log heading without a subtitle")
	var filter_buttons: Dictionary = history_ui.get("_filter_buttons") as Dictionary
	_check(filter_buttons.values().all(func(button: Button) -> bool:
		return button.custom_minimum_size.y <= 30.0 and _button_is_borderless(button)),
		"pause Log filters are compact and borderless")
	_check(history_ui.theme != null and history_ui.theme.default_font == UIKit.font(),
		"pause Log uses the shared bunker font")
	history_ui.call("_set_filter", "Inventory")
	_check(history_ui.get("_row_entries").size() == 1,
		"inventory filter retains matching events")
	history_ui.call("_set_filter", "Power")
	_check(history_ui.get("_row_entries").size() == 1,
		"domain filter retains matching event")
	history_ui.call("_set_filter", "Water")
	_check(history_ui.get("_row_entries").is_empty(),
		"domain filter removes unrelated events")
	history_ui.free()
	if failures == 0:
		print("NOTIFICATION_UI_SMOKE_OK")
	quit(failures)

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)

func _button_is_borderless(button: Button) -> bool:
	var style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	return style != null and style.border_width_left == 0 \
		and style.border_width_top == 0 and style.border_width_right == 0 \
		and style.border_width_bottom == 0

func _tree_contains_text(root_node: Node, expected: String) -> bool:
	if root_node is Label and (root_node as Label).text == expected:
		return true
	for child: Node in root_node.get_children():
		if _tree_contains_text(child, expected):
			return true
	return false
