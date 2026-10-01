extends NPCActivity
class_name LieActivity
## LieActivity.gd — going to bed.
##
## Sep 2026 rework into a real sleep routine:
##   • Residents sleep at NIGHT (their own bedtime — see NPC.chronotype),
##     not whenever energy happens to dip below 60. In the day they only
##     lie down for a nap when genuinely exhausted.
##   • Each resident adopts a bed as "theirs" and goes back to it; they only
##     take someone else's bed if their own is gone/taken.
##   • Getting into bed plays the SAME animated sit → lie-down → sleep
##     sequence as the player (shared AdventurerModelController, driven via
##     npc.sleeping_bed), instead of teleporting a rotated capsule.
##   • No free bed: doze in a chair; no chair either: sleep on the floor.
##     Each leaves a thought (slept well / stiff neck / sore back).
##   • They wake when rested and it's morning, or when a need becomes
##     critical — not the instant energy crosses a number mid-night.
##
## `relax_mode` (RelaxActivity): lie on a bed awake for a break — no sleep,
## no wake rules, the owning RelaxActivity's session timer ends it.
## `forced` (CommandRest): sleep now regardless of the clock; wake at 90%.

const BED_REGEN_PER_GAME_HOUR: float = 10.0      ## gross; NPC drains 3/h meanwhile → +7 net
const CHAIR_REGEN_PER_GAME_HOUR: float = 7.0
const FLOOR_REGEN_PER_GAME_HOUR: float = 6.0
const RELAX_REGEN_MULT: float = 0.25
const APPROACH_OFFSET: float = 0.4
const MIN_SLEEP_FOR_THOUGHT: float = 2.5          ## game hours

enum Mode { NONE, BED, CHAIR, FLOOR }
enum Phase { SEEK, IN_BED, STANDING }

var relax_mode: bool = false
var forced: bool = false

var _mode: Mode = Mode.NONE
var _phase: Phase = Phase.SEEK
var _bed: Node = null
var _chair_sleep: SitActivity = null    ## CHAIR mode runs a SitActivity variant
var _floor_rot: Vector3 = Vector3.ZERO
var _slept_hours: float = 0.0
var _finished: bool = false
var _approach: Vector3 = Vector3.ZERO
var _chair_seated: bool = false
var _floor_seek: bool = false
var _floor_seek_time: float = 0.0
var _floor_spot: Vector3 = Vector3.ZERO

func label() -> String:
	if relax_mode:
		return "Lying down" if _phase == Phase.IN_BED else "Finding a bed"
	match _mode:
		Mode.BED:
			return "Sleeping" if _phase == Phase.IN_BED else ("Getting up" if _phase == Phase.STANDING else "Heading to bed")
		Mode.CHAIR:
			return "Dozing in a chair"
		Mode.FLOOR:
			return "Sleeping on the floor"
	return "Heading to bed"

func is_need() -> bool:
	return true

func is_asleep() -> bool:
	return not relax_mode and ((_mode == Mode.BED and _phase == Phase.IN_BED) or _mode == Mode.FLOOR \
		or (_mode == Mode.CHAIR and _chair_sleep != null and _chair_sleep._state == SitActivity.SState.SEATED))

func score(npc: NPC) -> float:
	if relax_mode:
		return 0.0
	var drive: float = npc.get_sleep_drive()
	if drive <= 0.0:
		return 0.0
	return 100.0 * drive

## Asleep is not interruptible by ordinary wants — only urgent needs (see
## can_yield_to_need) or the wake rules end it.
func interruptible() -> bool:
	return _phase == Phase.SEEK and _mode != Mode.FLOOR and _chair_sleep == null

func can_yield_to_need(npc: NPC) -> bool:
	return npc.hunger < NPC.NEED_CRITICAL or npc.thirst < NPC.NEED_CRITICAL

func backoff_on_futile() -> bool:
	return not relax_mode

func enter(npc: NPC) -> void:
	_finished = false
	_slept_hours = 0.0
	_bed = _choose_bed(npc)
	if _bed != null:
		_mode = Mode.BED
		_phase = Phase.SEEK
		if not relax_mode:
			npc.home_bed = _bed
		npc.set_nav_target(_bed_side_point(npc, _bed))
		return
	if relax_mode:
		_finished = true   ## RelaxActivity falls back to standing about
		return
	var chair: Node = SitActivity._find_free_chair(npc)
	if chair != null:
		_mode = Mode.CHAIR
		_chair_seated = false
		_chair_sleep = _ChairDoze.new()
		_chair_sleep.enter(npc)
		return
	_seek_floor_spot(npc)

