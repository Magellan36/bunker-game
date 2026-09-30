extends RefCounted
class_name NPCCombat
## NPCCombat.gd (Sep 2026) — residents and violence: taking hits, dying, and
## (during a hostile crash-out) attacking with a weapon.
##
## Contract with the weapons session: docs/systems/weapons/HANDOFF.md.
## WeaponItem calls NPC.receive_weapon_hit(context) with
## {damage, position, direction, kind, source, collider}; everything a hit
## MEANS for a resident is decided here:
##   - health loss, and an injury by weapon type where it landed (head,
##     torso, arm, leg from the hit height): gunshots leave an open wound and
##     bleeding, blades bleed, blunt weapons can fracture a limb;
##   - shock (morale), fear, a large relationship hit and a named memory
##     toward the attacker; everyone who sees it reacts too;
##   - fight or flight: someone who already hates the attacker (or is
##     crashing out at them) fights back; everyone else runs (FleeActivity);
##   - at 0 health they die (NPC.is_dead() plays the shared dying clip).
##
## Hits on the PLAYER from a resident's weapon: the player has no
## receive_weapon_hit() (the player/medical area owns that), so a
## resident's weapon reports its hits here (hit_resolved) and
## apply_player_hit() deals the damage through PlayerStats health (0 = game
## over, via MainWorld) plus a PlayerMedical injury. If the player ever gets
## its own receive_weapon_hit(), this bridge steps aside automatically.

const FLEE_SECONDS: float = 7.0
const REPEAT_HIT_WINDOW_H: float = 1.0      ## further hits in this window cost less relationship
const WITNESS_RANGE: float = 14.0
const FIST_REACH: float = 1.1               ## Fists.reach (weapons session)
const FISTS_SCRIPT: GDScript = preload("res://scripts/weapons/Fists.gd")
## Deaths from neglect (starvation, dehydration, untreated bleeding) —
## the same rule as violence: health at 0 is death.
const NEGLECT_DEATHS: bool = true

var dead: bool = false
var death_cause: String = ""
var killed_by: String = ""                  ## "player", an npc_id, or ""
var attacked_by: String = ""                ## last attacker (fight-back/flee target)
var last_hit_kind: String = ""              ## "punch" hits start fist fights, not lethal ones
var flee_from: String = ""                  ## who they're running from (an attacker, or a fight nearby)
var escalate: bool = false                  ## mid fist fight, the target used a real weapon (CrashOutActivity)
var break_up_id: String = ""                ## the brawler this resident is stepping in to stop (BreakUpFightActivity)
var separated: bool = false                 ## pulled off their target by a peacemaker (CrashOutActivity disengages)
var separated_by: String = ""
var _shun_logged_at: float = -100.0
var debug_phase: String = ""               ## CrashOutActivity phase name (NPCCombatDebug overlay)

## Colony-scale rarity: after a fight, the next fist fight within this many
## game hours stays a shouting match (everyone's shaken; nobody wants
## another). Escalated (weapon) attacks aren't held back by it.
const FIGHT_COOLDOWN_H: float = 8.0
static var last_fight_hours: float = -100.0
## Aftermath: they won't work within SHUN_RANGE of someone who attacked
## them in the last SHUN_HOURS (they find something else to do).
const SHUN_HOURS: float = 48.0
const SHUN_RANGE: float = 5.0
const SHUN_WORK_MULT: float = 0.3
var flee_until_msec: int = 0
var rushing: bool = false                   ## charging at someone (CrashOutActivity) — runs
var attacking_id: String = ""               ## who they're arming for / attacking right now (CrashOutActivity)
var last_rescued_hours: float = -100.0
var _last_hit_at: Dictionary = {}           ## attacker id -> game hour
var _fists: Node = null                     ## Fists, created on first use as a child of the NPC

## Rescue events (NPC.on_rescued_by_player): the player stepping in while
## a resident is being attacked, or treating one who is at death's door.
## One rescue credit per RESCUE_REPEAT_H, so a long fight doesn't stack.
const RESCUE_HEALTH: float = 25.0
const PUNCH_FLOOR: float = 5.0              ## punches never take health below this
const RESCUE_REPEAT_H: float = 12.0

