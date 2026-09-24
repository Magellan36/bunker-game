extends NPCActivity
class_name WanderActivity
const NPC_COMPANIONSHIP: GDScript = preload("res://scripts/npc/NPCCompanionship.gd")
## Low-priority free-time behavior with a concrete intention per trip.
## Residents may visit another available resident, walk to a meaningful world
## landmark, or deliberately cross the cleared bunker. This stays inside the
## utility activity model: needs and work can still preempt it immediately.

enum Phase { OBSERVING, TRAVELLING }

const MIN_TRIP_DISTANCE: float = 3.0
const DESTINATION_ATTEMPTS: int = 12
const TARGET_APPROACH_DISTANCE: float = 1.6
## The nav agent may declare its target finished 1.1m early. Aim only 1.2m
## from a social target so even the early edge lands inside TALK_RANGE (3m).
const SOCIAL_STOP_OFFSET: float = 1.2
const SOCIAL_ARRIVAL_DISTANCE: float = 2.6
const SOCIAL_FOLLOW_RESUME_DISTANCE: float = 3.6
const SOCIAL_SETTLE_TIME: float = 0.6
const SOCIAL_MOVING_SPEED: float = 0.12
const SOCIAL_CHANCE_MIN: float = 0.10
const SOCIAL_CHANCE_MAX: float = 0.55
const LANDMARK_CHANCE: float = 0.75
const TRAVEL_TIMEOUT: float = 24.0
const FOLLOW_REPATH_DISTANCE: float = 0.3
const RECENT_TARGET_LIMIT: int = 3
const RESERVATION_META: StringName = &"_npc_free_time_visitor"

## Existing gameplay groups are the semantic vocabulary. Adding a new kind of
## destination only requires its world object to join a group and one entry
## here; no room graph or parallel AI system is involved.
const LANDMARK_GROUPS: Array[Dictionary] = [
	{"group": &"stove", "travel": "Heading to the kitchen", "observe": "Looking over the kitchen"},
	{"group": &"farming_tray", "travel": "Heading to the garden", "observe": "Looking over the garden"},
	{"group": &"shelving", "travel": "Going to check supplies", "observe": "Looking over the supplies"},
	{"group": &"generator", "travel": "Heading to the generator", "observe": "Checking on the generator"},
	{"group": &"interactable_static", "travel": "Heading to the common area", "observe": "Spending time in the common area"},
]

var _phase: Phase = Phase.OBSERVING
var _time_left: float = 0.0
var _destination: Vector3 = Vector3.INF
var _last_destination: Vector3 = Vector3.INF
var _target: Node3D = null
var _target_id: int = 0
var _follow_target: bool = false
var _follow_target_stationary_for: float = 0.0
var _purpose: String = "Looking around"
var _arrival_purpose: String = "Looking around"
var _recent_target_ids: Array[int] = []
var _preferred_landmark_group: StringName = &""
var _agenda_beats_remaining: int = 0
var _agenda_complete: bool = false
var _resume_intent: Dictionary = {}


func score(npc: NPC) -> float:
	var base: float = npc.get_leisure_score(&"wander", 5.0) * npc.get_work_ethic_passive_mult()
	return base + 4.0 if is_resume_candidate() and _resume_is_valid(npc) else base


func label() -> String:
	return _purpose


func switch_margin() -> float:
	return 0.25


func enter(npc: NPC) -> void:
	_release_target(npc)
	_phase = Phase.OBSERVING
	_purpose = "Looking around"
	_arrival_purpose = _purpose
	_time_left = npc.get_leisure_observation_seconds(npc.idle_time_min, npc.idle_time_max)
	_destination = Vector3.INF
	_follow_target = false
	_agenda_beats_remaining = npc.get_leisure_agenda_beat_count()
	_agenda_complete = false
	if npc.behavior_profile != null:
		_preferred_landmark_group = npc.behavior_profile.preferred_landmark_group
	var companion: NPC = npc.get_companion()
	if companion != null and NPC_COMPANIONSHIP.should_follow(npc):
		_target = companion
		_target_id = companion.get_instance_id()
		_follow_target = true
		_purpose = "Spending time with %s" % companion.npc_name
		_arrival_purpose = _purpose
		_time_left = npc.get_leisure_observation_seconds(18.0, 45.0)
	if not _resume_intent.is_empty() and resume_from_intent(npc, _resume_intent):
		_resume_intent.clear()


