extends Node3D
class_name InteractionSystem
## InteractionSystem.gd
## Handles pickup, drop, world interaction, inventory storing, and slot scrolling.
## Scroll wheel cycles through inventory slots.
## Hold E stores held item. Scroll auto-stores/retrieves items.
##
## KEY DESIGN: inventory items stay in their slot even while held.
## activate_item()   → makes item visible/physics-on, keeps it in slot
## deactivate_item() → hides item back, keeps it in slot
## remove_item()     → only called on world-drop (clears slot)
## This means the HUD always shows all 4 slots correctly, and scrolling
## never reshuffles slot positions.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var hold_height: float       = 0.8
@export var store_hold_time: float   = 0.6   ## Seconds to hold E to store item

# ─── Node refs ────────────────────────────────────────────────────────────────
@onready var hold_point: Node3D      = $HoldPoint
@onready var detect_area: Area3D     = $DetectArea
@onready var player: CharacterBody3D = get_parent()

## Set by MainWorld after ready
var prompt: Node     = null
var inventory: Node  = null   ## InventoryManager reference

## Set by MainWorld — used to highlight the selected slot in the HUD
var inventory_hud: Node = null

## Set by MainWorld — when true, all interaction input is suppressed
var build_mode_active: bool = false

## Set by MainWorld — ShelfUI node ref; checked to suppress input while open
var shelf_ui: Node = null

# ─── State ────────────────────────────────────────────────────────────────────
var held_item: RigidBody3D = null
var _world_root: Node3D    = null

## If held_item came from inventory, track which slot so we can deactivate it
## when swapping away. -1 means the item was picked up fresh from the world.
var _held_from_slot: int = -1

## Hold-E store progress
var _store_hold_t: float  = 0.0
var _is_holding_e: bool   = false

## Tap-vs-hold disambiguation for E (use vs store).
## When E is pressed we don't know yet whether it's a tap or hold.
## We defer on_use() until E is released (or store threshold fires first).
var _use_pending: bool    = false

## Currently selected inventory slot (-1 = none)
var selected_slot: int = -1

func _ready() -> void:
	hold_point.position = Vector3(0.0, hold_height, -1.0)
	_world_root = get_tree().get_first_node_in_group("world")
	detect_area.body_entered.connect(_on_body_entered)
	detect_area.body_exited.connect(_on_body_exited)

## Tracked interactable bodies currently inside DetectArea.
## Maintained via body_entered / body_exited signals.
## This is the authoritative set — _update_prompt() only considers bodies in here.
var _tracked_bodies: Dictionary = {}   ## Node3D → true
## StaticBody3D nodes currently in prompt range — used to fire set_player_in_range()
## because Jolt Area3D body_entered/exited signals never fire for StaticBody3D.
var _static_in_range: Dictionary = {}  ## Node3D → true

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("interactable") or body.is_in_group("pickup"):
		_tracked_bodies[body] = true
	if body.is_in_group("interactable") and body.has_method("set_player_in_range"):
		body.set_player_in_range(true)

func _on_body_exited(body: Node3D) -> void:
	_tracked_bodies.erase(body)
	if body.is_in_group("interactable") and body.has_method("set_player_in_range"):
		body.set_player_in_range(false)

func _process(delta: float) -> void:
	if build_mode_active or _shelf_ui_open():
		if prompt != null:
			prompt.hide_prompt()
		return
	_tick_store_hold(delta)
	_tick_continuous_refuel(delta)
	_update_prompt()

## Continuously transfers fuel while the player holds E with a fuel can in hand.
## Fires every frame E is held; FuelCan.refuel_tick() handles the actual transfer.
func _tick_continuous_refuel(delta: float) -> void:
	if not _is_holding_e:
		return
	if held_item == null:
		return
	## Only act when the item supports continuous refuelling.
	if not held_item.has_method("refuel_tick"):
		return
	## Suppress the standard store-hold logic for this item — fuel cans cannot
	## be stored anyway (can_store() == false), but prevent _store_hold_t from
	## triggering the "Inventory full" message while refuelling.
	_store_hold_t = 0.0
	_use_pending  = false
	held_item.refuel_tick(delta)

