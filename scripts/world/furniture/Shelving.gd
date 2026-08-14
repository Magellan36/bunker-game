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

# ─── Interaction ──────────────────────────────────────────────────────────────
var _player_in_range: bool    = false
var _interaction_system: Node = null   ## Injected by BuildModeController after spawn
var _storage_ui: Node         = null   ## Injected by MainWorld after spawn (Aug 2026 — the shared StorageUI, was _shelf_ui)

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
	var metal_mat: StandardMaterial3D = StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.60, 0.62, 0.65, 1.0)
	metal_mat.roughness    = 0.4
	metal_mat.metallic     = 0.5

	var shelf_mat: StandardMaterial3D = StandardMaterial3D.new()
	shelf_mat.albedo_color = Color(0.55, 0.57, 0.60, 1.0)
	shelf_mat.roughness    = 0.4
	shelf_mat.metallic     = 0.5

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
	for corner: Vector2 in corners:
		## Vertical bar
		var post_mi: MeshInstance3D = MeshInstance3D.new()
		var post: BoxMesh = BoxMesh.new()
		post.size = Vector3(post_w, post_h, post_d)
		post_mi.mesh = post
		post_mi.position = Vector3(corner.x, post_h * 0.5 - post_y_offset, corner.y)
		post_mi.set_surface_override_material(0, metal_mat)
		add_child(post_mi)

		## Horizontal lip (front-facing L-bracket detail)
		var lip_mi: MeshInstance3D = MeshInstance3D.new()
		var lip: BoxMesh = BoxMesh.new()
		lip.size = Vector3(post_w, 0.015, 0.008)
		lip_mi.mesh = lip
		lip_mi.position = Vector3(corner.x, post_h * 0.5 - post_y_offset, corner.y - post_d * 0.5 - 0.004)
		lip_mi.set_surface_override_material(0, metal_mat)
		add_child(lip_mi)

	## Slot notches on each post (small horizontal marks for adjustable shelves)
	for corner: Vector2 in corners:
		for sy: float in shelf_y:
			for n: int in range(-1, 2):
				var notch_mi: MeshInstance3D = MeshInstance3D.new()
				var notch: BoxMesh = BoxMesh.new()
				notch.size = Vector3(post_w + 0.005, 0.004, 0.003)
				notch_mi.mesh = notch
				notch_mi.position = Vector3(corner.x, sy + float(n) * 0.012, corner.y - post_d * 0.5 - 0.002)
				notch_mi.set_surface_override_material(0, metal_mat)
				add_child(notch_mi)

	## Shelf platforms — span full width, posts sit inside
	for sy: float in shelf_y:
		var shelf_mi: MeshInstance3D = MeshInstance3D.new()
		var shelf: BoxMesh = BoxMesh.new()
		shelf.size = Vector3(unit_w, 0.018, unit_d)
		shelf_mi.mesh = shelf
		shelf_mi.position = Vector3(0.0, sy, 0.0)
		shelf_mi.set_surface_override_material(0, shelf_mat)
		add_child(shelf_mi)

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
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Shelf is full")
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

## Animate an item flying from the player's hand to its shelf position,
## then freeze it in place once it arrives.
## Uses a Tween for smooth placement — item unfreezes briefly during flight,
## then locks solid when it lands.
func _place_item_in_slot(item: RigidBody3D, slot_idx: int, stack_idx: int) -> void:
	## Compute final world position
	var base_pos: Vector3 = _slot_nodes[slot_idx].global_position

	## Extra per-type base lift so items don't clip into the shelf surface.
	## Cases lay flat → need a bit more lift off the shelf board.
	var iname: String = ""
	if "item_name" in item:
		iname = str(item.item_name).to_lower()
	var extra_lift: float = 0.0
	if _get_item_type(item) == "test_crate":
		## Aug 2026 — TestCrate's mesh pivot is centered (bottom plate sits at
		## -H*0.5+T*0.5 = -0.231 below the item's own origin; see
		## TestCrate._build_placeholder_mesh()). Without this lift the crate's
		## origin lands at the marker itself and ~0.23m of the model sinks
		## through the shelf platform below it — this is the reported bug.
		## 0.18 = platform_top_offset(0.009) + half_crate_height(0.24) -
		## slot_lift(0.075), rounded down ~0.006 for a hair of visible
		## clearance instead of exact flush contact (avoids z-fighting).
		extra_lift = 0.18
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
	)

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
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")
	item.freeze           = false
	item.freeze_mode      = RigidBody3D.FREEZE_MODE_KINEMATIC
	item.collision_layer  = 2
	item.collision_mask   = 1
	item.gravity_scale    = 1.0
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	if "from_inventory" in item:
		item.from_inventory = false
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
func npc_try_place_item(npc: Node, item: RigidBody3D) -> bool:
	var slot: int = _find_slot_for(item)
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

	## Remove shelved guard so pickup is allowed again
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")

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

	## Remove shelved guard before handing to inventory
	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")

	item.freeze          = false
	item.visible         = true
	item.collision_layer = 1
	item.collision_mask  = 1
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO

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
			if item == null:
				continue
			if item.get_parent() != world_root:
				item.get_parent().remove_child(item)
				world_root.add_child(item)
			if item.is_in_group("shelved"):
				item.remove_from_group("shelved")
			item.freeze          = false
			item.freeze_mode     = RigidBody3D.FREEZE_MODE_KINEMATIC
			item.gravity_scale   = 1.0
			item.collision_layer = 1
			item.collision_mask  = 1
			item.linear_velocity  = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
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
