extends Node3D
class_name BunkerNavMesh
## BunkerNavMesh.gd  (NPC Pass 2, Part 1)
## Owns the game's single runtime-baked NavigationMesh covering the currently
## dug-out bunker. Instantiated by MainWorld._ready() (one line, see plan).
##
## Sources, per rebake:
##   WALKABLE  — one 1×1 floor quad per key in MainWorld._cleared_cells,
##               read via MainWorld.get_cleared_cell_keys() (added below in
##               this same part). Cell key "cx,cz" spans world X [cx,cx+1],
##               Z [cz,cz+1].
##   OBSTACLES — one box per placed object from
##               BuildModeController.get_nav_obstacle_snapshot(), extruded
##               tall (OBSTACLE_H) so the bake can never treat its top as a
##               walkable ledge.
##
## Rebake triggers (all automatic, no other system edited):
##   - RockSurround.chunk_deconstructed / chunk_restored signals (dig/undo)
##   - placed-object fingerprint change, polled every POLL_INTERVAL
##   - one initial bake shortly after startup
## All triggers only mark dirty; the actual bake runs debounced
## (REBAKE_DEBOUNCE after the last trigger) and asynchronously
## (NavigationServer3D.bake_from_source_geometry_data on a worker thread),
## so digging ten rocks in a row costs one bake, and nothing hitches.

const FLOOR_Y: float = 0.0            ## bake-source plane; path Y is advisory only —
                                      ## NPC gravity/physics owns real Y (see NPC.gd)
const OBSTACLE_H: float = 2.0
const REBAKE_DEBOUNCE: float = 0.5    ## seconds after last dirty-mark before baking
const POLL_INTERVAL: float = 1.0      ## placed-object fingerprint poll cadence

var _region: NavigationRegion3D = null
var _navmesh: NavigationMesh = null
var _dirty: bool = true
var _debounce: float = 0.0
var _poll_timer: float = 0.0
var _last_fingerprint: int = -1
var _baking: bool = false
var _bake_queued_again: bool = false

func _ready() -> void:
	add_to_group("bunker_navmesh")

	_navmesh = NavigationMesh.new()
	## Agent shape: NPC capsule is radius 0.5 — but the two most common
	## traversal gaps in this game are exactly 1 cell (1.0 wide) between two
	## obstacle footprints, which 0.5 would seal shut. 0.35 keeps doorway-
	## sized gaps open while still hugging paths safely inside the physics
	## capsule's slide behavior (collision remains the hard guarantee).
	_navmesh.agent_radius = 0.35
	_navmesh.agent_height = 1.8
	_navmesh.agent_max_climb = 0.3
	_navmesh.agent_max_slope = 30.0
	_navmesh.cell_size = 0.1
	_navmesh.cell_height = 0.15

	_region = NavigationRegion3D.new()
	_region.name = "BunkerNavRegion"
	_region.navigation_mesh = _navmesh
	add_child(_region)

	## Listen for digs directly — RockSurround is MainWorld's exported ref.
	var world: Node = get_tree().get_first_node_in_group("main_world")
	if world != null and "rock_surround" in world and world.rock_surround != null:
		var rs: Node = world.rock_surround
		if rs.has_signal("chunk_deconstructed"):
			rs.chunk_deconstructed.connect(func(_a = null, _b = null, _c = null) -> void: mark_dirty())
		if rs.has_signal("chunk_restored"):
			rs.chunk_restored.connect(func(_a = null, _b = null, _c = null) -> void: mark_dirty())

func mark_dirty() -> void:
	_dirty = true
	_debounce = REBAKE_DEBOUNCE

func _process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = POLL_INTERVAL
		_poll_placed_objects()

	if _dirty:
		_debounce -= delta
		if _debounce <= 0.0:
			_dirty = false
			_rebake()

func _poll_placed_objects() -> void:
	var world: Node = get_tree().get_first_node_in_group("main_world")
	if world == null or not ("_build_controller" in world):
		return
	var bc: Node = world._build_controller
	if bc == null or not bc.has_method("get_nav_obstacle_snapshot"):
		return
	var snap: Dictionary = bc.get_nav_obstacle_snapshot()
	var fp: int = snap.get("fingerprint", 0)
	if fp != _last_fingerprint:
		_last_fingerprint = fp
		mark_dirty()

func _rebake() -> void:
	if _baking:
		_bake_queued_again = true   ## coalesce: bake once more when current finishes
		return

	var world: Node = get_tree().get_first_node_in_group("main_world")
	if world == null or not world.has_method("get_cleared_cell_keys"):
		return

	var src: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()

	## ── Walkable floor: one quad (two triangles) per cleared cell ──────────
	var cell_keys: Array = world.get_cleared_cell_keys()
	for key: String in cell_keys:
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2:
			continue
		var cx: float = float(parts[0])
		var cz: float = float(parts[1])
		var a: Vector3 = Vector3(cx,       FLOOR_Y, cz)
		var b: Vector3 = Vector3(cx + 1.0, FLOOR_Y, cz)
		var c: Vector3 = Vector3(cx + 1.0, FLOOR_Y, cz + 1.0)
		var d: Vector3 = Vector3(cx,       FLOOR_Y, cz + 1.0)
		src.add_faces(PackedVector3Array([a, c, b,  a, d, c]), Transform3D.IDENTITY)

	## ── Obstacles: one tall box per placed object footprint ────────────────
	var bc: Node = world._build_controller if ("_build_controller" in world) else null
	if bc != null and bc.has_method("get_nav_obstacle_snapshot"):
		var snap: Dictionary = bc.get_nav_obstacle_snapshot()
		for ob: Dictionary in snap.get("obstacles", []):
			var pos: Vector3  = ob["pos"]
			var half: Vector2 = ob["half"]
			var ang: float    = deg_to_rad(float(ob["angle_deg"]))
			src.add_faces(_box_faces(half, OBSTACLE_H),
				Transform3D(Basis(Vector3.UP, ang), Vector3(pos.x, FLOOR_Y, pos.z)))

	_baking = true
	NavigationServer3D.bake_from_source_geometry_data(_navmesh, src, _on_bake_done)

func _on_bake_done() -> void:
	_baking = false
	## Push the freshly-baked mesh into the region (re-assign triggers sync).
	_region.navigation_mesh = _navmesh
	if _bake_queued_again:
		_bake_queued_again = false
		mark_dirty()

## Local-space triangle list for a box: XZ half-extents `half`, from y=0 up
## to y=h. 5 faces (bottom skipped — it sits on the floor plane and only the
## sides/top matter for blocking walkability).
func _box_faces(half: Vector2, h: float) -> PackedVector3Array:
	var x: float = half.x
	var z: float = half.y
	var p: Array[Vector3] = [
		Vector3(-x, 0.0, -z), Vector3( x, 0.0, -z),
		Vector3( x, 0.0,  z), Vector3(-x, 0.0,  z),   ## 0..3 bottom ring
		Vector3(-x, h,   -z), Vector3( x, h,   -z),
		Vector3( x, h,    z), Vector3(-x, h,    z),   ## 4..7 top ring
	]
	var f: PackedVector3Array = PackedVector3Array()
	var quads: Array = [
		[0, 1, 5, 4],   ## -Z side
		[1, 2, 6, 5],   ## +X side
		[2, 3, 7, 6],   ## +Z side
		[3, 0, 4, 7],   ## -X side
		[4, 5, 6, 7],   ## top
	]
	for q: Array in quads:
		f.append_array(PackedVector3Array([
			p[q[0]], p[q[1]], p[q[2]],
			p[q[0]], p[q[2]], p[q[3]],
		]))
	return f