extends NPCActivity
class_name CrashOutActivity
## CrashOutActivity.gd (Sep 2026) — what a resident DOES during a HOSTILE or
## BREAKDOWN crash-out (NPCCrashOut owns the state, timing and aftermath;
## OVERDRIVE plays out through ordinary jobs with boosted work scores).
##
## HOSTILE:   storm over to whoever they're furious at and rant at them;
##            then lash out at the bunker — shut the generator off, throw
##            food away, hurl things around; then pace, seething, until it
##            passes. (Attacking arrives with the combat system — see
##            NPCCrashOut.attack_enabled.)
## BREAKDOWN: go somewhere alone, slump against a wall (the lean rig, head
##            down) and fall apart, sobbing now and then.
## Not interruptible — like RimWorld mental breaks, it runs its course.

enum Phase { START, APPROACH, RANT, SABOTAGE, PACE, FIND_SPOT, SLUMP, STAND }

const RANT_SECONDS: Vector2 = Vector2(9.0, 14.0)
const APPROACH_TIMEOUT: float = 18.0
const MAX_SABOTAGE: int = 2

var _phase: Phase = Phase.START
var _timer: float = 0.0
var _bark_timer: float = 0.0
var _sabotage_done: int = 0
var _sabotage_target: Node3D = null
var _sabotage_kind: String = ""
var _leaning: bool = false
var _spot: Dictionary = {}

func score(npc: NPC) -> float:
	if npc.crash != null and npc.crash.active() and npc.crash.mode in [NPCCrashOut.Mode.HOSTILE, NPCCrashOut.Mode.BREAKDOWN]:
		return 1000.0
	return 0.0

func label() -> String:
	return "Crashing out — %s" % _npc_desc

var _npc_desc: String = ""

func interruptible() -> bool:
	return false

func can_yield_to_need(npc: NPC) -> bool:
	## Even a breakdown yields to someone about to die of thirst/hunger.
	return npc.crash.mode == NPCCrashOut.Mode.BREAKDOWN and (npc.hunger < 8.0 or npc.thirst < 8.0)

func backoff_on_futile() -> bool:
	return false

func enter(npc: NPC) -> void:
	_timer = 0.0
	_sabotage_done = npc.crash.sabotaged
	_leaning = false
	if npc.crash.mode == NPCCrashOut.Mode.HOSTILE:
		var t: Node3D = npc.crash.target_node()
		_npc_desc = "furious at %s" % ("you" if npc.crash.target_id == "player" else String(t.get("npc_name")) if t != null else "everyone")
		if npc.crash.confronted or t == null:
			_phase = Phase.SABOTAGE if _sabotage_done < MAX_SABOTAGE else Phase.PACE
		else:
			_phase = Phase.APPROACH
	else:
		_npc_desc = "breaking down"
		_phase = Phase.FIND_SPOT

func tick(npc: NPC, delta: float) -> void:
	_timer += delta
	_bark_timer -= delta
	match _phase:
		Phase.APPROACH:
			var t: Node3D = npc.crash.target_node()
			if t == null or _timer > APPROACH_TIMEOUT:
				_to(Phase.SABOTAGE)
				return
			npc.set_nav_target(t.global_position)
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, t.global_position) < 2.2:
				_to(Phase.RANT)
				_timer = -randf_range(RANT_SECONDS.x, RANT_SECONDS.y)
				_on_confront(npc, t)
		Phase.RANT:
			var t: Node3D = npc.crash.target_node()
			npc.halt_movement(delta)
			if t != null:
				npc.face_toward(t.global_position, delta * 5.0)
			if _bark_timer <= 0.0:
				_bark_timer = randf_range(3.0, 4.5)
				npc.bark(NPCDialogue.rant_line(npc, npc.crash.target_id), true)
			if NPCCrashOut.attack_enabled and t != null:
				_attack(npc, t)
			if _timer >= 0.0:
				_to(Phase.SABOTAGE)
		Phase.SABOTAGE:
			_tick_sabotage(npc, delta)
		Phase.PACE:
			## Seething: short fast legs, muttering.
			npc.nav_steer(delta)
			if npc.nav_finished() or _timer > 8.0:
				_timer = 0.0
				var world: Node = npc.get_tree().get_first_node_in_group("main_world")
				if world != null and world.has_method("get_random_cleared_cell_center"):
					npc.set_nav_target(world.get_random_cleared_cell_center())
			if _bark_timer <= 0.0:
				_bark_timer = randf_range(10.0, 18.0)
				npc.bark_event("seething")
		Phase.FIND_SPOT:
			_spot = _isolated_spot(npc)
			if _spot.is_empty():
				_to(Phase.SLUMP)   ## nowhere to go — fall apart right here
			else:
				npc.set_nav_target(_spot["stand"])
				_to(Phase.STAND)
		Phase.STAND:
			## Walking to the spot (named STAND so SLUMP can mean "there").
			npc.nav_steer(delta)
			var close: bool = NPCItemUser.flat_distance(npc.global_position, _spot["stand"]) < 0.6
			if close or npc.nav_finished() or _timer > APPROACH_TIMEOUT:
				var model: Node = npc.get_node_or_null("CharacterModel")
				if close and model != null and model.has_method("begin_lean") and model.begin_lean(_spot["point"], _spot["normal"]):
					npc.lock_movement()
					_leaning = true
				_to(Phase.SLUMP)
		Phase.SLUMP:
			if not _leaning:
				npc.halt_movement(delta)
			if _bark_timer <= 0.0:
				_bark_timer = randf_range(12.0, 25.0)
				npc.bark_event("sob")

func done(npc: NPC) -> bool:
	return not npc.crash.active()

