extends Node3D
class_name InteractionFocusGlow
## InteractionFocusGlow.gd  —  Focus Mode target highlight (Aug 2026)
## ─────────────────────────────────────────────────────────────────────────
## Rim-light outline + real bloom (native, from the rim shader's own
## HDR emission) on whatever object Focus Mode (hold Ctrl)
## is currently highlighting. Driven by InteractionSystem calling
## set_target(node_or_null) once per _update_prompt() call — this node
## owns its own _process() for the pulse/position animation, so it stays
## correct regardless of exactly how often the caller updates the target.
##
## Rim outline + real bloom, both from ONE shader, no extra node needed.
## A single shared Fresnel ShaderMaterial applied via
## GeometryInstance3D.material_overlay to every MeshInstance3D found
## (recursively) under the target. This is an EXTRA render pass on top of
## each mesh's existing material — nothing about the target's own
## appearance, material, or geometry is touched or duplicated, which is
## what makes this safe to apply to any object regardless of how its mesh
## was authored (procedural primitives, GLB imports, multi-part
## assemblies like Can Case's dozen individual can visuals).
##
## Aug 2026 — the "glow around the object" is no longer a separate
## Sprite3D (removed — read as a flat, same-shape-for-everything decal
## stamped at the object's center, not an actual glow). Instead, the
## rim shader outputs bright HDR EMISSION at the same fresnel-masked
## edges as the outline itself — this project's WorldEnvironment
## (scenes/world/MainWorld.tscn) already has real bloom active
## (glow_hdr_threshold = 1.4), so once the edge pixels cross that
## threshold, Godot's own renderer generates the surrounding glow
## automatically, following the object's ACTUAL silhouette rather than
## a fixed circular shape. Tuned tight/contained (steep rim_power,
## modest emission boost) rather than a wide atmospheric bleed.
##
## Defensively coded against a freed target — is_instance_valid() checked
## every frame before touching the target or any mesh instance under it;
## clearing state on invalidity rather than assuming set_target(null)
## will always be called first (a target can be picked up, stored, or
## otherwise removed out from under Focus Mode mid-highlight).

const PULSE_SPEED:     float = 2.0    ## radians/sec — one full breath ~3.1s
const PULSE_AMPLITUDE: float = 0.22   ## +/-22% — "slightly more intense"
const RIM_BASE_INTENSITY: float = 0.75   ## drives the shader's rim_intensity uniform —
                                          ## controls BOTH the outline's own opacity and,
                                          ## via the shader's internal EMISSION_BOOST, how
                                          ## far past the scene's glow threshold it pushes

var _target: Node3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _rim_material: ShaderMaterial = null
var _pulse_time: float = 0.0

func _ready() -> void:
	_rim_material = _build_rim_material()

## Fresnel-masked outline (ALPHA, unchanged technique from the prior fix)
## PLUS HDR EMISSION at the same masked edges, scaled by a fixed internal
## boost so it clears the scene's glow_hdr_threshold (1.4) with headroom
## for the pulse, without being pushed so high the bloom spreads wide.
## EMISSION_BOOST tuned for "tight/contained" per direct instruction —
## raise it in-editor if a wider atmospheric bleed is wanted later.
func _build_rim_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled;

uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 12.0) = 5.0;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.75;

const float EMISSION_BOOST = 3.0;   // tight/contained — clears glow_hdr_threshold
                                     // (1.4) with modest headroom, not blown out wide

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = rim_color.rgb;
	ALPHA = fresnel * rim_intensity;
	EMISSION = rim_color.rgb * fresnel * rim_intensity * EMISSION_BOOST;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

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
		return

	_pulse_time += delta
	var pulse: float = 1.0 + sin(_pulse_time * PULSE_SPEED) * PULSE_AMPLITUDE

	## Single value now drives both the outline's own visibility AND
	## (via the shader's fixed EMISSION_BOOST) how far past the glow
	## threshold the edges push — outline and bloom pulse together as
	## one cohesive effect instead of two separately-tuned pieces.
	_rim_material.set_shader_parameter("rim_intensity", RIM_BASE_INTENSITY * pulse)