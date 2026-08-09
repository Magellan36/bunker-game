extends PickupableItem
class_name FarmProduceItem
## FarmProduceItem.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §7. ONE script for both tomato/onion produce via
## export var. 1-charge, fully consumed in one on_use() call, no partial-
## bite tracking like WaterBottle's continuous-mL model.
##
## Species whose produce can be planted back into a tray instead of eaten,
## in addition to being buyable as a packet. Mirrors SeedItem.gd's plant flow.
const REPLANTABLE_TYPES: Array[String] = ["potato", "onion", "garlic"]

const TRAY_RANGE: float = 2.5   ## Matches SeedItem.gd's TRAY_RANGE

@export var produce_type: String = "tomato"   ## "tomato" or "onion"

## Flat hunger restore per produce item — same order of magnitude as
## FoodCan's per-bite value (12.5), used whole here since this is a single
## 1-charge item rather than a 2-bite can.
const FOOD_RESTORE: float = 20.0

## Visual scale per produce type — most items 2x, large items (corn, carrot,
## pumpkin) 3x. Applied to the MeshInstance3D only, collision stays at the
## original radius for gameplay consistency.
const PRODUCE_SCALE: Dictionary = {
	"tomato": 2.0, "onion": 2.0, "basil": 2.0, "strawberry": 2.0,
	"carrot": 3.0, "chili_pepper": 2.0, "bell_pepper": 2.0, "garlic": 2.0,
	"potato": 2.0, "blueberry": 2.0, "corn": 3.0, "pumpkin": 3.0,
}

var shelf_stack_limit: int  = 6
var shelf_item_type: String = "farm_produce"   ## Shared slot for both types —
## per-instance produce_type preserved by Shelving.gd's real-node-reference
## slots, same reasoning as PurifierFilterItem/SeedItem.

var _player_stats: Node     = null
var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("basket_storable")
	add_to_group("cookpot_storable")
	_mesh = get_node_or_null("MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_display_name() -> String:
	return PlantDatabase.get_display_name(produce_type)

func get_prompt_text() -> String:
	return "[F] Pick up  %s" % get_display_name()

func _find_nearest_plantable_tray() -> FarmingTray:
	if not (produce_type in REPLANTABLE_TYPES):
		return null
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
	var pot: CookingPot = CookingPot.find_nearest_open_pot(global_position, get_tree())
	if pot != null:
		var preview: Dictionary = pot.preview_add(self)
		if not preview.is_empty():
			var bonus_txt: String = "" if preview["bonus_pct"] <= 0.0 else "  (+%d%% Diversity)" % int(round(preview["bonus_pct"] * 100.0))
			return "[E] Add to Pot  →  %.1f Filling%s" % [preview["total"], bonus_txt]
	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray != null:
		return "[E] Plant %s" % get_display_name()
	return "[E] Eat  %s" % get_display_name()

## Fully consumed in one call — no charge tracking, no empty-state.
func on_use() -> void:
	var pot: CookingPot = CookingPot.find_nearest_open_pot(global_position, get_tree())
	if pot != null:
		if pot.try_add_item(self):
			CookingPot.release_from_player_hand(get_tree(), self)
			return

	var tray: FarmingTray = _find_nearest_plantable_tray()
	if tray != null:
		if tray.plant_first_open_cell(produce_type):
			queue_free()
		return

	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("FarmProduceItem: _player_stats not found.")
		return
	_player_stats.replenish_food(consume_as_food())

## Consumes this produce (frees the node) and returns the food restored.
## Shared mutation for player + NPCs (NPC Pass 2, Part 3).
func consume_as_food() -> float:
	queue_free()
	return FOOD_RESTORE

## Unique mesh per produce type — replaces the generic sphere with shapes
## that read as their real-life fruits/vegetables at a glance.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = PlantDatabase.get_produce_color(produce_type)
	mat.metallic     = PlantDatabase.get_produce_metallic(produce_type)
	mat.roughness    = PlantDatabase.get_produce_roughness(produce_type)

	match produce_type:
		"tomato":
			_build_tomato(mat)
		"onion":
			_build_onion(mat)
		"basil":
			_build_basil(mat)
		"strawberry":
			_build_strawberry(mat)
		"carrot":
			_build_carrot(mat)
		"chili_pepper":
			_build_chili_pepper(mat)
		"bell_pepper":
			_build_bell_pepper(mat)
		"garlic":
			_build_garlic(mat)
		"potato":
			_build_potato(mat)
		"blueberry":
			_build_blueberry(mat)
		"corn":
			_build_corn(mat)
		"pumpkin":
			_build_pumpkin(mat)
		_:
			_build_generic_sphere(mat)

	## Apply visual scale (2x default, 3x for corn/carrot/pumpkin)
	var scale_factor: float = PRODUCE_SCALE.get(produce_type, 2.0)
	_mesh.scale = Vector3.ONE * scale_factor

	add_child(_mesh)

	## Real collision shape on the RigidBody3D itself — see SeedItem.gd's
	## _build_placeholder_mesh() comment for why create_trimesh_collision()
	## was wrong here (no collider on this body at all -> infinite fall,
	## undetectable by the interaction system).
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = 0.055
	shape.shape = sphere_shape
	shape.position = _mesh.position
	add_child(shape)

## Tomato — round sphere with small green stem cylinder on top
func _build_tomato(mat: StandardMaterial3D) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.10
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.055, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Green stem
	var stem_mi: MeshInstance3D = MeshInstance3D.new()
	var stem: CylinderMesh = CylinderMesh.new()
	stem.top_radius = 0.006
	stem.bottom_radius = 0.008
	stem.height = 0.02
	stem.radial_segments = 6
	stem_mi.mesh = stem
	stem_mi.position = Vector3(0.0, 0.11, 0.0)
	var stem_mat: StandardMaterial3D = StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.25, 0.55, 0.15, 1.0)
	stem_mat.roughness = 0.7
	stem_mi.set_surface_override_material(0, stem_mat)
	_mesh.add_child(stem_mi)

