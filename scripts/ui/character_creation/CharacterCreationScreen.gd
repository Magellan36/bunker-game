extends Control
## Bare-bones character creation — sidebar category layout (Body/Hair/
## Features/Accessories), matching the reference UI's shape. Only Body
## (gender) and Hair (style + color + an independent beard toggle) are
## functional right now — Features/Accessories are laid out and visible
## per request but disabled, since there's no underlying system for them
## yet.
## Runs as the project's boot scene (see project.godot's run/main_scene)
## before MainWorld ever loads. Every choice writes into the
## CharacterCreationData autoload; PlayerModelController.gd reads it at
## _ready() for any instance with use_character_creation_data = true.
## Nothing here touches real gameplay systems — this whole screen and
## everything on it is discarded the moment MainWorld loads via
## change_scene_to_file() below.

## key must match a HAIRSTYLES key in PlayerModelController.gd exactly.
## genders controls which buttons appear for which gender selection —
## Hair_Beard only offered for "male" and Hair_BuzzedFemale only for
## "female" as a sensible bare-bones default; the rest offered for
## either. Purely a UI-list filter, doesn't touch PlayerModelController.
const HAIRSTYLE_OPTIONS: Array[Dictionary] = [
	{"key": "buzzed", "label": "Buzzed", "genders": ["male"]},
	{"key": "buzzed_female", "label": "Buzzed (Fem)", "genders": ["female"]},
	{"key": "simple_parted", "label": "Simple Parted", "genders": ["male", "female"]},
	{"key": "long", "label": "Long", "genders": ["male", "female"]},
	{"key": "buns", "label": "Buns", "genders": ["male", "female"]},
]
## Beard moved out of HAIRSTYLE_OPTIONS — it's independently toggleable
## (see beard_toggle below) and combinable with any hairstyle above, for
## either gender, rather than a mutually-exclusive pick. Still looked up
## from PlayerModelController.HAIRSTYLES["beard"] wherever needed
## (thumbnail rendering doesn't apply here since it's a toggle, not a
## selectable grid option).

## Curated realistic palette rather than the reference's full rainbow
## grid — a grounded survival game, not a stylized vampire game. Purely
## a content list, swap/extend freely; a fuller "any color" picker
## (JT's Color Picker Kit, still vendored in addons/jts_colorpickerkit/,
## just unreferenced by this screen now) is a reasonable thing to bring
## back later behind something like an "Advanced" toggle.
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

const PREVIEW_SCENE_PATH: String = "res://scenes/player/PlayerModel.tscn"
const NEXT_SCENE_PATH: String = "res://scenes/world/MainWorld.tscn"
const THUMBNAIL_PIXEL_SIZE: int = 72

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
@export var beard_toggle: CheckButton = null

@export var randomise_button: Button = null
@export var complete_button: Button = null

@export var preview_root: Node3D = null

var _category_group := ButtonGroup.new()
var _gender_group := ButtonGroup.new()
var _hairstyle_group := ButtonGroup.new()
var _selected_swatch: Button = null
var _preview_instance: Node3D = null
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

	for btn in [category_body_button, category_hair_button,
			category_features_button, category_accessories_button]:
		btn.toggle_mode = true
		btn.button_group = _category_group
	## Features/Accessories have no system behind them yet — laid out
	## per request, not wired. Remove `disabled = true` here once each
	## one gets its own real panel in a later pass. Face dropped
	## entirely (not applicable to a top-down bunker sim).
	category_features_button.disabled = true
	category_accessories_button.disabled = true
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

	beard_toggle.button_pressed = CharacterCreationData.beard_enabled
	beard_toggle.toggled.connect(_on_beard_toggled)

	randomise_button.pressed.connect(_on_randomise_pressed)
	complete_button.pressed.connect(_on_complete_pressed)

	_build_color_swatches()
	_rebuild_hairstyle_buttons()
	category_body_button.button_pressed = true
	_show_category("body")
	_rebuild_preview()

func _show_category(category: String) -> void:
	body_panel.visible = category == "body"
	hair_panel.visible = category == "hair"

func _on_gender_picked(gender: String) -> void:
	CharacterCreationData.gender = gender
	## If the current hairstyle is no longer offered for this gender
	## (e.g. Buzzed after switching female — it's male-only now), fall
	## back to the first valid option rather than a stale selection with
	## no highlighted button.
	var fallback_key := ""
	var still_valid := false
	for option in HAIRSTYLE_OPTIONS:
		if not (option["genders"] as Array).has(gender):
			continue
		if fallback_key == "":
			fallback_key = option["key"]
		if option["key"] == CharacterCreationData.hairstyle_key:
			still_valid = true
	if not still_valid and fallback_key != "":
		CharacterCreationData.hairstyle_key = fallback_key
	_rebuild_hairstyle_buttons()
	_rebuild_preview()

