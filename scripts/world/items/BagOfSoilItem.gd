extends RigidBody3D
class_name BagOfSoilItem
## BagOfSoilItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §5.4/§8. Pickupable consumable — sold via the Farming
## toolbar tool's shop ($100, spawns 1 instance above the player's head).
##
## Physics/pickup/drop/knockout scaffolding copied verbatim from FoodCan.gd
## (the closest existing shape — simple carriable consumable, no multi-charge
## logic needed here at all).
##
## on_use() while held: finds the nearest FarmingTray in range with an open
## soil cell, fills it, consumes this bag, and drops an EmptyBagItem near the
## tray (mirrors PurifierFilterItem.spawn_at()'s "drop near position, not
## auto-added to inventory" pattern).

signal picked_up()
signal dropped()
signal knocked_out()

const KNOCK_DISTANCE: float    = 2.2
const KNOCK_LINGER_TIME: float = 0.35

@export var follow_speed: float     = 18.0
@export var inv_follow_speed: float = 40.0
@export var pickup_grace: float     = 0.6

## Proximity range for finding the nearest tray — same value as
## PurifierFilterItem.REPLACE_RANGE / FarmingTray.REPLACE_RANGE.
const TRAY_RANGE: float = 2.5

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "bag_of_soil"

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
	return "Bag of Soil"

func get_prompt_text() -> String:
	return "[F] Pick up  Bag of Soil"

func _find_nearest_tray_needing_soil() -> FarmingTray:
	var best: FarmingTray = null
	var best_dist: float = TRAY_RANGE
	for node: Node in get_tree().get_nodes_in_group("farming_tray"):
		if node is FarmingTray and (node as FarmingTray).has_open_soil_cell():
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = node as FarmingTray
	return best

func get_use_prompt() -> String:
	var tray: FarmingTray = _find_nearest_tray_needing_soil()
	if tray == null:
		return ""
	return "[E] Fill Tray with Soil"

func on_use() -> void:
	var tray: FarmingTray = _find_nearest_tray_needing_soil()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray needing soil nearby")
		return

	if not tray.fill_first_open_soil_cell():
		return

	EmptyBagItem.spawn_at(get_parent(), tray.global_position)
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

## Placeholder box model — a full sack, visibly bulkier than EmptyBagItem's
## flatter silhouette so the two read as distinct on the ground at a glance.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.26, 0.20, 0.16)
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.10, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.42, 0.28, 1.0)
	mat.roughness    = 0.95
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself — see SeedItem.gd's
	## _build_placeholder_mesh() comment for why create_trimesh_collision()
	## was wrong here (no collider on this body at all -> infinite fall,
	## undetectable by the interaction system).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = _mesh.position
	add_child(shape)

## Spawn helper (used by FarmingShopHelper for shop purchases). Mirrors
## PurifierFilterItem.spawn_at()'s shape — floor-dropped, not auto-added to
## inventory, small random horizontal offset.
static func spawn_at(parent: Node, base_pos: Vector3) -> BagOfSoilItem:
	var item: BagOfSoilItem = BagOfSoilItem.new()
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item
