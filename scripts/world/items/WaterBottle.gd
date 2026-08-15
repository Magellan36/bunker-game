extends PickupableItem
## WaterBottle.gd
## Pickupable consumable. Continuous mL-based fill + blended water quality
## (Jul 2026 rework — replaces the old fixed 2-sip model).
## Drinking (tap E) removes up to STANDARD_DRINK_ML at once, restoring
## hydration proportional to however much water was actually available.
## Refilling (hold E near a WaterDispenser) continuously transfers water
## from the dispenser's tank, blending quality volume-weighted exactly like
## WaterDispenser.gd blends from a hookup.

# ─── Config ───────────────────────────────────────────────────────────────────
const MAX_FILL_ML:        float = 750.0   ## Full bottle capacity
const STANDARD_DRINK_ML:  float = 375.0   ## One "drink" — half the bottle at full
const STANDARD_HYDRATION: float = 21.5    ## Hydration restored by one FULL standard drink

## Continuous refill rate — mirrors FuelCan.FUEL_RATE's derivation exactly:
## FuelCan refuels 100 units in 12.5s (FUEL_RATE=8.0/s). Same 12.5s-to-full
## target applied to this bottle's 750mL capacity: 750 / 12.5 = 60.0 mL/s.
const REFILL_RATE_ML_PER_SEC: float = 60.0
const REFILL_RANGE:           float = 2.5   ## Max distance to a WaterDispenser to refill

## Shelf stacking — 6 bottles per slot, stand upright in two rows of 3
var shelf_stack_limit: int   = 6
var shelf_item_type: String  = "water_bottle"

# ─── State ───────────────────────────────────────────────────────────────────
var _player_stats: Node     = null

## Spawns full. current_fill_mL is the single source of truth for "empty" —
## _is_empty() is a computed check (current_fill_mL <= 0.0), not a one-way
## latch, so refilling a drained bottle correctly un-empties it.
var current_fill_mL: float     = MAX_FILL_ML
var stored_water_quality: float = 100.0

# ─── Node refs (set in _ready) ────────────────────────────────────────────────
var _mesh: MeshInstance3D = null ## For tinting when empty

func _ready() -> void:
	super._ready()
	add_to_group("inventory_item")
	add_to_group("basket_storable")
	add_to_group("cookpot_storable")
	_mesh = get_node_or_null("MeshInstance3D")

# ─── Empty check (computed, not a latch) ──────────────────────────────────────
func _is_empty() -> bool:
	return current_fill_mL <= 0.0

## Aug 2026 — Cleaning's generic trash convention (see JobBoard._is_trash_item()'s
## own comment). Same reasoning as FoodCan.is_trash() — an empty bottle
## stays the same node, so this reads the live computed state, not a
## one-time group tag; refilling correctly un-trashes it automatically.
func is_trash() -> bool:
	return _is_empty()

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

func get_trash_material() -> String:
	return "organic" if current_fill_mL > 0.0 else "plastic"

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

	_player_stats.replenish_water(take_drink())

## Deducts one standard drink from this bottle and returns the hydration it
## restores. Shared mutation for BOTH the player (on_use above) and NPCs
## (NPCItemUser) — NPC Pass 2, Part 3. Values stay linked by construction:
## there is exactly one place a drink leaves a bottle.
func take_drink() -> float:
	var amount_removed: float = minf(STANDARD_DRINK_ML, current_fill_mL)
	if amount_removed <= 0.0:
		return 0.0
	var hydration: float = STANDARD_HYDRATION * (amount_removed / STANDARD_DRINK_ML)
	current_fill_mL -= amount_removed
	current_fill_mL  = maxf(0.0, current_fill_mL)
	_update_empty_tint()
	charge_changed.emit()
	return hydration

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
