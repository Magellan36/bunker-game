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
	// Godot's CylinderMesh side-surface UV wraps U around the circumference
	// and V along the cylinder's height/length axis — confirmed by the
	// reported bug (arrows visibly rotating AROUND the pipe rather than
	// sliding along it: scrolling UV.x was scrolling around the
	// circumference, not along the pipe's length). The arrow_texture image
	// itself is drawn with its chevrons pointing along ITS OWN U axis
	// (image-x), meant to repeat/scroll along the pipe's length — so the
	// texture's U must be sampled from the mesh's V (length), and the
	// texture's V (repeat band) from the mesh's U (circumference).
	vec2 tex_uv = vec2(UV.y, UV.x);
	tex_uv.x -= TIME * scroll_speed * flow_sign;
	vec4 tex = texture(arrow_texture, tex_uv);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
