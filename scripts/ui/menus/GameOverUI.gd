extends CanvasLayer
## GameOverUI.gd — shown when the player's HP hits 0 (permanent death).
## Sep 2026 quiet pass: the main-menu language. The dying clip plays out, a
## curtain settles over the bunker, "You died" resolves from wide tracking in
## a left-third column, then three text actions with the gliding rail:
##   Load last save  — newest slot, rebuilt through the LoadingScreen (death
##                     is final in this world, so a fresh world is loaded;
##                     the old `load_game(0)` never worked: slots are 1..3)
##   Main menu       — WorldManager.leave_world() back to the boot scene
##   Quit to desktop
## Instantiated on demand by MainWorld._open_game_over().

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const ITEM_SCRIPT: GDScript = preload("res://scripts/ui/main_menu/MainMenuItem.gd")
const FOCUS_RAIL: GDScript = preload("res://scripts/ui/common/FocusRail.gd")
const NAV_SCRIPT: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const SLOT_FORMAT: GDScript = preload("res://scripts/ui/common/SaveSlotFormat.gd")
const FONT_BOLD: FontFile = preload("res://assets/fonts/IosevkaCharon-Bold.ttf")
const LOADING_SCENE: String = "res://scenes/ui/LoadingScreen.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu/MainMenu.tscn"

## The screen deliberately appears a beat after death (so the dying collapse
## plays out) and settles slowly instead of popping up.
const FADE_DELAY: float = 1.5
const FADE_DURATION: float = 1.5
const TRACKING: float = 0.15

var _dim: ColorRect = null
var _column: VBoxContainer = null
var _title: Label = null
var _title_font: FontVariation = null
var _rule: ColorRect = null
var _items: Array[Button] = []
var _load_item: Button = null
var _rail: Control = null
var _curtain: ColorRect = null
var _latest_slot: int = 0
var _leaving: bool = false
var _s: float = 1.0

func _ready() -> void:
	layer = 200   ## above pause menu (200 is PauseMenuUI's layer)
	visible = false
	_build()
	get_viewport().size_changed.connect(_layout)
	get_viewport().gui_focus_changed.connect(func(control: Control) -> void:
		if control in _items:
			_rail.call("set_target", control))

func _build() -> void:
	var root := Control.new()
	root.name = "GameOver"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	BunkerUIComponents.apply_theme(root)
	add_child(root)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.027, 0.027, 0.84)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP   ## block clicks behind
	root.add_child(_dim)
	_rail = FOCUS_RAIL.new()
	_rail.set("color", Q.ACCENT)
	root.add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", 0)
	root.add_child(_column)
	var eyebrow: Label = Q.eyebrow(_eyebrow_text(), 13)
	_column.add_child(eyebrow)
	_column.add_child(_gap(14.0))
	_title_font = FontVariation.new()
	_title_font.base_font = FONT_BOLD
	_title = Q.label("YOU DIED", 96, Q.TEXT)
	_title.add_theme_font_override("font", _title_font)
	_column.add_child(_title)
	var rule_holder := Control.new()
	rule_holder.custom_minimum_size.y = 24.0
	rule_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(rule_holder)
	_rule = ColorRect.new()
	_rule.color = BunkerDesign.BRASS
	_rule.position = Vector2(4.0, 8.0)
	_rule.size = Vector2(0.0, 2.0)
	rule_holder.add_child(_rule)
	_column.add_child(Q.label("The bunker falls silent.", 19, Q.MUTED))
	_column.add_child(_gap(56.0))

	_load_item = _item("Load last save", _on_load_pressed)
	_item("Main menu", _on_menu_pressed)
	_item("Quit to desktop", _on_quit_pressed)
	_refresh_load_caption()

	_curtain = ColorRect.new()
	_curtain.color = Color.BLACK
	_curtain.modulate.a = 0.0
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_curtain)
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var nav: Node = NAV_SCRIPT.new()
	nav.set("ui_root", root)
	nav.set("close_on_cancel", false)
	add_child(nav)
	_layout()

func _item(title: String, callback: Callable) -> Button:
	var item: Button = ITEM_SCRIPT.new()
	item.call("setup", title)
	item.call("set_accent_color", Q.ACCENT)
	item.pressed.connect(func() -> void:
		if not _leaving:
			callback.call())
	_column.add_child(item)
	_items.append(item)
	return item