## Onion — sphere with pointed top (tapered upper half)
func _build_onion(mat: StandardMaterial3D) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.10
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.05, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Small pointed tip on top (divide position by 2x scale)
	var tip_mi: MeshInstance3D = MeshInstance3D.new()
	var tip: CylinderMesh = CylinderMesh.new()
	tip.top_radius = 0.003
	tip.bottom_radius = 0.012
	tip.height = 0.025
	tip.radial_segments = 6
	tip_mi.mesh = tip
	tip_mi.position = Vector3(0.0, 0.105 / 2.0, 0.0)
	tip_mi.set_surface_override_material(0, mat)
	_mesh.add_child(tip_mi)

## Basil — small cluster of 3 flat leaf-like boxes
func _build_basil(mat: StandardMaterial3D) -> void:
	## Stem
	var stem_mi: MeshInstance3D = MeshInstance3D.new()
	var stem: CylinderMesh = CylinderMesh.new()
	stem.top_radius = 0.004
	stem.bottom_radius = 0.005
	stem.height = 0.06
	stem.radial_segments = 6
	stem_mi.mesh = stem
	stem_mi.position = Vector3(0.0, 0.03, 0.0)
	var stem_mat: StandardMaterial3D = StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.18, 0.45, 0.12, 1.0)
	stem_mat.roughness = 0.7
	stem_mi.set_surface_override_material(0, stem_mat)
	_mesh.add_child(stem_mi)

	## 3 leaves fanning out
	for i in range(3):
		var leaf_mi: MeshInstance3D = MeshInstance3D.new()
		var leaf: BoxMesh = BoxMesh.new()
		leaf.size = Vector3(0.035, 0.004, 0.05)
		leaf_mi.mesh = leaf
		var angle: float = TAU * i / 3.0
		leaf_mi.position = Vector3(cos(angle) * 0.018, 0.065, sin(angle) * 0.018)
		leaf_mi.rotation.y = angle
		leaf_mi.set_surface_override_material(0, mat)
		_mesh.add_child(leaf_mi)

	_mesh.mesh = BoxMesh.new()
	_mesh.mesh.size = Vector3(0.001, 0.001, 0.001)
	_mesh.position = Vector3(0.0, 0.0, 0.0)

