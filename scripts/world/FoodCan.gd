extends RigidBody3D
## FoodCan.gd
## Pickupable consumable. Two bites (E twice) — each restores 12.5% hunger.
## After 2 uses becomes an empty can (kept in world, no queue_free).

# ─── Signals ─────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()
signal charge_changed()   ## Emitted whenever _bites_left changes

# ─── Config ───────────────────────────────────────────────────────────────────
const FOOD_PER_BITE: float  = 12.5   ## 25 / 2 — half the can per eat
const TOTAL_BITES: int      = 2
const KNOCK_DISTANCE: float     = 2.2    ## World-held only
const KNOCK_LINGER_TIME: float  = 0.35

@export var follow_speed: float       = 18.0
@export var inv_follow_speed: float   = 40.0
@export var pickup_grace: float       = 0.6

## Shelf stacking — 6 cans per slot, stand upright in two rows of 3
var shelf_stack_limit: int   = 6
var shelf_item_type: String  = "food_can"

# ─── State ───────────────────────────────────────────────────────────────────
var is_held: bool           = false
var from_inventory: bool    = false
var _hold_point: Node3D     = null
var _player_stats: Node     = null
var _grace_timer: float        = 0.0
var _out_of_range_time: float  = 0.0
var _bites_left: int    = TOTAL_BITES   ## Counts down 2 → 1 → 0 (empty)
var _is_empty: bool     = false

# ─── Node refs ────────────────────────────────────────────────────────────────
var _mesh: MeshInstance3D = null   ## For tinting when empty

func _ready() -> void:
	add_to_group("pickup")
	add_to_group("inventory_item")
	contact_monitor = true
	max_contacts_reported = 4
	_mesh = get_node_or_null("MeshInstance3D")

# ─── Physics ──────────────────────────────────────────────────────────────────
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

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Food Can"

func get_prompt_text() -> String:
	if _is_empty:
		return "[F] Pick up  Can (Empty)"
	return "[F] Pick up  Food Can"

func get_use_prompt() -> String:
	if _is_empty:
		return ""   ## No use prompt when empty — nothing left to eat
	return "[E] Eat  (%d/%d)" % [_bites_left, TOTAL_BITES]

# ─── Pickup ───────────────────────────────────────────────────────────────────
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

# ─── Use / Eat ────────────────────────────────────────────────────────────────
func on_use() -> void:
	if _is_empty:
		return

	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("FoodCan: _player_stats not found.")
		return

	_player_stats.replenish_food(FOOD_PER_BITE)
	_bites_left -= 1
	charge_changed.emit()

	if _bites_left <= 0:
		_become_empty()

# ─── Empty state ──────────────────────────────────────────────────────────────
func _become_empty() -> void:
	_is_empty   = true
	_bites_left = 0

	# Tint mesh to washed-out grey — signals empty to the player
	if _mesh != null:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.55, 0.55, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mesh.material_override = mat

# ─── Drop ─────────────────────────────────────────────────────────────────────
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

# ─── Place ────────────────────────────────────────────────────────────────────
func place(_world_parent: Node3D, place_position: Vector3, _rot: Vector3 = Vector3.ZERO) -> void:
	drop(_world_parent, place_position)

# ─── Knocked out ─────────────────────────────────────────────────────────────
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

# ─── Culling helper ───────────────────────────────────────────────────────────
## Expand cull margin while held so fast 180° turns don't clip the item.
## Reset to 0 on drop so world items cull normally.
func _set_held_culling(held: bool) -> void:
	var margin: float = 10.0 if held else 0.0
	for child in get_children():
		if child is GeometryInstance3D:
			child.extra_cull_margin = margin
