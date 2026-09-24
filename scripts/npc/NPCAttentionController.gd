extends Node
class_name NPCAttentionController
## Presentation-only awareness layer. It consumes short-lived stimuli and
## chooses what a resident appears to notice; utility scores and activity
## lifecycle decisions never read this controller.
##
## AdventurerModel currently has no animation-safe additive head/neck hook.
## The controller therefore uses the documented fallback: the selected gaze
## target reacts first internally, then the whole body follows smoothly only
## while the CharacterBody is stationary. A future model controller may expose
## set_attention_target() without changing this arbitration contract.

const METRICS: GDScript = preload("res://scripts/npc/NPCMetrics.gd")

const SCAN_INTERVAL: float = 0.18
const STIMULUS_LIMIT: int = 16
const PLAYER_NOTICE_RADIUS: float = 5.5
const RESIDENT_NOTICE_RADIUS: float = 4.5
const BODY_YAW_THRESHOLD: float = deg_to_rad(24.0)
const TASK_YAW_THRESHOLD: float = deg_to_rad(12.0)
const CONVERSATION_YAW_THRESHOLD: float = deg_to_rad(8.0)
const BODY_TURN_MAX_SPEED: float = deg_to_rad(105.0)
const BODY_TURN_ACCELERATION: float = deg_to_rad(280.0)
const BODY_FOLLOW_DELAY: float = 0.18
const STATIONARY_SPEED: float = 0.10

var _npc: CharacterBody3D = null
var _stimuli: Array[Dictionary] = []
var _active: Dictionary = {}
var _pending: Dictionary = {}
var _pending_ready_at: float = 0.0
var _active_since: float = 0.0
var _scan_left: float = 0.0
var _stationary_for: float = 0.0
var _angular_velocity: float = 0.0
var _reaction_delay: float = 0.22
var _ambient_interval_min: float = 3.5
var _ambient_interval_max: float = 7.5
var _next_ambient_at: float = 0.0
var _next_aversion_at: float = INF
var _aversion_until: float = 0.0
var _aversion_sign: float = 1.0
var _rng := RandomNumberGenerator.new()


func setup(npc: CharacterBody3D) -> void:
	_npc = npc
	_rng.seed = int(npc.get("generation_seed")) ^ 0x4154544E
	var profile: Variant = npc.get("behavior_profile")
	if profile != null:
		var restlessness: float = clampf(float(profile.get("restlessness")), 0.0, 1.0)
		var patience: float = clampf(float(profile.get("patience")), 0.0, 1.0)
		_reaction_delay = lerpf(0.34, 0.12, restlessness)
		_ambient_interval_min = lerpf(2.8, 5.2, patience)
		_ambient_interval_max = lerpf(5.5, 10.0, patience)
	_next_ambient_at = _now() + _rng.randf_range(_ambient_interval_min, _ambient_interval_max)


## Input contract:
## {source: WeakRef, world_position: Vector3, category: StringName,
##  salience: float, expires_at: float, body_turn_allowed: bool}
func submit(stimulus: Dictionary) -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var now: float = _now()
	var source_variant: Variant = stimulus.get("source")
	var source_ref: WeakRef = source_variant as WeakRef
	if source_ref == null and source_variant is Object:
		source_ref = weakref(source_variant)
	var normalized: Dictionary = {
		"source": source_ref,
		"world_position": stimulus.get("world_position", _npc.global_position),
		"category": StringName(stimulus.get("category", &"ambient")),
		"salience": clampf(float(stimulus.get("salience", 0.0)), 0.0, 2.0),
		"expires_at": float(stimulus.get("expires_at", now + 1.0)),
		"body_turn_allowed": bool(stimulus.get("body_turn_allowed", true)),
	}
	if float(normalized["expires_at"]) <= now:
		return
	var key: String = _stimulus_key(normalized)
	# A continuously observed target is one sustained stimulus, not a series of
	# expiring glances. Refresh its payload without restarting reaction timing.
	if key == _stimulus_key(_active):
		_active = normalized.duplicate()
	if key == _stimulus_key(_pending):
		_pending = normalized.duplicate()
	for index: int in range(_stimuli.size() - 1, -1, -1):
		if _stimulus_key(_stimuli[index]) == key:
			_stimuli.remove_at(index)
	_stimuli.append(normalized)
	while _stimuli.size() > STIMULUS_LIMIT:
		_stimuli.pop_front()


