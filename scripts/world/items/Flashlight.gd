extends RigidBody3D
## Flashlight.gd
## Pickupable flashlight. Toggle on/off with [E] while held.
## Auto-aims the beam in the direction the player is facing.
## Battery drains over time; recharging not yet implemented.

# ─── Signals ──────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()
signal charge_changed()   ## Battery % changed — for HUD badge

# ─── Config ───────────────────────────────────────────────────────────────────
const KNOCK_DISTANCE:   float = 2.2
const KNOCK_LINGER_TIME:float = 0.35
const BATTERY_DRAIN:    float = 0.8    ## % per real second while on
const CONE_ANGLE:       float = 22.0   ## SpotLight3D inner angle
const CONE_OUTER:       float = 30.0   ## SpotLight3D outer angle
const LIGHT_RANGE:      float = 14.0   ## metres
const LIGHT_ENERGY:     float = 2.8

## Slight downward tilt so beam hits the floor ahead, not the horizon.
const BEAM_PITCH_DEG:   float = -12.0

@export var follow_speed:     float = 18.0
@export var inv_follow_speed: float = 40.0
@export var pickup_grace:     float = 0.6

## Shelf config
var shelf_stack_limit: int  = 1
var shelf_item_type:   String = "flashlight"

# ─── State ────────────────────────────────────────────────────────────────────
var is_held:           bool   = false
var from_inventory:    bool   = false
var _hold_point:       Node3D = null
var _player:           Node3D = null   ## CharacterBody3D — set on pickup
var _grace_timer:      float  = 0.0
var _out_of_range_time:float  = 0.0

var _on:         bool  = false
var _battery:    float = 100.0  ## 0–100
var _is_dead:    bool  = false

# ─── Node refs ────────────────────────────────────────────────────────────────
var _spot:       SpotLight3D        = null
var _body_mesh:  MeshInstance3D     = null
var _lens_mat:   StandardMaterial3D = null

# ─── Colours ──────────────────────────────────────────────────────────────────
const COL_ON:   Color = Color(1.0,  0.98, 0.88, 1.0)   ## warm white
const COL_LOW:  Color = Color(0.95, 0.75, 0.20, 1.0)   ## orange-yellow
const COL_DEAD: Color = Color(0.30, 0.30, 0.32, 0.55)  ## gray

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("pickup")
	add_to_group("inventory_item")
	contact_monitor        = true
	max_contacts_reported  = 4

	_build_mesh()
	_build_light()
	_build_collision()
	_refresh_state()

# ─── Visual Construction ──────────────────────────────────────────────────────
func _build_mesh() -> void:
	## Flashlight body: cylinder (handle) + wider cylinder (head) + lens cap.
	## Everything lies along local +Z so the light points forward naturally.

	## Handle — thin long cylinder along +Z
	var handle_mi: MeshInstance3D = MeshInstance3D.new()
	var handle_mesh: CylinderMesh = CylinderMesh.new()
	handle_mesh.top_radius      = 0.040
	handle_mesh.bottom_radius   = 0.038
	handle_mesh.height          = 0.24
	handle_mesh.radial_segments = 10
	handle_mi.mesh = handle_mesh
	## CylinderMesh is Y-up by default; rotate 90° on X so it lies along Z.
	handle_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	handle_mi.position         = Vector3(0.0, 0.0, 0.0)

	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.12, 0.12, 0.14, 1.0)
	body_mat.roughness    = 0.75
	body_mat.metallic     = 0.6
	handle_mi.set_surface_override_material(0, body_mat)
	add_child(handle_mi)
	_body_mesh = handle_mi

	## Head — wider, shorter, pushed forward along +Z
	var head_mi: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: CylinderMesh = CylinderMesh.new()
	head_mesh.top_radius      = 0.045
	head_mesh.bottom_radius   = 0.055
	head_mesh.height          = 0.06
	head_mesh.radial_segments = 10
	head_mi.mesh = head_mesh
	head_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	head_mi.position         = Vector3(0.0, 0.0, 0.15)

	var head_mat: StandardMaterial3D = StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.15, 0.15, 0.18, 1.0)
	head_mat.roughness    = 0.65
	head_mat.metallic     = 0.7
	head_mi.set_surface_override_material(0, head_mat)
	add_child(head_mi)

	## Lens cap — thin glowing disk at the very tip
	var lens_mi: MeshInstance3D = MeshInstance3D.new()
	var lens_mesh: CylinderMesh = CylinderMesh.new()
	lens_mesh.top_radius      = 0.044
	lens_mesh.bottom_radius   = 0.044
	lens_mesh.height          = 0.005
	lens_mesh.radial_segments = 14
	lens_mi.mesh = lens_mesh
	lens_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	lens_mi.position         = Vector3(0.0, 0.0, 0.182)

	_lens_mat = StandardMaterial3D.new()
	_lens_mat.albedo_color               = COL_DEAD
	_lens_mat.emission_enabled           = true
	_lens_mat.emission                   = COL_DEAD
	_lens_mat.emission_energy_multiplier = 0.0
	_lens_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_mi.set_surface_override_material(0, _lens_mat)
	add_child(lens_mi)

