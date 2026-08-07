extends RefCounted
class_name InteractionProximityScan
## InteractionProximityScan.gd  —  InteractionSystem slice, Phase 1 (Aug 2026)
## ─────────────────────────────────────────────────────────────────────────
## Two "find nearest thing" filter chains that were independently
## duplicated across up to 9 places in InteractionSystem.gd:
##
## Pattern A (nearest_body_in_group): scan detect_area.get_overlapping_bodies(),
## skip the currently-held item, skip "shelved", skip frozen RigidBody3D,
## optionally apply a predicate, keep closest by distance_to(). Was
## duplicated in _try_pickup(), _nearest_pickup_distance(),
## _try_add_nearest_to_basket(), _try_add_nearest_to_cookpot(), and
## _nearest_group_storable_distance().
##
## Pattern B (nearest_in_group): scan a scene-tree group by name (the
## standard workaround for Jolt's Area3D.get_overlapping_bodies() missing
## StaticBody3D, used throughout this file already), apply an optional
## predicate, keep closest within max_dist. Was duplicated in
## _find_nearest_open_stove(), _find_nearest_stove_with_pot(),
## _find_nearest_npc(), and _find_nearest_ready_pot().
##
## Same _owner back-reference pattern as WallSnapHelpers.gd/PowerGraph.gd —
## nothing is moved off InteractionSystem, this reaches into _owner.detect_area/
## _owner.held_item/_owner.player/_owner.get_tree() rather than owning copies.
##
## Deliberately NOT generalized here: _nearest_shelf() (flat-XZ distance,
## the one outlier — see InteractionSystem.gd's own comment on it) and the
## CASE 2 prompt-loop's static scan (has set_player_in_range() side effects,
## not a pure query) — both stay where they are.

var _owner: InteractionSystem = null

func _init(owner: InteractionSystem) -> void:
	_owner = owner

## Pattern A. Nearest RigidBody3D in detect_area overlap belonging to
## group_name, skipping the held item / shelved / frozen. predicate, if
## given, is called as predicate.call(body) and must return true to keep
## the candidate. Returns null if nothing qualifies.
func nearest_body_in_group(group_name: String, predicate: Callable = Callable()) -> Node3D:
	var bodies: Array        = _owner.detect_area.get_overlapping_bodies()
	var closest: Node3D      = null
	var closest_dist: float  = INF
	for body in bodies:
		if body == _owner.held_item:
			continue
		if not body.is_in_group(group_name):
			continue
		if body.is_in_group("shelved"):
			continue
		if body is RigidBody3D and (body as RigidBody3D).freeze:
			continue
		if predicate.is_valid() and not predicate.call(body):
			continue
		var d: float = (body as Node3D).global_position.distance_to(_owner.player.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = body
	return closest

## Distance-only twin of nearest_body_in_group(). Returns INF if nothing
## qualifies — safe to use directly in a "strictly closer than" comparison.
func nearest_distance_in_group(group_name: String, predicate: Callable = Callable()) -> float:
	var body: Node3D = nearest_body_in_group(group_name, predicate)
	if body == null:
		return INF
	return body.global_position.distance_to(_owner.player.global_position)

## Pattern B. Nearest node in scene-tree group_name (full 3D distance from
## _owner.player), no further than max_dist, additionally passing predicate
## if given (predicate.call(node) -> bool). StaticBody3D-safe — this is the
## group-scan workaround already used throughout InteractionSystem.gd for
## nodes Area3D can't reliably see.
func nearest_in_group(group_name: String, max_dist: float, predicate: Callable = Callable()) -> Node:
	var closest: Node        = null
	var closest_dist: float  = max_dist
	var player_pos: Vector3  = _owner.player.global_position
	for node: Node in _owner.get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		if predicate.is_valid() and not predicate.call(node):
			continue
		var d: float = (node as Node3D).global_position.distance_to(player_pos)
		if d < closest_dist:
			closest_dist = d
			closest = node
	return closest