func tick(npc: NPC, delta: float) -> void:
	var h: float = npc.game_hours(delta)
	match _mode:
		Mode.BED:
			_tick_bed(npc, delta, h)
		Mode.CHAIR:
			_chair_sleep.tick(npc, delta)
			if _chair_sleep._state == SitActivity.SState.SEATED:
				_chair_seated = true
				_slept_hours += h
				npc.energy = minf(npc.energy_cap, npc.energy + CHAIR_REGEN_PER_GAME_HOUR * h)
				if _should_wake(npc):
					_chair_sleep._stand(npc)
			if _chair_sleep.done(npc):
				if not _chair_seated and not relax_mode:
					## Never got the chair (taken / unreachable): sleep on the
					## floor instead of giving up and wandering the night.
					_chair_sleep.exit(npc)
					_chair_sleep = null
					_seek_floor_spot(npc)
				else:
					_finished = true
		Mode.FLOOR:
			if _floor_seek:
				_floor_seek_time += delta
				npc.nav_steer(delta)
				if npc.nav_finished() or _floor_seek_time > 15.0 \
						or NPCItemUser.flat_distance(npc.global_position, _floor_spot) < 0.5:
					_floor_seek = false
					_begin_floor(npc)
				return
			npc.halt_movement(delta)
			_slept_hours += h
			npc.energy = minf(npc.energy_cap, npc.energy + FLOOR_REGEN_PER_GAME_HOUR * h)
			if _should_wake(npc):
				_finished = true

func _tick_bed(npc: NPC, delta: float, h: float) -> void:
	if _bed == null or not is_instance_valid(_bed):
		if _phase == Phase.IN_BED:
			npc.sleeping_bed = null
			npc.request_stand_at(_approach)
		_finished = true
		return
	match _phase:
		Phase.SEEK:
			npc.nav_steer(delta)
			var d: float = NPCItemUser.flat_distance(npc.global_position, (_bed as Node3D).global_position)
			if npc.nav_finished() or d < 1.4:
				if d > 2.2:
					_finished = true   ## couldn't reach it — let the brain rethink
				elif _bed.npc_try_lie(npc):
					_get_into_bed(npc)
				else:
					_finished = true   ## taken while we walked over
					for other: Node in npc.get_tree().get_nodes_in_group("npc"):
						if other != npc and other is NPC and other.sleeping_bed == _bed and not relax_mode:
							npc.bonds.relate(other.npc_id, -1.5, "took the bed I was heading for")
		Phase.IN_BED:
			if relax_mode:
				npc.energy = minf(npc.energy_cap, npc.energy + BED_REGEN_PER_GAME_HOUR * RELAX_REGEN_MULT * h)
				return
			_slept_hours += h
			npc.energy = minf(npc.energy_cap, npc.energy + BED_REGEN_PER_GAME_HOUR * h)
			if _should_wake(npc):
				_get_up(npc)
		Phase.STANDING:
			if not npc.in_sit_sequence():
				_release_bed(npc)
				_finished = true

func done(_npc: NPC) -> bool:
	return _finished

func exit(npc: NPC) -> void:
	match _mode:
		Mode.BED:
			if _phase == Phase.IN_BED:
				_get_up(npc)
			_release_bed(npc)
		Mode.CHAIR:
			if _chair_sleep != null:
				_chair_sleep.exit(npc)
		Mode.FLOOR:
			npc.rotation = _floor_rot
			npc.request_stand_at(npc.global_position)
	if not relax_mode and _mode != Mode.NONE:
		_leave_sleep_thought(npc)
		if _slept_hours >= 1.0:
			npc.bark_event("woke_floor" if _mode == Mode.FLOOR else "woke")
	_mode = Mode.NONE
	_phase = Phase.SEEK

# ─── Wake rules ─────────────────────────────────────────────────────────────
func _should_wake(npc: NPC) -> bool:
	if npc.hunger < NPC.NEED_CRITICAL or npc.thirst < NPC.NEED_CRITICAL:
		return true
	if forced:
		return npc.energy >= 90.0
	## A night's sleep lasts until morning (Sep 2026: topping up to full
	## energy used to wake them mid-night, and up they got to wander).
	if npc.is_night_for_me():
		return false
	if npc.energy >= npc.energy_cap - 0.5:
		return true
	## Daytime: a nap ends once reasonably rested; a night's sleep ends at
	## (or after) this resident's wake-up time once well rested.
	return npc.energy >= 70.0