func tick(npc: NPC, delta: float) -> void:
	if _phase == Phase.TRAVELLING:
		_tick_travel(npc, delta)
		return

	var companion: NPC = npc.get_companion()
	if companion != null and NPC_COMPANIONSHIP.should_follow(npc):
		_target = companion
		_target_id = companion.get_instance_id()
		_follow_target = true
		_purpose = "Spending time with %s" % companion.npc_name
		_arrival_purpose = _purpose
		if NPCItemUser.flat_distance(npc.global_position, companion.global_position) \
				> SOCIAL_FOLLOW_RESUME_DISTANCE:
			_destination = _social_destination(npc, companion)
			_phase = Phase.TRAVELLING
			_time_left = TRAVEL_TIMEOUT
			npc.set_nav_target(_destination, NPC.NAV_PRECISE_TARGET_DISTANCE)
			return
	npc.halt_movement(delta)
	_time_left -= delta
	if _time_left <= 0.0:
		if _agenda_beats_remaining <= 0:
			_agenda_complete = true
			return
		_pick_intention(npc)


func _tick_travel(npc: NPC, delta: float) -> void:
	## A freed Godot Object compares equal to null, so the remembered instance
	## id is what distinguishes "open-floor trip" from "target was removed."
	if _target_id != 0 and (_target == null or not is_instance_valid(_target)):
		_abandon_intention(npc)
		return

	if _follow_target and _target != null:
		if not _target.has_method("is_available_for_companionship") \
				or not _target.is_available_for_companionship():
			_abandon_intention(npc)
			return
		var target_speed: float = _target_horizontal_speed(_target)
		if target_speed <= SOCIAL_MOVING_SPEED:
			_follow_target_stationary_for += delta
		else:
			_follow_target_stationary_for = 0.0
		var updated_destination: Vector3 = _social_destination(npc, _target)
		if NPCItemUser.flat_distance(updated_destination, _destination) >= FOLLOW_REPATH_DISTANCE:
			_destination = updated_destination
			npc.set_nav_target(_destination, NPC.NAV_PRECISE_TARGET_DISTANCE)
			_time_left = TRAVEL_TIMEOUT
		var target_distance: float = NPCItemUser.flat_distance(
			npc.global_position, _target.global_position)
		if _follow_target_stationary_for >= SOCIAL_SETTLE_TIME \
				and target_distance <= SOCIAL_ARRIVAL_DISTANCE:
			_arrive(npc)
			return
		# Stay in one continuous travel phase while the companion is moving.
		# Matching their pace avoids the old arrive/restart braking cycle.
		npc.nav_steer(delta, _follow_speed_scale(npc, target_distance, target_speed))
		_time_left -= delta
		if npc.nav_failed() or _time_left <= 0.0:
			_abandon_intention(npc)
		return

	npc.nav_steer(delta)
	_time_left -= delta
	if npc.nav_failed():
		_abandon_intention(npc)
	elif npc.nav_finished():
		if _follow_target and _target != null \
				and NPCItemUser.flat_distance(npc.global_position, _target.global_position) > SOCIAL_ARRIVAL_DISTANCE:
			_abandon_intention(npc)
		else:
			_arrive(npc)
	elif _time_left <= 0.0:
		_abandon_intention(npc)


func _pick_intention(npc: NPC) -> void:
	_release_target(npc)
	if _try_social_visit(npc):
		return
	if randf() <= LANDMARK_CHANCE and _try_landmark_visit(npc):
		return
	_pick_cross_bunker_destination(npc)


