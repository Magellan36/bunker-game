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

// ─── World-space uniform arrow scale/speed + cross-joint phase (Jul 2026) ───
// CylinderMesh's V axis always spans exactly 0->1 across the WHOLE segment
// regardless of its real length, so without correction the arrow pattern
// gets stretched to fit once per segment (short pipe = compressed pattern,
// long pipe = stretched pattern) and a fixed UV-rate scroll therefore covers
// more physical distance/sec on longer pipes (visibly faster). Fix: scale
// tex_uv.x by this segment's own real length ÷ the desired world-units per
// arrow tile BEFORE scrolling, so tile size and scroll speed are constant in
// world-space on every pipe regardless of length.
uniform float pipe_length : hint_range(0.01, 100.0) = 1.0;   // this segment's real length (m),
                                                              // set from WaterPipeSegment._build_arrow_overlay()
uniform float tile_world_length : hint_range(0.05, 5.0) = 0.4;   // desired world-units per arrow tile

// Local per-segment UV starting at 0 caused a phase discontinuity at every
// joint (arrows visibly "restarting" segment to segment instead of flowing
// through). phase_offset is each segment's upstream endpoint's cumulative
// REAL-WORLD distance from the hookup (in world units, from
// WaterGraph.compute_flow_directions()), converted to UV tiles here the
// same way pipe_length is — this keeps the scrolling texture's phase
// continuous node-to-node instead of resetting per segment.
uniform float phase_offset : hint_range(0.0, 10000.0) = 0.0;   // world units, set from
                                                                // WaterPipeSegment.set_phase_offset()

// Water only actually flows through a pipe run that's reachable from a
// hookup (see WaterManager.recompute_flow_directions()'s July 2026 update —
// segments NOT present in WaterGraph.compute_flow_directions()'s result for
// the live hookup are, by definition, disconnected: no water, so no arrows
// at all rather than an arrow animation implying flow that isn't there).
uniform bool has_flow = false;   // set from WaterPipeSegment.set_has_flow()

void fragment() {
	if (!build_mode_visible || !has_flow) {
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

	// The arrow texture's chevrons are baked pointing in a single fixed
	// direction along +U (confirmed against assets/textures/water/
	// pipe_flow_arrow.png). Originally only the SCROLL direction flipped
	// with flow_sign, which just made the glyphs slide backwards while
	// still visibly pointing the old way — wrong the moment flow reverses.
	// Mirroring the raw length-axis UV around the segment's own midpoint
	// when flow_sign is negative flips the chevron shape itself (">" becomes
	// "<"), so the arrows always visually point the way the water is
	// actually moving, not just animate in that direction.
	float raw_uv = tex_uv.x;
	if (flow_sign < 0.0) {
		raw_uv = 1.0 - raw_uv;
	}

	// Rescale the length-axis UV from "0..1 across this whole segment" to
	// "0..(real world tiles across this segment)" so tile size is constant
	// in world-space regardless of segment length, then add this segment's
	// phase offset (also in tile units) so the pattern continues seamlessly
	// from the upstream joint instead of restarting at 0.
	float tiles_per_segment = pipe_length / tile_world_length;
	float phase_tiles = phase_offset / tile_world_length;
	tex_uv.x = raw_uv * tiles_per_segment + phase_tiles;

	// Scroll at a constant world-units/sec rate (scroll_speed is world-units/sec,
	// converted to tile units the same way) rather than a fixed UV-rate, so
	// scroll speed is also constant in world-space across all pipe lengths.
	// flow_sign here flips the direction of APPARENT MOTION to match the
	// mirrored glyph above (both must flip together or the arrows point one
	// way but visibly crawl the other).
	tex_uv.x -= TIME * (scroll_speed / tile_world_length) * flow_sign;

	vec4 tex = texture(arrow_texture, tex_uv);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
