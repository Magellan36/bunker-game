extends LightStorage
class_name TrashCan
## TrashCan.gd
## Light storage furniture (10 slots) that doubles as the disposal point for
## the future trash/recycling system. E behavior is 100% inherited from
## LightStorage — always opens the shared StorageUI, fully retrievable via
## Carry/⊕ at any fill level (per design: never disable retrieval).
##
## F is overridden with the full trash-handling surface:
##   - Holding a Trash Bag          → merge its contents back into the can
##   - Empty-handed + has contents  → collect everything into a new Trash
##                                     Bag handed directly to the player
##                                     (partial fill fine — "at any point
##                                     of its fullness")
##   - Empty-handed + no contents   → no-op (falls through to pickup logic)
##   - Holding an eligible item     → store it; if full, show a "too full"
##                                     toast and drop the item (the same
##                                     never-strand-the-held-item fallback
##                                     LightStorage._try_store_held() uses)
## This is a clean split because LightStorage's own F-prompt/store path
## already goes silent once is_full() is true — there's no real overlap to
## resolve, just a new use for the F slot that store leaves vacant at 10/10.

func _init() -> void:
	capacity      = 10
	display_name  = "Trash Can"
	prompt_height = 1.0
	grid_cols     = 2
	grid_rows     = 5

## Aug 2026 — the group NPCJobBoard._has_trash_receptacle() checks before
## any trash item is ever offered to Cleaning at all. Everything else in
## the NPC trash-collection system was already built and waiting on this
## one line — see NPC thread's own plan/HANDOVER entry for the full
## picture if useful context. super._ready() first preserves everything
## LightStorage._ready() already does (shelving group, collision, mesh).
func _ready() -> void:
	super._ready()
	add_to_group("trash_receptacle")

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

## Presence check — every stored item is a REAL live node now (merged-back
## items are reconstructed, see _merge_bag()), so plain stored[] occupancy is
## the only thing that matters; the old combined live+merged _total_count()
## and the is_full() override are gone with the side-channel they served.
func _has_any_stored() -> bool:
	for s in stored:
		if s != null:
			return true
	return false

## Populated ONLY when reconstruction fails (script missing/renamed since
## the item was bagged — should not happen in normal play). Rolled into the
## next bag this can produces so the data is never silently discarded, even
## though it can't become a live item again without its original script.
var _unrecoverable_records: Array[Dictionary] = []

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
		return "[F] Collect trash bag" if _has_any_stored() else ""
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
		if _has_any_stored():
			## Job Progress Bar (Aug 2026) — collecting used to build the bag
			## instantly here; now gated behind a timed job. Falls back to the
			## old instant behavior if InteractionSystem can't be resolved.
			if _interaction_system.has_method("start_job"):
				_interaction_system.start_job(self, InteractionSystem.JOB_DEFAULT_DURATION, Callable(self, "_finish_collect").bind(_interaction_system), "Collecting Trash...")
			else:
				_empty_into_bag(_interaction_system)
			return true
		return false

	## Holding a normal eligible item → throw it away
	if not held.is_in_group("inventory_item"):
		return false   ## unrelated held item, nothing this can does with it
	if is_full():
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, "Trash can is too full")
		_interaction_system._quick_drop()   ## Established pattern (LightStorage._try_store_held()) — error, but don't strand the held item just because ITS specific destination was unavailable.
		return true
	_try_store_held(held)   ## inherited mechanics unchanged
	return true

# ─── Empty-into-bag ─────────────────────────────────────────────────────────
## Job completion callback for the empty-handed collect job above — re-checks
## _has_any_stored() defensively (the player is locked in place for the
## whole job, so this shouldn't ever go false out from under it, but costs
## nothing to check) before actually building the bag.
func _finish_collect(isys: Node) -> void:
	if _has_any_stored():
		_empty_into_bag(isys)

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

	## Fold in any reconstruction-failed records — a bag collected now must
	## include everything logically "in" the can, even data that can't become
	## a live item again (see _unrecoverable_records).
	for record: Dictionary in _unrecoverable_records:
		record["disposed_index"] = contents.size()
		contents.append(record)
	_unrecoverable_records.clear()

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
	var records: Array = bag.contents if "contents" in bag else []
	var free_slots: int = 0
	for s in stored:
		if s == null:
			free_slots += 1
	if records.size() > free_slots:
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, "Trash can is too full")
		isys._quick_drop()   ## Aug 2026 fix — same never-strand fallback as above (LightStorage pattern); the bag is still isys.held_item here, before the release-and-merge sequence, so _quick_drop() works as-is.
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

	## Reconstruct each record into a real item and absorb it exactly like a
	## freshly-thrown-away item — reuses _absorb_item() unchanged, so a
	## reconstructed FuelCan at 69% fuel is retrieved via Carry/⊕ afterward
	## with 100% the same mechanics as anything else in the can.
	var lost: Array[Dictionary] = []
	for record: Dictionary in records:
		var item: RigidBody3D = TrashCan.reconstruct_item(record, self)
		if item != null:
			_absorb_item(item)
		else:
			lost.append(record)   ## should not happen in practice — see safety net below

	if not lost.is_empty():
		## Defense in depth: reconstruction should always succeed for any
		## item that was ever legitimately thrown away, but if a script got
		## moved/renamed since a bag was created, don't silently vanish the
		## record — fold it into whatever bag this can produces next rather
		## than dropping it on the floor (matches the "never lose an item"
		## priority even in this should-never-happen case).
		_unrecoverable_records.append_array(lost)

	bag.queue_free()

