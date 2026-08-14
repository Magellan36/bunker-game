extends Node3D
class_name InteractionFocusGlow
## InteractionFocusGlow.gd  —  Sobel edge-detection outline system (Aug 2026)
## ─────────────────────────────────────────────────────────────────────────
## Full rebuild (v2) — replaces the earlier Fresnel material_overlay
## approach entirely. Screen-space Sobel edge detection over the scene's
## depth + normal-roughness buffers, masked to ONE target object via a
## dedicated silhouette pass, so only the highlighted object gets ink
## lines — not every edge on screen.
##
## WHY SOBEL, NOT FRESNEL (the structural difference, so nobody swaps it
## back thinking it's equivalent): a Fresnel rim only brightens surfaces
## at grazing angles to the camera. A front-facing corner/crease — dead-on
## to the camera, sharp edge to the human eye — has zero grazing angle
## and stays dark under Fresnel. Sobel over the NORMAL buffer catches
## exactly those interior creases; Sobel over DEPTH catches silhouettes.
## Together they produce the full "every edge gets an ink line"
## cel-shaded look (Borderlands-style) that was the actual goal.
##
## DESIGNED FOR REUSE — this is not Focus-Mode-specific. Public API is
## one method: set_target(node_or_null). Any future system (tutorials,
## quest pointers, etc.) highlights an object exactly the way Focus Mode
## does: call set_target(obj), later set_target(null). Multiple
## simultaneous highlights would need this node instanced once per
## target plus a distinct render layer each — not built yet, flagged in
## docs as the known extension point.
##
## HOW THE MASK WORKS (the per-object isolation pass): target meshes get
## render layer HIGHLIGHT_LAYER *added* to their `layers` bitmask
## (originals saved/restored — additive, main camera view unaffected). A
## SubViewport camera that copies the main camera every frame, cull_mask
## = only that layer, renders the target's silhouette alone. The Sobel
## shader multiplies its edge signal by that mask (slightly dilated so
## boundary edges aren't clipped), restricting lines to the one target.
##
## Requires Forward+ (this project: Godot 4.6 Forward Plus, confirmed) —
## hint_normal_roughness_texture is Forward+-only. If the project ever
## moves to Mobile/Compatibility rendering, the normal half of the edge
## signal goes dark and this needs revisiting.

const HIGHLIGHT_LAYER: int = 11            ## render layer for the mask pass —
                                            ## confirmed unused project-wide (Aug 2026)
const HIGHLIGHT_LAYER_BIT: int = 1 << (HIGHLIGHT_LAYER - 1)

## Aug 2026 — objects in this group get an opaque stand-in duplicate
## spawned (mask-viewport-only, see _spawn_stand_ins()) because their
## real material is alpha-transparent and writes no depth/normal data
## for the main Sobel pass to detect. WaterCase.gd is the first/only
## member; add more items here the same way if the same problem shows
## up elsewhere.
const TRANSLUCENT_FIX_GROUP: String = "outline_needs_opaque_stand_in"

const PULSE_SPEED:     float = 2.0
const PULSE_AMPLITUDE: float = 0.22
const OUTLINE_BASE_STRENGTH: float = 0.85  ## drives the shader's outline_strength uniform
const EMISSION_BOOST: float = 3.0          ## pushes line pixels past glow_hdr_threshold
                                            ## (1.4, MainWorld.tscn) for the soft bloom halo

var _target: Node3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _saved_layers: Dictionary = {}          ## MeshInstance3D -> original layers bitmask

var _stand_ins: Array[MeshInstance3D] = []          ## opaque duplicates, layer 11 ONLY
var _stand_in_sources: Array[MeshInstance3D] = []   ## parallel array — real mesh each mirrors
var _stand_in_material: StandardMaterial3D = null

var _mask_viewport: SubViewport = null
var _mask_camera: Camera3D = null
var _main_camera: Camera3D = null
var _quad: MeshInstance3D = null
var _outline_material: ShaderMaterial = null
var _pulse_time: float = 0.0

func _ready() -> void:
	_main_camera = get_viewport().get_camera_3d()

	## Aug 2026 — exclude the mask layer from the MAIN camera so opaque
	## stand-ins (spawned for TRANSLUCENT_FIX_GROUP targets — see
	## _spawn_stand_ins()) never double-render in the real game view.
	## Computed via bitwise clear, not a hardcoded mask value. Real mesh
	## instances stay visible as normal — they're still on layer 1 too,
	## which this doesn't touch; only layer-11-EXCLUSIVE nodes (i.e. only
	## the new stand-ins) are affected.
	if _main_camera != null:
		_main_camera.cull_mask = _main_camera.cull_mask & ~HIGHLIGHT_LAYER_BIT

	_stand_in_material = StandardMaterial3D.new()
	_stand_in_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stand_in_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_stand_in_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	_mask_viewport = SubViewport.new()
	_mask_viewport.transparent_bg = true
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	## own_world_3d stays false (default) — the mask camera renders THIS
	## scene's world, filtered by cull_mask, which is the whole point.
	add_child(_mask_viewport)

	_mask_camera = Camera3D.new()
	_mask_camera.cull_mask = HIGHLIGHT_LAYER_BIT
	_mask_viewport.add_child(_mask_camera)

	_outline_material = _build_outline_material()

	## Fullscreen clip-space quad — standard Godot 4 technique: the vertex
	## shader writes POSITION directly, so the mesh's own transform is
	## irrelevant; parking it under this node keeps the scene tree tidy.
	_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	_quad.mesh = qm
	_quad.material_override = _outline_material
	## Never frustum-culled — its true screen coverage isn't knowable
	## from its 3D AABB since the vertex shader ignores the transform.
	_quad.extra_cull_margin = 16384.0
	_quad.visible = false
	add_child(_quad)

	_sync_mask_viewport_size()
	get_viewport().size_changed.connect(_sync_mask_viewport_size)

