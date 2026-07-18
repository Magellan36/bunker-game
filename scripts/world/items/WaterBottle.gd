extends RigidBody3D
## WaterBottle.gd
## Pickupable consumable. Continuous mL-based fill + blended water quality
## (Jul 2026 rework — replaces the old fixed 2-sip model).
## Drinking (tap E) removes up to STANDARD_DRINK_ML at once, restoring
## hydration proportional to however much water was actually available.
## Refilling (hold E near a WaterDispenser) continuously transfers water
## from the dispenser's tank, blending quality volume-weighted exactly like
## WaterDispenser.gd blends from a hookup.

# ─── Signals ─────────────────────────────────────────────────────────────────
signal picked_up()
signal dropped()
signal knocked_out()
signal charge_changed()   ## Emitted whenever current_fill_mL changes — lets HUD update badge live

# ─── Config ───────────────────────────────────────────────────────────────────
const MAX_FILL_ML:        float = 750.0   ## Full bottle capacity
const STANDARD_DRINK_ML:  float = 375.0   ## One "drink" — half the bottle at full
const STANDARD_HYDRATION: float = 21.5    ## Hydration restored by one FULL standard drink

## Continuous refill rate — mirrors FuelCan.FUEL_RATE's derivation exactly:
## FuelCan refuels 100 units in 12.5s (FUEL_RATE=8.0/s). Same 12.5s-to-full
## target applied to this bottle's 750mL capacity: 750 / 12.5 = 60.0 mL/s.
const REFILL_RATE_ML_PER_SEC: float = 60.0
const REFILL_RANGE:           float = 2.5   ## Max distance to a WaterDispenser to refill

const KNOCK_DISTANCE: float    = 2.2    ## Max distance before knockout check begins (world-held only)
const KNOCK_LINGER_TIME: float = 0.35   ## Must stay out-of-range this long to actually drop

@export var follow_speed: float       = 18.0   ## World-held follow speed
@export var inv_follow_speed: float   = 40.0   ## Inventory-held: snaps instantly through turns
@export var pickup_grace: float       = 0.6

## Shelf stacking — 6 bottles per slot, stand upright in two rows of 3
var shelf_stack_limit: int   = 6
var shelf_item_type: String  = "water_bottle"

# ─── State ───────────────────────────────────────────────────────────────────
var is_held: bool           = false
var from_inventory: bool    = false   ## Set by InteractionSystem — disables knockout when true
var _hold_point: Node3D     = null
var _player_stats: Node     = null
var _grace_timer: float        = 0.0
var _out_of_range_time: float  = 0.0

## Spawns full. current_fill_mL is the single source of truth for "empty" —
## _is_empty() is a computed check (current_fill_mL <= 0.0), not a one-way
## latch, so refilling a drained bottle correctly un-empties it.
var current_fill_mL: float     = MAX_FILL_ML
var stored_water_quality: float = 100.0

# ─── Node refs (set in _ready) ────────────────────────────────────────────────
var _mesh: MeshInstance3D = null ## For tinting when empty

func _ready() -> void:
	add_to_group("pickup")
	add_to_group("inventory_item")
	contact_monitor = true
	max_contacts_reported = 4
	_mesh = get_node_or_null("MeshInstance3D")

# ─── Physics ──────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_held or _hold_point == null:
		return

	if _grace_timer > 0.0:
		_grace_timer -= delta

	var target: Vector3 = _hold_point.global_position
	var dist: float = global_position.distance_to(target)

	# Inventory items never knock out — they always snap to the hold point.
	# Knockout only applies to world-held items (picked up fresh, not from a slot).
	if not from_inventory:
		if _grace_timer <= 0.0 and dist > KNOCK_DISTANCE:
			_out_of_range_time += delta
			if _out_of_range_time >= KNOCK_LINGER_TIME:
				_do_knocked_out()
				return
		else:
			_out_of_range_time = 0.0

	var speed: float = inv_follow_speed if from_inventory else follow_speed
	linear_velocity  = (target - global_position) * speed
	angular_velocity = Vector3.ZERO

# ─── Empty check (computed, not a latch) ──────────────────────────────────────
func _is_empty() -> bool:
	return current_fill_mL <= 0.0

