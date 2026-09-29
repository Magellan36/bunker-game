extends NPCActivity
class_name CrashOutActivity
## CrashOutActivity.gd (Sep 2026) — what a resident DOES during a HOSTILE or
## BREAKDOWN crash-out (NPCCrashOut owns the state, timing and aftermath;
## OVERDRIVE plays out through ordinary jobs with boosted work scores).
##
## HOSTILE:   storm over to whoever they're furious at and rant at them;
##            then lash out at the bunker — shut the generator off, throw
##            food away, hurl things around; then pace, seething, until it
##            passes. Lighter hatred (BRAWL_BELOW) turns the rant into a
##            fist fight instead (Fists, until the target is beaten down or
##            it blows over). When it has ESCALATED (a repeat crash-out, a
##            deep hatred, or the target hit them first) they go for a
##            weapon lying within reach (or their fists) and try to kill
##            (NPCCombat; weapons contract in docs/systems/weapons/HANDOFF.md).
## BREAKDOWN: go somewhere alone, slump against a wall (the lean rig, head
##            down) and fall apart, sobbing now and then.
## Not interruptible — like RimWorld mental breaks, it runs its course.

enum Phase { START, APPROACH, RANT, SABOTAGE, PACE, FIND_SPOT, SLUMP, STAND, ARM, ATTACK, GLARE }

const RANT_SECONDS: Vector2 = Vector2(9.0, 14.0)
const APPROACH_TIMEOUT: float = 18.0
const MAX_SABOTAGE: int = 2
const WEAPON_SEARCH: float = 14.0
const ATTACK_SECONDS: Vector2 = Vector2(12.0, 20.0)
const ESCALATE_BELOW: float = -65.0      ## relationship (incl. half the grudge) that turns a rant into an attack
const GUN_RANGE: float = 7.0
const BRAWL_BELOW: float = -50.0         ## hatred between this and ESCALATE_BELOW: a fist fight, not sabotage
const BRAWL_SECONDS: Vector2 = Vector2(6.0, 10.0)
const BRAWL_STOP_HEALTH: float = 45.0    ## a brawl stops once the target is beaten down to this
## Fight feel. Capsules touch at 0.8 m between centres; fists reach 1.1 m.
const CLOSE_IN_AT: float = 2.4           ## within this, walk straight in (avoidance would steer around them)
const MIN_SPACING: float = 0.9           ## never crowd closer than this (centre to centre)
const SQUARE_UP: Vector2 = Vector2(0.45, 0.8)   ## guard up and facing before the first blow
const FACING_OK: float = 0.6             ## rad (~35°): only strike when roughly facing them
const FIGHT_TURN: float = 10.0           ## face_toward weight per second while fighting (rate-capped)
const BRAWL_GIVE_UP: float = 2.5         ## s with the target out of reach (got away): the brawl ends
const GLARE_SECONDS: Vector2 = Vector2(0.9, 1.5)  ## disengage: hold ground, glaring, before pacing off
## De-escalation (colony first: fights are rare). Before a fist fight the
## target may back down, or a friend nearby may talk them out of it; during
## one, a brave friend of either may walk over and pull them apart.
const TALK_DOWN_RANGE: float = 8.0
const PEACEMAKER_RANGE: float = 10.0
const PEACEMAKER_CHANCE: float = 0.35    ## per second, per fight, until someone steps in

