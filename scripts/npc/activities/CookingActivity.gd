extends NPCSessionActivity
class_name CookingActivity
## Cooking (Aug 2026, sustained session, command-only for now). One command
## = one target: serve a ready dish if one exists anywhere; otherwise
## finish an in-progress pot (fetch ingredients one at a time up to
## CookingPot.CAPACITY, or until none are left) over starting a new pot on
## an empty stove. Never waits through the cook timer itself — turns the
## stove on and ends the session, same as every other multi-visit job in
## this system leaving further progress for a later command/think-cycle.
## All progress lives on the Stove/CookingPot objects themselves (no new
## per-NPC memory), so a DIFFERENT NPC picking up this same stove later is
## just... the normal case, not a special one.
##
## Built as a proper NPCSessionActivity (not folded directly into a Command
## wrapper) specifically so a later autonomous-scoring pass only has to
## change score() below — see its own comment for the exact shape to
## follow when that pass happens.

const WORK_RANGE: float = 1.6   ## matches RefuelActivity's WORK_RANGE — distance to work a stove

var _stove: Node = null
var _mode: String = ""            ## "serve", "power", or "setup"
var _phase: String = ""           ## sub-phase, meaning depends on _mode
var _carrying_kind: String = ""   ## "pot" or "ingredient" — which fetch is in flight (setup mode)
var _fetch_loose: RigidBody3D = null
var _fetch_shelf: Dictionary = {}
var _storage_dest: Node = null    ## serve mode only
var _finished: bool = false

func label() -> String:
	if _mode == "serve":
		match _phase:
			"travel_to_stove": return "Heading to plate a dish"
			"travel_to_storage": return "Storing a meal"
			_: return "Serving a dish"
	if _mode == "power":
		return "Heading to restart the stove"
	if _carrying_kind == "pot":
		match _phase:
			"fetch": return "Fetching a Cooking Pot"
			"travel_to_stove": return "Bringing a pot to the stove"
			_: return "Cooking"
	if _carrying_kind == "ingredient":
		match _phase:
			"fetch": return "Fetching an ingredient"
			"travel_to_stove": return "Bringing an ingredient to the pot"
			_: return "Cooking"
	return "Cooking"

## Command-only for now (Aug 2026) — always 0.0, never auto-selected. When
## autonomous scoring is added later, follow REFUEL's own shape exactly:
##   if not NPCJobQueries.has_cooking_target_available(npc): return 0.0
##   return NPC.COOKING_BASE_SCORE * npc.get_work_ethic_job_mult() \
##       * npc.get_job_priority_weight("COOKING")
## (has_cooking_target_available() already exists in NPCJobQueries.gd,
## written for exactly this — nothing else in this file needs to change.)
func score(_npc: NPC) -> float:
	return 0.0

func enter(npc: NPC) -> void:
	_skipped = {}
	_finished = false
	_mode = ""
	_phase = ""
	_stove = null
	_carrying_kind = ""
	_fetch_loose = null
	_fetch_shelf = {}
	_storage_dest = null

	## Recovering mid-carry (e.g. force_command() re-fired this while
	## already holding the pot/ingredient from an interrupted attempt) —
	## re-pick a target for what's already in hand rather than re-fetching.
	if npc.held_item != null and npc.held_item is CookingPot:
		var t: Node = NPCJobQueries.find_cooking_pot_target(npc)
		if t == null:
			NPCItemUser.drop_held(npc)   ## nothing needs this pot anymore
			_finished = true
			return
		if not NPCItemUser.claim_item(t, npc):
			_finished = true
			return
		_mode = "setup"
		_carrying_kind = "pot"
		_stove = t
		_phase = "travel_to_stove"
		npc.set_nav_target(approach_point(npc, _stove))
		return

	if npc.held_item != null and NPCItemUser.is_cookable_ingredient(npc.held_item):
		var t2: Node = NPCJobQueries.find_cooking_ingredient_target(npc)
		if t2 == null:
			NPCItemUser.drop_held(npc)
			_finished = true
			return
		if not NPCItemUser.claim_item(t2, npc):
			_finished = true
			return
		_mode = "setup"
		_carrying_kind = "ingredient"
		_stove = t2
		_phase = "travel_to_stove"
		npc.set_nav_target(approach_point(npc, _stove))
		return

	var serve: Node = NPCJobQueries.find_cooking_serve_target(npc)
	if serve != null:
		_start_serve(npc, serve)
		return

	var power_target: Node = NPCJobQueries.find_cooking_needs_power_target(npc)
	if power_target != null:
		_start_power_retry(npc, power_target)
		return

	var ing_target: Node = NPCJobQueries.find_cooking_ingredient_target(npc)
	if ing_target != null:
		_start_setup(npc, ing_target, "ingredient")
		return

	var pot_target: Node = NPCJobQueries.find_cooking_pot_target(npc)
	if pot_target != null:
		_start_setup(npc, pot_target, "pot")
		return

	_finished = true   ## nothing to do anywhere