# ─── Bed flow ─────────────────────────────────────────────────────────────
## Own bed first, then a free bed nobody has claimed, then any free bed.
func _choose_bed(npc: NPC) -> Node:
	var own: Node = npc.home_bed
	if own != null and is_instance_valid(own) and own.is_bed_free():
		return own
	var claimed: Dictionary = {}
	for other: Node in npc.get_tree().get_nodes_in_group("npc"):
		if other != npc and other is NPC and other.home_bed != null and is_instance_valid(other.home_bed):
			claimed[other.home_bed.get_instance_id()] = true
	var unclaimed: Node = NPCSessionActivity.nearest_in_group(npc, "bed",
		func(b: Node) -> bool: return b.is_bed_free() and not claimed.has(b.get_instance_id()))
	if unclaimed != null:
		return unclaimed
	return NPCSessionActivity.nearest_in_group(npc, "bed", func(b: Node) -> bool: return b.is_bed_free())

## Which long side of the bed is nearer the NPC (+1 / -1), matching the
## player's bed flow in MainWorld._wire_bed().
func _side(npc: NPC, bed: Node3D) -> float:
	var local: Vector3 = bed.global_transform.affine_inverse() * npc.global_position
	return 1.0 if local.z >= 0.0 else -1.0

func _bed_side_point(npc: NPC, bed: Node) -> Vector3:
	if not bed.has_method("get_sheets_transform"):
		return (bed as Node3D).global_position
	var t: Transform3D = bed.get_sheets_transform(_side(npc, bed as Node3D))
	return t.origin + t.basis.z * (APPROACH_OFFSET + 0.3)

func _get_into_bed(npc: NPC) -> void:
	var bed3: Node3D = _bed as Node3D
	var side: float = _side(npc, bed3)
	npc.lock_movement()
	if _bed.has_method("get_sheets_transform"):
		## Fallback stand spot only — the model controller walks to the bed
		## side nearest the NPC, lies down, and on waking returns the NPC to
		## wherever its stand-up clip actually ends (see NPC._physics_process).
		var t: Transform3D = _bed.get_sheets_transform(side)
		_approach = t.origin + t.basis.z * APPROACH_OFFSET
		_approach.y = npc.global_position.y
	else:
		_approach = npc.global_position
	npc.sleeping_bed = bed3   ## starts the controller's sit → lie-down → sleep sequence
	_phase = Phase.IN_BED

func _get_up(npc: NPC) -> void:
	npc.sleeping_bed = null   ## controller plays sit-up/stand and eases back to the side
	npc.request_stand_at(_approach)
	_phase = Phase.STANDING

func _release_bed(npc: NPC) -> void:
	if _bed != null and is_instance_valid(_bed) and _bed.has_method("npc_stand"):
		_bed.npc_stand(npc)

# ─── Floor fallback ───────────────────────────────────────────────────────
## Somewhere out of the way to lie down — against a wall, not in the middle
## of the room or a doorway — then down they go.
func _seek_floor_spot(npc: NPC) -> void:
	_mode = Mode.FLOOR
	var spot: Dictionary = LeanActivity.find_spot(npc)
	_floor_spot = spot["stand"] if not spot.is_empty() else npc.global_position
	_floor_seek = not spot.is_empty()
	_floor_seek_time = 0.0
	if _floor_seek:
		npc.set_nav_target(_floor_spot)
	else:
		_begin_floor(npc)

func _begin_floor(npc: NPC) -> void:
	_mode = Mode.FLOOR
	_floor_rot = npc.rotation
	npc.lock_movement()
	npc.rotation = Vector3(_floor_rot.x, _floor_rot.y, _floor_rot.z + deg_to_rad(90.0))

func _leave_sleep_thought(npc: NPC) -> void:
	if _slept_hours < MIN_SLEEP_FOR_THOUGHT:
		return
	match _mode:
		Mode.BED: npc.add_thought("slept_in_bed")
		Mode.CHAIR: npc.add_thought("slept_in_chair")
		Mode.FLOOR: npc.add_thought("slept_on_floor")
	npc.log_action("Slept %.1f hours (%s)" % [_slept_hours, ["", "in bed", "in a chair", "on the floor"][_mode]])

## Chair variant used for dozing: no own regen/stand rule — LieActivity
## drives both.
class _ChairDoze extends SitActivity:
	func _regen_energy(_npc: NPC, _delta: float) -> void:
		pass
	func _should_stand(_npc: NPC) -> bool:
		return false
