shader_type canvas_item;

// Subtle grimy/worn overlay for HUD meter visuals (Jul 2026 "gritty bunker"
// pass) — darkens random blotches across whatever this canvas item draws
// (draw_arc/draw_circle/draw_texture_rect all pass through COLOR here).
// Deliberately kept subtle: default strength is low so it reads as "worn
// metal", not as visual noise/static. Tune grit_strength/grit_scale per
// node via its ShaderMaterial if a specific instance needs to differ.

uniform float grit_strength : hint_range(0.0, 1.0) = 0.14;
uniform float grit_scale : hint_range(4.0, 200.0) = 26.0;

float _grit_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 c = COLOR;
	if (c.a > 0.0) {
		vec2 cell = floor(FRAGCOORD.xy / grit_scale);
		float n = _grit_hash(cell);
		c.rgb *= (1.0 - n * grit_strength);
	}
	COLOR = c;
}