var _phase: Phase = Phase.START
var _timer: float = 0.0
var _bark_timer: float = 0.0
var _sabotage_done: int = 0
var _sabotage_target: Node3D = null
var _sabotage_kind: String = ""
var _leaning: bool = false
var _spot: Dictionary = {}
var _will_attack: bool = false
var _brawl: bool = false
var _weapon = null   ## WeaponItem (untyped: the weapon script has no class_name)
var _attack_left: float = 0.0
var _swing_gap: float = 0.0
var _squared: bool = false
var _combo: int = 0
var _out_of_reach: float = 0.0
var _peace_check: float = 0.0
var _peacemaker_called: bool = false

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
		_will_attack = NPCCrashOut.attack_enabled and t != null and _escalated(npc)
		## Punched first: they punch back.
		_brawl = not _will_attack and NPCCrashOut.attack_enabled and t != null \
			and (_hatred(npc) <= BRAWL_BELOW or npc.combat.attacked_by == npc.crash.target_id)
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
				_start_attack_or_sabotage(npc)
				return
			npc.set_nav_target(t.global_position)
			npc.nav_steer(delta)
			if NPCItemUser.flat_distance(npc.global_position, t.global_position) < 2.2:
				_to(Phase.RANT)
				_timer = -randf_range(RANT_SECONDS.x, RANT_SECONDS.y) * (0.5 if _will_attack or _brawl else 1.0)
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
				_start_attack_or_sabotage(npc)
		Phase.SABOTAGE:
			_tick_sabotage(npc, delta)
		Phase.ARM:
			_tick_arm(npc, delta)
		Phase.ATTACK:
			_tick_attack(npc, delta)
		Phase.GLARE:
			## Disengaging: hold ground and stare them down, then storm off.
			var t: Node3D = npc.crash.target_node()
			npc.halt_movement(delta)
			if t != null:
				npc.face_toward(t.global_position, minf(FIGHT_TURN * delta, 0.99))
			if _timer >= 0.0:
				_to(Phase.PACE)
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
	npc.combat.rushing = false
	npc.combat.attacking_id = ""
	npc.combat.put_fists_away()
	if _weapon != null and is_instance_valid(_weapon):
		if _weapon.has_method("set_aiming"):
			_weapon.set_aiming(false)
		npc.combat.unwatch_weapon(_weapon)
		if npc.held_item == _weapon:
			NPCItemUser.drop_held(npc)   ## the rage passes; the weapon ends up on the floor
		NPCItemUser.release_item(_weapon)
	_weapon = null
	if _leaning:
		var model: Node = npc.get_node_or_null("CharacterModel")
		if model != null:
			model.end_lean()
		npc.request_stand_at(npc.global_position)
		_leaning = false
	_sabotage_target = null

func attention_target(npc: NPC) -> Node3D:
	return npc.crash.target_node() if _phase in [Phase.APPROACH, Phase.RANT, Phase.ATTACK, Phase.GLARE] else null

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

## Combat hook kept for the RANT phase: attacking itself is its own phase.
func _attack(_npc: NPC, _target: Node3D) -> void:
	pass

# ─── Attacking (NPCCombat) ──────────────────────────────────────────────────
## Rant → attack only once it has escalated: they've crashed out before, the
## hatred runs very deep, or the target hit them first.
func _escalated(npc: NPC) -> bool:
	var id: String = npc.crash.target_id
	var hit_first: bool = npc.combat.attacked_by == id
	return npc.crash.count >= 2 or _hatred(npc) <= ESCALATE_BELOW or (hit_first and npc.combat.last_hit_kind != "punch")

## Relationship plus half the grudge toward the target (lower = worse).
func _hatred(npc: NPC) -> float:
	var id: String = npc.crash.target_id
	return npc.get_relationship(id) + npc.bonds.grudge_against(id) * 0.5