func notice(source: Object, world_position: Vector3, category: StringName,
		salience: float, lifetime: float = 1.0, body_turn_allowed: bool = true) -> void:
	submit({
		"source": weakref(source) if source != null else null,
		"world_position": world_position,
		"category": category,
		"salience": salience,
		"expires_at": _now() + maxf(0.05, lifetime),
		"body_turn_allowed": body_turn_allowed,
	})


func get_debug_info() -> Dictionary:
	return {
		"category": String(_active.get("category", &"")),
		"world_position": _active.get("world_position", Vector3.INF),
		"salience": float(_active.get("salience", 0.0)),
		"pending_category": String(_pending.get("category", &"")),
		"stimulus_count": _stimuli.size(),
		"angular_velocity": _angular_velocity,
	}


func _physics_process(delta: float) -> void:
	if _npc == null or not is_instance_valid(_npc):
		return
	var now: float = _now()
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN_INTERVAL
		_collect_automatic_stimuli(now)
		_prune(now)
		_arbitrate(now)
	_commit_pending(now)
	_update_stationary(delta)
	_update_body_turn(delta, now)


func _collect_automatic_stimuli(now: float) -> void:
	var task: Dictionary = _npc.call("get_attention_task_stimulus") \
		if _npc.has_method("get_attention_task_stimulus") else {}
	if not task.is_empty():
		task["expires_at"] = now + 0.45
		submit(task)

	var player: Node3D = _npc.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		player = _npc.get_tree().get_first_node_in_group("Player") as Node3D
	if player != null and player != _npc:
		var player_distance: float = _flat_distance(_npc.global_position, player.global_position)
		if player_distance <= PLAYER_NOTICE_RADIUS:
			notice(player, player.global_position, &"player_proximity",
				lerpf(0.78, 0.38, player_distance / PLAYER_NOTICE_RADIUS), 0.75, false)

	var nearest_mover: CharacterBody3D = null
	var nearest_distance: float = INF
	for node: Node in _npc.get_tree().get_nodes_in_group("npc"):
		if node == _npc or not node is CharacterBody3D:
			continue
		var other := node as CharacterBody3D
		if Vector2(other.velocity.x, other.velocity.z).length() < 0.2:
			continue
		var distance: float = _flat_distance(_npc.global_position, other.global_position)
		if distance <= RESIDENT_NOTICE_RADIUS and distance < nearest_distance:
			nearest_distance = distance
			nearest_mover = other
	if nearest_mover != null:
		notice(nearest_mover, nearest_mover.global_position, &"moving_resident",
			lerpf(0.60, 0.30, nearest_distance / RESIDENT_NOTICE_RADIUS), 0.4, false)

	if now >= _next_ambient_at:
		var angle: float = _rng.randf_range(-PI, PI)
		var distance: float = _rng.randf_range(2.0, 5.0)
		var offset := Vector3(sin(angle), 0.0, cos(angle)) * distance
		notice(null, _npc.global_position + offset, &"ambient_glance", 0.22,
			_rng.randf_range(0.8, 1.8), false)
		_next_ambient_at = now + _rng.randf_range(_ambient_interval_min, _ambient_interval_max)


func _prune(now: float) -> void:
	for index: int in range(_stimuli.size() - 1, -1, -1):
		var stimulus: Dictionary = _stimuli[index]
		var source_ref: WeakRef = stimulus.get("source") as WeakRef
		if float(stimulus.get("expires_at", 0.0)) <= now \
				or (source_ref != null and source_ref.get_ref() == null):
			_stimuli.remove_at(index)
	if not _active.is_empty() and float(_active.get("expires_at", 0.0)) <= now:
		_active.clear()
	if not _pending.is_empty():
		var pending_source: WeakRef = _pending.get("source") as WeakRef
		if float(_pending.get("expires_at", 0.0)) <= now \
				or (pending_source != null and pending_source.get_ref() == null):
			_pending.clear()


func _arbitrate(now: float) -> void:
	var best: Dictionary = {}
	var best_score: float = -INF
	for stimulus: Dictionary in _stimuli:
		var position: Vector3 = _resolved_position(stimulus)
		var distance: float = _flat_distance(_npc.global_position, position)
		var score: float = float(stimulus.get("salience", 0.0)) - minf(distance, 12.0) * 0.015
		if _stimulus_key(stimulus) == _stimulus_key(_active):
			score += 0.12
		if score > best_score:
			best_score = score
			best = stimulus
	if best.is_empty() or _stimulus_key(best) == _stimulus_key(_active):
		_pending.clear()
		return
	if _stimulus_key(best) != _stimulus_key(_pending):
		_pending = best.duplicate()
		_pending_ready_at = now + _reaction_delay * _rng.randf_range(0.8, 1.2)


