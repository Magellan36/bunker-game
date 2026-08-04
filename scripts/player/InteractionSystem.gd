extends Node3D
class_name InteractionSystem
## InteractionSystem.gd
## Handles pickup, drop, world interaction, inventory storing, and slot scrolling.
## Scroll wheel cycles through inventory slots.
## E is a pure instant tap-to-use/interact key. G is the instant store/put-away key.
## Scroll auto-stores/retrieves items.
##
## KEY DESIGN: inventory items stay in their slot even while held.
## activate_item()   → makes item visible/physics-on, keeps it in slot
## deactivate_item() → hides item back, keeps it in slot
## remove_item()     → only called on world-drop (clears slot)
## This means the HUD always shows all 4 slots correctly, and scrolling
## never reshuffles slot positions.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var hold_height: float       = 0.8

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

## Set by MainWorld — BasketUI node ref; checked to suppress input while open
var basket_ui: Node = null

# ─── State ────────────────────────────────────────────────────────────────────
var held_item: RigidBody3D = null
var _world_root: Node3D    = null

## If held_item came from inventory, track which slot so we can deactivate it
## when swapping away. -1 means the item was picked up fresh from the world.
var _held_from_slot: int = -1

## True while the player is holding E down. E itself is a pure instant tap
## (on_use/on_interact fires on press, not on release) — this flag only
## drives per-frame continuous-hold actions on the held item, e.g.
## FuelCan.refuel_tick(). It no longer gates any store behavior (see G).
var _is_holding_e: bool = false

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
	if build_mode_active or _shelf_ui_open() or _basket_ui_open():
		if prompt != null:
			prompt.hide_prompt()
		return
	_tick_continuous_refuel(delta)
	_tick_continuous_bottle_refill(delta)
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
	held_item.refuel_tick(delta)

## Continuously refills a water bottle while the player holds E with it near a
## WaterDispenser. Mirrors _tick_continuous_refuel() exactly — fires every
## frame E is held; WaterBottle.bottle_refill_tick() handles the actual
## transfer + nearest-dispenser lookup (Jul 2026 bottle rework).
func _tick_continuous_bottle_refill(delta: float) -> void:
	if not _is_holding_e:
		return
	if held_item == null:
		return
	if not held_item.has_method("bottle_refill_tick"):
		return
	held_item.bottle_refill_tick(delta)

## Returns true if the shelf UI overlay is open
func _shelf_ui_open() -> bool:
	return shelf_ui != null and shelf_ui.is_open

## Returns true if the basket UI overlay is open
func _basket_ui_open() -> bool:
	return basket_ui != null and basket_ui.is_open

