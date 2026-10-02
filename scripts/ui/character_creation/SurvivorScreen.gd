extends Control
## SurvivorScreen.gd (Sep 2026) — character creation, rebuilt in the quiet
## main-menu language (docs/ui/QUIET_DESIGN_SYSTEM.md, plan Pass 2B / D3).
##
## Text left, subject right — the same composition as the main menu. The
## survivor stands in the right half under a single warm key light (the
## bunker lamp motif) with a cool rim; the key light "switches on" as the
## screen opens. The left column holds a text-only choice list with the
## shared FocusRail, a "Selected" caption on the chosen body, Randomise and
## Begin. Body choice writes CharacterCreationData.gender; the live preview
## is the real AdventurerModel (read at _ready, so it is rebuilt on change).
##
## The packed-away hair/feature/accessory system lives on, unreferenced, in
## CharacterCreationScreen.gd (see docs/systems/character-creation).

const Q: GDScript = preload("res://scripts/ui/common/QuietControls.gd")
const ITEM_SCRIPT: GDScript = preload("res://scripts/ui/main_menu/MainMenuItem.gd")
const FOCUS_RAIL: GDScript = preload("res://scripts/ui/common/FocusRail.gd")
const NAV_SCRIPT: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const PREVIEW_SCENE_PATH: String = "res://scenes/player/AdventurerModel.tscn"
const NEXT_SCENE_PATH: String = "res://scenes/ui/LoadingScreen.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/ui/main_menu/MainMenu.tscn"
const PREVIEW_SCALE: float = 1.25
const KEY_ENERGY: float = 1.35

@export var preview_root: Node3D
@export var preview_container: SubViewportContainer
@export var key_light: DirectionalLight3D
@export var curtain: ColorRect
@export var floor_glow: TextureRect

var male_button: Button
var female_button: Button
var randomise_button: Button
var complete_button: Button
var back_button: Button

var _s: float = 1.0
var _column: VBoxContainer
var _title: Label
var _rule: ColorRect
var _rail: Control
var _footer_left: HBoxContainer
var _footer_right: HBoxContainer
var _error_label: Label
var _preview_instance: Node3D
var _preview_tween: Tween
var _leaving: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	BunkerUIComponents.apply_theme(self)
	_build()
	get_viewport().size_changed.connect(_layout)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_layout()
	_sync_selection()
	_rebuild_preview()
	var nav: Node = NAV_SCRIPT.new()
	nav.set("ui_root", self)
	nav.set("close_on_cancel", false)   ## B returns to the menu via _unhandled_input
	add_child(nav)
	_play_intro()


# ── Build ────────────────────────────────────────────────────────────────────