func exit(npc: NPC) -> void:
	if _leaning:
		var model: Node = npc.get_node_or_null("CharacterModel")
		if model != null:
			model.end_lean()
		npc.request_stand_at(npc.global_position)
		_leaning = false
	_sabotage_target = null

func attention_target(npc: NPC) -> Node3D:
	return npc.crash.target_node() if _phase in [Phase.APPROACH, Phase.RANT] else null

func _to(p: Phase) -> void:
	_phase = p
	_timer = 0.0
	_bark_timer = 0.0

## The confrontation itself: the target (a resident) is shaken by it.
func _on_confront(npc: NPC, t: Node3D) -> void:
	npc.crash.confronted = true
	if t is NPC:
		(t as NPC).bonds.relate(npc.npc_id, -6.0, "screamed at me in a rage", "", true)
		(t as NPC).morale_sys.note_shock(0.3)
		(t as NPC).social.fear = minf(100.0, (t as NPC).social.fear + 20.0)
	npc.log_event("crash", "Confronted %s, shouting" % ("you" if npc.crash.target_id == "player" else String(t.get("npc_name"))))

## Combat hook (not wired yet — see NPCCrashOut.attack_enabled).
func _attack(_npc: NPC, _target: Node3D) -> void:
	pass

# ─── Sabotage ───────────────────────────────────────────────────────────────
func _tick_sabotage(npc: NPC, delta: float) -> void:
	if _sabotage_done >= MAX_SABOTAGE:
		_to(Phase.PACE)
		return
	if _sabotage_target == null or not is_instance_valid(_sabotage_target):
		_pick_sabotage(npc)
		if _sabotage_target == null:
			_to(Phase.PACE)
			return
		npc.set_nav_target(_sabotage_target.global_position)
	npc.nav_steer(delta)
	if _timer > APPROACH_TIMEOUT:
		_sabotage_target = null
		_sabotage_done += 1
		npc.crash.sabotaged = _sabotage_done
		return
	if NPCItemUser.in_reach(npc, _sabotage_target.global_position, 1.9):
		npc.lock_movement()
		npc.face_toward(_sabotage_target.global_position, 1.0)
		_do_sabotage(npc)
		_sabotage_target = null
		_sabotage_done += 1
		npc.crash.sabotaged = _sabotage_done
		_timer = 0.0

func _pick_sabotage(npc: NPC) -> void:
	_sabotage_kind = ""
	## 1. The generator — the cruellest thing to do to a bunker.
	var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
	if pm != null and _sabotage_done == 0:
		for g: Node in npc.get_tree().get_nodes_in_group("generator"):
			if g is Node3D and pm.get_generator_running(str(g.get_instance_id())) \
					and NPCItemUser.is_reachable(npc, (g as Node3D).global_position, 1.9):
				_sabotage_target = g
				_sabotage_kind = "generator"
				return
	## 2. Food lying around.
	var food: RigidBody3D = NPCItemUser.find_loose_item(npc, Callable(NPCItemUser, "is_edible"))
	if food != null and not NPCItemUser.is_claimed_by_other(food, npc):
		_sabotage_target = food
		_sabotage_kind = "food"
		return
	## 3. Anything loose — throw it.
	var anything: RigidBody3D = NPCItemUser.find_loose_item(npc, func(it: Node) -> bool: return true)
	if anything != null:
		_sabotage_target = anything
		_sabotage_kind = "throw"

func _do_sabotage(npc: NPC) -> void:
	match _sabotage_kind:
		"generator":
			var pm: Node = npc.get_tree().get_first_node_in_group("power_manager")
			pm.set_generator_running(str(_sabotage_target.get_instance_id()), false)
			npc.log_event("crash", "Shut the generator off in a rage")
			NotificationManager.notify(UIKit.Domain.POWER, NotificationManager.Severity.CRITICAL,
				"%s shut the generator off!" % npc.npc_name)
			npc.bark_event("sabotage")
		"food":
			var item_name: String = NPCSessionActivity.display_name(_sabotage_target)
			_sabotage_target.queue_free()
			npc.log_event("crash", "Threw away %s" % item_name.to_lower())
			npc.bark_event("sabotage")
		"throw":
			for it: Node in npc.get_tree().get_nodes_in_group("pickup"):
				if it is RigidBody3D and not it.freeze and not (("is_held" in it) and it.is_held) \
						and (it as RigidBody3D).global_position.distance_to(npc.global_position) < 3.0:
					var away: Vector3 = ((it as RigidBody3D).global_position - npc.global_position)
					away.y = 0.0
					(it as RigidBody3D).apply_central_impulse((away.normalized() + Vector3.UP * 0.6) * 4.0)
			npc.log_event("crash", "Threw things around")
			npc.bark_event("sabotage")
	## Everyone who saw it is shaken and angry with them.
	for w: Node in npc.get_tree().get_nodes_in_group("npc"):
		if w != npc and w is NPC and w.global_position.distance_to(npc.global_position) < 10.0:
			(w as NPC).morale_sys.note_shock(0.15)

# ─── Breakdown spot ─────────────────────────────────────────────────────────
## A wall spot as far from everyone else as possible.
func _isolated_spot(npc: NPC) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -1.0
	for i: int in 4:
		var s: Dictionary = LeanActivity.find_spot(npc)
		if s.is_empty():
			continue
		var nearest: float = 99.0
		for o: Node in npc.get_tree().get_nodes_in_group("npc"):
			if o != npc:
				nearest = minf(nearest, (o as Node3D).global_position.distance_to(s["stand"]))
		if nearest > best_score:
			best_score = nearest
			best = s
	return best
