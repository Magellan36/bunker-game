extends LightStorage
class_name TrashCan
## TrashCan.gd
## Light storage furniture (10 slots) that doubles as the disposal point for
## the future trash/recycling system. E behavior is 100% inherited from
## LightStorage — always opens the shared StorageUI, fully retrievable via
## Carry/⊕ at any fill level (per design: never disable retrieval).
##
## F is overridden with dual behavior depending on fill state:
##   - Not full + holding an eligible item  → normal store (inherited path)
##   - Full (10/10) + empty hands           → empty into a new Trash Bag,
##                                             handed directly to the player
##   - Full + hands NOT empty               → soft warning, no action
## This is a clean split because LightStorage's own F-prompt/store path
## already goes silent once is_full() is true — there's no real overlap to
## resolve, just a new use for the F slot that store leaves vacant at 10/10.

func _init() -> void:
	capacity      = 10
	display_name  = "Trash Can"
	prompt_height = 1.0
	grid_cols     = 2
	grid_rows     = 5

func _build_mesh() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.32, 0.26, 1.0)   ## drab olive-grey
	mat.metallic = 0.15
	mat.roughness = 0.75

	## Simple tapered cylinder body (basic model, per design direction —
	## refine visually later)
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_mesh: CylinderMesh = CylinderMesh.new()
	body_mesh.top_radius    = 0.24
	body_mesh.bottom_radius = 0.19
	body_mesh.height        = 0.62
	body_mesh.radial_segments = 16
	body_mi.mesh = body_mesh
	body_mi.position = Vector3(0.0, 0.31, 0.0)
	body_mi.set_surface_override_material(0, mat)
	add_child(body_mi)

	## Collision (procedural, not scene-authored — this object has no .tscn)
	var col: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	## CylinderShape3D has no top/bottom taper (unlike the CylinderMesh above)
	## — use a single uniform radius. Use the WIDER of the two (0.24, the
	## top) rather than an average, so collision fully encloses the tapered
	## visual mesh instead of letting items clip through the narrower base.
	shape.radius = 0.24
	shape.height = 0.62
	col.shape = shape
	col.position = Vector3(0.0, 0.31, 0.0)
	add_child(col)

	## Rim lip, thin torus-substitute (flattened cylinder) at the open top
	var rim_mi: MeshInstance3D = MeshInstance3D.new()
	var rim_mesh: CylinderMesh = CylinderMesh.new()
	rim_mesh.top_radius = 0.26
	rim_mesh.bottom_radius = 0.26
	rim_mesh.height = 0.03
	rim_mi.mesh = rim_mesh
	rim_mi.position = Vector3(0.0, 0.615, 0.0)
	rim_mi.set_surface_override_material(0, mat)
	add_child(rim_mi)

static func build_ghost_mesh() -> Mesh:
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.26
	cyl.bottom_radius = 0.19
	cyl.height = 0.65
	return cyl

## Data records merged back in via a Trash Bag placed into this can (see
## _merge_bag()). Counted toward capacity but NOT individually retrievable
## via Carry/⊕ — there's no live node to hand back, only compacted data
## (matches how real trash works: once bagged and re-dumped, you don't fish
## one specific can back out without re-opening the bag). Folded into the
## contents of the NEXT bag this can produces.
var merged_trash_data: Array[Dictionary] = []

func _live_count() -> int:
	var n: int = 0
	for s in stored:
		if s != null:
			n += 1
	return n

func _total_count() -> int:
	return _live_count() + merged_trash_data.size()

## Overrides LightStorage.is_full() — combined count (live + merged data),
## not just live stored[] slots, so throwing in a fresh item correctly gets
## blocked once merged-back bag data has already used up the can's capacity.
func is_full() -> bool:
	return _total_count() >= capacity

# ─── F override — store OR empty-into-bag depending on fill state ─────────
func get_f_prompt() -> String:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null:
		return ""
	var held: RigidBody3D = _interaction_system.held_item
	if held != null and ("is_trash_bag" in held):
		return "[F] Empty bag into trash can"
	if held == null:
		return "[F] Collect trash bag" if _total_count() > 0 else ""
	if not held.is_in_group("inventory_item"):
		return ""
	return "" if is_full() else "[F] Throw away item"

func on_f_interact() -> bool:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null:
		return false
	var held: RigidBody3D = _interaction_system.held_item

	## Holding a Trash Bag → merge its contents back into the can
	if held != null and ("is_trash_bag" in held):
		_merge_bag(held, _interaction_system)
		return true

	## Empty-handed → collect whatever's in the can (partial fill is fine
	## now — "at any point of its fullness")
	if held == null:
		if _total_count() > 0:
			_empty_into_bag(_interaction_system)
			return true
		return false

	## Holding a normal eligible item → throw it away
	if not held.is_in_group("inventory_item"):
		return false   ## unrelated held item, nothing this can does with it
	if is_full():
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, "Trash can is too full")
		return true
	_try_store_held(held)   ## inherited mechanics unchanged
	return true

