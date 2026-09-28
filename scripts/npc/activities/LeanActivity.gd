extends NPCActivity
class_name LeanActivity
## LeanActivity.gd (Sep 2026) — a passive idle: lean back against a wall for
## a while, like people do when there's nothing pressing.
##
## Uses the animation session's wall-lean rig (docs/systems/player-model/
## ANIMATIONS.md "Wall lean"): walk to a spot, then
## CharacterModel.begin_lean(wall_point, wall_normal) turns the resident's
## back to the wall and settles into the loop. end_lean() stands them back
## up; NPC.request_stand_at() waits for that stand-up before walking again.
##
## Spot choice: a FLAT wall (knee and shoulder raycasts agree), never
## furniture or loose items, with ~0.5 m of clear walkable floor in front,
## reachable, and not beside another leaner or a crowd.
##
## Competes with Wander/Relax as a free-time option; a cooldown afterwards
## keeps residents rotating between them instead of leaning all day.

const BASE_SCORE: float = 6.5
const DURATION_HOURS_MIN: float = 0.35   ## game hours (~20-50 game minutes)
const DURATION_HOURS_MAX: float = 0.8
const COOLDOWN_HOURS_MIN: float = 0.4
const COOLDOWN_HOURS_MAX: float = 1.2
const SEARCH_RADIUS: float = 7.0
const SAMPLES: int = 10
const RAY_LEN: float = 2.6
const STANDOFF: float = 0.55              ## approach point distance from the wall
const CLEAR_RADIUS: float = 0.3           ## free floor needed in front of the wall
const SPOT_SPACING: float = 1.3           ## from other leaners / residents
const APPROACH_TIMEOUT: float = 12.0
const LOOK_RANGE: float = 4.0

enum Phase { WALK, SETTLE, LEANING, DONE }

static var _spots: Dictionary = {}        ## npc instance id -> wall point (other leaners avoid it)

var _phase: Phase = Phase.DONE
var _wall_point: Vector3 = Vector3.ZERO
var _wall_normal: Vector3 = Vector3.ZERO
var _left_hours: float = 0.0
var _walk_time: float = 0.0
var _started_lean: bool = false
var _look: Node3D = null
var _look_timer: float = 0.0

func label() -> String:
	return "Leaning on the wall" if _phase == Phase.LEANING else "Finding a spot to lean"

func score(npc: NPC) -> float:
	if npc.is_night_for_me() or NPCItemUser.hands_full(npc):
		return 0.0
	if NPCClock.now() < float(npc.get_meta("_lean_cooldown_until", -1.0)):
		return 0.0
	if npc.get_node_or_null("CharacterModel") == null or not npc.get_node("CharacterModel").has_method("begin_lean"):
		return 0.0
	return BASE_SCORE * npc.get_work_ethic_passive_mult()

func enter(npc: NPC) -> void:
	_started_lean = false
	_walk_time = 0.0
	var spot: Dictionary = find_spot(npc)
	if spot.is_empty():
		_phase = Phase.DONE
		npc.set_meta("_lean_cooldown_until", NPCClock.now() + 0.5)   ## nowhere to lean nearby — don't retry every second
		return
	_wall_point = spot["point"]
	_wall_normal = spot["normal"]
	_spots[npc.get_instance_id()] = _wall_point
	_left_hours = randf_range(DURATION_HOURS_MIN, DURATION_HOURS_MAX)
	_phase = Phase.WALK
	npc.set_nav_target(spot["stand"])

