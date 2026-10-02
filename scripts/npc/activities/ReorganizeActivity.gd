extends NPCActivity
## ReorganizeActivity.gd (Oct 2026, Brannon) — an organized eye on storage.
## When a clearly better place opens up for something already put away, a
## resident with nothing better to do moves it. Examples:
##   - a drawer frees up and a bandage is sitting on a shelf;
##   - the garden shelf has room and a seed bag is across the bunker;
##   - a lone water case sits with the medicine.
## Moves come from StorageProfile.moves(): single moves into free space that
## make storage strictly tidier. Never swaps or chains, never what the player
## put away in the last game day, never the same item twice in 20 minutes,
## at most MAX_ACTIVE at once across the bunker.
## Low priority in normal play (just above wandering). During preparation,
## when there's little else to do, it comes next after putting purchases
## away (NPCBrain.PREP_ALLOWED). Residents say why, and the label and log
## name it ("Moving Bandage to the dresser (in a drawer)").

const STORAGE_PROFILE: GDScript = preload("res://scripts/npc/queries/StorageProfile.gd")
const SCORE: float = 6.0
const PREP_SCORE: float = 25.0
const MAX_ACTIVE: int = 2
const COOLDOWN_MS: Vector2 = Vector2(60000.0, 150000.0)    ## normal play, per resident
const PREP_COOLDOWN_MS: Vector2 = Vector2(2000.0, 5000.0)
const GIVE_UP_SECONDS: float = 30.0

## item instance id -> npc instance id: moves in progress, bunker-wide.
static var _active: Dictionary = {}

enum Phase { FETCH, CARRY, DONE }

var _move: Dictionary = {}
var _phase: Phase = Phase.DONE
var _timer: float = 0.0
var _why: String = ""
var _handoff: NPCActivity = null

func label() -> String:
	if _move.is_empty() or not is_instance_valid(_move["item"]):
		return "Organizing"
	var where: String = String(STORAGE_PROFILE.PHRASES.get(_why, ""))
	return "Moving %s to the %s%s" % [NPCSessionActivity.display_name(_move["item"]), _storage_name(_move["to"]),
		" (%s)" % where if where != "" else ""]

static func _storage_name(s: Variant) -> String:
	var n: Variant = (s as Node).get("display_name") if is_instance_valid(s) else null
	return String(n).to_lower() if n != null and String(n) != "" else "shelf"

func score(npc: NPC) -> float:
	if NPCItemUser.hands_full(npc) or npc.crash.active() or npc.is_night_for_me():
		return 0.0
	var preparing: bool = npc.is_preparing()
	if not preparing and (npc.hunger < 35.0 or npc.thirst < 35.0 or npc.energy < 30.0):
		return 0.0   ## (needs are on hold before the seal)
	if Time.get_ticks_msec() < int(npc.get_meta("_reorg_cooldown_ms", 0)):
		return 0.0
	if _busy_count(npc) >= MAX_ACTIVE or _pick(npc).is_empty():
		return 0.0
	return PREP_SCORE if preparing else SCORE

## Moves others are making right now (forgetting residents who are gone).
static func _busy_count(npc: NPC) -> int:
	var n: int = 0
	for id: int in _active.keys():
		var who: Object = instance_from_id(int(_active[id]))
		if who == null or not is_instance_valid(who) or instance_from_id(id) == null:
			_active.erase(id)
		elif who != npc:
			n += 1
	return n

## The best move this resident can make now.
func _pick(npc: NPC) -> Dictionary:
	for m: Dictionary in STORAGE_PROFILE.moves(npc.get_tree()):
		## The list is cached a few seconds: anything in it may be gone since
		## (eaten, merged, freed). Check before touching it as a Node.
		if not is_instance_valid(m["item"]) or not is_instance_valid(m["from"]) or not is_instance_valid(m["to"]):
			continue
		var item: Node = m["item"]
		if _active.has(item.get_instance_id()) and int(_active[item.get_instance_id()]) != npc.get_instance_id():
			continue
		if NPCItemUser.is_claimed_by_other(item, npc) or NPCItemUser.is_claimed_by_other(m["to"], npc):
			continue
		if npc.job_state.is_unreachable(m["from"]) or npc.job_state.is_unreachable(m["to"]):
			continue
		if not NPCItemUser.is_reachable(npc, (m["from"] as Node3D).global_position, NPCItemUser.SHELF_RANGE):
			npc.job_state.mark_unreachable(m["from"])
			continue
		return m
	return {}

func interruptible() -> bool:
	return _phase != Phase.CARRY   ## hands empty: anything that matters may take over

func can_yield_to_need(_npc: NPC) -> bool:
	return true

func accepts_held_item(_npc: NPC, item_in_hand: Node) -> bool:
	return not _move.is_empty() and item_in_hand == _move["item"]