func _build() -> void:
	var interface := Control.new()
	interface.name = "Interface"
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(interface)
	move_child(interface, curtain.get_index())   ## below the curtain
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_rail = FOCUS_RAIL.new()
	_rail.set("color", Q.ACCENT)
	interface.add_child(_rail)
	_rail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", 0)
	interface.add_child(_column)
	_column.add_child(Q.eyebrow("New game", 13))
	_column.add_child(_gap(10.0))
	_title = Q.label("Your survivor", 60, Q.TEXT)
	_title.name = "Title"
	_column.add_child(_title)
	var rule_holder := Control.new()
	rule_holder.custom_minimum_size.y = 26.0
	rule_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(rule_holder)
	_rule = ColorRect.new()
	_rule.color = BunkerDesign.BRASS
	_rule.position = Vector2(4.0, 10.0)
	_rule.size = Vector2(56.0, 2.0)
	rule_holder.add_child(_rule)
	_column.add_child(Q.label("Choose who goes below.", 19, Q.MUTED))
	_column.add_child(_gap(44.0))
	_column.add_child(Q.eyebrow("Body", 12))
	_column.add_child(_gap(8.0))

	var body_group := ButtonGroup.new()
	male_button = _item("Male", func() -> void: _choose("male"))
	female_button = _item("Female", func() -> void: _choose("female"))
	for choice: Button in [male_button, female_button]:
		choice.set("reserve_caption", true)
		choice.toggle_mode = true
		choice.button_group = body_group
	randomise_button = _item("Randomise", _on_randomise_pressed)
	_column.add_child(_gap(30.0))
	complete_button = _item("Begin", _on_complete_pressed)
	complete_button.call("set_title_color", Q.TEXT)

	_error_label = Q.label("", 14, BunkerDesign.RED)
	_error_label.visible = false
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_error_label)

	_footer_left = HBoxContainer.new()
	_footer_left.name = "FooterLeft"
	_footer_left.add_theme_constant_override("separation", 24)
	interface.add_child(_footer_left)
	BunkerUIComponents.key_hint(_footer_left, "ENTER", "Select", "ENTER", "A")
	## The Back hint doubles as the pointer path out: a flat, unfocusable
	## Button wrapped around the keycap (Esc/B remain the keyboard/pad path).
	back_button = Button.new()
	back_button.name = "BackToMenu"
	back_button.flat = true
	for style: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		back_button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_button.tooltip_text = ""
	back_button.modulate.a = 0.85
	back_button.mouse_entered.connect(func() -> void: back_button.modulate.a = 1.0)
	back_button.mouse_exited.connect(func() -> void: back_button.modulate.a = 0.85)
	back_button.pressed.connect(_on_back_pressed)
	_footer_left.add_child(back_button)
	var back_hint := MarginContainer.new()
	back_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_button.add_child(back_hint)
	BunkerUIComponents.key_hint(back_hint, "ESC", "Main menu", "ESC", "B")
	back_button.custom_minimum_size = back_hint.get_combined_minimum_size()
	back_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_footer_right = HBoxContainer.new()
	_footer_right.name = "FooterRight"
	_footer_right.alignment = BoxContainer.ALIGNMENT_END
	_footer_right.add_theme_constant_override("separation", 24)
	interface.add_child(_footer_right)
	BunkerUIComponents.key_hint(_footer_right, "DRAG", "Rotate", "DRAG", "LB / RB")
	BunkerUIComponents.key_hint(_footer_right, "WHEEL", "Zoom", "WHEEL", "LT / RT")

	_link_focus()


func _item(title: String, callback: Callable) -> Button:
	var item: Button = ITEM_SCRIPT.new()
	item.call("setup", title)
	item.call("set_accent_color", Q.ACCENT)
	item.pressed.connect(func() -> void:
		if not _leaving:
			callback.call())
	_column.add_child(item)
	return item


func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.set_meta(&"base_height", height)
	return gap


func _link_focus() -> void:
	var order: Array[Button] = [male_button, female_button, randomise_button, complete_button]
	for i: int in order.size():
		var button := order[i]
		button.focus_neighbor_top = button.get_path_to(order[(i - 1 + order.size()) % order.size()])
		button.focus_neighbor_bottom = button.get_path_to(order[(i + 1) % order.size()])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)


func _layout() -> void:
	var viewport := get_viewport_rect().size
	_s = clampf(minf(viewport.y / 1080.0, viewport.x / 1920.0 * 1.15), 0.66, 1.4)
	var left := clampf(viewport.x * 0.085, 48.0 * _s, 420.0 * _s)
	_column.position = Vector2(left, viewport.y * 0.2)
	_column.size = Vector2(560.0 * _s, 0.0)
	_title.add_theme_font_size_override("font_size", roundi(60.0 * _s))
	for child: Node in _column.get_children():
		if child.has_method("apply_ui_scale"):
			child.call("apply_ui_scale", _s)
		elif child.has_meta(&"base_height"):
			(child as Control).custom_minimum_size.y = float(child.get_meta(&"base_height")) * _s
	_rail.set("ui_scale", _s)
	if _rule.size.x > 0.0:
		_rule.size.x = 56.0 * _s
	# Subject stage: right of the column, clear of both footers.
	## Width is capped near the old 960x1080 render target (RX 580 GPU-crash
	## mitigation, see CharacterPreviewViewport) and centred in the space.
	var stage_left := viewport.x * 0.42
	var stage_width := minf(viewport.x - stage_left, viewport.y * 1.05)
	preview_container.position = Vector2(stage_left + (viewport.x - stage_left - stage_width) * 0.5,
		viewport.y * 0.04)
	preview_container.size = Vector2(stage_width, viewport.y * 0.88)
	floor_glow.size = Vector2(stage_width * 0.9, viewport.y * 0.34)
	floor_glow.position = preview_container.position + Vector2(stage_width * 0.05, viewport.y * 0.66)
	_footer_left.position = Vector2(left, viewport.y - 72.0 * _s)
	_footer_left.reset_size()
	_footer_right.reset_size()
	_footer_right.position = Vector2(viewport.x - 40.0 * _s - _footer_right.size.x, viewport.y - 72.0 * _s)


