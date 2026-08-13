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
## charge. Drops an EmptyFertilizerBottleItem when the last charge is used —
## Aug 2026 fix, previously (incorrectly) dropped a copy-pasted EmptyBagItem
## (a soil-bag-shaped prop) instead of anything bottle-shaped.

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
		EmptyFertilizerBottleItem.spawn_at(get_parent(), tray.global_position)
		queue_free()

## Bottle model — cylindrical fertilizer bottle matching the reference image.
## Body + tapered shoulder + narrow neck + cap. Tinted per tier: grey-green
## for Normal, purple for Pro. All CylinderMesh primitives.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.position = Vector3(0.0, 0.14, 0.0)

	var body_color: Color = Color(0.45, 0.20, 0.55, 1.0) if tier == "pro" \
		else Color(0.20, 0.52, 0.28, 1.0)
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body_mat.roughness    = 0.75
	body_mat.metallic     = 0.05

	var cap_mat: StandardMaterial3D = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.90, 0.90, 0.90, 1.0)
	cap_mat.roughness    = 0.60
	cap_mat.metallic     = 0.0

	var label_mat: StandardMaterial3D = StandardMaterial3D.new()
	label_mat.albedo_color = Color(0.92, 0.92, 0.88, 1.0)
	label_mat.roughness    = 0.80
	label_mat.metallic     = 0.0

	## Main body — wide cylinder.
	var body: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius    = 0.065
	body_mesh.bottom_radius = 0.065
	body_mesh.height        = 0.18
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.0, 0.0)
	body.set_surface_override_material(0, body_mat)
	_mesh.add_child(body)

	## Shoulder — tapers from body width to neck width.
	var shoulder: MeshInstance3D = MeshInstance3D.new()
	var shoulder_mesh: CylinderMesh = CylinderMesh.new()
	shoulder_mesh.top_radius    = 0.025
	shoulder_mesh.bottom_radius = 0.065
	shoulder_mesh.height        = 0.04
	shoulder.mesh = shoulder_mesh
	shoulder.position = Vector3(0.0, 0.11, 0.0)
	shoulder.set_surface_override_material(0, body_mat)
	_mesh.add_child(shoulder)

	## Neck — narrow cylinder.
	var neck: MeshInstance3D = MeshInstance3D.new()
	var neck_mesh: CylinderMesh = CylinderMesh.new()
	neck_mesh.top_radius    = 0.025
	neck_mesh.bottom_radius = 0.025
	neck_mesh.height        = 0.035
	neck.mesh = neck_mesh
	neck.position = Vector3(0.0, 0.145, 0.0)
	neck.set_surface_override_material(0, body_mat)
	_mesh.add_child(neck)

	## Cap — slightly wider than neck, white/grey.
	var cap: MeshInstance3D = MeshInstance3D.new()
	var cap_mesh: CylinderMesh = CylinderMesh.new()
	cap_mesh.top_radius    = 0.03
	cap_mesh.bottom_radius = 0.03
	cap_mesh.height        = 0.015
	cap.mesh = cap_mesh
	cap.position = Vector3(0.0, 0.17, 0.0)
	cap.set_surface_override_material(0, cap_mat)
	_mesh.add_child(cap)

	## Label — thin flat box on the front face.
	var label: MeshInstance3D = MeshInstance3D.new()
	label.mesh = BoxMesh.new()
	(label.mesh as BoxMesh).size = Vector3(0.08, 0.10, 0.005)
	label.position = Vector3(0.0, 0.02, 0.066)
	label.set_surface_override_material(0, label_mat)
	_mesh.add_child(label)

	add_child(_mesh)

	## Collision — single cylinder matching overall bounding volume.
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cyl_shape: CylinderShape3D = CylinderShape3D.new()
	cyl_shape.radius = 0.065
	cyl_shape.height = 0.34
	shape.shape = cyl_shape
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
