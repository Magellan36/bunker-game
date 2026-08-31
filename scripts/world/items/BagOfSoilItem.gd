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

func get_trash_material() -> String:
	return "organic" if _charges >= _max_charges else "plastic"

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

## Aug 2026 per-cell interaction pass — targets the single tray cell
## nearest to this held item (== roughly the player's hand position), not
## "the tray's first open cell". A double tray fills whichever side the
## player is standing closer to.
## Job Progress Bar (Aug 2026) — split into a trigger (this) and a
## completion (_finish_fill_soil()); the actual fill_soil_at_cell() call +
## charge decrement + possible self-consumption are deferred to job
## completion, so a cancelled job leaves the bag/tray untouched.
func on_use() -> void:
	var tray: FarmingTray = _find_nearest_tray_needing_soil()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray needing soil nearby")
		return

	var cell_index: int = tray.nearest_open_soil_cell_to(global_position)
	if cell_index < 0:
		return

	var isys: Node = _hold_point.get_parent() if _hold_point != null else null
	if isys == null or not isys.has_method("start_job"):
		return
	isys.start_job(tray, InteractionSystem.JOB_DEFAULT_DURATION, Callable(self, "_finish_fill_soil").bind(tray, cell_index), "Filling Soil...", TRAY_RANGE)

func _finish_fill_soil(tray: FarmingTray, cell_index: int) -> void:
	if not is_instance_valid(tray) or not tray.fill_soil_at_cell(cell_index):
		return

	_charges -= 1
	charge_changed.emit()
	_update_target_highlight(null)

	if _charges <= 0:
		EmptyBagItem.spawn_at(get_parent(), tray.global_position)
		queue_free()

## Aug 2026 (NPC Gardening thread) — index-aware counterpart to on_use(),
## for callers that have already resolved a SPECIFIC cell (e.g. via a
## per-cell claim) rather than "nearest cell to my own position." Mirrors
## on_use() exactly — same charge decrement, same signal, same
## EmptyBagItem-at-zero cleanup — just targets fill_soil_at_cell(cell_index)
## instead of resolving a cell itself. Flag to the Farming thread if this
## doesn't fit however fill_soil_at_cell() ends up shaped.
func apply_at_cell(tray: FarmingTray, cell_index: int) -> bool:
	if not tray.fill_soil_at_cell(cell_index):
		return false
	_charges -= 1
	charge_changed.emit()
	_update_target_highlight(null)
	if _charges <= 0:
		EmptyBagItem.spawn_at(get_parent(), tray.global_position)
		queue_free()
	return true

## Bag model — upright sealed soil bag matching the reference image.
## Built from BoxMesh primitives: a puffy middle body, a narrower sealed
## top, and a flat bottom base. Light brown / burlap color.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.position = Vector3(0.0, 0.15, 0.0)

	var bag_mat: StandardMaterial3D = StandardMaterial3D.new()
	bag_mat.albedo_color = Color(0.62, 0.53, 0.38, 1.0)
	bag_mat.roughness    = 0.92
	bag_mat.metallic     = 0.0

	var seam_mat: StandardMaterial3D = StandardMaterial3D.new()
	seam_mat.albedo_color = Color(0.55, 0.46, 0.32, 1.0)
	seam_mat.roughness    = 0.90
	seam_mat.metallic     = 0.0

	## Main body — puffy middle section, widest part of the bag.
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = BoxMesh.new()
	(body.mesh as BoxMesh).size = Vector3(0.22, 0.20, 0.12)
	body.position = Vector3(0.0, 0.0, 0.0)
	body.set_surface_override_material(0, bag_mat)
	_mesh.add_child(body)

	## Sealed top — narrower, crimped/folded over.
	var top: MeshInstance3D = MeshInstance3D.new()
	top.mesh = BoxMesh.new()
	(top.mesh as BoxMesh).size = Vector3(0.18, 0.08, 0.10)
	top.position = Vector3(0.0, 0.12, 0.0)
	top.set_surface_override_material(0, bag_mat)
	_mesh.add_child(top)

	## Top seam — thin dark strip where the bag is heat-sealed.
	var top_seam: MeshInstance3D = MeshInstance3D.new()
	top_seam.mesh = BoxMesh.new()
	(top_seam.mesh as BoxMesh).size = Vector3(0.18, 0.01, 0.10)
	top_seam.position = Vector3(0.0, 0.085, 0.0)
	top_seam.set_surface_override_material(0, seam_mat)
	_mesh.add_child(top_seam)

	## Bottom base — flat, slightly inset.
	var base: MeshInstance3D = MeshInstance3D.new()
	base.mesh = BoxMesh.new()
	(base.mesh as BoxMesh).size = Vector3(0.22, 0.02, 0.12)
	base.position = Vector3(0.0, -0.10, 0.0)
	base.set_surface_override_material(0, seam_mat)
	_mesh.add_child(base)

	## Side bulge strips — thin boxes on left/right faces to suggest
	## the puffy, filled-bag curve without using rounded geometry.
	for sign_x: int in [-1, 1]:
		var strip: MeshInstance3D = MeshInstance3D.new()
		strip.mesh = BoxMesh.new()
		(strip.mesh as BoxMesh).size = Vector3(0.015, 0.18, 0.10)
		strip.position = Vector3(sign_x * 0.11, 0.0, 0.0)
		strip.set_surface_override_material(0, bag_mat)
		_mesh.add_child(strip)

	add_child(_mesh)

	## Collision — single box matching overall bounding volume.
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(0.22, 0.30, 0.12)
	shape.shape = box_shape
	shape.position = _mesh.position
	add_child(shape)

## Spawn helper (used by FarmingShopHelper for shop purchases). Mirrors
## PurifierFilterItem.spawn_at()'s shape — floor-dropped, not auto-added to
## inventory, small random horizontal offset.
static func spawn_at(parent: Node, base_pos: Vector3) -> BagOfSoilItem:
	var item: BagOfSoilItem = BagOfSoilItem.new()
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item