## Returns true if the shelf UI overlay is open
func _shelf_ui_open() -> bool:
	return shelf_ui != null and shelf_ui.is_open

func _unhandled_input(event: InputEvent) -> void:
	if build_mode_active:
		return   ## BuildModeController owns all input while active
	if _shelf_ui_open():
		return   ## ShelfUI owns all input while open
	# ── Scroll wheel — cycle inventory slots ──
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_slot(-1)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_slot(1)
				get_viewport().set_input_as_handled()
				return

	# F — pickup / drop / shelf place
	if event.is_action_pressed("pickup"):
		## If shelf UI is open, F does nothing (UI owns interaction)
		if _shelf_ui_open():
			get_viewport().set_input_as_handled()
			return
		var shelf: Node3D = _nearest_shelf()
		if held_item != null:
			## Holding something — try placing on nearby shelf first, else drop
			if shelf != null and shelf.has_method("on_f_interact"):
				shelf.on_f_interact()
			else:
				_quick_drop()
		else:
			## Empty-handed — just try world pickup (shelf menu is E)
			_try_pickup()

	# E — use held item (tap) / store (hold) / shelf open / world interact
	if event.is_action_pressed("interact"):
		## Shelf nearby → E always opens shelf UI (overrides item use/store)
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_e_interact"):
			shelf.on_e_interact()
			get_viewport().set_input_as_handled()
			return
		if held_item != null:
			_use_pending  = true
			_is_holding_e = true
			_store_hold_t = 0.0
		elif held_item == null:
			_try_interact()

	if event.is_action_released("interact"):
		if _use_pending and held_item != null:
			if held_item.has_method("on_use"):
				held_item.on_use()
			elif held_item.has_method("on_interact"):
				held_item.on_interact()
		_use_pending  = false
		_is_holding_e = false
		_store_hold_t = 0.0

# ─── Scroll slot logic ────────────────────────────────────────────────────────
func _scroll_slot(direction: int) -> void:
	if inventory == null:
		return

	# Next slot index (wraps 0-3)
	var next_slot: int
	if selected_slot == -1:
		next_slot = 0 if direction > 0 else 3
	else:
		next_slot = (selected_slot + direction + inventory.SLOT_COUNT) % inventory.SLOT_COUNT

	# Deactivate current held item (put it back to hidden/frozen in its slot)
	# but ONLY if it came from inventory — world-pickups stay active until dropped
	if held_item != null and _held_from_slot != -1:
		_put_item_back_to_slot()

	# If a world-held item and we scroll, store it first to free a hand.
	# Non-storable items (crates, cases) always drop — never go into inventory.
	if held_item != null and _held_from_slot == -1:
		if _item_is_storable(held_item):
			# Try to store in the selected slot if empty, otherwise first free
			var store_to: int = selected_slot if (selected_slot != -1 and inventory.slots[selected_slot] == null) \
				else inventory.first_empty_slot()
			if store_to != -1:
				_store_item_to_slot(store_to)
			else:
				_quick_drop()
		else:
			_quick_drop()

	# Bring new slot's item to hand (if occupied)
	if inventory.slots[next_slot] != null:
		_bring_item_to_hand_from_slot(next_slot)

	selected_slot = next_slot
	_update_hud_selection()

## Deactivate held inventory item — it stays in slot but goes hidden/frozen.
func _put_item_back_to_slot() -> void:
	if held_item == null or inventory == null or _held_from_slot == -1:
		return

	_is_holding_e = false
	_store_hold_t = 0.0

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	# Reset held state on the item itself
	if "is_held" in held_item:
		held_item.is_held = false
	if "_hold_point" in held_item:
		held_item._hold_point = null
	held_item.gravity_scale = 1.0

	# Reset flag — item is no longer being held
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	inventory.deactivate_item(_held_from_slot)

	held_item = null
	_held_from_slot = -1

