extends RefCounted
class_name NPCCompanionship
## Mutual, non-exclusive social sessions. A session influences where both
## residents spend their time but does not replace Gardening/Cleaning/Sit/etc.

const SESSION_MIN_MSEC: int = 90000
const SESSION_MAX_MSEC: int = 240000
const VICINITY_RADIUS: float = 6.0
const BREAK_DISTANCE: float = 10.0
const SEPARATION_GRACE_MSEC: int = 18000

static var _sessions: Dictionary = {}
static var _member_session: Dictionary = {}
static var _next_id: int = 1


static func begin(a: NPC, b: NPC) -> bool:
	_cleanup()
	if a == null or b == null or a == b or not is_instance_valid(a) or not is_instance_valid(b):
		return false
	var a_existing := int(_member_session.get(a.get_instance_id(), 0))
	var b_existing := int(_member_session.get(b.get_instance_id(), 0))
	if a_existing != 0 or b_existing != 0:
		return a_existing != 0 and a_existing == b_existing
	if not _can_join(a) or not _can_join(b):
		return false
	var now := Time.get_ticks_msec()
	var session_id := _next_id
	_next_id += 1
	_sessions[session_id] = {
		"a": weakref(a), "b": weakref(b),
		"expires": now + randi_range(SESSION_MIN_MSEC, SESSION_MAX_MSEC),
		"separated_since": 0,
	}
	_member_session[a.get_instance_id()] = session_id
	_member_session[b.get_instance_id()] = session_id
	return true


static func tick(npc: NPC) -> void:
	_cleanup()
	var session := _session_for(npc)
	if session.is_empty():
		return
	var partner := _other(session, npc)
	if partner == null:
		end_for(npc)
		return
	var now := Time.get_ticks_msec()
	if NPCItemUser.flat_distance(npc.global_position, partner.global_position) > BREAK_DISTANCE:
		if int(session.get("separated_since", 0)) == 0:
			session["separated_since"] = now
		elif now - int(session["separated_since"]) >= SEPARATION_GRACE_MSEC:
			end_for(npc)
	else:
		session["separated_since"] = 0


static func partner_for(npc: NPC) -> NPC:
	_cleanup()
	return _other(_session_for(npc), npc)


static func is_position_compatible(npc: NPC, position: Vector3, extra_radius: float = 0.0) -> bool:
	var partner := partner_for(npc)
	return partner == null or NPCItemUser.flat_distance(position, partner.global_position) \
		<= VICINITY_RADIUS + extra_radius


static func end_for(npc: NPC) -> void:
	if npc == null:
		return
	var session_id := int(_member_session.get(npc.get_instance_id(), 0))
	if session_id == 0:
		return
	var session: Dictionary = _sessions.get(session_id, {})
	for key: String in ["a", "b"]:
		var ref: WeakRef = session.get(key) as WeakRef
		var member: NPC = ref.get_ref() as NPC if ref != null else null
		if member != null:
			_member_session.erase(member.get_instance_id())
	_sessions.erase(session_id)


static func _can_join(npc: NPC) -> bool:
	if npc.health <= 0.0:
		return false
	return not npc.is_passed_out() if npc.has_method("is_passed_out") else true


static func _session_for(npc: NPC) -> Dictionary:
	if npc == null:
		return {}
	return _sessions.get(int(_member_session.get(npc.get_instance_id(), 0)), {})


static func _other(session: Dictionary, npc: NPC) -> NPC:
	if session.is_empty():
		return null
	for key: String in ["a", "b"]:
		var ref: WeakRef = session.get(key) as WeakRef
		var member: NPC = ref.get_ref() as NPC if ref != null else null
		if member != null and member != npc:
			return member
	return null


static func _cleanup() -> void:
	var now := Time.get_ticks_msec()
	for session_id: Variant in _sessions.keys():
		var session: Dictionary = _sessions.get(session_id, {})
		var a_ref: WeakRef = session.get("a") as WeakRef
		var b_ref: WeakRef = session.get("b") as WeakRef
		if a_ref == null or b_ref == null or a_ref.get_ref() == null or b_ref.get_ref() == null \
				or now >= int(session.get("expires", 0)):
			var a: NPC = a_ref.get_ref() as NPC if a_ref != null else null
			var b: NPC = b_ref.get_ref() as NPC if b_ref != null else null
			if a != null:
				_member_session.erase(a.get_instance_id())
			if b != null:
				_member_session.erase(b.get_instance_id())
			_sessions.erase(session_id)
