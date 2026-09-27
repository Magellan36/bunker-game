// surface_feed_grain.gdshader (Sep 2026)
// Main-menu "surface feed" treatment over the 3D backdrop only (the menu text
// sits above it and stays crisp): animated luminance grain stepped at a film
// frame rate, plus a soft edge vignette. Set `animate` false for reduced motion.
shader_type canvas_item;

uniform float grain_amount : hint_range(0.0, 0.3) = 0.05;
uniform float grain_fps : hint_range(1.0, 60.0) = 24.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float vignette_radius : hint_range(0.0, 1.5) = 0.55;
uniform bool animate = true;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float frame = animate ? floor(TIME * grain_fps) : 0.0;
	float n = hash(FRAGCOORD.xy + frame * 91.7) - 0.5;
	vec2 d = UV - vec2(0.5);
	float edge = smoothstep(vignette_radius, 1.05, length(d * vec2(1.0, 1.25)));
	float shade = edge * vignette_strength;
	// Target = dst * (1 - shade) * (1 - G) + tint * G, expressed as one
	// premultiplied-equivalent mix: grain lightens or darkens, vignette darkens.
	float g = n * grain_amount;
	float G = abs(g) * 2.0;
	vec3 tint = g > 0.0 ? vec3(1.0) : vec3(0.0);
	float a = 1.0 - (1.0 - shade) * (1.0 - G);
	COLOR = vec4(tint * G / max(a, 1e-4), a);
}