## Activate an inventory-slot item and bring it to the player's hand.
func _bring_item_to_hand_from_slot(slot: int) -> void:
	if inventory == null:
		return

	var item: RigidBody3D = inventory.activate_item(slot)
	if item == null:
		return

	item.global_position = hold_point.global_position

	held_item = item
	_held_from_slot = slot
	# Remove from tracked set — inventory items re-entering the DetectArea
	# after activation could otherwise show a ghost prompt in Case 2.
	_tracked_bodies.erase(held_item)

	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	# Mark as inventory-held so the item skips its knockout distance check
	if "from_inventory" in held_item:
		held_item.from_inventory = true
	held_item.pickup(hold_point)
	# Pass player reference so items that need facing direction (e.g. flashlight) can track it.
	if held_item.has_method("set_player"):
		held_item.set_player(player)

# ─── Store held item into inventory (explicit, e.g. hold-E or scroll-to-empty) ─
## Store a world-held item into a specific slot.
func _store_item_to_slot(slot: int) -> void:
	if held_item == null or inventory == null:
		return

	_is_holding_e = false
	_store_hold_t = 0.0

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	held_item.gravity_scale   = 1.0
	held_item.freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
	held_item.collision_layer = 1
	held_item.collision_mask  = 1
	held_item.linear_velocity = Vector3.ZERO

	inventory.add_item_to_slot(held_item, slot)
	held_item = null
	_held_from_slot = -1

## Store held item into inventory — first available slot (hold-E path).
func _store_item() -> void:
	if held_item == null or inventory == null:
		return

	_is_holding_e = false
	_store_hold_t = 0.0

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	held_item.gravity_scale   = 1.0
	held_item.freeze_mode     = RigidBody3D.FREEZE_MODE_STATIC
	held_item.collision_layer = 1
	held_item.collision_mask  = 1
	held_item.linear_velocity = Vector3.ZERO

	var stored_slot: int = inventory.add_item(held_item)
	held_item = null
	_held_from_slot = -1

	if stored_slot != -1:
		selected_slot = stored_slot
		_update_hud_selection()

func _update_hud_selection() -> void:
	if inventory_hud != null and inventory_hud.has_method("set_selected"):
		inventory_hud.set_selected(selected_slot)

# ─── Hold-E store tick ────────────────────────────────────────────────────────
func _tick_store_hold(delta: float) -> void:
	if not _is_holding_e or held_item == null:
		_is_holding_e = false
		_store_hold_t = 0.0
		return

	_store_hold_t += delta

	if _store_hold_t >= store_hold_time:
		# Hold threshold reached — cancel the pending tap-use
		_use_pending = false
		if _held_from_slot != -1:
			# Inventory item — put it back to its slot
			_put_item_back_to_slot()
		elif inventory != null and not inventory.is_full() and _item_is_storable(held_item):
			_store_item()
		else:
			_store_hold_t = store_hold_time

# ─── Prompt ───────────────────────────────────────────────────────────────────

## Maximum distance at which any prompt is shown (world units).
## Must match InteractPrompt.FADE_END so entries are culled exactly when alpha=0.
const MAX_PROMPT_DIST: float = 3.2

## Maximum number of interact prompts shown at once (empty-handed, Case 2 only).
## When more interactables are in range, only the N closest to the player show —
## keeps the screen from getting crowded/confusing with many overlapping prompts.
const MAX_VISIBLE_PROMPTS: int = 3



