extends Node3D
## BunkerPregen.gd
## Generates the starting bunker as a simple 16×8 rectangle at runtime.
##
## Layout (no pit, no inset):
##   Floor  : every cell in the 16×8 interior
##   Walls  : 4 outer edge runs (each extended 1 cell past the corners)
##   Pillars: 4 outer corners
##
## generate() returns a Dictionary { "wx.wz" -> Node3D } using the same
## key format as MainWorld._autofill_nodes so the dig solver can remove
## pregen walls/pillars when a rock is destroyed and opens up that edge.

var build_controller: Node3D = null
var rock_surround:    Node3D = null
var gridmap:          GridMap = null

## Collects spawned light nodes + perimeter key list so we can bridge them
## to the perimeter wire loop one frame after their deferred registration fires.
var _pregen_lights:    Array[Node3D]  = []
var _perimeter_keys:   Array[String]  = []
var _perimeter_positions: Array[Vector3] = []

## Public wire data — read by MainWorld._rebuild_auto_wires to remove stale
## pregen wire nodes/visuals when they become interior after a dig.
## perimeter_wire_nodes: "%.3f_%.3f" XZ key → PM node key String
## perimeter_wire_segs:  Array of the WireSegment Node3D visuals
var perimeter_wire_nodes: Dictionary  = {}   ## pos_key → pm_key
var perimeter_wire_segs:  Array[Node3D] = []

## Fuel can spawn positions — set during generate(), consumed in _spawn_fuel_cans()
var _fuel_can_positions: Array[Vector3] = []

## Flashlight spawn position — center of bunker, dropped from height so it lands on the floor
var _flashlight_spawn: Vector3 = Vector3.ZERO

## ── Must stay in sync with _on_chunk_deconstructed in MainWorld ──────────────
const PLACEMENT_Y: float = 2.0
const FLOOR_Y_ROW: int   = -6
const SHIFT_X:     float = -0.5
const SHIFT_Z:     float = -0.5

const TILE_FLOOR:  int = 0
const TILE_WALL:   int = 1
const TILE_PILLAR: int = 2
const TILE_LIGHT:  int = 5

## Darkening tint applied to the pregen GridMap's floor/wall/pillar meshlib
## items at runtime (July 2026 lighting fix) — matches BuildMaterials.gd's
## DARK=0.667 factor used on player-placed walls/floors in Build Mode.
## bunker_tiles.meshlib is a completely separate asset from that build-mode
## material system (the GridMap references it directly), so its baked
## materials were never touched by that tint and read noticeably brighter/
## more cream-colored than everything else. See _retint_meshlib().
const RETINT_DARK: float = 0.667
var _meshlib_retinted: bool = false

const ANGLE_LEFT:   float = 180.0
const ANGLE_RIGHT:  float =   0.0
const ANGLE_TOP:    float =  90.0
const ANGLE_BOTTOM: float = 270.0


## Returns a Dictionary of all spawned wall/pillar nodes keyed by "%.2f,%.2f"
## world position so MainWorld can register them in _autofill_nodes.
## Duplicates gridmap's MeshLibrary (never mutates the shared .meshlib
## resource on disk) and darkens the FLOOR/WALL/PILLAR items' existing
## surface materials by RETINT_DARK, in place, preserving whatever texture/
## material each item already had — mirrors the "darkening factor applied
## via albedo_color tint" approach BuildMaterials.gd uses for build-mode
## walls/floors. Idempotent (_meshlib_retinted guard) since generate() could
## in principle run more than once.
func _retint_meshlib() -> void:
	if _meshlib_retinted or gridmap == null or gridmap.mesh_library == null:
		return
	_meshlib_retinted = true

	var lib: MeshLibrary = gridmap.mesh_library.duplicate(true) as MeshLibrary
	if lib == null:
		return

	var valid_ids: PackedInt32Array = lib.get_item_list()
	for item_id: int in [TILE_FLOOR, TILE_WALL, TILE_PILLAR]:
		if not valid_ids.has(item_id):
			continue
		var mesh: Mesh = lib.get_item_mesh(item_id)
		if mesh == null:
			continue
		var new_mesh: ArrayMesh = mesh.duplicate(true) as ArrayMesh
		if new_mesh == null:
			continue   ## Not an ArrayMesh (e.g. a primitive) — leave untouched rather than guess.
		for surf: int in new_mesh.get_surface_count():
			var existing: Material = new_mesh.surface_get_material(surf)
			var mat: StandardMaterial3D = (
				existing.duplicate() as StandardMaterial3D
				if existing is StandardMaterial3D
				else StandardMaterial3D.new())
			mat.albedo_color = Color(RETINT_DARK, RETINT_DARK, RETINT_DARK, 1.0) * mat.albedo_color
			new_mesh.surface_set_material(surf, mat)
		lib.set_item_mesh(item_id, new_mesh)

	gridmap.mesh_library = lib


