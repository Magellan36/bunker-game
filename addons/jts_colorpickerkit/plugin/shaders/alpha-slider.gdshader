// ============================================================
//  © [2025] [JoenTNT]
//  Licensed under the Apache License, Version 2.0
//  http://www.apache.org/licenses/LICENSE-2.0
// ============================================================

shader_type canvas_item;

const vec4 ZERO_COLOR = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 ONE_COLOR = vec4(1.0, 1.0, 1.0, 1.0);

uniform vec4 lighter_trans: source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 darker_trans: source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform vec2 image_ratio = vec2(30.0, 164.0);
uniform float fixed_scale = 16.0;

void fragment() {
	vec2 uv = UV * image_ratio;
	float alpha_y = 1.0 - uv.y / image_ratio.y;
	vec4 color = COLOR;
	color.a = alpha_y;

	vec2 check = floor(uv * fixed_scale);
	float checker = mod(check.x + check.y, 2.0);
	
	vec4 background = mix(darker_trans, lighter_trans, checker);
	vec4 result_color = mix(background, color, color.a);
	if (result_color.a < 1.0) result_color.a = 1.0;
	COLOR = result_color;
}