var _npc: NPC = null

func setup(npc: NPC) -> void:
	_npc = npc

static func weapon_name(kind: String) -> String:
	return {"revolver": "revolver", "pistol_whip": "pistol", "knife": "knife", "hatchet": "hatchet",
		"pipe": "pipe", "bat": "bat", "crowbar": "crowbar", "fists": "fists", "punch": "fist"}.get(kind, "weapon")

static func id_of(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if node.is_in_group("player"):
		return "player"
	return String(node.get("npc_id")) if "npc_id" in node else ""

func is_fleeing() -> bool:
	return not dead and Time.get_ticks_msec() < flee_until_msec

## Current health of a resident or the player (100 if unknown).
static func health_of(n: Node) -> float:
	if n is NPC:
		return (n as NPC).health
	if n != null and n.is_in_group("player"):
		var stats: Node = n.get_tree().get_first_node_in_group("player_stats")
		return float(stats.health) if stats != null else 100.0
	return 100.0

## Fists (scripts/weapons/Fists.gd, weapons session): same API as a weapon;
## the animation session plays the punch clips off its signals.
func raise_fists() -> Node:
	if _fists == null or not is_instance_valid(_fists):
		_fists = FISTS_SCRIPT.new()
		_npc.add_child(_fists)
		watch_weapon(_fists)
	_fists.set_aiming(true)
	return _fists

func put_fists_away() -> void:
	if _fists != null and is_instance_valid(_fists):
		_fists.set_aiming(false)

## Hit reaction clip on the victim's model (animation session's API; a
## no-op until the model has it). Residents' model is "CharacterModel",
## the player's "PlayerModel".
static func play_hit_reaction(body: Node, ctx: Dictionary) -> void:
	if body == null or not is_instance_valid(body):
		return
	for path: String in ["CharacterModel", "PlayerModel"]:
		var model: Node = body.get_node_or_null(path)
		if model != null and model.has_method("play_hit_reaction"):
			model.play_hit_reaction(ctx)
			return

func attacker_node() -> Node3D:
	return _node_of(attacked_by)

## Who they're running from (FleeActivity).
func threat_node() -> Node3D:
	return _node_of(flee_from if flee_from != "" else attacked_by)

func _node_of(id: String) -> Node3D:
	if id == "player":
		return _npc.get_tree().get_first_node_in_group("player") as Node3D
	return _npc.crash._find(id) if id != "" else null

# ─── Taking a hit ───────────────────────────────────────────────────────────
func receive_hit(ctx: Dictionary) -> void:
	if dead:
		return
	var dmg: float = maxf(0.0, float(ctx.get("damage", 0.0)))
	var kind: String = String(ctx.get("kind", ""))
	var src: Node = ctx.get("source") as Node
	var src_id: String = id_of(src)
	var hit_pos: Vector3 = ctx.get("position", _npc.global_position + Vector3.UP)
	var part: int = _body_part_at(hit_pos)
	## The player hitting someone who is attacking another resident is
	## stepping in, not starting a fight.
	var defended: NPC = null
	if src_id == "player" and attacking_id != "" and attacking_id != "player":
		defended = _npc.crash._find(attacking_id)
		if defended != null and defended.is_dead():
			defended = null
	## Fists hurt; they don't kill (a beating leaves someone on the floor
	## needing care, not dead — weapons are what kill).
	var punch: bool = kind in ["punch", "fists"]
	if punch:
		_npc.health = maxf(minf(_npc.health, PUNCH_FLOOR), _npc.health - dmg)
	else:
		_npc.health = maxf(0.0, _npc.health - dmg)
	var injury: String = _injure(kind, part, dmg)
	## Knocked back a little: a jab rocks them, a bat sends them stumbling.
	var dir: Vector3 = ctx.get("direction", Vector3.ZERO)
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		_npc.velocity += dir.normalized() * clampf(dmg * 0.12, 0.4, 2.5)
	if not punch and src_id != "" and _npc.crash.active() and _npc.crash.target_id == src_id:
		escalate = true
		NPCCombatDebug.trace(_npc, "target hit back with a real weapon (%s) -> escalate flag" % kind)
	## Fight or flight is decided by how they felt about the attacker BEFORE this.
	var prior_hate: float = (_npc.get_relationship(src_id) + _npc.bonds.grudge_against(src_id) * 0.5) if src_id != "" else 0.0
	var who: String = "You" if src_id == "player" else (_npc.bonds.display_name(src_id) if src_id != "" else "Someone")
	_npc.log_event("hurt", "%s hit me with a %s (−%d health%s)" % [who, weapon_name(kind), int(round(dmg)), ", " + injury if injury != "" else ""])
	_npc.morale_sys.note_shock(0.4)
	NPCCombatDebug.trace(_npc, "hit by %s: %s %.0f dmg at %s -> health %.0f%s%s" % [src_id if src_id != "" else "?", kind, dmg,
		MedicalCondition.body_part_label(part), _npc.health, ", " + injury if injury != "" else "",
		" (player stepping in for %s)" % defended.npc_name if defended != null else ""])
	if src_id != "":
		attacked_by = src_id
		last_hit_kind = kind
		var now: float = NPCClock.now()
		var repeat: bool = now - float(_last_hit_at.get(src_id, -99.0)) < REPEAT_HIT_WINDOW_H
		_last_hit_at[src_id] = now
		if repeat:
			_npc.bonds.relate(src_id, -8.0, "kept hitting me")
		else:
			_npc.bonds.relate(src_id, -30.0, "attacked me with a %s" % weapon_name(kind),
				"%s attacked me with a %s" % [who, weapon_name(kind)], true)
		if src_id == "player":
			_npc.social.fear = minf(100.0, _npc.social.fear + 25.0)
		## Bystanders don't blame the player for stopping an attack (only
		## those who care about the attacker still mind), and the one being
		## attacked is grateful rather than a witness.
		_witnesses_react(src_id, src, "attacked %s" % _npc.npc_name, 0.0 if defended != null else -4.0, 12.0, 0.15, defended)
		if defended == null:   ## stepping in to stop a fight isn't a new threat
			_bystanders_clear_out(src_id, src, punch)
		if defended != null:
			defended.combat.credit_rescue("stopped %s attacking me" % _npc.npc_name)
	if _npc.health <= 0.0:
		die(kind, src_id)
		return
	_npc.bark_event("hurt")
	_react(src_id, prior_hate)

## Fight or flight.
func _react(src_id: String, hate: float) -> void:
	if src_id == "" or _npc.crash.active():
		return   ## mid crash-out: it carries on (a hostile one may now aim at them)
	var nerve: float = _npc._trait("resilience") - _npc.social.fear / 200.0
	NPCCombatDebug.trace(_npc, "fight or flight vs %s: prior hate %.0f (fight if <= %.0f), nerve %.2f (> 0.35), cowed %s" % [
		src_id, hate, NPCCrashOut.HOSTILE_AT, nerve, _npc.social.is_cowed()])
	if hate <= NPCCrashOut.HOSTILE_AT and nerve > 0.35 and not _npc.social.is_cowed():
		_npc.bark_event("fight_back")
		_npc.log_event("crash", "Fought back")
		_npc.crash.target_id = src_id
		_npc.crash.begin(NPCCrashOut.Mode.HOSTILE)
		return
	flee_from = src_id
	flee_until_msec = Time.get_ticks_msec() + int(FLEE_SECONDS * 1000.0)
	_npc.bark_event("flee")
	if _npc.brain != null:
		_npc.brain.stop_current()

## People near a fight get out of the way: anyone right beside a brawl
## steps clear; a weapon attack sends the faint-hearted running (the
## brave stay put and just react). Only bystanders who aren't busy with
## something they can't drop (a crash-out, sleeping, already running).
const CLEAR_OUT_BRAWL: float = 1.8
const CLEAR_OUT_WEAPON: float = 6.0
func _bystanders_clear_out(actor_id: String, actor: Node, punch: bool) -> void:
	if actor == null or not (actor is Node3D):
		return
	var radius: float = CLEAR_OUT_BRAWL if punch else CLEAR_OUT_WEAPON
	for w: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if not (w is NPC) or w == _npc or w == actor:
			continue
		var wn: NPC = w as NPC
		if wn.combat.is_fleeing() or wn.crash.active() or wn.is_passed_out() or (wn.brain != null and wn.brain.is_sleeping()):
			continue
		if wn.global_position.distance_to(_npc.global_position) > radius:
			continue
		var nerve: float = wn._trait("resilience") - wn.social.fear / 200.0
		if not punch and nerve > 0.55:
			continue
		NPCCombatDebug.trace(wn, "clearing out of the way of %s (%s, nerve %.2f)" % [actor_id, "brawl" if punch else "weapon", nerve])
		wn.combat.flee_from = actor_id
		wn.combat.flee_until_msec = Time.get_ticks_msec() + int((1.6 if punch else 4.5) * 1000.0)
		if wn.brain != null and wn.brain.is_current_interruptible():
			wn.brain.stop_current()

## A rescue by the player: false (and nothing happens) when they were
## already credited with one in the last RESCUE_REPEAT_H game hours.
func credit_rescue(what: String) -> bool:
	if dead or NPCClock.now() - last_rescued_hours < RESCUE_REPEAT_H:
		NPCCombatDebug.trace(_npc, "rescue '%s' NOT credited (already rescued %.1fh ago, window %.0fh)" % [what, NPCClock.now() - last_rescued_hours, RESCUE_REPEAT_H])
		return false
	NPCCombatDebug.trace(_npc, "RESCUE credited: '%s' (+20 player)" % what)
	last_rescued_hours = NPCClock.now()
	_npc.log_event("care", "You %s" % what)
	_npc.bark_event("thanks")
	_npc.on_rescued_by_player(what)
	return true

## A resident who attacked this one recently (a named memory of it) and
## isn't forgiven yet.
func shuns(other: NPC) -> bool:
	if other.is_dead() or _npc.get_relationship(other.npc_id) > -20.0:
		return false
	var now: float = NPCClock.now()
	for m: Dictionary in _npc.bonds.get_memories(other.npc_id):
		if float(m.get("amount", 0.0)) <= -20.0 and now - float(m.get("stamp", -999.0)) < SHUN_HOURS \
				and String(m.get("text", "")).contains("attacked me"):
			return true
	return false

## Work scores ×SHUN_WORK_MULT while someone they shun is right there.
func shun_work_mult() -> float:
	for o: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if o == _npc or not (o is NPC):
			continue
		if NPCItemUser.flat_distance(o.global_position, _npc.global_position) > SHUN_RANGE or not shuns(o as NPC):
			continue
		if NPCClock.now() - _shun_logged_at > 2.0:
			_shun_logged_at = NPCClock.now()
			NPCCombatDebug.trace(_npc, "shuns %s within %.0f m -> work scores x%.1f" % [(o as NPC).npc_name, SHUN_RANGE, SHUN_WORK_MULT])
			_npc.log_event("bond", "Won't work next to %s" % (o as NPC).npc_name)
		return SHUN_WORK_MULT
	return 1.0

## At death's door: low enough health that treating them is saving them.
func is_critical() -> bool:
	return not dead and (_npc.health <= RESCUE_HEALTH or _npc.is_passed_out())

## Head / torso / arm / leg from where the blow landed on the body.
func _body_part_at(pos: Vector3) -> int:
	var local: Vector3 = _npc.global_transform.affine_inverse() * pos
	var up: float = pos.y - NPCStuckRecovery.FLOOR_Y   ## height above the floor
	if up > 1.5:
		return MedicalCondition.BodyPart.HEAD
	if up < 0.85:
		return MedicalCondition.BodyPart.LEFT_LEG if local.x < 0.0 else MedicalCondition.BodyPart.RIGHT_LEG
	if absf(local.x) > 0.22:
		return MedicalCondition.BodyPart.LEFT_ARM if local.x < 0.0 else MedicalCondition.BodyPart.RIGHT_ARM
	return MedicalCondition.BodyPart.TORSO

## Returns a short description for the log ("" if just bruised).
func _injure(kind: String, part: int, dmg: float) -> String:
	var med: NPCMedical = _npc.medical
	var where: String = MedicalCondition.body_part_label(part).to_lower()
	if med == null:
		return ""
	match kind:
		"revolver":
			med.spawn_open_wound(part)
			med.spawn_bleeding(part)
			return "shot in the %s" % where
		"knife", "hatchet":
			med.spawn_bleeding(part)
			if kind == "hatchet":
				med.spawn_open_wound(part)
			return "cut on the %s" % where
	## Blunt: a hard blow can break a limb.
	var limb: bool = part != MedicalCondition.BodyPart.HEAD and part != MedicalCondition.BodyPart.TORSO
	if limb and randf() < clampf((dmg - 10.0) / 30.0, 0.0, 0.7):
		med.spawn_fractured(part)
		return "fractured %s" % where
	return ""

## Everyone who sees violence reacts: a little against the attacker even as
## a bystander, much more if they cared about the victim; the player being
## violent also makes people afraid (which, like threats, buys compliance).
func _witnesses_react(actor_id: String, actor: Node, what: String, base: float, care_mult: float, shock: float, skip: NPC = null) -> void:
	for w: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if not (w is NPC) or w == _npc or w == skip or (w as NPC).npc_id == actor_id:
			continue
		var wn: NPC = w as NPC
		if wn.global_position.distance_to(_npc.global_position) > WITNESS_RANGE or not wn._can_see(_npc):
			continue
		var care: float = maxf(0.0, wn.get_relationship(_npc.npc_id) / 100.0)
		wn.bonds.relate(actor_id, base - care_mult * care, "%s in front of me" % what)
		wn.morale_sys.note_shock(shock)
		if actor_id == "player":
			wn.social.fear = minf(100.0, wn.social.fear + 10.0)

# ─── Death ──────────────────────────────────────────────────────────────────
func die(cause: String, killer_id: String = "", quiet: bool = false) -> void:
	if dead:
		return
	dead = true
	NPCCombatDebug.trace(_npc, "DIED: %s (killer %s)" % [cause, killer_id if killer_id != "" else "-"])
	death_cause = cause
	killed_by = killer_id
	attacking_id = ""
	put_fists_away()
	if _npc.brain != null:
		_npc.brain.stop_current()
	if _npc.held_item != null:
		NPCItemUser.drop_held(_npc)
	NPCItemUser.release_all_for(_npc)
	_npc.lock_movement()
	_npc.velocity = Vector3.ZERO
	## Out of the living: every system that looks for residents uses this
	## group. MainWorld saves "npc_dead" too, so the body persists.
	_npc.remove_from_group("npc")
	_npc.add_to_group("npc_dead")
	_npc.collision_layer = 0          ## walk-through, not interactable; still stands on the floor
	if quiet:
		return   ## restoring a save: the body is simply there
	var how: String = describe_death()
	_npc.log_event("death", how)
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.CRITICAL,
		"%s is dead — %s" % [_npc.npc_name, how.to_lower()])
	## Everyone left behind: shock and grief; the killer is never forgiven.
	for w: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if not (w is NPC):
			continue
		var wn: NPC = w as NPC
		var close: float = maxf(0.0, wn.get_relationship(_npc.npc_id) / 100.0)
		var near: bool = wn.global_position.distance_to(_npc.global_position) < WITNESS_RANGE
		wn.morale_sys.note_shock(0.35 + 0.4 * close + (0.25 if near else 0.0))
		wn.log_event("mood", "%s died%s" % [_npc.npc_name, " in front of me" if near else ""])
		if near:
			wn.bark_event("horrified", _npc.npc_name)
		if killer_id != "" and killer_id != wn.npc_id:
			wn.bonds.relate(killer_id, -25.0 - 50.0 * close, "killed %s" % _npc.npc_name,
				"%s killed %s" % ["You" if killer_id == "player" else wn.bonds.display_name(killer_id), _npc.npc_name], true)
			if killer_id == "player":
				wn.social.fear = minf(100.0, wn.social.fear + (35.0 if near else 20.0))