func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.set_meta(&"base_height", height)
	return gap

func _eyebrow_text() -> String:
	var stats: Node = get_tree().get_first_node_in_group("player_stats") if is_inside_tree() else null
	if stats != null and "current_day" in stats:
		return "Bunker Game  ·  Day %d" % int(stats.get("current_day"))
	return "Bunker Game"

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	_s = clampf(minf(viewport.y / 1080.0, viewport.x / 1920.0 * 1.15), 0.66, 1.4)
	_column.position = Vector2(clampf(viewport.x * 0.085, 48.0 * _s, 420.0 * _s), viewport.y * 0.28)
	_column.size = Vector2(600.0 * _s, viewport.y * 0.6)
	_title.add_theme_font_size_override("font_size", roundi(96.0 * _s))
	for item: Button in _items:
		item.call("apply_ui_scale", _s)
	_rail.set("ui_scale", _s)

func _refresh_load_caption() -> void:
	var newest := ""
	_latest_slot = 0
	for slot: int in range(1, SaveManager.SAVE_SLOT_COUNT + 1):
		var info: Dictionary = SaveManager.get_slot_info(slot)
		if info.get("exists", false) and (_latest_slot == 0 or str(info.get("timestamp", "")) > newest):
			newest = str(info.get("timestamp", ""))
			_latest_slot = slot
	if _latest_slot > 0:
		var info: Dictionary = SaveManager.get_slot_info(_latest_slot)
		_load_item.call("set_caption", "Slot %d  ·  %s" % [_latest_slot, SLOT_FORMAT.describe(info)])
		_load_item.disabled = false
	else:
		_load_item.call("set_caption", "No save found")
		_load_item.disabled = true
		_load_item.focus_mode = Control.FOCUS_NONE

func _set_tracking(amount: float) -> void:
	_title_font.spacing_glyph = roundi(96.0 * _s * TRACKING * amount)

func open() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	## Deliberately NOT pausing the tree — the player's dying clip must play
	## out behind the dim (a paused tree would freeze it mid-collapse). The
	## player is dead + movement-locked, so nothing meaningful continues.
	_refresh_load_caption()
	_dim.modulate.a = 0.0
	_column.modulate.a = 0.0
	for item: Button in _items:
		item.modulate.a = 0.0
	_set_tracking(2.6)
	await get_tree().create_timer(FADE_DELAY).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(_dim, "modulate:a", 1.0, UIMotion.duration(FADE_DURATION))
	t.tween_property(_column, "modulate:a", 1.0, UIMotion.duration(1.2)).set_delay(UIMotion.duration(0.6))
	t.tween_method(_set_tracking, 2.6, 1.0, UIMotion.duration(2.2)).set_delay(UIMotion.duration(0.6)) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_rule, "size:x", 56.0 * _s, UIMotion.duration(0.8)).set_delay(UIMotion.duration(1.4)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i: int in _items.size():
		var at := UIMotion.duration(1.8 + 0.08 * float(i))
		t.tween_property(_items[i], "modulate:a", 1.0, UIMotion.duration(0.45)).set_delay(at)
	t.tween_callback(func() -> void:
		var first: Button = _load_item if not _load_item.disabled else _items[1]
		first.grab_focus()
		_rail.call("snap")).set_delay(UIMotion.duration(1.8))

func _leave(scene_path: String) -> void:
	_leaving = true
	var t := create_tween()
	t.tween_property(_curtain, "modulate:a", 1.0, UIMotion.duration(0.7)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		var error: Error = WorldManager.leave_world(scene_path)
		if error != OK:
			push_error("[GameOver] Could not open %s (error %d)" % [scene_path, error])
			_leaving = false
			_curtain.modulate.a = 0.0
			return
		queue_free())

func _on_load_pressed() -> void:
	if _latest_slot <= 0:
		return
	var info: Dictionary = SaveManager.get_slot_info(_latest_slot)
	var gender := str(info.get("gender", ""))
	if gender == "male" or gender == "female":
		CharacterCreationData.gender = gender
	WorldManager.pending_load_slot = _latest_slot
	_leave(LOADING_SCENE)

func _on_menu_pressed() -> void:
	_leave(MAIN_MENU_SCENE)

func _on_quit_pressed() -> void:
	get_tree().quit()
