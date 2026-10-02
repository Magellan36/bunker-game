extends StaticBody3D
class_name Shelving
## Shelving.gd
## Base class for the shelf family (Small / Medium / Large). Buildable/
## deconstructible shelf unit. Procedural mesh (no GLB).
## Slot count = shelf_y.size() * slots_per_tier (Medium = 5 tiers × 2
## columns = 10 storage slots). Each slot is a STACK — multiple small
## items can share one slot up to a type-specific limit. Subclasses
## (SmallShelf / LargeShelf) override _init() only — dimensions,
## slots_per_tier, shelf_y — everything else is inherited unchanged.
##
## Stack limits (per slot):
##   WaterCase / CanCase  → 4  (lay flat, 2×2 grid)
##   WaterBottle / FoodCan → 6  (stand upright, two rows of 3)
##   TestCrate             → 1  (one per slot)
##   Unknown items         → 1
##
## F — place held item into first compatible slot (prompt: "[F] Place item")
## E — open shelf UI menu (prompt: "[E] Open")
##
## Slot layout (shelf 0 = bottom, shelf 4 = top):
##   Slot 0 = shelf 0, left    Slot 1 = shelf 0, right
##   Slot 2 = shelf 1, left    Slot 3 = shelf 1, right
##   Slot 4 = shelf 2, left    Slot 5 = shelf 2, right
##   Slot 6 = shelf 3, left    Slot 7 = shelf 3, right
##   Slot 8 = shelf 4, left    Slot 9 = shelf 4, right

# ─── Asset ────────────────────────────────────────────────────────────────────
## Procedural mesh — no GLB needed. 4 corner posts + shelf platforms.

# ─── Tunable dimensions ───────────────────────────────────────────────────────
@export var unit_w: float = 1.25
## Aug 2026 — raised from 2.5 to 3.55 alongside the shelf_y spacing
## increase, so the posts (derived below as unit_h - 0.2375) still extend
## comfortably above the new top tier (2.52) with headroom for a
## crate-height item, matching the previous proportions.
@export var unit_h: float = 3.55
## Aug 2026 — widened from 0.625 to 0.85 so TestCrate (D=0.73, the deepest
## carriable item) fits within the shelf's own depth instead of clipping
## through the front/back — found during the tier-spacing fix below.
@export var unit_d: float = 0.85

## Aug 2026 — widened from 0.45 to 0.60 spacing (interior clear height
## 0.432 -> 0.582) so TestCrate (H=0.48, the largest carriable item) fits
## with clearance on every tier. Bottom tier dropped from 0.225 to 0.12,
## closer to the floor per design feedback.
@export var shelf_y: Array[float] = [0.12, 0.72, 1.32, 1.92, 2.52]
@export var slot_offset_x: float  = 0.275
@export var slot_lift: float      = 0.075
@export var multi_col_spacing: float = 0.30   ## Column spacing for the N-column (slots_per_tier != 2) layout path only

@export var slots_per_tier: int  = 2        ## Columns of slots per tier (2 = classic left/right)
@export var display_name: String = "Medium Shelf"

# ─── Slot state ───────────────────────────────────────────────────────────────
## Each slot is an Array of RigidBody3D items (a stack).
## slots[i] = [] means empty, slots[i].size() = count in that slot.
var slots: Array = []   ## Sized in _ready(): shelf_y.size() * slots_per_tier empty stacks
var _slot_nodes: Array = []   ## Marker3D for each slot's base world position

## All shelves use the same two immutable finishes. Sharing them avoids two
## material resources per placed shelf (and per Build preview rebuild).
static var _shared_metal_material: StandardMaterial3D = null
static var _shared_shelf_material: StandardMaterial3D = null

# ─── Interaction ──────────────────────────────────────────────────────────────
var _player_in_range: bool    = false
var _interaction_system: Node = null   ## Injected by BuildModeController after spawn
var _storage_ui: Node         = null   ## Injected by MainWorld after spawn (Aug 2026 — the shared StorageUI, was _shelf_ui)

const NPC_STORAGE_STANDOFF: float = 0.75

func get_npc_interaction_slots(_action: StringName) -> Array[Dictionary]:
	## Shelves may be placed against either wall face. Publish both long-side
	## approaches and let navmesh projection discard the blocked side.
	var basis: Basis = global_transform.basis.orthonormalized()
	var front_position: Vector3 = global_transform * Vector3(
		0.0, 0.0, unit_d * 0.5 + NPC_STORAGE_STANDOFF)
	var back_position: Vector3 = global_transform * Vector3(
		0.0, 0.0, -unit_d * 0.5 - NPC_STORAGE_STANDOFF)
	return [
		{
			"slot_id": &"front",
			"claim_group": &"front",
			"transform": Transform3D(basis, front_position),
		},
		{
			"slot_id": &"back",
			"claim_group": &"back",
			"transform": Transform3D(basis.rotated(Vector3.UP, PI), back_position),
		},
	]

## Full-fidelity preview mode (Jul 2026) — set TRUE by BuildModeHUD's
## construct-tab preview code BEFORE add_child(), so this instance builds
## its real visual exactly like a placed object but skips every
## side-effecting call (group membership, PowerManager/WaterManager
## registration). MUST be set before add_child() — _ready() fires
## synchronously during add_child() and reads this immediately. See
## docs/systems/build/README.md "Full-fidelity previews" for the full
## convention and why this exists (a previous version instantiated these
## same scripts with no guard and registered 3 real running generators
## into the live PowerManager the instant Build Mode opened).
var _is_preview_only: bool = false

## Aug 2026 — safe spawn point for any item about to be handed to the player
## via pickup(). The player's own position is guaranteed clear of solid
## world geometry (their own collision volume occupies it), so starting a
## carried item here — rather than at its old storage-slot position, which
## can be behind a shelf/furniture unit pressed against a wall — eliminates
## the tunnel-through-wall/floor bug entirely. The short remaining distance
## to the real hold point is closed by PickupableItem._physics_process()'s
## existing per-frame chase, so this still gets a small natural "pop into
## hand" motion instead of an instant teleport onto the hold point itself.
## Shared by Shelving.retrieve_to_carry() and LightStorage.take_for_carry().
static func carry_spawn_position(isys: Node) -> Vector3:
	const SPAWN_HEIGHT: float = 1.0   ## Roughly chest height on the player
	return isys.global_position + Vector3(0.0, SPAWN_HEIGHT, 0.0)