func _start_serve(npc: NPC, stove: Node) -> void:
	if not NPCItemUser.claim_item(stove, npc):
		_finished = true
		return
	_mode = "serve"
	_stove = stove
	_phase = "travel_to_stove"
	npc.set_nav_target(approach_point(npc, _stove))

func _start_power_retry(npc: NPC, stove: Node) -> void:
	if not NPCItemUser.claim_item(stove, npc):
		_finished = true
		return
	_mode = "power"
	_stove = stove
	_phase = "travel_to_stove"
	npc.set_nav_target(approach_point(npc, _stove))

func _start_setup(npc: NPC, stove: Node, needs: String) -> void:
	if not NPCItemUser.claim_item(stove, npc):
		_finished = true
		return
	_mode = "setup"
	_stove = stove
	if needs == "pot":
		_begin_fetch_pot(npc)
	else:
		_begin_fetch_ingredient(npc)

func _begin_fetch_pot(npc: NPC) -> void:
	_carrying_kind = "pot"
	_phase = "fetch"
	_fetch_loose = null
	_fetch_shelf = {}
	var filt: Callable = Callable(NPCItemUser, "is_cooking_pot")
	var loose: RigidBody3D = NPCItemUser.find_loose_item(npc, filt)
	var shelf_pick: Dictionary = {} if loose != null else NPCItemUser.find_shelved_item(npc, filt)
	var tgt: Node3D = loose if loose != null \
		else (shelf_pick.get("shelf") as Node3D if not shelf_pick.is_empty() else null)
	if tgt == null:
		_finished = true   ## no Cooking Pot anywhere
		return
	if loose != null:
		if not NPCItemUser.claim_item(loose, npc):
			_finished = true
			return
		_fetch_loose = loose
	else:
		if not NPCItemUser.claim_item(shelf_pick.get("item"), npc):
			_finished = true
			return
		_fetch_shelf = shelf_pick
	npc.set_nav_target(tgt.global_position)

func _begin_fetch_ingredient(npc: NPC) -> void:
	_carrying_kind = "ingredient"
	_phase = "fetch"
	_fetch_loose = null
	_fetch_shelf = {}
	var filt: Callable = Callable(NPCItemUser, "is_cookable_ingredient")
	var loose: RigidBody3D = NPCItemUser.find_loose_item(npc, filt)
	var shelf_pick: Dictionary = {} if loose != null else NPCItemUser.find_shelved_item(npc, filt)
	var tgt: Node3D = loose if loose != null \
		else (shelf_pick.get("shelf") as Node3D if not shelf_pick.is_empty() else null)
	if tgt == null:
		_turn_on_stove(npc)   ## no more ingredients anywhere — cook with whatever's already in
		return
	if loose != null:
		if not NPCItemUser.claim_item(loose, npc):
			_turn_on_stove(npc)   ## momentary claim clash — settle for what's already in the pot
			return
		_fetch_loose = loose
	else:
		if not NPCItemUser.claim_item(shelf_pick.get("item"), npc):
			_turn_on_stove(npc)
			return
		_fetch_shelf = shelf_pick
	npc.set_nav_target(tgt.global_position)

func tick(npc: NPC, delta: float) -> void:
	if _mode == "serve":
		_tick_serve(npc, delta)
	elif _mode == "power":
		_tick_power(npc, delta)
	else:
		_tick_setup(npc, delta)