func _sync_mask_viewport_size() -> void:
	_mask_viewport.size = get_viewport().get_visible_rect().size

func _build_outline_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform sampler2D mask_tex : filter_linear;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_strength : hint_range(0.0, 1.5) = 0.85;
uniform float emission_boost = 3.0;
uniform float depth_edge_threshold : hint_range(0.0, 0.2) = 0.03;
uniform float normal_edge_threshold : hint_range(0.0, 2.0) = 0.55;

// Linearize depth so edge thresholds behave consistently near and far.
float linear_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return -(view.xyz / view.w).z;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;

	// ── Mask gate (dilated): 3x3 max — cheap early-out when the pixel
	// is nowhere near the target's silhouette.
	float mask = 0.0;
	for (int mx = -1; mx <= 1; mx++) {
		for (int my = -1; my <= 1; my++) {
			mask = max(mask, texture(mask_tex, SCREEN_UV + vec2(float(mx), float(my)) * px).a);
		}
	}
	if (mask < 0.01) {
		ALPHA = 0.0;
	} else {
		// ── Sobel kernels over depth (linearized) and normals.
		// Offsets:  tl t tr / l c r / bl b br
		float dtl = linear_depth(SCREEN_UV + vec2(-1.0, -1.0) * px, INV_PROJECTION_MATRIX);
		float dt  = linear_depth(SCREEN_UV + vec2( 0.0, -1.0) * px, INV_PROJECTION_MATRIX);
		float dtr = linear_depth(SCREEN_UV + vec2( 1.0, -1.0) * px, INV_PROJECTION_MATRIX);
		float dl  = linear_depth(SCREEN_UV + vec2(-1.0,  0.0) * px, INV_PROJECTION_MATRIX);
		float dr  = linear_depth(SCREEN_UV + vec2( 1.0,  0.0) * px, INV_PROJECTION_MATRIX);
		float dbl = linear_depth(SCREEN_UV + vec2(-1.0,  1.0) * px, INV_PROJECTION_MATRIX);
		float db  = linear_depth(SCREEN_UV + vec2( 0.0,  1.0) * px, INV_PROJECTION_MATRIX);
		float dbr = linear_depth(SCREEN_UV + vec2( 1.0,  1.0) * px, INV_PROJECTION_MATRIX);

		float dgx = (dtr + 2.0 * dr + dbr) - (dtl + 2.0 * dl + dbl);
		float dgy = (dbl + 2.0 * db + dbr) - (dtl + 2.0 * dt + dtr);
		// Scale-normalize by center depth so far objects don't over-edge.
		float dc = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
		float depth_edge = length(vec2(dgx, dgy)) / max(dc, 0.05);

		vec3 ntl = texture(normal_tex, SCREEN_UV + vec2(-1.0, -1.0) * px).rgb;
		vec3 nt  = texture(normal_tex, SCREEN_UV + vec2( 0.0, -1.0) * px).rgb;
		vec3 ntr = texture(normal_tex, SCREEN_UV + vec2( 1.0, -1.0) * px).rgb;
		vec3 nl  = texture(normal_tex, SCREEN_UV + vec2(-1.0,  0.0) * px).rgb;
		vec3 nr  = texture(normal_tex, SCREEN_UV + vec2( 1.0,  0.0) * px).rgb;
		vec3 nbl = texture(normal_tex, SCREEN_UV + vec2(-1.0,  1.0) * px).rgb;
		vec3 nb  = texture(normal_tex, SCREEN_UV + vec2( 0.0,  1.0) * px).rgb;
		vec3 nbr = texture(normal_tex, SCREEN_UV + vec2( 1.0,  1.0) * px).rgb;

		vec3 ngx = (ntr + 2.0 * nr + nbr) - (ntl + 2.0 * nl + nbl);
		vec3 ngy = (nbl + 2.0 * nb + nbr) - (ntl + 2.0 * nt + ntr);
		float normal_edge = length(ngx) + length(ngy);

		float edge = 0.0;
		edge = max(edge, step(depth_edge_threshold, depth_edge));
		edge = max(edge, step(normal_edge_threshold, normal_edge));

		// Silhouette edge derived from the MASK's own alpha, independent
		// of depth/normal — the only signal available for translucent
		// targets (alpha-blended materials render into the mask
		// viewport's color output normally, they just don't write
		// depth/normal). Redundant with the depth-based silhouette edge
		// for ordinary opaque objects (same result, no visible change);
		// the deciding signal for TRANSLUCENT_FIX_GROUP targets.
		float mask_c = texture(mask_tex, SCREEN_UV).a;
		float mask_edge = 0.0;
		for (int mx = -1; mx <= 1; mx++) {
			for (int my = -1; my <= 1; my++) {
				if (mx == 0 && my == 0) continue;
				float mn = texture(mask_tex, SCREEN_UV + vec2(float(mx), float(my)) * px * 1.5).a;
				mask_edge = max(mask_edge, abs(mask_c - mn));
			}
		}
		edge = max(edge, step(0.25, mask_edge));

		float line = edge * mask * outline_strength;
		ALBEDO = line_color.rgb;
		ALPHA = line;
		EMISSION = line_color.rgb * line * emission_boost;
	}
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

