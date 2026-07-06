// pause_blur.gdshader
// Simple gaussian-ish screen blur for the pause menu backdrop.
// Attach as a ShaderMaterial on a full-rect ColorRect with
// use_hdr_2d/canvas_item + SCREEN_TEXTURE — samples whatever
// was rendered behind it (the paused game world) and blurs it,
// then darkens slightly so panel text stays readable on top.
shader_type canvas_item;

uniform float blur_amount : hint_range(0.0, 12.0) = 5.0;
uniform float darken      : hint_range(0.0, 1.0)   = 0.35;

void fragment() {
	vec2 pixel_size = SCREEN_PIXEL_SIZE * blur_amount;
	vec4 sum = vec4(0.0);

	// 9-tap box blur (cheap, good enough for a paused backdrop — this does
	// not need to run every frame at full game framerate since the scene
	// behind it is static while the menu is open).
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

	vec3 darkened = sum.rgb * (1.0 - darken);
	COLOR = vec4(darkened, 1.0);
}