# ─── Signals ──────────────────────────────────────────────────────────────────
signal item_placed(slot_index: int, item: RigidBody3D)
signal item_retrieved(slot_index: int, item: RigidBody3D)
## Oct 2026: the player moved a stored stack to another slot (StorageUI).
## Emitted once per item; the item never left storage.
signal item_moved(from_slot: int, to_slot: int, item: RigidBody3D)

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("shelving")
	## Layer 1 = player collision, Layer 3 (bit value 4) = build hover raycast.
	## Must match the layer set on wall/pillar placed objects (also 5).
	collision_layer = 5
	collision_mask  = 0
	for i: int in shelf_y.size() * slots_per_tier:
		slots.append([])
	_load_mesh()
	_build_slot_markers()
	_build_collision()

# ─── Mesh ─────────────────────────────────────────────────────────────────────
func _load_mesh() -> void:
	## Metallic grey — matches Table.gd
	var metal_mat: StandardMaterial3D = _metal_material()
	var shelf_mat: StandardMaterial3D = _shelf_material()

	## 4 corner posts — angle-iron style (shortened at top by one shelf spacing)
	var post_w: float = 0.035
	var post_d: float = 0.035
	## Aug 2026 — rebuilt from shelf_y directly instead of unit_h. The old
	## formula (unit_h - 0.2375) was tuned against the pre-resize 0.45 tier
	## spacing and never recomputed when spacing/unit_h changed in the crate-
	## fit pass, so posts drifted to reaching ~0.57m above the top shelf.
	## Posts now extend exactly 1/6 of the tier spacing above the TOP shelf
	## (≈ 0.10m at the current 0.60 spacing — also close to 1/6 of TestCrate's
	## height, the secondary reference point). post_y_offset (how far the
	## post's bottom sits below floor level, for the embedded/anchored look)
	## is unchanged and independent of this.
	var tier_spacing: float  = (shelf_y[1] - shelf_y[0]) if shelf_y.size() > 1 else 0.60
	var post_top_excess: float = tier_spacing / 6.0
	var post_y_offset: float   = 0.225
	var post_h: float          = shelf_y[shelf_y.size() - 1] + post_top_excess + post_y_offset
	var corners: Array[Vector2] = [
		Vector2(-unit_w * 0.5 + post_w * 0.5, -unit_d * 0.5 + post_d * 0.5),
		Vector2( unit_w * 0.5 - post_w * 0.5, -unit_d * 0.5 + post_d * 0.5),
		Vector2(-unit_w * 0.5 + post_w * 0.5,  unit_d * 0.5 - post_d * 0.5),
		Vector2( unit_w * 0.5 - post_w * 0.5,  unit_d * 0.5 - post_d * 0.5),
	]
	var post_positions: Array[Vector3] = []
	var lip_positions: Array[Vector3] = []
	for corner: Vector2 in corners:
		post_positions.append(Vector3(corner.x, post_h * 0.5 - post_y_offset, corner.y))
		lip_positions.append(Vector3(
			corner.x, post_h * 0.5 - post_y_offset, corner.y - post_d * 0.5 - 0.004))
	_add_box_multimesh("Posts", Vector3(post_w, post_h, post_d), post_positions, metal_mat)
	_add_box_multimesh("PostLips", Vector3(post_w, 0.015, 0.008), lip_positions, metal_mat)

	## Slot notches on each post (small horizontal marks for adjustable shelves)
	var notch_positions: Array[Vector3] = []
	for corner: Vector2 in corners:
		for sy: float in shelf_y:
			for n: int in range(-1, 2):
				notch_positions.append(Vector3(
					corner.x, sy + float(n) * 0.012, corner.y - post_d * 0.5 - 0.002))
	_add_box_multimesh(
		"ShelfNotches", Vector3(post_w + 0.005, 0.004, 0.003), notch_positions, metal_mat)

	## Shelf platforms — span full width, posts sit inside
	var shelf_positions: Array[Vector3] = []
	for sy: float in shelf_y:
		shelf_positions.append(Vector3(0.0, sy, 0.0))
	_add_box_multimesh("ShelfPlatforms", Vector3(unit_w, 0.018, unit_d), shelf_positions, shelf_mat)

## One renderer node replaces each family of identical box meshes. This keeps
## every authored transform exactly while collapsing a medium shelf from 73
## MeshInstance3D children to four MultiMeshInstance3D children.
func _add_box_multimesh(node_name: String, size: Vector3,
		positions: Array[Vector3], material: StandardMaterial3D) -> void:
	if positions.is_empty():
		return
	var box := BoxMesh.new()
	box.size = size
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = box
	instances.instance_count = positions.size()
	var combined_aabb := AABB()
	for i: int in positions.size():
		var instance_transform := Transform3D(Basis.IDENTITY, positions[i])
		instances.set_instance_transform(i, instance_transform)
		var instance_aabb: AABB = instance_transform * box.get_aabb()
		combined_aabb = instance_aabb if i == 0 else combined_aabb.merge(instance_aabb)
	## Providing this up front makes culling and same-frame preview sizing
	## deterministic; otherwise RenderingServer computes the MultiMesh bounds
	## asynchronously after the catalog has already measured it.
	instances.custom_aabb = combined_aabb
	var renderer := MultiMeshInstance3D.new()
	renderer.name = node_name
	renderer.multimesh = instances
	renderer.material_override = material
	add_child(renderer)

static func _metal_material() -> StandardMaterial3D:
	if _shared_metal_material == null:
		_shared_metal_material = StandardMaterial3D.new()
		_shared_metal_material.albedo_color = Color(0.60, 0.62, 0.65, 1.0)
		_shared_metal_material.roughness = 0.4
		_shared_metal_material.metallic = 0.5
	return _shared_metal_material

