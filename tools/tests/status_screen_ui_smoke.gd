extends SceneTree
## Headless presentation/contract smoke for the general player Status workspace.
## Run with:
## godot --headless --path . --script res://tools/tests/status_screen_ui_smoke.gd

const UI_SCRIPT: GDScript = preload("res://scripts/ui/medical/StatusScreenUI.gd")
const MEDICAL_SCRIPT: GDScript = preload("res://scripts/player/medical/PlayerMedical.gd")
const STATS_SCRIPT: GDScript = preload("res://scripts/player/PlayerStats.gd")
const INVENTORY_SCRIPT: GDScript = preload("res://scripts/ui/inventory/InventoryManager.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var medical: PlayerMedical = MEDICAL_SCRIPT.new() as PlayerMedical
	var stats: PlayerStats = STATS_SCRIPT.new() as PlayerStats
	var inventory: Node = INVENTORY_SCRIPT.new() as Node
	root.add_child(stats)
	root.add_child(medical)
	root.add_child(inventory)

	var wound: MedicalCondition = MedicalCondition.new()
	wound.id = "open_wound"
	wound.body_part = MedicalCondition.BodyPart.LEFT_ARM
	wound.severity = 100.0
	wound.has_heal_ring = true
	medical.add_condition(wound)
	var bleed: MedicalCondition = MedicalCondition.new()
	bleed.id = "bleeding"
	bleed.body_part = MedicalCondition.BodyPart.LEFT_ARM
	bleed.severity = 42.0
	medical.add_condition(bleed)

	var ui: StatusScreenUI = UI_SCRIPT.new() as StatusScreenUI
	ui.player_medical = medical
	ui.player_stats = stats
	ui.inventory = inventory
	root.add_child(ui)
	await process_frame
	await process_frame

	_check(ui != null, "status workspace instantiates")
	var panel: PanelContainer = ui.get("_panel") as PanelContainer
	_check(panel != null, "modern native shell exists")
	if panel != null:
		_check(panel.size.x <= 1420.0 and panel.size.y <= 820.0,
			"workspace keeps approved desktop bounds")
	var tabs: Array = ui.get("_tab_buttons") as Array
	var pages: Array = ui.get("_pages") as Array
	_check(tabs.size() == 4 and pages.size() == 4,
		"overview, health, needs, and inventory sections exist")
	var summaries: Dictionary = ui.get("_summary_metrics") as Dictionary
	_check(summaries.size() == 5,
		"persistent health, food, water, stamina, and sleep summary exists")
	var navigation: Node = ui.get("_controller_nav") as Node
	_check(
		(
			navigation != null
			and bool(navigation.get("right_stick_navigation"))
			and not bool(navigation.get("stick_navigation"))
		),
		"d-pad/right-stick navigate while left stick remains player movement"
	)

	ui.open()
	_check(ui.is_open() and ui.visible, "Tab workspace opens non-modally")
	ui.call("_set_tab", 1)
	ui.call("_select_body_part", MedicalCondition.BodyPart.LEFT_ARM)
	var condition_cards: Dictionary = ui.get("_condition_cards") as Dictionary
	_check(condition_cards.size() == 2,
		"health section presents each active condition on the selected body region")
	_check(String(ui.call("_treatment_kind", bleed)) == "bandage",
		"bleeding retains Bandage treatment mapping")
	_check(String(ui.call("_treatment_kind", wound)) == "antibiotics",
		"open wounds retain Antibiotics treatment mapping")
	var inventory_cards: Array = ui.get("_inventory_cards") as Array
	var viewports: Array = ui.get("_inventory_viewports") as Array
	_check(inventory_cards.size() == 4 and viewports.size() == 4,
		"all quick slots have persistent prebuilt preview viewports")
	ui.close()
	_check(not ui.is_open() and not ui.visible, "close hides the reusable workspace")

	ui.free()
	inventory.free()
	medical.free()
	stats.free()
	if _failures == 0:
		print("STATUS_SCREEN_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("STATUS_SCREEN_UI_SMOKE_FAIL: %s" % message)