func describe_death() -> String:
	var who: String = "you" if killed_by == "player" else (_npc.bonds.display_name(killed_by) if killed_by != "" else "")
	match death_cause:
		"starvation":
			return "Starved to death"
		"dehydration":
			return "Died of thirst"
		"injuries":
			return "Died of their injuries"
	if who != "":
		return "Killed by %s with a %s" % [who, weapon_name(death_cause)]
	return "Died"

## Called from NPC._tick_needs when health runs out without a blow.
func check_neglect_death() -> void:
	if dead or not NEGLECT_DEATHS or _npc.health > 0.0:
		return
	var cause: String = "injuries"
	if _npc.hunger <= 0.0:
		cause = "starvation"
	elif _npc.thirst <= 0.0:
		cause = "dehydration"
	die(cause, attacked_by if cause == "injuries" else "")

# ─── Hits on the player from a resident's weapon ────────────────────────────
func watch_weapon(weapon: Node) -> void:
	if weapon != null and weapon.has_signal("hit_resolved") and not weapon.is_connected("hit_resolved", _on_weapon_hit):
		weapon.connect("hit_resolved", _on_weapon_hit)

func unwatch_weapon(weapon: Node) -> void:
	if weapon != null and is_instance_valid(weapon) and weapon.has_signal("hit_resolved") and weapon.is_connected("hit_resolved", _on_weapon_hit):
		weapon.disconnect("hit_resolved", _on_weapon_hit)