static func _shelf_material() -> StandardMaterial3D:
	if _shared_shelf_material == null:
		_shared_shelf_material = StandardMaterial3D.new()
		_shared_shelf_material.albedo_color = Color(0.55, 0.57, 0.60, 1.0)
		_shared_shelf_material.roughness = 0.4
		_shared_shelf_material.metallic = 0.5
	return _shared_shelf_material

# ─── Slot markers ─────────────────────────────────────────────────────────────
func _build_slot_markers() -> void:
	_slot_nodes.clear()
	## Right-side slots get an extra nudge away from the left wall.
	## slot_offset_x already separates left/right; right_extra shifts them slightly further right.
	const right_extra: float = 0.06
	for tier: int in shelf_y.size():
		for side: int in slots_per_tier:
			var x: float
			if slots_per_tier == 2:
				## Classic left/right — EXACT pre-existing math, do not alter
				var base_x: float = slot_offset_x * (1.0 if side == 1 else -1.0)
				x = base_x + (right_extra if side == 1 else 0.0)
			else:
				## N evenly spaced columns centered on the unit (Large Shelf: 3)
				x = (float(side) - float(slots_per_tier - 1) * 0.5) * multi_col_spacing
			var y: float = shelf_y[tier] + slot_lift
			var marker: Marker3D = Marker3D.new()
			marker.position = Vector3(x, y, 0.0)
			add_child(marker)
			_slot_nodes.append(marker)

# ─── Collision ────────────────────────────────────────────────────────────────
func _build_collision() -> void:
	var cshape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(unit_w, unit_h, unit_d)
	cshape.shape = box
	cshape.position = Vector3(0.0, unit_h * 0.5, 0.0)
	add_child(cshape)

# ─── Stack limit query ────────────────────────────────────────────────────────
## Returns the max items per slot for this item type.
## Items declare their own limit via shelf_stack_limit property.
## Default = 1 for anything that doesn't declare it.
func _get_stack_limit(item: RigidBody3D) -> int:
	if "shelf_stack_limit" in item:
		return int(item.shelf_stack_limit)
	return 1

## Returns the type-key string for an item, used to enforce same-type stacking.
## Items can optionally declare shelf_item_type; otherwise we use class_name or script path.
func _get_item_type(item: RigidBody3D) -> String:
	if "shelf_item_type" in item:
		return str(item.shelf_item_type)
	# Fall back to script path (unique per item class)
	if item.get_script() != null:
		return item.get_script().resource_path
	return item.get_class()

# ─── Interaction API ──────────────────────────────────────────────────────────

## Lazily resolves _interaction_system by scanning the tree for an
## InteractionSystem node. Caches the result. Safe to call every frame.
func _resolve_interaction_system() -> Node:
	## InteractionSystem lives at Player/InteractionSystem.
	## Find it by class name scan — avoids hard-coded paths or missing groups.
	var nodes: Array = get_tree().get_nodes_in_group("world")
	## Try world root's child Player first (common layout)
	if nodes.size() > 0:
		var world: Node = nodes[0]
		for child in world.get_children():
			var isys: Node = child.get_node_or_null("InteractionSystem")
			if isys != null:
				_interaction_system = isys
				return isys
	## Fallback: brute-force search entire tree
	var all: Array = get_tree().get_nodes_in_group("interactable")
	## Can't use that — try get_root traversal for InteractionSystem class
	_interaction_system = _find_node_by_class(get_tree().get_root(), "InteractionSystem")
	return _interaction_system

func _find_node_by_class(node: Node, class_name_str: String) -> Node:
	if node.get_script() != null:
		var src: String = node.get_script().resource_path
		if src.contains(class_name_str):
			return node
	for child in node.get_children():
		var result: Node = _find_node_by_class(child, class_name_str)
		if result != null:
			return result
	return null

func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range

## F key — place held item if valid, or "[F] Shelf full" if no room.
## Falls back to scene-group lookup if _interaction_system wasn't injected
## (e.g. pre-placed shelves that bypass BuildModeController spawn).
func get_f_prompt() -> String:
	var isys: Node = _interaction_system
	if isys == null:
		isys = _resolve_interaction_system()
	if isys == null:
		return ""
	var item: RigidBody3D = isys.held_item
	if item == null:
		return ""
	var slot: int = _find_slot_for(item)
	if slot == -1:
		return "[F] Shelf full"
	return "[F] Place item"

## E key — always available when near shelf
func get_e_prompt() -> String:
	return "[E] Open shelf"

## Legacy shim
func get_interact_prompt() -> String:
	return get_f_prompt()

func get_prompt_world_pos() -> Vector3:
	return global_position + Vector3(0.0, unit_h + 0.3, 0.0)

## F pressed — place held item onto shelf. Returns true if there was
## something held to attempt placing (consumed the press), false if hands
## were empty (a no-op today, but the return value now matters to the
## F-dispatch's empty-handed fallback — see InteractionSystem.gd).
func on_f_interact() -> bool:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null:
		return false
	var item: RigidBody3D = _interaction_system.held_item
	if item != null:
		_try_place_item(item)
		return true
	return false

## E pressed — open the shelf UI overlay
func on_e_interact() -> void:
	if _storage_ui == null:
		push_warning("Shelving: _storage_ui not injected")
		return
	_storage_ui.open(self)

## Legacy shim
func on_interact() -> void:
	on_f_interact()

# ─── Slot finder ──────────────────────────────────────────────────────────────
## Returns the first slot index that accepts this item, or -1 if none.
## Rules:
##   1. Prefer a slot already containing the same item type (partial stack)
##   2. Fall back to the first empty slot
func _find_slot_for(item: RigidBody3D) -> int:
	var limit: int  = _get_stack_limit(item)
	var itype: String = _get_item_type(item)

	# Pass 1: partial stack of same type
	for i: int in slots.size():
		var stack: Array = slots[i]
		if stack.is_empty():
			continue
		if stack.size() >= limit:
			continue
		# Check type match
		if _get_item_type(stack[0]) == itype:
			return i

	# Pass 2: first empty slot
	for i: int in slots.size():
		if slots[i].is_empty():
			return i

	return -1   ## No room