# ─── Prompt interface ─────────────────────────────────────────────────────────
## While empty, the bottle presents itself as a distinct "Empty Water Bottle"
## everywhere (name, ground prompt, inventory badge) instead of showing a
## meaningless "0ml/750ml" readout. This is purely a display-state derived
## from _is_empty() — no separate scene/class — so refilling from a dispenser
## (current_fill_mL rising above 0) flips it straight back to a normal bottle
## with normal readouts, same object the whole time.
func get_display_name() -> String:
	if _is_empty():
		return "Empty Water Bottle"
	return "Water Bottle"

## Water-quality colour convention — mirrored from WaterDispenserUI._quality_color()
## / InventoryHUD._bottle_quality_color() (0-50 red / 50.01-75 yellow / 75.01-100
## green, inclusive lower boundary each tier). Hex values match those consts'
## Color(...) values exactly (CRIT=1.00,0.35,0.30 / WARN=1.00,0.72,0.10 /
## GOOD=0.30,0.85,0.35), duplicated here per this project's per-file-helper
## convention for water UI colour code.
const CRIT_COLOR_HEX: String = "ff594d"
const WARN_COLOR_HEX: String = "ffb81a"
const GOOD_COLOR_HEX: String = "4dd959"

func _quality_hex(quality: float) -> String:
	if quality <= 50.0:
		return CRIT_COLOR_HEX
	elif quality <= 75.0:
		return WARN_COLOR_HEX
	return GOOD_COLOR_HEX

## BBCode "Xml/750ml (Q%)" fragment, coloured by current water quality.
## Used by every prompt line (ground pickup / drink / refill) so the display
## is identical everywhere. Requires the prompt Label to be a BBCode-enabled
## RichTextLabel (see InteractPrompt.tscn / InteractPrompt.gd).
func _fill_quality_bbcode() -> String:
	var ml: int     = int(round(current_fill_mL))
	var max_ml: int = int(MAX_FILL_ML)
	var q: int      = int(round(stored_water_quality))
	var hex: String = _quality_hex(stored_water_quality)
	return "[color=#%s]%dml/%dml (%d%%)[/color]" % [hex, ml, max_ml, q]

func get_prompt_text() -> String:
	if _is_empty():
		return "[F] Pick up  Empty Water Bottle"
	return "[F] Pick up  Water Bottle  —  " + _fill_quality_bbcode()

func get_use_prompt() -> String:
	var dispenser: WaterDispenser = _find_nearest_dispenser()
	if dispenser != null:
		if current_fill_mL >= MAX_FILL_ML:
			return ""   ## Already full — nothing to do at the dispenser
		if _is_empty():
			return "[Hold E] Refill Empty Water Bottle"
		return "[Hold E] Refill Bottle  —  " + _fill_quality_bbcode()

	if _is_empty():
		return ""   ## No use prompt when empty and not at a dispenser — can't drink it
	return "[E] Drink  —  " + _fill_quality_bbcode()

# ─── Pickup ───────────────────────────────────────────────────────────────────
func pickup(hold_point: Node3D) -> void:
	is_held       = true
	_hold_point   = hold_point
	_grace_timer       = pickup_grace
	_out_of_range_time = 0.0
	freeze        = false
	freeze_mode   = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	collision_layer = 2
	collision_mask  = 1
	_set_held_culling(true)
	picked_up.emit()

# ─── Use / Drink ──────────────────────────────────────────────────────────────
## Tapping E near a WaterDispenser does nothing here — that proximity is
## reserved for the continuous hold-E refill tick (see bottle_refill_tick()),
## mirroring FuelCan's on_use() being a no-op near a generator.
func on_use() -> void:
	if _find_nearest_dispenser() != null:
		return

	if _is_empty():
		return

	if _player_stats == null:
		_player_stats = get_tree().get_first_node_in_group("player_stats")
	if _player_stats == null:
		push_warning("WaterBottle: _player_stats not found.")
		return

	var amount_removed: float = minf(STANDARD_DRINK_ML, current_fill_mL)
	var hydration: float      = STANDARD_HYDRATION * (amount_removed / STANDARD_DRINK_ML)

	_player_stats.replenish_water(hydration)
	current_fill_mL -= amount_removed
	current_fill_mL  = maxf(0.0, current_fill_mL)

	_update_empty_tint()
	charge_changed.emit()   ## Tell InventoryHUD to redraw the badge immediately

