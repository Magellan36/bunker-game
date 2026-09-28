extends SceneTree
## tools/menu_backdrop/bake_menu_clutter.gd — scatters the main-menu clutter.
##
##   godot --headless --path . --script res://tools/menu_backdrop/bake_menu_clutter.gd
##
## Writes scenes/world/menu_backdrop/MenuClutter.tscn: instances of the Poly
## Haven clutter and Destroyed City pieces thrown across the surface after
## the blast — upright, on their sides, upside down, or tilted and half
## buried — resting on the baked terrain. Deterministic (fixed seed): re-run
## after re-baking the terrain or moving slots. Rules only; nothing here is AI.

const BACKDROP := "res://scenes/world/menu_backdrop/MenuBackdrop.tscn"
const SLOT_SCRIPT := "res://scripts/world/menu_backdrop/BackdropAssetSlot.gd"
const TERRAIN_MESH := "res://assets/menu_backdrop/terrain/menu_terrain.res"
const BUILDER := "res://scripts/world/menu_backdrop/MenuTerrainBuilder.gd"
const OUT := "res://scenes/world/menu_backdrop/MenuClutter.tscn"
const C := "res://assets/models/menu_backdrop/clutter/"
const D := "res://assets/models/menu_backdrop/destroyed/"
const SEED := 20260927

const CAMERA := Vector2(-1.5, 9.0)
## Ground zero lies far off to the back-left; debris was thrown away from it.
const BLAST_DIR := Vector2(0.62, 0.78)

## kind: small | medium | rock | rubble. weight: relative frequency.
## poses: allowed resting poses. scale: [min, max] base scale.
const ITEMS := {
	"ammo_box": {"kind": "small", "weight": 3, "poses": ["upright", "side", "back", "tilt"]},
	"cheese_box": {"kind": "small", "weight": 1, "poses": ["upright", "side", "back"]},
	"signal_flashlight": {"kind": "small", "weight": 1, "poses": ["side", "tilt"]},
	"vintage_flashlight": {"kind": "small", "weight": 1, "poses": ["side", "tilt"]},
	"concrete_cat_statue": {"kind": "small", "weight": 1, "poses": ["side", "back", "tilt"]},
	"jerrycan": {"kind": "small", "weight": 3, "poses": ["upright", "side", "back", "tilt"]},
	"cardboard_box": {"kind": "small", "weight": 3, "poses": ["upright", "side", "back", "tilt"]},
	"spacecraft_instrument": {"kind": "small", "weight": 0.5, "poses": ["side", "back", "tilt"]},
	"cash_register": {"kind": "medium", "weight": 2, "poses": ["side", "back", "tilt"]},
	"television": {"kind": "medium", "weight": 3, "poses": ["upright", "side", "back", "tilt"]},
	"monobloc_chair": {"kind": "medium", "weight": 3, "poses": ["side", "back", "tilt"]},
	"tyre": {"kind": "medium", "weight": 4, "poses": ["flat", "flat", "upright", "tilt"]},
	"utility_box_01": {"kind": "medium", "weight": 2, "poses": ["side", "back", "tilt"]},
	"utility_box_02": {"kind": "medium", "weight": 2, "poses": ["side", "tilt"]},
	"aircon_unit": {"kind": "medium", "weight": 2, "poses": ["side", "back", "tilt"]},
	"wheelchair": {"kind": "medium", "weight": 1, "poses": ["side", "back"]},
	"wooden_crate": {"kind": "medium", "weight": 3, "poses": ["upright", "side", "back", "tilt"]},
	"military_crate": {"kind": "medium", "weight": 2, "poses": ["upright", "side", "tilt"]},
	"military_compressor": {"kind": "medium", "weight": 1, "poses": ["side", "tilt"]},
	"fire_pit": {"kind": "medium", "weight": 1, "poses": ["upright"]},
	"boulder_03": {"kind": "rock", "weight": 2, "poses": ["rock"]},
	"boulder_05": {"kind": "rock", "weight": 2, "poses": ["rock"]},
	"moss_rock_01": {"kind": "rock", "weight": 1, "poses": ["rock"]},
	"moss_rock_02": {"kind": "rock", "weight": 1, "poses": ["rock"]},
	"moss_rock_03": {"kind": "rock", "weight": 1, "poses": ["rock"]},
	"moss_rock_04": {"kind": "rock", "weight": 1, "poses": ["rock"]},
	"moss_rock_05": {"kind": "rock", "weight": 1, "poses": ["rock"]},
	"moss_rock_06": {"kind": "rock", "weight": 1, "poses": ["rock"]},
	"debris": {"kind": "rubble", "weight": 4, "poses": ["rock"]},
	"rocks": {"kind": "rubble", "weight": 3, "poses": ["rock"]},
	"road_slab": {"kind": "rubble", "weight": 3, "poses": ["slab"]},
	"column_1": {"kind": "rubble", "weight": 1, "poses": ["side", "tilt"]},
	"column_2": {"kind": "rubble", "weight": 1, "poses": ["side", "tilt"]},
	"column_3": {"kind": "rubble", "weight": 1, "poses": ["side", "tilt"]},
}
## kind -> [count, min distance, max distance, scale near, scale far]
const BANDS := {
	"small": [22, 11.0, 48.0, 1.0, 1.0],
	"medium": [40, 12.0, 130.0, 1.0, 1.15],
	"rock": [46, 12.0, 460.0, 0.9, 2.6],
	"rubble": [52, 14.0, 480.0, 1.0, 3.2],
}

