extends NPCSessionActivity
class_name CookingActivity
## CookingActivity.gd — kitchen work, one opportunity per session (see
## NPCJobQueries.cooking_opportunity()):
##   serve      — a dish is ready: plate it; eat it if hungry, else store it
##   power      — a filled pot sits on a stove that's off: switch it on
##   ingredient — a pot on a stove has room: fetch ingredients (one at a
##                time, up to CookingPot.CAPACITY), then switch it on
##   pot        — a stove has no pot: fetch one, place it, then fill it
## Never waits out the cook timer — it leaves and a later session (anyone's)
## serves the dish. All progress lives on the Stove/CookingPot, so any
## resident can pick up where another left off.
##
## Sep 2026: now autonomous — residents cook whenever ingredients are in
## reach and no cooked meal is waiting (meal prep), sooner when someone is
## getting hungry (NPCJobQueries.cooking_demand()), and they only load or
## switch on a pot on a CONNECTED stove (a pot may still be set on an
## unplugged one, ready for later), and
## always serve a finished dish or restart a stove that lost power. A
## stove that can't be switched on (no grid) is left alone for a while
## instead of being retried (and re-notified) every few seconds. Each step
## at the stove is a short visible work beat.

const WORK_RANGE: float = 1.8
const STEP_TIME: float = 1.6            ## seconds per action at the stove
const UNPOWERED_RETRY_HOURS: float = 2.0

var _stove: Node = null
var _mode: String = ""
var _phase: String = ""                 ## fetch | travel | work | store
var _fetch_loose: RigidBody3D = null
var _fetch_shelf: Dictionary = {}
var _storage_dest: Node = null
var _work_left: float = 0.0
var _finished: bool = false

## Head looks only at people (Brannon, Sep 2026): forward while cooking.
func attention_target(_npc: NPC) -> Node3D:
	return null

func label() -> String:
	match _mode:
		"serve":
			return "Storing a meal" if _phase == "store" else "Plating a meal"
		"power":
			return "Switching on the stove"
		"pot":
			return "Fetching a cooking pot" if _phase == "fetch" else "Setting up the stove"
		"ingredient":
			return "Fetching ingredients" if _phase == "fetch" else "Cooking"
	return "Cooking"

func score(npc: NPC) -> float:
	var opp: Dictionary = NPCJobQueries.cooking_opportunity(npc)
	if opp.is_empty():
		return 0.0
	match String(opp["mode"]):
		"serve":
			return npc.work_score("COOKING", 1.4)
		"power":
			return npc.work_score("COOKING", 1.2)
	var demand: float = NPCJobQueries.cooking_demand(npc)
	if demand <= 0.0:
		return 0.0
	return npc.work_score("COOKING", 0.8 + 0.6 * demand)

func accepts_held_item(_npc: NPC, item: Node) -> bool:
	return item is CookingPot or NPCItemUser.is_cookable_ingredient(item)

func enter(npc: NPC) -> void:
	_skipped = {}
	_case_tries = 0
	_finished = false
	var opp: Dictionary = NPCJobQueries.cooking_opportunity(npc)
	if opp.is_empty():
		_finished = true
		return
	_stove = opp["stove"]
	_mode = String(opp["mode"])
	if not NPCItemUser.claim_item(_stove, npc):
		_finished = true
		return
	## Already carrying the right thing? Go straight to the stove.
	if NPCItemUser.hands_full(npc):
		if _held_fits(npc):
			_go_to_stove(npc)
		else:
			_handoff = PutAwayHeldItemActivity.new()   ## put it away first, then someone cooks
			_finished = true
		return
	if _mode == "pot" or _mode == "ingredient":
		_begin_fetch(npc)
	else:
		_go_to_stove(npc)

## Does what's in hand fit the current step? (A water bottle only once the
## pot already has food and no water.)
func _held_fits(npc: NPC) -> bool:
	var item: Node = npc.held_item
	if _mode == "pot":
		return item is CookingPot
	if _mode != "ingredient":
		return false
	for f: Callable in _ingredient_filters():
		if f.call(item):
			return true
	return false