# ─── Empty-into-bag ─────────────────────────────────────────────────────────
func _empty_into_bag(isys: Node) -> void:
	var contents: Array[Dictionary] = []
	for i: int in stored.size():
		var item: RigidBody3D = stored[i]
		if item == null:
			continue
		contents.append(TrashCan.extract_trash_record(item, contents.size()))
		if "held_item" in isys and isys.held_item == item:
			isys.held_item = null
		for npc: Node in get_tree().get_nodes_in_group("npc"):
			if "held_item" in npc and npc.held_item == item:
				npc.held_item = null
		item.queue_free()
		stored[i] = null

	## Fold in anything already merged back from a previous bag — a bag
	## collected now must include everything logically "in" the can.
	for record: Dictionary in merged_trash_data:
		record["disposed_index"] = contents.size()
		contents.append(record)
	merged_trash_data.clear()

	var bag_script: GDScript = load("res://scripts/world/items/TrashBag.gd")
	var bag: RigidBody3D = RigidBody3D.new()
	bag.set_script(bag_script)
	bag.contents = contents

	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	world_root.add_child(bag)

	## Same safe player-side spawn point + immediate hand-off used by
	## Shelving.retrieve_to_carry() / LightStorage.take_for_carry() — see
	## the wall-tunneling fix. Reused here verbatim since the failure mode
	## (spawning inside/behind solid geometry) is identical in kind.
	bag.global_position = Shelving.carry_spawn_position(isys)
	if bag.has_method("pickup"):
		bag.pickup(isys.hold_point)
	isys.held_item       = bag
	isys._held_from_slot = -1

func _merge_bag(bag: RigidBody3D, isys: Node) -> void:
	var bag_count: int = 0
	if "contents" in bag:
		bag_count = (bag.contents as Array).size()
	if _total_count() + bag_count > capacity:
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, "Trash can is too full")
		return

	## Release the bag from the player's hand — same release sequence
	## _try_store_held() uses for a normal item (Shelving.gd pattern), since
	## the bag is leaving the player's hand permanently either way.
	isys._is_holding_e = false
	if bag.has_signal("knocked_out") and bag.knocked_out.is_connected(isys._on_item_knocked_out):
		bag.knocked_out.disconnect(isys._on_item_knocked_out)
	if isys._held_from_slot != -1 and isys.inventory != null:
		isys.inventory.retrieve_item(isys._held_from_slot)
	isys.held_item       = null
	isys._held_from_slot = -1
	if "is_held" in bag: bag.is_held = false
	if "_hold_point" in bag: bag._hold_point = null

	if "contents" in bag:
		for record: Dictionary in (bag.contents as Array):
			merged_trash_data.append(record)
	bag.queue_free()   ## fully compacted into merged_trash_data now — nothing left to hold onto

## Generic per-item data capture via script-property reflection — works for
## ANY inventory_item type automatically, no per-item opt-in required from
## other threads' item scripts. Captures every public (non-underscore-
## prefixed, by the codebase's own private-var convention) script-declared
## property whose type is safely snapshot-able (primitives, Vector/Color,
## Array, Dictionary). Object-typed properties (node references, e.g. a
## cached mesh or hold-point pointer) are deliberately EXCLUDED — keeping a
## reference to a node that's about to be freed is exactly the freed-
## instance-reference bug class currently under separate investigation
## elsewhere; this avoids ever creating a new instance of it.
static func extract_trash_record(item: RigidBody3D, disposed_index: int) -> Dictionary:
	var item_type: String = str(item.shelf_item_type) if "shelf_item_type" in item else item.get_class()
	var display_name: String = item.get_display_name() if item.has_method("get_display_name") else item_type

	var data: Dictionary = {}
	const SAFE_TYPES: Array[int] = [
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME,
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, TYPE_ARRAY, TYPE_DICTIONARY,
	]
	for prop: Dictionary in item.get_property_list():
		var pname: String = prop.get("name", "")
		if pname.is_empty() or pname.begins_with("_"):
			continue
		if (prop.get("usage", 0) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if not SAFE_TYPES.has(prop.get("type", TYPE_NIL)):
			continue   ## Excludes TYPE_OBJECT (node refs) and anything else unsafe to snapshot
		data[pname] = item.get(pname)

	return {
		"item_type":      item_type,
		"display_name":   display_name,
		"disposed_index": disposed_index,
		"data":           data,
	}