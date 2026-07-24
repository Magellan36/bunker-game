extends RigidBody3D
class_name SeedItem
## SeedItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §5.4/§8. ONE script for both tomato/onion seeds via
## export var (mirrors PurifierFilterItem.gd's one-script convention). Sold
## via the Farming toolbar tool's shop — $25 per purchase spawns 4 separate
## instances (not a stack-count object, see FarmingShopHelper.gd).
##
## on_use() while held: finds the nearest FarmingTray in range with an open
## plantable cell (soiled, unplanted), plants into it, consumes this seed.

signal picked_up()
signal dropped()
signal knocked_out()

const KNOCK_DISTANCE: float    = 2.2
const KNOCK_LINGER_TIME: float = 0.35

@export var follow_speed: float     = 18.0
@export var inv_follow_speed: float = 40.0
@export var pickup_grace: float     = 0.6

@export var seed_type: String = "tomato"   ## "tomato" or "onion"

const TRAY_RANGE: float = 2.5

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "seed"   ## Shared slot key for both types, same
## reasoning PurifierFilterItem.gd uses (shared shelf_item_type, per-instance
## state — here seed_type — preserved by Shelving.gd's real-node-reference slots).

var is_held: bool           = false
var from_inventory: bool    = false
var _hold_point: Node3D     = null
var _grace_timer: float       = 0.0
var _out_of_range_time: float = 0.0

var _mesh: MeshInstance3D = null

func _ready() -> void:
	add_to_group("pickup")
	add_to_group("inventory_item")
	contact_monitor = true
	max_contacts_reported = 4
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	if not from_inventory:
		if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_do_knocked_out()
				return
		else:
			_out_of_range_time = 0.0

	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (target - global_position) * speed
	angular_velocity = Vector3.ZERO

func get_display_name() -> String:
	return "%s Seed" % PlantDatabase.get_display_name(seed_type)

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % get_display_name()

func _find_nearest_plantable_tray() -> FarmingTray:
	var best: FarmingTray = null
	var best_dist: float = TRAY_RANGE
	for node: Node in get_tree().get_nodes_in_group("farming_tray"):
		if node is FarmingTray and (node as FarmingTray).has_open_plantable_cell():
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = node as FarmingTray
	return best

func get_use_prompt() -> String:
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray == null:
		return ""
	return "[E] Plant %s" % PlantDatabase.get_display_name(seed_type)

func on_use() -> void:
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray ready to plant nearby")
		return

	if not tray.plant_first_open_cell(seed_type):
		return

	queue_free()

func pickup(hold_point: Node3D) -> void:
	is_held       = true
	_hold_point   = hold_point
	_grace_timer       = pickup_grace
	_out_of_range_time = 0.0
	freeze        = false
	freeze_mode   = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	collision_layer = 2
	collision_mask  = 1
	_set_held_culling(true)
	picked_up.emit()

func drop(_world_parent: Node3D, drop_position: Vector3) -> void:
	is_held         = false
	_hold_point     = null
	global_position = drop_position
	gravity_scale   = 1.0
	freeze = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3.ZERO
	add_to_group("pickup")
	_set_held_culling(false)
	dropped.emit()

func place(_world_parent: Node3D, place_position: Vector3, _rot: Vector3 = Vector3.ZERO) -> void:
	drop(_world_parent, place_position)

func _do_knocked_out() -> void:
	is_held         = false
	_hold_point     = null
	gravity_scale   = 1.0
	freeze = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	_set_held_culling(false)
	knocked_out.emit()

func _set_held_culling(held: bool) -> void:
	var margin: float = 10.0 if held else 0.0
	for child in get_children():
		if child is GeometryInstance3D:
			child.extra_cull_margin = margin

## Small flat packet placeholder, tinted per seed_type so the two types are
## visually distinguishable on the ground.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.10, 0.02, 0.14)
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.01, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.65, 0.25, 1.0) if seed_type == "tomato" else Color(0.75, 0.78, 0.55, 1.0)
	mat.roughness    = 0.85
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself (NOT
	## MeshInstance3D.create_trimesh_collision(), which nests a separate
	## StaticBody3D under the mesh and leaves this RigidBody3D with no
	## collider at all — it would fall through the floor forever and be
	## invisible to the interaction system's body-detection). Mirrors
	## PurifierFilterItem.tscn's CollisionShape3D-as-direct-child pattern.
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = _mesh.position
	add_child(shape)

## Spawn helper (used by FarmingShopHelper — 4 separate instances per purchase,
## per plan §8.2, since nothing in this codebase's item system supports
## partial-stack consumption within one physical item).
static func spawn_at(parent: Node, base_pos: Vector3, type: String) -> SeedItem:
	var item: SeedItem = SeedItem.new()
	item.seed_type = type
	var offset: Vector3 = Vector3(randf_range(-0.30, 0.30), 0.0, randf_range(-0.30, 0.30))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item
