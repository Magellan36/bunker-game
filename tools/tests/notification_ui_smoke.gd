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
	# Sep 2026 quiet pass (decision D2): compact cards top-right under cash.
	_check(float(constants.get("TOAST_WIDTH", 0.0)) == 360.0
		and float(constants.get("TOAST_EDGE", 0.0)) == 24.0,
		"toast uses the quiet top-right geometry")
	_check(str(constants.get("TOAST_AVOID_GROUP", "")) == "ui_toast_avoid",
		"toasts avoid registered surfaces")
	_check(int(constants.get("MAX_VISIBLE_TOASTS", 0)) == 3,
		"visible stack remains capped")
	# Regression (Sep 2026): a toast held behind a modal has its card retired
	# and freed; when the modal closes the same entry must get a fresh card
	# instead of touching the freed one ("Left operand of 'is' ... freed").
	notifications.call("clear_transient_queue")
	notifications.call("feedback", UIKit.Domain.POWER, info, "Held toast regression")
	for i: int in range(4):
		await process_frame
	var modal_layer := CanvasLayer.new()
	root.add_child(modal_layer)
	var modal := Control.new()
	modal_layer.add_child(modal)
	modal.size = Vector2(400, 300)
	preload("res://scripts/ui/common/QuietControls.gd").avoid_toasts(modal, true)
	await create_timer(0.5).timeout
	modal_layer.queue_free()
	for i: int in range(6):
		await process_frame
	var held_view: Variant = null
	for entry: Dictionary in notifications.get("_queue"):
		if str(entry.get("text", "")) == "Held toast regression":
			held_view = entry.get("view")
	_check(is_instance_valid(held_view) and (held_view as Control).visible,
		"a toast held behind a modal returns with a fresh card")
	# History is already captured; keep the headless renderer from repeatedly
	# drawing live toasts while the log view is exercised.
	notifications.call("clear_transient_queue")
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
