extends PickupableItem
class_name BagOfSoilItem
## BagOfSoilItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §5.4/§8. Pickupable consumable — sold via the Farming
## toolbar tool's shop ($100, spawns 1 instance above the player's head).
##
## on_use() while held: finds the nearest FarmingTray in range with an open
## soil cell, fills it, consumes this bag, and drops an EmptyBagItem near the
## tray (mirrors PurifierFilterItem.spawn_at()'s "drop near position, not
## auto-added to inventory" pattern).

# ─── Config ───────────────────────────────────────────────────────────────────
## Proximity range for finding the nearest tray — same value as
## PurifierFilterItem.REPLACE_RANGE / FarmingTray.REPLACE_RANGE.
const TRAY_RANGE: float = 2.5

const MAX_CHARGES: int = 2
var _charges: int = MAX_CHARGES
var _max_charges: int = MAX_CHARGES   ## Matches InventoryHUD's fallback field names exactly

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "bag_of_soil"

## Nearest-valid-tray highlight (Group 5 item 12) — recomputed every physics
## frame while held, only toggled on the tray objects when the target changes.
var _highlighted_tray: FarmingTray = null

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		_update_target_highlight(null)
		return

	super._physics_process(delta)

	_update_target_highlight(_find_nearest_tray_needing_soil())

## Group 5 item 12 — swaps the pulsing highlight to whichever tray is
## currently the nearest valid soil target (or clears it if none/dropped).
func _update_target_highlight(new_target: FarmingTray) -> void:
	if new_target == _highlighted_tray:
		return
	if _highlighted_tray != null and is_instance_valid(_highlighted_tray):
		_highlighted_tray.set_target_highlighted(false)
	_highlighted_tray = new_target
	if _highlighted_tray != null:
		_highlighted_tray.set_target_highlighted(true)

func _on_drop_extra() -> void:
	_update_target_highlight(null)

func get_display_name() -> String:
	return "Bag of Soil"

func get_prompt_text() -> String:
	return "[F] Pick up  Bag of Soil (%d/%d)" % [_charges, _max_charges]

func _find_nearest_tray_needing_soil() -> FarmingTray:
	var best: FarmingTray = null
	var best_dist: float = TRAY_RANGE
	for node: Node in get_tree().get_nodes_in_group("farming_tray"):
		if node is FarmingTray and (node as FarmingTray).has_open_soil_cell():
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = node as FarmingTray
	return best

func get_use_prompt() -> String:
	var tray: FarmingTray = _find_nearest_tray_needing_soil()
	if tray == null:
		return ""
	return "[E] Fill Tray with Soil"

func on_use() -> void:
	var tray: FarmingTray = _find_nearest_tray_needing_soil()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray needing soil nearby")
		return

	if not tray.fill_first_open_soil_cell():
		return

	_charges -= 1
	charge_changed.emit()
	_update_target_highlight(null)

	if _charges <= 0:
		EmptyBagItem.spawn_at(get_parent(), tray.global_position)
		queue_free()

## Sack model — rounded-box burlap sack with soft edges, matching the
## reference image. Straight/stiff, not floppy. Uses SurfaceTool to build
## a subdivided box with corner rounding.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _make_sack_mesh(Vector3(0.26, 0.20, 0.16), 3, 0.035)
	_mesh.position = Vector3(0.0, 0.10, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.53, 0.38, 1.0)
	mat.roughness    = 0.92
	mat.metallic     = 0.0
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself — see SeedItem.gd's
	## _build_placeholder_mesh() comment for why create_trimesh_collision()
	## was wrong here (no collider on this body at all -> infinite fall,
	## undetectable by the interaction system).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(0.26, 0.20, 0.16)
	shape.shape = box_shape
	shape.position = _mesh.position
	add_child(shape)

## Generates a rounded-box mesh (pillow sack shape) via SurfaceTool.
## `size` is the full bounding-box dimensions, `segs` is subdivisions per
## face edge (more = smoother corners), `radius` is the corner round-off.
static func _make_sack_mesh(size: Vector3, segs: int, radius: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs: Vector3 = size * 0.5
	var r: float = minf(radius, minf(hs.x, minf(hs.y, hs.z)))
	## 6 face definitions: [face_normal, tangent_u, tangent_v].
	var face_defs: Array = [
		[Vector3.RIGHT,   Vector3.UP,     Vector3.FORWARD],
		[Vector3.LEFT,    Vector3.UP,     Vector3.FORWARD],
		[Vector3.UP,      Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.DOWN,    Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.FORWARD, Vector3.UP,     Vector3.RIGHT],
		[Vector3.BACK,    Vector3.UP,     Vector3.RIGHT]]
	var n: int = segs
	for face: Array in face_defs:
		var face_dir: Vector3 = face[0]
		for i: int in n:
			for j: int in n:
				var quad: Array[Vector3] = []
				var quad_n: Array[Vector3] = []
				for di: int in [0, 1]:
					for dj: int in [0, 1]:
						var pu: float = float(i + di) / float(n) * 2.0 - 1.0
						var pv: float = float(j + dj) / float(n) * 2.0 - 1.0
						var pos: Vector3 = Vector3.ZERO
						if face_dir == Vector3.RIGHT or face_dir == Vector3.LEFT:
							pos = Vector3(face_dir.x * hs.x, pu * (hs.y - r), pv * (hs.z - r))
						elif face_dir == Vector3.UP or face_dir == Vector3.DOWN:
							pos = Vector3(pu * (hs.x - r), face_dir.y * hs.y, pv * (hs.z - r))
						else:
							pos = Vector3(pu * (hs.x - r), pv * (hs.y - r), face_dir.z * hs.z)
						var corner_vec: Vector3 = pos - Vector3(
							clampf(pos.x, -hs.x + r, hs.x - r),
							clampf(pos.y, -hs.y + r, hs.y - r),
							clampf(pos.z, -hs.z + r, hs.z - r))
						quad.append(pos)
						quad_n.append(corner_vec.normalized() if corner_vec.length_squared() > 0.001 else face_dir)
				for tri: Array in [[0, 1, 2], [1, 3, 2]]:
					for k: int in tri:
						st.set_normal(quad_n[k])
						st.add_vertex(quad[k])
	var arrays: Array = st.commit_to_arrays()
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Spawn helper (used by FarmingShopHelper for shop purchases). Mirrors
## PurifierFilterItem.spawn_at()'s shape — floor-dropped, not auto-added to
## inventory, small random horizontal offset.
static func spawn_at(parent: Node, base_pos: Vector3) -> BagOfSoilItem:
	var item: BagOfSoilItem = BagOfSoilItem.new()
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item
