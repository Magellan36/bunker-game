extends RefCounted
class_name NPCStuckRecovery
## NPCStuckRecovery.gd (Sep 2026 rewrite; logic formerly inline in NPC.gd).
##
## Watches an NPC while it is TRYING to travel (nav target active, movement
## not locked by an activity) and steps in when real displacement stops.
##
## What changed versus the old inline version, and why:
##   • Stall detection is relative to the NPC's own expected speed. The old
##     fixed 0.6 m/s bar meant slow NPCs (elderly, injured, exhausted) were
##     "stuck" every half second — each false alarm aborted their activity,
##     dropped what they carried and teleported them.
##   • Recovery never teleports blindly. Every nudge target is snapped onto
##     the navmesh AND swept with test_move(); if no clean spot exists the
##     NPC stays put and the activity is abandoned instead. Blind position
##     nudges were the documented cause of NPCs clipping through walls and
##     falling out of the world.
##   • Recovery doesn't drop carried items any more — NPCBrain's hands
##     policy already sets things down if the NEXT activity can't use them.
##   • Escalation is one ladder for every obstruction type:
##       1. re-path (and give a blocking loose item a shove)
##       2. side-step / back off along the collision normal (safe nudge)
##       3. larger safe nudge + abandon the activity (bench it briefly)
##     Any real progress resets the ladder.
##   • Fell-out rescue: an NPC that ends up below the floor is returned to
##     its last known safe standing spot instead of waiting for MainWorld's
##     deep abyss catch at Y = -8.

const CHECK_INTERVAL: float = 0.25
const GRACE: float = 0.75                 ## stalled this long before step 1
const MIN_PROGRESS_FRAC: float = 0.3      ## of expected travel per interval
const MIN_PROGRESS_ABS: float = 0.03
const NUDGE_SMALL: float = 0.6
const NUDGE_LARGE: float = 1.3
const FLOOR_Y: float = 0.5                ## BunkerNavMesh.FLOOR_Y
const FELL_OUT_BELOW: float = -0.25       ## NPC origin (capsule centre) this low = under the floor
const ABANDON_BENCH_SEC: float = 20.0

var recoveries: int = 0                   ## lifetime count, for debug dumps
var last_cause: String = ""

var _npc: NPC = null
var _timer: float = 0.0
var _ref_pos: Vector3 = Vector3.ZERO
var _stalled_for: float = 0.0
var _step: int = 0
var _last_safe_pos: Vector3 = Vector3.INF
var _safe_timer: float = 0.0

func setup(npc: NPC) -> void:
	_npc = npc
	_ref_pos = npc.global_position

func reset() -> void:
	_timer = 0.0
	_stalled_for = 0.0
	_step = 0
	_ref_pos = _npc.global_position

## "Arrived but can't act": navigation finished yet the activity keeps
## steering (never locks movement to do its thing) — the target is out of
## reach from the closest walkable spot. After this long, abandon it.
const ARRIVED_IDLE_LIMIT: float = 5.0
var _arrived_idle: float = 0.0

func tick(delta: float) -> void:
	_track_safe_position(delta)
	if _rescue_if_fell_out():
		return
	if _npc.nav_agent != null and not _npc.is_movement_locked() and _npc.nav_agent.is_navigation_finished() \
			and _npc.brain != null and _npc.brain.current_activity() != null:
		_arrived_idle += delta
		if _arrived_idle >= ARRIVED_IDLE_LIMIT:
			_arrived_idle = 0.0
			## Standing somewhere the navmesh doesn't reach (a pocket
			## between furniture)? Ease back onto walkable ground first.
			var home: Vector3 = snap_to_navmesh(_npc.global_position)
			if home != Vector3.INF and NPCItemUser.flat_distance(home, _npc.global_position) > 0.15:
				var d: Vector3 = home - _npc.global_position
				d.y = 0.0
				_safe_nudge(d.normalized(), d.length() + 0.3)
			last_cause = "arrived but the target is out of reach"
			_npc.job_state.mark_unreachable_near(_npc.get_tree(), _npc.nav_agent.target_position, 1.0)
			NPCDebug.log_stuck(_npc, "unreachable target", {"activity": _npc.brain.current_label()})
			_npc.abandon_current_activity(last_cause, 30.0)
			return
	else:
		_arrived_idle = 0.0
	if _npc.nav_agent == null or _npc.is_movement_locked() or _npc.nav_agent.is_navigation_finished():
		_timer = 0.0
		_stalled_for = 0.0
		_ref_pos = _npc.global_position
		return
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	var moved: float = NPCItemUser.flat_distance(_npc.global_position, _ref_pos)
	var expected: float = _npc.get_expected_travel_speed() * _timer
	_timer = 0.0
	_ref_pos = _npc.global_position
	if moved >= maxf(MIN_PROGRESS_ABS, expected * MIN_PROGRESS_FRAC):
		_stalled_for = 0.0
		_step = 0
		return
	_stalled_for += CHECK_INTERVAL
	if _stalled_for >= GRACE:
		_stalled_for = 0.0
		_recover()