func _update_prompt() -> void:
	if prompt == null:
		return

	# ── Guard: held_item freed externally (build mode deconstruct, etc.) ─────
	if held_item != null and not is_instance_valid(held_item):
		held_item       = null
		_held_from_slot = -1

	# ═════════════════════════════════════════════════════════════════════════
	# CASE 1 — Player is holding an item
	# ═════════════════════════════════════════════════════════════════════════
	if held_item != null:
		var entries: Array            = []
		var item_lines: Array[String] = []

		# Use prompt (e.g. water bottle drink line)
		if held_item.has_method("get_use_prompt"):
			var up: String = held_item.get_use_prompt()
			if up != "": item_lines.append(up)

		# Interact prompt
		if held_item.has_method("get_interact_prompt"):
			var ip: String = held_item.get_interact_prompt()
			if ip != "": item_lines.append(ip)

		var has_action_lines:  bool = not item_lines.is_empty()
		var store_in_progress: bool = _is_holding_e and _store_hold_t > 0.05

		# Store / put-away hint — only add when it adds value
		if _item_is_storable(held_item) or _held_from_slot != -1:
			if store_in_progress:
				var pct: int = int((_store_hold_t / store_hold_time) * 100.0)
				if _held_from_slot != -1:
					item_lines.append("[E] Putting away... %d%%" % pct)
				elif inventory != null and inventory.is_full():
					item_lines.append("[Hold E] Inventory full")
				else:
					item_lines.append("[E] Storing... %d%%" % pct)
			elif has_action_lines:
				if _held_from_slot != -1:
					item_lines.append("[Hold E] Put away")
				elif inventory != null and inventory.is_full():
					item_lines.append("[Hold E] Inventory full")
				else:
					item_lines.append("[Hold E] Store")

		# Anchor prompt to hold_point position, not physics body center.
		var item_prompt_pos: Vector3 = hold_point.global_position \
				if hold_point != null else held_item.global_position

		if not item_lines.is_empty() and (has_action_lines or store_in_progress):
			entries.append({
				"text":      "\n".join(item_lines),
				"world_pos": item_prompt_pos,
				"dist":      0.0
			})

		# Shelf nearby — separate panel above the shelf
		var nearby_shelf: Node3D = _nearest_shelf()
		if nearby_shelf != null:
			var shelf_lines: Array[String] = []
			if nearby_shelf.has_method("get_f_prompt"):
				var fp: String = nearby_shelf.get_f_prompt()
				if fp != "": shelf_lines.append(fp)
			if nearby_shelf.has_method("get_e_prompt"):
				var ep: String = nearby_shelf.get_e_prompt()
				if ep != "": shelf_lines.append(ep)
			if not shelf_lines.is_empty():
				var shelf_pos: Vector3 = nearby_shelf.global_position + Vector3(0.0, 2.3, 0.0)
				if nearby_shelf.has_method("get_prompt_world_pos"):
					shelf_pos = nearby_shelf.get_prompt_world_pos()
				entries.append({ "text": "\n".join(shelf_lines), "world_pos": shelf_pos, "dist": 0.0 })

		if entries.is_empty():
			prompt.hide_prompt()
		else:
			prompt.set_prompts(entries)
		return

	# ═════════════════════════════════════════════════════════════════════════
	# CASE 2 — Empty-handed: show prompts for nearby interactables
	# ═════════════════════════════════════════════════════════════════════════

	# Purge stale / freed entries (Jolt may skip body_exited on layer change)
	var stale: Array = []
	for body in _tracked_bodies:
		if not is_instance_valid(body):
			stale.append(body)
	for body in stale:
		_tracked_bodies.erase(body)

	var candidates: Array = []
	for body in _tracked_bodies:
		if not is_instance_valid(body):
			continue
		# Shelved items — no prompt; access via shelf menu (E)
		if body.is_in_group("shelved"):
			continue
		if body is RigidBody3D and (body as RigidBody3D).freeze:
			continue
		# Currently held — Case 1 handles it
		if "is_held" in body and body.is_held:
			continue
		if not (body.is_in_group("interactable") or body.is_in_group("pickup")):
			continue
		var d: float = body.global_position.distance_to(player.global_position)
		if d > MAX_PROMPT_DIST:
			continue
		candidates.append({ "node": body, "dist": d })

	## Also include nearby StaticBody3D interactables — Jolt Area3D misses them.
	## (Same fix as _try_interact pass 2 — keeps prompts and interaction in sync.)
	##
	## IMPORTANT: We also call set_player_in_range() here because Jolt's Area3D
	## body_entered/body_exited signals never fire for StaticBody3D nodes.
	## Without this, generators (StaticBody3D + "interactable") never receive
	## set_player_in_range(true), so their _process polling and fuel banner
	## never activate.  We track which static nodes are currently in-range so
	## we can fire set_player_in_range(false) when they leave.
	var static_in_range_now: Dictionary = {}

	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		if not (node is StaticBody3D):
			continue
		if node.is_in_group("shelved") or node.is_in_group("shelving"):
			continue   ## Shelves handled separately above
		var sn3: Node3D = node as Node3D
		var sd: float = sn3.global_position.distance_to(player.global_position)

		if sd <= MAX_PROMPT_DIST:
			static_in_range_now[sn3] = true
			## Fire set_player_in_range(true) only on first entry, not every frame.
			if not _static_in_range.has(sn3):
				if sn3.has_method("set_player_in_range"):
					sn3.set_player_in_range(true)
			## Add to prompt candidates
			var already: bool = false
			for existing: Dictionary in candidates:
				if existing["node"] == sn3:
					already = true
					break
			if not already:
				candidates.append({ "node": sn3, "dist": sd })

	## Fire set_player_in_range(false) for any static nodes that left range.
	for gone_node in _static_in_range:
		if not static_in_range_now.has(gone_node) and is_instance_valid(gone_node):
			if gone_node.has_method("set_player_in_range"):
				gone_node.set_player_in_range(false)
	_static_in_range = static_in_range_now

	# Closest first so nearest panel renders on top
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["dist"] < b["dist"])

	# Cap to the N closest so the screen never gets crowded with prompts.
	if candidates.size() > MAX_VISIBLE_PROMPTS:
		candidates = candidates.slice(0, MAX_VISIBLE_PROMPTS)

	var entries: Array = []
	for cand: Dictionary in candidates:
		var body: Node3D = cand["node"] as Node3D
		var lines: Array[String] = []

		if body.is_in_group("pickup") and body.has_method("get_prompt_text"):
			var pt: String = body.get_prompt_text()
			if pt != "": lines.append(pt)
		elif body.is_in_group("pickup"):
			lines.append("[F] Pick up")

		if body.is_in_group("shelving"):
			if body.has_method("get_f_prompt"):
				var fp: String = body.get_f_prompt()
				if fp != "": lines.append(fp)
			if body.has_method("get_e_prompt"):
				var ep: String = body.get_e_prompt()
				if ep != "": lines.append(ep)
		elif body.is_in_group("interactable") and not body.is_in_group("pickup"):
			if body.has_method("get_interact_prompt"):
				var ip: String = body.get_interact_prompt()
				if ip != "": lines.append(ip)
			elif body.has_method("get_prompt_text"):
				var pt: String = body.get_prompt_text()
				if pt != "": lines.append(pt)
		elif body.is_in_group("interactable") and body.has_method("get_interact_prompt"):
			var ip: String = body.get_interact_prompt()
			if ip != "": lines.append(ip)

		if lines.is_empty():
			continue

		var prompt_pos: Vector3 = body.global_position
		if body.is_in_group("shelving") and body.has_method("get_prompt_world_pos"):
			prompt_pos = body.get_prompt_world_pos()

		entries.append({
			"text":      "\n".join(lines),
			"world_pos": prompt_pos,
			"dist":      cand["dist"]
		})

	if entries.is_empty():
		prompt.hide_prompt()
	else:
		prompt.set_prompts(entries)

