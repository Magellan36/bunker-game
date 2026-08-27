extends NPCActivity
class_name DrinkActivity
## Thirst-driven. Priority: Dispenser/loose bottle (nearest-wins) →
## shelved bottle → loose Water Case → shelved Water Case (Aug 2026 —
## the last two tiers via NPCCaseFetch, shared with EatActivity's
## CanCase handling; see that file for the take-case-out/eject/
## reshelve mechanics).
##
## Bottle handling (Part 12): grabs the bottle FIRST, holds it through
## the full CONSUME_TIME wait, then drinks+drops — mirroring
## EatActivity's order. The previous version grabbed and dropped inside
## the same call at the END of the wait, with zero visible holding
## duration — looked exactly like the bottle teleporting into the hand
## and immediately falling, because that's functionally what happened.
## Also claims its bottle target (NPCItemUser, Part 12) so two NPCs
## can't converge on the same one.
const DRINK_ML:        float = 375.0   ## == WaterBottle.STANDARD_DRINK_ML
const HYDRATION:       float = 21.5    ## == WaterBottle.STANDARD_HYDRATION
const CONSUME_TIME:    float = 2.0
const USE_RANGE:       float = 1.4

var _mode: String = ""        ## "dispenser" | "bottle" | "shelf_bottle" | "case"
var _target: Node = null
var _shelf_pick: Dictionary = {}   ## Aug 2026 — only populated while _mode == "shelf_bottle", before the grab completes
var _drinking: float = 0.0
var _pending_snatch: Node = null   ## Part 30
var _handoff: NPCActivity = null
var _case_fetch: NPCCaseFetch = null   ## Aug 2026 — last-resort tier once dispenser/loose/shelved bottle all come up empty

func label() -> String:
	return "Drinking" if _drinking > 0.0 else "Getting water"

func score(npc: NPC) -> float:
	if npc.thirst >= 55.0:
		return 0.0
	if _pick_target(npc).is_empty() \
			and not npc.is_npc_snatch_eligible(Callable(NPCItemUser, "is_drinkable_bottle")):
		return 0.0
	return (100.0 - npc.thirst) * 1.2 * npc.get_work_ethic_passive_mult()   ## thirst outranks equal-level energy

func _pick_target(npc: NPC) -> Dictionary:
	var best_d: float = INF
	var out: Dictionary = {}
	for d: Node in npc.get_tree().get_nodes_in_group("water_dispenser"):
		if not is_instance_valid(d) or d.current_fill_mL < DRINK_ML:
			continue
		var dist: float = NPCItemUser.flat_distance((d as Node3D).global_position, npc.global_position)
		if dist < best_d:
			best_d = dist
			out = {"mode": "dispenser", "node": d}
	var bottle: RigidBody3D = NPCItemUser.find_loose_item(npc,
		Callable(NPCItemUser, "is_drinkable_bottle"))
	if bottle != null:
		var dist_b: float = NPCItemUser.flat_distance(bottle.global_position, npc.global_position)
		if dist_b < best_d:
			out = {"mode": "bottle", "node": bottle}
	if not out.is_empty():
		return out
	## Aug 2026 — storage-aware fallback tiers, only tried once no dispenser
	## or loose bottle exists anywhere at all. Strict priority order (not a
	## distance comparison against the above) — matches EatActivity's own
	## loose-then-shelf convention and Brannon's specified case ordering.
	var shelf: Dictionary = NPCItemUser.find_shelved_item(npc, Callable(NPCItemUser, "is_drinkable_bottle"))
	if not shelf.is_empty():
		return {"mode": "shelf_bottle", "node": shelf.get("shelf"), "shelf_pick": shelf}
	var case_pick: Dictionary = NPCItemUser.find_fetch_target(npc, Callable(NPCItemUser, "is_stocked_water_case"))
	if not case_pick.is_empty():
		return {"mode": "case"}
	return {}

