extends StaticBody3D
class_name LightStorage
## LightStorage.gd
## Shared base for furniture with hidden internal storage of LIGHT items —
## eligibility is exactly the "inventory_item" group (same set as pocket
## inventory). No stacking, no slot geometry, no visible stored meshes:
## stored items are frozen, hidden, collision-disabled children of this node.
##
## Joins the "shelving" group on purpose: that group is InteractionSystem's
## duck-typed E/F container contract (on_e_interact / on_f_interact /
## get_e_prompt / get_f_prompt / get_prompt_world_pos), NOT "is literally a
## shelf". The Aug 2026 E distance-fairness rule applies automatically.
## Subclasses override _build_mesh() and set the storage shape in _init().
##
## UI: opened via the shared StorageUI (the same instance Shelving uses) —
## this file implements the StorageUI contract (get_ui_config /
## get_slot_display / take_for_carry / take_for_inventory) so no separate
## UI script is needed.
##
## Storage model: a FIXED-SIZE slot array of length `capacity` (null-padded).
## StorageUI addresses slots positionally via get_slot_display(slot_idx), so
## indices MUST stay stable when a middle slot is emptied — never append/
## remove, always write/clear by index. Storing fills the first null slot.

@export var capacity: int          = 2
@export var display_name: String   = "End Table"
@export var prompt_height: float   = 1.2   ## get_prompt_world_pos Y offset
@export var grid_cols: int         = 2
@export var grid_rows: int         = 1
@export var row_labels: Array[String] = []

## Fixed-size slot array — length == capacity, null = empty. See header.
var stored: Array[RigidBody3D] = []

## Injected by MainWorld._setup_storage_ui() (property-name checks at
## MainWorld.gd:575-580) and by the spawn_structure() branch (mid-session
## placement) — same convention as Shelving's _storage_ui / _interaction_system.
var _storage_ui: Node          = null
var _interaction_system: Node  = null

## Full-fidelity preview convention — see Bed.gd / Shelving.gd / Table.gd.
## Set TRUE by preview code BEFORE add_child(). Guard skips groups only;
## mesh building always runs (GrowLight Aug 2026 lesson: guard AFTER mesh).
var _is_preview_only: bool = false

func _ready() -> void:
	collision_layer = 5   ## wall/pillar/shelving/table convention
	collision_mask  = 0
	stored.resize(capacity)
	_build_mesh()
	if _is_preview_only:
		return
	add_to_group("shelving")
	## Aug 2026 fix — Shelving.gd joins BOTH "interactable" and "shelving";
	## this file only joined "shelving", which InteractionSystem's Pass 2
	## (the static-body scan) explicitly EXCLUDES on purpose (its own
	## comment claims shelving-group objects are "handled separately" —
	## that separate handling is Pass 1, which requires "interactable" OR
	## "pickup" membership). Without this line, End Table/Dresser fell into
	## the gap between both passes and never became a prompt candidate at
	## all — not a display bug, they were simply never scanned.
	add_to_group("interactable")

## Subclasses MUST override.
func _build_mesh() -> void:
	push_warning("LightStorage subclass missing _build_mesh() override")

func is_full() -> bool:
	return _first_null_slot() == -1

func _first_null_slot() -> int:
	for i: int in stored.size():
		if stored[i] == null:
			return i
	return -1

# ─── E/F contract (mirrors Shelving.gd) ────────────────────────────────────
func on_f_interact() -> void:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null:
		return
	var item: RigidBody3D = _interaction_system.held_item
	if item != null:
		_try_store_held(item)

func on_e_interact() -> void:
	if _storage_ui == null:
		push_warning("LightStorage: _storage_ui not injected")
		return
	_storage_ui.open(self)

func on_interact() -> void:   ## legacy shim, same as Shelving
	on_f_interact()

func get_e_prompt() -> String:
	return "[E] Open %s" % display_name.to_lower()

func get_f_prompt() -> String:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null or _interaction_system.held_item == null:
		return ""
	var item: RigidBody3D = _interaction_system.held_item
	if not item.is_in_group("inventory_item"):
		return ""
	if is_full():
		return "%s Full" % display_name   ## Aug 2026 — was "", matching Shelving.gd's existing "[F] Shelf full" pattern
	return "[F] Store item"

func get_prompt_world_pos() -> Vector3:
	return global_position + Vector3(0.0, prompt_height, 0.0)

func _resolve_interaction_system() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		_interaction_system = player.get_node_or_null("InteractionSystem")

# ─── Store ─────────────────────────────────────────────────────────────────
## F path — store the player's HELD item. Handles InteractionSystem release
## (sequence copied verbatim from Shelving._try_place_item(), lines ~334-351 —
## keep in lockstep with it).
func _try_store_held(item: RigidBody3D) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if not item.is_in_group("inventory_item"):
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Too big for the %s" % display_name.to_lower())
		return
	if is_full():
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("%s is full" % display_name)
		return

	## Release from InteractionSystem cleanly — mirrors Shelving exactly.
	_interaction_system._is_holding_e = false
	if item.has_signal("knocked_out") and \
			item.knocked_out.is_connected(_interaction_system._on_item_knocked_out):
		item.knocked_out.disconnect(_interaction_system._on_item_knocked_out)
	if _interaction_system._held_from_slot != -1 and \
			_interaction_system.inventory != null:
		_interaction_system.inventory.retrieve_item(_interaction_system._held_from_slot)
	_interaction_system.held_item       = null
	_interaction_system._held_from_slot = -1
	if "is_held"        in item: item.is_held        = false
	if "_hold_point"    in item: item._hold_point    = null
	if "from_inventory" in item: item.from_inventory = false

	_absorb_item(item)

