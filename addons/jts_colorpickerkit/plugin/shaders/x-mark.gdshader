// ============================================================
//  © [2025] [JoenTNT]
//  Licensed under the Apache License, Version 2.0
//  http://www.apache.org/licenses/LICENSE-2.0
// ============================================================

shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float thickness : hint_range(0.001, 1.000) = 0.1;
uniform float smoothness : hint_range(0.000, 1.000) = 0.02;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;

    float line1 = abs(uv.x - uv.y);
    float line2 = abs(uv.x + uv.y);
    float xShape = min(line1, line2);

    float alpha = smoothstep(thickness + smoothness, thickness - smoothness, xShape);
    vec3 xColor = COLOR.rgb;
    vec3 bgColor = vec3(0.0);

    vec3 finalColor = mix(bgColor, xColor, alpha);
    COLOR = vec4(finalColor, alpha * COLOR.a);
}