func _rebuild_hairstyle_buttons() -> void:
	for child in hairstyle_button_container.get_children():
		child.queue_free()
	for option in HAIRSTYLE_OPTIONS:
		var genders: Array = option["genders"]
		if not genders.has(CharacterCreationData.gender):
			continue
		var btn: Button = _build_hairstyle_button(option)
		## Must be in the tree BEFORE the thumbnail is populated —
		## ItemPreviewKit.build_viewport()/set_item() read global
		## transforms and look_at() targets that only exist once the
		## viewport is actually inside the SceneTree (building detached
		## spams "not inside tree" errors and leaves empty viewports).
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

## Thumbnail rendering reuses ItemPreviewKit.gd (scripts/ui/common/) —
## the project's one shared "live 3D preview in a small viewport" tool,
## already used by InventoryHUD/StorageUI. Not reinventing that camera/
## lighting/AABB-normalization math here; just feeding it a standalone
## Node3D containing the hair mesh + its tinted material (built the same
## way PlayerModelController._build_hair_material() builds the real
## one), the same generic input shape it already accepts for any item.
func _populate_hairstyle_thumbnail(btn: Button, option: Dictionary) -> void:
	var vp_container := SubViewportContainer.new()
	vp_container.stretch = true
	## MOUSE_FILTER_IGNORE — otherwise this container eats the click
	## before it ever reaches `btn` underneath it.
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(vp_container)
	## build_viewport() adds the SubViewport as a child of vp_container
	## (already in the tree via btn, so its camera look_at() and the
	## global-transform math in set_item() all work).
	var vp: SubViewport = ItemPreviewKit.build_viewport(vp_container, THUMBNAIL_PIXEL_SIZE)
	var preview_item: Node3D = _build_hair_preview_node(option["key"])
	if preview_item != null:
		## Must be inside the tree before set_item() duplicates it —
		## that walk reads item.global_transform, which errors on a
		## detached node. Attaching here is safe: set_item()'s clear()
		## queue-frees it defensively, no manual free needed.
		vp.add_child(preview_item)
		ItemPreviewKit.set_item(vp, preview_item)

## Standalone (not attached to any skeleton) copy of one hairstyle's
## mesh, tinted with the currently-selected hair color — thumbnail only.
## Deliberately simpler than PlayerModelController._setup_hair(): no
## bone attachment, no skin data, just the mesh + material, since a
## thumbnail only needs to look right sitting at the origin.
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
		## NOT flat — Godot's flat buttons skip drawing a background in
		## their idle/normal state by design, which was hiding every
		## swatch's color until hovered even though the stylebox
		## override below was correctly set the whole time. Redundant
		## with flat anyway now that normal/hover/pressed are all
		## explicitly overridden with the same color.
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
	## Live-update in place — repaints the real preview's hair material
	## and rebuilds the hairstyle thumbnails so they reflect the new
	## tint too (cheap — six small static meshes, not a full body
	## rebuild).
	if _preview_instance != null:
		for mesh_name in ["Hair", "Beard"]:
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
	if _preview_instance != null:
		_preview_instance.queue_free()
	var scene: PackedScene = load(PREVIEW_SCENE_PATH)
	_preview_instance = scene.instantiate()
	## Set BEFORE add_child() — PlayerModelController._ready() reads
	## this the moment the node enters the tree.
	_preview_instance.set("use_character_creation_data", true)
	preview_root.add_child(_preview_instance)
	## Matches Player.tscn's PlayerModel scale (see that scene's
	## transform override) so the preview looks like the real in-game
	## character, not undersized.
	_preview_instance.scale = Vector3(1.25, 1.25, 1.25)

func _on_randomise_pressed() -> void:
	var gender: String = "male" if _rng.randi() % 2 == 0 else "female"
	CharacterCreationData.gender = gender
	if gender == "female":
		female_button.button_pressed = true
	else:
		male_button.button_pressed = true

	var valid_options: Array = HAIRSTYLE_OPTIONS.filter(
		func(o): return (o["genders"] as Array).has(gender)
	)
	var picked_option: Dictionary = valid_options[_rng.randi() % valid_options.size()]
	CharacterCreationData.hairstyle_key = picked_option["key"]
	CharacterCreationData.hair_tint_color = HAIR_COLOR_SWATCHES[_rng.randi() % HAIR_COLOR_SWATCHES.size()]
	CharacterCreationData.beard_enabled = _rng.randi() % 2 == 0
	beard_toggle.button_pressed = CharacterCreationData.beard_enabled

	_build_color_swatches()
	_rebuild_hairstyle_buttons()
	_rebuild_preview()

func _on_complete_pressed() -> void:
	get_tree().change_scene_to_file(NEXT_SCENE_PATH)