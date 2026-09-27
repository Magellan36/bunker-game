shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// menu_ground.gdshader (Sep 2026): the main-menu surface terrain.
// Weaves four human-made ground sets (ambientCG, CC0; see
// assets/menu_backdrop/provenance.json) using the baked terrain's vertex
// weights (MenuTerrainBuilder: R gravel, G debris, B brick, A pad), each
// set's own height map for natural edges, and a large-scale noise so
// patches of rubble and debris wander across the open ground.
// Layers: earth = Ground067, gravel = Ground062S, debris = Ground073,
// brick = Ground111. ord textures pack R = AO, G = roughness, B = height.

uniform sampler2D earth_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_ord : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_ord : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D debris_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D debris_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D debris_ord : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D brick_ord : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Engine-generated seamless noise (NoiseTexture2D) for the weave.
uniform sampler2D weave_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

// Metres covered by one tile of each set (earth, gravel, debris, brick).
uniform vec4 tile_metres = vec4(3.4, 2.2, 2.9, 3.1);
// A second, larger sample of every set hides tiling on the open ground.
uniform float macro_ratio = 0.23;
uniform float weave_metres = 70.0;
uniform float blend_softness = 0.16;
// Grade into the storm palette: mid-dark, desaturated, faintly green-grey.
uniform float albedo_gain = 0.5;
uniform float saturation = 0.8;
uniform vec3 grade_tint : source_color = vec3(0.92, 0.95, 0.9);
// Settled ash on up-facing ground.
uniform vec3 ash_color : source_color = vec3(0.47, 0.48, 0.46);
uniform float ash_amount = 0.24;
uniform float normal_strength = 1.1;
uniform float detail_fade_start = 45.0;
uniform float detail_fade_end = 220.0;

varying vec3 v_world;
varying vec3 v_world_normal;
varying vec4 v_splat;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_splat = COLOR;
}

// One set, sampled at its own scale and at a larger macro scale.
void sample_set(sampler2D albedo_tex, sampler2D normal_tex, sampler2D ord_tex, vec2 xz,
		float tile, float macro_mix, out vec3 albedo, out vec3 nrm, out vec3 ord) {
	vec2 uv = xz / tile;
	// Rotated ~37° so the two tiling grids never line up.
	vec2 uv_macro = mat2(vec2(0.799, 0.602), vec2(-0.602, 0.799)) * xz / (tile / macro_ratio) + vec2(0.37, 0.71);
	albedo = mix(texture(albedo_tex, uv).rgb, texture(albedo_tex, uv_macro).rgb, macro_mix);
	nrm = mix(texture(normal_tex, uv).rgb, texture(normal_tex, uv_macro).rgb, macro_mix * 0.6);
	ord = mix(texture(ord_tex, uv).rgb, texture(ord_tex, uv_macro).rgb, macro_mix);
}

void fragment() {
	vec2 xz = v_world.xz;
	float weave_a = texture(weave_noise, xz / weave_metres).r;
	float weave_b = texture(weave_noise, xz / (weave_metres * 0.41) + vec2(0.5, 0.2)).r;
	float fine = texture(weave_noise, xz / 6.0).r;
	float cam_dist = length(v_world - CAMERA_POSITION_WORLD);
	float far = smoothstep(detail_fade_start, detail_fade_end, cam_dist);
	float macro_mix = mix(0.28 + 0.4 * weave_a, 0.75, far);

	vec3 a0; vec3 n0; vec3 o0;
	vec3 a1; vec3 n1; vec3 o1;
	vec3 a2; vec3 n2; vec3 o2;
	vec3 a3; vec3 n3; vec3 o3;
	sample_set(earth_albedo, earth_normal, earth_ord, xz, tile_metres.x, macro_mix, a0, n0, o0);
	sample_set(gravel_albedo, gravel_normal, gravel_ord, xz, tile_metres.y, macro_mix, a1, n1, o1);
	sample_set(debris_albedo, debris_normal, debris_ord, xz, tile_metres.z, macro_mix, a2, n2, o2);
	sample_set(brick_albedo, brick_normal, brick_ord, xz, tile_metres.w, macro_mix, a3, n3, o3);

	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	// Authored weights from the bake, then the weave: debris drifts into
	// hollows and slopes, brick rubble scatters in patches, the street's
	// gravel frays at its edges.
	vec4 w = vec4(0.55, v_splat.r, v_splat.g, v_splat.b);
	w.y *= smoothstep(0.2, 0.6, weave_b + 0.3);
	w.z = max(w.z, smoothstep(0.6, 0.78, weave_a) * 0.75);
	w.z = max(w.z, smoothstep(0.12, 0.35, slope) * 0.8);
	w.w = max(w.w, smoothstep(0.62, 0.8, weave_b) * 0.9);
	// Height-based blend: the taller surface of each set wins at the seams.
	vec4 hw = w + vec4(o0.b, o1.b, o2.b, o3.b) * 0.6;
	float top = max(max(hw.x, hw.y), max(hw.z, hw.w));
	vec4 bw = max(hw - (top - blend_softness), vec4(0.0));
	bw /= max(dot(bw, vec4(1.0)), 1e-4);

	vec3 albedo = a0 * bw.x + a1 * bw.y + a2 * bw.z + a3 * bw.w;
	vec3 nrm = n0 * bw.x + n1 * bw.y + n2 * bw.z + n3 * bw.w;
	vec3 ord = o0 * bw.x + o1 * bw.y + o2 * bw.z + o3 * bw.w;

	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	// Slow value drift across the open ground (scorch, damp, dust).
	float drift = mix(0.78, 1.12, texture(weave_noise, xz / 190.0 + vec2(0.13, 0.61)).r);
	albedo = mix(vec3(lum), albedo, saturation) * albedo_gain * grade_tint * drift;
	float ash = smoothstep(0.82, 0.98, v_world_normal.y) * smoothstep(0.35, 0.7, fine)
		* (1.0 - bw.z * 0.5) * ash_amount;
	albedo = mix(albedo, ash_color * albedo_gain * 1.4, ash);

	ALBEDO = albedo;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - far * 0.7);
	ROUGHNESS = clamp(mix(ord.g, 1.0, ash * 0.6) * 1.05, 0.0, 1.0);
	AO = ord.r;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = 0.25;
}
