extends NPCActivity
class_name TalkActivity
## NPC↔NPC Talking (Aug 2026). One reusable instance lives in
## _candidates (constructed with defaults — partner=null,
## is_initiator=true) for the normal scored/organic path; a SEPARATE
## one-shot instance gets force_command()'d onto the partner side
## (partner=initiator, is_initiator=false) via start_talk_session().
## No travel phase — only ever matched between NPCs already within
## TALK_RANGE, so both lock in place immediately. Non-interruptible
## once a partner's actually locked in, same "commit once started"
## reasoning as every other multi-step activity in this file.
## FUTURE WORK: relationship-based random conversation OUTCOMES —
## deliberately not built yet. This pass is groundwork only: both
## NPCs occupied, facing each other, logged.
const SESSION_MIN: float = 8.0    ## seconds, real-time — a quick social beat, not a game-hours-scale session like Relaxing
const SESSION_MAX: float = 20.0

var _partner: Node = null
var _elapsed: float = 0.0
var _duration: float = 0.0
var _is_initiator: bool = true
var _self_npc: NPC = null   ## interruptible() has no npc parameter in this codebase's activity interface — stored here at enter() so it can check this NPC's own needs

func _init(partner: Node = null, is_initiator: bool = true) -> void:
	_partner = partner
	_is_initiator = is_initiator

func label() -> String:
	return "Talking" if _partner != null else "Idle"

func score(npc: NPC) -> float:
	if not _is_initiator:
		return 0.0
	if npc.has_method("is_talk_on_cooldown") and npc.is_talk_on_cooldown():
		return 0.0
	var partner: Node = npc.find_talk_partner()
	if partner == null:
		return 0.0
	var mult: float = npc.get_talk_score_mult(partner) if npc.has_method("get_talk_score_mult") else 1.0
	return NPC.TALK_BASE_SCORE * npc.get_work_ethic_passive_mult() * mult

func interruptible() -> bool:
	if _partner == null:
		return true   ## brief instant before a partner locks in
	## Needs take priority over an ongoing conversation — same 55%
	## threshold Eat/DrinkActivity themselves auto-trigger on, so
	## "hungry enough to interrupt" means the same thing everywhere.
	if _self_npc != null and (float(_self_npc.hunger) < 55.0 or float(_self_npc.thirst) < 55.0):
		return true
	return false

func enter(npc: NPC) -> void:
	_self_npc = npc
	if _is_initiator:
		_partner = npc.find_talk_partner()
		if _partner == null:
			return
		if not _partner.has_method("start_talk_session") or not _partner.start_talk_session(npc):
			_partner = null
			return
		_duration = randf_range(SESSION_MIN, SESSION_MAX)
		_elapsed = 0.0
	if _partner != null and is_instance_valid(_partner):
		npc.lock_movement()
		var target_pos: Vector3 = (_partner as Node3D).global_position
		target_pos.y = npc.global_position.y
		npc.look_at(target_pos, Vector3.UP)

func tick(npc: NPC, delta: float) -> void:
	if _partner == null or not is_instance_valid(_partner):
		_partner = null
		return
	npc.halt_movement(delta)
	if not _is_initiator:
		return   ## partner just waits — end_talk_if_talking() (called via the initiator's own end-of-session) clears _partner externally
	_elapsed += delta
	if _elapsed >= _duration:
		if _partner.has_method("end_talk_session"):
			_partner.end_talk_session(true)
		npc.log_action("Talked to %s" % _partner.npc_name)
		if npc.has_method("apply_talk_relationship_swing") and ("npc_id" in _partner):
			npc.apply_talk_relationship_swing(_partner.npc_id, _partner.npc_name)
		_partner = null

func done(npc: NPC) -> bool:
	return _partner == null

func exit(npc: NPC) -> void:
	if _partner != null and is_instance_valid(_partner) and _is_initiator:
		## interrupted some other way (including a low-needs abort) —
		## don't leave the partner stuck waiting forever; natural=false
		## since this path only ever fires when the conversation did
		## NOT reach its normal duration-elapsed ending (that path
		## already nulls _partner before exit() runs, so this branch
		## is exclusively the "cut short" case).
		if _partner.has_method("end_talk_session"):
			_partner.end_talk_session(false)
	if _duration > 0.0 and npc.has_method("start_talk_cooldown"):
		npc.start_talk_cooldown()   ## covers both natural completion and any interrupt/abort path
	_partner = null