## Strawberry — cone/tapered shape with small seed dots
func _build_strawberry(mat: StandardMaterial3D) -> void:
	## Main body — tapered cylinder (wider at top, narrow at bottom)
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body: CylinderMesh = CylinderMesh.new()
	body.top_radius = 0.04
	body.bottom_radius = 0.012
	body.height = 0.09
	body.radial_segments = 10
	body_mi.mesh = body
	body_mi.position = Vector3(0.0, 0.045, 0.0)
	body_mi.set_surface_override_material(0, mat)
	_mesh.mesh = body
	_mesh.position = Vector3(0.0, 0.045, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Green leafy top (calyx)
	var leaf_mat: StandardMaterial3D = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.20, 0.50, 0.12, 1.0)
	leaf_mat.roughness = 0.7
	for i in range(5):
		var leaf_mi: MeshInstance3D = MeshInstance3D.new()
		var leaf: BoxMesh = BoxMesh.new()
		leaf.size = Vector3(0.012, 0.003, 0.025)
		leaf_mi.mesh = leaf
		var angle: float = TAU * i / 5.0
		leaf_mi.position = Vector3(cos(angle) * 0.02, 0.092, sin(angle) * 0.02)
		leaf_mi.rotation.y = angle
		leaf_mi.set_surface_override_material(0, leaf_mat)
		_mesh.add_child(leaf_mi)

## Carrot — long tapered cylinder (wider at top, pointed at bottom)
func _build_carrot(mat: StandardMaterial3D) -> void:
	var body: CylinderMesh = CylinderMesh.new()
	body.top_radius = 0.022
	body.bottom_radius = 0.004
	body.height = 0.12
	body.radial_segments = 8
	_mesh.mesh = body
	_mesh.position = Vector3(0.0, 0.06, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Green leafy top
	var leaf_mat: StandardMaterial3D = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.22, 0.52, 0.15, 1.0)
	leaf_mat.roughness = 0.7
	for i in range(3):
		var leaf_mi: MeshInstance3D = MeshInstance3D.new()
		var leaf: CylinderMesh = CylinderMesh.new()
		leaf.top_radius = 0.003
		leaf.bottom_radius = 0.003
		leaf.height = 0.04
		leaf.radial_segments = 4
		leaf_mi.mesh = leaf
		var angle: float = TAU * i / 3.0
		leaf_mi.position = Vector3(cos(angle) * 0.01, 0.125, sin(angle) * 0.01)
		leaf_mi.set_surface_override_material(0, leaf_mat)
		_mesh.add_child(leaf_mi)

## Chili pepper — long thin curved capsule
func _build_chili_pepper(mat: StandardMaterial3D) -> void:
	var body: CapsuleMesh = CapsuleMesh.new()
	body.radius = 0.012
	body.height = 0.10
	_mesh.mesh = body
	_mesh.position = Vector3(0.0, 0.05, 0.0)
	_mesh.rotation.z = 0.25   ## slight curve
	_mesh.set_surface_override_material(0, mat)

	## Small green stem
	var stem_mi: MeshInstance3D = MeshInstance3D.new()
	var stem: CylinderMesh = CylinderMesh.new()
	stem.top_radius = 0.004
	stem.bottom_radius = 0.006
	stem.height = 0.015
	stem.radial_segments = 6
	stem_mi.mesh = stem
	stem_mi.position = Vector3(0.0, 0.102, 0.0)
	var stem_mat: StandardMaterial3D = StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.22, 0.50, 0.15, 1.0)
	stem_mat.roughness = 0.7
	stem_mi.set_surface_override_material(0, stem_mat)
	_mesh.add_child(stem_mi)