var _handoff: NPCActivity = null
func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func _fetch_filter() -> Callable:
	return Callable(NPCItemUser, "is_cooking_pot") if _mode == "pot" else Callable(NPCItemUser, "is_cookable_ingredient")

## Ingredient search order (Sep 2026): best available quality first —
## fresh produce, then food cans (loose or from shelving/storage). One water
## bottle may go in as a soup base once the pot already has food in it.
func _ingredient_filters() -> Array[Callable]:
	var out: Array[Callable] = [Callable(NPCItemUser, "is_fresh_produce"), Callable(NPCItemUser, "is_food_can")]
	var pot: Node = _stove.pot_ref if _stove != null and is_instance_valid(_stove) else null
	if pot != null and pot.count_filled() > 0 and _water_in_pot(pot) == 0:
		out.append(Callable(NPCItemUser, "is_drinkable_bottle"))
	return out

static func _water_in_pot(pot: Node) -> int:
	var n: int = 0
	if "slots" in pot:
		for entry in pot.slots:
			if entry != null and String(entry.get("ingredient_key", "")) == "water_bottle":
				n += 1
	return n

func _begin_fetch(npc: NPC) -> void:
	_phase = "fetch"
	var pick: Dictionary = {}
	if _mode == "pot":
		pick = NPCItemUser.find_fetch_target(npc, _fetch_filter())
	else:
		for f: Callable in _ingredient_filters():
			pick = NPCItemUser.find_fetch_target(npc, f)
			if not pick.is_empty():
				break
	_fetch_loose = pick.get("loose")
	_fetch_shelf = pick.get("shelf", {})
	var tgt: Node3D = _fetch_loose if _fetch_loose != null else (_fetch_shelf.get("shelf") as Node3D if not _fetch_shelf.is_empty() else null)
	var claim_target: Node = _fetch_loose if _fetch_loose != null else _fetch_shelf.get("item")
	if tgt == null or not NPCItemUser.claim_item(claim_target, npc):
		## Last resort: open a stocked can case (or a water case for the
		## soup base) — the same dispenser flow residents use to eat.
		if _mode == "ingredient" and _start_case_fetch(npc):
			return
		_dbg(npc, "fetch found nothing (mode=%s)" % _mode)
		## No more ingredients: cook with what's already in the pot.
		if _mode == "ingredient":
			_mode = "power"
			_go_to_stove(npc)
		else:
			_finished = true
		return
	npc.set_nav_target(tgt.global_position)

var _case_fetch: NPCCaseFetch = null
var _case_tries: int = 0

func _start_case_fetch(npc: NPC) -> bool:
	if _case_tries >= 3:
		return false
	var pairs: Array = [[Callable(NPCItemUser, "is_stocked_can_case"), Callable(NPCItemUser, "is_food_can")]]
	if Callable(NPCItemUser, "is_drinkable_bottle") in _ingredient_filters():
		pairs.append([Callable(NPCItemUser, "is_stocked_water_case"), Callable(NPCItemUser, "is_drinkable_bottle")])
	for pair: Array in pairs:
		if not NPCItemUser.find_fetch_target(npc, pair[0]).is_empty():
			_case_tries += 1
			_case_fetch = NPCCaseFetch.new(pair[0], pair[1])
			return true
	return false

func _go_to_stove(npc: NPC) -> void:
	_phase = "travel"
	npc.set_nav_target(approach_point(npc, _stove))