func _unhandled_input(event: InputEvent) -> void:
	if build_mode_active:
		return   ## BuildModeController owns all input while active
	if _shelf_ui_open() or _basket_ui_open():
		return   ## ShelfUI/BasketUI owns all input while open
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
			## Empty-handed — compare the closest stove-with-pot (if any)
			## against the closest normal pickup candidate and grab whichever
			## is TRULY closer. Confirmed Aug 2026 fix: previously the
			## stove-pot case always won regardless of distance, so a pot
			## across the room could beat a vegetable at the player's feet.
			var host_stove: Node = _find_nearest_stove_with_pot()
			if host_stove != null:
				var stove_dist: float = (host_stove as Node3D).global_position.distance_to(player.global_position)
				if stove_dist <= _nearest_pickup_distance():
					_try_pickup_pot_from_stove(host_stove)
					return
			_try_pickup()

	# E — use held item (instant tap) / shelf open / world interact.
	# Pure tap: fires immediately on press, no hold-to-store behavior.
	if event.is_action_pressed("interact"):
		## Shelf nearby → E always opens shelf UI (overrides item use)
		var shelf: Node3D = _nearest_shelf()
		if shelf != null and shelf.has_method("on_e_interact"):
			shelf.on_e_interact()
			get_viewport().set_input_as_handled()
			return
		## Basket held → E stashes nearest "basket_storable" item instead of item use
		if held_item != null and ("is_basket_container" in held_item):
			_try_add_nearest_to_basket(held_item)
			get_viewport().set_input_as_handled()
			return
		## Cooking Pot held → E either places it on a nearby open Stove, or
		## (if no open stove in range) stashes the nearest "cookpot_storable"
		## item into it. Mirrors the basket branch immediately above exactly.
		if held_item != null and ("is_cookpot_container" in held_item):
			_try_use_held_cookpot(held_item)
			get_viewport().set_input_as_handled()
			return
		## Giveable item held + an NPC in range → E gives it instead of
		## normal item use.
		if held_item != null and NPCItemUser.is_giveable(held_item) and _find_nearest_npc() != null:
			_try_give_to_nearest_npc(held_item)
			get_viewport().set_input_as_handled()
			return
		if held_item != null:
			# _is_holding_e stays true only to drive per-frame continuous
			# actions (e.g. FuelCan.refuel_tick / bottle refill) — it no
			# longer gates a store action.
			_is_holding_e = true
			if held_item.has_method("on_use"):
				held_item.on_use()
			elif held_item.has_method("on_interact"):
				held_item.on_interact()
		else:
			## A ready dish takes priority over other interactables ONLY if
			## it's truly the closest one — same distance-fairness fix
			## already applied to the [F] stove-pot pickup case.
			var ready_pot: Node = _find_nearest_ready_pot()
			if ready_pot != null:
				var pot_dist: float = (ready_pot as Node3D).global_position.distance_to(player.global_position)
				if pot_dist <= _nearest_interact_distance():
					_try_take_dish(ready_pot)
					return
			_try_interact()

	if event.is_action_released("interact"):
		_is_holding_e = false

	# G — store / put away held item (instant, no progress bar)
	if event.is_action_pressed("store_item"):
		if held_item != null and ("is_basket_container" in held_item):
			if basket_ui != null and basket_ui.has_method("open"):
				basket_ui.open(held_item)
			get_viewport().set_input_as_handled()
			return
		if held_item != null:
			_is_holding_e = false
			if _held_from_slot != -1:
				_put_item_back_to_slot()
			elif inventory != null and not inventory.is_full() and _item_is_storable(held_item):
				_store_item()
			get_viewport().set_input_as_handled()

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

# ─── Store held item into inventory (explicit, e.g. G-tap or scroll-to-empty) ─
## Store a world-held item into a specific slot.
func _store_item_to_slot(slot: int) -> void:
	if held_item == null or inventory == null:
		return

	_is_holding_e = false

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