## Bell pepper — round sphere
func _build_bell_pepper(mat: StandardMaterial3D) -> void:
	var body: SphereMesh = SphereMesh.new()
	body.radius = 0.04
	body.height = 0.07
	_mesh.mesh = body
	_mesh.position = Vector3(0.0, 0.04, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Small green stem (divide position by 2x scale)
	var stem_mi: MeshInstance3D = MeshInstance3D.new()
	var stem: CylinderMesh = CylinderMesh.new()
	stem.top_radius = 0.005
	stem.bottom_radius = 0.007
	stem.height = 0.018
	stem.radial_segments = 6
	stem_mi.mesh = stem
	stem_mi.position = Vector3(0.0, 0.082 / 2.0, 0.0)
	var stem_mat: StandardMaterial3D = StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.22, 0.50, 0.15, 1.0)
	stem_mat.roughness = 0.7
	stem_mi.set_surface_override_material(0, stem_mat)
	_mesh.add_child(stem_mi)

## Garlic — bulb shape (sphere with smaller cloves around base)
func _build_garlic(mat: StandardMaterial3D) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.07
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.04, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Small pointed tip (divide position by 2x scale)
	var tip_mi: MeshInstance3D = MeshInstance3D.new()
	var tip: CylinderMesh = CylinderMesh.new()
	tip.top_radius = 0.002
	tip.bottom_radius = 0.008
	tip.height = 0.015
	tip.radial_segments = 6
	tip_mi.mesh = tip
	tip_mi.position = Vector3(0.0, 0.078 / 2.0, 0.0)
	tip_mi.set_surface_override_material(0, mat)
	_mesh.add_child(tip_mi)

## Potato — irregular oval (squashed sphere)
func _build_potato(mat: StandardMaterial3D) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.075
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.04, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Small "eyes" (tiny dark indentations — just small spheres)
	var eye_mat: StandardMaterial3D = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.45, 0.35, 0.22, 1.0)
	eye_mat.roughness = 0.9
	for i in range(3):
		var eye_mi: MeshInstance3D = MeshInstance3D.new()
		var eye: SphereMesh = SphereMesh.new()
		eye.radius = 0.005
		eye.height = 0.01
		eye_mi.mesh = eye
		var angle: float = TAU * i / 3.0
		eye_mi.position = Vector3(cos(angle) * 0.035, 0.045, sin(angle) * 0.035)
		eye_mi.set_surface_override_material(0, eye_mat)
		_mesh.add_child(eye_mi)

## Blueberry — small sphere with crown (tiny cylinder on top)
func _build_blueberry(mat: StandardMaterial3D) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.028
	sphere.height = 0.05
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.03, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Small crown/star on top
	var crown_mi: MeshInstance3D = MeshInstance3D.new()
	var crown: CylinderMesh = CylinderMesh.new()
	crown.top_radius = 0.008
	crown.bottom_radius = 0.004
	crown.height = 0.006
	crown.radial_segments = 5
	crown_mi.mesh = crown
	crown_mi.position = Vector3(0.0, 0.058, 0.0)
	var crown_mat: StandardMaterial3D = StandardMaterial3D.new()
	crown_mat.albedo_color = Color(0.35, 0.25, 0.15, 1.0)
	crown_mat.roughness = 0.7
	crown_mi.set_surface_override_material(0, crown_mat)
	_mesh.add_child(crown_mi)