# ─── Continuous refill tick (called by InteractionSystem._process each frame) ─
## Transfers REFILL_RATE_ML_PER_SEC * delta mL from the nearest in-range
## WaterDispenser into this bottle, blending quality volume-weighted exactly
## like WaterDispenser.gd blends from a hookup. Mirrors FuelCan.refuel_tick()'s
## shape precisely (nearest-node lookup, clamp-to-headroom, clamp-to-source).
func bottle_refill_tick(delta: float) -> void:
	if current_fill_mL >= MAX_FILL_ML:
		return

	var dispenser: WaterDispenser = _find_nearest_dispenser()
	if dispenser == null:
		return

	if dispenser.current_fill_mL <= 0.0:
		return

	var transfer: float = minf(REFILL_RATE_ML_PER_SEC * delta, MAX_FILL_ML - current_fill_mL)
	transfer             = minf(transfer, dispenser.current_fill_mL)

	if transfer <= 0.0:
		return

	var new_total: float = current_fill_mL + transfer
	if new_total > 0.0:
		stored_water_quality = (current_fill_mL * stored_water_quality + transfer * dispenser.stored_water_quality) / new_total
	current_fill_mL = new_total

	dispenser.current_fill_mL -= transfer
	dispenser.current_fill_mL  = maxf(0.0, dispenser.current_fill_mL)

	_update_empty_tint()
	charge_changed.emit()

func _find_nearest_dispenser() -> WaterDispenser:
	var best_node: WaterDispenser = null
	var best_dist: float = REFILL_RANGE
	for node: Node in get_tree().get_nodes_in_group("water_dispenser"):
		if node is WaterDispenser:
			var d: float = global_position.distance_to((node as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best_node = node as WaterDispenser
	return best_node

# ─── HUD contract (Jul 2026 rework) ───────────────────────────────────────────
## Duck-typed contract for InventoryHUD — checked before the generic
## _get_charge_info() fallback chain. Returns fill fraction (0-1) + water
## quality (0-100) so the HUD can draw a quality-coloured fill badge instead
## of the old sip-count badge.
func get_bottle_badge_info() -> Dictionary:
	return {
		"fill_pct":    current_fill_mL / MAX_FILL_ML,
		"fill_mL":     current_fill_mL,
		"max_fill_mL": MAX_FILL_ML,
		"quality":     stored_water_quality,
	}

# ─── Empty-state tint ─────────────────────────────────────────────────────────
## Applied/cleared any time current_fill_mL crosses the empty threshold in
## either direction (drink → empty, refill → no longer empty) — no longer a
## one-way latch like the old _become_empty().
func _update_empty_tint() -> void:
	if _mesh == null:
		return
	if _is_empty():
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.55, 0.6, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mesh.material_override = mat
	else:
		_mesh.material_override = null

# ─── Drop ─────────────────────────────────────────────────────────────────────
func drop(_world_parent: Node3D, drop_position: Vector3) -> void:
	is_held         = false
	_hold_point     = null
	global_position = drop_position
	gravity_scale   = 1.0
	freeze = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3.ZERO
	add_to_group("pickup")
	_set_held_culling(false)
	dropped.emit()

# ─── Place ────────────────────────────────────────────────────────────────────
func place(_world_parent: Node3D, place_position: Vector3, _rot: Vector3 = Vector3.ZERO) -> void:
	drop(_world_parent, place_position)

# ─── Knocked out ─────────────────────────────────────────────────────────────
func _do_knocked_out() -> void:
	is_held         = false
	_hold_point     = null
	gravity_scale   = 1.0
	freeze = false
	collision_layer = 1
	collision_mask  = 1
	linear_velocity = Vector3(randf_range(-2.0, 2.0), 2.0, randf_range(-2.0, 2.0))
	_set_held_culling(false)
	knocked_out.emit()

# ─── Culling helper ──────────────────────────────────────────────────────────
## While held, expand the culling margin so Godot never clips the item during
## fast turns. Reset to 0 on drop so world items still cull normally.
func _set_held_culling(held: bool) -> void:
	var margin: float = 10.0 if held else 0.0
	for child in get_children():
		if child is GeometryInstance3D:
			child.extra_cull_margin = margin