var _rng := RandomNumberGenerator.new()
var _heights: PackedVector3Array
var _consts: Dictionary
var _pads: Array = []      ## [Vector2 centre, float radius]
var _placed: Array = []    ## [Vector2 position, float radius]
var _bounds: Dictionary = {}
var _scenes: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_rng.seed = SEED
	_consts = (load(BUILDER) as GDScript).get_script_constant_map()
	var terrain: ArrayMesh = load(TERRAIN_MESH)
	_heights = terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	await _collect_pads()
	for item: String in ITEMS:
		var path: String = (C if ITEMS[item]["kind"] in ["small", "medium", "rock"] else D) + item + "/" + item + ".gltf"
		_scenes[item] = load(path)
		_bounds[item] = _measure(_scenes[item])

	var root := Node3D.new()
	root.name = "MenuClutter"
	var clusters: Array = _make_clusters(16)
	var counts := {}
	for kind: String in BANDS:
		var band: Array = BANDS[kind]
		var names: Array = ITEMS.keys().filter(func(n: String) -> bool: return ITEMS[n]["kind"] == kind)
		var placed := 0
		var tries := 0
		while placed < int(band[0]) and tries < 4000:
			tries += 1
			var item: String = _pick(names)
			var pos: Vector2 = _choose_position(kind, band, clusters)
			if pos == Vector2.INF:
				continue
			var d: float = pos.distance_to(CAMERA)
			var far_t: float = clampf((d - band[1]) / maxf(band[2] - band[1], 1.0), 0.0, 1.0)
			var s: float = lerpf(band[3], band[4], far_t) * _rng.randf_range(0.85, 1.15)
			var node := _place(item, pos, s)
			if node == null:
				continue
			root.add_child(node)
			node.owner = root
			placed += 1
			counts[item] = int(counts.get(item, 0)) + 1
		print("%-7s placed %d (tries %d)" % [kind, placed, tries])
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT)
	print("saved %s: %d instances, err=%d" % [OUT, root.get_child_count(), err])
	print(counts)
	quit(0 if err == OK else 1)


func _collect_pads() -> void:
	var backdrop: Node3D = (load(BACKDROP) as PackedScene).instantiate()
	root.add_child(backdrop)
	await process_frame
	for slot: Node in backdrop.find_children("*", "Node3D", true, false):
		var script: Script = slot.get_script()
		if script == null or script.resource_path != SLOT_SCRIPT or slot.name == "Ground":
			continue
		var box := AABB()
		var first := true
		var stack: Array[Node] = [slot]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children(true))
			if node is GeometryInstance3D and not (node is GPUParticles3D or node is CPUParticles3D):
				var wb: AABB = (node as GeometryInstance3D).global_transform * (node as GeometryInstance3D).get_aabb()
				box = wb if first else box.merge(wb)
				first = false
		if not first:
			_pads.append([Vector2(box.get_center().x, box.get_center().z), maxf(box.size.x, box.size.z) * 0.5 + 0.6])
	backdrop.queue_free()