# ─── Stacking placement offsets ───────────────────────────────────────────────
## Returns the local position offset for item at stack index `idx`,
## given the item type's layout. All relative to the slot marker's position.
##
## Layout reference:
##
##   CanCase (limit=2):
##     Stand upright. Stacks vertically — idx 0 = bottom, 1 = top.
##
##   WaterCase (limit=1):
##     Stand upright, single case per slot. No offset.
##
##   WaterBottle / FoodCan (limit=6):
##     Stand upright. 3 across (X) × 2 deep (Z).
##     idx 0-2 = front row, idx 3-5 = back row.
##
##   TestCrate (limit=1):
##     Single item, centered at slot marker. No offset.

const CASE_H_UPRIGHT: float = 0.34   ## Provisional standing height of one case, top-to-bottom. Tune in-editor per the note above.
const CASE_GAP_Y: float     = 0.004  ## Small gap between the two stacked cases (kept from the old constant)

## Bottle / can spacing
const BTLCAN_SPACE_X: float = 0.085  ## Spacing between columns
const BTLCAN_SPACE_Z: float = 0.110  ## Spacing front-to-back row

func _stack_offset(item: RigidBody3D, idx: int) -> Vector3:
	var limit: int = _get_stack_limit(item)

	## ── Can Case: limit=2, stacked vertically (one on top of the other) ──────
	if _get_item_type(item) == "can_case":
		## CASE_H_UPRIGHT is a first-pass estimate (CanCase is a .tscn scene,
		## not procedural, so its real AABB isn't visible from script). Verify
		## in-editor: if the top case floats above or clips into the bottom
		## one, adjust ONLY this constant.
		var oy: float = float(idx) * (CASE_H_UPRIGHT + CASE_GAP_Y)
		return Vector3(0.0, oy, 0.0)

	## ── Bottles / Cans: limit=6 ───────────────────────────────────────────────
	## 3 columns × 2 rows (depth). Front row first (idx 0-2), back row (idx 3-5).
	if limit == 6:
		var col: int  = idx % 3
		var row: int  = idx / 3
		var ox: float = (col - 1.0) * BTLCAN_SPACE_X
		var oz: float = (row - 0.5) * BTLCAN_SPACE_Z
		return Vector3(ox, 0.0, oz)

	## ── Crates (limit=1) or unknown ──────────────────────────────────────────
	return Vector3.ZERO

## Returns the rotation (degrees) for this item at stack position idx.
func _stack_rotation(item: RigidBody3D, idx: int) -> Vector3:
	var limit: int = _get_stack_limit(item)

	## Cases (CanCase / WaterCase): stand upright. Y=90 keeps the label facing
	## the player, matching the existing shelf-facing convention.
	var itype: String = _get_item_type(item)
	if itype == "can_case" or itype == "water_case":
		return Vector3(0.0, 90.0, 0.0)   ## Aug 2026 — stand upright (was -90° X, laid flat); Y=90 keeps label facing the player, matching the existing shelf-facing convention

	## Bottles/cans: perfectly upright — small natural lean removed for clean look
	if limit == 6:
		return Vector3.ZERO

	## Crates: flat, no rotation
	return Vector3.ZERO

# ─── Place (F) ────────────────────────────────────────────────────────────────
func _try_place_item(item: RigidBody3D) -> void:
	var slot: int = _find_slot_for(item)
	if slot == -1:
		## Aug 2026 fix — previously silent: no warning, and the item was
		## left stranded in the player's hand with no fallback. Shelving
		## has no "too big" concept (_find_slot_for() accepts any item
		## type into any empty slot) — -1 here always means genuinely
		## full. Now warns AND falls through to the same drop F would do
		## with nothing in range (InteractionSystem._quick_drop()),
		## matching LightStorage.gd's established too-big/full pattern —
		## bunkers get tight with furniture placed close together, so a
		## silent block here left players unable to drop OR pick up
		## anything near a full shelf without walking away first.
		NotificationManager.notify(UIKit.Domain.INVENTORY,
			NotificationManager.Severity.WARNING, "Shelf is full")
		_interaction_system._quick_drop()
		return

	## Release from InteractionSystem cleanly
	_interaction_system._is_holding_e = false

	if item.has_signal("knocked_out") and \
			item.knocked_out.is_connected(_interaction_system._on_item_knocked_out):
		item.knocked_out.disconnect(_interaction_system._on_item_knocked_out)

	## If from inventory, clear that slot without dropping
	if _interaction_system._held_from_slot != -1 and \
			_interaction_system.inventory != null:
		_interaction_system.inventory.retrieve_item(_interaction_system._held_from_slot)

	_interaction_system.held_item       = null
	_interaction_system._held_from_slot = -1

	if "is_held"        in item: item.is_held       = false
	if "_hold_point"    in item: item._hold_point   = null
	if "from_inventory" in item: item.from_inventory = false

	## Reparent to world root so it's not a child of the player
	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	if item.get_parent() != world_root:
		item.get_parent().remove_child(item)
		world_root.add_child(item)

	## Push onto stack and position
	var stack_idx: int = slots[slot].size()
	slots[slot].append(item)
	_place_item_in_slot(item, slot, stack_idx)
	item_placed.emit(slot, item)
	## Oct 2026 (NPC re-organizing): residents leave what the player put
	## away alone for a game day (StorageProfile.pinned).
	item.set_meta("player_placed_h", NPCClock.now())

## Animate an item flying from the player's hand to its shelf position,
## then freeze it in place once it arrives.
## Uses a Tween for smooth placement — item unfreezes briefly during flight,
## then locks solid when it lands.
func _place_item_in_slot(item: RigidBody3D, slot_idx: int, stack_idx: int) -> void:
	var pose: Array = _slot_pose(item, slot_idx, stack_idx)
	var target_pos: Vector3 = pose[0]
	var target_rot: Vector3 = pose[1]
	_finish_place_item(item, target_pos, target_rot)

