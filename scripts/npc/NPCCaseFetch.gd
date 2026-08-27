extends RefCounted
class_name NPCCaseFetch
## NPCCaseFetch.gd (Aug 2026)
## Shared case-dispenser fetch state machine — identical logic needed by
## both EatActivity (CanCase) and DrinkActivity (WaterCase), factored out
## here instead of duplicated per-activity (a case is a case, regardless
## of what it dispenses). Only entered by the owning activity once its own
## loose-item and shelved-item search (NPCItemUser.find_fetch_target) has
## already come up completely empty — this is strictly the last-resort
## tier, per Brannon's specified priority order (loose -> shelved -> loose
## case -> shelved case).
##
## Usage (from EatActivity/DrinkActivity):
##   _case_fetch = NPCCaseFetch.new(Callable(NPCItemUser, "is_stocked_can_case"),
##                                   Callable(NPCItemUser, "is_edible"))
##   ... each tick while not _case_fetch.is_done(): _case_fetch.tick(npc, delta) ...
##   once is_done(): if failed() the activity has nothing left to do this
##   run; otherwise get_ejected_item() is a freshly-loose, already-claimed
##   item ready to be handed to the activity's OWN normal loose-item
##   grab/consume logic — NPCCaseFetch's job ends the moment the item
##   exists in the world, it never carries or consumes anything itself.
##
## Flow (Aug 2026, unified — Brannon: same sequence whether the case was
## loose or shelved): locate (loose case -> shelved case) -> travel ->
## PICK UP the case (grab_loose or grab_from_shelf — a loose case is now
## always physically picked up, not interacted with in place) -> wait
## (PRE_EJECT_WAIT) -> eject -> wait (POST_EJECT_WAIT) -> put the case
## back: RESHELVE if it came from a shelf, otherwise DROP it back down
## where the NPC is standing (no storage to return it to) -> done.

enum Phase { LOCATE, TRAVEL_LOOSE, TRAVEL_SHELF, WAIT_PRE_EJECT, EJECT, WAIT_POST_EJECT, RESHELVE, DROP, DONE, FAILED }

const PRE_EJECT_WAIT:  float = 1.0   ## Aug 2026 — Brannon: a beat after picking the case up, before ejecting
const POST_EJECT_WAIT: float = 1.0   ## Aug 2026 — Brannon: a full second (was 0.75), same beat before putting it away
const CASE_RANGE: float = 1.8   ## Aug 2026 — a case is a "larger object" per Brannon's own example, not a small loose item like a can/bottle; deliberately NOT NPCItemUser.PICKUP_RANGE (1.2, tuned for tiny items — reusing it here caused the same push-into-it symptom on a case's bigger collision footprint)

var phase: int = Phase.LOCATE

var _case_filter: Callable
var _item_filter: Callable
var _case: RigidBody3D = null
var _origin_shelf: Node = null
var _origin_slot: int = -1
var _from_shelf: bool = false   ## Aug 2026 — both paths now hold the case at eject time, so npc.held_item == _case no longer distinguishes them; this flag does
var _ejected: RigidBody3D = null
var _wait_timer: float = 0.0

func _init(case_filter: Callable, item_filter: Callable) -> void:
	_case_filter = case_filter
	_item_filter = item_filter

func is_done() -> bool:
	return phase == Phase.DONE or phase == Phase.FAILED

func failed() -> bool:
	return phase == Phase.FAILED

## Only valid once is_done() and not failed(). Already claimed on this
## NPC's behalf — the caller just needs to walk over and grab it via its
## own normal find_loose_item-style flow (it'll be the nearest match).
func get_ejected_item() -> RigidBody3D:
	return _ejected

func tick(npc: NPC, delta: float) -> void:
	match phase:
		Phase.LOCATE:
			_locate(npc)
		Phase.TRAVEL_LOOSE:
			_tick_travel_loose(npc, delta)
		Phase.TRAVEL_SHELF:
			_tick_travel_shelf(npc, delta)
		Phase.WAIT_PRE_EJECT:
			_tick_wait_pre_eject(npc, delta)
		Phase.EJECT:
			_tick_eject(npc, delta)
		Phase.WAIT_POST_EJECT:
			_tick_wait_post_eject(npc, delta)
		Phase.RESHELVE:
			_tick_reshelve(npc, delta)
		Phase.DROP:
			_tick_drop(npc, delta)

func _locate(npc: NPC) -> void:
	var pick: Dictionary = NPCItemUser.find_fetch_target(npc, _case_filter)
	if pick.is_empty():
		phase = Phase.FAILED
		return
	if pick.has("loose"):
		_case = pick["loose"]
		_from_shelf = false
		if not NPCItemUser.claim_item(_case, npc):
			phase = Phase.FAILED
			return
		npc.set_nav_target(_case.global_position)
		phase = Phase.TRAVEL_LOOSE
	else:
		var shelf_pick: Dictionary = pick["shelf"]
		_origin_shelf = shelf_pick.get("shelf")
		_origin_slot = int(shelf_pick.get("slot", -1))
		_case = shelf_pick.get("item")
		_from_shelf = true
		if not NPCItemUser.claim_item(_case, npc):
			phase = Phase.FAILED
			return
		npc.set_nav_target((_origin_shelf as Node3D).global_position)
		phase = Phase.TRAVEL_SHELF

