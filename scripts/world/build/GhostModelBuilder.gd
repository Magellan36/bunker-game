extends RefCounted
class_name GhostModelBuilder
## GhostModelBuilder.gd — MASTER FILE for all ghost/preview visuals in Build
## Mode. Both the Construct submenu's spinning preview (BuildModeHUD.gd) and
## the in-world placement ghost (GhostPreview.gd) call into this file rather
## than maintaining separate registries/logic. Adding a new placeable object
## that already has a menu preview (i.e. is registered in
## PROCEDURAL_PREVIEW_SOURCES below) automatically gets a correctly-shaped
## in-world ghost AND a facing arrow for free — no per-object ghost code
## needed elsewhere.
##
## Three responsibilities, each usable independently:
##   1. PROCEDURAL_PREVIEW_SOURCES + build_real_instance() — construct a
##      real, side-effect-free instance of an object's actual script/scene.
##   2. apply_ghost_tint() — recursively recolor every mesh surface in a
##      ghost subtree to translucent green/red, regardless of how many
##      MeshInstance3D nodes it contains or what their real materials are.
##   3. attach_facing_arrow() — universal front-direction indicator,
##      previously hand-attached to only a few tiles; now available (and,
##      per Part 4, applied) to every placeable object.

## ── Registry: tile_id → real script/scene source ────────────────────────
## MOVED HERE from BuildModeHUD.gd — this is now the single source of truth.
## BuildModeHUD.gd no longer keeps its own copy (see Part 5).
##
## TO ADD A NEW FURNITURE/DEVICE: add one entry here. That's the entire
## requirement to get (a) a spinning real-model Construct-menu preview,
## (b) a correctly-shaped in-world ghost, and (c) a facing arrow — all three,
## automatically, no other file needs to change.
const PROCEDURAL_PREVIEW_SOURCES: Dictionary = {
	4:  { "path": "res://scenes/world/Bed.tscn",                    "is_script": false },
	3:  { "path": "res://scripts/world/furniture/Shelving.gd",      "is_script": true  },
	5:  { "path": "res://scripts/world/power/WallLight.gd",         "is_script": true },
	6:  { "path": "res://scripts/world/power/GeneratorObject.gd",   "is_script": true, "tier_prop": "generator_tier", "tier": 0 },
	7:  { "path": "res://scripts/world/power/GeneratorObject.gd",   "is_script": true, "tier_prop": "generator_tier", "tier": 1 },
	8:  { "path": "res://scripts/world/power/GeneratorObject.gd",   "is_script": true, "tier_prop": "generator_tier", "tier": 2 },
	10: { "path": "res://scripts/world/power/PowerTerminal.gd",     "is_script": true },
	11: { "path": "res://scripts/world/items/HeavyConsumerTest.gd", "is_script": true },
	12: { "path": "res://scripts/world/power/BreakerBox.gd",        "is_script": true },
	16: { "path": "res://scripts/world/power/UpgradedBreakerBox.gd","is_script": true },
	13: { "path": "res://scripts/world/power/BatteryBank.gd",       "is_script": true, "tier_prop": "battery_tier", "tier": 0 },
	14: { "path": "res://scripts/world/power/BatteryBank.gd",       "is_script": true, "tier_prop": "battery_tier", "tier": 1 },
	15: { "path": "res://scripts/world/power/BatteryBank.gd",       "is_script": true, "tier_prop": "battery_tier", "tier": 2 },
	18: { "path": "res://scripts/world/water/WaterTestSink.gd",     "is_script": true },
	19: { "path": "res://scripts/world/water/WaterDispenser.gd",    "is_script": true },
	20: { "path": "res://scripts/world/water/WaterPurifier.gd",     "is_script": true },
	21: { "path": "res://scripts/world/farming/FarmingTray.gd",     "is_script": true, "tier_prop": "cell_count", "tier": 1 },
	22: { "path": "res://scripts/world/farming/FarmingTray.gd",     "is_script": true, "tier_prop": "cell_count", "tier": 2 },
	23: { "path": "res://scripts/world/power/GrowLight.gd",         "is_script": true },
	24: { "path": "res://scripts/world/power/GrowLight.gd",         "is_script": true },
	27: { "path": "res://scripts/world/furniture/Table.gd",  "is_script": true, "tier_prop": "cell_count", "tier": 1 },
	28: { "path": "res://scripts/world/furniture/Table.gd",  "is_script": true, "tier_prop": "cell_count", "tier": 2 },
	29: { "path": "res://scripts/world/furniture/Chair.gd",  "is_script": true },
	30: { "path": "res://scripts/world/cooking/Stove.gd",         "is_script": true },
	31: { "path": "res://scripts/world/furniture/Poster.gd", "is_script": true },
	32: { "path": "res://scripts/world/furniture/EndTable.gd", "is_script": true },
	33: { "path": "res://scripts/world/furniture/Dresser.gd",  "is_script": true },
	34: { "path": "res://scripts/world/furniture/SmallShelf.gd", "is_script": true },
	35: { "path": "res://scripts/world/furniture/LargeShelf.gd", "is_script": true },
	36: { "path": "res://scripts/world/furniture/TrashCan.gd", "is_script": true },
	37: { "path": "res://scripts/world/furniture/BuildStation.gd", "is_script": true },
	## NOT YET REGISTERED — flagged, not silently skipped (see testing
	## checklist item 5): TILE_LIGHT (5, WallLight.gd — wall-mounted,
	## no entry existed even before this plan), TILE_STOVE (30,
	## Stove.gd — added by the cooking-system Claude instance after this
	## plan's original wall work started). Both fall back to the old
	## generic-box path (or MeshLibrary path) until registered — same
	## graceful degradation as anything else not yet in this dict.
}

