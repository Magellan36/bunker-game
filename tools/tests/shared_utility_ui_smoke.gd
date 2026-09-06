extends SceneTree
## Headless presentation/contract smoke for shared confirmation and trash-item UI.
## Run with:
## godot --headless --path . --script res://tools/tests/shared_utility_ui_smoke.gd

const CONFIRM_SCRIPT: GDScript = preload("res://scripts/ui/common/ConfirmDialogUI.gd")
const TRASH_PANEL_SCRIPT: GDScript = preload("res://scripts/ui/common/TrashBagInfoPanel.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dialog: ConfirmDialogUI = CONFIRM_SCRIPT.new() as ConfirmDialogUI
	root.add_child(dialog)
	await process_frame
	dialog.open("Exit to desktop?", "Unsaved progress will be lost.",
		"Exit game", "Stay here", "danger", "exit")
	await process_frame
	await process_frame
	_check(dialog.is_open() and dialog.visible, "confirmation opens through preserved contract")
	var confirmation_panel: PanelContainer = dialog.get("_panel") as PanelContainer
	_check(confirmation_panel.size.x <= 560.0,
		"confirmation keeps compact desktop proportions")
	var viewport_size: Vector2 = root.get_visible_rect().size
	_check(confirmation_panel.position.y >= 24.0
		and confirmation_panel.position.y + confirmation_panel.size.y <= viewport_size.y - 24.0,
		"confirmation is viewport-bounded on its first open")
	_check((dialog.get("_confirm_button") as Button).text == "Exit game",
		"confirmation presents contextual affirmative wording")
	_check((dialog.get("_cancel_button") as Button).text == "Stay here",
		"confirmation presents contextual safe wording")
	_check((dialog.get("_controller_nav") as ControllerUINavigation).right_stick_navigation,
		"confirmation supports d-pad and right-stick navigation")
	dialog.close()
	_check(not dialog.is_open() and not dialog.visible, "confirmation closes cleanly")
	dialog.open("Expand the bunker?", "", "Excavate  ·  $1,500", "Cancel", "purchase", "demolish")
	await process_frame
	await process_frame
	_check(not (dialog.get("_message_card") as PanelContainer).visible,
		"excavation confirmation omits its redundant explanatory tooltip")
	_check(confirmation_panel.size.y <= 224.0,
		"message-free confirmation uses the compact bounded layout")
	dialog.close()

	var trash_panel: CanvasLayer = TRASH_PANEL_SCRIPT.new() as CanvasLayer
	root.add_child(trash_panel)
	await process_frame
	var shell: PanelContainer = trash_panel.get("_panel") as PanelContainer
	_check(shell != null and shell.custom_minimum_size.x == 330.0,
		"trash context card uses bounded compact width")
	var bag: TrashBag = TrashBag.new()
	bag.contents = [
		{"display_name": "Water Bottle", "item_type": "water_bottle", "data": {
			"current_fill_mL": 240.0, "stored_water_quality": 82.0, "material": "plastic"}},
		{"display_name": "Flashlight", "item_type": "flashlight", "data": {
			"_battery": 46.0, "material": "metal"}},
	]
	root.add_child(bag)
	trash_panel.set("_bag", bag)
	trash_panel.call("_rebuild_contents")
	var rows: VBoxContainer = trash_panel.get("_list_box") as VBoxContainer
	_check(rows.get_child_count() == 2, "trash records become individual context rows")
	_check((trash_panel.get("_count_label") as Label).text == "2 ITEMS",
		"trash context presents item count")

	dialog.free()
	trash_panel.free()
	bag.free()
	if _failures == 0:
		print("SHARED_UTILITY_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("SHARED_UTILITY_UI_SMOKE_FAIL: %s" % message)
