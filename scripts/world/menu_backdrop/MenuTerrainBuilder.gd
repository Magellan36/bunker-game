class_name MenuTerrainBuilder
extends RefCounted
## MenuTerrainBuilder.gd (Sep 2026)
## Builds the main-menu surface terrain: a heightfield shaped by explicit,
## hand-tuned rules (street, ditches, craters, berms, hills, a far ridge), with
## flat pads under every backdrop slot so buildings and props sit on level
## ground. Deterministic: the same slot layout always gives the same mesh.
##
## Not called at runtime. `tools/menu_terrain/bake_menu_terrain.gd` runs it
## against the live slot layout and saves the result to
## `assets/menu_backdrop/terrain/menu_terrain.res`, so the menu never pays for
## generation. Re-bake after moving or resizing slots.
##
## Vertex COLOR carries the ground-layer weights read by
## `assets/shaders/menu_ground.gdshader`:
##   R = gravel (street bed), G = debris (ditches, crater bowls, hollows),
##   B = brick rubble (around ruins, crater rims), A = pad (level ground).

## Terrain extent in world metres (camera sits at about x -1.5, z 9).
const X_HALF: float = 440.0
const Z_NEAR: float = 26.0
const Z_FAR: float = -540.0
## Grid resolution; spacing is densest near the street and the camera.
const COLUMNS: int = 256
const ROWS: int = 256
const X_POWER: float = 1.8
const Z_POWER: float = 1.9

const CAMERA_XZ: Vector2 = Vector2(-1.5, 9.0)
const STREET_HALF_WIDTH: float = 5.0
const DITCH_OFFSET: float = 8.6
const DITCH_DEPTH: float = 1.25
const DITCH_WIDTH: float = 1.7

## (x, z, radius, depth): shell and collapse craters along the street.
const CRATERS: Array[Vector4] = [
	Vector4(-8.5, -47.0, 4.5, 1.3),
	Vector4(8.0, -70.0, 6.0, 1.6),
	Vector4(-30.0, -96.0, 9.0, 2.2),
	Vector4(34.0, -148.0, 12.0, 2.6),
	Vector4(-62.0, -182.0, 15.0, 3.0),
	Vector4(70.0, -60.0, 10.0, 2.0),
]

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
## Each pad: {centre: Vector2, radius: float, falloff: float}
var _pads: Array[Dictionary] = []


func _init() -> void:
	_noise.seed = 7031
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.frequency = 1.0
	_detail.seed = 1187
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail.fractal_octaves = 3
	_detail.frequency = 1.0


## A level pad: height blends to 0 inside `radius`, over `falloff` metres.
func add_pad(centre: Vector2, radius: float, falloff: float) -> void:
	_pads.append({"centre": centre, "radius": radius, "falloff": falloff})


func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in ROWS + 1:
		var v: float = float(row) / ROWS
		var z: float = Z_NEAR - (Z_NEAR - Z_FAR) * pow(v, Z_POWER)
		for col: int in COLUMNS + 1:
			var t: float = float(col) / COLUMNS * 2.0 - 1.0
			var x: float = signf(t) * X_HALF * pow(absf(t), X_POWER)
			var sample: Dictionary = _sample(x, z)
			st.set_color(sample["splat"])
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, sample["height"], z))
	## Rows run away from the camera (-Z), columns run +X. Godot front faces
	## are clockwise seen from above, so each quad is wound i → i+stride → i+1.
	var stride: int = COLUMNS + 1
	for row: int in ROWS:
		for col: int in COLUMNS:
			var i: int = row * stride + col
			st.add_index(i)
			st.add_index(i + stride)
			st.add_index(i + 1)
			st.add_index(i + 1)
			st.add_index(i + stride)
			st.add_index(i + stride + 1)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Street centreline: a gentle S-curve that keeps the vanishing point.
static func street_x(z: float) -> float:
	return -2.0 + 3.2 * sin((z + 20.0) * 0.011) * smoothstep(-5.0, -60.0, z)


func _fbm(noise: FastNoiseLite, x: float, z: float, metres: float) -> float:
	return noise.get_noise_2d(x / metres, z / metres)   ## about -1..1