func generate() -> Dictionary:
	if build_controller == null or rock_surround == null:
		push_error("BunkerPregen: build_controller or rock_surround not set")
		return {}

	_retint_meshlib()

	var offset_x: float = rock_surround.OFFSET_X
	var offset_z: float = rock_surround.OFFSET_Z
	var depth:    int   = rock_surround.bunker_depth  ## 16 — runs along X
	var width:    int   = rock_surround.bunker_width  ##  8 — runs along Z

	var wx0: int = int(floor(offset_x))
	var wz0: int = int(floor(offset_z))

	var x0: int = wx0
	var x1: int = wx0 + depth - 1
	var z0: int = wz0
	var z1: int = wz0 + width - 1

	## World-space positions of the 4 inner rock faces (used for wall placement).
	## These are the exact world coords where walls must sit — flush with rock inner edge.
	var wall_left:   float = offset_x                ## = -12.5
	var wall_right:  float = offset_x + float(depth) ## =   3.5
	var wall_top:    float = offset_z                ## =   4.5
	var wall_bottom: float = offset_z + float(width) ## =  12.5

	var spawned: Dictionary = {}   ## key → Node3D, returned to MainWorld

	## ── Pass 1: stamp floor ───────────────────────────────────────────────────
	if gridmap != null:
		for lx: int in range(depth):
			for lz: int in range(width):
				var cx: int = wx0 + lx
				var cz: int = wz0 + lz
				var fcx: int = int(floor(float(cx) + 0.5 + SHIFT_X))
				var fcz: int = int(floor(float(cz) + 0.5 + SHIFT_Z))
				if gridmap.get_cell_item(Vector3i(fcx, FLOOR_Y_ROW, fcz)) == GridMap.INVALID_CELL_ITEM:
					gridmap.set_cell_item(Vector3i(fcx, FLOOR_Y_ROW, fcz), TILE_FLOOR)

	## ── Pass 2: perimeter walls ───────────────────────────────────────────────
	## Wall positions use wall_left/right/top/bottom directly — these are the
	## exact world-space inner faces of the rock ring, so walls sit flush.
	## Each run extends 1 cell past the corners to cover the full edge.

	## Top wall (flush with rock inner top face, facing -Z)
	for cx: int in range(x0 - 1, x1 + 2):
		var wx: float = float(cx) + 0.5 + SHIFT_X
		var wz: float = wall_top
		var node: Node3D = _wall(wx, wz, ANGLE_TOP)
		if node != null:
			spawned[_wkey(wx) + "," + _wkey(wz)] = node

	## Bottom wall (flush with rock inner bottom face, facing +Z)
	for cx: int in range(x0 - 1, x1 + 2):
		var wx: float = float(cx) + 0.5 + SHIFT_X
		var wz: float = wall_bottom
		var node: Node3D = _wall(wx, wz, ANGLE_BOTTOM)
		if node != null:
			spawned[_wkey(wx) + "," + _wkey(wz)] = node

	## Left wall (flush with rock inner left face, facing -X)
	for cz: int in range(z0 - 1, z1 + 2):
		var wx: float = wall_left
		var wz: float = float(cz) + 0.5 + SHIFT_Z
		var node: Node3D = _wall(wx, wz, ANGLE_LEFT)
		if node != null:
			spawned[_wkey(wx) + "," + _wkey(wz)] = node

	## Right wall (flush with rock inner right face, facing +X)
	for cz: int in range(z0 - 1, z1 + 2):
		var wx: float = wall_right
		var wz: float = float(cz) + 0.5 + SHIFT_Z
		var node: Node3D = _wall(wx, wz, ANGLE_RIGHT)
		if node != null:
			spawned[_wkey(wx) + "," + _wkey(wz)] = node

	## ── Pass 3: corner pillars ────────────────────────────────────────────────
	var corners: Array = [
		[wall_left,  wall_top   ],  ## top-left
		[wall_right, wall_top   ],  ## top-right
		[wall_left,  wall_bottom],  ## bot-left
		[wall_right, wall_bottom],  ## bot-right
	]
	for c: Array in corners:
		var px: float    = float(c[0])
		var pz: float    = float(c[1])
		var node: Node3D = _pillar(px, pz)
		if node != null:
			spawned[_wkey(px) + "," + _wkey(pz)] = node

	## ── Pass 4: pregen lights ────────────────────────────────────────────────
	## 6 lights placed to exactly match where a player would snap them via
	## _snap_light_to_wall().  Key rules:
	##   • Y = LIGHT_PLACEMENT_Y (1.0) — same base as player-placed lights
	##   • XZ snapped to wall face - LIGHT_WALL_HALF_THICKNESS (0.05) inward
	##   • Angles from _snap_light_to_wall convention:
	##       wall in -Z (north) → angle 180  (light faces south)
	##       wall in +Z (south) → angle 0    (light faces north)
	##       wall in -X (left)  → angle 270  (light faces right/east)
	##       wall in +X (right) → angle 90   (light faces left/west)
	##
	## Room: X [wall_left → wall_right] = [-12.5 → 3.5], depth=16
	##       Z [wall_top  → wall_bottom] = [4.5  → 12.5], width=8
	##   Centre X   = -4.5
	##   1/3  Z pos =  6.5   (offset_z + width/3)
	##   2/3  Z pos = 10.5   (offset_z + width*2/3)
	## LWHT = inset from wall coordinate to flush light position. Tune empirically.
	const LWHT: float = 0.18
	const LY:   float = 1.0    ## LIGHT_PLACEMENT_Y

	var cx_mid:      float = offset_x + float(depth) * 0.5        ## -4.5
	var cz_third:    float = offset_z + float(width) / 3.0        ##  6.5
	var cz_twothird: float = offset_z + float(width) * 2.0 / 3.0  ## 10.5

	var light_defs: Array = [
		## [wx,                    wz,                    angle ]
		[cx_mid,                 wall_top    + LWHT, 180.0],  ## north wall, face south
		[cx_mid,                 wall_bottom - LWHT,   0.0],  ## south wall, face north
		[wall_left  + LWHT,      cz_third,            270.0],  ## left wall 1/3, face east
		[wall_left  + LWHT,      cz_twothird,         270.0],  ## left wall 2/3, face east
		[wall_right - LWHT,      cz_third,             90.0],  ## right wall 1/3, face west
		[wall_right - LWHT,      cz_twothird,          90.0],  ## right wall 2/3, face west
	]

	_pregen_lights.clear()
	for ld: Array in light_defs:
		var lx: float = float(ld[0])
		var lz: float = float(ld[1])
		var la: float = float(ld[2])
		var lnode: Node3D = _light(lx, LY, lz, la)
		if lnode != null:
			## Collect for deferred bridging — wire node is not yet registered
			## at this point because WallLight uses call_deferred(_register_wire_deferred).
			_pregen_lights.append(lnode)

	## ── Pass 5 / 6: wire loop + light bridging ─────────────────────────────
	## Removed — MainWorld._rebuild_auto_wires() now owns ALL wire nodes.
	## It is called once by _on_chunk_deconstructed (which is triggered by
	## the initial pregen rock-surround setup) and re-runs on every dig.
	## Light reconnection is handled there too via _auto_connect_to_nearby_wires.

	## ── Pass 7: schedule 2 fuel cans leaning against left wall ──────────────
	## Cans are RigidBody3D items — they must be spawned into MainWorld (our parent),
	## not via build_controller which handles static structure tiles only.
	## LWHT = light wall-half-thickness already computed above (recompute here for clarity).
	var cz_third2:    float = offset_z + float(width) / 3.0
	var cz_twothird2: float = offset_z + float(width) * 2.0 / 3.0
	var can_x: float  = wall_left + 0.65   ## ~0.65m inset from left wall face
	var can_y: float  = 0.5                ## safe above-floor Y; gravity settles the can naturally
	_fuel_can_positions = [
		Vector3(can_x, can_y, cz_third2),
		Vector3(can_x, can_y, cz_twothird2),
	]
	call_deferred("_spawn_fuel_cans")

		## ── Pass 8: flashlight — placed directly into player inventory slot 0 ──
	## Keep _flashlight_spawn set as fallback if inventory isn't available.
	var center_x: float = offset_x + float(depth) * 0.5
	var center_z: float = offset_z + float(width) * 0.5
	_flashlight_spawn = Vector3(center_x, 0.5, center_z)
	call_deferred("_give_flashlight_to_player")

	return spawned


