shader_type spatial;
// cull_disabled (Jul 2026 fix — see "arrows completely gone" below): the
// ceiling-strip redesign discards fragments based on world-space UP-facing
// normal (v_up_dot), but pipes are ceiling-mounted and the player views them
// from BELOW — the upward-facing polygons we want to keep are exactly the
// back-facing ones from the camera's viewpoint below. With `cull_back`,
// those polygons were removed by backface culling before the fragment
// shader's discard() ever ran, so nothing was left to show — arrows read as
// totally gone. `cull_disabled` renders both sides; the discard() in
// fragment() is what actually decides visibility now, same as before.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

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
uniform float tile_world_length : hint_range(0.05, 5.0) = 0.8;   // desired world-units per arrow tile (doubled Jul 2026 — arrows were too tightly packed, this halves arrow density / removes every other one)

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

// ─── Dual quality/purity arrows, ceiling-facing strip only (Jul 2026 redesign) ──
// PRIOR layout: the scrolling arrow band was split into two lanes wrapped
// around the pipe's full circumference (front half-circumference = quality,
// back half-circumference = purity) — both always visible somewhere around
// the pipe depending on viewing angle, seam position arbitrary relative to
// world "up". Brannon's explicit request: collapse BOTH onto just the
// ceiling-facing (top) strip of the pipe, as a SEQUENCE running along the
// pipe's length — quality arrow tile, then purity arrow tile immediately
// touching it, then a blank gap, then the next pair repeats. Same scrolling/
// phase/continuity math as before, just re-targeted: the along-pipe
// coordinate now picks which tile of the repeating [quality][purity][gap]
// pattern a fragment falls in, instead of picking a single lane's tile.
uniform vec4 quality_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 purity_color  : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// World-space gap between one quality+purity pair and the next (Jul 2026
// redesign) — independent of tile_world_length so pair spacing can be tuned
// without changing individual arrow size.
uniform float gap_world_length : hint_range(0.0, 5.0) = 0.5;

// How much of the pipe's circumference (as a dot-product band around world
// UP) counts as "ceiling-facing" — 1.0 = only the exact top line, lower =
// wider band. Soft-edged via v_up_dot itself, no hard cutoff artifacts.
const float UP_BAND_DOT: float = 0.55;


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
// of UV, ONCE, before any scaling — WaterPipeSegment.gd's _rebuild_mesh()'s
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

// World-space "facing up" test (Jul 2026, ceiling-strip redesign) — computed
// once per vertex from the object's own normal transformed to world space,
// so the visible band is stable in world orientation regardless of how this
// segment's mesh is locally rotated to point along its pipe direction.
varying float v_up_dot;

void vertex() {
	// 0.0 at point_a's cap, 1.0 at point_b's cap — see comment block above.
	v_ab_uv = clamp((VERTEX.y / pipe_length) + 0.5, 0.0, 1.0);

	vec3 world_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	v_up_dot = dot(world_normal, vec3(0.0, 1.0, 0.0));
}

void fragment() {
	if (!build_mode_visible || !has_flow) {
		discard;
	}

	// Only the ceiling-facing strip of the pipe's circumference shows arrows
	// now (Jul 2026 redesign) — everywhere else on the cylinder is fully
	// discarded rather than tinted, so both lanes read as sitting on top of
	// the pipe instead of wrapping around it.
	if (v_up_dot < UP_BAND_DOT) {
		discard;
	}
	// Soft-edged cross-section coordinate (0 at the band's outer edge, 1 at
	// dead-center-top) — purely cosmetic width falloff, not a hard seam.
	float lane_v = clamp((v_up_dot - UP_BAND_DOT) / (1.0 - UP_BAND_DOT), 0.0, 1.0);

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

	// World-space distance along the whole pipe RUN (continuous across
	// joints via phase_offset), scrolling toward downstream over time.
	float world_dist = along_uv * pipe_length + phase_offset;
	world_dist -= TIME * scroll_speed;

	// Repeating [quality tile][purity tile][gap] pattern, each pair
	// touching (no gap between the two tiles of one pair), then a blank gap
	// before the next pair starts (Jul 2026 redesign).
	float period = tile_world_length * 2.0 + gap_world_length;
	// GLSL mod() on a negative value still returns a value in [0, period) as
	// long as period > 0, matching GLSL's floored-mod semantics — safe for
	// world_dist going negative as TIME increases.
	float local_pos = mod(world_dist, period);

	vec4 tex = vec4(0.0);
	vec4 tint = vec4(1.0);
	if (local_pos < tile_world_length) {
		// Quality tile.
		float tex_u = local_pos / tile_world_length;
		tex = texture(arrow_texture, vec2(tex_u, lane_v));
		tint = quality_color;
	} else if (local_pos < tile_world_length * 2.0) {
		// Purity tile, immediately after (touching) the quality tile.
		float tex_u = (local_pos - tile_world_length) / tile_world_length;
		tex = texture(arrow_texture, vec2(tex_u, lane_v));
		tint = purity_color;
	} else {
		// Gap between pairs — fully transparent, nothing sampled.
		discard;
	}

	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a;
}
