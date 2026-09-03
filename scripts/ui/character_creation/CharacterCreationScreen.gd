extends Control
## Character creation — approved warm-charcoal / blue redesign, first pass.
## Existing appearance/preview behavior stays here; native scene containers
## and CharacterCreationLayout own presentation. Legacy controls are hidden.
##
## Aug 2026 — V1 simplification. Only Body (gender) is functional now;
## Hair joined Features/Accessories as disabled/"Coming soon" — the
## whole per-piece customization system (hairstyle/color/beard picking,
## the outfit system it drove) is packed away for a later version, not
## deleted. See docs/systems/player-model/README.md "V1 simplification
## — Adventurer models" for why and how to bring it back. Everything
## below this comment that built/wired the hair picker
## (HAIRSTYLE_OPTIONS, HAIR_COLOR_SWATCHES, _rebuild_hairstyle_buttons,
## _build_hairstyle_button, _populate_hairstyle_thumbnail,
## _build_hair_preview_node, _on_hairstyle_picked, _on_beard_toggled,
## _build_color_swatches, _on_swatch_picked, _select_swatch,
## _find_named_meshes, the beard button setup in _ready()) is UNUSED in
## V1 — left in place rather than deleted, per the same packed-away
## reasoning, since it's cheap to keep and expensive to accurately
## reconstruct later. None of it runs; category_hair_button is disabled
## so hair_panel is never shown and none of these are ever called from
## a live UI interaction.
##
## Runs as the project's boot scene (see project.godot's run/main_scene)
## before MainWorld ever loads. Gender choice writes into the
## CharacterCreationData autoload; AdventurerModelController.gd reads it
## at _ready() for the actual in-game body (see that file). Nothing here
## touches real gameplay systems — this whole screen and everything on
## it is discarded the moment Complete routes through the LoadingScreen to
## MainWorld (change_scene_to_file() below).

## key must match a HAIRSTYLES key in PlayerModelController.gd exactly.
## Aug 2026 — UNUSED in V1, see the packed-away note above.
const HAIRSTYLE_OPTIONS: Array[Dictionary] = [
	{"key": "buzzed", "label": "Buzzed", "genders": ["male"]},
	{"key": "buzzed_female", "label": "Buzzed (Fem)", "genders": ["female"]},
	{"key": "simple_parted", "label": "Simple Parted", "genders": ["male", "female"]},
	{"key": "long", "label": "Long", "genders": ["male", "female"]},
	{"key": "buns", "label": "Buns", "genders": ["male", "female"]},
]

## Aug 2026 — UNUSED in V1, see the packed-away note above.
const HAIR_COLOR_SWATCHES: Array[Color] = [
	Color(0.02, 0.02, 0.02),
	Color(0.12, 0.08, 0.05),
	Color(0.25, 0.15, 0.08),
	Color(0.45, 0.30, 0.15),
	Color(0.55, 0.42, 0.20),
	Color(0.75, 0.60, 0.30),
	Color(0.35, 0.12, 0.05),
	Color(0.55, 0.25, 0.08),
	Color(0.55, 0.55, 0.55),
	Color(0.85, 0.85, 0.82),
]

## Aug 2026 — points at the new AdventurerModel.tscn (V1's single
## complete-body model) instead of the old customizable PlayerModel.tscn.
const PREVIEW_SCENE_PATH: String = "res://scenes/player/AdventurerModel.tscn"
## Aug 2026 — Complete now goes through the LoadingScreen first (threaded
## MainWorld load + fixed display time) instead of swapping straight to the
## world, so the bunker build-up happens behind a branded screen.
const NEXT_SCENE_PATH: String = "res://scenes/ui/LoadingScreen.tscn"
const THUMBNAIL_PIXEL_SIZE: int = 72
const SELECTED_ICON: Texture2D = preload("res://assets/ui/placeholders/redesign/selected_AI_PLACEHOLDER.svg")
const UNSELECTED_ICON: Texture2D = preload("res://assets/ui/placeholders/redesign/unselected_AI_PLACEHOLDER.svg")

@export var category_body_button: Button = null
@export var category_hair_button: Button = null
@export var category_features_button: Button = null
@export var category_accessories_button: Button = null