## _wire_perimeter — REMOVED.
## Wire layout is now owned entirely by MainWorld._rebuild_auto_wires().
## These empty stubs keep the public dict references intact so any code
## that reads perimeter_wire_nodes / perimeter_wire_segs doesn't crash.
func _wire_perimeter(
		_wall_left: float, _wall_right: float,
		_wall_top: float,  _wall_bottom: float) -> void:
	## No-op: MainWorld owns all wires now.
	perimeter_wire_nodes.clear()
	perimeter_wire_segs.clear()
	_perimeter_keys.clear()
	_perimeter_positions.clear()


## _connect_lights_to_perimeter — REMOVED.
## Light-to-wire bridging is handled by MainWorld pass C
## (calls _auto_connect_to_nearby_wires on every wall_light after each
## wire rebuild).  This stub is kept so any stale call_deferred references
## don't throw a "method not found" error at runtime.
func _connect_lights_to_perimeter() -> void:
	pass  ## No-op.

## Spawns 2 fuel cans leaning against the left wall.
## Called one frame after generate() via call_deferred so get_parent() is valid.
func _spawn_fuel_cans() -> void:
	var world_parent: Node3D = get_parent() as Node3D
	if world_parent == null:
		push_warning("BunkerPregen: no parent node — cannot spawn fuel cans")
		return

	var can_scene: PackedScene = load("res://scenes/world/FuelCan.tscn") as PackedScene
	if can_scene == null:
		push_warning("BunkerPregen: FuelCan.tscn not found — skipping pregen cans")
		return

	for pos: Vector3 in _fuel_can_positions:
		var can: RigidBody3D = can_scene.instantiate() as RigidBody3D
		## Freeze kinematically BEFORE entering the scene tree so physics doesn't
		## process the body at origin (0,0,0) for even one frame, which causes
		## fall-through on floors that haven't been "seen" by the body yet.
		can.freeze      = true
		can.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		world_parent.add_child(can)
		can.global_position = pos
		## Slight rotation so they look leaned/natural, not perfectly aligned
		can.rotation_degrees = Vector3(0.0, randf_range(-15.0, 15.0), 0.0)
		## Unfreeze after one physics frame — body is now positioned correctly
		can.call_deferred("_unfreeze_after_spawn")

	_fuel_can_positions.clear()