## Cached comparison set — PickupableItem's own base-class properties
## (carry-physics bookkeeping: grace timers, hold-point ref, out-of-range
## tracking) are never item-specific gameplay state, so they're excluded
## regardless of name. Everything else declared on the ACTUAL subclass is
## captured, whether public or private-by-convention — this codebase marks
## meaningful state private too (FuelCan._fuel_remaining, Flashlight._battery),
## so an underscore-name filter (the original design) silently drops exactly
## the data that matters most. Never filter by name again here.
static func _base_property_names() -> Dictionary:
	var base_item: RigidBody3D = PickupableItem.new()
	var names: Dictionary = {}
	for prop: Dictionary in base_item.get_property_list():
		names[prop.get("name", "")] = true
	base_item.free()
	return names

static func extract_trash_record(item: RigidBody3D, disposed_index: int) -> Dictionary:
	var item_type: String    = str(item.shelf_item_type) if "shelf_item_type" in item else item.get_class()
	var display_name: String = item.get_display_name() if item.has_method("get_display_name") else item_type
	var script_path: String  = item.get_script().resource_path if item.get_script() != null else ""
	var scene_path: String   = item.scene_file_path   ## empty for bare-script nodes — self-detecting scene-vs-script split

	var data: Dictionary = {}
	const SAFE_TYPES: Array[int] = [
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME,
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR, TYPE_ARRAY, TYPE_DICTIONARY,
	]
	var base_names: Dictionary = _base_property_names()
	for prop: Dictionary in item.get_property_list():
		var pname: String = prop.get("name", "")
		if pname.is_empty() or base_names.has(pname):
			continue
		if (prop.get("usage", 0) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if not SAFE_TYPES.has(prop.get("type", TYPE_NIL)):
			continue   ## still excludes TYPE_OBJECT (node refs) — see the freed-instance-safety note this had before
		data[pname] = item.get(pname)

	if item.has_method("get_trash_material"):
		data["material"] = item.get_trash_material()

	return {
		"item_type":      item_type,
		"display_name":   display_name,
		"script_path":    script_path,
		"scene_path":     scene_path,
		"disposed_index": disposed_index,
		"data":           data,
	}

## Rebuilds a live item from a trash record — the inverse of
## extract_trash_record(). Prefers instantiating the item's own scene when
## it has one (restores baked collision/structure exactly — required for
## FuelCan, FoodCan, WaterBottle, Flashlight, PurifierFilterItem, all of
## which keep their collision shape in a companion .tscn, not in script).
## Falls back to bare script + add_child only for the genuinely scene-less
## procedural items (SeedItem, DishItem, FertilizerItem, EmptyBagItem,
## EmptyFertilizerBottleItem, FarmProduceItem, BagOfSoilItem). "data" is
## applied AFTER add_child() either way, so the item's own _ready()-set
## defaults (e.g. a fresh FuelCan's full tank) get overwritten by the
## restored values, not the other way around.
static func reconstruct_item(record: Dictionary, parent: Node) -> RigidBody3D:
	var scene_path: String  = record.get("scene_path", "")
	var script_path: String = record.get("script_path", "")
	var item: RigidBody3D   = null

	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var inst: Node = (load(scene_path) as PackedScene).instantiate()
		if inst is RigidBody3D:
			item = inst
		else:
			push_warning("TrashCan: scene '%s' root is not a RigidBody3D" % scene_path)
			inst.queue_free()

	if item == null:
		if script_path.is_empty() or not ResourceLoader.exists(script_path):
			push_warning("TrashCan: cannot reconstruct '%s' — no usable scene or script" % record.get("item_type", "?"))
			return null
		item = RigidBody3D.new()
		item.set_script(load(script_path))

	parent.add_child(item)
	var data: Dictionary = record.get("data", {})
	for key: String in data.keys():
		if key in item:
			item.set(key, data[key])
	return item