func tick(npc: NPC, delta: float) -> void:
	if _finished:
		return
	if _stove == null or not is_instance_valid(_stove):
		_finished = true
		return
	match _phase:
		"fetch":
			_tick_fetch(npc, delta)
		"travel":
			npc.nav_steer(delta)
			if NPCItemUser.in_reach(npc, (_stove as Node3D).global_position, WORK_RANGE):
				npc.lock_movement()
				npc.face_toward((_stove as Node3D).global_position, 1.0)
				_phase = "work"
				_work_left = STEP_TIME
				npc.show_work_banner()
		"work":
			npc.halt_movement(delta)
			_work_left -= delta * npc.get_work_speed_mult("cooking")
			npc.update_work_banner(label().to_upper(), 1.0 - _work_left / STEP_TIME)
			if _work_left <= 0.0:
				npc.hide_work_banner()
				_do_step(npc)
		"store":
			_tick_store(npc, delta)

func _tick_fetch(npc: NPC, delta: float) -> void:
	if _case_fetch != null:
		if not _case_fetch.is_done():
			_case_fetch.tick(npc, delta)
			return
		var item: RigidBody3D = null if _case_fetch.failed() else _case_fetch.get_ejected_item()
		_case_fetch = null
		if item != null and is_instance_valid(item):
			_fetch_loose = item   ## already claimed by NPCCaseFetch
			_fetch_shelf = {}
			npc.set_nav_target(item.global_position)
		else:
			_begin_fetch(npc)
		return
	if NPCItemUser.hands_full(npc):
		if _held_fits(npc):
			_go_to_stove(npc)
		else:
			_handoff = PutAwayHeldItemActivity.new()   ## not usable here — put it away tidily
			_finished = true
		return
	if _fetch_loose != null:
		if not is_instance_valid(_fetch_loose) or (("is_held" in _fetch_loose) and _fetch_loose.is_held) or NPCItemUser.is_on_stove(_fetch_loose):
			_begin_fetch(npc)
			return
		NPCItemUser.track_fetch_target(npc, _fetch_loose)
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, _fetch_loose.global_position, NPCItemUser.PICKUP_RANGE):
			if not NPCItemUser.grab_loose(npc, _fetch_loose):
				_begin_fetch(npc)
		return
	if not _fetch_shelf.is_empty():
		var shelf: Node3D = _fetch_shelf.get("shelf")
		if shelf == null or not is_instance_valid(shelf):
			_begin_fetch(npc)
			return
		npc.nav_steer(delta)
		if NPCItemUser.in_reach(npc, shelf.global_position, NPCItemUser.SHELF_RANGE):
			if not NPCItemUser.grab_from_shelf(npc, shelf, int(_fetch_shelf.get("slot", -1))):
				_begin_fetch(npc)
		return
	_finished = true

func _do_step(npc: NPC) -> void:
	match _mode:
		"serve":
			_take_dish(npc)
		"power":
			_turn_on_stove(npc)
		"pot":
			if npc.held_item is CookingPot and _stove.has_open_slot() and _stove.try_place_pot(npc.held_item):
				NPCItemUser.release_item(npc.held_item)
				npc.held_item = null
				npc.log_action("Set a pot on the stove")
				if not NPCJobQueries.stove_connected(_stove):
					_finished = true   ## ready for when it's wired up — no cooking on an unplugged stove
					return
				_mode = "ingredient"
				_begin_fetch(npc)
			else:
				_finished = true
		"ingredient":
			var pot: Node = _stove.pot_ref
			if pot == null or not NPCItemUser.hands_full(npc) or pot.is_full() or (pot.has_method("is_dish_ready") and pot.is_dish_ready()):
				_dbg(npc, "ingredient step aborted (pot=%s hands=%s)" % [pot, NPCItemUser.hands_full(npc)])
				_finished = true
				return
			var item: RigidBody3D = npc.held_item
			var item_name: String = display_name(item)
			if pot.try_add_item(item):
				NPCItemUser.release_item(item)
				if npc.held_item == item:
					npc.held_item = null
				npc.log_action("Added %s to the pot" % item_name)
				if pot.count_filled() < CookingPot.CAPACITY:
					_begin_fetch(npc)
				else:
					_turn_on_stove(npc)
			else:
				_dbg(npc, "pot refused %s" % item_name)
				_finished = true