func _measure(scene: PackedScene) -> AABB:
	var inst: Node3D = scene.instantiate()
	var box := AABB()
	var first := true
	for mi: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t: Transform3D = Transform3D.IDENTITY
		var n: Node = m
		while n != inst and n is Node3D:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var b: AABB = t * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	inst.free()
	return box


func _pick(names: Array) -> String:
	var total := 0.0
	for n: String in names:
		total += float(ITEMS[n]["weight"])
	var r := _rng.randf() * total
	for n: String in names:
		r -= float(ITEMS[n]["weight"])
		if r <= 0.0:
			return n
	return names[-1]


func _make_clusters(count: int) -> Array:
	var out: Array = []
	for i: int in count:
		var d: float = exp(_rng.randf_range(log(12.0), log(420.0)))
		var yaw: float = deg_to_rad(_rng.randf_range(-36.0, 40.0))
		out.append(CAMERA + Vector2(sin(yaw), -cos(yaw)) * d)
	return out


func _choose_position(kind: String, band: Array, clusters: Array) -> Vector2:
	var pos: Vector2
	if _rng.randf() < 0.6:
		# Debris field: stretched along the blast direction.
		var c: Vector2 = clusters[_rng.randi() % clusters.size()]
		var spread: float = clampf(c.distance_to(CAMERA) * 0.09, 2.5, 28.0)
		var along: float = _rng.randfn(0.0, spread * 1.8)
		var across: float = _rng.randfn(0.0, spread * 0.7)
		pos = c + BLAST_DIR * along + Vector2(-BLAST_DIR.y, BLAST_DIR.x) * across
	else:
		var d: float = exp(_rng.randf_range(log(band[1]), log(band[2])))
		var yaw: float = deg_to_rad(_rng.randf_range(-44.0, 46.0))
		pos = CAMERA + Vector2(sin(yaw), -cos(yaw)) * d
	var dist: float = pos.distance_to(CAMERA)
	if dist < band[1] or dist > band[2]:
		return Vector2.INF
	var yaw_deg: float = rad_to_deg(atan2(pos.x - CAMERA.x, CAMERA.y - pos.y))
	# Behind the menu text (left third, near): mostly clear.
	if yaw_deg < -11.0 and dist < 75.0 and _rng.randf() < 0.88:
		return Vector2.INF
	# Keep most of the near street open.
	var street_x: float = _street_x(pos.y)   ## mirrors MenuTerrainBuilder.street_x
	if absf(pos.x - street_x) < 3.2 and dist < 45.0 and _rng.randf() < 0.7:
		return Vector2.INF
	for pad: Array in _pads:
		if pos.distance_to(pad[0]) < float(pad[1]):
			return Vector2.INF
	return pos


func _street_x(z: float) -> float:
	return -2.0 + 3.2 * sin((z + 20.0) * 0.011) * smoothstep(-5.0, -60.0, z)


