shader_type spatial;
render_mode blend_mix, cull_back;

// tank_fill.gdshader — Water Dispenser fill-level visual (Jul 2026, Feature 2
// of the purifier-pulse/dispenser-fill plan).
//
// No new geometry: applied directly to WaterDispenser's existing single
// BoxMesh body (the box was fully opaque flat-color before this — there is
// no separate "window" mesh). Below the fill cutoff renders as a water-blue
// tint (WaterInfoUI/WaterDispenserUI's existing OK_COLOR blue theme, reused
// here for consistency rather than inventing a new blue — see
// WaterDispenser.gd's COLOR_WATER_FILL const); above it renders as the
// dispenser's normal empty-tank body color. A thin brighter "waterline" band
// sits right at the cutoff for readability at normal camera distance (a
// cheap, optional nice-to-have flagged in the plan — kept simple, no
// ripple/wave/foam).
//
// Cutoff is computed in OBJECT-LOCAL space (VERTEX.y, relative to the box
// mesh's own vertical extent via `tank_height`), NOT world Y, so this reads
// correctly no matter where the dispenser is placed/rotated.

uniform float fill_pct : hint_range(0.0, 1.0) = 0.0;   // set from WaterDispenser._update_fill_visual()
uniform float tank_height : hint_range(0.05, 5.0) = 0.55;   // BOX_SIZE.y — box is vertically centered on its own local origin

uniform vec4 water_color : source_color = vec4(0.35, 0.85, 1.00, 1.0);   // matches WaterInfoUI.OK_COLOR
uniform vec4 empty_color : source_color = vec4(0.26, 0.42, 0.48, 1.0);   // matches WaterDispenser.COLOR_BODY

const float WATERLINE_BAND: float = 0.02;   // fraction of tank_height either side of the cutoff
const vec4  WATERLINE_COLOR: vec4 = vec4(0.75, 0.97, 1.00, 1.0);   // bright highlight at the fill line

varying float v_local_frac;

void vertex() {
	// 0.0 at the box's bottom, 1.0 at its top (box mesh is centered on its
	// own local origin, so local Y ranges roughly [-tank_height/2, +tank_height/2]).
	v_local_frac = clamp((VERTEX.y / tank_height) + 0.5, 0.0, 1.0);
}

void fragment() {
	vec4 base_color;
	if (abs(v_local_frac - fill_pct) < WATERLINE_BAND) {
		base_color = WATERLINE_COLOR;
	} else if (v_local_frac <= fill_pct) {
		base_color = water_color;
	} else {
		base_color = empty_color;
	}

	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.45;
	METALLIC = 0.20;
}