func _tick_power(npc: NPC, delta: float) -> void:
	if _stove == null or not is_instance_valid(_stove):
		_finished = true
		return
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, (_stove as Node3D).global_position) <= WORK_RANGE:
		npc.velocity = Vector3.ZERO
		_turn_on_stove(npc)

func _tick_serve(npc: NPC, delta: float) -> void:
	match _phase:
		"travel_to_stove":
			if _stove == null or not is_instance_valid(_stove):
				_finished = true
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, (_stove as Node3D).global_position) <= WORK_RANGE:
				npc.velocity = Vector3.ZERO
				_take_dish(npc)
		"travel_to_storage":
			if _storage_dest == null or not is_instance_valid(_storage_dest):
				NPCItemUser.drop_held(npc)
				_finished = true
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, (_storage_dest as Node3D).global_position) <= NPCItemUser.SNATCH_RANGE:
				if npc.held_item != null and _storage_dest.has_method("npc_try_place_item") \
						and _storage_dest.npc_try_place_item(npc, npc.held_item):
					pass   ## stored successfully
				else:
					NPCItemUser.drop_held(npc)
				_finished = true

func _take_dish(npc: NPC) -> void:
	var pot: Node = _stove.pot_ref
	if pot == null or not pot.has_method("is_dish_ready") or not pot.is_dish_ready():
		_finished = true   ## someone else served it, or state changed since target-find
		return
	var result: Dictionary = pot.serve_dish()
	if result.is_empty():
		_finished = true
		return

	## Mirrors InteractionSystem._try_take_dish()'s spawn exactly.
	var dish_script: GDScript = load("res://scripts/world/items/DishItem.gd")
	var dish: RigidBody3D = RigidBody3D.new()
	dish.set_script(dish_script)
	dish.collision_layer = 1
	dish.collision_mask  = 1
	dish.continuous_cd   = true
	## Must be set before add_child() — see InteractionSystem._try_take_dish()'s
	## identical comment. Mirrors that fix exactly.
	dish.fill_value      = float(result["value"])
	dish.bonus_pct       = float(result["bonus_pct"])
	dish.dish_name       = String(result.get("name", "Cooked Dish"))
	dish.hydration_value = float(result.get("hydration", 0.0))

	var world_root: Node = npc.get_tree().get_root()
	world_root.add_child(dish)
	dish.global_position = (_stove as Node3D).global_position
	dish.pickup(npc.hold_point)
	npc.held_item = dish

	if npc.hunger < 55.0:   ## same threshold EatActivity.score() uses
		var name_before: String = dish.dish_name   ## capture before eat_held_step() frees the node
		NPCItemUser.eat_held_step(npc)
		npc.log_action("Cooked and ate %s" % name_before)
		_finished = true
		return

	npc.log_action("Cooked %s" % dish.dish_name)
	_storage_dest = NPCJobQueries.find_cleaning_destination(npc, false, dish)
	if _storage_dest == null:
		NPCItemUser.drop_held(npc)
		_finished = true
		return
	_phase = "travel_to_storage"
	npc.set_nav_target((_storage_dest as Node3D).global_position)

func _tick_setup(npc: NPC, delta: float) -> void:
	match _phase:
		"fetch":
			_tick_fetch(npc, delta)
		"travel_to_stove":
			if _stove == null or not is_instance_valid(_stove):
				_finished = true
				return
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, (_stove as Node3D).global_position) <= WORK_RANGE:
				npc.velocity = Vector3.ZERO
				_apply_at_stove(npc)

## Identical shape to RefuelActivity._tick_fetch() — generalized here since
## _fetch_loose/_fetch_shelf are populated identically regardless of
## whether _carrying_kind is "pot" or "ingredient".
func _tick_fetch(npc: NPC, delta: float) -> void:
	if npc.held_item != null:
		_phase = "travel_to_stove"
		npc.set_nav_target(approach_point(npc, _stove))
		return
	if _fetch_loose != null and is_instance_valid(_fetch_loose):
		if "is_held" in _fetch_loose and _fetch_loose.is_held:
			_fetch_loose = null
			_finished = true
			return
		NPCItemUser.track_fetch_target(npc, _fetch_loose)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, _fetch_loose.global_position) <= NPCItemUser.PICKUP_RANGE:
			if not NPCItemUser.grab_loose(npc, _fetch_loose):
				_finished = true
		return
	if not _fetch_shelf.is_empty():
		var shelf: Node3D = _fetch_shelf.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_finished = true
			return
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) <= NPCItemUser.SHELF_RANGE:
			if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
				_finished = true
		return
	_finished = true

