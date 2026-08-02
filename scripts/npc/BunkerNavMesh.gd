extends Node3D
class_name BunkerNavMesh
## BunkerNavMesh.gd  (rewritten in NPC Pass 2, Part 9 — parsed-collider bake)
## Owns the game's single runtime-baked NavigationMesh covering the dug-out
## bunker. Instantiated by MainWorld._ready().
##
## Geometry sources, per rebake (BOTH feed one bake):
##   1. PARSED PHYSICS WORLD — NavigationServer3D.parse_source_geometry_data
##      walks the scene from MainWorld and collects every static collider
##      matching geometry_collision_mask = 1: the GridMap floor tiles
##      (walkable tops at their REAL height, y≈0.5), pregen + player-placed
##      walls/pillars (vertical blockers), furniture/device StaticBodies
##      (blockers at real footprints), rocks. RigidBody items and
##      CharacterBody3D (player, NPCs) are excluded by the parser itself.
##      This is the ground truth — no hand-fed footprints, no winding math,
##      no per-tile assumptions.
##   2. SAFETY-NET FLOOR — one quad per MainWorld._cleared_cells key at
##      FLOOR_Y (0.5, the real floor surface). Coplanar with the parsed
##      floor tops, so it merges harmlessly when redundant; it guarantees
##      walkable coverage even if a floor tile ever lacks collision.
##
## Rebake triggers (unchanged from Part 1): RockSurround dig/restore
## signals, placed-object fingerprint poll, initial startup bake — all
## debounced, all baked async off-thread.
##
## HISTORY (do not "restore" any of these):
##   - Part 1 baked hand-built floor quads at FLOOR_Y = 0.0 — half a meter
##     BELOW the real floor. That vertical offset silently broke
##     NavigationAgent3D waypoint advancement (3D-distance reached-checks
##     could never pass) and hid the navmesh under the floor in debug view.
##     FLOOR_Y is now 0.5 and the primary geometry is parsed, not hand-built.
##   - Part 1 also fed every placed object through _tile_half_extents'
##     0.40×0.40 fallback as an obstacle box (wires/pipes/posters/lights
##     became phantom blockers). Parsed colliders replace all of that; the
##     snapshot function is still called ONLY as a cheap change-detector
##     fingerprint, never for geometry.
##   - Part 8's map cell-size sync is kept: the map must match the mesh's
##     cell_size/cell_height for correct map-level rasterization.

const FLOOR_Y: float = 0.5            ## REAL floor surface (GridMap y=1.0,
                                      ## 0.1 cells, row -6 → tile top 0.5)
const REBAKE_DEBOUNCE: float = 0.5
const POLL_INTERVAL: float = 1.0

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

	## Map voxel grid must match the NavigationMesh's below (Part 8, kept).
	var nav_map: RID = get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(nav_map, 0.1)
	NavigationServer3D.map_set_cell_height(nav_map, 0.15)

	_navmesh = NavigationMesh.new()
	## Parse real static colliders on physics bit 1 (walls/floors/furniture
	## all use collision_layer 5 = bits 1+3; mask 1 matches them all).
	_navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_navmesh.geometry_collision_mask = 1
	## Agent shape — matches the NPC capsule exactly (radius 0.4, Part 7/8).
	_navmesh.agent_radius = 0.4
	_navmesh.agent_height = 1.8
	_navmesh.agent_max_climb = 0.3
	_navmesh.agent_max_slope = 30.0
	_navmesh.cell_size = 0.1
	_navmesh.cell_height = 0.15

	_region = NavigationRegion3D.new()
	_region.name = "BunkerNavRegion"
	_region.navigation_mesh = _navmesh
	add_child(_region)

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

## Placed-object fingerprint — used ONLY as a "something changed, rebake"
## signal. The snapshot's footprint data is NOT used for geometry anymore.
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
		_bake_queued_again = true
		return

	var world: Node = get_tree().get_first_node_in_group("main_world")
	if world == null or not world.has_method("get_cleared_cell_keys"):
		return

	var src: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()

	## ── Source 1: the real physics world (floors, walls, furniture, rocks) ─
	NavigationServer3D.parse_source_geometry_data(_navmesh, src, world)

	## ── Source 2: safety-net floor quads at the REAL floor height ──────────
	## Coplanar with parsed floor-tile tops; harmless duplicate when tiles
	## have collision, load-bearing if any ever doesn't. Winding: (a,c,b) /
	## (a,d,c) yields the upward (+Y) normal Recast requires for walkable.
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

	_baking = true
	NavigationServer3D.bake_from_source_geometry_data(_navmesh, src, _on_bake_done)

func _on_bake_done() -> void:
	_baking = false
	_region.navigation_mesh = _navmesh
	if NPCDebug.enabled:
		print("[BunkerNavMesh] bake done: %d polygons, %d vertices" % [
			_navmesh.get_polygon_count(), _navmesh.get_vertices().size()])
	if _bake_queued_again:
		_bake_queued_again = false
		mark_dirty()

const FLOOR_Y: float = 0.5            ## REAL floor surface (GridMap y=1.0,
                                      ## 0.1 cells, row -6 → tile top 0.5)
const REBAKE_DEBOUNCE: float = 0.5
const POLL_INTERVAL: float = 1.0

var _region: NavigationRegion3D = null
var _navmesh: NavigationMesh = null
var _dirty: bool = true
var _debounce: float = 0.0
var _poll_timer: float = 0.0
var _last_fingerprint: int = -1
var _baking: bool = false
var _bake_queued_again: bool = false