## Final world [position, rotation] of `item` at `stack_idx` in `slot_idx`.
func _slot_pose(item: RigidBody3D, slot_idx: int, stack_idx: int) -> Array:
	## Compute final world position
	var base_pos: Vector3 = _slot_nodes[slot_idx].global_position

	## Extra per-type base lift so items don't clip into the shelf surface.
	## Cases lay flat → need a bit more lift off the shelf board.
	var iname: String = ""
	if "item_name" in item:
		iname = str(item.item_name).to_lower()
	var extra_lift: float = 0.0
	if _get_item_type(item) == "test_crate":
		## TestCrate's mesh pivot is centered on the item origin (the GLB is
		## shifted down half its height; bottom plate sits at -0.149 below the
		## origin). Without this lift the crate's origin lands at the marker
		## itself and ~0.15m of the model sinks through the shelf platform.
		## 0.083 = platform_top_offset(0.009) + half_crate_height(0.149) -
		## slot_lift(0.075), with a hair of clearance instead of exact flush
		## contact (avoids z-fighting).
		extra_lift = 0.083
	elif _get_stack_limit(item) == 4 and iname.contains("case"):
		extra_lift = 0.06   ## Cases laid flat — lift centre above shelf board
	elif _get_stack_limit(item) == 6:
		extra_lift = 0.05   ## Bottles/cans — minor lift so base doesn't clip

	base_pos.y += extra_lift

	var offset: Vector3   = _stack_offset(item, stack_idx)
	## Rotate offset into shelf's local space so it aligns with shelf facing
	var rot_offset: Vector3   = global_transform.basis * offset
	var target_pos: Vector3   = base_pos + rot_offset

	## Compute final world rotation
	var rot_deg: Vector3 = _stack_rotation(item, stack_idx)
	var target_rot: Vector3 = global_rotation + Vector3(
		deg_to_rad(rot_deg.x),
		deg_to_rad(rot_deg.y),
		deg_to_rad(rot_deg.z)
	)
	return [target_pos, target_rot]

func _finish_place_item(item: RigidBody3D, target_pos: Vector3, target_rot: Vector3) -> void:

	## Mark as shelved immediately — before the tween — so the item is blocked
	## from direct pickup even during the 0.22 s flight animation.
	if not item.is_in_group("shelved"):
		item.add_to_group("shelved")

	## Disable physics while flying so gravity doesn't fight the tween
	item.gravity_scale    = 0.0
	item.freeze           = false
	item.freeze_mode      = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.collision_layer  = 0
	item.collision_mask   = 0
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

	## Tween position + rotation to target over 0.22 s (snappy but visible)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(item, "global_position", target_pos, 0.22)
	tween.tween_property(item, "global_rotation",  target_rot,  0.22)

	## When tween finishes: freeze solid and re-enable collision so the item
	## can be interacted with normally (E on the shelf to retrieve it).
	tween.chain().tween_callback(func() -> void:
		item.gravity_scale   = 0.0
		item.freeze          = true
		item.freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
		## Keep layer=0 so no Area3D can ever detect a shelved item.
		## retrieve_to_carry / retrieve_to_inventory restore the layer on retrieval.
		item.collision_layer = 0
		item.collision_mask  = 0
		item.global_position = target_pos
		item.global_rotation = target_rot
		## Shelved = frozen + physics off + not an RVO obstacle (Aug 2026).
		if item.has_method("deactivate_dynamic_state"):
			item.deactivate_dynamic_state()
		## Leave the "pickup" group so the world-item scans (cleaning every 2s,
		## NPC fetch, etc.) never iterate stored items at all (Aug 2026).
		item.remove_from_group("pickup")
		## A frozen, "shelved" item still gets walked (and skipped) by
		## InteractionSystem's per-frame "interactable" scan — container-type
		## items (CanCase, WaterCase, Basket, …) join that group permanently
		## in their own _ready(), so without this every shelved one of those
		## pays the scan's per-node cost for the rest of the game regardless
		## of storage state. Pull them out while shelved.
		if item.is_in_group("interactable"):
			item.set_meta("_was_interactable", true)
			item.remove_from_group("interactable")
	)

# ─── Save/Load (Save/Load overhaul) ──────────────────────────────────────────
## Serializes every non-empty slot's item stack into item specs
## (ItemSaveData.gd). Backs the placed-object "storage" extra for the shelf
## family. Slot/stack order is preserved so items reload in the same place.
func get_storage_save_data() -> Dictionary:
	var contents: Array = []
	for i: int in slots.size():
		var stack: Array = slots[i]
		if stack.is_empty():
			continue
		var specs: Array = []
		for item: Variant in stack:
			specs.append(ItemSaveData.capture(item))
		contents.append({"slot": i, "stack": specs})
	return {"contents": contents}

## Rebuilds shelved items from get_storage_save_data()'s output. Spawns each
## item into the world root, then reuses _place_item_in_slot() (the same
## placement path a live store uses) so frozen/shelved/pickup-excluded state
## all settle identically. A freshly-restored shelf has no existing contents.
func restore_storage_save_data(data: Dictionary) -> void:
	var world_root: Node3D = get_tree().get_first_node_in_group("world") as Node3D
	if world_root == null:
		world_root = get_parent() as Node3D
	if world_root == null:
		return
	for entry: Dictionary in data.get("contents", []):
		var slot: int = int(entry.get("slot", -1))
		if slot < 0 or slot >= slots.size():
			continue
		for spec: Variant in entry.get("stack", []):
			if not (spec is Dictionary):
				continue
			var item: Node = ItemSaveData.spawn(spec as Dictionary, world_root)
			if item == null:
				continue
			var stack_idx: int = slots[slot].size()
			slots[slot].append(item)
			_place_item_in_slot(item as RigidBody3D, slot, stack_idx)