func _apply_at_stove(npc: NPC) -> void:
	if _carrying_kind == "pot":
		if npc.held_item == null or not (npc.held_item is CookingPot):
			_finished = true
			return
		if _stove == null or not is_instance_valid(_stove) or not _stove.has_open_slot():
			NPCItemUser.drop_held(npc)   ## filled/gone since we set out — don't get stuck on a dead trip
			_finished = true
			return
		var pot: RigidBody3D = npc.held_item
		if _stove.try_place_pot(pot):
			npc.held_item = null
			_begin_fetch_ingredient(npc)   ## chain straight into filling it, same session
		else:
			NPCItemUser.drop_held(npc)
			_finished = true
		return

	## _carrying_kind == "ingredient"
	if npc.held_item == null or not NPCItemUser.is_cookable_ingredient(npc.held_item):
		_finished = true
		return
	if _stove == null or not is_instance_valid(_stove) or _stove.pot_ref == null:
		NPCItemUser.drop_held(npc)
		_finished = true
		return
	var pot2: Node = _stove.pot_ref
	if not pot2.has_method("try_add_item") or pot2.is_full():
		NPCItemUser.drop_held(npc)
		_finished = true
		return
	var item: RigidBody3D = npc.held_item
	if pot2.try_add_item(item):
		npc.held_item = null
		if pot2.count_filled() < CookingPot.CAPACITY:
			_begin_fetch_ingredient(npc)
		else:
			_turn_on_stove(npc)
	else:
		NPCItemUser.drop_held(npc)
		_finished = true

func _turn_on_stove(npc: NPC) -> void:
	if _stove == null or not is_instance_valid(_stove) or _stove.pot_ref == null:
		_finished = true
		return
	if _stove.pot_ref.count_filled() <= 0:
		_finished = true   ## empty pot — nothing to cook, leave it for next time
		return
	if not _stove.powered_on:
		_stove.on_interact()   ## turns on if grid-connected; silently no-ops otherwise
		if not _stove.powered_on:
			## Aug 2026 — genuinely no power. on_interact()'s own HUD
			## warning is written for a player caller and doesn't make
			## sense attributed to an NPC. Leave the pot exactly as-is —
			## full, unlit — and leave; find_cooking_needs_power_target()
			## will find this same stove again on the next "Cook a meal"
			## command once power is actually restored. No waiting around.
			NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
				"%s cannot cook meal (Stove unpowered)" % npc.npc_name)
			npc.log_action("Cooking blocked — stove unpowered")
			_finished = true
			return
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO,
			"%s started cooking a meal" % npc.npc_name)
	npc.log_action("Started cooking a meal")
	_finished = true   ## work here is done — leave, per the leave-and-recheck model

func done(_npc: NPC) -> bool:
	return _finished

func debug_info() -> Dictionary:
	return {
		"activity": "cooking",
		"mode": _mode,
		"phase": _phase,
		"carrying": _carrying_kind,
		"stove": (_stove.name if _stove != null and is_instance_valid(_stove) else ""),
		"stove_powered": (_stove.powered_on if _stove != null and is_instance_valid(_stove) else false),
	}

func exit(npc: NPC) -> void:
	if _stove != null:
		NPCItemUser.release_item(_stove)
	if _fetch_loose != null:
		NPCItemUser.release_item(_fetch_loose)
	if not _fetch_shelf.is_empty():
		NPCItemUser.release_item(_fetch_shelf.get("item"))
	var detail: String = "mode=%s phase=%s carrying=%s stove=%s" % [
		_mode, _phase, _carrying_kind,
		(_stove.name if _stove != null and is_instance_valid(_stove) else "none")]
	on_session_exit(npc, "cooking", _finished, detail)