func _sample(x: float, z: float) -> Dictionary:
	var d_street: float = absf(x - street_x(z))
	var ahead: float = smoothstep(-8.0, -26.0, z)   ## 0 near the camera, 1 up the street
	var h: float = 0.22 * _fbm(_detail, x, z, 6.0) + 0.35 * _fbm(_noise, x, z, 24.0)

	# Street bed: slightly sunken, smoothed.
	var road: float = 1.0 - smoothstep(STREET_HALF_WIDTH - 1.0, STREET_HALF_WIDTH + 1.5, d_street)
	h = lerpf(h, -0.12 + 0.05 * _fbm(_detail, x, z, 3.0), road)

	# Ditches either side, broken up so they read as eroded, not engineered.
	var ditch_break: float = smoothstep(-0.35, 0.25, _fbm(_noise, x * 0.6, z, 30.0))
	var ditch: float = exp(-pow((d_street - DITCH_OFFSET) / DITCH_WIDTH, 2.0)) * ahead * ditch_break
	var berm: float = exp(-pow((d_street - DITCH_OFFSET - 3.2) / 2.2, 2.0)) * ahead
	h += -DITCH_DEPTH * ditch + 0.55 * berm * ditch_break

	# Rising ground away from the street: mounds mid-way, hills at the sides.
	var side: float = smoothstep(16.0, 90.0, d_street) * smoothstep(-12.0, -70.0, z)
	var hills: float = (0.55 + 0.45 * _fbm(_noise, x, z, 110.0)) \
		* lerpf(4.0, 22.0, smoothstep(60.0, 320.0, d_street))
	h += side * hills
	# A long low ridge across the far distance, parted where the street runs,
	# so the skyline's feet sink behind a horizon line.
	var ridge: float = exp(-pow((z + 215.0) / 28.0, 2.0)) * smoothstep(10.0, 45.0, d_street)
	h += ridge * (4.0 + 3.0 * _fbm(_noise, x, z, 60.0))

	# Craters: a bowl with a raised, broken rim.
	var crater_bowl: float = 0.0
	var crater_rim: float = 0.0
	for c: Vector4 in CRATERS:
		var d: float = Vector2(x - c.x, z - c.y).length()
		var r: float = c.z * (1.0 + 0.12 * _fbm(_detail, x, z, 4.0))
		if d < r * 1.9:
			var bowl: float = clampf(1.0 - (d / r) * (d / r), 0.0, 1.0)
			var rim: float = exp(-pow((d - r) / (0.32 * r), 2.0))
			h += -c.w * bowl + c.w * 0.38 * rim
			crater_bowl = maxf(crater_bowl, bowl)
			crater_rim = maxf(crater_rim, rim)

	# Level pads under slots (buildings, props, the bunker entrance).
	var pad: float = 0.0
	var near_ruin: float = 0.0
	for p: Dictionary in _pads:
		var d: float = ((p["centre"] as Vector2) - Vector2(x, z)).length()
		var radius: float = p["radius"]
		var falloff: float = p["falloff"]
		pad = maxf(pad, 1.0 - smoothstep(radius, radius + falloff, d))
		near_ruin = maxf(near_ruin, exp(-pow((d - radius) / (falloff + 4.0), 2.0)))
	h = lerpf(h, 0.04 * _fbm(_detail, x, z, 3.0), pad)

	# Keep the foreground gentle so nothing pokes into the lens.
	var cam: float = 1.0 - smoothstep(7.0, 16.0, Vector2(x, z).distance_to(CAMERA_XZ))
	h = lerpf(h, minf(h, 0.2) * 0.4, cam)

	var weave: float = _fbm(_noise, x + 311.0, z - 97.0, 18.0)
	var gravel: float = clampf(road * (0.75 + 0.25 * weave) + 0.35 * pad * smoothstep(0.1, 0.6, weave), 0.0, 1.0)
	var debris: float = clampf(ditch * 1.2 + crater_bowl * 0.9 + smoothstep(-0.2, -0.9, h) * 0.6, 0.0, 1.0)
	var brick: float = clampf(near_ruin * (0.55 + 0.45 * weave) + crater_rim * 0.8, 0.0, 1.0)
	return {"height": h, "splat": Color(gravel, debris, brick, pad)}
