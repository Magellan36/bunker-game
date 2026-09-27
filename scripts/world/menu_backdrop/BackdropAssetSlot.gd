@tool
extends Node3D
## BackdropAssetSlot.gd (Sep 2026)
## One authored placement in the main-menu surface scene. Drop a human-made or
## properly licensed scene into `asset_scene` and it is instanced at this
## node's origin (ground contact at y = 0, facing -Z like the camera).
##
## Until then, the editor and DEBUG builds show an untextured greybox massing
## block so the composition can be judged before the art exists. Release
## (non-debug) exports never build greybox geometry: an unfilled slot ships
## empty and logs a warning. `tools/tests/check_menu_backdrop_slots.py
## --release` is the matching pre-ship gate.
##
## The spawned node is never owned by the edited scene, so nothing generated
## here is ever written back into MenuBackdrop.tscn.

const GREYBOX_COLOR: Color = Color(0.29, 0.30, 0.29)
static var _greybox_material: StandardMaterial3D = null

## The real asset for this placement. Leave empty only during development.
@export var asset_scene: PackedScene:
	set(value):
		asset_scene = value
		_rebuild()
## Development massing volume in metres (X width, Y height, Z depth).
@export var greybox_size: Vector3 = Vector3(10.0, 18.0, 8.0):
	set(value):
		greybox_size = value
		_rebuild()
## Breaks the greybox's roofline into stepped fragments to read as a ruin.
@export var greybox_broken: bool = true:
	set(value):
		greybox_broken = value
		_rebuild()
## Art brief for whoever builds the replacement (shown in the Inspector).
@export_multiline var brief: String = ""

var _spawned: Node3D = null


func _ready() -> void:
	_rebuild()


func is_filled() -> bool:
	return asset_scene != null


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _spawned != null and is_instance_valid(_spawned):
		_spawned.free()
	_spawned = null
	if asset_scene != null:
		_spawned = asset_scene.instantiate() as Node3D
		if _spawned == null:
			push_warning("[MenuBackdrop] Slot %s: asset_scene root is not a Node3D." % name)
			return
	elif Engine.is_editor_hint() or OS.is_debug_build():
		_spawned = _build_greybox()
	else:
		push_warning("[MenuBackdrop] Slot %s has no asset; shipping it empty." % name)
		return
	_spawned.name = "SlotContent"
	add_child(_spawned, false, Node.INTERNAL_MODE_BACK)


func _build_greybox() -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(name))
	var size := greybox_size
	if not greybox_broken:
		root.add_child(_block(Vector3.ZERO, size))
		return root
	# A solid lower mass plus a few stepped fragments gives a torn roofline
	# without implying any real architectural detail.
	var base_height := size.y * rng.randf_range(0.5, 0.72)
	root.add_child(_block(Vector3.ZERO, Vector3(size.x, base_height, size.z)))
	var fragments := rng.randi_range(2, 4)
	var cursor := -size.x * 0.5
	for i: int in range(fragments):
		var width := size.x / float(fragments) * rng.randf_range(0.55, 1.0)
		var height := (size.y - base_height) * rng.randf_range(0.15, 1.0)
		var depth := size.z * rng.randf_range(0.45, 1.0)
		var x := cursor + width * 0.5
		cursor += size.x / float(fragments)
		root.add_child(_block(Vector3(x, base_height, rng.randf_range(-0.2, 0.2) * size.z),
			Vector3(width, height, depth)))
	return root


func _block(bottom_center: Vector3, block_size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = block_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material()
	instance.position = bottom_center + Vector3(0.0, block_size.y * 0.5, 0.0)
	return instance


static func _material() -> StandardMaterial3D:
	if _greybox_material == null:
		_greybox_material = StandardMaterial3D.new()
		_greybox_material.albedo_color = GREYBOX_COLOR
		_greybox_material.roughness = 1.0
	return _greybox_material