## NPC Pass 2, Part 3 — NPC-side retrieval. Mirrors retrieve_to_carry()'s
## un-shelving mechanics exactly (group removal, freeze/collision restore),
## minus the InteractionSystem bookkeeping, then hands the item to the NPC's
## hold point via the standard pickup() path. Returns the item or null.
func npc_retrieve(slot_idx: int, npc_hold_point: Node3D) -> RigidBody3D:
	if slot_idx < 0 or slot_idx >= slots.size():
		return null
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return null
	var item: RigidBody3D = stack.pop_back()
	_cancel_move(item)
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")
	if item.has_meta("_was_interactable"):
		item.add_to_group("interactable")
		item.remove_meta("_was_interactable")
	item.freeze           = false
	item.freeze_mode      = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.collision_layer  = 2
	item.collision_mask   = 1
	item.gravity_scale    = 1.0
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	if "from_inventory" in item:
		item.from_inventory = false
	## Aug 2026 fix — mirrors retrieve_to_carry()'s own fix just above (see
	## its comment): unfreezing an item still sitting at its shelf-slot
	## position risks tunneling through the shelf's own StaticBody3D
	## collision (posts, platforms) on the way to the hold point.
	## retrieve_to_carry() already teleports to a safe spot before calling
	## pickup(); this NPC path never got the same fix — confirmed as the
	## cause of a Can/Water Case unfreezing INSIDE the shelf and falling
	## straight through onto the floor instead of chasing to the NPC's
	## hand (larger items sit deeper in the shelf's own geometry, making
	## this far more visible for cases than for a filter or a single can).
	## Using the hold point's own position directly, since it's already the
	## exact target — no need to derive a chest-height offset the way
	## carry_spawn_position() does for the player path.
	if npc_hold_point != null:
		item.global_position = npc_hold_point.global_position
	if item.has_method("pickup"):
		item.pickup(npc_hold_point)
	item_retrieved.emit(slot_idx, item)
	return item

## NPC-side placement (Aug 2026, Cleaning) — mirrors _try_place_item()
## exactly for the actual shelving math/animation (reuses
## _find_slot_for()/_place_item_in_slot() directly, unchanged), but
## sources the item from an NPC's held_item instead of the player's
## InteractionSystem and skips all the InteractionSystem-specific
## bookkeeping (inventory slot clearing, knocked_out signal) that simply
## doesn't apply to NPCs. Returns false if the shelf has no room — caller
## decides what to do next (CleaningActivity just sets the item back
## down rather than carrying it forever).
## Oct 2026: `slot` (optional) is where the resident wants it
## (StorageProfile.best_shelf_slot: big things low, its own type beside it);
## anything invalid falls back to the usual first-free choice.
func npc_try_place_item(npc: Node, item: RigidBody3D, slot_choice: int = -1) -> bool:
	var slot: int = slot_choice if slot_choice >= 0 and can_place_in_slot(item, slot_choice) else _find_slot_for(item)
	if slot == -1:
		return false

	if "held_item" in npc and npc.held_item == item:
		npc.held_item = null

	## Mirror _try_place_item()'s (player path) held-state clear exactly.
	## Without this, the item's own is_held/_hold_point stay set to the
	## NPC that carried it here — PickupableItem._physics_process() then
	## keeps measuring distance against the NPC's (now walking-away)
	## hold point every frame, and once that exceeds KNOCK_DISTANCE for
	## KNOCK_LINGER_TIME, _do_knocked_out() fires and un-freezes/ejects
	## the item off the shelf. This was the actual cause of shelved
	## items popping back out ~1s after an NPC placed them.
	if "is_held"        in item: item.is_held       = false
	if "_hold_point"    in item: item._hold_point   = null
	if "from_inventory" in item: item.from_inventory = false

	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	if item.get_parent() != world_root:
		item.get_parent().remove_child(item)
		world_root.add_child(item)

	var stack_idx: int = slots[slot].size()
	slots[slot].append(item)
	_place_item_in_slot(item, slot, stack_idx)
	item_placed.emit(slot, item)
	return true

## Can this item go in this slot: empty, or a partial stack of the same
## type with room (the same rules _find_slot_for() applies).
func can_place_in_slot(item: RigidBody3D, slot_idx: int) -> bool:
	if item == null or slot_idx < 0 or slot_idx >= slots.size():
		return false
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return true
	return stack.size() < _get_stack_limit(item) and _get_item_type(stack[0]) == _get_item_type(item)

## Public capacity check, used so a full shelf isn't chosen as a
## destination in the first place — see NPC.find_cleaning_destination().
func has_room_for(item: RigidBody3D) -> bool:
	return _find_slot_for(item) != -1

## Aug 2026 — generic "does this shelf have ANY free space at all" check,
## independent of a specific item's type. Used by
## NPC.has_viable_destination_for_category() to answer "does storage
## exist for this classification" without needing a representative item
## on hand — has_room_for(item) needs a real item to test slot-type
## matching, this doesn't. Deliberately conservative: an empty slot
## always counts, even though a specific item might ALSO fit into a
## same-type partial stack with no fully-empty slot left — fine for an
## availability estimate, not for an actual placement decision.
func has_free_space() -> bool:
	for stack: Array in slots:
		if stack.is_empty():
			return true
	return false

# ─── Retrieve to carry (from StorageUI's primary "Carry" button) ─────────────
## Pops the top item from the slot's stack and gives it to the player's hand.
## Returns true on success — Aug 2026, part of the StorageUI contract
## (get_slot_display/take_for_carry/take_for_inventory), see §7.4 below.
func retrieve_to_carry(slot_idx: int, isys: Node) -> bool:
	if slot_idx < 0 or slot_idx >= slots.size():
		return false
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return false
	if isys.held_item != null:
		return false   ## Hands full — UI should have blocked this already

	## Pop from top of stack
	var item: RigidBody3D = stack.pop_back()
	_cancel_move(item)

	## Remove shelved guard so pickup is allowed again
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")
	if item.has_meta("_was_interactable"):
		item.add_to_group("interactable")
		item.remove_meta("_was_interactable")

	item.freeze           = false
	item.freeze_mode      = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.collision_layer  = 2
	item.collision_mask   = 1
	item.gravity_scale    = 1.0
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

	if item.has_signal("knocked_out") and \
			not item.knocked_out.is_connected(isys._on_item_knocked_out):
		item.knocked_out.connect(isys._on_item_knocked_out)

	if "from_inventory" in item:
		item.from_inventory = false

	item.global_position = Shelving.carry_spawn_position(isys)   ## Aug 2026 fix — was left at the shelf slot, could tunnel through a wall on the way to the player

	if item.has_method("pickup"):
		item.pickup(isys.hold_point)

	isys.held_item       = item
	isys._held_from_slot = -1
	item_retrieved.emit(slot_idx, item)
	return true