func _start_attack_or_sabotage(npc: NPC) -> void:
	if npc.crash.target_node() == null or not (_will_attack or _brawl):
		_to(Phase.SABOTAGE if _sabotage_done < MAX_SABOTAGE else Phase.PACE)
		return
	if _brawl:
		var punched_first: bool = npc.combat.attacked_by == npc.crash.target_id and npc.combat.last_hit_kind in ["punch", "fists"]
		var held_back: String = _held_back(npc, punched_first)
		if held_back != "":
			npc.log_event("crash", held_back)
			_brawl = false
			_to(Phase.SABOTAGE if _sabotage_done < MAX_SABOTAGE else Phase.PACE)
			return
	npc.combat.attacking_id = npc.crash.target_id
	NPCCombat.last_fight_hours = NPCClock.now()
	if _brawl:
		## A fist fight: no weapon, shorter, and it stops short of killing.
		_attack_left = randf_range(BRAWL_SECONDS.x, BRAWL_SECONDS.y)
		_weapon = null
		_begin_attack(npc)
		return
	_attack_left = randf_range(ATTACK_SECONDS.x, ATTACK_SECONDS.y)
	_weapon = npc.held_item if npc.held_item != null and "weapon_kind" in npc.held_item else _find_weapon(npc)
	if _weapon != null and npc.held_item != _weapon:
		NPCItemUser.claim_item(_weapon, npc)
		npc.set_nav_target(_weapon.global_position)
		_to(Phase.ARM)
	else:
		_begin_attack(npc)

## The nearest loose weapon they can get to.
func _find_weapon(npc: NPC) -> RigidBody3D:
	var best: RigidBody3D = null
	var best_d: float = WEAPON_SEARCH
	for it: Node in npc.get_tree().get_nodes_in_group("inventory_item"):
		if not (it is RigidBody3D) or not ("weapon_kind" in it) or it.is_in_group("shelved"):
			continue
		if ("is_held" in it and it.is_held) or NPCItemUser.is_claimed_by_other(it, npc):
			continue
		var d: float = NPCItemUser.flat_distance(npc.global_position, (it as Node3D).global_position)
		if d < best_d and NPCItemUser.is_reachable(npc, (it as Node3D).global_position, 1.4):
			best_d = d
			best = it
	return best

func _tick_arm(npc: NPC, delta: float) -> void:
	if _weapon == null or not is_instance_valid(_weapon) or ("is_held" in _weapon and _weapon.is_held) or _timer > APPROACH_TIMEOUT:
		_weapon = null
		_begin_attack(npc)   ## someone else got it — fists, then
		return
	npc.combat.rushing = true
	npc.nav_steer(delta)
	if NPCItemUser.in_reach(npc, _weapon.global_position, NPCItemUser.PICKUP_RANGE):
		if NPCItemUser.grab_loose(npc, _weapon):
			npc.log_event("crash", "Grabbed a %s" % NPCCombat.weapon_name(String(_weapon.weapon_kind)))
		else:
			_weapon = null
		_begin_attack(npc)

func _begin_attack(npc: NPC) -> void:
	var t: Node3D = npc.crash.target_node()
	if _weapon != null and npc.held_item == _weapon:
		_weapon.set_aiming(true)
		npc.combat.watch_weapon(_weapon)
	else:
		_weapon = null
		npc.combat.raise_fists()
	var who: String = "you" if npc.crash.target_id == "player" else String(t.get("npc_name")) if t != null else "someone"
	npc.bark_event("attack")
	_squared = false
	_combo = 0
	_out_of_reach = 0.0
	_peace_check = 1.0
	_peacemaker_called = false
	npc.combat.escalate = false
	npc.combat.separated = false
	if _brawl:
		npc.log_event("crash", "Started a fist fight with %s" % who)
	else:
		npc.log_event("crash", "Attacked %s%s" % [who, " with a %s" % NPCCombat.weapon_name(String(_weapon.weapon_kind)) if _weapon != null else ""])
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.CRITICAL,
		("%s is fighting %s!" if _brawl else "%s is attacking %s!") % [npc.npc_name, who])
	_to(Phase.ATTACK)

func _attack_range() -> float:
	if _weapon == null:
		return NPCCombat.FIST_REACH
	if _weapon.is_firearm():
		return GUN_RANGE if _weapon.ammo > 0 else _weapon.whip_reach
	return _weapon.reach