## Store held item into inventory — first available slot (G-tap path).
func _store_item() -> void:
	if held_item == null or inventory == null:
		return

	_is_holding_e = false

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

	## Seated players always see [E] Stand, overriding every other prompt.
	if player.seated_chair != null and is_instance_valid(player.seated_chair):
		prompt.set_prompts([{
			"text":      "[E] Stand",
			"world_pos": player.seated_chair.global_position,
			"dist":      0.0,
			"icons":     [],
		}])
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

		# Store / put-away hint — only add when it adds value
		if _item_is_storable(held_item) or _held_from_slot != -1:
			if _held_from_slot != -1:
				item_lines.append("[G] Put away")
			elif inventory != null and inventory.is_full():
				item_lines.append("[G] Inventory full")
			else:
				item_lines.append("[G] Store")

		# Anchor prompt to hold_point position, not physics body center.
		var item_prompt_pos: Vector3 = hold_point.global_position \
				if hold_point != null else held_item.global_position

		if not item_lines.is_empty():
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

		# Basket held → "[E] Add to Basket" over each nearby storable item.
		# CASE 2 further down never runs while something is held (this whole
		# block returns before reaching it), so this can only live here.
		# Reuses _tracked_bodies — the same Area3D-maintained set CASE 2 uses —
		# rather than polling detect_area every frame.
		if "is_basket_container" in held_item:
			for body in _tracked_bodies:
				if not is_instance_valid(body):
					continue
				if not body.is_in_group("basket_storable"):
					continue
				if body.is_in_group("shelved"):
					continue
				if body is RigidBody3D and (body as RigidBody3D).freeze:
					continue
				var bd: float = body.global_position.distance_to(player.global_position)
				if bd > MAX_PROMPT_DIST:
					continue
				entries.append({
					"text":      "[E] Add to Basket",
					"world_pos": body.global_position,
					"dist":      bd
				})

		# Cooking Pot held → "[E] Add to Pot" over each nearby storable food
		# item, PLUS "[E] Place Cooking Pot" over the nearest open Stove.
		# Confirmed Aug 2026: these two target types are the ONLY prompts
		# that should show while holding the pot — nothing above the held
		# pot itself. Mirrors the basket block above exactly, plus the
		# stove target (baskets have no equivalent "place" target).
		if "is_cookpot_container" in held_item:
			for body in _tracked_bodies:
				if not is_instance_valid(body):
					continue
				if not body.is_in_group("cookpot_storable"):
					continue
				if body.is_in_group("shelved"):
					continue
				if body is RigidBody3D and (body as RigidBody3D).freeze:
					continue
				var bd: float = body.global_position.distance_to(player.global_position)
				if bd > MAX_PROMPT_DIST:
					continue
				entries.append({
					"text":      "[E] Add to Pot",
					"world_pos": body.global_position,
					"dist":      bd
				})
			var nearby_stove: Node = _find_nearest_open_stove()
			if nearby_stove != null:
				entries.append({
					"text":      "[E] Place Cooking Pot",
					"world_pos": (nearby_stove as Node3D).global_position + Vector3(0.0, 0.9, 0.0),
					"dist":      0.0
				})

		# Give to NPC — holding a giveable item (dish, produce, can, or
		# bottle) → "[E] Give <item> to <name>" over each nearby NPC.
		# Mirrors the basket/cookpot blocks above exactly.
		if NPCItemUser.is_giveable(held_item):
			for npc: Node in get_tree().get_nodes_in_group("npc"):
				if not is_instance_valid(npc):
					continue
				var nd: float = (npc as Node3D).global_position.distance_to(player.global_position)
				if nd > MAX_PROMPT_DIST:
					continue
				entries.append({
					"text":      "[E] Give %s to %s" % [held_item.get_display_name(), String(npc.npc_name)],
					"world_pos": (npc as Node3D).global_position + Vector3(0.0, 1.8, 0.0),
					"dist":      nd
				})

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
		## StaticBody3D (generators, stoves, etc.) OR a frozen RigidBody3D
		## (e.g. a CookingPot resting on a Stove — the detect_area-based scan
		## above explicitly skips frozen bodies, so without this a frozen pot
		## would never get a prompt at all). The two passes never overlap:
		## the first pass already excludes frozen bodies, so nothing here
		## can be double-added.
		var is_frozen_rigid: bool = node is RigidBody3D and (node as RigidBody3D).freeze
		if not (node is StaticBody3D or is_frozen_rigid):
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
		if body.has_method("get_prompt_world_pos"):
			prompt_pos = body.get_prompt_world_pos()

		var icons: Array = []
		if body.has_method("get_slot_icon_descriptors"):
			icons = body.get_slot_icon_descriptors()

		entries.append({
			"text":      "\n".join(lines),
			"world_pos": prompt_pos,
			"dist":      cand["dist"],
			"icons":     icons,
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

## E while holding a Basket — finds the nearest "basket_storable" world item
## in reach and stashes it, instead of calling the basket's own on_use().
func _try_add_nearest_to_basket(basket: Node) -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body == held_item:   ## DetectArea now also sees the player's
			continue              ## own held item (layer 2, Aug 2026 mask
			                       ## widen) — never treat it as a candidate.
		if body.is_in_group("basket_storable"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	var hud: Node = get_tree().get_first_node_in_group("hud")

	if closest == null:
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Nothing nearby to store")
		return

	if not basket.try_add_item(closest):
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Basket full")

## Cooking Pot equivalent of _try_add_nearest_to_basket(), with an added
## stove-placement priority check first. Called when the player presses E
## while holding a Cooking Pot (is_cookpot_container duck type).
func _try_use_held_cookpot(pot: Node) -> void:
	var stove: Node = _find_nearest_open_stove()
	if stove != null:
		if held_item.knocked_out.is_connected(_on_item_knocked_out):
			held_item.knocked_out.disconnect(_on_item_knocked_out)
		stove.try_place_pot(pot)
		held_item        = null
		_held_from_slot  = -1
		_is_holding_e    = false
		return
	_try_add_nearest_to_cookpot(pot)

## Identical mechanism to _try_add_nearest_to_basket() — "cookpot_storable"
## group instead of "basket_storable", pot.try_add_item() instead of
## basket.try_add_item().
func _try_add_nearest_to_cookpot(pot: Node) -> void:
	var bodies: Array        = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body == held_item:   ## DetectArea now also sees the player's
			continue              ## own held item (layer 2, Aug 2026 mask
			                       ## widen) — never treat it as a candidate.
		if body.is_in_group("cookpot_storable"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	var hud: Node = get_tree().get_first_node_in_group("hud")

	if closest == null:
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Nothing nearby to store")
		return

	if not pot.try_add_item(closest):
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Pot full")

## Stove is a StaticBody3D — Jolt's Area3D.get_overlapping_bodies() is
## unreliable for those (same caveat _try_interact()'s Pass 2 already
## documents), so this uses a group scan, not detect_area.
func _find_nearest_open_stove() -> Node:
	var closest: Node        = null
	var closest_dist: float  = MAX_PROMPT_DIST
	var player_pos: Vector3  = player.global_position
	for node: Node in get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(node):
			continue
		if not node.has_method("has_open_slot") or not node.has_open_slot():
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Same group-scan reasoning as _find_nearest_open_stove().
func _find_nearest_stove_with_pot() -> Node:
	var closest: Node        = null
	var closest_dist: float  = MAX_PROMPT_DIST
	var player_pos: Vector3  = player.global_position
	for node: Node in get_tree().get_nodes_in_group("stove"):
		if not is_instance_valid(node):
			continue
		if not ("pot_ref" in node) or node.pot_ref == null:
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Same group-scan/range reasoning as _find_nearest_open_stove(), reused
## by both the Give prompt (Change 1) and its dispatch (Change 2).
func _find_nearest_npc() -> Node:
	var closest: Node       = null
	var closest_dist: float = MAX_PROMPT_DIST
	var player_pos: Vector3 = player.global_position
	for node: Node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Give dispatch. NPC.receive_item_from_player() may free `item`
## internally (single-serving items are consumed and destroyed on the
## spot) — do not touch `item` after a true return, same caution this
## file already applies around consume_as_food()-adjacent calls elsewhere.
func _try_give_to_nearest_npc(item: RigidBody3D) -> void:
	var target: Node = _find_nearest_npc()
	if target == null or not target.has_method("receive_item_from_player"):
		return
	if not target.receive_item_from_player(item):
		return
	## Single-serving items (Dish/Produce) are destroyed inside
	## receive_item_from_player() — consume_as_food() frees the node, so
	## is_instance_valid(item) is false here and there is nothing left to
	## clean up on the item itself. Multi-charge items (can/bottle)
	## persist and are STILL correctly held by the player (is_held/
	## hold_point tracking untouched by that call) — only clear our own
	## bookkeeping in the destroyed case. Clearing it unconditionally was
	## the bug: it desynced held_item (null) from a surviving item's own
	## is_held (still true), leaving a can/bottle visually stuck in the
	## player's hand but undroppable/unstorable/unusable since every
	## other action checks held_item, which had already gone null.
	if is_instance_valid(item):
		return
	held_item       = null
	_held_from_slot = -1
	_is_holding_e   = false

## Mirrors _try_pickup()'s tail exactly (signal connect, held_item/_held_from_slot
## bookkeeping, set_player call) — the only difference is the item comes from
## Stove.try_remove_pot() instead of a detect_area scan.
func _try_pickup_pot_from_stove(stove: Node) -> void:
	var pot: Node = stove.try_remove_pot()
	if pot == null:
		return
	held_item       = pot
	_held_from_slot = -1
	_tracked_bodies.erase(held_item)
	if "from_inventory" in held_item:
		held_item.from_inventory = false
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	if held_item.has_method("set_player"):
		held_item.set_player(player)

## Scans "cooking_pot" — covers a pot on a stove AND a standalone pot sitting
## on the ground with a ready dish still in it.
func _find_nearest_ready_pot() -> Node:
	var closest: Node        = null
	var closest_dist: float  = MAX_PROMPT_DIST
	var player_pos: Vector3  = player.global_position
	for node: Node in get_tree().get_nodes_in_group("cooking_pot"):
		if not is_instance_valid(node):
			continue
		if not node.has_method("is_dish_ready") or not node.is_dish_ready():
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest

## Read-only peek at the distance to whatever _try_interact() would
## actually interact with, without triggering it — mirrors both of
## _try_interact()'s passes exactly. Used purely to fairly compare against
## the ready-dish special case above. Returns INF if nothing is eligible.
func _nearest_interact_distance() -> float:
	var bodies: Array       = detect_area.get_overlapping_bodies()
	var closest_dist: float = INF

	for body in bodies:
		if body.is_in_group("interactable") and body.has_method("on_interact"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d

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

	return closest_dist


## Spawns a DishItem from the pot's serve_dish() result and puts it directly
## in the player's hand — mirrors _try_pickup_pot_from_stove()'s tail.
func _try_take_dish(pot: Node) -> void:
	var result: Dictionary = pot.serve_dish()
	if result.is_empty():
		return

	var dish_script: GDScript = load("res://scripts/world/items/DishItem.gd")
	var dish: RigidBody3D = RigidBody3D.new()
	dish.set_script(dish_script)
	dish.collision_layer = 1
	dish.collision_mask  = 1
	dish.continuous_cd   = true

	var world_root: Node = get_tree().get_root()
	world_root.add_child(dish)
	dish.global_position = (pot as Node3D).global_position
	dish.fill_value = result["value"]
	dish.bonus_pct  = result["bonus_pct"]

	held_item       = dish
	_held_from_slot = -1
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)
	if held_item.has_method("set_player"):
		held_item.set_player(player)

# ─── World Interaction ────────────────────────────────────────────────────────
func _try_interact() -> void:
	## Seated players always stand, regardless of what else is nearby —
	## checked first, before any proximity scan, so a chair can never lose
	## a closest-distance comparison to some other interactable.
	if player.seated_chair != null and is_instance_valid(player.seated_chair):
		player.seated_chair.on_interact()
		return

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

## Read-only peek at the distance to whatever _try_pickup() would grab,
## without actually grabbing it — used purely to fairly compare against the
## stove-with-pot special case above. Returns INF if nothing is eligible.
func _nearest_pickup_distance() -> float:
	var bodies: Array = detect_area.get_overlapping_bodies()
	var closest_dist: float = INF
	for body in bodies:
		if body.is_in_group("pickup"):
			if body.is_in_group("shelved"):
				continue
			if body is RigidBody3D and (body as RigidBody3D).freeze:
				continue
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
	return closest_dist

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

	## NPC takeaway notification — look this up BEFORE reassigning
	## held_item below, since find_holder() checks each live NPC's own
	## held_item field for a match.
	var taken_from: Node = NPCItemUser.find_holder(closest, get_tree())

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

	if taken_from != null and taken_from.has_method("on_item_taken_by_player"):
		taken_from.on_item_taken_by_player()

# ─── Knocked out ──────────────────────────────────────────────────────────────
func _on_item_knocked_out() -> void:
	# If it was an inventory item, deactivate it in-slot (don't clear the slot)
	if _held_from_slot != -1 and inventory != null:
		inventory.deactivate_item(_held_from_slot)

	held_item = null
	_held_from_slot = -1
	_is_holding_e = false
	# Don't clear selected_slot — the slot still has the item, just knocked out
	_update_hud_selection()

# ─── Quick Drop ───────────────────────────────────────────────────────────────
func _quick_drop() -> void:
	if held_item == null:
		return

	_is_holding_e = false

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