func _commit_pending(now: float) -> void:
	if _pending.is_empty() or now < _pending_ready_at:
		return
	_active = _pending
	_active["world_position"] = _resolved_position(_active)
	_pending.clear()
	_active_since = now
	METRICS.increment(&"attention_target_changes")
	METRICS.record_event(&"attention_changed", _npc, {
		"category": String(_active.get("category", &"")),
		"salience": float(_active.get("salience", 0.0)),
	})
	if StringName(_active.get("category", &"")) == &"conversation_partner":
		_next_aversion_at = now + _rng.randf_range(2.2, 5.5)
	else:
		_next_aversion_at = INF


func _update_stationary(delta: float) -> void:
	var speed: float = Vector2(_npc.velocity.x, _npc.velocity.z).length()
	if speed <= STATIONARY_SPEED:
		_stationary_for += delta
	else:
		_stationary_for = 0.0


func _update_body_turn(delta: float, now: float) -> void:
	if _active.is_empty() or not bool(_active.get("body_turn_allowed", true)) \
			or _stationary_for < BODY_FOLLOW_DELAY or now - _active_since < BODY_FOLLOW_DELAY \
			or not _npc.has_method("can_attention_turn_body") \
			or not bool(_npc.call("can_attention_turn_body")):
		_angular_velocity = move_toward(_angular_velocity, 0.0, BODY_TURN_ACCELERATION * delta)
		return
	var target_position: Vector3 = _resolved_position(_active)
	var direction: Vector3 = target_position - _npc.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	var desired_yaw: float = atan2(-direction.x, -direction.z)
	var category: StringName = StringName(_active.get("category", &""))
	if category == &"conversation_partner":
		_update_glance_aversion(now)
		# Until the rig has an additive head/eye channel, aversion remains an
		# observed attention beat; swinging the whole torso away reads as fidgeting.
	var error: float = wrapf(desired_yaw - _npc.rotation.y, -PI, PI)
	var threshold: float = BODY_YAW_THRESHOLD
	if category == &"conversation_partner" or category == &"player_conversation":
		threshold = CONVERSATION_YAW_THRESHOLD
	elif category == &"task_target" or category == &"interaction_facing":
		threshold = TASK_YAW_THRESHOLD
	if absf(error) <= threshold:
		_angular_velocity = move_toward(_angular_velocity, 0.0, BODY_TURN_ACCELERATION * delta)
		return
	var desired_speed: float = clampf(error * 3.2, -BODY_TURN_MAX_SPEED, BODY_TURN_MAX_SPEED)
	_angular_velocity = move_toward(_angular_velocity, desired_speed, BODY_TURN_ACCELERATION * delta)
	var step: float = _angular_velocity * delta
	if absf(step) > absf(error):
		step = error
	_npc.rotation.y = wrapf(_npc.rotation.y + step, -PI, PI)
	METRICS.observe(&"attention_body_yaw_error_degrees", absf(rad_to_deg(error)),
		[5.0, 15.0, 30.0, 60.0, 90.0, 135.0, 180.0])


func _update_glance_aversion(now: float) -> void:
	if now < _next_aversion_at:
		return
	_aversion_sign = -1.0 if _rng.randf() < 0.5 else 1.0
	_aversion_until = now + _rng.randf_range(0.35, 0.9)
	_next_aversion_at = _aversion_until + _rng.randf_range(2.0, 5.0)
	METRICS.increment(&"attention_glance_aversions")


func _resolved_position(stimulus: Dictionary) -> Vector3:
	var source_ref: WeakRef = stimulus.get("source") as WeakRef
	var source: Object = source_ref.get_ref() if source_ref != null else null
	if source is Node3D:
		return (source as Node3D).global_position
	return stimulus.get("world_position", _npc.global_position)


func _stimulus_key(stimulus: Dictionary) -> String:
	if stimulus.is_empty():
		return ""
	var source_ref: WeakRef = stimulus.get("source") as WeakRef
	var source: Object = source_ref.get_ref() if source_ref != null else null
	var source_id: int = source.get_instance_id() if source != null else 0
	return "%s:%d" % [String(stimulus.get("category", &"")), source_id]


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
