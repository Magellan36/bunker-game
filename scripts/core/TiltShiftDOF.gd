extends CanvasLayer
class_name TiltShiftDOF
## TiltShiftDOF.gd
## Screen-space tilt-shift DOF — full-rect ColorRect + shader material only.
## GameCamera.gd owns all decision-making (build-mode override,
## GraphicsSettings.dof_enabled gating, tuning values) the same way it
## already owns FOV; this node just forwards apply() calls to shader
## uniforms. See docs/systems/graphics/README.md.
##
## Instantiated dynamically by MainWorld._setup_tilt_shift_dof() (same
## pattern as LightingDirector.gd) — not a scene-defined node, so it never
## needs a .tscn edit or a manual Godot-editor step.

const SHADER_PATH: String = "res://assets/shaders/tilt_shift_dof.gdshader"

var _rect: ColorRect = null
var _mat:  ShaderMaterial = null

func _ready() -> void:
	## Renders above the 3D world but below every UI CanvasLayer — HUD is
	## the lowest UI layer at the default (unset) value of 1; every other
	## menu/panel is >=10 (StorageUI=10 up to NotificationManager=220).
	## Layer 0 guarantees this always draws before (i.e. underneath) all of
	## them, so the blur only ever touches the 3D game view, never UI.
	layer = 0

	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		push_warning("[TiltShiftDOF] tilt_shift_dof.gdshader not found")
		return
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect.material = _mat
	add_child(_rect)

## Called by GameCamera whenever GraphicsSettings.settings_changed fires or
## build mode toggles. `active` gates the whole effect (dof_enabled AND not
## build mode); the four tuning values map 1:1 to GameCamera's own exports.
func apply(active: bool, focus_center_y: float, focus_band_half_height: float,
		transition_height: float, max_blur_px: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("strength", 1.0 if active else 0.0)
	_mat.set_shader_parameter("focus_center_y", focus_center_y)
	_mat.set_shader_parameter("focus_band_half_height", focus_band_half_height)
	_mat.set_shader_parameter("transition_height", transition_height)
	_mat.set_shader_parameter("max_blur_px", max_blur_px)