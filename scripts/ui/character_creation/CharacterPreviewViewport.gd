extends SubViewportContainer
## Orbit/zoom controls for the character-creation preview only — mouse
## drag orbits, scroll wheel zooms. Scoped entirely to this container's
## own input via _gui_input(), doesn't touch any other camera or the
## real game's input at all, since this whole screen runs before the
## game ever loads.

@export var camera: Camera3D = null
@export var look_at_point: Vector3 = Vector3(0.0, 1.4, 0.0)  ## roughly chest height
@export var distance: float = 3.0
@export var min_distance: float = 1.2
@export var max_distance: float = 6.0
@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 0.25

var _yaw: float = 0.0
var _pitch: float = -0.1
var _dragging: bool = false

func _ready() -> void:
	_update_camera()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance - zoom_speed, min_distance, max_distance)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance + zoom_speed, min_distance, max_distance)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * orbit_speed
		_pitch = clampf(_pitch - mm.relative.y * orbit_speed, -1.3, 1.3)
		_update_camera()

func _update_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch),
	) * distance
	camera.position = look_at_point + offset
	camera.look_at(look_at_point, Vector3.UP)