## Shared absorption — used by the F path above. Stored items are invisible:
## frozen, collision-off, and excluded from every nearby-item scan via the
## ecosystem-wide "shelved" group. Writes into the first null slot so indices
## stay stable. NO metadata layer-saving — restoration always uses the
## codebase's canonical values (see take_for_carry / take_for_inventory).
func _absorb_item(item: RigidBody3D) -> void:
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask  = 0
	item.visible = false
	item.add_to_group("shelved")   ## reuse the ecosystem-wide "stored" exclusion group
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	add_child(item)
	item.position = Vector3.ZERO
	stored[_first_null_slot()] = item

## Reparent an item OUT of this furniture to the world root so it exists at a
## sane world transform once un-shelved (items here are hidden children of the
## furniture, which shelf items never are). Shared by take_for_carry /
## take_for_inventory / eject_all_items.
func _reparent_to_world(item: RigidBody3D) -> void:
	var world_root: Node3D = get_tree().get_first_node_in_group("world")
	if world_root == null:
		world_root = get_parent()
	if item.get_parent() != world_root:
		item.get_parent().remove_child(item)
		world_root.add_child(item)
	item.global_position = global_position + Vector3(0.0, 0.6, 0.0)

# ─── StorageUI contract (Aug 2026) ─────────────────────────────────────────
## Thin wrappers matching Shelving.gd's own StorageUI-contract methods —
## this is what lets the ONE shared StorageUI serve End Table / Dresser
## with zero new UI code. Stored items have no world presence, so the
## 3D viewport previews just show the item's mesh; "—" when empty.

func get_ui_config() -> Dictionary:
	return {
		"title": display_name.to_upper(),
		"slot_count": capacity,
		"grid_cols": grid_cols,
		"grid_rows": grid_rows,
		"display_order": [],                  ## identity — visual pos i = stored index i
		"row_labels": row_labels,
		"supports_stacking": false,
		"primary_button_icon": "↑",
		"primary_button_tooltip": "Carry",
		"primary_button_color": Color(0.20, 0.45, 0.30, 1.00),
		"primary_requires_empty_hands": true,
		"closes_on_action": true,
	}

func get_slot_display(slot_idx: int) -> Array:
	if slot_idx < 0 or slot_idx >= stored.size() or stored[slot_idx] == null:
		return [null, 0]
	return [stored[slot_idx], 1]

## Primary button — mirrors Shelving.retrieve_to_carry() (Shelving.gd:469-506)
## plus the two LightStorage-only deltas: reparent to world + visible restore.
func take_for_carry(slot_idx: int, isys: Node) -> bool:
	if slot_idx < 0 or slot_idx >= stored.size() or stored[slot_idx] == null:
		return false
	if isys.held_item != null:
		return false   ## Hands full — UI should have blocked this already
	var item: RigidBody3D = stored[slot_idx]
	stored[slot_idx] = null

	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")
	item.visible = true
	_reparent_to_world(item)
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
	return true

## Secondary "⊕" button — mirrors Shelving.retrieve_to_inventory()
## (Shelving.gd:510-532) plus the reparent + visible-restore deltas.
func take_for_inventory(slot_idx: int, inv: Node) -> bool:
	if slot_idx < 0 or slot_idx >= stored.size() or stored[slot_idx] == null:
		return false
	var item: RigidBody3D = stored[slot_idx]
	stored[slot_idx] = null

	if item.is_in_group("shelved"):
		item.remove_from_group("shelved")
	item.visible = true
	_reparent_to_world(item)
	item.freeze          = false
	item.collision_layer = 1
	item.collision_mask  = 1
	item.linear_velocity  = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	inv.add_item(item)
	return true

# ─── Eject on deconstruct / build-undo ─────────────────────────────────────
## REQUIRED for any container whose stored items are children of itself:
## BuildModeController deconstruct (~line 1805) and BuildUndoStack (line 59)
## duck-call eject_all_items() on removed objects — without it our stored
## items are silently freed along with the furniture node. Spread the ejected
## items so they don't interpenetrate.
func eject_all_items() -> void:
	for i: int in stored.size():
		var item: RigidBody3D = stored[i]
		if item == null:
			continue
		stored[i] = null
		if not is_instance_valid(item):
			continue
		if item.is_in_group("shelved"):
			item.remove_from_group("shelved")
		item.visible         = true
		item.freeze          = false
		item.collision_layer = 1
		item.collision_mask  = 1
		item.linear_velocity  = Vector3.ZERO
		item.angular_velocity = Vector3.ZERO
		var world_root: Node3D = get_tree().get_first_node_in_group("world")
		if world_root == null:
			world_root = get_parent()
		if item.get_parent() != world_root:
			item.get_parent().remove_child(item)
			world_root.add_child(item)
		item.global_position = global_position + Vector3(0.3 * (i + 1), 0.6, 0.15 * (i % 2))
