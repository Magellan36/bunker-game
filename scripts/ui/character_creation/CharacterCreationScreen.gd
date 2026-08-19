extends Control
## Bare-bones character creation — Gender, then Hairstyle + hair color.
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
	{"key": "buzzed", "label": "Buzzed", "genders": ["male", "female"]},
	{"key": "buzzed_female", "label": "Buzzed (Fem)", "genders": ["female"]},
	{"key": "simple_parted", "label": "Simple Parted", "genders": ["male", "female"]},
	{"key": "long", "label": "Long", "genders": ["male", "female"]},
	{"key": "buns", "label": "Buns", "genders": ["male", "female"]},
	{"key": "beard", "label": "Beard", "genders": ["male"]},
]

const PREVIEW_SCENE_PATH: String = "res://scenes/player/PlayerModel.tscn"
const NEXT_SCENE_PATH: String = "res://scenes/world/MainWorld.tscn"

@export var gender_panel: Control = null
@export var hair_panel: Control = null
@export var male_button: Button = null
@export var female_button: Button = null
@export var hairstyle_button_container: Container = null
@export var color_picker_instance: UI_ColorPickerInstance = null
@export var start_button: Button = null
@export var preview_root: Node3D = null

var _preview_instance: Node3D = null

func _ready() -> void:
	male_button.pressed.connect(_on_gender_picked.bind("male"))
	female_button.pressed.connect(_on_gender_picked.bind("female"))
	color_picker_instance.on_color_picked.connect(_on_color_picked)
	color_picker_instance.set_picked_color(CharacterCreationData.hair_tint_color)
	start_button.pressed.connect(_on_start_pressed)
	hair_panel.visible = false
	_rebuild_preview()

func _on_gender_picked(gender: String) -> void:
	CharacterCreationData.gender = gender
	gender_panel.visible = false
	hair_panel.visible = true
	_rebuild_hairstyle_buttons()
	_rebuild_preview()

func _rebuild_hairstyle_buttons() -> void:
	for child in hairstyle_button_container.get_children():
		child.queue_free()
	for option in HAIRSTYLE_OPTIONS:
		var genders: Array = option["genders"]
		if not genders.has(CharacterCreationData.gender):
			continue
		var btn := Button.new()
		btn.text = option["label"]
		btn.pressed.connect(_on_hairstyle_picked.bind(option["key"]))
		hairstyle_button_container.add_child(btn)

func _on_hairstyle_picked(key: String) -> void:
	CharacterCreationData.hairstyle_key = key
	_rebuild_preview()

func _on_color_picked(c: Color) -> void:
	CharacterCreationData.hair_tint_color = c
	## Live-update in place — no mesh swap needed for a color-only
	## change, just repaint the hair mesh's existing material.
	if _preview_instance == null:
		return
	for mesh_instance in _find_named_meshes(_preview_instance, "Hair"):
		for surf_i in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_surface_override_material(surf_i)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).albedo_color = c

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

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(NEXT_SCENE_PATH)