func tick(npc: NPC, delta: float) -> void:
	match _phase:
		Phase.WALK:
			_walk_time += delta
			npc.nav_steer(delta)
			var stand: Vector3 = _wall_point + _wall_normal * STANDOFF
			if NPCItemUser.flat_distance(npc.global_position, stand) < 0.6 or npc.nav_finished():
				if NPCItemUser.flat_distance(npc.global_position, stand) > 1.2 or not _begin(npc):
					_phase = Phase.DONE   ## couldn't get there / model busy — let the brain rethink
			elif _walk_time > APPROACH_TIMEOUT:
				_phase = Phase.DONE
		Phase.SETTLE:
			npc.halt_movement(delta)
			if _model(npc) != null and _model(npc).is_leaning():
				_phase = Phase.LEANING
		Phase.LEANING:
			_left_hours -= npc.game_hours(delta)
			_tick_look(npc, delta)
			if _left_hours <= 0.0:
				_phase = Phase.DONE

func _begin(npc: NPC) -> bool:
	var model: Node = _model(npc)
	if model == null or not model.begin_lean(_wall_point, _wall_normal):
		return false
	npc.lock_movement()
	_started_lean = true
	_phase = Phase.SETTLE
	return true

func done(_npc: NPC) -> bool:
	return _phase == Phase.DONE

func exit(npc: NPC) -> void:
	_spots.erase(npc.get_instance_id())
	if _started_lean:
		var model: Node = _model(npc)
		if model != null:
			model.end_lean()
		npc.request_stand_at(npc.global_position)   ## waits for the stand-up, then settles where the clip leaves them
		npc.set_meta("_lean_cooldown_until", NPCClock.now() + randf_range(COOLDOWN_HOURS_MIN, COOLDOWN_HOURS_MAX))
	_started_lean = false
	_phase = Phase.DONE

func backoff_on_futile() -> bool:
	return false   ## own cooldown handles "nowhere to lean"

func attention_target(_npc: NPC) -> Node3D:
	return _look if _phase == Phase.LEANING and _look != null and is_instance_valid(_look) else null

static func _model(npc: NPC) -> Node:
	return npc.get_node_or_null("CharacterModel")

## Glance at whoever is close — the player first — re-picking every few
## seconds (the head look-at itself is slow and subtle).
func _tick_look(npc: NPC, delta: float) -> void:
	_look_timer -= delta
	if _look_timer > 0.0:
		return
	_look_timer = randf_range(3.0, 5.5)
	_look = null
	var best: float = LOOK_RANGE
	var player: Node3D = npc.get_tree().get_first_node_in_group("player") as Node3D
	if player != null and NPCItemUser.flat_distance(player.global_position, npc.global_position) < LOOK_RANGE:
		_look = player
		return
	for other: Node in npc.get_tree().get_nodes_in_group("npc"):
		if other == npc:
			continue
		var d: float = NPCItemUser.flat_distance((other as Node3D).global_position, npc.global_position)
		if d < best and randf() < 0.7:
			best = d
			_look = other

# ─── Spot search ────────────────────────────────────────────────────────────
## Returns {"point": wall surface point at floor height, "normal": outward
## wall normal (horizontal), "stand": approach point} or {}.
static func find_spot(npc: NPC) -> Dictionary:
	var map: RID = npc.get_world_3d().navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return {}
	var space: PhysicsDirectSpaceState3D = npc.get_world_3d().direct_space_state
	var floor_y: float = NPCStuckRecovery.FLOOR_Y
	var best: Dictionary = {}
	var best_d: float = INF
	for i: int in SAMPLES:
		## A random walkable point near the resident, then look for a wall
		## in a random direction from it.
		var a: float = randf() * TAU
		var r: float = randf_range(1.0, SEARCH_RADIUS)
		var probe: Vector3 = NavigationServer3D.map_get_closest_point(map,
			Vector3(npc.global_position.x + cos(a) * r, floor_y, npc.global_position.z + sin(a) * r))
		var dir: Vector3 = Vector3(cos(randf() * TAU), 0.0, sin(randf() * TAU)).normalized()
		var spot: Dictionary = _wall_along(npc, space, probe, dir, floor_y)
		if spot.is_empty():
			continue
		var d: float = NPCItemUser.flat_distance(npc.global_position, spot["stand"])
		if d < best_d and _spot_free(npc, spot) and NPCItemUser.is_reachable(npc, spot["stand"], 0.5):
			best_d = d
			best = spot
	return best

