extends StaticBody3D
class_name Shelving
## Shelving.gd
## Buildable/deconstructible shelf unit. Mesh loaded from GLB asset.
## 3 tiers × 2 slots = 6 storage slots. Each slot is a STACK — multiple
## small items can share one slot up to a type-specific limit.
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
## Slot layout (shelf 0 = bottom, shelf 2 = top):
##   Slot 0 = shelf 0, left    Slot 1 = shelf 0, right
##   Slot 2 = shelf 1, left    Slot 3 = shelf 1, right
##   Slot 4 = shelf 2, left    Slot 5 = shelf 2, right

# ─── Asset ────────────────────────────────────────────────────────────────────
const MODEL_PATH: String = "res://assets/models/steel_frame_shelves_01_4k.glb"

# ─── Tunable dimensions ───────────────────────────────────────────────────────
@export var unit_w: float = 1.0
@export var unit_h: float = 2.0
@export var unit_d: float = 0.5

@export var shelf_y: Array[float] = [0.18, 0.62, 1.06]
@export var slot_offset_x: float  = 0.22
@export var slot_lift: float      = 0.06

# ─── Slot state ───────────────────────────────────────────────────────────────
## Each slot is an Array of RigidBody3D items (a stack).
## slots[i] = [] means empty, slots[i].size() = count in that slot.
var slots: Array = [[], [], [], [], [], []]
var _slot_nodes: Array = []   ## Marker3D for each slot's base world position

# ─── Interaction ──────────────────────────────────────────────────────────────
var _player_in_range: bool    = false
var _interaction_system: Node = null   ## Injected by BuildModeController after spawn
var _shelf_ui: Node           = null   ## Injected by MainWorld after spawn

# ─── Signals ──────────────────────────────────────────────────────────────────
signal item_placed(slot_index: int, item: RigidBody3D)
signal item_retrieved(slot_index: int, item: RigidBody3D)

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("interactable")
	add_to_group("shelving")
	## Layer 1 = player collision, Layer 3 (bit value 4) = build hover raycast.
	## Must match the layer set on wall/pillar placed objects (also 5).
	collision_layer = 5
	collision_mask  = 0
	_load_mesh()
	_build_slot_markers()
	_build_collision()

# ─── Mesh ─────────────────────────────────────────────────────────────────────
func _load_mesh() -> void:
	var scene: PackedScene = load(MODEL_PATH)
	if scene == null:
		push_error("Shelving: failed to load model at " + MODEL_PATH)
		var mi: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(unit_w, unit_h, unit_d)
		mi.mesh = bm
		mi.position = Vector3(0.0, unit_h * 0.5, 0.0)
		add_child(mi)
		return
	var instance: Node3D = scene.instantiate()
	instance.position = Vector3.ZERO
	add_child(instance)

# ─── Slot markers ─────────────────────────────────────────────────────────────
func _build_slot_markers() -> void:
	_slot_nodes.clear()
	## Right-side slots get an extra nudge away from the left wall.
	## slot_offset_x already separates left/right; right_extra shifts them slightly further right.
	const right_extra: float = 0.06
	for tier: int in shelf_y.size():
		for side: int in 2:
			var base_x: float = slot_offset_x * (1.0 if side == 1 else -1.0)
			var x: float = base_x + (right_extra if side == 1 else 0.0)
			var y: float  = shelf_y[tier] + slot_lift
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

## F pressed — place held item onto shelf
func on_f_interact() -> void:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null:
		return
	var item: RigidBody3D = _interaction_system.held_item
	if item != null:
		_try_place_item(item)

## E pressed — open the shelf UI overlay
func on_e_interact() -> void:
	if _shelf_ui == null:
		push_warning("Shelving: _shelf_ui not injected")
		return
	_shelf_ui.open(self)

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
	for i: int in 6:
		var stack: Array = slots[i]
		if stack.is_empty():
			continue
		if stack.size() >= limit:
			continue
		# Check type match
		if _get_item_type(stack[0]) == itype:
			return i

	# Pass 2: first empty slot
	for i: int in 6:
		if slots[i].is_empty():
			return i

	return -1   ## No room

