extends PickupableItem
class_name SeedItem
## SeedItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §5.4/§8. ONE script for every species via export var
## seed_type (mirrors PurifierFilterItem.gd's one-script convention). Sold
## via the Farming toolbar tool's shop — $25 per purchase spawns 1 instance
## holding 4 charges (Fertilizer/Charges plan — see FarmingShopHelper.gd).
##
## on_use() while held: finds the nearest FarmingTray in range with an open
## plantable cell (soiled, unplanted), plants into it, consumes one charge.

@export var seed_type: String = "tomato"   ## "tomato" or "onion"

const TRAY_RANGE: float = 2.5

const MAX_CHARGES: int = 4
var _charges: int = MAX_CHARGES
var _max_charges: int = MAX_CHARGES   ## Matches InventoryHUD's fallback field names exactly

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "seed"   ## Shared slot key for both types, same
## reasoning PurifierFilterItem.gd uses (shared shelf_item_type, per-instance
## state — here seed_type — preserved by Shelving.gd's real-node-reference slots).

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

	_update_target_highlight(_find_nearest_plantable_tray())

## Group 5 item 12 — swaps the pulsing highlight to whichever tray is
## currently the nearest valid plant target (or clears it if none/dropped).
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
	return "%s Seed" % PlantDatabase.get_display_name(seed_type)

func get_prompt_text() -> String:
	return "[F] Pick up  %s (%d/%d)" % [get_display_name(), _charges, _max_charges]

func _find_nearest_plantable_tray() -> FarmingTray:
	var best: FarmingTray = null
	var best_dist: float = TRAY_RANGE
	for node: Node in get_tree().get_nodes_in_group("farming_tray"):
		if node is FarmingTray and (node as FarmingTray).has_open_plantable_cell():
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = node as FarmingTray
	return best

func get_use_prompt() -> String:
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray == null:
		return ""
	return "[E] Plant %s (%d/%d)" % [PlantDatabase.get_display_name(seed_type), _charges, _max_charges]

func on_use() -> void:
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray == null:
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("No tray ready to plant nearby")
		return

	if not tray.plant_first_open_cell(seed_type):
		return

	_charges -= 1
	charge_changed.emit()
	_update_target_highlight(null)

	if _charges <= 0:
		queue_free()   ## No "empty packet" object — seeds don't have one, unlike soil/fertilizer bags

## Small flat packet placeholder, tinted per seed_type so the two types are
## visually distinguishable on the ground. Includes a centered text label.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.10, 0.02, 0.14)
	_mesh.mesh = box
	_mesh.position = Vector3(0.0, 0.01, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = PlantDatabase.get_seed_packet_color(seed_type)
	mat.roughness    = 0.85
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	## Text label — centered on the packet, 2/3 up its length.
	var label: Label3D = Label3D.new()
	label.text = "%s Seeds" % PlantDatabase.get_display_name(seed_type)
	label.font_size = 6
	label.scale = Vector3(0.001, 0.001, 0.001)
	label.modulate = Color(0.95, 0.92, 0.78, 1.0)
	label.outline_size = 0
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.width = 90
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	label.fixed_size = false
	label.position = Vector3(0.0, 0.025, -0.023)
	label.rotation.x = -PI / 2.0
	add_child(label)

	## Real collision shape on the RigidBody3D itself (NOT
	## MeshInstance3D.create_trimesh_collision(), which nests a separate
	## StaticBody3D under the mesh and leaves this RigidBody3D with no
	## collider at all — it would fall through the floor forever and be
	## invisible to the interaction system's body-detection). Mirrors
	## PurifierFilterItem.tscn's CollisionShape3D-as-direct-child pattern.
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	shape.position = _mesh.position
	add_child(shape)

## Spawn helper (used by FarmingShopHelper — one instance per purchase, now
## holding 4 charges instead of spawning 4 separate physical items).
static func spawn_at(parent: Node, base_pos: Vector3, type: String) -> SeedItem:
	var item: SeedItem = SeedItem.new()
	item.seed_type = type
	var offset: Vector3 = Vector3(randf_range(-0.30, 0.30), 0.0, randf_range(-0.30, 0.30))
	parent.add_child(item)
	item.global_position = base_pos + offset
	return item