static func _wall_along(npc: NPC, space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, floor_y: float) -> Dictionary:
	var knee: Dictionary = _ray(npc, space, Vector3(from.x, floor_y + 0.45, from.z), dir)
	var shoulder: Dictionary = _ray(npc, space, Vector3(from.x, floor_y + 1.35, from.z), dir)
	if knee.is_empty() or shoulder.is_empty():
		return {}
	var n: Vector3 = knee["normal"]
	if absf(n.y) > 0.15 or absf((shoulder["normal"] as Vector3).y) > 0.15:
		return {}   ## not a vertical face
	if (knee["normal"] as Vector3).dot(shoulder["normal"]) < 0.97:
		return {}   ## not one flat face from knee to shoulder
	var kp: Vector3 = knee["position"]
	var sp: Vector3 = shoulder["position"]
	if Vector2(kp.x - sp.x, kp.z - sp.z).length() > 0.08:
		return {}   ## shelf lip / ledge / sloped rock
	if not _is_wall(knee["collider"]) or not _is_wall(shoulder["collider"]):
		return {}
	n = Vector3(n.x, 0.0, n.z).normalized()
	var point: Vector3 = Vector3(kp.x, floor_y, kp.z)
	var stand: Vector3 = point + n * STANDOFF
	## Walkable floor right there, and nothing solid in the space the body
	## (and the raised knee) will occupy.
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(npc.get_world_3d().navigation_map, stand)
	if NPCItemUser.flat_distance(on_mesh, stand) > 0.2:
		return {}
	var shape := SphereShape3D.new()
	shape.radius = CLEAR_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, Vector3(stand.x, floor_y + 0.55, stand.z) - n * 0.1)
	q.exclude = [npc.get_rid()]
	if not space.intersect_shape(q, 1).is_empty():
		return {}
	## Elbow room: no furniture right beside the spot either (leaning next
	## to a bed or shelf reads as wedged in, and the walk there bumps it).
	var side: Vector3 = Vector3(-n.z, 0.0, n.x)
	for s: float in [-0.65, 0.65]:
		q.transform = Transform3D(Basis.IDENTITY, Vector3(stand.x, floor_y + 0.55, stand.z) + side * s)
		if not space.intersect_shape(q, 1).is_empty():
			return {}
	return {"point": point, "normal": n, "stand": Vector3(stand.x, floor_y, stand.z)}

static func _ray(npc: NPC, space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * RAY_LEN)
	q.exclude = [npc.get_rid()]
	return space.intersect_ray(q)

## Structural surfaces only: rock/room walls and player-built walls — never
## furniture, devices, doors or loose items.
static func _is_wall(collider: Object) -> bool:
	if collider == null or not (collider is Node):
		return false
	if collider is RigidBody3D or collider is CharacterBody3D:
		return false
	var n: Node = collider as Node
	for i: int in 3:
		if n == null:
			break
		if n.is_in_group("interactable") or n.is_in_group("npc_bottleneck") or n.is_in_group("pickup"):
			return false
		if n.has_meta("tile_id") and int(n.get_meta("tile_id")) != 1:
			return false   ## a placed object that isn't a full-height wall (BuildModeController.TILE_WALL)
		n = n.get_parent()
	return true

static func _spot_free(npc: NPC, spot: Dictionary) -> bool:
	for id in _spots.keys():
		if id != npc.get_instance_id() and NPCItemUser.flat_distance(_spots[id], spot["point"]) < SPOT_SPACING:
			return false
	for other: Node in npc.get_tree().get_nodes_in_group("npc"):
		if other != npc and NPCItemUser.flat_distance((other as Node3D).global_position, spot["stand"]) < SPOT_SPACING:
			return false
	return true
