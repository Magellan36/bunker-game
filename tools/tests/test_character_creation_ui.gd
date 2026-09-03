extends Node
## Headless regression coverage for the character-creation redesign.

const SCREEN_SCENE: PackedScene = preload("res://scenes/ui/character_creation/CharacterCreation.tscn")
const TEST_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3440, 1440),
]

var _failures: Array[String] = []
var _original_gender: String

func _ready() -> void:
	_original_gender = CharacterCreationData.gender
	get_tree().create_timer(25.0).timeout.connect(_on_timeout)
	_run.call_deferred()

func _run() -> void:
	for viewport_size: Vector2i in TEST_SIZES:
		await _check_resolution(viewport_size)
	await _check_native_input_and_state()
	CharacterCreationData.gender = _original_gender
	if _failures.is_empty():
		print("Character creation UI test passed across %d resolutions." % TEST_SIZES.size())
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			push_error(failure)
		get_tree().quit(1)

func _check_resolution(viewport_size: Vector2i) -> void:
	get_window().size = viewport_size
	var screen: Control = SCREEN_SCENE.instantiate() as Control
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	var layout: Control = screen.get_node("Layout") as Control
	var panel: Control = screen.get_node("Layout/Columns/SurvivorPanel") as Control
	var preview: Control = screen.get_node("Layout/Columns/PreviewColumn/PreviewStage/Preview") as Control
	var male: Button = screen.get_node("Layout/Columns/SurvivorPanel/PanelMargin/PanelContent/ChoiceScroll/FocusInset/Choices/BodyPanel/Male") as Button
	var female: Button = screen.get_node("Layout/Columns/SurvivorPanel/PanelMargin/PanelContent/ChoiceScroll/FocusInset/Choices/BodyPanel/Female") as Button
	var complete: Button = screen.get_node("Layout/Columns/SurvivorPanel/PanelMargin/PanelContent/Complete") as Button

	_expect(layout.size.x > 0.0 and layout.size.y > 0.0, "%s: layout collapsed" % viewport_size)
	_expect(panel.size.x >= 360.0, "%s: choice panel too narrow (%s)" % [viewport_size, panel.size.x])
	_expect(preview.size.x > 0.0 and preview.size.y > 0.0, "%s: preview collapsed" % viewport_size)
	_expect(male.size.y >= 68.0 and female.size.y >= 68.0, "%s: body targets below controller-friendly size" % viewport_size)
	_expect(complete.size.y >= 68.0, "%s: Complete target below controller-friendly size" % viewport_size)
	_expect(_inside_screen(panel, screen), "%s: panel escaped the screen" % viewport_size)
	_expect(_inside_screen(complete, screen), "%s: Complete escaped the screen" % viewport_size)
	_expect(screen.get_node("LegacyCustomization").visible == false, "%s: packed-away controls became visible" % viewport_size)

	# Live resize catches layout code that only runs during initial construction.
	get_window().size = Vector2i(viewport_size.x + 37, viewport_size.y + 23)
	await get_tree().process_frame
	_expect(_inside_screen(complete, screen), "%s: Complete escaped after live resize" % viewport_size)
	screen.queue_free()
	await get_tree().process_frame

func _check_native_input_and_state() -> void:
	get_window().size = Vector2i(1920, 1080)
	CharacterCreationData.gender = "male"
	var screen: Control = SCREEN_SCENE.instantiate() as Control
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	var male: Button = screen.male_button as Button
	var female: Button = screen.female_button as Button
	var randomise: Button = screen.randomise_button as Button
	var complete: Button = screen.complete_button as Button

	_expect(male.button_pressed, "saved male selection was not restored")
	_expect(male.has_focus(), "initial keyboard/controller focus is not on the restored choice")
	female.grab_focus()
	_send_action("ui_accept")
	await get_tree().process_frame
	_expect(CharacterCreationData.gender == "female", "native ui_accept did not choose Female")
	_expect(female.button_pressed and not male.button_pressed, "choice toggle state did not synchronize")
	_expect((female.get_node("Indicator") as TextureRect).texture.resource_path.contains("selected_AI_PLACEHOLDER"), "selected indicator did not synchronize")
	_expect((male.get_node("Indicator") as TextureRect).texture.resource_path.contains("unselected_AI_PLACEHOLDER"), "unselected indicator did not synchronize")

	_send_joypad_input()
	await get_tree().process_frame
	_expect((screen.get_node("%NavigationHint") as Label).text.contains("[A]"), "controller hint did not react to controller input")
	_send_key_input()
	await get_tree().process_frame
	_expect((screen.get_node("%NavigationHint") as Label).text.contains("Enter / Space"), "keyboard hint did not return after keyboard input")

	_expect(randomise.focus_mode == Control.FOCUS_ALL, "Randomise is not controller focusable")
	_expect(complete.focus_mode == Control.FOCUS_ALL, "Complete is not controller focusable")
	_expect(screen.preview_root.get_child_count() == 1, "preview should contain exactly one survivor model")
	screen.queue_free()
	await get_tree().process_frame

func _inside_screen(control: Control, screen: Control) -> bool:
	var rect: Rect2 = control.get_global_rect()
	var bounds: Rect2 = screen.get_global_rect()
	return rect.position.x >= bounds.position.x - 1.0 \
		and rect.position.y >= bounds.position.y - 1.0 \
		and rect.end.x <= bounds.end.x + 1.0 \
		and rect.end.y <= bounds.end.y + 1.0

func _send_action(action_name: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action_name
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action_name
	release.pressed = false
	Input.parse_input_event(release)

func _send_joypad_input() -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	InputMode._input(event)

func _send_key_input() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	InputMode._input(event)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _on_timeout() -> void:
	push_error("Character creation UI test timed out.")
	get_tree().quit(2)
