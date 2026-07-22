shader_type spatial;
// cull_disabled (kept deliberately, Jul 2026 ribbon rewrite): the arrow
// overlay is now a thin flat ribbon mounted just above the pipe rather than
// a wrap-around cylinder (see the "Arrow shape distortion" section in
// docs/systems/water/README.md for why). A flat quad's visible face depends
// on winding/orientation, and this project has already been bitten twice by
// wrong-side-culling assumptions on this exact shader (see the "arrows
// completely gone" history below) — cull_disabled costs nothing extra for a
// 2-triangle ribbon and removes that entire class of regression risk.
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
// ALWAYS pushed explicitly from WaterPipeSegment._build_arrow_overlay()
// now (Jul 2026 fix — "arrows stretched out lengthwise") — derived from the
// ribbon's actual current width/aspect so it can't silently drift out of
// sync with the arrow texture's real proportions again (see
// WaterPipeSegment.ARROW_CONTENT_ASPECT's own comment for the root cause).
// This default is just a harmless fallback if the material is ever used
// without that push.
uniform float tile_world_length : hint_range(0.05, 5.0) = 0.11;

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

// World-space gap between one quality+purity pair and the next. ALWAYS
// pushed explicitly from WaterPipeSegment._build_arrow_overlay() now (Jul
// 2026 fix — kept proportional to the corrected, no-longer-stretched arrow
// length via ARROW_PAIR_GAP_RATIO, rather than a fixed absolute number that
// would read as oversized next to a properly-sized arrow). This default is
// just a harmless fallback if the material is ever used without that push.
uniform float gap_world_length : hint_range(0.0, 5.0) = 0.025;


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

void vertex() {
	// 0.0 at point_a's cap, 1.0 at point_b's cap — see comment block above.
	// Still valid unchanged for the new flat ribbon mesh: WaterPipeSegment.
	// _build_arrow_overlay()'s ribbon quad uses the exact same local-Y-is-
	// length-axis convention the old CylinderMesh used (Y centered on
	// origin, -pipe_length/2..+pipe_length/2), specifically so this line
	// and everything below it (tiling/phase/scroll/direction) needs zero
	// changes for the mesh-shape rewrite.
	v_ab_uv = clamp((VERTEX.y / pipe_length) + 0.5, 0.0, 1.0);
}

void fragment() {
	if (!build_mode_visible || !has_flow) {
		discard;
	}

	// Cross-section (arrow width) coordinate (Jul 2026 ribbon rewrite): the
	// old cylinder-based version derived this from a per-fragment world-
	// normal dot product (v_up_dot), which is a COSINE of the angle around
	// the pipe's circumference — non-linear, and additionally warped by the
	// pipe mesh's low (10-sided) polygon count within the narrow visible
	// band, producing visibly kinked/zigzag "M"-shaped chevrons. A flat
	// ribbon quad has no circumference and no cosine term at all — UV.x is
	// already perfectly linear across the ribbon's width by construction,
	// so no remapping is needed here at all.
	float lane_v = UV.x;

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
	// ARROW_CONTENT_START/WIDTH (Jul 2026 fix — "arrows not touching, want
	// less space", sub-cause A): pipe_flow_arrow.png's two baked chevrons
	// each have heavy transparent padding around them within their own
	// 0..0.5 half (confirmed via direct alpha-channel column inspection —
	// opaque content only spans pixel columns 15-50 of the texture's 128px
	// width, i.e. normalized 0.1172-0.3906). The OLD `ARROW_TEXTURE_PERIOD =
	// 0.5` sampled that ENTIRE padded half per tile — tile boundaries did
	// touch exactly (that math was already correct), but because each tile
	// sampled the full padded range, the VISIBLE gap between two "touching"
	// chevrons worked out to a real, non-zero gap regardless. Fix: sample
	// only the measured opaque content sub-range instead of the full
	// padded half, so the visible chevrons themselves sit flush.
	const float ARROW_CONTENT_START = 0.1172;
	const float ARROW_CONTENT_WIDTH = 0.2734;   // 0.3906 - 0.1172
	if (local_pos < tile_world_length) {
		// Quality tile.
		float tex_u = ARROW_CONTENT_START + (local_pos / tile_world_length) * ARROW_CONTENT_WIDTH;
		tex = texture(arrow_texture, vec2(tex_u, lane_v));
		tint = quality_color;
	} else if (local_pos < tile_world_length * 2.0) {
		// Purity tile, immediately after (touching) the quality tile.
		float tex_u = ARROW_CONTENT_START + ((local_pos - tile_world_length) / tile_world_length) * ARROW_CONTENT_WIDTH;
		tex = texture(arrow_texture, vec2(tex_u, lane_v));
		tint = purity_color;
	} else {
		// Gap between pairs — fully transparent, nothing sampled.
		discard;
	}

	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a;
}
