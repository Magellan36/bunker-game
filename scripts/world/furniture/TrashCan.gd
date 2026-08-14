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
	shape.top_radius    = 0.24
	shape.bottom_radius = 0.19
	shape.height        = 0.62
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

# ─── F override — store OR empty-into-bag depending on fill state ─────────
func get_f_prompt() -> String:
	if is_full():
		if _interaction_system == null:
			_resolve_interaction_system()
		if _interaction_system != null and _interaction_system.held_item == null:
			return "[F] Collect trash bag"
		return ""   ## Full + hands occupied — nothing actionable
	## Not full — same eligibility/wording logic as the base class, but
	## "Throw away" reads better than generic "Store item" for a trash can.
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null or _interaction_system.held_item == null:
		return ""
	if not _interaction_system.held_item.is_in_group("inventory_item"):
		return ""
	return "[F] Throw away item"

func on_f_interact() -> void:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null:
		return
	if is_full():
		if _interaction_system.held_item == null:
			_empty_into_bag(_interaction_system)
		else:
			var hud: Node = get_tree().get_first_node_in_group("hud")
			if hud != null and hud.has_method("show_soft_warning"):
				hud.show_soft_warning("Hands full — can't collect the trash bag")
		return
	super.on_f_interact()   ## Not full — normal store path, unchanged

# ─── Empty-into-bag ─────────────────────────────────────────────────────────
func _empty_into_bag(isys: Node) -> void:
	var contents: Array[Dictionary] = []
	for i: int in stored.size():
		var item: RigidBody3D = stored[i]
		if item == null:
			continue   ## shouldn't happen (is_full() was just verified) — defensive only
		contents.append(TrashCan.extract_trash_record(item, contents.size()))
		## Defensive holder-reference clear before freeing — belt-and-
		## suspenders consistent with npc_try_place_item()'s existing
		## convention, even though items reaching this point should already
		## be fully detached (frozen/hidden children, not held by anyone).
		if "held_item" in isys and isys.held_item == item:
			isys.held_item = null
		var npc_list: Array = get_tree().get_nodes_in_group("npc")
		for npc: Node in npc_list:
			if "held_item" in npc and npc.held_item == item:
				npc.held_item = null
		item.queue_free()
		stored[i] = null

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