# ─── Storable check ───────────────────────────────────────────────────────────
## An item is storable if it is in the inventory_item group AND its can_store()
## method returns true (or doesn't exist — assumed storable).
## Items like FuelCan override can_store() → false to block inventory storage.
func _item_is_storable(item: RigidBody3D) -> bool:
	if not item.is_in_group("inventory_item"):
		return false
	if item.has_method("can_store"):
		return item.can_store()
	return true

# ─── Nearest shelf via group scan (Area3D misses StaticBody3D reliably) ───────
func _nearest_shelf() -> Node3D:
	var shelves: Array      = get_tree().get_nodes_in_group("shelving")
	var closest: Node3D     = null
	var closest_dist: float = 2.5   ## Max reach (flat XZ distance, metres)
	var player_xz: Vector2  = Vector2(player.global_position.x, player.global_position.z)
	for shelf: Node in shelves:
		if not is_instance_valid(shelf):
			continue
		if shelf is Node3D:
			var s3: Node3D    = shelf as Node3D
			var shelf_xz: Vector2 = Vector2(s3.global_position.x, s3.global_position.z)
			var d: float = shelf_xz.distance_to(player_xz)
			if d < closest_dist:
				closest_dist = d
				closest = s3
	return closest

# ─── World Interaction ────────────────────────────────────────────────────────
func _try_interact() -> void:
	var bodies: Array       = detect_area.get_overlapping_bodies()
	var closest: Node3D     = null
	var closest_dist: float = INF

	## Pass 1 - RigidBody3D interactables tracked via Area3D overlap.
	## NOTE: only bodies that actually implement on_interact() are considered.
	## Some items (e.g. FuelCan) sit in the "interactable" group purely so their
	## get_prompt_text()/get_use_prompt() lines show up while HELD - they have no
	## on_interact() of their own. If those were allowed to win the closest-node
	## comparison, pressing E while merely standing near one would silently no-op
	## instead of falling through to the next-closest thing that can actually
	## respond (e.g. a WaterHookup a bit further away). Filtering here keeps E
	## always resolving to the closest thing that will actually do something.
	for body in bodies:
		if body.is_in_group("interactable") and body.has_method("on_interact"):
			## Shelved items — block direct interaction; use shelf menu (E) to retrieve
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	## Pass 2 — StaticBody3D interactables (e.g. PowerTerminal, BreakerBox).
	## Jolt's Area3D.get_overlapping_bodies() is unreliable for StaticBody3D nodes,
	## so we do a proximity group scan — same pattern as _nearest_shelf().
	var static_reach: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(node):
			continue
		if not (node is StaticBody3D):
			continue
		if not node.has_method("on_interact"):
			continue
		if node.is_in_group("shelved"):
			continue
		var n3: Node3D = node as Node3D
		var d: float = n3.global_position.distance_to(player_pos)
		if d < static_reach and d < closest_dist:
			closest_dist = d
			closest = n3

	if closest != null:
		closest.on_interact()

