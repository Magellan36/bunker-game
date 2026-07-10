extends RigidBody3D
## WaterBottle.gd
## Pickupable consumable. Drink in two halves (E twice).
## Each sip restores 21.5% water. After 2 sips becomes an empty bottle.

# ─── Signals ─────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()
signal charge_changed()   ## Emitted whenever _sips_left changes — lets HUD update badge live

# ─── Config ───────────────────────────────────────────────────────────────────
const WATER_PER_SIP: float  = 21.5   ## 43 / 2 — half the bottle per drink
const TOTAL_SIPS: int       = 2
const KNOCK_DISTANCE: float     = 2.2    ## Max distance before knockout check begins (world-held only)
const KNOCK_LINGER_TIME: float  = 0.35   ## Must stay out-of-range this long to actually drop

@export var follow_speed: float       = 18.0   ## World-held follow speed
@export var inv_follow_speed: float   = 40.0   ## Inventory-held: snaps instantly through turns
@export var pickup_grace: float       = 0.6

## Shelf stacking — 6 bottles per slot, stand upright in two rows of 3
var shelf_stack_limit: int   = 6
var shelf_item_type: String  = "water_bottle"

# ─── State ───────────────────────────────────────────────────────────────────
var is_held: bool           = false
var from_inventory: bool    = false   ## Set by InteractionSystem — disables knockout when true
var _hold_point: Node3D     = null
var _player_stats: Node     = null
var _grace_timer: float        = 0.0
var _out_of_range_time: float  = 0.0   ## Accumulates while item is past KNOCK_DISTANCE
var _sips_left: int     = TOTAL_SIPS   ## Counts down 2 → 1 → 0 (empty)
var _is_empty: bool     = false

# ─── Node refs (set in _ready) ────────────────────────────────────────────────
var _mesh: MeshInstance3D = null ## For tinting when empty

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

	# Inventory items never knock out — they always snap to the hold point.
	# Knockout only applies to world-held items (picked up fresh, not from a slot).
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
	return "Water Bottle"

func get_prompt_text() -> String:
	if _is_empty:
		return "[F] Pick up  Water Bottle (Empty)"
	return "[F] Pick up  Water Bottle"

func get_use_prompt() -> String:
	if _is_empty:
		return ""   ## No use prompt when empty — can't drink it
	return "[E] Drink  (%d/%d)" % [_sips_left, TOTAL_SIPS]

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

# ─── Use / Drink ──────────────────────────────────────────────────────────────
func on_use() -> void:
	if _is_empty:
		return

	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("WaterBottle: _player_stats not found.")
		return

	_player_stats.replenish_water(WATER_PER_SIP)
	_sips_left -= 1
	charge_changed.emit()   ## Tell InventoryHUD to redraw the badge immediately

	if _sips_left <= 0:
		_become_empty()

# ─── Empty state ──────────────────────────────────────────────────────────────
func _become_empty() -> void:
	_is_empty  = true
	_sips_left = 0

	# Tint mesh to a washed-out grey to signal empty
	if _mesh != null:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.55, 0.6, 0.7)
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

# ─── Culling helper ──────────────────────────────────────────────────────────
## While held, expand the culling margin so Godot never clips the item during
## fast turns. Reset to 0 on drop so world items still cull normally.
func _set_held_culling(held: bool) -> void:
	var margin: float = 10.0 if held else 0.0
	for child in get_children():
		if child is GeometryInstance3D:
			child.extra_cull_margin = margin
