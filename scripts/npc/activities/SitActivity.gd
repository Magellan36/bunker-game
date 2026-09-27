extends NPCActivity
class_name SitActivity
## SitActivity.gd — take a seat for a short daytime rest.
##
## Sep 2026: sitting is for getting off your feet in the day; real sleep is
## LieActivity (beds, at night). The two used to share the exact same score
## formula, and because Sit is scored first it won every tie — NPCs napped
## in chairs and almost never used beds.
##
## Uses the shared AdventurerModelController sit sequence (animated sit
## down / stand up), exactly like the player's chair flow.

const REST_UNTIL_ENERGY: float = 60.0
const ENERGY_REGEN_PER_GAME_HOUR: float = 25.0
const APPROACH_OFFSET: float = 0.4

enum SState { SEEK, SEATED, STANDING }

var _chair: Node = null
var _state: SState = SState.SEEK

func label() -> String:
	match _state:
		SState.SEEK: return "Finding a seat"
		SState.STANDING: return "Standing up"
		_: return "Resting"

func is_need() -> bool:
	return true

func score(npc: NPC) -> float:
	if npc.is_night_for_me():
		return 0.0   ## night-time tiredness is LieActivity's job (it falls back to a chair itself)
	var u: float = NPC.urgency(npc.energy, 40.0, 10.0)
	if u <= 0.0 or _find_free_chair(npc) == null:
		return 0.0
	return 70.0 * u

func interruptible() -> bool:
	return _state == SState.SEEK

## Getting up for something urgent is always fine.
func can_yield_to_need(_npc: NPC) -> bool:
	return _state == SState.SEATED

func enter(npc: NPC) -> void:
	_chair = _find_free_chair(npc)
	_state = SState.SEEK
	if _chair != null:
		npc.set_nav_target((_chair as Node3D).global_position)

func tick(npc: NPC, delta: float) -> void:
	if _chair == null or not is_instance_valid(_chair):
		if _state != SState.SEEK:
			npc.seated_chair = null
			npc.request_stand_at(npc.global_position)
		_chair = null
		_state = SState.SEEK
		return
	match _state:
		SState.SEEK:
			npc.nav_steer(delta)
			var close: bool = NPCItemUser.flat_distance(npc.global_position, (_chair as Node3D).global_position) < 0.9
			if npc.nav_finished() or close:
				if close or NPCItemUser.flat_distance(npc.global_position, (_chair as Node3D).global_position) < 1.6:
					if _chair.npc_try_sit(npc):
						_begin_sit(npc)
						_state = SState.SEATED
						_on_seated(npc)
					else:
						_chair = null   ## someone took it — done() ends us; rescore
				else:
					_chair = null       ## couldn't get close enough (blocked) — give up
		SState.SEATED:
			_regen_energy(npc, delta)
			if _should_stand(npc):
				_stand(npc)
		SState.STANDING:
			if not npc.in_sit_sequence():
				_release_chair(npc)
				_state = SState.SEEK

func done(_npc: NPC) -> bool:
	return _chair == null

func exit(npc: NPC) -> void:
	if _state == SState.SEATED:
		_stand(npc)
	_release_chair(npc)
	_state = SState.SEEK

func _begin_sit(npc: NPC) -> void:
	var t: Transform3D = (_chair as Node3D).get_seat_transform()
	npc.rotation.y = t.basis.get_euler().y
	var approach_pos: Vector3 = t.origin + t.basis.z * APPROACH_OFFSET
	approach_pos.y = npc.global_position.y
	npc.global_position = approach_pos
	var model: Node = npc.get_node_or_null("CharacterModel")
	if model != null:
		model.set("_chair_approach_pos", approach_pos)
		model.set("_chair_seat_pos", Vector3(t.origin.x, approach_pos.y, t.origin.z))
	npc.seated_chair = _chair   ## starts the controller's sitting_down phase
	npc.lock_movement()

## Leaves the seat: the model plays its stand-up clip, then the NPC is put
## back on its feet at the chair's (navmesh-snapped) stand spot.
func _stand(npc: NPC) -> void:
	npc.seated_chair = null
	if _chair != null and is_instance_valid(_chair):
		npc.request_stand_at((_chair as Node3D).get_stand_position())
	_state = SState.STANDING

func _on_seated(_npc: NPC) -> void:
	pass

func _regen_energy(npc: NPC, delta: float) -> void:
	npc.energy = minf(npc.energy_cap, npc.energy + ENERGY_REGEN_PER_GAME_HOUR * npc.game_hours(delta))

func _should_stand(npc: NPC) -> bool:
	return npc.energy >= REST_UNTIL_ENERGY

func _release_chair(npc: NPC) -> void:
	if _chair != null and is_instance_valid(_chair) and _chair.has_method("npc_stand"):
		_chair.npc_stand(npc)
	_chair = null

static func _find_free_chair(npc: NPC) -> Node:
	return NPCSessionActivity.nearest_in_group(npc, "chair",
		func(c: Node) -> bool: return not c.has_method("is_seat_free") or c.is_seat_free())