## Aug 2026 — a loose case is now picked up (grab_loose), same as any
## other loose fetch target, instead of being interacted with in place.
func _tick_travel_loose(npc: NPC, delta: float) -> void:
	if _case == null or not is_instance_valid(_case) \
			or ("is_held" in _case and _case.is_held) or _case.is_in_group("shelved"):
		phase = Phase.FAILED
		return
	NPCItemUser.track_fetch_target(npc, _case)
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, _case.global_position) <= CASE_RANGE:
		if NPCItemUser.grab_loose(npc, _case):
			_wait_timer = PRE_EJECT_WAIT
			phase = Phase.WAIT_PRE_EJECT
		else:
			NPCItemUser.release_item(_case)
			_case = null
			phase = Phase.FAILED

func _tick_travel_shelf(npc: NPC, delta: float) -> void:
	if _origin_shelf == null or not is_instance_valid(_origin_shelf):
		phase = Phase.FAILED
		return
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, (_origin_shelf as Node3D).global_position) <= NPCItemUser.SHELF_RANGE:
		if NPCItemUser.grab_from_shelf(npc, _origin_shelf, _origin_slot):
			_case = npc.held_item
			_wait_timer = PRE_EJECT_WAIT
			phase = Phase.WAIT_PRE_EJECT
		else:
			phase = Phase.FAILED   ## slot emptied under us — another NPC/the player got there first

func _tick_wait_pre_eject(npc: NPC, delta: float) -> void:
	npc.halt_movement(delta)
	if npc.held_item != _case or _case == null or not is_instance_valid(_case):
		phase = Phase.FAILED   ## lost it mid-wait (Takeaway, etc.)
		return
	_wait_timer -= delta
	if _wait_timer <= 0.0:
		phase = Phase.EJECT

func _tick_eject(npc: NPC, delta: float) -> void:
	npc.halt_movement(delta)
	if _case == null or not is_instance_valid(_case) or not _case.has_method("on_interact"):
		phase = Phase.FAILED
		return
	_case.on_interact()   ## ejects one item at the case's own SpawnPoint — works whether held or placed, see file header
	_ejected = _find_freshly_ejected(npc)
	_wait_timer = POST_EJECT_WAIT
	phase = Phase.WAIT_POST_EJECT

func _tick_wait_post_eject(npc: NPC, delta: float) -> void:
	npc.halt_movement(delta)
	_wait_timer -= delta
	if _wait_timer > 0.0:
		return
	if npc.held_item != _case or _case == null or not is_instance_valid(_case):
		phase = Phase.DONE   ## lost it somehow — move on regardless
		return
	phase = Phase.RESHELVE if _from_shelf else Phase.DROP

## The item on_interact() just spawned has no direct return value or
## signal — it lands fresh in the "pickup" group at the case's own
## SpawnPoint. Nearest match to the case's current position, called the
## same tick as on_interact() before anything else has a chance to claim
## or move it, is a safe, unambiguous pick. Pre-claimed here so the
## calling activity's own subsequent find_loose_item() call is guaranteed
## to find it uncontested.
func _find_freshly_ejected(npc: NPC) -> RigidBody3D:
	var item: RigidBody3D = NPCItemUser.find_loose_item(npc, _item_filter)
	if item != null:
		NPCItemUser.claim_item(item, npc)
	return item

func _tick_reshelve(npc: NPC, delta: float) -> void:
	if npc.held_item != _case or _case == null or not is_instance_valid(_case):
		phase = Phase.DONE   ## lost it somehow (Takeaway, etc.) — move on regardless
		return
	if _origin_shelf == null or not is_instance_valid(_origin_shelf):
		## Shelf itself vanished (deconstructed mid-session) — set the
		## case down rather than carrying it forever, same graceful-
		## degradation shape CleaningActivity already uses for a
		## no-destination item.
		NPCItemUser.drop_held(npc)
		NPCItemUser.release_item(_case)
		_case = null
		phase = Phase.DONE
		return
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, (_origin_shelf as Node3D).global_position) <= NPCItemUser.SHELF_RANGE:
		if not _origin_shelf.npc_try_place_item(npc, _case):
			## Origin shelf filled by someone/something else in the rare
			## window we were away — just set it down instead of
			## carrying it around indefinitely.
			NPCItemUser.drop_held(npc)
		NPCItemUser.release_item(_case)
		_case = null
		phase = Phase.DONE

## Aug 2026 — a case that was already loose (never came from storage) has
## nowhere to be "returned" to — it just gets set back down where the NPC
## is currently standing, same as any other no-destination item elsewhere
## in this codebase (CleaningActivity's own fallback for the same
## situation).
func _tick_drop(npc: NPC, _delta: float) -> void:
	if npc.held_item == _case and _case != null:
		NPCItemUser.drop_held(npc)
	if _case != null:
		NPCItemUser.release_item(_case)
	_case = null
	phase = Phase.DONE

## Called by the owning activity's exit() if interrupted mid-flow —
## releases whatever claims/holds are still outstanding. Deliberately
## does NOT try to reshelve/set down a held case here (exit() paths
## across this codebase set items down rather than attempt further
## navigation once an activity is being torn down) — matches
## EatActivity/DrinkActivity's own exit() convention of dropping
## whatever's currently held.
func cleanup(npc: NPC) -> void:
	if _case != null:
		NPCItemUser.release_item(_case)
	if _ejected != null:
		NPCItemUser.release_item(_ejected)