# ─── Retrieve to inventory (from StorageUI's secondary "Add to inventory" button) ─
## Returns true on success — Aug 2026, part of the StorageUI contract.
func retrieve_to_inventory(slot_idx: int, inv: Node) -> bool:
	if slot_idx < 0 or slot_idx >= slots.size():
		return false
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return false

	var item: RigidBody3D = stack.pop_back()
	_cancel_move(item)

	## Remove shelved guard before handing to inventory
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")
	if item.has_meta("_was_interactable"):
		item.add_to_group("interactable")
		item.remove_meta("_was_interactable")

	item.freeze          = false
	item.visible         = true
	item.collision_layer = item.rest_collision_layer()
	item.collision_mask  = item._rest_collision_mask()
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	if item.has_method("restore_dynamic_state"):
		item.restore_dynamic_state()   ## back to a live item (Aug 2026)

	inv.add_item(item)
	item_retrieved.emit(slot_idx, item)
	return true

# ─── Eject all on deconstruct ─────────────────────────────────────────────────
func eject_all_items() -> void:
	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()

	for i: int in slots.size():
		var stack: Array = slots[i]
		for item: RigidBody3D in stack:
			_cancel_move(item)
			if item == null:
				continue
			if item.get_parent() != world_root:
				item.get_parent().remove_child(item)
				world_root.add_child(item)
			if item.is_in_group("shelved"):
				item.remove_from_group("shelved")
			if item.has_meta("_was_interactable"):
				item.add_to_group("interactable")
				item.remove_meta("_was_interactable")
			item.freeze          = false
			item.freeze_mode     = RigidBody3D.FREEZE_MODE_KINEMATIC
			item.gravity_scale   = 1.0
			item.collision_layer = item.rest_collision_layer()
			item.collision_mask  = item._rest_collision_mask()
			item.linear_velocity  = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
			if item.has_method("restore_dynamic_state"):
				item.restore_dynamic_state()   ## ejected to the floor — live again (Aug 2026)
			item.add_to_group("pickup")   ## back in the world-item scans (Aug 2026)
			item.global_position = global_position + Vector3(
				randf_range(-0.5, 0.5), 0.8, randf_range(-0.4, 0.4))
			item.apply_central_impulse(Vector3(
				randf_range(-1.0, 1.0), 2.0, randf_range(-0.8, 0.8)))
		slots[i].clear()

# ─── Ghost mesh ───────────────────────────────────────────────────────────────
static func build_ghost_mesh() -> ArrayMesh:
	var W: float = 1.0
	var H: float = 2.0
	var D: float = 0.5
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ghost_box(st, Vector3(0.0, H * 0.5, 0.0), Vector3(W, H, D))
	st.generate_normals()
	return st.commit()

static func _ghost_box(st: SurfaceTool, centre: Vector3, size: Vector3) -> void:
	var hx: float = size.x * 0.5;  var hy: float = size.y * 0.5;  var hz: float = size.z * 0.5
	var cx: float = centre.x;      var cy: float = centre.y;      var cz: float = centre.z
	var f: Array = [
		[Vector3(cx+hx,cy-hy,cz-hz),Vector3(cx+hx,cy+hy,cz-hz),Vector3(cx+hx,cy+hy,cz+hz),
		 Vector3(cx+hx,cy-hy,cz-hz),Vector3(cx+hx,cy+hy,cz+hz),Vector3(cx+hx,cy-hy,cz+hz)],
		[Vector3(cx-hx,cy-hy,cz+hz),Vector3(cx-hx,cy+hy,cz+hz),Vector3(cx-hx,cy+hy,cz-hz),
		 Vector3(cx-hx,cy-hy,cz+hz),Vector3(cx-hx,cy+hy,cz-hz),Vector3(cx-hx,cy-hy,cz-hz)],
		[Vector3(cx-hx,cy+hy,cz-hz),Vector3(cx-hx,cy+hy,cz+hz),Vector3(cx+hx,cy+hy,cz+hz),
		 Vector3(cx-hx,cy+hy,cz-hz),Vector3(cx+hx,cy+hy,cz+hz),Vector3(cx+hx,cy+hy,cz-hz)],
		[Vector3(cx-hx,cy-hy,cz+hz),Vector3(cx-hx,cy-hy,cz-hz),Vector3(cx+hx,cy-hy,cz-hz),
		 Vector3(cx-hx,cy-hy,cz+hz),Vector3(cx+hx,cy-hy,cz-hz),Vector3(cx+hx,cy-hy,cz+hz)],
		[Vector3(cx-hx,cy-hy,cz+hz),Vector3(cx+hx,cy-hy,cz+hz),Vector3(cx+hx,cy+hy,cz+hz),
		 Vector3(cx-hx,cy-hy,cz+hz),Vector3(cx+hx,cy+hy,cz+hz),Vector3(cx-hx,cy+hy,cz+hz)],
		[Vector3(cx+hx,cy-hy,cz-hz),Vector3(cx-hx,cy-hy,cz-hz),Vector3(cx-hx,cy+hy,cz-hz),
		 Vector3(cx+hx,cy-hy,cz-hz),Vector3(cx-hx,cy+hy,cz-hz),Vector3(cx+hx,cy+hy,cz-hz)],
	]
	for face: Array in f:
		for v: Vector3 in face:
			st.add_vertex(v)

# ─── Helpers ──────────────────────────────────────────────────────────────────
## Returns true if every slot's stack is at its limit for this item type,
## and there are no empty slots left.
func is_slot_full_for(item: RigidBody3D) -> bool:
	return _find_slot_for(item) == -1

func slot_count(slot_idx: int) -> int:
	if slot_idx < 0 or slot_idx >= slots.size():
		return 0
	return slots[slot_idx].size()

func slot_top_item(slot_idx: int) -> RigidBody3D:
	if slot_idx < 0 or slot_idx >= slots.size():
		return null
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return null
	return stack[stack.size() - 1]

