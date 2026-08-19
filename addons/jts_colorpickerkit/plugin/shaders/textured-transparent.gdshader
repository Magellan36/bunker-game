// ============================================================
//  © [2025] [JoenTNT]
//  Licensed under the Apache License, Version 2.0
//  http://www.apache.org/licenses/LICENSE-2.0
// ============================================================

shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec4 lighter_trans: source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 darker_trans: source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform vec2 image_size = vec2(1.0, 1.0);
uniform float fixed_scale = 1.0;
uniform float max_length = 16;

void fragment() {
	float fixed_x_img_size = mod(image_size.x, max_length);
	float fixed_y_img_size = mod(image_size.y, max_length);

	vec2 uv = UV * fixed_scale;
	vec4 color = COLOR;
	vec2 check = floor(uv);
	float checker = mod(check.x + check.y, 2.0);

	vec4 background = mix(darker_trans, lighter_trans, checker);
    vec4 result = mix(background, color, color.a);
	if (result.a < 1.0) result.a = 1.0;
    COLOR = result;
}
