extends SubViewportContainer
## Orbit/zoom controls for the character-creation preview only — mouse
## drag orbits, scroll wheel zooms. Scoped entirely to this container's
## own input via _gui_input(), doesn't touch any other camera or the
## real game's input at all, since this whole screen runs before the
## game ever loads.

@export var camera: Camera3D = null
## Aug 2026 — retuned for the character's actual scaled height (~2.1 m
## after the 1.25x model scale). Measured bones (scaled): feet y≈0.06,
## pelvis/Hips y≈1.12, head y≈1.98. The old 0.8 aimed below the pelvis,
## pushing the figure too high in frame.
##
## Aug 2026, third pass — centered on the stomach/navel region (~1.1),
## which both centers the figure vertically and lands the aim on the
## abdomen as requested.
@export var look_at_point: Vector3 = Vector3(0.0, 1.2, 0.0)
@export var distance: float = 2.2
@export var min_distance: float = 1.2
@export var max_distance: float = 5.0
@export var orbit_speed: float = 0.005
@export var zoom_speed: float = 0.25

## Aug 2026 — right stick orbits the preview (gamepad support), mirroring
## the mouse-drag yaw swing. Radians per second at full stick deflection;
## tunable, matching the feel of mouse-orbit at this distance.
@export var stick_orbit_speed: float = 1.5
## Aug 2026 — right-stick Y pans the preview vertically, mirroring
## middle-mouse drag. World units per second at full deflection, scaled by
## the current zoom distance (same relationship pan_speed uses), so the
## feel stays consistent at any zoom.
@export var stick_pan_speed: float = 0.5
## Right-stick magnitude below which no orbit happens (avoids drift from a
## resting stick).
const STICK_DEADZONE: float = 0.3

## Aug 2026 — yaw starts at PI, not 0. At yaw 0 the camera sits at +Z
## looking toward -Z; the character's front faces -Z (Godot's own
## forward convention, after PlayerModelController's 180° Mixamo-axis
## fix) — so a camera at +Z is looking at the character from behind
## where its face points, i.e. its back. PI puts the camera on the
## correct side to see the front by default.
var _yaw: float = PI
var _pitch: float = -0.05
var _dragging_orbit: bool = false
var _dragging_pan: bool = false

## Aug 2026 — middle-click-drag pan. Scaled by the current zoom distance
## in _gui_input() below (not a flat pixel-to-world ratio) so panning
## feels consistent whether zoomed in close or backed out — the same
## mouse-pixel drag should cover the same FRACTION of the visible frame
## at any zoom level, not the same absolute world distance.
@export var pan_speed: float = 0.0015

func _ready() -> void:
	_update_camera()
	_apply_graphics_settings()

## Aug 2026 — right stick orbits (X) and pans vertically (Y) the preview,
## mirroring mouse-drag orbit and middle-mouse-drag pan. Polled in _process
## so a held stick keeps moving; analog (small push = slow movement).
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > STICK_DEADZONE:
		_yaw -= rx * stick_orbit_speed * delta
		_update_camera()
	if absf(ry) > STICK_DEADZONE:
		## Screen-relative vertical pan, same as middle-mouse drag:
		## move look_at_point along the camera's own up vector.
		look_at_point += camera.global_transform.basis.y * ry * (stick_pan_speed * distance) * delta
		_update_camera()

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
		## Aug 2026 — left AND right button both drive the same
		## horizontal-only orbit now (previously left-only, and
		## previously also adjusted pitch — see _pitch's fixed value
		## above, no longer touched here at all).
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging_orbit = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_pan = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance - zoom_speed, min_distance, max_distance)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance + zoom_speed, min_distance, max_distance)
			_update_camera()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging_orbit:
			## Yaw only — _pitch is never touched by dragging anymore,
			## so the camera only ever swings left/right around the
			## character, never tilts up/down.
			_yaw -= mm.relative.x * orbit_speed
			_update_camera()
		elif _dragging_pan:
			## Screen-relative pan: camera's OWN current right/up
			## vectors, not world X/Z — so a horizontal drag always
			## pans horizontally on screen and a vertical drag always
			## pans vertically, regardless of the current yaw. The
			## viewing angle itself (_yaw/_pitch/distance) never
			## changes here, only what point it's centered on.
			var cam_right: Vector3 = camera.global_transform.basis.x
			var cam_up: Vector3 = camera.global_transform.basis.y
			var pan_scale: float = pan_speed * distance
			look_at_point -= cam_right * mm.relative.x * pan_scale
			look_at_point += cam_up * mm.relative.y * pan_scale
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