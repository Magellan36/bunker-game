extends SceneTree
## Headless notification/pause presentation contracts. Run with:
## godot --headless --path . --script res://tools/tests/notification_ui_smoke.gd

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	NotificationManager.set("_queue", [])
	NotificationManager.set("_history", [])
	NotificationManager.notify(UIKit.Domain.POWER,
		NotificationManager.Severity.WARNING, "Generator L fuel reserve low")
	NotificationManager.notify(UIKit.Domain.POWER,
		NotificationManager.Severity.WARNING, "Generator L fuel reserve low")
	var queue: Array = NotificationManager.get("_queue")
	var history: Array[Dictionary] = NotificationManager.get_history()
	_check(queue.size() == 1 and int(queue[0].count) == 2,
		"duplicate live alerts collapse with a count")
	_check(history.size() == 1 and int(history[0].count) == 2,
		"duplicate journal events collapse with a count")
	NotificationManager.feedback(UIKit.Domain.NEUTRAL,
		NotificationManager.Severity.INFO, "Item moved")
	_check(NotificationManager.get_history().size() == 1,
		"temporary feedback stays out of Bunker Log")
	_check(NotificationManager.TOAST_WIDTH == 520.0
		and NotificationManager.TOAST_HEIGHT == 48.0,
		"toast uses approved compact geometry")
	_check(NotificationManager.MAX_VISIBLE_TOASTS == 3,
		"visible stack remains capped")
	var history_ui := NotificationHistoryUI.new()
	root.add_child(history_ui)
	await process_frame
	_check(history_ui.get("_filter_buttons").size() == 5,
		"Bunker Log exposes all approved filters")
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