## Tiles with no meaningful "front" — skip the facing arrow entirely.
## Matches the existing exemption already in GhostPreview.gd's comments.
const NO_ARROW_TILES: Array[int] = []   ## Populated by caller with TILE_WALL/HALF/QUARTER/PILLAR/FLOOR — see Part 4 (can't reference BuildModeController's constants from this file directly; caller passes its own tile_id, this file just needs to know NOT to force an arrow on those — see attach_facing_arrow's tile_id param)

## Hand-tuned arrow placement overrides, preserved from the original
## per-tile _attach_ghost_direction_arrow() calls (z_offset, y_rotation_offset_deg).
## Anything not listed here gets the DEFAULT_ARROW_OFFSET fallback below —
## reasonable out of the box for new furniture, refine here later if needed.
const ARROW_OVERRIDES: Dictionary = {
	# tile_id: [z_offset, y_rotation_offset_deg]
	4:  [0.75, 90.0],    ## Bed
	3:  [0.6,  180.0],   ## Shelving (Medium) — model rotated to +Z-front convention (Aug 2026); arrow now standard
	34: [0.6,  180.0],   ## Small Shelf — same procedural-mesh facing as Medium
	35: [0.6,  180.0],   ## Large Shelf — same procedural-mesh facing as Medium
	6:  [0.0,  180.0],   ## Generator S (z_offset computed from size at call time — see Part 4)
	7:  [0.0,  180.0],   ## Generator M
	8:  [0.0,  180.0],   ## Generator L
}
const DEFAULT_ARROW_Y_ROT: float = 180.0   ## Most objects' real "front" is local +Z, opposite the arrow geometry's own base -Z direction. Tiles with a hand-tuned ARROW_OVERRIDES entry are unaffected — this only fills in when no entry exists.
const DEFAULT_ARROW_Z_MARGIN: float = 0.15   ## Added to an object's own half-extent for tiles with no override

## Builds a detached, side-effect-free instance of the REAL object script/
## scene. Sets _is_preview_only BEFORE add_child() (required — see each
## script's own comment on that var) so _ready() skips registration but
## still runs its real mesh-building code unmodified. Returns null if
## tile_id isn't registered or the resource fails to load — callers must
## treat null as "fall back to whatever this caller did before this file
## existed," never as an error.
static func build_real_instance(tile_id: int) -> Node3D:
	if not PROCEDURAL_PREVIEW_SOURCES.has(tile_id):
		return null
	var info: Dictionary = PROCEDURAL_PREVIEW_SOURCES[tile_id]
	var inst: Node3D = null
	if bool(info.get("is_script", false)):
		var script: GDScript = load(String(info["path"])) as GDScript
		if script == null:
			return null
		inst = script.new()
	else:
		var packed: PackedScene = load(String(info["path"])) as PackedScene
		if packed == null:
			return null
		inst = packed.instantiate() as Node3D
	if inst == null:
		return null

	inst.set("_is_preview_only", true)
	var tier_prop: String = String(info.get("tier_prop", ""))
	if not tier_prop.is_empty():
		inst.set(tier_prop, info["tier"])

	if inst is RigidBody3D:
		var rb: RigidBody3D = inst as RigidBody3D
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	return inst   ## strip_collision() call REMOVED from here — see GhostPreview.gd instead

