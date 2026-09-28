extends NPCActivity
class_name TalkActivity
## TalkActivity.gd — NPC↔NPC conversation.
##
## One NPC (the initiator) wins this on a think tick and pulls the nearest
## free NPC within NPC.TALK_RANGE into its own non-initiator TalkActivity via
## start_talk_session(). Both stop and face each other. The initiator owns
## the session timer; at the end ONE shared conversation outcome is rolled
## (NPC.resolve_conversation) and applied to both participants, so a chat
## can't be "good" for one side and "bad" for the other any more.
##
## Sep 2026 fixes:
##   • If EITHER side leaves early (hunger, a command, pass-out...), the
##     other side's session ends immediately — the initiator no longer keeps
##     talking to an empty spot and then applies a relationship swing for a
##     conversation that never finished.
##   • Participants now "take turns": they face each other continuously
##     (partners can shuffle a little from avoidance) and the NPC shows
##     who is speaking via a small speech indicator (see NPC.set_speaking()).

const SESSION_MIN: float = 8.0    ## real seconds — a quick social beat
const SESSION_MAX: float = 20.0
const TURN_MIN: float = 1.4
const TURN_MAX: float = 3.2

var _partner: Node = null
var _elapsed: float = 0.0
var _duration: float = 0.0
var _is_initiator: bool = true
var _self_npc: NPC = null
var _turn_left: float = 0.0
var _speaking: bool = false
var _ended_naturally: bool = false
var _turns: int = 0
var _approaching: bool = false          ## initiator walking over to a friend
var _approach_time: float = 0.0
const APPROACH_GIVE_UP: float = 12.0
const CHAT_DISTANCE: float = 1.8

func _init(partner: Node = null, is_initiator: bool = true) -> void:
	_partner = partner
	_is_initiator = is_initiator

func attention_target(_npc: NPC) -> Node3D:
	return _partner as Node3D if _partner != null and is_instance_valid(_partner) else null

func label() -> String:
	if _partner == null or not is_instance_valid(_partner):
		return "Idle"
	if _approaching:
		return "Going to chat with %s" % String(_partner.npc_name)
	return "Chatting with %s" % String(_partner.npc_name) if ("npc_name" in _partner) else "Talking"

func get_partner() -> Node:
	return _partner if _partner != null and is_instance_valid(_partner) else null

## Ends this side of the session (called by the partner via NPC.end_talk_session()).
func end_session() -> void:
	_partner = null

func score(npc: NPC) -> float:
	if not _is_initiator:
		return 0.0
	if npc.crash.active():
		return 0.0   ## no chit-chat mid crash-out (overdrive included)
	if npc.is_talk_on_cooldown():
		return 0.0
	var partner: Node = npc.find_talk_partner()
	if partner == null:
		return 0.0
	return npc.get_social_score(partner)

func interruptible() -> bool:
	if _partner == null or _approaching:
		return true   ## not talking yet
	## Needs always win over small talk.
	if _self_npc != null and (_self_npc.hunger < NPC.NEED_LOW or _self_npc.thirst < NPC.NEED_LOW \
			or _self_npc.energy < NPC.NEED_LOW * 0.5):
		return true
	return false

func enter(npc: NPC) -> void:
	_self_npc = npc
	if _is_initiator:
		_partner = npc.find_talk_partner()
		if _partner == null:
			return
		if NPCItemUser.flat_distance(npc.global_position, (_partner as Node3D).global_position) > NPC.TALK_RANGE:
			## A friend across the room — walk over first.
			_approaching = true
			_approach_time = 0.0
			npc.set_nav_target((_partner as Node3D).global_position)
			return
		_begin_session(npc)
	else:
		_speaking = false
		_turn_left = randf_range(TURN_MIN, TURN_MAX)
		_face_partner(npc)

func _begin_session(npc: NPC) -> void:
	_approaching = false
	if not _partner.start_talk_session(npc):
		_partner = null
		return
	_duration = randf_range(SESSION_MIN, SESSION_MAX) * npc.get_talk_length_mult(_partner)
	_elapsed = 0.0
	_speaking = true   ## the initiator opens
	_turn_left = randf_range(TURN_MIN, TURN_MAX)
	_face_partner(npc)

func _face_partner(npc: NPC) -> void:
	if _partner != null and is_instance_valid(_partner):
		npc.lock_movement()
		npc.face_toward((_partner as Node3D).global_position, 1.0)
		npc.set_speaking(_speaking)

func tick(npc: NPC, delta: float) -> void:
	if _partner == null or not is_instance_valid(_partner):
		_partner = null
		return
	if _approaching:
		_approach_time += delta
		if _approach_time > APPROACH_GIVE_UP or not _partner.is_available_to_talk():
			_partner = null   ## they got busy — never mind
			return
		npc.set_nav_target((_partner as Node3D).global_position)
		npc.nav_steer(delta)
		if NPCItemUser.flat_distance(npc.global_position, (_partner as Node3D).global_position) <= CHAT_DISTANCE:
			_begin_session(npc)
		return
	## The partner walked off (interrupted by a need, a command...) — end
	## our side too instead of talking to thin air.
	if not _partner.brain.is_talking() or _partner.brain.get_talk_partner_id() != npc.npc_id:
		_partner = null
		return
	npc.halt_movement(delta)
	npc.face_toward((_partner as Node3D).global_position, delta * 6.0)
	_turn_left -= delta
	if _turn_left <= 0.0:
		_turn_left = randf_range(TURN_MIN, TURN_MAX)
		_speaking = not _speaking if _is_initiator else _speaking
		if _is_initiator:
			npc.set_speaking(_speaking)
			_partner.set_speaking(not _speaking)
			## Whoever holds the floor sometimes says something readable.
			var speaker: NPC = npc if _speaking else _partner
			if randf() < 0.55:
				speaker.say_line(NPCDialogue.chat_line(speaker, _turns > 0))
			_turns += 1
	if not _is_initiator:
		return   ## partner just waits — the initiator's end-of-session clears _partner via end_talk_session()
	_elapsed += delta
	if _elapsed >= _duration:
		_ended_naturally = true
		npc.resolve_conversation(_partner)   ## shared outcome, both sides, logged once each
		_partner.end_talk_session()
		_partner = null

func done(_npc: NPC) -> bool:
	return _partner == null

func exit(npc: NPC) -> void:
	npc.set_speaking(false)
	if _partner != null and is_instance_valid(_partner) and not _approaching:
		## We're leaving early — release the other side cleanly.
		_partner.set_speaking(false)
		_partner.end_talk_session()
	if _duration > 0.0 or not _is_initiator:
		npc.start_talk_cooldown()   ## covers natural completion and any interrupt/abort path
	_partner = null

func backoff_on_futile() -> bool:
	return _is_initiator