func _try_social_visit(npc: NPC) -> bool:
	var sociability: float = clampf(float(npc.personality.get("sociability", 0.5)), 0.0, 1.0)
	if randf() > lerpf(SOCIAL_CHANCE_MIN, SOCIAL_CHANCE_MAX, sociability):
		return false
	var candidates: Array[Node3D] = []
	for node: Node in npc.get_tree().get_nodes_in_group("npc"):
		if node == npc or not is_instance_valid(node) or not node is Node3D:
			continue
		if not node.has_method("is_available_for_companionship") \
				or not node.is_available_for_companionship():
			continue
		var other: Node3D = node as Node3D
		var distance: float = NPCItemUser.flat_distance(npc.global_position, other.global_position)
		if distance < MIN_TRIP_DISTANCE or distance > 24.0:
			continue
		if _recent_target_ids.has(other.get_instance_id()) or not _target_is_available(other, npc):
			continue
		candidates.append(other)
	if candidates.is_empty():
		return false
	var partner: Node3D = candidates.pick_random()
	if not NPC_COMPANIONSHIP.begin(npc, partner as NPC):
		return false
	var partner_name: String = String(partner.get("npc_name"))
	var committed := _commit_target(npc, partner, _social_destination(npc, partner),
		"Going to see %s" % partner_name, "Spending time with %s" % partner_name, true)
	if not committed:
		NPC_COMPANIONSHIP.end_for(npc)
	return committed


func _try_landmark_visit(npc: NPC) -> bool:
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}
	for definition: Dictionary in LANDMARK_GROUPS:
		var group_name: StringName = definition["group"]
		for node: Node in npc.get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or not node is Node3D:
				continue
			var candidate_landmark: Node3D = node as Node3D
			var target_id: int = candidate_landmark.get_instance_id()
			if seen.has(target_id) or _recent_target_ids.has(target_id):
				continue
			seen[target_id] = true
			if NPCItemUser.flat_distance(npc.global_position, candidate_landmark.global_position) < MIN_TRIP_DISTANCE:
				continue
			if not _target_is_available(candidate_landmark, npc):
				continue
			candidates.append({
				"node": candidate_landmark,
				"group": group_name,
				"travel": String(definition["travel"]),
				"observe": String(definition["observe"]),
			})
	if candidates.is_empty():
		return false

	## A persistent activity instance remembers one favored landmark category.
	## This creates a readable habit during the session without adding saved
	## schedules or opaque per-NPC bookkeeping.
	var preferred: Array[Dictionary] = []
	if _preferred_landmark_group != &"":
		for candidate: Dictionary in candidates:
			if candidate["group"] == _preferred_landmark_group:
				preferred.append(candidate)
	var preference_chance: float = 0.65
	if npc.behavior_profile != null:
		preference_chance = lerpf(0.82, 0.48, npc.behavior_profile.novelty_seeking)
	var choice: Dictionary = (preferred.pick_random() if not preferred.is_empty() and randf() < preference_chance
		else candidates.pick_random())
	if _preferred_landmark_group == &"":
		_preferred_landmark_group = choice["group"]
	var selected_landmark: Node3D = choice["node"] as Node3D
	var destination: Vector3 = NPCSessionActivity.approach_point(
		npc, selected_landmark, TARGET_APPROACH_DISTANCE, &"observe")
	return _commit_target(npc, selected_landmark, destination, choice["travel"], choice["observe"], false)


func _pick_cross_bunker_destination(npc: NPC) -> void:
	var world: Node = npc.get_tree().get_first_node_in_group("main_world")
	if world == null or not world.has_method("get_random_cleared_cell_center"):
		_wait_after_failed_pick(npc)
		return
	var best: Vector3 = Vector3.INF
	var best_distance: float = 0.0
	for _attempt: int in DESTINATION_ATTEMPTS:
		var candidate: Vector3 = world.get_random_cleared_cell_center()
		var distance: float = NPCItemUser.flat_distance(npc.global_position, candidate)
		if _last_destination != Vector3.INF \
				and NPCItemUser.flat_distance(_last_destination, candidate) < MIN_TRIP_DISTANCE:
			continue
		if distance > best_distance:
			best = candidate
			best_distance = distance
	if best == Vector3.INF or best_distance < MIN_TRIP_DISTANCE:
		_wait_after_failed_pick(npc)
		return
	_commit_destination(npc, best, "Crossing the bunker", "Taking in the room")


