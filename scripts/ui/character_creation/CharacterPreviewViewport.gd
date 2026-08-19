extends SubViewportContainer
## Orbit/zoom controls for the character-creation preview only — mouse
## drag orbits, scroll wheel zooms. Scoped entirely to this container's
## own input via _gui_input(), doesn't touch any other camera or the
## real game's input at all, since this whole screen runs before the
## game ever loads.

@export var camera: Camera3D = null
## Aug 2026 — retuned for the character's actual scaled height (~2.1 m
## after the 1.25x model scale) now that both the facing and floor-
## offset fixes are in — the old values were tuned blind before either
## existed. ~1.0 m (roughly navel/lower-torso height) centers a
## standing figure of that height reasonably in frame at this distance.
@export var look_at_point: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var distance: float = 2.2
@export var min_distance: float = 1.2
@export var max_distance: float = 5.0
@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 0.25

## Aug 2026 — yaw starts at PI, not 0. At yaw 0 the camera sits at +Z
## looking toward -Z; the character's front faces -Z (Godot's own
## forward convention, after PlayerModelController's 180° Mixamo-axis
## fix) — so a camera at +Z is looking at the character from behind
## where its face points, i.e. its back. PI puts the camera on the
## correct side to see the front by default.
var _yaw: float = PI
var _pitch: float = -0.05
var _dragging: bool = false

func _ready() -> void:
	_update_camera()
	_apply_graphics_settings()

## Aug 2026 — GPU-crash mitigation. The preview SubViewport (960x1080) is
## the heaviest 3D render target on the character-creation screen; its MSAA
## is forced off and its 3D render scale is routed through the existing
## GraphicsSettings autoload so a lowered render_scale actually reduces the
## preview's GPU load instead of only affecting the in-world viewport. The
## preview is one static skinned mesh — MSAA here is visually imperceptible,
## and the Forward+ MSAA buffer it would otherwise reserve is exactly the
## kind of render-target pressure that triggered the RENDER_LIST_OPAQUE
## allocation failure on the RX 580 (see godotcrash.txt investigation).
func _apply_graphics_settings() -> void:
	var vp := get_node_or_null("SubViewport") as SubViewport
	if vp == null:
		return
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = GraphicsSettings.render_scale

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