// ============================================================
//  © [2025] [JoenTNT]
//  Licensed under the Apache License, Version 2.0
//  http://www.apache.org/licenses/LICENSE-2.0
// ============================================================

shader_type canvas_item;

uniform vec4 hue_color: source_color = vec4(1.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV;
    float saturation = uv.x;

    float value = 1.0 - uv.y;
    vec3 final_color = mix(vec3(1.0), hue_color.rgb, saturation) * value;

    COLOR = vec4(final_color, 1.0);
}