func _commit_target(npc: NPC, target: Node3D, destination: Vector3,
		travel_purpose: String, observe_purpose: String, follow: bool) -> bool:
	if not _claim_target(target, npc):
		npc.release_interaction_slot()
		return false
	_target = target
	_target_id = target.get_instance_id()
	_follow_target = follow
	_follow_target_stationary_for = 0.0
	_remember_target(_target_id)
	_commit_destination(npc, destination, travel_purpose, observe_purpose,
		NPC.NAV_PRECISE_TARGET_DISTANCE if follow else NPC.NAV_DEFAULT_TARGET_DISTANCE)
	return true


func _commit_destination(npc: NPC, destination: Vector3,
		travel_purpose: String, observe_purpose: String,
		desired_distance: float = NPC.NAV_DEFAULT_TARGET_DISTANCE) -> void:
	_destination = destination
	_last_destination = destination
	_purpose = travel_purpose
	_arrival_purpose = observe_purpose
	_phase = Phase.TRAVELLING
	_time_left = TRAVEL_TIMEOUT
	_agenda_beats_remaining = maxi(0, _agenda_beats_remaining - 1)
	npc.set_nav_target(destination, desired_distance)
	if NPCDebug.enabled:
		NPCDebug.log_free_time_intention(npc, _purpose, _target, _destination)


func _arrive(npc: NPC) -> void:
	_phase = Phase.OBSERVING
	_purpose = _arrival_purpose
	_time_left = npc.get_leisure_observation_seconds(
		maxf(8.0, npc.idle_time_min), maxf(18.0, npc.idle_time_max * 4.0))
	npc.halt_movement(1.0)
	if _target != null and is_instance_valid(_target):
		var look_point: Vector3 = _target.global_position
		look_point.y = npc.global_position.y
		if npc.global_position.distance_squared_to(look_point) > 0.01:
			npc.request_attention(_target, look_point, &"task_target", 0.78,
				_time_left + 0.5, true)


func _abandon_intention(npc: NPC) -> void:
	_release_target(npc)
	_phase = Phase.OBSERVING
	_purpose = "Reconsidering where to go"
	_arrival_purpose = _purpose
	_destination = Vector3.INF
	_follow_target = false
	_follow_target_stationary_for = 0.0
	_time_left = randf_range(0.5, 1.5)
	npc.cancel_navigation()
	npc.halt_movement(1.0)


func _wait_after_failed_pick(npc: NPC) -> void:
	_phase = Phase.OBSERVING
	_purpose = "Looking around"
	_arrival_purpose = _purpose
	_time_left = randf_range(npc.idle_time_min, npc.idle_time_max)


func _social_destination(npc: NPC, partner: Node3D) -> Vector3:
	var away: Vector3
	if partner is CharacterBody3D:
		var partner_velocity: Vector3 = (partner as CharacterBody3D).velocity
		partner_velocity.y = 0.0
		if partner_velocity.length() > SOCIAL_MOVING_SPEED:
			away = -partner_velocity.normalized()
	if away.length_squared() < 0.01:
		away = npc.global_position - partner.global_position
		away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	var spacing: float = npc.behavior_profile.preferred_social_distance \
		if npc.behavior_profile != null else SOCIAL_STOP_OFFSET
	return partner.global_position + away.normalized() * spacing


func _follow_speed_scale(npc: NPC, distance: float, partner_speed: float) -> float:
	var spacing: float = npc.behavior_profile.preferred_social_distance \
		if npc.behavior_profile != null else SOCIAL_STOP_OFFSET
	var own_speed: float = maxf(0.1, npc.move_speed * npc.get_status_speed_multiplier())
	if partner_speed > SOCIAL_MOVING_SPEED:
		var pace_match: float = partner_speed / own_speed
		var catch_up: float = maxf(0.0, distance - spacing) * 0.2
		return clampf(pace_match + catch_up, 0.35, 1.15)
	return clampf((distance - spacing) / 1.2, 0.2, 1.0)


static func _target_horizontal_speed(target: Node3D) -> float:
	if target is CharacterBody3D:
		var target_velocity: Vector3 = (target as CharacterBody3D).velocity
		return Vector2(target_velocity.x, target_velocity.z).length()
	return 0.0