func _place(item: String, pos: Vector2, s: float) -> Node3D:
	var aabb: AABB = _bounds[item]
	var radius: float = maxf(aabb.size.x, aabb.size.z) * 0.5 * s
	for p: Array in _placed:
		if pos.distance_to(p[0]) < (radius + float(p[1])) * 0.9:
			return null
	var poses: Array = ITEMS[item]["poses"]
	var pose: String = poses[_rng.randi() % poses.size()]
	var yaw: float = _rng.randf() * TAU
	var basis := Basis(Vector3.UP, yaw)
	var sink := 0.0
	match pose:
		"upright":
			var lean := Vector3(BLAST_DIR.x, 0.0, BLAST_DIR.y).cross(Vector3.UP).normalized()
			basis = Basis(lean, deg_to_rad(_rng.randf_range(2.0, 9.0))) * basis
			sink = _rng.randf_range(0.0, 0.04)
		"side":
			var axis := Vector3.RIGHT if _rng.randf() < 0.5 else Vector3.BACK
			basis = basis * Basis(axis, deg_to_rad(90.0 * (1.0 if _rng.randf() < 0.5 else -1.0) + _rng.randf_range(-10.0, 10.0)))
			sink = _rng.randf_range(0.04, 0.12)
		"back":
			basis = basis * Basis(Vector3.RIGHT, deg_to_rad(180.0 + _rng.randf_range(-12.0, 12.0)))
			sink = _rng.randf_range(0.04, 0.1)
		"tilt":
			var axis := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
			basis = Basis(axis, deg_to_rad(_rng.randf_range(25.0, 65.0))) * basis
			sink = _rng.randf_range(0.18, 0.38)
		"flat":
			basis = basis * Basis(Vector3.RIGHT, deg_to_rad(90.0 + _rng.randf_range(-6.0, 6.0)))
			sink = _rng.randf_range(0.02, 0.1)
		"rock":
			var axis := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
			basis = Basis(axis, deg_to_rad(_rng.randf_range(0.0, 22.0))) * basis
			sink = _rng.randf_range(0.12, 0.3)
		"slab":
			var axis := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized()
			basis = Basis(axis, deg_to_rad(_rng.randf_range(4.0, 28.0))) * basis
			sink = _rng.randf_range(0.1, 0.35)
	# Follow the ground's slope a little.
	var n: Vector3 = _normal(pos)
	basis = Basis(Quaternion(Vector3.UP, n).slerp(Quaternion.IDENTITY, 0.35)) * basis
	basis = basis.scaled(Vector3.ONE * s)
	var min_y := INF
	var max_y := -INF
	for i: int in 8:
		var y: float = (basis * aabb.get_endpoint(i)).y
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
	var ground: float = _height(pos)
	var origin := Vector3(pos.x, ground - min_y - sink * (max_y - min_y), pos.y)
	var node: Node3D = (_scenes[item] as PackedScene).instantiate()
	node.name = "%s_%d" % [item, _placed.size()]
	node.transform = Transform3D(basis, origin)
	_placed.append([pos, radius])
	return node


## Terrain height from the baked grid (inverse of MenuTerrainBuilder's spacing).
func _height(p: Vector2) -> float:
	var cols: int = _consts["COLUMNS"]
	var rows: int = _consts["ROWS"]
	var t: float = signf(p.x) * pow(clampf(absf(p.x) / float(_consts["X_HALF"]), 0.0, 1.0), 1.0 / float(_consts["X_POWER"]))
	var v: float = pow(clampf((float(_consts["Z_NEAR"]) - p.y) / (float(_consts["Z_NEAR"]) - float(_consts["Z_FAR"])), 0.0, 1.0), 1.0 / float(_consts["Z_POWER"]))
	var cf: float = (t + 1.0) * 0.5 * cols
	var rf: float = v * rows
	var c0: int = clampi(int(floor(cf)), 0, cols - 1)
	var r0: int = clampi(int(floor(rf)), 0, rows - 1)
	var fc: float = clampf(cf - c0, 0.0, 1.0)
	var fr: float = clampf(rf - r0, 0.0, 1.0)
	var stride: int = cols + 1
	var h00: float = _heights[r0 * stride + c0].y
	var h01: float = _heights[r0 * stride + c0 + 1].y
	var h10: float = _heights[(r0 + 1) * stride + c0].y
	var h11: float = _heights[(r0 + 1) * stride + c0 + 1].y
	return lerpf(lerpf(h00, h01, fc), lerpf(h10, h11, fc), fr)


func _normal(p: Vector2) -> Vector3:
	var e := 0.5
	var dx: float = _height(p + Vector2(e, 0.0)) - _height(p - Vector2(e, 0.0))
	var dz: float = _height(p + Vector2(0.0, e)) - _height(p - Vector2(0.0, e))
	return Vector3(-dx, 2.0 * e, -dz).normalized()
