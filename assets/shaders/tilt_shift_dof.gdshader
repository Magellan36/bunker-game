// tilt_shift_dof.gdshader
// Screen-space tilt-shift depth-of-field for the fixed-pitch isometric
// camera. Keeps a horizontal "focus band" of the screen sharp and blurs
// everything above it (ceiling/back-wall) and below it (foreground edge),
// independent of 3D depth — see GameCamera.gd / TiltShiftDOF.gd and
// docs/systems/graphics/README.md for why point/distance-based DOF doesn't
// work for this camera angle.
shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// Vertical screen position (0 = top, 1 = bottom) of the sharp band's center.
uniform float focus_center_y : hint_range(0.0, 1.0) = 0.55;
// Half-height (screen-UV units) of the fully-sharp band around focus_center_y.
uniform float focus_band_half_height : hint_range(0.0, 0.5) = 0.16;
// Screen-UV distance beyond the sharp band it takes to reach max_blur_px —
// a soft ramp, not a hard cutoff.
uniform float transition_height : hint_range(0.01, 0.5) = 0.22;
// Max blur radius in resolution-independent virtual pixels at the screen
// top/bottom edges.
uniform float max_blur_px : hint_range(0.0, 16.0) = 6.0;
// Master multiplier — GameCamera.gd drives this to 0.0 to fully disable
// (build mode / GraphicsSettings.dof_enabled == false) without touching
// node visibility.
uniform float strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float dist = max(0.0, abs(SCREEN_UV.y - focus_center_y) - focus_band_half_height);
	float t = smoothstep(0.0, transition_height, dist);
	float blur_px = t * max_blur_px * strength;

	if (blur_px < 0.05) {
		COLOR = texture(SCREEN_TEXTURE, SCREEN_UV);
	} else {
		vec2 pixel_size = SCREEN_PIXEL_SIZE * blur_px;
		vec4 sum = vec4(0.0);
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(-pixel_size.x, -pixel_size.y));
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2( 0.0,          -pixel_size.y));
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2( pixel_size.x, -pixel_size.y));
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(-pixel_size.x,  0.0));
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2( 0.0,           0.0));
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2( pixel_size.x,  0.0));
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(-pixel_size.x,  pixel_size.y));
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2( 0.0,           pixel_size.y));
		sum += texture(SCREEN_TEXTURE, SCREEN_UV + vec2( pixel_size.x,  pixel_size.y));
		sum /= 9.0;

		COLOR = sum;
	}
}