func _take_dish(npc: NPC) -> void:
	var pot: Node = _stove.pot_ref
	if pot == null or not pot.has_method("is_dish_ready") or not pot.is_dish_ready():
		_finished = true
		return
	var result: Dictionary = pot.serve_dish()
	if result.is_empty():
		_finished = true
		return
	_stove.npc_set_powered(false)

	var dish: RigidBody3D = RigidBody3D.new()
	dish.set_script(load("res://scripts/world/items/DishItem.gd"))
	dish.collision_layer = 1
	dish.collision_mask = 1
	dish.continuous_cd = true
	dish.fill_value = float(result["value"])
	dish.bonus_pct = float(result["bonus_pct"])
	dish.dish_name = String(result.get("name", "Cooked Dish"))
	dish.hydration_value = float(result.get("hydration", 0.0))
	var world: Node = npc.get_tree().get_first_node_in_group("main_world")
	(world if world != null else npc.get_tree().get_root()).add_child(dish)
	dish.global_position = (_stove as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
	dish.pickup(npc.hold_point)
	npc.held_item = dish
	npc.on_work_done("cooking")
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO,
		"%s cooked %s" % [npc.npc_name, dish.dish_name])

	if npc.hunger < 60.0:
		var name_before: String = dish.dish_name
		NPCItemUser.eat_held_step(npc)
		npc.log_action("Cooked and ate %s" % name_before)
		_finished = true
		return
	npc.log_action("Cooked %s" % dish.dish_name)
	npc.bark_event("food_ready")
	_storage_dest = NPCJobQueries.find_cleaning_destination(npc, false, dish)
	if _storage_dest == null:
		NPCItemUser.drop_held(npc)   ## leave it out where people can find it
		_finished = true
		return
	_phase = "store"
	npc.set_nav_target((_storage_dest as Node3D).global_position)

func _tick_store(npc: NPC, delta: float) -> void:
	if _storage_dest == null or not is_instance_valid(_storage_dest) or not NPCItemUser.hands_full(npc):
		if NPCItemUser.hands_full(npc):
			NPCItemUser.drop_held(npc)
		_finished = true
		return
	npc.nav_steer(delta)
	if NPCItemUser.in_reach(npc, (_storage_dest as Node3D).global_position, NPCItemUser.SNATCH_RANGE):
		npc.lock_movement()
		if not NPCItemUser.store_held(npc, _storage_dest):
			NPCItemUser.drop_held(npc)
		_finished = true

func _turn_on_stove(npc: NPC) -> void:
	_finished = true
	var pot: Node = _stove.pot_ref
	if pot == null or pot.count_filled() <= 0:
		return
	if _stove.powered_on:
		npc.log_action("Checked on the cooking")
		return
	if not _stove.npc_set_powered(true):
		_stove.set_meta("_npc_unpowered_until", NPCClock.now() + UNPOWERED_RETRY_HOURS)
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING,
			"%s can't cook — the stove has no power" % npc.npc_name)
		npc.log_action("Cooking blocked — stove unpowered")
		return
	npc.log_action("Started cooking a meal")
	npc.on_work_done("cooking")

func done(_npc: NPC) -> bool:
	return _finished

func _dbg(npc: NPC, msg: String) -> void:
	if NPCDebug.enabled:
		NPCDebug.log_cleaning(npc, "cooking", msg)

func debug_info() -> Dictionary:
	return {
		"activity": "cooking",
		"mode": _mode,
		"phase": _phase,
		"stove": (_stove.name if _stove != null and is_instance_valid(_stove) else ""),
		"stove_powered": (_stove.powered_on if _stove != null and is_instance_valid(_stove) else false),
	}

func exit(npc: NPC) -> void:
	if _case_fetch != null:
		_case_fetch.cleanup(npc)
		_case_fetch = null
	var detail: String = "mode=%s phase=%s" % [_mode, _phase]
	on_session_exit(npc, "cooking", _finished, detail)
