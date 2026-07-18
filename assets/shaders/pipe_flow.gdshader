shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

// pipe_flow.gdshader — build-mode-only scrolling arrow overlay for water
// pipes (Jul 2026). This project's first spatial shader (the only prior
// custom shader, vignette.gdshader, is canvas_item) — kept deliberately
// simple, new ground. Applied as a SECOND, additive overlay MeshInstance3D
// on WaterPipeSegment, never replacing the pipe's own always-visible solid
// material — see WaterPipeSegment.gd's own header on why pipes stay visible
// outside build mode (forbidden to touch that).

uniform sampler2D arrow_texture : source_color, filter_linear, repeat_enable;
uniform float scroll_speed : hint_range(0.0, 5.0) = 1.0;
uniform float flow_sign : hint_range(-1.0, 1.0) = 1.0;   // set per-segment from
                                                          // WaterPipeSegment.set_flow_sign()
uniform bool build_mode_visible = false;   // toggled per-segment, not a global setting

void fragment() {
	if (!build_mode_visible) {
		discard;
	}
	vec2 scrolled_uv = UV;
	scrolled_uv.x -= TIME * scroll_speed * flow_sign;
	vec4 tex = texture(arrow_texture, scrolled_uv);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
