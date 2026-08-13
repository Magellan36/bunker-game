extends Node3D
class_name InteractionFocusGlow
## InteractionFocusGlow.gd  —  Focus Mode target highlight (Aug 2026)
## ─────────────────────────────────────────────────────────────────────────
## Rim-light outline + soft halo on whatever object Focus Mode (hold Ctrl)
## is currently highlighting. Driven by InteractionSystem calling
## set_target(node_or_null) once per _update_prompt() call — this node
## owns its own _process() for the pulse/position animation, so it stays
## correct regardless of exactly how often the caller updates the target.
##
## Rim outline: a single shared Fresnel ShaderMaterial applied via
## GeometryInstance3D.material_overlay to every MeshInstance3D found
## (recursively) under the target. This is an EXTRA render pass on top of
## each mesh's existing material — nothing about the target's own
## appearance, material, or geometry is touched or duplicated, which is
## what makes this safe to apply to any object regardless of how its mesh
## was authored (procedural primitives, GLB imports, multi-part
## assemblies like Can Case's dozen individual can visuals).
##
## Soft halo: one Sprite3D, procedurally-generated radial gradient
## texture (no external asset), billboarded to always face the camera,
## repositioned to the target's global_position every frame.
##
## Defensively coded against a freed target — is_instance_valid() checked
## every frame before touching the target or any mesh instance under it;
## clearing state on invalidity rather than assuming set_target(null)
## will always be called first (a target can be picked up, stored, or
## otherwise removed out from under Focus Mode mid-highlight).

const PULSE_SPEED:     float = 2.0    ## radians/sec — one full breath ~3.1s
const PULSE_AMPLITUDE: float = 0.22   ## +/-22% — "slightly more intense"
const RIM_BASE_INTENSITY: float = 0.75   ## multiplies the shader's already edge-restricted
                                          ## fresnel alpha — this is the ONLY rim knob now
const HALO_BASE_ALPHA:    float = 0.75   ## more opaque
const HALO_WORLD_DIAMETER: float = 1.0   ## metres — tune in-editor per feel

var _target: Node3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _rim_material: ShaderMaterial = null
var _halo: Sprite3D = null
var _pulse_time: float = 0.0

func _ready() -> void:
	_rim_material = _build_rim_material()
	_halo = _build_halo_sprite()
	add_child(_halo)
	_halo.visible = false

## Aug 2026 (reverted, corrected) — StandardMaterial3D.rim_enabled turned
## out to be the wrong tool: it's an ADDITIONAL lighting-response term at
## grazing angles, layered on top of the base albedo/emission — it does
## NOT mask or restrict the base material to the edges. The base material
## (opaque-ish albedo alpha + full-surface emission) was rendering across
## the ENTIRE mesh, which is exactly the "nearly completely white whole
## object" reported. Back to a Fresnel shader — the only technique that
## actually restricts color to the silhouette, by driving ALPHA itself
## from the fresnel term (near-zero facing the camera, near-full at
## grazing/edge angles) rather than adding a bonus on top of an
## already-fully-opaque surface. Standard alpha blend (blend_mix), not
## additive — additive was the earlier "too intense" complaint; this
## fixes both problems in one pass rather than re-guessing either alone.
func _build_rim_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled;

uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 12.0) = 5.0;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb;
	ALPHA = fresnel * rim_intensity;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func _build_halo_sprite() -> Sprite3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient   = gradient
	tex.width      = 128
	tex.height     = 128
	tex.fill       = GradientTexture2D.FILL_RADIAL
	tex.fill_from  = Vector2(0.5, 0.5)
	tex.fill_to    = Vector2(1.0, 0.5)

	var sprite := Sprite3D.new()
	sprite.texture     = tex
	sprite.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded      = false
	sprite.transparent = true
	sprite.double_sided = true
	sprite.pixel_size  = HALO_WORLD_DIAMETER / float(tex.width)
	sprite.modulate    = Color(1.0, 1.0, 1.0, 0.0)
	return sprite

## Called once per InteractionSystem._update_prompt() invocation with the
## resolved Focus Mode target (or null — no highlight this frame). Only
## rediscovers mesh instances when the target actually changes; cheap to
## call every frame regardless.
func set_target(node: Node3D) -> void:
	if node == _target:
		return
	_clear_current_overlay()
	_target = node
	if _target != null and is_instance_valid(_target):
		_mesh_instances = _find_mesh_instances(_target)
		for mi: MeshInstance3D in _mesh_instances:
			mi.material_overlay = _rim_material
	else:
		_target = null

func _clear_current_overlay() -> void:
	if _target != null and is_instance_valid(_target):
		for mi: MeshInstance3D in _mesh_instances:
			if is_instance_valid(mi):
				mi.material_overlay = null
	_mesh_instances.clear()

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		result.append_array(_find_mesh_instances(child))
	return result

func _process(delta: float) -> void:
	## Defensive: target freed externally (picked up, stored, deconstructed,
	## etc.) without set_target(null) ever being called — self-heal rather
	## than touch a dangling reference. Same discipline established
	## elsewhere in this file's history for held_item.
	if _target != null and not is_instance_valid(_target):
		_mesh_instances.clear()
		_target = null

	if _target == null:
		_halo.visible = false
		return

	_pulse_time += delta
	var pulse: float = 1.0 + sin(_pulse_time * PULSE_SPEED) * PULSE_AMPLITUDE

	_rim_material.set_shader_parameter("rim_intensity", RIM_BASE_INTENSITY * pulse)

	_halo.visible = true
	_halo.global_position = _target.global_position
	_halo.modulate.a = HALO_BASE_ALPHA * pulse