// ============================================================
//  © [2025] [JoenTNT]
//  Licensed under the Apache License, Version 2.0
//  http://www.apache.org/licenses/LICENSE-2.0
// ============================================================

shader_type canvas_item;

const float COLOR_COUNT = 6.0;

uniform float horizontal_mode : hint_range(0, 1, 1.0) = 0.0;

uniform vec4 RED_COLOR: source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 YELLOW_COLOR: source_color = vec4(1.0, 1.0, 0.0, 1.0);
uniform vec4 GREEN_COLOR: source_color = vec4(0.0, 1.0, 0.0, 1.0);
uniform vec4 CYAN_COLOR: source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform vec4 BLUE_COLOR: source_color = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 MAGENTA_COLOR: source_color = vec4(1.0, 0.0, 1.0, 1.0);

uniform float offset_y = 0.0;

void fragment() {
	vec2 uv = UV;
	vec4 color = COLOR;
	float hue;
	vec3 result_color;
	
	if (horizontal_mode > 0.5) {
		hue = mod(uv.x + offset_y, 1.0)* COLOR_COUNT;
		if (hue < 1.0)
			result_color = mix(RED_COLOR.rgb, YELLOW_COLOR.rgb, hue);
		else if (hue < 2.0)
			result_color = mix(YELLOW_COLOR.rgb, GREEN_COLOR.rgb, hue - 1.0);
		else if (hue < 3.0)
			result_color = mix(GREEN_COLOR.rgb, CYAN_COLOR.rgb, hue - 2.0);
		else if (hue < 4.0)
			result_color = mix(CYAN_COLOR.rgb, BLUE_COLOR.rgb, hue - 3.0);
		else if (hue < 5.0)
			result_color = mix(BLUE_COLOR.rgb, MAGENTA_COLOR.rgb, hue - 4.0);
		else
			result_color = mix(MAGENTA_COLOR.rgb, RED_COLOR.rgb, hue - 5.0);
	} else {
		hue = mod(uv.y + offset_y, 1.0)* COLOR_COUNT;
		if (hue < 1.0)
			result_color = mix(RED_COLOR.rgb, YELLOW_COLOR.rgb, hue);
		else if (hue < 2.0)
			result_color = mix(YELLOW_COLOR.rgb, GREEN_COLOR.rgb, hue - 1.0);
		else if (hue < 3.0)
			result_color = mix(GREEN_COLOR.rgb, CYAN_COLOR.rgb, hue - 2.0);
		else if (hue < 4.0)
			result_color = mix(CYAN_COLOR.rgb, BLUE_COLOR.rgb, hue - 3.0);
		else if (hue < 5.0)
			result_color = mix(BLUE_COLOR.rgb, MAGENTA_COLOR.rgb, hue - 4.0);
		else
			result_color = mix(MAGENTA_COLOR.rgb, RED_COLOR.rgb, hue - 5.0);
	}
	
	COLOR = vec4(result_color, 1.0) * color;
}