## ── Public API — unchanged signature, reusable by any system ─────────────────
func set_target(node: Node3D) -> void:
	if node == _target:
		return
	_clear_current_target()
	_target = node
	if _target != null and is_instance_valid(_target):
		_mesh_instances = _find_mesh_instances(_target)
		for mi: MeshInstance3D in _mesh_instances:
			_saved_layers[mi] = mi.layers
			mi.layers = mi.layers | HIGHLIGHT_LAYER_BIT
		if _target.is_in_group(TRANSLUCENT_FIX_GROUP):
			_spawn_stand_ins()
		_quad.visible = true
	else:
		_target = null

## Aug 2026 — see TRANSLUCENT_FIX_GROUP's own comment. Spawns an
## always-opaque duplicate of each real mesh instance, sharing the SAME
## mesh resource (no geometry copy — cheap), tagged layer 11 ONLY so
## only the mask camera ever sees them (main camera excludes layer 11,
## see _ready()). Gives the mask viewport genuine solid silhouette data
## regardless of the real object's own material transparency.
func _spawn_stand_ins() -> void:
	for mi: MeshInstance3D in _mesh_instances:
		if mi.mesh == null:
			continue
		var stand_in := MeshInstance3D.new()
		stand_in.mesh = mi.mesh
		stand_in.material_override = _stand_in_material
		stand_in.layers = HIGHLIGHT_LAYER_BIT
		stand_in.global_transform = mi.global_transform
		add_child(stand_in)
		_stand_ins.append(stand_in)
		_stand_in_sources.append(mi)

func _clear_current_target() -> void:
	for mi: MeshInstance3D in _mesh_instances:
		if is_instance_valid(mi) and _saved_layers.has(mi):
			mi.layers = _saved_layers[mi]
	_mesh_instances.clear()
	_saved_layers.clear()
	for si: MeshInstance3D in _stand_ins:
		if is_instance_valid(si):
			si.queue_free()
	_stand_ins.clear()
	_stand_in_sources.clear()
	_quad.visible = false

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			result.append(child as MeshInstance3D)
		result.append_array(_find_mesh_instances(child))
	return result

func _process(delta: float) -> void:
	## Defensive: target freed externally without set_target(null) —
	## self-heal, same discipline as everywhere else in this system.
	if _target != null and not is_instance_valid(_target):
		_mesh_instances = _mesh_instances.filter(
			func(mi: MeshInstance3D) -> bool: return is_instance_valid(mi))
		_clear_current_target()
		_target = null

	if _target == null:
		return

	## Stand-ins track their real source mesh every frame — handles the
	## target moving/rotating while highlighted (e.g. picked up).
	for i in _stand_ins.size():
		if is_instance_valid(_stand_ins[i]) and is_instance_valid(_stand_in_sources[i]):
			_stand_ins[i].global_transform = _stand_in_sources[i].global_transform

	## Mask camera mirrors the main camera exactly, every frame.
	if _main_camera == null or not is_instance_valid(_main_camera):
		_main_camera = get_viewport().get_camera_3d()
	if _main_camera != null:
		_mask_camera.global_transform = _main_camera.global_transform
		_mask_camera.fov  = _main_camera.fov
		_mask_camera.near = _main_camera.near
		_mask_camera.far  = _main_camera.far

	## Bind the mask texture every frame it's active (cheap — it's a
	## reference, not a copy; rebinding avoids any staleness after
	## viewport resizes).
	_outline_material.set_shader_parameter("mask_tex", _mask_viewport.get_texture())

	_pulse_time += delta
	var pulse: float = 1.0 + sin(_pulse_time * PULSE_SPEED) * PULSE_AMPLITUDE
	_outline_material.set_shader_parameter("outline_strength", OUTLINE_BASE_STRENGTH * pulse)
	_outline_material.set_shader_parameter("emission_boost", EMISSION_BOOST)