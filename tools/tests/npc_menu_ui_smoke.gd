extends SceneTree
## Headless presentation/contract smoke for the resident profile workspace.
## Run with:
## godot --headless --path . --script res://tools/tests/npc_menu_ui_smoke.gd

const UI_SCRIPT: GDScript = preload("res://scripts/ui/npc/NPCTalkMenuUI.gd")
var _failures: int = 0


class FakeBrain:
	extends Node
	var label: String = "Tending the farm"
	var command_count: int = 0

	func current_label() -> String:
		return label

	func force_command(_activity: NPCActivity) -> void:
		command_count += 1


class FakeResident:
	extends Node3D
	signal action_logged

	var npc_name: String = "Mara"
	var age: int = 34
	var health: float = 94.0
	var energy: float = 72.0
	var hunger: float = 61.0
	var thirst: float = 83.0
	var mood: float = 68.0
	var skills: Dictionary = {
		"farming": 1.3,
		"plumbing": 0.9,
		"electrical": 0.7,
		"construction": 1.1,
	}
	var brain: FakeBrain = null
	var medical: NPCMedical = null
	var entries: Array[Dictionary] = []

	func _ready() -> void:
		set_meta("_adventurer_random_gender", "female")
		brain = FakeBrain.new()
		add_child(brain)
		medical = NPCMedical.new()
		add_child(medical)
		medical.setup(self)
		entries.append({
			"text": "Mara planted potatoes",
			"fired_at_msec": Time.get_ticks_msec(),
			"game_time": "Day 2, 12:45",
		})

	func get_relationship(_target_id: String) -> float:
		return 28.0

	func get_relationship_label(_target_id: String) -> String:
		return "Friendly"

	func get_personality_words() -> Array[String]:
		return ["Observant", "Resolute", "Reserved"]

	func get_irritability_label() -> String:
		return ""

	func get_dialogue_line() -> String:
		return "Hydroponics are looking better today."

	func get_relationship_dialogue_line(target_id: String) -> String:
		return "I trust %s." % target_id

	func get_other_npc_topics() -> Array[Dictionary]:
		return [{"id": "npc_2", "name": "Finch"}]

	func get_action_log() -> Array[Dictionary]:
		return entries.duplicate()

	func is_relaxing() -> bool:
		return false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var resident: FakeResident = FakeResident.new()
	root.add_child(resident)
	await process_frame

	var wound: MedicalCondition = MedicalCondition.new()
	wound.id = "open_wound"
	wound.body_part = MedicalCondition.BodyPart.LEFT_ARM
	wound.severity = 100.0
	resident.medical.add_condition(wound)

	var ui: NPCTalkMenuUI = UI_SCRIPT.new() as NPCTalkMenuUI
	root.add_child(ui)
	await process_frame
	await process_frame

	_check(ui != null, "resident profile instantiates")
	var panel: PanelContainer = ui.get("_panel") as PanelContainer
	_check(panel != null, "modern native resident shell exists")
	if panel != null:
		_check(panel.size.x <= 1420.0 and panel.size.y <= 820.0,
			"workspace keeps approved desktop bounds")
	var tabs: Array = ui.get("_tab_buttons") as Array
	var pages: Array = ui.get("_pages") as Array
	_check(tabs.size() == 5 and pages.size() == 5,
		"overview, talk, requests, health, and activity log tabs exist")
	var needs: Dictionary = ui.get("_need_bars") as Dictionary
	var skills: Dictionary = ui.get("_skill_bars") as Dictionary
	_check(needs.size() == 5, "all five resident needs remain persistent")
	_check(skills.size() == 4, "all four established NPC skills are presented")
	var navigation: ControllerUINavigation = ui.get("_controller_nav") as ControllerUINavigation
	_check(
		navigation != null and navigation.right_stick_navigation and not navigation.stick_navigation,
		"d-pad/right-stick navigate while left stick remains player movement"
	)

	ui.open("Mara", resident)
	await process_frame
	_check(ui.is_open() and ui.visible, "resident profile opens")
	_check(int(ui.get("_active_tab")) == 0, "profile always opens on useful Overview tab")
	var portrait: NPCPortraitViewport = ui.get("_portrait") as NPCPortraitViewport
	_check(portrait != null, "persistent resident portrait exists")
	var portrait_viewport: SubViewport = portrait.get("_viewport") as SubViewport
	_check(
		portrait_viewport != null and portrait_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"portrait renders while the profile is open"
	)
	_check((ui.get("_relationship_meter") as NPCRelationshipMeter).value == 28.0,
		"real relationship value drives the relationship meter")

	ui.call("_set_tab", 1, true)
	_check((ui.get("_dialogue_label") as Label).text == "Hydroponics are looking better today.",
		"Talk delegates to established NPC dialogue")
	ui.call("_set_tab", 3, true)
	var medical_buttons: Dictionary = ui.get("_medical_part_buttons") as Dictionary
	_check(medical_buttons.has(MedicalCondition.BodyPart.LEFT_ARM),
		"Health presents real NPCMedical body-region data")
	var job_buttons: Array = ui.get("_job_buttons") as Array
	_check(job_buttons.size() == 6,
		"all six established work orders remain available")

	ui.close()
	_check(not ui.is_open() and not ui.visible, "close hides the resident profile")
	_check(portrait_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"portrait rendering stops when the profile closes")

	ui.free()
	resident.free()
	if _failures == 0:
		print("NPC_MENU_UI_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("NPC_MENU_UI_SMOKE_FAIL: %s" % message)
