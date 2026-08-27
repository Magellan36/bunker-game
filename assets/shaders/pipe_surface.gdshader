shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Plain matte pipe surface (Aug 2026). Replaces the old StandardMaterial3D so
// the pipe can:
//   1) tile the albedo via world-space TRIPLANAR at a fixed density — no
//      stretching on arbitrarily-long segments (same approach as
//      BuildMaterials' walls/floor),
//   2) break up the repeating tile grid with aperiodic world-space grime
//      (value-noise darkening), and
//   3) stagger per segment via `phase`, so each leg tiles out of phase with
//      its neighbours instead of looking like the same texture every time.
// `tint`/`emission` replicate the old StandardMaterial3D delete-highlight so
// deconstruct hover still works (resting tint = COLOR_PIPE, hover = red).

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_enable;
uniform float tile_scale : hint_range(0.01, 1.0) = 0.083;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.2;
uniform vec3 phase = vec3(0.0);
uniform vec3 grime_color : source_color = vec3(0.07, 0.06, 0.05);
uniform float grime_strength : hint_range(0.0, 1.0) = 0.35;
uniform float grime_scale : hint_range(0.5, 8.0) = 3.0;
uniform vec3 tint : source_color = vec3(0.45, 0.47, 0.49);
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy : hint_range(0.0, 4.0) = 0.0;

float _hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float _vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = _hash3(i);
	float n100 = _hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = _hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = _hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = _hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = _hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = _hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = _hash3(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
	           mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float _fbm(vec3 p) {
	return _vnoise(p) * 0.6 + _vnoise(p * 2.0) * 0.25 + _vnoise(p * 4.0) * 0.15;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_norm = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Triplanar albedo sampling at a fixed world-space density.
	vec3 tp = world_pos * tile_scale + phase;
	vec3 n = abs(world_norm);
	vec3 blend = pow(n, vec3(4.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	vec3 col = texture(albedo_tex, tp.yz).rgb * blend.x
	         + texture(albedo_tex, tp.xz).rgb * blend.y
	         + texture(albedo_tex, tp.xy).rgb * blend.z;

	// Aperiodic grime overlay to break up the tile repetition.
	float g = _fbm(world_pos * grime_scale + phase * 3.0);
	col = mix(col, col * grime_color, grime_strength * g);

	ALBEDO = col * tint;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission * emission_energy;
}