## Places a Flashlight directly into the player's inventory slot 0.
## Called deferred so InventoryManager is guaranteed to exist.
func _give_flashlight_to_player() -> void:
	var world_parent: Node3D = get_parent() as Node3D
	if world_parent == null:
		push_warning("BunkerPregen: no parent node — cannot give flashlight")
		return

	var fl_scene: PackedScene = load("res://scenes/world/Flashlight.tscn") as PackedScene
	if fl_scene == null:
		push_warning("BunkerPregen: Flashlight.tscn not found — skipping pregen flashlight")
		return

	## Instantiate and add to world first (InventoryManager._store_to_slot hides it)
	var fl: RigidBody3D = fl_scene.instantiate() as RigidBody3D
	fl.freeze      = true
	fl.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	world_parent.add_child(fl)
	## Place it off-screen initially — _store_to_slot will hide it anyway
	fl.global_position = Vector3(0.0, -100.0, 0.0)

	## Find InventoryManager in the scene tree
	var inv_mgr: Node = world_parent.get_node_or_null("InventoryManager")
	if inv_mgr == null:
		## Try searching the tree (it may live under Player or elsewhere)
		inv_mgr = world_parent.get_tree().get_first_node_in_group("inventory_manager")

	if inv_mgr != null and inv_mgr.has_method("add_item_to_slot"):
		var ok: bool = inv_mgr.add_item_to_slot(fl, 0)
		if not ok:
			## Slot 0 occupied — fall back to first free slot
			if inv_mgr.has_method("add_item"):
				inv_mgr.add_item(fl)
			else:
				## No free slots — drop it on the floor center instead
				fl.global_position    = _flashlight_spawn
				fl.rotation_degrees   = Vector3(randf_range(-8.0, 8.0), randf_range(0.0, 360.0), randf_range(-8.0, 8.0))
				fl.call_deferred("_unfreeze_after_spawn")
	else:
		## No inventory found — world drop fallback
		push_warning("BunkerPregen: InventoryManager not found — dropping flashlight in world")
		fl.global_position    = _flashlight_spawn
		fl.rotation_degrees   = Vector3(randf_range(-8.0, 8.0), randf_range(0.0, 360.0), randf_range(-8.0, 8.0))
		fl.call_deferred("_unfreeze_after_spawn")

func _wkey(v: float) -> String:
	return "%.2f" % v

## `is_true_pregen = true` — these are the ORIGINAL 4 boundary walls/pillars,
## the only ones WallSnapHelpers' strict original-rectangle math is valid for.
## Autofill walls/pillars spawned later by the dig solver (WireGraphBuilder.gd)
## call spawn_structure() without this flag. See spawn_structure()'s header
## comment in BuildModeController.gd for the full picture.
func _wall(wx: float, wz: float, angle: float) -> Node3D:
	return build_controller.spawn_structure(TILE_WALL, Vector3(wx, PLACEMENT_Y, wz), angle, true)

func _pillar(wx: float, wz: float) -> Node3D:
	return build_controller.spawn_structure(TILE_PILLAR, Vector3(wx, PLACEMENT_Y, wz), 0.0, true)

func _light(wx: float, wy: float, wz: float, angle: float) -> Node3D:
	return build_controller.spawn_structure(TILE_LIGHT, Vector3(wx, wy, wz), angle)
