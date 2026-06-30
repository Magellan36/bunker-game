// vignette.gdshader
// Soft radial vignette — dark/red edges, transparent center.
// Attach as a ShaderMaterial on the CriticalVignette ColorRect.
shader_type canvas_item;

uniform vec4 vignette_color : source_color = vec4(0.6, 0.0, 0.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.5;
uniform float radius   : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	vec2 uv     = UV - vec2(0.5);
	float dist  = length(uv * vec2(1.0, 1.2));   // Slight vertical squish
	float edge  = smoothstep(radius, 1.0, dist);
	float alpha = edge * strength;
	COLOR = vec4(vignette_color.rgb, alpha);
}
