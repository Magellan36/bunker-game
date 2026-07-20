shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

// pipe_flow.gdshader — build-mode-only scrolling arrow overlay for water
// pipes (Jul 2026). Applied as a SECOND, additive overlay MeshInstance3D on
// WaterPipeSegment, never replacing the pipe's own always-visible solid
// material — see WaterPipeSegment.gd's own header on why pipes stay visible
// outside build mode (forbidden to touch that).

uniform sampler2D arrow_texture : source_color, filter_linear, repeat_enable;
uniform float scroll_speed : hint_range(0.0, 5.0) = 1.0;
uniform float flow_sign : hint_range(-1.0, 1.0) = 1.0;   // >0 = point_a is this
                                                          // edge's upstream side,
                                                          // <0 = point_b is (set
                                                          // from WaterPipeSegment.
                                                          // set_flow_sign()).
uniform bool build_mode_visible = false;   // toggled per-segment, not a global setting

// ─── World-space uniform arrow scale/speed + cross-joint phase (Jul 2026) ───
// A fixed UV-rate scroll covers more physical distance/sec on longer pipes
// (visibly faster) and stretches the tile pattern to fit once per segment
// regardless of real length. Fix: rescale by this segment's own real length
// so tile size and scroll speed are constant in world-space on every pipe.
uniform float pipe_length : hint_range(0.01, 100.0) = 1.0;   // this segment's real length (m),
                                                              // set from WaterPipeSegment._build_arrow_overlay()
uniform float tile_world_length : hint_range(0.05, 5.0) = 0.4;   // desired world-units per arrow tile

// phase_offset is each segment's upstream endpoint's cumulative REAL-WORLD
// distance from the hookup (world units, from WaterGraph.
// compute_flow_directions()), converted to tile units below the same way
// pipe_length is — keeps the scrolling texture's phase continuous
// node-to-node instead of resetting per segment.
uniform float phase_offset : hint_range(0.0, 10000.0) = 0.0;   // world units, set from
                                                                // WaterPipeSegment.set_phase_offset()

// Water only actually flows through a pipe run that's reachable from a
// hookup. Segments NOT present in WaterGraph.compute_flow_directions()'s
// result for the live hookup are, by definition, disconnected: no water, so
// no arrows at all rather than an arrow animation implying flow that isn't
// there.
uniform bool has_flow = false;   // set from WaterPipeSegment.set_has_flow()

// ─── Cross-joint continuity fix (Jul 2026) ──────────────────────────────────
// PRIOR bug: the fragment-only version of this shader derived its "position
// along the pipe" coordinate from UV.y (the mesh's own side-surface V axis)
// and fixed chevron direction by mirroring that coordinate (1.0 - UV.y)
// around EACH SEGMENT'S OWN midpoint whenever flow_sign was negative. That
// mirror is segment-local — it pivots around 0.5 of THIS segment alone — so
// the coordinate that phase_offset/tiles_per_segment scaled was NOT the same
// "0 at upstream" coordinate the phase math assumed for every segment
// uniformly. Each segment's own tile pattern was internally consistent
// (looked fluid in isolation) but didn't line up with its neighbor's phase
// at the shared joint — every joint was a silent seam, which reads exactly
// as "each segment plays its own separate looping animation" instead of one
// continuous crawl (reported July 2026).
//
// FIX: build the upstream->downstream coordinate from VERTEX space instead
// of UV, ONCE, before any scaling — WaterPipeSegment._rebuild_mesh()'s
// look_at() + fixed 90-degree local-X rotation setup always orients the
// cylinder's local +Y axis toward point_b (provable directly from that fixed
// rotation composition, independent of the segment's world orientation), so
// VERTEX.y/pipe_length + 0.5 is 0 at point_a and 1 at point_b for every
// segment uniformly. Normalizing that ONE coordinate against flow_sign
// (still exactly the same "a_is_upstream" flag WaterPipeSegment.
// set_flow_sign() already sends) gives a single along-flow coordinate that
// drives tiling, phase, scroll AND chevron direction all together — no
// separate mirror step left to fall out of sync with the phase math.
varying float v_ab_uv;

void vertex() {
	// 0.0 at point_a's cap, 1.0 at point_b's cap — see comment block above.
	v_ab_uv = clamp((VERTEX.y / pipe_length) + 0.5, 0.0, 1.0);
}

void fragment() {
	if (!build_mode_visible || !has_flow) {
		discard;
	}

	// along_uv: 0 at THIS edge's upstream endpoint, 1 at its downstream
	// endpoint, regardless of whether that's point_a or point_b — same
	// coordinate feeds tiling/phase (continuity) and chevron direction
	// (always increases toward downstream, so a single scroll direction and
	// one fixed texture orientation both read correctly on every edge).
	//
	// NOTE (Jul 2026): the flow_sign>0/<0 branches below are intentionally
	// inverted relative to the naive "flow_sign>0 => point_a is upstream =>
	// along_uv=v_ab_uv" mapping. That naive mapping produced arrows that
	// both pointed and scrolled backwards end-to-end (reported after the
	// cross-joint continuity fix shipped) — the texture's own baked arrow
	// orientation and the TIME scroll sign below are both authored assuming
	// along_uv increases in the OPPOSITE sense from v_ab_uv's raw point_a-\>
	// point_b direction. Flipping both ternary branches corrects direction
	// and motion together without touching WaterGraph's upstream/downstream
	// math or WaterPipeSegment.set_flow_sign()'s meaning at all.
	float along_uv = flow_sign > 0.0 ? (1.0 - v_ab_uv) : v_ab_uv;

	// Rescale from "0..1 across this whole segment" to "0..(real world tiles
	// across this segment)" so tile size is constant in world-space
	// regardless of segment length, then add this segment's phase offset
	// (also in tile units) so the pattern continues seamlessly from the
	// upstream joint instead of restarting at 0.
	float tiles_per_segment = pipe_length / tile_world_length;
	float phase_tiles = phase_offset / tile_world_length;
	float tile_coord = along_uv * tiles_per_segment + phase_tiles;

	// Scroll at a constant world-units/sec rate, toward downstream — the
	// direction is already fully encoded by along_uv increasing away from
	// the hookup on every edge uniformly, so a single subtraction here
	// covers every segment with no per-edge sign needed.
	tile_coord -= TIME * (scroll_speed / tile_world_length);

	vec2 tex_uv = vec2(tile_coord, UV.x);
	vec4 tex = texture(arrow_texture, tex_uv);
	ALBEDO = tex.rgb;
	ALPHA = tex.a;
}