func _build_light() -> void:
	_spot = SpotLight3D.new()
	## Positioned at the lens tip, pointing along +Z (forward).
	## A small downward pitch (BEAM_PITCH_DEG) makes it illuminate the floor
	## ahead of the player rather than shooting into the far wall at eye level.
	_spot.position               = Vector3(0.0, 0.0, 0.20)
	_spot.rotation_degrees       = Vector3(BEAM_PITCH_DEG, 0.0, 0.0)
	_spot.spot_angle             = CONE_OUTER
	_spot.spot_angle_attenuation = 0.5
	_spot.spot_range             = LIGHT_RANGE
	_spot.light_energy           = LIGHT_ENERGY
	_spot.light_color            = COL_ON
	_spot.visible                = false   ## off at spawn
	_apply_graphics_settings()
	add_child(_spot)
	## Live-update if the player flips a toggle while holding this flashlight.
	GraphicsSettings.settings_changed.connect(_apply_graphics_settings)

## Applies the player's GraphicsSettings toggles to this flashlight's
## SpotLight3D. Called once at build time and again on every
## GraphicsSettings.settings_changed (preset switch or individual toggle).
func _apply_graphics_settings() -> void:
	if _spot == null:
		return
	## Shadow casting stays default OFF as a documented gameplay choice —
	## handheld shadow would block the center of the cone. Explicit opt-in
	## only, never preset-driven (GraphicsSettings.flashlight_shadows is
	## excluded from every preset's dictionary for this exact reason).
	_spot.shadow_enabled = GraphicsSettings.flashlight_shadows
	## Per-light volumetric-fog contribution (Light3D property, independent
	## of Environment.volumetric_fog_enabled) — lets the dust-mote beam-shaft
	## look be toggled off for performance without disabling ambient fog
	## everywhere else. 0.0 skips volumetric-fog computation for this light.
	_spot.light_volumetric_fog_energy = 1.0 if GraphicsSettings.flashlight_volumetrics else 0.0

## Adds a CapsuleShape3D collision body oriented along +Z (the flashlight's length axis).
## Without this the RigidBody3D has no shape and Jolt physics ignores it entirely.
func _build_collision() -> void:
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = 0.045       ## slightly wider than handle radius
	cap.height = 0.28        ## spans handle + head (~0.24 + a bit)
	col_shape.shape = cap
	## Rotate 90° on X so the capsule's long axis aligns with +Z (forward)
	col_shape.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(col_shape)

func _refresh_state() -> void:
	var actually_on: bool = _on and not _is_dead

	if _spot != null:
		_spot.visible = actually_on

	if _lens_mat != null:
		if actually_on:
			var col: Color = COL_LOW if _battery < 20.0 else COL_ON
			_lens_mat.albedo_color               = col
			_lens_mat.emission                   = col
			_lens_mat.emission_energy_multiplier = 1.8
		else:
			_lens_mat.albedo_color               = COL_DEAD
			_lens_mat.emission                   = COL_DEAD
			_lens_mat.emission_energy_multiplier = 0.0

	## Battery % is shown via the InventoryHUD badge (get_charge_info) — no 3D label needed.

