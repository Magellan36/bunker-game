extends SceneTree
## Headless presentation/contract smoke for the shared world prompt family.
## Run with:
## godot --headless --path . --script res://tools/tests/interaction_prompt_polish_smoke.gd

const PROMPT_SCENE: PackedScene = preload("res://scenes/ui/InteractPrompt.tscn")
const COOKING_POT_SCRIPT: GDScript = preload("res://scripts/world/items/CookingPot.gd")

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var prompt: CanvasLayer = PROMPT_SCENE.instantiate() as CanvasLayer
	root.add_child(prompt)
	await process_frame

	var panel: PanelContainer = prompt.get_node("Panel") as PanelContainer
	var chrome: Control = panel.get_node_or_null("PromptChrome") as Control
	var label: RichTextLabel = panel.get_node("VBox/HBox/Label") as RichTextLabel
	_check(chrome != null and chrome.has_method("trigger_acquire"),
		"compact prompt carries the one-shot acquisition polish")
	_check(label.get_theme_font_size("normal_font_size") == 13,
		"prompt retains its compact text scale")

	var generator_text: String = String(prompt.call("_style_prompt_semantics",
		"[E] Generator L  99% fuel  [Running]"))
	_check(generator_text.contains("99% FUEL") and generator_text.contains("● RUNNING"),
		"power prompt keeps its live fuel value and receives semantic status hierarchy")
	var battery_text: String = String(prompt.call("_style_prompt_semantics",
		"Battery Bank — 82%  [E] Info"))
	_check(battery_text.contains("82%") and battery_text.contains("│"),
		"single-divider device prompts retain their live values in the shared hierarchy")

	var cooking_text: String = String(prompt.call("_style_prompt_semantics",
		"Garden Vegetable Soup  —  Filling: 24.0  (+30% Diversity)  —  COOKING  (12/80s)"))
	_check(cooking_text.contains("Garden Vegetable Soup"), "dish preview name is retained")
	_check(cooking_text.contains("Filling: 24.0"), "dish filling value is retained")
	_check(cooking_text.contains("+30% DIVERSITY"), "diversity bonus is retained")
	_check(cooking_text.contains("● COOKING") and cooking_text.contains("12/80s"),
		"cooking state and timer are retained")

	var pot: CookingPot = COOKING_POT_SCRIPT.new() as CookingPot
	pot.slots = [
		{"node": null, "restore_value": 5.0, "ingredient_key": "food_can", "charge_badge": "1/2"},
		{"node": null, "restore_value": 4.0, "ingredient_key": "produce_carrot", "charge_badge": ""},
		null,
	]
	var descriptors: Array = pot.get_slot_icon_descriptors()
	_check(descriptors.size() == 3, "cooking pot still supplies exactly three preview slots")
	var first_descriptor: Dictionary = descriptors[0] as Dictionary
	var second_descriptor: Dictionary = descriptors[1] as Dictionary
	_check(not first_descriptor.is_empty() and String(first_descriptor.get("badge_text", "")) == "1/2",
		"partial ingredient quantity badge survives the shared presentation pass")
	_check(not second_descriptor.is_empty() and String(second_descriptor.get("produce_type", "")) == "carrot",
		"produce-specific live preview data survives the shared presentation pass")
	_check(descriptors[2] == null, "empty cooking slot stays visibly empty")

	var viewports: Array = prompt.call("_build_icon_slots", panel) as Array
	_check(viewports.size() == 3 and viewports[0] is SubViewport,
		"specialized prompt retains three pooled live-3D viewports")
	if viewports.size() == 3 and viewports[0] is SubViewport:
		_check((viewports[0] as SubViewport).size == Vector2i(48, 48),
			"ingredient previews use the polished supersampled render size")

	pot.free()
	prompt.free()
	if _failures == 0:
		print("INTERACTION_PROMPT_POLISH_SMOKE_OK")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("INTERACTION_PROMPT_POLISH_SMOKE_FAIL: %s" % message)