# ─── Recovery ladder ─────────────────────────────────────────────────────
func _recover() -> void:
	recoveries += 1
	_step += 1
	var col: KinematicCollision3D = _blocking_collision()
	var blocker: Object = col.get_collider() if col != null else null
	last_cause = _describe(blocker)
	NPCDebug.log_stuck(_npc, "step %d" % _step, {"cause": last_cause})

	match _step:
		1:
			## Re-path — the nav path may simply be stale (mid-rebake after a
			## dig, a door of clutter that just moved). Shove a light loose
			## item that is physically in the way.
			if blocker is RigidBody3D and not (("is_held" in blocker) and blocker.is_held):
				var rb: RigidBody3D = blocker as RigidBody3D
				if rb.mass < 3.0:
					var away: Vector3 = -col.get_normal()
					away.y = 0.0
					if away.length() > 0.01:
						rb.apply_central_impulse(away.normalized() * 2.0)
				elif _npc.can_clear_obstruction(rb):
					## A heavy item is blocking the way and our hands are
					## free: pick it up and put it somewhere sensible.
					_npc.brain.force_command(CleaningActivity.new(rb))
					_step = 0
					return
			_npc.repath()
		2:
			_safe_nudge(_away_dir(col, blocker), NUDGE_SMALL)
			_npc.repath()
		_:
			_safe_nudge(_away_dir(col, blocker), NUDGE_LARGE)
			_npc.abandon_current_activity("stuck (%s)" % last_cause, ABANDON_BENCH_SEC)
			_step = 0

## Direction to back off in: the collision normal if we have one, away from
## a blocking body otherwise, else a random horizontal direction.
func _away_dir(col: KinematicCollision3D, blocker: Object) -> Vector3:
	var d: Vector3 = Vector3.ZERO
	if col != null:
		d = col.get_normal()
	if d.length() < 0.01 and blocker is Node3D and is_instance_valid(blocker):
		d = _npc.global_position - (blocker as Node3D).global_position
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	## Blocked by another NPC: side-step rather than back straight up, so
	## two NPCs facing each other in a corridor don't just bounce apart
	## and walk straight back into each other.
	if blocker is NPC:
		d = d.normalized().rotated(Vector3.UP, deg_to_rad(60.0) * (1.0 if randf() < 0.5 else -1.0))
	return d.normalized()

## Moves the NPC only to a spot that is (a) on the navmesh and (b) reachable
## in a straight sweep without hitting anything. Tries a fan of directions
## and distances; does nothing if none is clean.
func _safe_nudge(dir: Vector3, distance: float) -> bool:
	var angles: Array[float] = [0.0, 40.0, -40.0, 80.0, -80.0, 140.0, -140.0, 180.0]
	for scale: float in [1.0, 0.6, 0.35]:
		for a: float in angles:
			var d: Vector3 = dir.rotated(Vector3.UP, deg_to_rad(a)) * distance * scale
			var target: Vector3 = snap_to_navmesh(_npc.global_position + d)
			if target == Vector3.INF:
				continue
			var motion: Vector3 = target - _npc.global_position
			motion.y = 0.0
			if motion.length() < 0.1:
				continue
			if _npc.test_move(_npc.global_transform, motion):
				## The sweep fails for EVERY direction when the capsule is
				## already overlapping something (the usual reason it's
				## wedged). Accept the spot anyway if it is itself clear and
				## genuinely walkable from here (short nav path — never
				## through a wall into another room).
				if not (_spot_clear(target) and _short_walk(target, motion.length())):
					continue
			_npc.global_position += motion
			_npc.velocity = Vector3.ZERO
			return true
	return false

