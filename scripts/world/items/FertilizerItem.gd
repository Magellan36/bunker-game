extends PickupableItem
class_name FertilizerItem
## FertilizerItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System — Fertilizer plan. ONE script for both tiers via
## export var tier ("normal"/"pro"), same one-script-per-item-family
## convention SeedItem.gd/PurifierFilterItem.gd already establish.
##
## on_use() while held: finds the nearest FarmingTray in range with an open
## (growing, not-yet-fertilized) cell, applies fertilizer to it, consumes one
## charge. Drops an EmptyBagItem when the last charge is used, mirroring
## BagOfSoilItem's empty-container pattern.

@export var tier: String = "normal"   ## "normal" or "pro"

const MAX_CHARGES: int = 4
var _charges: int = MAX_CHARGES
var _max_charges: int = MAX_CHARGES   ## Matches InventoryHUD's fallback field names exactly

## Proximity range for finding the nearest tray — same value as
## PurifierFilterItem.REPLACE_RANGE / FarmingTray.REPLACE_RANGE.
const TRAY_RANGE: float = 2.5

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "fertilizer"   ## Shared slot for both tiers — per-
## instance `tier` preserved by Shelving.gd's real-node-reference slots, same
## reasoning PurifierFilterItem/SeedItem/FarmProduceItem already use.

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

	_update_target_highlight(_find_nearest_fertilizable_tray())

## Group 5 item 12 — swaps the pulsing highlight to whichever tray is
## currently the nearest valid fertilize target (or clears it if none/dropped).
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

## Bonus values, per confirmed numbers: +12.5% normal, +25% pro.
static func get_growth_bonus(fert_tier: String) -> float:
	return 0.25 if fert_tier == "pro" else 0.125

func get_display_name() -> String:
	return "Pro Fertilizer" if tier == "pro" else "Normal Fertilizer"

func get_prompt_text() -> String:
	return "[F] Pick up  %s (%d/%d)" % [get_display_name(), _charges, _max_charges]

func _find_nearest_fertilizable_tray() -> FarmingTray:
	var best: FarmingTray = null
	var best_dist: float = TRAY_RANGE
	for node: Node in get_tree().get_nodes_in_group("farming_tray"):
		if node is FarmingTray and (node as FarmingTray).has_open_fertilizable_cell():
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = node as FarmingTray
	return best

## Narrower query, used only to give a specific "already fertilized" toast
## instead of a generic "nothing nearby" one when that's the actual reason.
func _find_nearest_tray_with_already_fertilized_plant() -> FarmingTray:
	var best: FarmingTray = null
	var best_dist: float = TRAY_RANGE
	for node: Node in get_tree().get_nodes_in_group("farming_tray"):
		if node is FarmingTray and (node as FarmingTray).has_already_fertilized_growing_cell():
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = node as FarmingTray
	return best

func get_use_prompt() -> String:
	var tray: FarmingTray = _find_nearest_fertilizable_tray()
	if tray == null:
		return ""
	return "[E] Apply Fertilizer (%d/%d)" % [_charges, _max_charges]

func on_use() -> void:
	var tray: FarmingTray = _find_nearest_fertilizable_tray()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			if _find_nearest_tray_with_already_fertilized_plant() != null:
				hud.show_soft_warning("This plant is already fertilized")
			else:
				hud.show_soft_warning("No growing plant nearby to fertilize")
		return

	if not tray.fertilize_first_open_cell(tier):
		return   ## Shouldn't happen given the has_open_fertilizable_cell() check above, but stay defensive

	_charges -= 1
	charge_changed.emit()
	_update_target_highlight(null)

	if _charges <= 0:
		EmptyBagItem.spawn_at(get_parent(), tray.global_position)
		queue_free()

## Placeholder sack model, copied from BagOfSoilItem's shape/collision setup,
## tinted per tier so the two are visually distinguishable on a shelf/floor:
## darker "chemical" grey-green for Normal, richer saturated green for Pro.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.26, 0.20, 0.16)
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.10, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.62, 0.20, 1.0) if tier == "pro" else Color(0.40, 0.45, 0.32, 1.0)
	mat.roughness    = 0.90
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself — see SeedItem.gd's
	## _build_placeholder_mesh() comment for why create_trimesh_collision()
	## was wrong here (no collider on this body at all -> infinite fall,
	## undetectable by the interaction system).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = _mesh.position
	add_child(shape)

## Spawn helper (used by FarmingShopHelper for shop purchases). Mirrors
## SeedItem.spawn_at()'s shape — floor-dropped, not auto-added to inventory,
## small random horizontal offset.
static func spawn_at(parent: Node, base_pos: Vector3, fert_tier: String) -> FertilizerItem:
	var item: FertilizerItem = FertilizerItem.new()
	item.tier = fert_tier
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item
