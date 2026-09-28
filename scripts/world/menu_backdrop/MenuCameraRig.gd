extends Node3D
## MenuCameraRig.gd (Sep 2026)
## Cinematic camera for the main-menu surface view. The authored transform in
## MenuBackdrop.tscn is the rest pose; everything here is a small, smoothed
## offset from it: an opening dolly, pointer parallax and a push-in when the
## player leaves the menu. No screen shake and no idle drift (Sep 2026: the
## old noise "drift" read as handheld shake, so it was removed).
## Reduced motion (UIMotion) collapses all of it to the static rest pose.

@export var camera: Camera3D
## Look-toward-pointer range in degrees (yaw, pitch).
@export var parallax_degrees: Vector2 = Vector2(1.4, 0.8)
## Lateral camera shift at the screen edge, metres.
@export var parallax_shift: float = 0.16
## The opening shot starts this far behind the rest pose and settles forward.
@export var intro_dolly: float = 3.0
@export var intro_duration: float = 8.0
## Leaving the menu pushes forward and narrows the lens.
@export var exit_push: float = 3.5
@export var exit_fov_scale: float = 0.84

var _rest: Transform3D
var _rest_fov: float = 50.0
var _pointer: Vector2 = Vector2.ZERO
var _pointer_smoothed: Vector2 = Vector2.ZERO
var _intro: float = 0.0
var _exit: float = 0.0


func _ready() -> void:
	_rest = transform
	if camera != null:
		_rest_fov = camera.fov
	if UIMotion.reduced():
		_intro = 1.0
	_apply()


func set_pointer(normalized: Vector2) -> void:
	_pointer = normalized.clamp(Vector2(-1.0, -1.0), Vector2.ONE)


func skip_intro() -> void:
	_intro = 1.0


func play_exit(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "_exit", 1.0, maxf(UIMotion.duration(seconds), 0.01)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func _process(delta: float) -> void:
	if _intro < 1.0:
		_intro = minf(1.0, _intro + delta / maxf(intro_duration, 0.01))
	var target := Vector2.ZERO if UIMotion.reduced() else _pointer
	_pointer_smoothed = _pointer_smoothed.lerp(target, 1.0 - exp(-2.0 * delta))
	_apply()


func _apply() -> void:
	var yaw := -_pointer_smoothed.x * parallax_degrees.x
	var pitch := -_pointer_smoothed.y * parallax_degrees.y
	var intro_ease := 1.0 - pow(1.0 - _intro, 3.0)
	var exit_ease := _exit
	var offset := Vector3(_pointer_smoothed.x * parallax_shift, 0.0, 0.0)
	offset.z += (1.0 - intro_ease) * intro_dolly - exit_ease * exit_push
	offset.y += (1.0 - intro_ease) * 0.2
	var local := Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)), offset)
	transform = _rest * local
	if camera != null:
		camera.fov = _rest_fov * lerpf(1.0, exit_fov_scale, exit_ease)
