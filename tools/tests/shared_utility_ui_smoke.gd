extends SceneTree
## Headless presentation/contract smoke for shared confirmation and trash-item UI.
## Run with:
## godot --headless --path . --script res://tools/tests/shared_utility_ui_smoke.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	var confirm_script: GDScript = load("res://scripts/ui/common/ConfirmDialogUI.gd") as GDScript
	var trash_script: GDScript = load("res://scripts/ui/common/TrashBagInfoPanel.gd") as GDScript
	var dialog: CanvasLayer = confirm_script.new() as CanvasLayer
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
	_check(not dialog.is_open() and dialog.visible,
		"confirmation ends interaction before its short exit finishes")
	dialog.open("Expand the bunker?", "", "Excavate  ·  $1,500", "Cancel", "purchase", "demolish")
	await create_timer(UIMotion.EXIT + 0.04).timeout
	_check(dialog.is_open() and dialog.visible,
		"reopening confirmation cancels its stale close")
	_check(not (dialog.get("_message_card") as PanelContainer).visible,
		"excavation confirmation omits its redundant explanatory tooltip")
	_check(confirmation_panel.size.y <= 224.0,
		"message-free confirmation uses the compact bounded layout")
	dialog.close()

	var trash_panel: CanvasLayer = trash_script.new() as CanvasLayer
	root.add_child(trash_panel)
	await process_frame
	var shell: PanelContainer = trash_panel.get("_panel") as PanelContainer
	_check(shell != null and shell.custom_minimum_size.x == 330.0,
		"trash context card uses bounded compact width")
	var bag_script: GDScript = load("res://scripts/world/items/TrashBag.gd") as GDScript
	var bag: Node3D = bag_script.new() as Node3D
	var records: Array[Dictionary] = [
		{"display_name": "Water Bottle", "item_type": "water_bottle", "data": {
			"current_fill_mL": 240.0, "stored_water_quality": 82.0, "material": "plastic"}},
		{"display_name": "Flashlight", "item_type": "flashlight", "data": {
			"_battery": 46.0, "material": "metal"}},
	]
	bag.set("contents", records)
	root.add_child(bag)
	trash_panel.set("_bag", bag)
	trash_panel.call("_rebuild_contents")
	var rows: VBoxContainer = trash_panel.get("_list_box") as VBoxContainer
	_check(rows.get_child_count() == 2, "trash records become individual context rows")
	_check((trash_panel.get("_count_label") as Label).text == "2 ITEMS",
		"trash context presents item count")
	var first_copy: Array[String] = _label_text(rows.get_child(0))
	var second_copy: Array[String] = _label_text(rows.get_child(1))
	_check("240 mL  •  82% quality" in first_copy,
		"serialized water detail uses shared formatting")
	_check("46% charge  •  Metal" in second_copy,
		"serialized battery detail uses shared formatting")

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


func _label_text(node: Node) -> Array[String]:
	var result: Array[String] = []
	if node is Label:
		result.append((node as Label).text)
	for child: Node in node.get_children():
		result.append_array(_label_text(child))
	return result