# ─── Physics + orientation ────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	## Battery drain
	if _on and not _is_dead:
		_battery -= BATTERY_DRAIN * delta
		if _battery <= 0.0:
			_battery = 0.0
			_is_dead  = true
			_on       = false
			_refresh_state()
			charge_changed.emit()
		elif fmod(_battery, 5.0) < (BATTERY_DRAIN * delta):
			_refresh_state()
			charge_changed.emit()

	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float     = global_position.distance_to(target)

	if not from_inventory:
		if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_do_knocked_out()
				return
		else:
			_out_of_range_time = 0.0

	## Move toward hold point
	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (target - global_position) * speed

	## ── Aim toward player's facing direction ──────────────────────────────────
	## The player's rotation.y is the yaw angle facing its movement direction.
	## We lock the flashlight body to that same yaw (flat, no pitch/roll) so the
	## mesh and spotlight always point where the player is going.
	## angular_velocity must be zeroed AFTER setting rotation so physics doesn't
	## fight us next frame.
	if _player != null and is_instance_valid(_player):
		## Track player's actual facing direction (rotation.y set by atan2 in Player._handle_movement).
		## camera_yaw_rad is the camera's orbital yaw — NOT the player's facing direction — so
		## using it caused the beam to rotate with the camera instead of with the player.
		## rotation.y holds the last-moved facing angle, which is correct flashlight behaviour.
		rotation = Vector3(0.0, _player.rotation.y, 0.0)
	angular_velocity = Vector3.ZERO

## Called deferred by BunkerPregen after global_position is set.
func _unfreeze_after_spawn() -> void:
	freeze = false

# ─── Inventory charge badge ───────────────────────────────────────────────────
## InventoryHUD calls this to show the battery % badge on the slot.
## Returns [current_int, max_int] — HUD renders "current/max" or just "current" if max==1.
## We return integer percent so the badge shows e.g. "87/100".
func get_charge_info() -> Array:
	return [int(_battery), 100]

# ─── Prompt interface ─────────────────────────────────────────────────────────
func get_display_name() -> String:
	return "Flashlight"

func get_prompt_text() -> String:
	if _is_dead:
		return "[F] Pick up  Flashlight (Dead)"
	return "[F] Pick up  Flashlight (%d%%)" % int(_battery)

func get_use_prompt() -> String:
	if _is_dead:
		return ""
	return "[E] %s flashlight" % ("Turn Off" if _on else "Turn On")

# ─── Pickup / Drop ────────────────────────────────────────────────────────────
func set_player(p: Node3D) -> void:
	## Called by InteractionSystem when this item is picked up.
	_player = p

func pickup(hold_point: Node3D) -> void:
	is_held            = true
	_hold_point        = hold_point
	_grace_timer       = pickup_grace
	_out_of_range_time = 0.0
	freeze             = false
	freeze_mode        = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale      = 0.0
	collision_layer    = 2
	collision_mask     = 1
	## Self-healing player ref: if set_player() was never called (e.g. pregen
	## inventory path), find the player via group so facing still works.
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	_set_held_culling(true)
	picked_up.emit()

func drop(_world_parent: Node3D, drop_position: Vector3) -> void:
	is_held         = false
	_hold_point     = null
	_player         = null
	global_position = drop_position
	gravity_scale   = 1.0
	freeze          = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3.ZERO
	add_to_group("pickup")
	_set_held_culling(false)
	dropped.emit()

func place(_world_parent: Node3D, place_position: Vector3, _rot: Vector3 = Vector3.ZERO) -> void:
	drop(_world_parent, place_position)

# ─── Use: toggle light ────────────────────────────────────────────────────────
func on_use() -> void:
	if _is_dead:
		return
	_on = not _on
	_refresh_state()

# ─── Knocked out ──────────────────────────────────────────────────────────────
func _do_knocked_out() -> void:
	is_held         = false
	_hold_point     = null
	_player         = null
	gravity_scale   = 1.0
	freeze          = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	_set_held_culling(false)
	knocked_out.emit()

# ─── Culling ─────────────────────────────────────────────────────────────────
func _set_held_culling(held: bool) -> void:
	var margin: float = 10.0 if held else 0.0
	for child: Node in get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).extra_cull_margin = margin