func _tick_attack(npc: NPC, delta: float) -> void:
	var t: Node3D = npc.crash.target_node()
	_attack_left -= delta
	var target_down: bool = t == null or (t.has_method("is_dead") and t.is_dead())
	var who: String = "you" if npc.crash.target_id == "player" else String(t.get("npc_name")) if t != null else "them"
	if _brawl and not target_down and NPCCombat.health_of(t) <= BRAWL_STOP_HEALTH:
		target_down = true   ## beaten down: a brawl stops there
		npc.log_event("crash", "Beat %s down" % who)
	## Someone got between them.
	if npc.combat.separated:
		npc.combat.separated = false
		npc.log_event("crash", "%s pulled me off %s" % [npc.combat.separated_by, who])
		_disengage(npc)
		return
	if _brawl and not _peacemaker_called:
		_peace_check -= delta
		if _peace_check <= 0.0:
			_peace_check = 1.0
			_call_peacemaker(npc, t)
	## The target answered a fist fight with a real weapon: now it's serious.
	if _brawl and npc.combat.escalate:
		npc.combat.escalate = false
		_brawl = false
		_will_attack = true
		npc.combat.put_fists_away()
		npc.log_event("crash", "Went for a weapon")
		_start_attack_or_sabotage(npc)
		return
	if target_down or _attack_left <= 0.0 or (_brawl and _out_of_reach > BRAWL_GIVE_UP):
		_disengage(npc)
		return
	var d: float = NPCItemUser.flat_distance(npc.global_position, t.global_position)
	var reach: float = _attack_range()
	var gun: bool = _weapon != null and is_instance_valid(_weapon) and _weapon.is_firearm() and _weapon.ammo > 0
	_out_of_reach = _out_of_reach + delta if d > reach + 1.5 else 0.0
	## Getting there: pathfind from afar; up close walk straight in and hold
	## a fighting distance (a gun just stops once in range).
	if (gun and d > reach * 0.9) or (not gun and d > maxf(CLOSE_IN_AT, reach + 0.4)):
		npc.combat.rushing = d > 4.0
		npc.set_nav_target(t.global_position)
		npc.nav_steer(delta)
		_squared = false
		return
	npc.combat.rushing = false
	if gun:
		npc.halt_movement(delta)
	else:
		npc.steer_direct(t.global_position, maxf(reach * 0.8, MIN_SPACING), delta)
	npc.face_toward(t.global_position, minf(FIGHT_TURN * delta, 0.99))
	if not _squared:
		_squared = true   ## guard up, sizing them up, before the first blow
		_swing_gap = maxf(_swing_gap, randf_range(SQUARE_UP.x, SQUARE_UP.y))
	_swing_gap -= delta
	if _swing_gap > 0.0 or d > reach * 0.95 or absf(_facing_error(npc, t.global_position)) > FACING_OK:
		return
	if _bark_timer <= 0.0:
		_bark_timer = randf_range(4.0, 7.0)
		npc.bark_event("attack")
	var aim_at: Vector3 = t.global_position + Vector3.UP * 0.35
	var dir: Vector3 = Vector3(t.global_position.x - npc.global_position.x, 0.0, t.global_position.z - npc.global_position.z)
	if _weapon != null and is_instance_valid(_weapon) and npc.held_item == _weapon:
		## Melee swings from the body toward the target (the held weapon sits
		## ahead of the body, so aiming from it goes sideways up close); guns
		## aim from the weapon, with shaky hands (some shots miss).
		if gun:
			dir = (aim_at - _weapon.global_position).normalized().rotated(Vector3.UP, randf_range(-0.07, 0.07))
		if _weapon.try_attack(dir):
			_swing_gap = randf_range(0.5, 1.1)   ## wind-up between blows; gives the victim a chance
	else:
		## Fists (weapons session's Fists node): a jab, usually followed by
		## a cross, then a breather so the other one gets a chance.
		_weapon = null
		var fists: Node = npc.combat.raise_fists()
		if fists != null and fists.try_attack(dir):
			_combo += 1
			var follow_up: bool = _combo % 2 == 1 and randf() < 0.75
			_swing_gap = randf_range(0.3, 0.42) if follow_up else randf_range(0.9, 1.5)