func enter(npc: NPC) -> void:
	_drinking = 0.0
	_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
	if _pending_snatch != null:
		return   ## handled on first tick() below
	var pick: Dictionary = _pick_target(npc)
	_mode = pick.get("mode", "")
	_target = pick.get("node", null)
	_shelf_pick = pick.get("shelf_pick", {})
	if _mode == "bottle" and _target != null:
		if not NPCItemUser.claim_item(_target, npc):
			_target = null   ## lost the race between scoring and entering
			return
	elif _mode == "shelf_bottle":
		var shelf_item: RigidBody3D = _shelf_pick.get("item")
		if shelf_item == null or not NPCItemUser.claim_item(shelf_item, npc):
			_mode = ""
			_target = null
			return
	elif _mode == "case":
		_case_fetch = NPCCaseFetch.new(Callable(NPCItemUser, "is_stocked_water_case"), Callable(NPCItemUser, "is_drinkable_bottle"))
		return
	if _target != null:
		npc.set_nav_target((_target as Node3D).global_position)

func tick(npc: NPC, delta: float) -> void:
	if _pending_snatch != null:
		_handoff = SnatchActivity.new(_pending_snatch, Callable(NPCItemUser, "is_drinkable_bottle"), false)
		_pending_snatch = null
		return
	if _case_fetch != null:
		if _case_fetch.is_done():
			if not _case_fetch.failed():
				_target = _case_fetch.get_ejected_item()
				_mode = "bottle"
			_case_fetch = null
			return
		_case_fetch.tick(npc, delta)
		return
	if _target == null or not is_instance_valid(_target):
		_target = null
		return
	match _mode:
		"bottle":
			_tick_bottle(npc, delta)
		"shelf_bottle":
			_tick_shelf_bottle(npc, delta)
		_:
			_tick_dispenser(npc, delta)

func _tick_dispenser(npc: NPC, delta: float) -> void:
	if _drinking > 0.0:
		npc.halt_movement(delta)
		_drinking -= delta
		if _drinking <= 0.0:
			_finish_dispenser(npc)
		return
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, (_target as Node3D).global_position) <= USE_RANGE:
		npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO, which Part 13's
		                     ## movement-lock never protected from a late avoidance callback
		_drinking = CONSUME_TIME

func _finish_dispenser(npc: NPC) -> void:
	var d: Node = _target
	var ml: float = minf(DRINK_ML, d.current_fill_mL)
	if ml > 0.0:
		d.current_fill_mL -= ml                       ## REAL deduction
		if d.has_method("_update_fill_visual"):
			d._update_fill_visual()
		npc.thirst = minf(100.0, npc.thirst + HYDRATION * (ml / DRINK_ML))
	_reacquire_or_finish(npc)

func _tick_bottle(npc: NPC, delta: float) -> void:
	if _drinking > 0.0:
		npc.halt_movement(delta)
		_drinking -= delta
		if _drinking <= 0.0:
			_finish_bottle(npc)
		return
	if npc.held_item == _target:
		## Grabbed — start the visible holding/drinking wait.
		npc.lock_movement()   ## Part 16 — was a raw velocity=ZERO (see 3b note)
		_drinking = CONSUME_TIME
		return
	if "is_held" in _target and _target.is_held:
		NPCItemUser.release_item(_target)
		_target = null
		return
	npc.nav_steer(delta)
	## Part 16 — this was the exact bug from the water-bottle report: raw 3D
	## distance against PICKUP_RANGE(1.2), with a loose bottle's ~0.9 vertical
	## offset from the NPC's capsule-center origin eating most of that budget.
	if NPCItemUser.flat_distance(npc.global_position, (_target as Node3D).global_position) <= NPCItemUser.PICKUP_RANGE:
		if not NPCItemUser.grab_loose(npc, _target):
			NPCItemUser.release_item(_target)
			_target = null   ## grab failed — give up cleanly, rescore next think