func enter(npc: NPC) -> void:
	_timer = 0.0
	_handoff = null
	_move = _pick(npc)
	if _move.is_empty():
		_phase = Phase.DONE
		return
	_active[(_move["item"] as Node).get_instance_id()] = npc.get_instance_id()
	NPCItemUser.claim_item(_move["item"], npc)
	_why = String(_move["reason"])
	_phase = Phase.FETCH
	npc.set_nav_target((_move["from"] as Node3D).global_position)
	if _why != "":
		var now: int = Time.get_ticks_msec()
		if now - int(npc.get_meta("_storage_remark_ms", -NPCJobQueries.STORAGE_REMARK_GAP_MS)) >= NPCJobQueries.STORAGE_REMARK_GAP_MS:
			npc.set_meta("_storage_remark_ms", now)
			npc.bark(NPCDialogue.bark_line("organize_" + _why))

func tick(npc: NPC, delta: float) -> void:
	_timer += delta
	match _phase:
		Phase.FETCH:
			_tick_fetch(npc, delta)
		Phase.CARRY:
			_tick_carry(npc, delta)

func _tick_fetch(npc: NPC, delta: float) -> void:
	if not is_instance_valid(_move["from"]) or not is_instance_valid(_move["item"]):
		_phase = Phase.DONE   ## gone
		return
	var src: Node = _move["from"]
	var item: Node = _move["item"]
	if not _still_there(src, int(_move["slot"]), item):
		_phase = Phase.DONE   ## someone took it, or it moved: nothing to do
		return
	if _timer > GIVE_UP_SECONDS:
		npc.job_state.mark_unreachable(src)
		_phase = Phase.DONE
		return
	if NPCItemUser.wait_turn_at(npc, src, delta):
		return   ## someone's at that storage: wait a little way back
	npc.nav_steer(delta)
	if not NPCItemUser.in_reach(npc, (src as Node3D).global_position, NPCItemUser.SHELF_RANGE):
		return
	npc.lock_movement()
	var took: bool = false
	if "slots" in src:
		took = NPCItemUser.grab_from_shelf(npc, src, int(_move["slot"]))
	elif src.has_method("npc_take"):
		var got: RigidBody3D = src.npc_take(int(_move["slot"]), npc.hold_point)
		if got != null:
			npc.held_item = got
			took = true
	NPCItemUser.release_item(src)   ## next person's turn at that storage
	if not took or npc.held_item != item:
		_phase = Phase.DONE
		return
	STORAGE_PROFILE.invalidate()
	_phase = Phase.CARRY
	_timer = 0.0
	npc.set_nav_target((_move["to"] as Node3D).global_position)

static func _still_there(src: Node, slot: int, item: Node) -> bool:
	if "slots" in src:
		var stacks: Array = src.slots
		return slot >= 0 and slot < stacks.size() and not (stacks[slot] as Array).is_empty() and stacks[slot].back() == item
	if "stored" in src:
		var stored: Array = src.stored
		return slot >= 0 and slot < stored.size() and stored[slot] == item
	return false

func _tick_carry(npc: NPC, delta: float) -> void:
	if not is_instance_valid(_move["item"]) or npc.held_item != _move["item"]:
		_phase = Phase.DONE
		return
	var item: Node = _move["item"]
	var dst: Variant = _move["to"]
	## Can't get there, or it filled up: the usual put-away finds the best place now.
	if not is_instance_valid(dst) or _timer > GIVE_UP_SECONDS or (dst.has_method("has_room_for") and not dst.has_room_for(item)):
		if is_instance_valid(dst) and _timer > GIVE_UP_SECONDS:
			npc.job_state.mark_unreachable(dst)
		_put_away_instead()
		return
	if NPCItemUser.wait_turn_at(npc, dst, delta):
		return
	npc.nav_steer(delta)
	if not NPCItemUser.in_reach(npc, (dst as Node3D).global_position, NPCItemUser.SHELF_RANGE):
		return
	npc.lock_movement()
	var name: String = NPCSessionActivity.display_name(item)
	if NPCItemUser.store_held(npc, dst):
		item.set_meta("_reorg_ms", Time.get_ticks_msec())
		var where: String = String(STORAGE_PROFILE.PHRASES.get(_why, ""))
		npc.log_action("Moved %s to the %s%s" % [name, _storage_name(dst), " (%s)" % where if where != "" else ""])
		NPCItemUser.release_item(dst)
		_phase = Phase.DONE
	else:
		_put_away_instead()

func _put_away_instead() -> void:
	_handoff = PutAwayHeldItemActivity.new()
	_phase = Phase.DONE

func take_handoff() -> NPCActivity:
	var h: NPCActivity = _handoff
	_handoff = null
	return h

func done(_npc: NPC) -> bool:
	return _phase == Phase.DONE

func exit(npc: NPC) -> void:
	if not _move.is_empty() and is_instance_valid(_move["item"]):
		_active.erase((_move["item"] as Node).get_instance_id())
	var gap: Vector2 = PREP_COOLDOWN_MS if npc.is_preparing() else COOLDOWN_MS
	npc.set_meta("_reorg_cooldown_ms", Time.get_ticks_msec() + int(randf_range(gap.x, gap.y)))
	STORAGE_PROFILE.invalidate()

func attention_target(_npc: NPC) -> Node3D:
	return null
