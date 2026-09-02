extends Camera3D
class_name GameCamera
## GameCamera.gd
## Fixed isometric camera that smoothly transitions to top-down during build mode.
## Supports 90° yaw rotation via Home (CCW) and End (CW) keys.
## Attach to: Camera3D node inside res://scenes/world/MainWorld.tscn

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var follow_speed: float    = 8.0    ## Lerp speed for position follow.
@export var height: float          = 14.0   ## Camera height in normal mode.
@export var z_offset: float        = 8.0    ## Pull-back on Z in normal mode.
@export var target_path: NodePath  = NodePath()

## Build mode camera settings
@export var build_height: float    = 14.0   ## Height when top-down.
@export var build_z_offset: float  = 0.0    ## No Z pull-back when top-down.
@export var transition_speed: float = 4.0   ## Lerp speed for mode transition.

## Yaw rotation settings
@export var yaw_lerp_speed: float  = 6.0    ## How fast the 90° snap animates.

## Depth of field (tilt-shift rework, Aug 2026 — replaces the old
## CameraAttributesPractical distance-based DOF; see
## docs/systems/graphics/README.md "Tilt-shift DOF" for why). Keeps a
## horizontal band of the screen sharp and blurs the ceiling/back-wall area
## above it and the foreground edge below it — screen-space, NOT tied to
## camera-to-target distance, so it stays correct at every FOV setting and
## never partially blurs through a single tall object the way the old
## point-focus version did. Auto-disabled in build mode (max placement
## clarity) regardless of the setting, and gated on GraphicsSettings.dof_enabled
## otherwise — same two rules as before, just applied to a different effect.
@export_range(0.0, 1.0) var dof_focus_center_y: float = 0.55
@export_range(0.0, 0.5) var dof_focus_band_half_height: float = 0.16
@export_range(0.01, 0.5) var dof_transition_height: float = 0.22
@export_range(0.0, 16.0) var dof_max_blur_px: float = 6.0

## Trauma-based camera shake (graphics plan Phase 7) — additive on top of
## the existing lerped transform, does not replace/change it. Call
## add_trauma() from gameplay events (e.g. MainWorld's grid_tripped handler).
@export var trauma_decay_per_sec: float = 1.2
@export var max_shake_offset: float = 0.35   ## metres
@export var max_shake_rotation_deg: float = 2.0

# ─── Internal ─────────────────────────────────────────────────────────────────
var _target: Node3D    = null
var _build_mode: bool  = false
var _trauma: float = 0.0
var _shake_seed: float = 0.0

## Injected by MainWorld._setup_tilt_shift_dof() right after it creates this
## node — MainWorld also calls _apply_dof_setting() again immediately after
## assigning this, so node-_ready()-ordering between GameCamera and
## TiltShiftDOF doesn't matter; the null-guard in _apply_dof_setting() below
## just needs to survive the brief window before that injection happens.
var tilt_shift: TiltShiftDOF = null

## Current interpolated camera params (lerped each frame)
var _cur_height:  float = 0.0
var _cur_z_off:   float = 0.0

## Yaw orbit (snaps to 0 / 90 / 180 / 270)
var _target_yaw_rad: float = 0.0   ## Destination yaw in radians
var _cur_yaw_rad:    float = 0.0   ## Current interpolated yaw in radians

func _ready() -> void:
	_cur_height    = height
	_cur_z_off     = z_offset
	_cur_yaw_rad   = 0.0
	_target_yaw_rad = 0.0

	if not target_path.is_empty():
		_target = get_node(target_path)
	else:
		push_warning("GameCamera: No target assigned. Set target_path in Inspector.")

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
## GraphicsSettings.dof_enabled. Forwards to the screen-space tilt-shift
## node rather than a CameraAttributesPractical resource — see the export
## block above for why.
func _apply_dof_setting() -> void:
	if tilt_shift == null:
		return
	var active: bool = (not _build_mode) and GraphicsSettings.dof_enabled
	tilt_shift.apply(active, dof_focus_center_y, dof_focus_band_half_height,
			dof_transition_height, dof_max_blur_px)

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
	## Pitch is derived from the current height/z-offset (see _follow_target),
	## so only the position params lerp here — the camera pitches to follow.
	var t: float = transition_speed * delta
	if _build_mode:
		_cur_height = lerp(_cur_height, build_height,  t)
		_cur_z_off  = lerp(_cur_z_off,  build_z_offset, t)
	else:
		_cur_height = lerp(_cur_height, height,        t)
		_cur_z_off  = lerp(_cur_z_off,  z_offset,       t)

	## Yaw lerp — everything in radians so lerp_angle works correctly
	_cur_yaw_rad = lerp_angle(_cur_yaw_rad, _target_yaw_rad, yaw_lerp_speed * delta)

func _follow_target(delta: float) -> void:
	## Build raw offset then rotate around Y by current yaw
	var offset: Vector3 = Vector3(0.0, _cur_height, _cur_z_off)
	offset = offset.rotated(Vector3.UP, _cur_yaw_rad)

	var desired_pos: Vector3 = _target.global_position + offset
	## Aug 2026 — lerped position follow (follow_speed was always exported for
	## this but unused): the camera smoothly glides to the target instead of
	## teleporting with it, so when the player snaps to the stand position at
	## the end of a sit/stand animation the camera transitions smoothly instead
	## of snapping with the model.
	global_position = global_position.lerp(desired_pos, clampf(follow_speed * delta, 0.0, 1.0))

	## ONE consistent orientation for both modes (Aug 2026 fix). Pitch is
	## derived from the CURRENT offset (height vs z-offset) so the camera
	## always points exactly at the target and the iso → top-down transition
	## is smooth. Previously this switched between look_at() and an explicit
	## Euler once _cur_pitch crossed 80°, and the two formulas computed the
	## angle differently (look_at uses atan2(height, z_off) ≈ 80.7° at the
	## switch vs the param's 80.1°) — a visible snap mid-transition. The
	## explicit rotation also avoids look_at()'s gimbal-lock instability near
	## straight-down, so no branch switch is needed at all.
	rotation = Vector3(
		-atan2(_cur_height, _cur_z_off),
		_cur_yaw_rad,
		0.0)

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