@export var body_panel: Control = null
@export var hair_panel: Control = null

@export var male_button: Button = null
@export var female_button: Button = null
@export var hairstyle_button_container: Container = null
@export var color_swatch_container: Container = null
@export var beard_button_container: Container = null

var _beard_button: Button = null

@export var randomise_button: Button = null
@export var complete_button: Button = null

@export var preview_root: Node3D = null

var _category_group := ButtonGroup.new()
var _gender_group := ButtonGroup.new()
var _hairstyle_group := ButtonGroup.new()
var _selected_swatch: Button = null
var _preview_instance: Node3D = null
var _rng := RandomNumberGenerator.new()
var _controller_hints: bool = false
var _transitioning: bool = false

@onready var _preview_hint: Label = %PreviewHint
@onready var _navigation_hint: Label = %NavigationHint
@onready var _error_message: Label = %ErrorMessage
@onready var _choice_scroll: ScrollContainer = %ChoiceScroll

func _ready() -> void:
	_rng.randomize()

	for btn in [category_body_button, category_hair_button,
			category_features_button, category_accessories_button]:
		btn.toggle_mode = true
		btn.button_group = _category_group
	## Aug 2026 — Hair joined Features/Accessories as disabled/"Coming
	## soon" for V1 (see the packed-away note at the top of this file).
	## Face dropped entirely (not applicable to a top-down bunker sim).
	category_hair_button.disabled = true
	category_features_button.disabled = true
	category_accessories_button.disabled = true
	category_hair_button.tooltip_text = "Coming soon"
	category_features_button.tooltip_text = "Coming soon"
	category_accessories_button.tooltip_text = "Coming soon"

	category_body_button.pressed.connect(_show_category.bind("body"))
	category_hair_button.pressed.connect(_show_category.bind("hair"))

	male_button.toggle_mode = true
	female_button.toggle_mode = true
	male_button.button_group = _gender_group
	female_button.button_group = _gender_group
	male_button.pressed.connect(_on_gender_picked.bind("male"))
	female_button.pressed.connect(_on_gender_picked.bind("female"))
	if CharacterCreationData.gender == "female":
		female_button.button_pressed = true
	else:
		male_button.button_pressed = true

	## Aug 2026 — beard button setup removed for V1 (hair/beard system
	## is packed away, see the top-of-file note); beard_button_container
	## stays empty and unused rather than being populated with a
	## now-nonfunctional toggle.

	randomise_button.pressed.connect(_on_randomise_pressed)
	complete_button.pressed.connect(_on_complete_pressed)

	category_body_button.button_pressed = true
	_show_category("body")
	_rebuild_preview()

	## Controller UI navigation (Aug 2026) — d-pad + left stick drive button
	## focus; A activates the focused button (Godot default). See
	## scripts/ui/common/ControllerUINavigation.gd. Loaded by path (not the
	## class_name global) so a stale global-class cache never breaks it.
	var nav: Node = (load("res://scripts/ui/common/ControllerUINavigation.gd") as GDScript).new()
	nav.ui_root = self
	nav.close_on_cancel = false   ## B must not exit character creation
	nav.stick_navigation = true   ## left stick navigates here (no movement to reserve)
	add_child(nav)
	_sync_body_selection()
	_configure_focus_order()
	_update_input_hints()
	# Restore focus without scrolling past the heading on first open. Subsequent
	# navigation still follows focus normally, including at smaller resolutions.
	_choice_scroll.follow_focus = false
	if CharacterCreationData.gender == "female":
		female_button.grab_focus()
	else:
		male_button.grab_focus()
	_choice_scroll.set_deferred("scroll_vertical", 0)
	_choice_scroll.set_deferred("follow_focus", true)

func _process(_delta: float) -> void:
	if _controller_hints != InputMode.is_controller():
		_update_input_hints()

func _update_input_hints() -> void:
	_controller_hints = InputMode.is_controller()
	if _controller_hints:
		_preview_hint.text = "Right stick: rotate / pan"
		_navigation_hint.text = "[A] Select   •   D-pad / left stick: navigate"
	else:
		_preview_hint.text = "Drag: rotate   •   Wheel: zoom\nMiddle-drag: pan"
		_navigation_hint.text = "Enter / Space: select   •   Tab / arrows: navigate"

