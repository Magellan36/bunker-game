extends SceneTree
## Headless structure/behaviour smoke for the main menu and its surface
## backdrop. Run with:
## godot --headless --path . --script res://tools/tests/main_menu_ui_smoke.gd
## Visual approval still needs the real renderer; this guards the contracts.

const MENU_SCENE: String = "res://scenes/ui/main_menu/MainMenu.tscn"
const BACKDROP_SCENE: String = "res://scenes/world/menu_backdrop/MenuBackdrop.tscn"
const SLOT_SCRIPT: String = "res://scripts/world/menu_backdrop/BackdropAssetSlot.gd"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	await process_frame
	await _check_backdrop()
	await _check_menu()
	if _failures == 0:
		print("MAIN_MENU_UI_SMOKE_OK")
	quit(_failures)


func _check_backdrop() -> void:
	var packed := load(BACKDROP_SCENE) as PackedScene
	_check(packed != null, "backdrop scene loads")
	if packed == null:
		return
	var backdrop: Node3D = packed.instantiate() as Node3D
	root.add_child(backdrop)
	await process_frame
	for method: String in ["set_pointer", "skip_intro", "play_exit", "get_flash", "get_gust"]:
		_check(backdrop.has_method(method), "backdrop exposes %s()" % method)
	var slots := 0
	for node: Node in backdrop.find_children("*", "Node3D", true, false):
		var script := node.get_script() as Script
		if script != null and script.resource_path == SLOT_SCRIPT:
			slots += 1
			_check(not str(node.get("brief")).is_empty(), "slot %s carries an art brief" % node.name)
	_check(slots >= 10, "backdrop maps its composition as asset slots (%d)" % slots)
	var storm: Node = backdrop.get_node("Storm")
	_check(float(storm.get("MIN_PULSE_GAP")) >= 1.0 / 3.0,
		"lightning never exceeds three flashes per second")
	storm.call("trigger", 1.0)
	await process_frame
	await process_frame
	_check(float(backdrop.call("get_flash")) > 0.1, "a strike brightens the scene")
	backdrop.free()


func _check_menu() -> void:
	var packed := load(MENU_SCENE) as PackedScene
	_check(packed != null, "main menu scene loads")
	if packed == null:
		return
	var menu: Node = packed.instantiate()
	root.add_child(menu)
	await process_frame
	var screen: Control = menu.get_node("Interface/Screen") as Control
	screen.call("skip_intro")
	await process_frame

	var home: Control = screen.get("_home_list") as Control
	var items: Array[Button] = []
	for child: Node in home.get_children():
		if child is Button and (child as Button).visible:
			items.append(child as Button)
	_check(items.size() >= 5, "home view lists its actions")
	# Autoload globals are not compile-time identifiers in a --script run.
	var saves: Node = root.get_node("SaveManager")
	var any_save := false
	for slot: int in range(1, int(saves.get("SAVE_SLOT_COUNT")) + 1):
		any_save = any_save or bool(saves.call("slot_exists", slot))
	var continue_item: Button = screen.get("_continue_item") as Button
	_check(continue_item.visible == any_save, "Continue appears only when a save exists")

	var focused := root.gui_get_focus_owner()
	_check(focused != null and home.is_ancestor_of(focused), "intro ends with a home item focused")
	var focusable: Array[Button] = []
	for item: Button in items:
		if item.focus_mode == Control.FOCUS_ALL:
			focusable.append(item)
	if focusable.size() >= 2:
		var first := focusable[0]
		var last := focusable[focusable.size() - 1]
		_check(first.get_node(first.focus_neighbor_top) == last, "focus wraps from top to bottom")
		_check(last.get_node(last.focus_neighbor_bottom) == first, "focus wraps from bottom to top")

	# Load view and back via ui_cancel.
	screen.call("_show_view", 1, true)
	await process_frame
	_check(int(screen.get("_view")) == 1, "Load Game opens its view")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	screen.call("_unhandled_input", cancel)
	await process_frame
	_check(int(screen.get("_view")) == 0, "Esc/B returns to the home view")

	# Quit is two-step.
	var emitted: Array[StringName] = []
	screen.connect("action_requested", func(action: StringName, _slot: int) -> void:
		emitted.append(action))
	screen.call("_on_quit_pressed")
	_check(emitted.is_empty(), "first Quit press only asks for confirmation")
	var quit_item: Button = screen.get("_quit_item") as Button
	_check(str(quit_item.call("get_title")) != "Quit", "Quit shows its confirmation label")
	screen.call("_disarm_quit")
	_check(str(quit_item.call("get_title")) == "Quit", "confirmation times out back to Quit")

	# Credits come from the attribution file.
	var credits: Node = screen.get("_credits")
	var list: Node = credits.get("_list")
	_check(list.get_child_count() > 10, "credits render the attribution file")

	# Responsive column stays in the left portion at common sizes.
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(2560, 1440), Vector2i(3440, 1440)]:
		root.size = size
		await process_frame
		screen.call("_layout")
		var column: Control = screen.get("_column") as Control
		_check(column.position.x + column.size.x <= size.x * 0.45,
			"menu column stays in the left portion at %s" % size)
		_check(column.position.x >= 40.0, "menu column keeps a safe margin at %s" % size)
	root.size = Vector2i(1920, 1080)
	menu.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("MAIN_MENU_UI_SMOKE_FAIL: %s" % message)