func slot_is_empty(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= slots.size():
		return true
	return slots[slot_idx].is_empty()

func _first_empty_slot() -> int:
	for i: int in slots.size():
		if slots[i].is_empty(): return i
	return -1

# ─── Moving a stored stack (Oct 2026, StorageUI "Move") ──────────────────────
## The whole stack in `from_idx` moves to `to_idx`. Rules (same as placing):
## the target is empty, or holds the same item type with room for the whole
## stack. Nothing a resident has claimed (about to fetch) moves, and nothing
## moves onto a claimed stack.
const MOVE_CLEARANCE: float = 0.22   ## how far past the shelf face items travel
const MOVE_OUT_TIME: float = 0.16
const MOVE_IN_TIME: float = 0.16
const MOVE_STAGGER: float = 0.04

func can_move_slot(from_idx: int, to_idx: int) -> bool:
	if from_idx == to_idx or from_idx < 0 or to_idx < 0 \
			or from_idx >= slots.size() or to_idx >= slots.size():
		return false
	var source: Array = slots[from_idx]
	var target: Array = slots[to_idx]
	if source.is_empty():
		return false
	for item: Variant in source + target:
		if is_instance_valid(item) and NPCItemUser.is_claimed_by_anyone(item):
			return false
	if target.is_empty():
		return true
	var lead: RigidBody3D = source[0]
	return _get_item_type(target[0]) == _get_item_type(lead) \
		and target.size() + source.size() <= _get_stack_limit(lead)

## Moves the stack and animates each item out past the shelf face (the side
## nearer `viewer`, so nothing clips the posts or its neighbours), across to
## the new slot while still clear, then back in. `slots` updates at once, so
## saves and NPC queries see the new layout immediately.
func move_slot(from_idx: int, to_idx: int, viewer: Node3D = null) -> bool:
	if not can_move_slot(from_idx, to_idx):
		return false
	var moving: Array = slots[from_idx].duplicate()
	slots[from_idx].clear()
	var side: float = 1.0
	if viewer != null and is_instance_valid(viewer):
		side = 1.0 if to_local(viewer.global_position).z >= 0.0 else -1.0
	var face_z: float = side * (unit_d * 0.5 + MOVE_CLEARANCE)
	for k: int in moving.size():
		var item: RigidBody3D = moving[k]
		var stack_idx: int = slots[to_idx].size()
		slots[to_idx].append(item)
		## Residents leave what the player arranged alone for a game day.
		item.set_meta("player_placed_h", NPCClock.now())
		_animate_move(item, to_idx, stack_idx, face_z, k * MOVE_STAGGER)
		item_moved.emit(from_idx, to_idx, item)
	return true

func _animate_move(item: RigidBody3D, slot_idx: int, stack_idx: int, face_z: float,
		delay: float) -> void:
	_cancel_move(item)
	var pose: Array = _slot_pose(item, slot_idx, stack_idx)
	var target_pos: Vector3 = pose[0]
	var target_rot: Vector3 = pose[1]
	var start_local: Vector3 = to_local(item.global_position)
	var end_local: Vector3 = to_local(target_pos)
	var out_start: Vector3 = to_global(Vector3(start_local.x, start_local.y, face_z))
	var out_end: Vector3 = to_global(Vector3(end_local.x, end_local.y, face_z))
	var across: float = clampf(0.14 + out_start.distance_to(out_end) * 0.22, 0.18, 0.5)
	var tween: Tween = item.create_tween()
	item.set_meta("_shelf_move_tween", tween)
	tween.tween_interval(delay)
	tween.tween_property(item, "global_position", out_start, MOVE_OUT_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "global_position", out_end, across) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(item, "global_rotation", target_rot, across)
	tween.tween_property(item, "global_position", target_pos, MOVE_IN_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		item.global_position = target_pos
		item.global_rotation = target_rot
		item.remove_meta("_shelf_move_tween"))

## An item leaving storage mid-move must not be pulled back to the shelf.
func _cancel_move(item: Node) -> void:
	if item == null or not is_instance_valid(item) or not item.has_meta("_shelf_move_tween"):
		return
	var tween: Variant = item.get_meta("_shelf_move_tween")
	if tween is Tween and (tween as Tween).is_valid():
		(tween as Tween).kill()
	item.remove_meta("_shelf_move_tween")

# ─── StorageUI contract (Aug 2026 — Storage UI Unification pass) ────────────
## Thin wrappers over this file's own pre-existing slot_top_item()/
## slot_count()/retrieve_to_carry()/retrieve_to_inventory() — none of that
## existing logic changed beyond the bool-return additions in §7.3/§7.4
## above, including NPC-facing npc_retrieve() and the item_placed/
## item_retrieved signals other systems already depend on.
func get_slot_display(slot_idx: int) -> Array:
	return [slot_top_item(slot_idx), slot_count(slot_idx)]

func take_for_carry(slot_idx: int, isys: Node) -> bool:
	return retrieve_to_carry(slot_idx, isys)

func take_for_inventory(slot_idx: int, inv: Node) -> bool:
	return retrieve_to_inventory(slot_idx, inv)

func get_ui_config() -> Dictionary:
	var tiers: int = shelf_y.size()
	## visual position -> data slot. Data slots are bottom-up; the UI panel
	## reads top-to-bottom matching the physical shelf, so visual row 0
	## (top of panel) shows the TOP tier's data slots. Generalizes the
	## existing 10-slot [8,9,6,7,4,5,2,3,0,1] mapping to any tier/column count.
	var order: Array[int] = []
	for visual_row: int in tiers:
		var data_tier: int = tiers - 1 - visual_row
		for col: int in slots_per_tier:
			order.append(data_tier * slots_per_tier + col)
	return {
		"title": display_name.to_upper(),
		"slot_count": slots.size(),
		"grid_cols": slots_per_tier,
		"grid_rows": tiers,
		"display_order": order,
		"supports_stacking": true,
		"primary_button_icon": "carry",
		"primary_button_tooltip": "Carry",
		"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
		"primary_requires_empty_hands": true,
		"closes_on_action": true,
	}