func _on_weapon_hit(ctx: Dictionary) -> void:
	var n: Node = ctx.get("collider") as Node
	while n != null and not n.is_in_group("player"):
		n = n.get_parent()
	if n != null and not n.has_method("receive_weapon_hit"):
		apply_player_hit(ctx)

func apply_player_hit(ctx: Dictionary) -> void:
	var stats: Node = _npc.get_tree().get_first_node_in_group("player_stats")
	var player: Node = _npc.get_tree().get_first_node_in_group("player")
	if stats == null or player == null or ("dead" in player and player.dead):
		return
	var dmg: float = float(ctx.get("damage", 0.0))
	var kind: String = String(ctx.get("kind", "fists"))
	stats.health = maxf(0.0, float(stats.health) - dmg)
	stats.health_changed.emit(stats.health)   ## 0 → MainWorld opens the game over
	if float(stats.health) > 0.0:
		play_hit_reaction(player, ctx)
	var pm: Node = _npc.get_tree().get_first_node_in_group("player_medical")
	if pm != null and float(stats.health) > 0.0:
		var parts: Array = [MedicalCondition.BodyPart.TORSO, MedicalCondition.BodyPart.LEFT_ARM,
			MedicalCondition.BodyPart.RIGHT_ARM, MedicalCondition.BodyPart.LEFT_LEG, MedicalCondition.BodyPart.RIGHT_LEG]
		var part: int = parts.pick_random()
		if kind == "revolver" and pm.has_method("spawn_open_wound"):
			pm.spawn_open_wound(part)
			pm.spawn_bleeding(part)
		elif kind in ["knife", "hatchet"] and pm.has_method("spawn_bleeding"):
			pm.spawn_bleeding(part)
		elif not kind in ["fists", "punch"] and part != MedicalCondition.BodyPart.TORSO and randf() < 0.25 and pm.has_method("spawn_fractured"):
			pm.spawn_fractured(part)
	var camera: Camera3D = _npc.get_viewport().get_camera_3d()
	if camera != null and camera.has_method("add_trauma"):
		camera.call("add_trauma", 0.45)
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.CRITICAL,
		"%s hit you with %s!" % [_npc.npc_name, "their fists" if kind == "fists" else "a " + weapon_name(kind)])

# ─── Save / load ────────────────────────────────────────────────────────────
func to_save() -> Dictionary:
	return {"dead": dead, "cause": death_cause, "killer": killed_by, "attacker": attacked_by, "rescued": last_rescued_hours}

func from_save(d: Dictionary) -> void:
	if d.is_empty():
		return
	death_cause = String(d.get("cause", ""))
	killed_by = String(d.get("killer", ""))
	attacked_by = String(d.get("attacker", ""))
	last_rescued_hours = float(d.get("rescued", -100.0))
	if bool(d.get("dead", false)):
		## Applied once the resident is in the tree (NPC._ready → apply_loaded_death).
		_pending_dead = true

var _pending_dead: bool = false

func apply_loaded_death() -> void:
	if _pending_dead:
		_pending_dead = false
		die(death_cause, killed_by, true)
