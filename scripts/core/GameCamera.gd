extends Camera3D
class_name GameCamera
## GameCamera.gd
## Fixed isometric camera that smoothly transitions to top-down during build mode.
## Supports 90° yaw rotation via Home (CCW) and End (CW) keys.
## Attach to: Camera3D node inside res://scenes/world/MainWorld.tscn

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var follow_speed: float    = 8.0    ## Lerp speed for position follow.
@export var height: float          = 14.0   ## Camera height in normal mode.
@export var pitch_degrees: float   = 55.0   ## Iso pitch angle (45–60 looks best).
@export var z_offset: float        = 8.0    ## Pull-back on Z in normal mode.
@export var target_path: NodePath  = NodePath()

## Build mode camera settings
@export var build_height: float    = 14.0   ## Height when top-down.
@export var build_z_offset: float  = 0.0    ## No Z pull-back when top-down.
@export var transition_speed: float = 4.0   ## Lerp speed for mode transition.

## Yaw rotation settings
@export var yaw_lerp_speed: float  = 6.0    ## How fast the 90° snap animates.

## Depth of field (graphics plan Phase 7) — gently softens the background so
## focus reads on whatever the flashlight/lights are hitting. Auto-disabled
## in build mode (max placement clarity) regardless of the setting, and
## gated on GraphicsSettings.dof_enabled otherwise.
@export var dof_focus_distance: float = 9.0
@export var dof_far_blur_amount: float = 0.08

## Trauma-based camera shake (graphics plan Phase 7) — additive on top of
## the existing lerped transform, does not replace/change it. Call
## add_trauma() from gameplay events (e.g. MainWorld's grid_tripped handler).
@export var trauma_decay_per_sec: float = 1.2
@export var max_shake_offset: float = 0.35   ## metres
@export var max_shake_rotation_deg: float = 2.0

# ─── Internal ─────────────────────────────────────────────────────────────────
var _target: Node3D    = null
var _build_mode: bool  = false
var _attributes: CameraAttributesPractical = null
var _trauma: float = 0.0
var _shake_seed: float = 0.0

## Current interpolated camera params (lerped each frame)
var _cur_height:  float = 0.0
var _cur_pitch:   float = 0.0
var _cur_z_off:   float = 0.0

## Yaw orbit (snaps to 0 / 90 / 180 / 270)
var _target_yaw_rad: float = 0.0   ## Destination yaw in radians
var _cur_yaw_rad:    float = 0.0   ## Current interpolated yaw in radians

func _ready() -> void:
	_cur_height    = height
	_cur_pitch     = pitch_degrees
	_cur_z_off     = z_offset
	_cur_yaw_rad   = 0.0
	_target_yaw_rad = 0.0

	if not target_path.is_empty():
		_target = get_node(target_path)
	else:
		push_warning("GameCamera: No target assigned. Set target_path in Inspector.")

	_attributes = CameraAttributesPractical.new()
	_attributes.dof_blur_far_distance   = dof_focus_distance
	_attributes.dof_blur_far_transition = 4.0
	_attributes.dof_blur_amount         = dof_far_blur_amount
	attributes = _attributes
	GraphicsSettings.settings_changed.connect(_apply_dof_setting)
	GraphicsSettings.settings_changed.connect(_apply_fov_setting)
	_apply_dof_setting()
	_apply_fov_setting()

func enter_build_mode() -> void:
	_build_mode = true
	_apply_dof_setting()   ## Forces DOF off in build mode regardless of setting

func exit_build_mode() -> void:
	_build_mode = false
	_apply_dof_setting()

## Depth of field is OFF in build mode unconditionally (max placement
## clarity, per graphics plan Section 5), and otherwise follows
## GraphicsSettings.dof_enabled.
func _apply_dof_setting() -> void:
	if _attributes == null:
		return
	_attributes.dof_blur_far_enabled = (not _build_mode) and GraphicsSettings.dof_enabled

## FOV is a comfort/motion-sickness preference (not preset-driven, see
## GraphicsSettings.camera_fov), applied unconditionally in both camera modes.
func _apply_fov_setting() -> void:
	fov = GraphicsSettings.camera_fov

## Adds camera shake trauma (0–1, clamped). Call from gameplay events, e.g.
## MainWorld's grid_tripped handler. Shake intensity scales with trauma^2 so
## small trauma amounts stay subtle and only heavy trauma reads as violent.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## Rotate camera 90° counter-clockwise (Home key)
func rotate_view_left() -> void:
	_target_yaw_rad -= PI * 0.5

## Rotate camera 90° clockwise (End key)
func rotate_view_right() -> void:
	_target_yaw_rad += PI * 0.5

func _physics_process(delta: float) -> void:
	if _target == null:
		return
	_lerp_camera_params(delta)
	_follow_target(delta)
	_apply_shake(delta)

func _lerp_camera_params(delta: float) -> void:
	var t: float = transition_speed * delta
	if _build_mode:
		_cur_height = lerp(_cur_height, build_height,  t)
		_cur_pitch  = lerp(_cur_pitch,  90.0,           t)
		_cur_z_off  = lerp(_cur_z_off,  build_z_offset, t)
	else:
		_cur_height = lerp(_cur_height, height,        t)
		_cur_pitch  = lerp(_cur_pitch,  pitch_degrees,  t)
		_cur_z_off  = lerp(_cur_z_off,  z_offset,       t)

	## Yaw lerp — everything in radians so lerp_angle works correctly
	_cur_yaw_rad = lerp_angle(_cur_yaw_rad, _target_yaw_rad, yaw_lerp_speed * delta)

func _follow_target(delta: float) -> void:
	## Build raw offset then rotate around Y by current yaw
	var offset: Vector3 = Vector3(0.0, _cur_height, _cur_z_off)
	offset = offset.rotated(Vector3.UP, _cur_yaw_rad)

	var desired_pos: Vector3 = _target.global_position + offset
	global_position = desired_pos

	## In build mode the camera is nearly straight down — look_at breaks with
	## Vector3.UP as the up vector (gimbal lock). Use yaw-derived forward instead.
	if _cur_pitch > 80.0:
		## rotation.y must use the same sign as the offset rotation and player
		## movement (both use +_cur_yaw_rad). Negating here caused build-mode
		## controls to move opposite to the camera's visual facing.
		rotation = Vector3(deg_to_rad(-_cur_pitch), _cur_yaw_rad, 0.0)
	else:
		look_at(_target.global_position, Vector3.UP)

## Additive trauma-based shake, applied ON TOP of the position/rotation
## _follow_target() just set — never replaces it, so shake decaying to zero
## always settles back to exactly the normal lerped camera pose.
func _apply_shake(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - trauma_decay_per_sec * delta)
	if _trauma <= 0.0:
		return
	_shake_seed += delta * 25.0
	var shake: float = _trauma * _trauma   ## quadratic falloff — small trauma stays subtle
	## sin/cos at different, non-multiple frequencies gives a decent cheap
	## pseudo-random jitter without needing an actual Noise resource.
	var offset: Vector3 = Vector3(
		sin(_shake_seed * 1.7),
		sin(_shake_seed * 2.3),
		0.0) * max_shake_offset * shake
	global_position += offset
	rotation.z += sin(_shake_seed * 3.1) * deg_to_rad(max_shake_rotation_deg) * shake