## Forces every CollisionObject3D descendant (StaticBody3D, RigidBody3D,
## Area3D, etc.) to collide with nothing. Ghosts are visual-only — no
## script should need to remember to gate its own collision_layer behind
## _is_preview_only for this to be safe; this makes it safe universally,
## for every object registered in PROCEDURAL_PREVIEW_SOURCES, present and
## future.
## Renamed public (was _strip_collision_recursive) — MUST be called AFTER
## the instance has entered the tree (i.e. after add_child()), never
## before, or a script's own _ready() (which typically sets
## collision_layer unconditionally) will silently undo it. See this fix's
## own root-cause note for why the original placement was wrong.
static func strip_collision(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		strip_collision(child)

## Second-tier fallback for MeshLibrary-backed tiles (Pillar, Floor) that
## have no procedural script. Returns null if tile_id isn't a valid
## MeshLibrary item either — final fallback is still the caller's own
## generic-box logic, same graceful degradation as build_real_instance().
static func build_meshlibrary_instance(tile_id: int, gridmap: GridMap) -> Node3D:
	if gridmap == null or gridmap.mesh_library == null:
		return null
	var mesh: Mesh = gridmap.mesh_library.get_item_mesh(tile_id)
	if mesh == null:
		return null
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	return mi

## Recursively recolors every MeshInstance3D surface under `root` to
## translucent green (valid) or red (invalid), unshaded — completely
## replacing whatever real materials/textures the object normally has, so
## ANY object (however many mesh parts it's built from) reads as a clean
## ghost. Works for both a single MeshInstance3D and a full multi-mesh
## real-object subtree.
static func apply_ghost_tint(root: Node3D, valid: bool) -> void:
	if root == null:
		return
	var color: Color = Color(0.40, 1.00, 0.50, 0.45) if valid else Color(1.00, 0.35, 0.35, 0.45)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color  = color
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tint_recursive(root, mat)

static func _tint_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			for s: int in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat)
	for child: Node in node.get_children():
		_tint_recursive(child, mat)

## Universal front-facing direction arrow — cyan, always-visible, no depth
## test. Attaches under `root`. `half_extent` is the object's own footprint
## (from _tile_half_extents()) used to compute a sensible default offset for
## any tile without a hand-tuned ARROW_OVERRIDES entry, so new furniture
## gets a reasonably-placed arrow with zero extra work.
static func attach_facing_arrow(root: Node3D, tile_id: int, half_extent: Vector2, skip_tiles: Array[int] = []) -> void:
	if root == null or tile_id in skip_tiles:
		return
	for child: Node in root.get_children():
		if child.name == "_GhostArrow":
			child.queue_free()

	var z_offset: float = half_extent.y + DEFAULT_ARROW_Z_MARGIN
	var y_rot: float = DEFAULT_ARROW_Y_ROT   ## was 0.0
	if ARROW_OVERRIDES.has(tile_id):
		var ov: Array = ARROW_OVERRIDES[tile_id]
		z_offset = ov[0] if ov[0] > 0.0 else z_offset   ## 0.0 override means "use computed default"
		y_rot    = ov[1]

	var arrow_root: Node3D = Node3D.new()
	arrow_root.name = "_GhostArrow"

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color               = Color(0.30, 0.90, 1.0, 0.85)
	mat.emission_enabled           = true
	mat.emission                   = Color(0.30, 0.90, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.6
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode                = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test               = true
	mat.render_priority              = 2

	const SHAFT_LEN: float = 0.28
	const SHAFT_W:   float = 0.055
	const SHAFT_H:   float = 0.04
	var shaft_mi: MeshInstance3D = MeshInstance3D.new()
	var shaft_box: BoxMesh = BoxMesh.new()
	shaft_box.size = Vector3(SHAFT_W, SHAFT_H, SHAFT_LEN)
	shaft_mi.mesh  = shaft_box
	shaft_mi.position = Vector3(0.0, 0.05, -(z_offset + SHAFT_LEN * 0.5))
	shaft_mi.set_surface_override_material(0, mat)
	arrow_root.add_child(shaft_mi)

	const HEAD_R: float = 0.10
	const HEAD_H: float = 0.06
	var head_mi: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius      = 0.0
	cone.bottom_radius   = HEAD_R
	cone.height          = HEAD_H
	cone.radial_segments = 4
	cone.rings           = 1
	head_mi.mesh = cone
	head_mi.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	head_mi.position = Vector3(0.0, 0.05, -(z_offset + SHAFT_LEN + HEAD_H * 0.5))
	head_mi.set_surface_override_material(0, mat)
	arrow_root.add_child(head_mi)

	if y_rot != 0.0:
		arrow_root.rotation_degrees = Vector3(0.0, y_rot, 0.0)

	root.add_child(arrow_root)