# ── Selection + preview ──────────────────────────────────────────────────────

func _sync_selection() -> void:
	var female := CharacterCreationData.gender == "female"
	female_button.set_pressed_no_signal(female)
	male_button.set_pressed_no_signal(not female)
	female_button.call("set_caption", "Selected" if female else "")
	male_button.call("set_caption", "" if female else "Selected")
	for choice: Button in [male_button, female_button]:
		choice.call("set_caption_color", Q.ACCENT)
		choice.call("apply_ui_scale", _s)


func _choose(gender: String) -> void:
	if CharacterCreationData.gender == gender:
		_sync_selection()
		return
	CharacterCreationData.gender = gender
	_sync_selection()
	_swap_preview()


func _on_randomise_pressed() -> void:
	_choose("male" if _rng.randi() % 2 == 0 else "female")


## Cross-fade: dip the stage, rebuild the real model, bring it back.
func _swap_preview() -> void:
	if is_instance_valid(_preview_tween):
		_preview_tween.kill()
	if UIMotion.reduced():
		_rebuild_preview()
		return
	_preview_tween = create_tween()
	_preview_tween.tween_property(preview_container, "modulate:a", 0.0, 0.12)
	_preview_tween.tween_callback(_rebuild_preview)
	_preview_tween.tween_property(preview_container, "modulate:a", 1.0, 0.28)


func _rebuild_preview() -> void:
	## remove_child() + free() so two survivors never coexist for a frame.
	if _preview_instance != null and is_instance_valid(_preview_instance):
		preview_root.remove_child(_preview_instance)
		_preview_instance.free()
	_preview_instance = null
	var scene := load(PREVIEW_SCENE_PATH) as PackedScene
	if scene == null:
		return
	_preview_instance = scene.instantiate() as Node3D
	preview_root.add_child(_preview_instance)
	_preview_instance.scale = Vector3.ONE * PREVIEW_SCALE


# ── Motion + navigation ──────────────────────────────────────────────────────

func _play_intro() -> void:
	curtain.modulate.a = 1.0
	var items: Array[Button] = [male_button, female_button, randomise_button, complete_button]
	var restored: Button = female_button if CharacterCreationData.gender == "female" else male_button
	if UIMotion.reduced():
		curtain.modulate.a = 0.0
		key_light.light_energy = KEY_ENERGY
		_rule.size.x = 56.0 * _s
		restored.grab_focus()
		return
	_rule.size.x = 0.0
	_column.modulate.a = 0.0
	preview_container.modulate.a = 0.0
	key_light.light_energy = 0.0
	for item: Button in items:
		item.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(curtain, "modulate:a", 0.0, 0.6)
	t.tween_property(_column, "modulate:a", 1.0, 0.7).set_delay(0.15)
	t.tween_property(preview_container, "modulate:a", 1.0, 0.8).set_delay(0.25)
	t.tween_property(key_light, "light_energy", KEY_ENERGY, 1.4).set_delay(0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_rule, "size:x", 56.0 * _s, 0.7).set_delay(0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(floor_glow, "modulate:a", 1.0, 1.6).from(0.0).set_delay(0.35)
	for i: int in items.size():
		t.tween_property(items[i], "modulate:a", 1.0, 0.4).set_delay(0.45 + 0.07 * float(i))
	restored.grab_focus()
	_rail.call("snap")


func _on_focus_changed(control: Control) -> void:
	if control in [male_button, female_button, randomise_button, complete_button]:
		_rail.call("set_target", control)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _leaving:
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_complete_pressed() -> void:
	var world_manager: Node = get_node_or_null(^"/root/WorldManager")
	if world_manager != null:
		world_manager.set("pending_new_game", true)   ## survivor selection after loading
	_leave(NEXT_SCENE_PATH)


func _on_back_pressed() -> void:
	_leave(MAIN_MENU_SCENE_PATH)


## Curtain to black, then change scene. A failed transition restores the
## screen and says so (never a silent dead end).
func _leave(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	_error_label.visible = false
	var t := create_tween()
	t.tween_property(curtain, "modulate:a", 1.0, UIMotion.duration(0.5)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		var error := get_tree().change_scene_to_file(path)
		if error != OK:
			_leaving = false
			curtain.modulate.a = 0.0
			_error_label.text = "Could not continue (error %d). Try again." % error
			_error_label.visible = true
			complete_button.grab_focus())