func _target_is_available(target: Node3D, npc: NPC) -> bool:
	var holder: Node = _reservation_holder(target)
	return holder == null or holder == npc


func _claim_target(target: Node3D, npc: NPC) -> bool:
	if not _target_is_available(target, npc):
		return false
	target.set_meta(RESERVATION_META, weakref(npc))
	return true


func _release_target(npc: NPC) -> void:
	if _target != null and is_instance_valid(_target) and _reservation_holder(_target) == npc:
		_target.remove_meta(RESERVATION_META)
	_target = null
	_target_id = 0
	_follow_target = false
	_follow_target_stationary_for = 0.0
	npc.release_interaction_slot()


func _reservation_holder(target: Node) -> Node:
	if not target.has_meta(RESERVATION_META):
		return null
	var marker: Variant = target.get_meta(RESERVATION_META)
	if marker is WeakRef:
		return (marker as WeakRef).get_ref() as Node
	if marker is Node:
		return marker as Node
	return null


func _remember_target(target_id: int) -> void:
	_recent_target_ids.erase(target_id)
	_recent_target_ids.append(target_id)
	while _recent_target_ids.size() > RECENT_TARGET_LIMIT:
		_recent_target_ids.pop_front()


func done(_npc: NPC) -> bool:
	return _agenda_complete


func exit(npc: NPC) -> void:
	_release_target(npc)
	npc.halt_movement(1.0)


func debug_info() -> Dictionary:
	return {
		"activity": "free_time",
		"phase": "travelling" if _phase == Phase.TRAVELLING else "observing",
		"purpose": _purpose,
		"target": (String(_target.name) if _target != null and is_instance_valid(_target) else ""),
		"destination": _destination,
		"seconds_left": _time_left,
		"agenda_beats_remaining": _agenda_beats_remaining,
		"preferred_landmark_group": String(_preferred_landmark_group),
	}


func attention_target(_npc: NPC) -> Node3D:
	return _target if _target != null and is_instance_valid(_target) else null


func make_resume_intent(_npc: NPC) -> Dictionary:
	## Only travel is a safe checkpoint. Observing is already complete, social
	## targets move, and no animation/item-transfer state is ever restored.
	if _phase != Phase.TRAVELLING or _follow_target or _destination == Vector3.INF:
		return {}
	var intent: Dictionary = {
		"kind": &"free_time_travel",
		"destination": _destination,
		"purpose": _purpose,
		"arrival_purpose": _arrival_purpose,
		"reason": &"interrupted",
	}
	if _target != null and is_instance_valid(_target):
		intent["target_path"] = _target.get_path()
	return intent


func resume_from_intent(npc: NPC, intent: Dictionary) -> bool:
	if StringName(intent.get("kind", &"")) != &"free_time_travel" or npc.held_item != null:
		return false
	var destination: Vector3 = intent.get("destination", Vector3.INF)
	if destination == Vector3.INF:
		return false
	var travel_purpose: String = String(intent.get("purpose", "Returning to where I was going"))
	var observe_purpose: String = String(intent.get("arrival_purpose", "Looking around"))
	var target_path: NodePath = intent.get("target_path", NodePath(""))
	if not target_path.is_empty():
		var resolved: Node = npc.get_node_or_null(target_path)
		if resolved == null or not resolved is Node3D:
			return false
		var target := resolved as Node3D
		var approach: Vector3 = NPCSessionActivity.approach_point(
			npc, target, TARGET_APPROACH_DISTANCE, &"observe")
		return _commit_target(npc, target, approach, travel_purpose, observe_purpose, false)
	_commit_destination(npc, destination, travel_purpose, observe_purpose)
	return true


func configure_resume(intent: Dictionary) -> void:
	_resume_intent = intent.duplicate(true)


func is_resume_candidate() -> bool:
	return not _resume_intent.is_empty()


func _resume_is_valid(npc: NPC) -> bool:
	if npc.held_item != null:
		return false
	var target_path: NodePath = _resume_intent.get("target_path", NodePath(""))
	return target_path.is_empty() or npc.get_node_or_null(target_path) is Node3D