func _spot_clear(p: Vector3) -> bool:
	var shape: Shape3D = _npc.collision.shape if _npc.collision != null else null
	if shape == null:
		return false
	var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, p + _npc.collision.position)
	q.exclude = [_npc.get_rid()]
	q.collision_mask = 1
	for hit: Dictionary in _npc.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = hit.get("collider")
		if c is StaticBody3D or (c is RigidBody3D and (c as RigidBody3D).mass >= 3.0):
			return false
	return true

func _short_walk(p: Vector3, straight: float) -> bool:
	var map: RID = _npc.get_world_3d().navigation_map
	var from: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(_npc.global_position.x, FLOOR_Y, _npc.global_position.z))
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, Vector3(p.x, FLOOR_Y, p.z), true)
	if path.size() < 2:
		return false
	var length: float = 0.0
	for i: int in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length <= straight * 2.5 + 0.5

## Closest navmesh point to `p` at the NPC's standing height, or
## Vector3.INF if the navmesh isn't close enough to trust.
func snap_to_navmesh(p: Vector3) -> Vector3:
	var map: RID = _npc.get_world_3d().navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var q: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(p.x, FLOOR_Y, p.z))
	if NPCItemUser.flat_distance(q, p) > 1.0:
		return Vector3.INF
	return Vector3(q.x, _npc.standing_height(), q.z)

func _blocking_collision() -> KinematicCollision3D:
	var best: KinematicCollision3D = null
	for i: int in _npc.get_slide_collision_count():
		var c: KinematicCollision3D = _npc.get_slide_collision(i)
		if absf(c.get_normal().y) > 0.7:
			continue   ## floor/ceiling contact, not an obstruction
		var body: Object = c.get_collider()
		if body is RigidBody3D and (("is_held" in body) and body.is_held):
			continue   ## our own carried item
		## Prefer items (actionable), then NPCs, then walls.
		if best == null or body is RigidBody3D or (body is NPC and not (best.get_collider() is RigidBody3D)):
			best = c
	return best

func _describe(blocker: Object) -> String:
	if blocker == null or not is_instance_valid(blocker):
		return "nothing identifiable"
	if blocker is NPC:
		return "blocked by %s" % String(blocker.npc_name)
	if blocker is RigidBody3D:
		return "blocked by %s" % NPCSessionActivity.display_name(blocker)
	if blocker is Node:
		return "wedged against %s" % String((blocker as Node).name)
	return "?"

# ─── Safety net ──────────────────────────────────────────────────────────
func _track_safe_position(delta: float) -> void:
	_safe_timer -= delta
	if _safe_timer > 0.0:
		return
	_safe_timer = 0.5
	if _npc.is_on_floor() and _npc.global_position.y > FELL_OUT_BELOW + 0.5 and not _npc.in_sit_sequence():
		_last_safe_pos = _npc.global_position

func _rescue_if_fell_out() -> bool:
	if _npc.global_position.y >= FELL_OUT_BELOW:
		return false
	var target: Vector3 = _last_safe_pos
	if target == Vector3.INF:
		target = snap_to_navmesh(_npc.global_position)
	if target == Vector3.INF:
		return false   ## nothing better known — MainWorld's abyss failsafe will catch it
	push_warning("[NPC] %s fell below the floor at %s — rescued to %s" % [_npc.npc_name, _npc.global_position, target])
	_npc.global_position = target + Vector3(0.0, 0.05, 0.0)
	_npc.velocity = Vector3.ZERO
	_npc.abandon_current_activity("fell below the floor", 5.0)
	reset()
	return true