# ─── Stacking placement offsets ───────────────────────────────────────────────
## Returns the local position offset for item at stack index `idx`,
## given the item type's layout. All relative to the slot marker's position.
##
## Layout reference (matches player's drawn diagram):
##
##   WaterCase / CanCase  (limit=4):
##     Lay flat (rotated 90° on X so label faces the player).
##     2 wide (X) × 2 tall (Y) — front view shows a 2×2 block.
##     idx 0 = bottom-left, 1 = bottom-right, 2 = top-left, 3 = top-right.
##     Each case is roughly 0.30 W × 0.12 H × 0.20 D when upright,
##     so laid flat it becomes ~0.30 W × 0.20 H × 0.12 D (H is its depth).
##     case_w=0.32 (X spacing), case_h=0.22 (Y lift per layer).
##
##   WaterBottle / FoodCan (limit=6):
##     Stand upright. 3 across (X) × 2 deep (Z).
##     idx 0-2 = front row, idx 3-5 = back row.
##
##   TestCrate (limit=1):
##     Single item, centered at slot marker. No offset.

## Approximate case dimensions when laid flat (label face = front/back ±Z):
const CASE_W: float    = 0.300   ## Width  along X (left-right on shelf)
const CASE_H_LAY: float = 0.200  ## Height along Y when laid flat (~depth when upright)
const CASE_GAP_X: float = 0.005  ## Small gap between side-by-side cases
const CASE_GAP_Y: float = 0.004  ## Small gap between stacked layers

## Bottle / can spacing
const BTLCAN_SPACE_X: float = 0.085  ## Spacing between columns
const BTLCAN_SPACE_Z: float = 0.110  ## Spacing front-to-back row

func _stack_offset(item: RigidBody3D, idx: int) -> Vector3:
	var limit: int = _get_stack_limit(item)

	var iname: String = ""
	if "item_name" in item:
		iname = str(item.item_name).to_lower()

	## ── Cases (WaterCase / CanCase): limit=4 ─────────────────────────────────
	## 2-wide × 2-tall block, cases laid flat.
	## Bottom layer: idx 0 (left), 1 (right). Top layer: idx 2 (left), 3 (right).
	if limit == 4 and (iname.contains("case")):
		var col: int   = idx % 2        ## 0=left, 1=right
		var layer: int = idx / 2        ## 0=bottom, 1=top
		## Centre the pair around X=0
		var ox: float  = (col - 0.5) * (CASE_W + CASE_GAP_X)
		## Stack upward — each layer lifts by the laid-flat height
		var oy: float  = layer * (CASE_H_LAY + CASE_GAP_Y)
		## Centred on shelf depth (no Z offset)
		return Vector3(ox, oy, 0.0)

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
	var iname: String = ""
	if "item_name" in item:
		iname = str(item.item_name).to_lower()

	## Cases: lay flat (-90° X) + 90° Y so the long axis runs shelf-depth-wise
	## (label face pointing toward player rather than along the shelf width).
	if limit == 4 and iname.contains("case"):
		return Vector3(-90.0, 90.0, 0.0)

	## Bottles/cans: perfectly upright — small natural lean removed for clean look
	if limit == 6:
		return Vector3.ZERO

	## Crates: flat, no rotation
	return Vector3.ZERO

# ─── Place (F) ────────────────────────────────────────────────────────────────
func _try_place_item(item: RigidBody3D) -> void:
	var slot: int = _find_slot_for(item)
	if slot == -1:
		return

	## Release from InteractionSystem cleanly
	_interaction_system._is_holding_e = false
	_interaction_system._store_hold_t = 0.0
	_interaction_system._use_pending  = false

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
	if _get_stack_limit(item) == 4 and iname.contains("case"):
		extra_lift = 0.06   ## Cases laid flat — lift centre above shelf board
	elif _get_stack_limit(item) == 6:
		extra_lift = 0.05   ## Bottles/cans — minor lift so base doesn't clip
	## Crates: slot_lift in _build_slot_markers already handles this

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

# ─── Retrieve to carry (from ShelfUI "Carry" button) ─────────────────────────
## Pops the top item from the slot's stack and gives it to the player's hand.
func retrieve_to_carry(slot_idx: int, isys: Node) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return
	if isys.held_item != null:
		return   ## Hands full — UI should have blocked this already

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

	if item.has_method("pickup"):
		item.pickup(isys.hold_point)

	isys.held_item       = item
	isys._held_from_slot = -1
	item_retrieved.emit(slot_idx, item)

# ─── Retrieve to inventory (from ShelfUI "Inv." button) ──────────────────────
func retrieve_to_inventory(slot_idx: int, inv: Node) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var stack: Array = slots[slot_idx]
	if stack.is_empty():
		return

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