## Stop fighting: lower the guard, then a moment's glare before storming off.
func _disengage(npc: NPC) -> void:
	npc.combat.rushing = false
	npc.combat.attacking_id = ""
	npc.combat.put_fists_away()
	if _weapon != null and is_instance_valid(_weapon):
		_weapon.set_aiming(false)
	_to(Phase.GLARE)
	_timer = -randf_range(GLARE_SECONDS.x, GLARE_SECONDS.y)
	npc.bark_event("seething")

## Why this fist fight doesn't happen ("" = it does): the colony just had
## one, the target backs down, or a friend talks them out of it. Being
## punched first overrides all of it (they defend themselves).
func _held_back(npc: NPC, punched_first: bool) -> String:
	if punched_first:
		return ""
	if NPCClock.now() - NPCCombat.last_fight_hours < NPCCombat.FIGHT_COOLDOWN_H:
		return "Held back — nobody wants another fight"
	var t: Node3D = npc.crash.target_node()
	if t is NPC and not (t as NPC).crash.active():
		var tn: NPC = t as NPC
		var back_down: float = 0.3 * (1.0 - tn._trait("neuroticism")) + (0.2 if tn.social.fear > 40.0 else 0.0)
		if randf() < back_down:
			tn.log_event("crash", "Backed down from a fight with %s" % npc.npc_name)
			return "%s backed down" % tn.npc_name
	for o: Node in npc.get_tree().get_nodes_in_group("npc"):
		var on: NPC = o as NPC
		if on == null or on == npc or on == t or not _free_to_act(on):
			continue
		if on.global_position.distance_to(npc.global_position) > TALK_DOWN_RANGE or not on._can_see(npc):
			continue
		if on.get_relationship(npc.npc_id) >= 40.0 and npc.get_relationship(on.npc_id) >= 30.0 and randf() < 0.5:
			on.log_event("bond", "Talked %s out of a fight" % npc.npc_name)
			npc.bonds.relate(on.npc_id, 4.0, "talked me down")
			return "%s talked me down" % on.npc_name
	return ""

## Someone brave who cares about one of them walks over to stop it.
func _call_peacemaker(npc: NPC, victim: Node3D) -> void:
	var best: NPC = null
	var best_d: float = PEACEMAKER_RANGE
	var victim_id: String = NPCCombat.id_of(victim)
	for o: Node in npc.get_tree().get_nodes_in_group("npc"):
		var on: NPC = o as NPC
		if on == null or on == npc or on == victim or not _free_to_act(on) or on.combat.break_up_id != "":
			continue
		var d: float = on.global_position.distance_to(npc.global_position)
		if d > best_d or not on._can_see(npc):
			continue
		var nerve: float = on._trait("resilience") - on.social.fear / 200.0
		var care: float = maxf(on.get_relationship(npc.npc_id), on.get_relationship(victim_id) if victim_id != "" else -100.0)
		if nerve >= 0.45 and care >= 25.0:
			best = on
			best_d = d
	if best != null and randf() < PEACEMAKER_CHANCE:
		_peacemaker_called = true
		best.combat.break_up_id = npc.npc_id
		best.log_event("bond", "Stepping in between %s and %s" % [npc.npc_name, victim.get("npc_name") if victim is NPC else "you"])

## Up and about, not caught up in something of their own.
static func _free_to_act(n: NPC) -> bool:
	return not n.is_dead() and not n.crash.active() and not n.combat.is_fleeing() and not n.is_passed_out() \
		and not (n.brain != null and n.brain.is_sleeping())

## Signed yaw from where they face to `pos` (radians).
func _facing_error(npc: NPC, pos: Vector3) -> float:
	var d: Vector3 = pos - npc.global_position
	return angle_difference(npc.rotation.y, atan2(-d.x, -d.z))

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
