// ============================================================
//  © [2025] [JoenTNT]
//  Licensed under the Apache License, Version 2.0
//  http://www.apache.org/licenses/LICENSE-2.0
// ============================================================

shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 fill_color: source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 outline_color: source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform vec2 control_size = vec2(0.0, 0.0);

uniform float outline_thickness: hint_range(0.000, 100.000) = 2.0;
uniform float radius_corner: hint_range(0.000, 100.000) = 0.0;

void fragment() {
	vec2 uv_scaled = UV * control_size;
    vec2 border_dist = min(uv_scaled, control_size - uv_scaled);
    float dist = min(border_dist.x, border_dist.y);

    vec4 tex = texture(TEXTURE, UV);

    float in_fill = step(radius_corner, dist);
    float in_outline = step(radius_corner - outline_thickness, dist) - in_fill;

    vec4 result = vec4(0.0);
    result += in_fill * fill_color;
    result += in_outline * outline_color;

    COLOR = result * tex.a;
}