func _configure_focus_order() -> void:
	var buttons: Array[Button] = [male_button, female_button, randomise_button, complete_button]
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		button.focus_mode = Control.FOCUS_ALL
		button.focus_previous = button.get_path_to(buttons[posmod(index - 1, buttons.size())])
		button.focus_next = button.get_path_to(buttons[(index + 1) % buttons.size()])
		# Vertical arrows stop at the ends, matching the existing controller nav.
		button.focus_neighbor_top = button.get_path_to(buttons[maxi(index - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(buttons[mini(index + 1, buttons.size() - 1)])
		button.focus_neighbor_left = NodePath(".")
		button.focus_neighbor_right = NodePath(".")

func _sync_body_selection() -> void:
	for button: Button in [male_button, female_button]:
		var indicator: TextureRect = button.get_node("Indicator") as TextureRect
		indicator.texture = SELECTED_ICON if button.button_pressed else UNSELECTED_ICON

func _show_category(category: String) -> void:
	body_panel.visible = category == "body"
	hair_panel.visible = category == "hair"

func _on_gender_picked(gender: String) -> void:
	CharacterCreationData.gender = gender
	_sync_body_selection()
	_rebuild_preview()

## Aug 2026 — UNUSED in V1 (hair category disabled), kept for the
## packed-away hair system. See the top-of-file note.
func _rebuild_hairstyle_buttons() -> void:
	for child in hairstyle_button_container.get_children():
		child.queue_free()
	for option in HAIRSTYLE_OPTIONS:
		var genders: Array = option["genders"]
		if not genders.has(CharacterCreationData.gender):
			continue
		var btn: Button = _build_hairstyle_button(option)
		hairstyle_button_container.add_child(btn)
		_populate_hairstyle_thumbnail(btn, option)
		if option["key"] == CharacterCreationData.hairstyle_key:
			btn.button_pressed = true

func _build_hairstyle_button(option: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(THUMBNAIL_PIXEL_SIZE, THUMBNAIL_PIXEL_SIZE)
	btn.toggle_mode = true
	btn.button_group = _hairstyle_group
	btn.tooltip_text = option["label"]
	btn.pressed.connect(_on_hairstyle_picked.bind(option["key"]))
	return btn

func _populate_hairstyle_thumbnail(btn: Button, option: Dictionary) -> void:
	var vp_container := SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(vp_container)
	var vp: SubViewport = ItemPreviewKit.build_viewport(vp_container, THUMBNAIL_PIXEL_SIZE)
	var preview_item: Node3D = _build_hair_preview_node(option["key"])
	if preview_item != null:
		vp.add_child(preview_item)
		ItemPreviewKit.set_item(vp, preview_item)

func _build_hair_preview_node(hairstyle_key: String) -> Node3D:
	var style: Dictionary = PlayerModelController.HAIRSTYLES.get(hairstyle_key, {})
	if style.is_empty():
		return null
	var hair_scene: PackedScene = load(style["scene"])
	if hair_scene == null:
		return null
	var hair_root: Node = hair_scene.instantiate()
	var mesh_src: MeshInstance3D = hair_root.find_child(style["mesh_node"], true, false) as MeshInstance3D
	if mesh_src == null:
		hair_root.free()
		return null

	var mat := StandardMaterial3D.new()
	var albedo: Texture2D = load(style["albedo"])
	var normal: Texture2D = load(style["normal"])
	if albedo != null:
		mat.albedo_texture = albedo
		mat.albedo_color = CharacterCreationData.hair_tint_color
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var wrapper := Node3D.new()
	var mesh_copy := MeshInstance3D.new()
	mesh_copy.mesh = mesh_src.mesh
	for surf_i in mesh_copy.mesh.get_surface_count():
		mesh_copy.set_surface_override_material(surf_i, mat)
	wrapper.add_child(mesh_copy)
	hair_root.free()
	return wrapper

func _on_hairstyle_picked(key: String) -> void:
	CharacterCreationData.hairstyle_key = key
	_rebuild_preview()

func _on_beard_toggled(pressed: bool) -> void:
	CharacterCreationData.beard_enabled = pressed
	_rebuild_preview()

func _build_color_swatches() -> void:
	for child in color_swatch_container.get_children():
		child.queue_free()
	_selected_swatch = null
	for c in HAIR_COLOR_SWATCHES:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(32, 32)
		var style := StyleBoxFlat.new()
		style.bg_color = c
		style.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.pressed.connect(_on_swatch_picked.bind(btn, c))
		color_swatch_container.add_child(btn)
		if c.is_equal_approx(CharacterCreationData.hair_tint_color):
			_select_swatch(btn)

func _on_swatch_picked(btn: Button, c: Color) -> void:
	CharacterCreationData.hair_tint_color = c
	_select_swatch(btn)
	if _preview_instance != null:
		for mesh_name in ["Hair", "Beard", "Eyebrows"]:
			for mesh_instance in _find_named_meshes(_preview_instance, mesh_name):
				for surf_i in mesh_instance.mesh.get_surface_count():
					var mat: Material = mesh_instance.get_surface_override_material(surf_i)
					if mat is StandardMaterial3D:
						(mat as StandardMaterial3D).albedo_color = c
	_rebuild_hairstyle_buttons()

func _select_swatch(btn: Button) -> void:
	if _selected_swatch != null and is_instance_valid(_selected_swatch):
		var prev_style: StyleBox = _selected_swatch.get_theme_stylebox("normal")
		if prev_style is StyleBoxFlat:
			(prev_style as StyleBoxFlat).set_border_width_all(0)
	_selected_swatch = btn
	var style: StyleBox = btn.get_theme_stylebox("normal")
	if style is StyleBoxFlat:
		var flat := style as StyleBoxFlat
		flat.border_color = Color.WHITE
		flat.set_border_width_all(3)

static func _find_named_meshes(root: Node, mesh_name: String) -> Array[MeshInstance3D]:
	var results: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D and child.name == mesh_name:
			results.append(child)
		results.append_array(_find_named_meshes(child, mesh_name))
	return results

func _rebuild_preview() -> void:
	## remove_child() + free() (not queue_free()) removes and deallocates
	## the old instance immediately and synchronously, so there is no
	## frame in which two instances can coexist under preview_root — see
	## the Aug 2026 fix history in docs/systems/player-model/README.md
	## if this pattern is ever reconsidered.
	if _preview_instance != null:
		preview_root.remove_child(_preview_instance)
		_preview_instance.free()
		_preview_instance = null
	var scene: PackedScene = load(PREVIEW_SCENE_PATH)
	_preview_instance = scene.instantiate()
	preview_root.add_child(_preview_instance)
	## Matches Player.tscn's PlayerModel scale so the preview looks like
	## the real in-game character, not undersized.
	_preview_instance.scale = Vector3(1.25, 1.25, 1.25)

func _on_randomise_pressed() -> void:
	## Aug 2026 — only randomizes gender now; hairstyle/color/beard
	## randomization is packed away along with the rest of the hair
	## system (see the top-of-file note).
	var gender: String = "male" if _rng.randi() % 2 == 0 else "female"
	CharacterCreationData.gender = gender
	if gender == "female":
		female_button.button_pressed = true
	else:
		male_button.button_pressed = true
	_sync_body_selection()
	_rebuild_preview()

func _on_complete_pressed() -> void:
	if _transitioning:
		return
	_transitioning = true
	_error_message.hide()
	for button: Button in [male_button, female_button, randomise_button, complete_button]:
		button.disabled = true
	var error: Error = _change_to_loading()
	if error != OK:
		_transitioning = false
		for button: Button in [male_button, female_button, randomise_button, complete_button]:
			button.disabled = false
		_error_message.text = "Could not open the loading screen. Please try again."
		_error_message.show()
		complete_button.grab_focus()
		push_error("Character creation: loading-screen transition failed (%s)." % error_string(error))

func _change_to_loading() -> Error:
	return get_tree().change_scene_to_file(NEXT_SCENE_PATH)