## Aug 2026 — shelved-bottle pre-phase. Once the grab lands, hands off to
## _tick_bottle() completely (mode flips to "bottle", _target becomes the
## now-held item) — identical holding/drinking/finish logic from there,
## regardless of whether the bottle started loose or shelved.
func _tick_shelf_bottle(npc: NPC, delta: float) -> void:
	if npc.held_item != null:
		_mode = "bottle"
		_target = npc.held_item
		_tick_bottle(npc, delta)
		return
	var shelf: Node3D = _shelf_pick.get("shelf")
	if shelf == null or not is_instance_valid(shelf):
		_target = null
		return
	npc.nav_steer(delta)
	if NPCItemUser.flat_distance(npc.global_position, shelf.global_position) <= NPCItemUser.SHELF_RANGE:
		if not NPCItemUser.grab_from_shelf(npc, shelf, int(_shelf_pick.get("slot", -1))):
			_target = null   ## slot emptied under us

func _finish_bottle(npc: NPC) -> void:
	var b: Node = _target
	if b != null and is_instance_valid(b) and npc.held_item == b:
		npc.thirst = minf(100.0, npc.thirst + b.take_drink())   ## REAL deduction
		NPCItemUser.release_item(b)
		NPCItemUser.drop_held(npc)
	_reacquire_or_finish(npc)

## Part 17 — shared by both finish paths. This is the actual fix: one sip
## (HYDRATION=21.5) essentially never satisfies thirst on its own, so
## setting _target=null unconditionally here (the old behavior) made
## done() end the activity after every single sip, forcing a full
## restart-from-scratch for the next one. Now, if thirst is still low,
## immediately look for a new target and keep going within this SAME
## activity run — only truly finish when satisfied or nothing is left.
func _reacquire_or_finish(npc: NPC) -> void:
	_target = null
	_mode = ""
	_shelf_pick = {}
	_pending_snatch = null
	if npc.thirst >= 90.0:
		return   ## satisfied — done() ends us next tick
	_pending_snatch = npc.find_snatch_target(Callable(NPCItemUser, "is_drinkable_bottle"))
	if _pending_snatch != null:
		return   ## picked up by tick() next frame
	var pick: Dictionary = _pick_target(npc)
	if pick.is_empty():
		return   ## nothing left to try — done() ends us (target stays null)
	_mode = pick.get("mode", "")
	_target = pick.get("node", null)
	_shelf_pick = pick.get("shelf_pick", {})
	if _mode == "bottle" and _target != null:
		if not NPCItemUser.claim_item(_target, npc):
			_target = null
			_mode = ""
			return
	elif _mode == "shelf_bottle":
		var shelf_item: RigidBody3D = _shelf_pick.get("item")
		if shelf_item == null or not NPCItemUser.claim_item(shelf_item, npc):
			_mode = ""
			return
	elif _mode == "case":
		_case_fetch = NPCCaseFetch.new(Callable(NPCItemUser, "is_stocked_water_case"), Callable(NPCItemUser, "is_drinkable_bottle"))
		return
	if _target != null:
		npc.set_nav_target((_target as Node3D).global_position)

func done(npc: NPC) -> bool:
	return (_target == null or npc.thirst >= 90.0) and _pending_snatch == null and _case_fetch == null

func interruptible() -> bool:
	## Aug 2026 fix — see EatActivity's identical fix for the full
	## explanation. Same bug, same cause (a case-fetch left this
	## interruptible the whole time it was in progress).
	return _drinking <= 0.0 and _case_fetch == null

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func exit(npc: NPC) -> void:
	if _case_fetch != null:
		_case_fetch.cleanup(npc)
		_case_fetch = null
	if not _shelf_pick.is_empty():
		NPCItemUser.release_item(_shelf_pick.get("item"))
	if _target != null:
		NPCItemUser.release_item(_target)
	if npc.held_item != null:
		NPCItemUser.release_item(npc.held_item)
		NPCItemUser.drop_held(npc)
	_target = null
	_shelf_pick = {}
	_drinking = 0.0