# ─── Pickup from world ────────────────────────────────────────────────────────
func _try_pickup() -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body.is_in_group("pickup"):
			## Shelved items — block direct pickup via F; use shelf menu (E) to retrieve
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	if closest == null:
		return

	held_item = closest
	_held_from_slot = -1   ## Fresh from world — not in any inventory slot yet
	# Remove from tracked set immediately — Jolt may not fire body_exited when
	# collision_layer changes at pickup, leaving a ghost entry that shows prompts.
	_tracked_bodies.erase(held_item)
	# Mark as world-held so knockout distance check is active
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	# Pass player reference so items that need facing direction (e.g. flashlight) can track it.
	if held_item.has_method("set_player"):
		held_item.set_player(player)

# ─── Knocked out ──────────────────────────────────────────────────────────────
func _on_item_knocked_out() -> void:
	# If it was an inventory item, deactivate it in-slot (don't clear the slot)
	if _held_from_slot != -1 and inventory != null:
		inventory.deactivate_item(_held_from_slot)

	held_item = null
	_held_from_slot = -1
	_is_holding_e = false
	_store_hold_t = 0.0
	_use_pending  = false
	# Don't clear selected_slot — the slot still has the item, just knocked out
	_update_hud_selection()

# ─── Quick Drop ───────────────────────────────────────────────────────────────
func _quick_drop() -> void:
	if held_item == null:
		return

	_is_holding_e = false
	_store_hold_t = 0.0

	if held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.disconnect(_on_item_knocked_out)

	var drop_pos: Vector3 = player.global_position + \
		player.global_transform.basis.z * -1.5 + Vector3(0.0, 0.2, 0.0)

	if _held_from_slot != -1 and inventory != null:
		# Item was from inventory — remove it from the slot before dropping
		inventory.remove_item(_held_from_slot, drop_pos)
		# remove_item calls item.drop() internally, so we're done
	else:
		# World item — just drop it
		held_item.drop(_world_root, drop_pos)

	held_item = null
	_held_from_slot = -1
