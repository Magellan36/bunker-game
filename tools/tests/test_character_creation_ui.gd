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
	# Test actual UI viewport sizes, not six OS sizes stretched over one canvas.
	get_window().mode = Window.MODE_WINDOWED
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	_original_gender = CharacterCreationData.gender
	get_tree().create_timer(40.0).timeout.connect(_on_timeout)
	_run.call_deferred()

func _run() -> void:
	for viewport_size: Vector2i in TEST_SIZES:
		await _check_resolution(viewport_size)
	await _check_native_input_and_state()
	await _check_female_restore()
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
	for frame: int in range(4):
		await get_tree().process_frame
	_expect(Vector2i(get_viewport().get_visible_rect().size) == viewport_size, "test viewport does not match requested size")

	var preview: Control = screen.preview_container as Control
	var male: Button = screen.male_button as Button
	var complete: Button = screen.complete_button as Button
	var column: Control = screen.get_node("Interface/Column") as Control
	var footer_left: Control = screen.get_node("Interface/FooterLeft") as Control
	var footer_right: Control = screen.get_node("Interface/FooterRight") as Control

	_expect(preview.size.x > 0.0 and preview.size.y > 0.0, "%s: preview collapsed" % viewport_size)
	## RX 580 mitigation: the preview render target stays near 960x1080.
	_expect(preview.size.x * preview.size.y <= 1.35 * 1920.0 * 1080.0 * 0.55 * maxf(1.0, viewport_size.y / 1080.0) ** 2,
		"%s: preview render target grew unexpectedly (%s)" % [viewport_size, preview.size])
	for button: Button in [screen.male_button, screen.female_button, screen.randomise_button, complete]:
		_expect(button.size.y >= 40.0, "%s: %s below controller-friendly size" % [viewport_size, button.name])
		_expect(_inside_screen(button, screen), "%s: %s escaped the screen" % [viewport_size, button.name])
	_expect(column.get_global_rect().end.x <= preview.get_global_rect().position.x + preview.size.x * 0.3,
		"%s: choice column runs deep into the subject" % viewport_size)
	_expect(_inside_screen(footer_left, screen) and _inside_screen(footer_right, screen), "%s: footer escaped" % viewport_size)
	_expect(not footer_left.get_global_rect().intersects(footer_right.get_global_rect()), "%s: footers overlap" % viewport_size)
	_expect(complete.get_global_rect().end.y < footer_left.get_global_rect().position.y, "%s: Begin collides with footer" % viewport_size)

	# Live resize catches layout code that only runs during initial construction.
	get_window().size = Vector2i(viewport_size.x + 37, viewport_size.y + 23)
	await get_tree().process_frame
	_expect(_inside_screen(complete, screen), "%s: Begin escaped after live resize" % viewport_size)
	screen.queue_free()
	await get_tree().process_frame

func _check_female_restore() -> void:
	get_window().size = Vector2i(1280, 720)
	CharacterCreationData.gender = "female"
	var screen: Control = SCREEN_SCENE.instantiate() as Control
	add_child(screen)
	for frame: int in range(5):
		await get_tree().process_frame
	_expect(screen.female_button.button_pressed and not screen.male_button.button_pressed, "Female selection was not restored")
	_expect(screen.female_button.has_focus(), "initial focus is not on the restored Female choice")
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
	_expect(male.call("get_title") == "Male", "Male option lost its label")
	female.grab_focus()
	_send_action("ui_accept")
	await get_tree().process_frame
	_expect(CharacterCreationData.gender == "female", "native ui_accept did not choose Female")
	_expect(female.button_pressed and not male.button_pressed, "choice toggle state did not synchronize")
	_expect(is_equal_approx(female.size.y, male.size.y), "choice heights differ, so selection shifts the layout")
	await get_tree().create_timer(0.6).timeout   ## cross-fade rebuild
	_expect(screen.preview_root.get_child_count() == 1, "preview should contain exactly one survivor model after a swap")

	_expect(randomise.focus_mode == Control.FOCUS_ALL, "Randomise is not controller focusable")
	_expect(complete.focus_mode == Control.FOCUS_ALL, "Begin is not controller focusable")
	_expect(screen.back_button.focus_mode == Control.FOCUS_NONE, "mouse-only back link joined the focus chain")
	complete.grab_focus()
	_send_action("ui_down")
	await get_tree().process_frame
	_expect(male.has_focus(), "focus does not wrap from Begin to the first choice")
	for i: int in range(6):
		randomise.emit_signal("pressed")
	await get_tree().create_timer(0.6).timeout
	_expect(screen.preview_root.get_child_count() == 1, "rapid randomising stacked survivor models")
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

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _on_timeout() -> void:
	push_error("Character creation UI test timed out.")
	get_tree().quit(2)