## Corn — cylinder with husk leaves peeling away from base
func _build_corn(mat: StandardMaterial3D) -> void:
	var body: CylinderMesh = CylinderMesh.new()
	body.top_radius = 0.018
	body.bottom_radius = 0.015
	body.height = 0.11
	body.radial_segments = 8
	_mesh.mesh = body
	_mesh.position = Vector3(0.0, 0.055, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Green husk leaves peeling away from the cob (rotate outward)
	var husk_mat: StandardMaterial3D = StandardMaterial3D.new()
	husk_mat.albedo_color = Color(0.30, 0.55, 0.18, 1.0)
	husk_mat.roughness = 0.7
	for i in range(3):
		var husk_mi: MeshInstance3D = MeshInstance3D.new()
		var husk: BoxMesh = BoxMesh.new()
		husk.size = Vector3(0.012, 0.05, 0.003)
		husk_mi.mesh = husk
		var angle: float = TAU * i / 3.0
		## Position at base, offset outward, rotated to peel away
		husk_mi.position = Vector3(cos(angle) * 0.025, 0.01, sin(angle) * 0.025)
		husk_mi.rotation.y = angle
		husk_mi.rotation.x = 0.4   ## tilt outward
		husk_mi.set_surface_override_material(0, husk_mat)
		_mesh.add_child(husk_mi)

	## Silk threads on top (divide position by 3x scale)
	var silk_mat: StandardMaterial3D = StandardMaterial3D.new()
	silk_mat.albedo_color = Color(0.85, 0.75, 0.30, 1.0)
	silk_mat.roughness = 0.6
	for i in range(4):
		var silk_mi: MeshInstance3D = MeshInstance3D.new()
		var silk: CylinderMesh = CylinderMesh.new()
		silk.top_radius = 0.002
		silk.bottom_radius = 0.002
		silk.height = 0.025
		silk.radial_segments = 4
		silk_mi.mesh = silk
		var angle: float = TAU * i / 4.0
		silk_mi.position = Vector3(cos(angle) * 0.008, 0.12 / 3.0, sin(angle) * 0.008)
		silk_mi.set_surface_override_material(0, silk_mat)
		_mesh.add_child(silk_mi)

## Pumpkin — large ribbed sphere (use multiple overlapping spheres for ribs)
func _build_pumpkin(mat: StandardMaterial3D) -> void:
	## Main body
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.10
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.055, 0.0)
	_mesh.set_surface_override_material(0, mat)

	## Vertical ribs (6 thin elongated boxes — divide positions by 3x scale)
	for i in range(6):
		var rib_mi: MeshInstance3D = MeshInstance3D.new()
		var rib: BoxMesh = BoxMesh.new()
		rib.size = Vector3(0.008, 0.09, 0.025)
		rib_mi.mesh = rib
		var angle: float = TAU * i / 6.0
		rib_mi.position = Vector3(cos(angle) * 0.055, 0.055 / 3.0, sin(angle) * 0.055)
		rib_mi.rotation.y = angle
		rib_mi.set_surface_override_material(0, mat)
		_mesh.add_child(rib_mi)

	## Green stem on top (divide position by 3x scale)
	var stem_mi: MeshInstance3D = MeshInstance3D.new()
	var stem: CylinderMesh = CylinderMesh.new()
	stem.top_radius = 0.006
	stem.bottom_radius = 0.010
	stem.height = 0.025
	stem.radial_segments = 6
	stem_mi.mesh = stem
	stem_mi.position = Vector3(0.0, 0.112 / 3.0, 0.0)
	var stem_mat: StandardMaterial3D = StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.25, 0.48, 0.15, 1.0)
	stem_mat.roughness = 0.7
	stem_mi.set_surface_override_material(0, stem_mat)
	_mesh.add_child(stem_mi)

## Generic fallback sphere
func _build_generic_sphere(mat: StandardMaterial3D) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.055, 0.0)
	_mesh.set_surface_override_material(0, mat)

## Harvest pop-in tween constants (Polish Plan Group 3 item 8) — cosmetic only,
## no physics/gameplay effect. Scale-in overshoot mirrors WaterPurifier's
## play_clean_pulse() tween convention (create_tween, EASE_OUT/TRANS_BACK for
## the "pop" feel), just applied to the item's own scale instead of a ring.
const HARVEST_POP_START_SCALE: float = 0.1
const HARVEST_POP_DURATION:    float = 0.28

## Spawn helper — mirrors PurifierFilterItem.spawn_at()'s small-random-offset
## scatter pattern (used by FarmPlant.harvest() to spawn 2× per harvest).
static func spawn_at(parent: Node, base_pos: Vector3, type: String) -> FarmProduceItem:
	var item: FarmProduceItem = FarmProduceItem.new()
	item.produce_type = type
	var offset: Vector3 = Vector3(randf_range(-0.25, 0.25), 0.15, randf_range(-0.25, 0.25))
	parent.add_child(item)
	item.global_position = base_pos + offset

	## Harvest pop-in (Group 3 item 8): starts tiny, scales up past full size
	## and settles — a quick "pop" so freshly-harvested produce reads clearly
	## instead of just appearing at full size.
	item.scale = Vector3.ONE * HARVEST_POP_START_SCALE
	var tween: Tween = item.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(item, "scale", Vector3.ONE, HARVEST_POP_DURATION)

	return item
