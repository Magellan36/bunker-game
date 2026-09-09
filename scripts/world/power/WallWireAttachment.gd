class_name WallWireAttachment
extends Node
## Invisible local wall feed. Topology events coalesce; no per-frame graph scan.
const RADIUS: float = 0.75
var manager: PowerManager
var host: Node3D
var device_key: String
var _edge_id: String = ""
var _target_key: String = ""
var _queued: bool = false
var _refreshing: bool = false

func bind(device: Node3D, pm: PowerManager, key: String) -> void:
	host = device
	manager = pm
	device_key = key
	manager._wire_nodes[key]["wall_feed"] = true
	manager.wire_edge_registered.connect(_queue_refresh)
	manager.wire_edge_unregistered.connect(_queue_refresh)
	_queue_refresh("")

func _queue_refresh(_changed: String) -> void:
	if _queued or _refreshing or not is_inside_tree():
		return
	_queued = true
	_refresh.call_deferred()

func _refresh() -> void:
	_queued = false
	if not is_instance_valid(host) or host.is_queued_for_deletion() or not is_instance_valid(manager):
		return
	if not manager._wire_nodes.has(device_key):
		return
	var best := Vector3.INF
	var best_distance: float = RADIUS
	var best_id: String = "~"
	for edge: Dictionary in manager.get_wire_edges():
		if bool(edge.get("no_visual", false)):
			continue
		var a: Vector3 = manager.get_wire_node_pos(edge["node_a"])
		var b: Vector3 = manager.get_wire_node_pos(edge["node_b"])
		if not is_equal_approx(a.y, b.y) or a.y > host.global_position.y:
			continue
		var ab := Vector2(b.x - a.x, b.z - a.z)
		if ab.length_squared() < 0.000001:
			continue
		var ap := Vector2(host.global_position.x - a.x, host.global_position.z - a.z)
		var t: float = clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
		# Choose a real snap sample on this run rather than rounding a
		# diagonal projection off its line and creating a disconnected tap.
		var steps: int = maxi(1, roundi(a.distance_to(b) / PowerManager.SNAP_GRID))
		if a.distance_to(b) <= PowerManager.SNAP_GRID * 1.5:
			steps = 1
		t = roundf(t * steps) / steps
		var candidate: Vector3 = a.lerp(b, t)
		var distance: float = Vector2(candidate.x - host.global_position.x, candidate.z - host.global_position.z).length()
		if distance < best_distance or (is_equal_approx(distance, best_distance) and String(edge["id"]) < best_id):
			best = candidate
			best_distance = distance
			best_id = edge["id"]
	_refreshing = true
	manager.begin_bulk()
	if best.is_finite():
		var key: String = manager._graph._snap_key(best)
		if key != _target_key or not manager.has_wire_edge(_edge_id):
			if manager.has_wire_edge(_edge_id):
				manager.unregister_wire_edge(_edge_id)
			_target_key = manager.register_wire_node(best, "joint", "", true)
			if _target_key != device_key:
				_edge_id = manager.register_wire_edge(device_key, _target_key, null, true)
				manager.set_wire_edge_no_visual(_edge_id)
	elif manager.has_wire_edge(_edge_id):
		manager.unregister_wire_edge(_edge_id)
		_edge_id = ""
		_target_key = ""
	manager.end_bulk()
	_refreshing = false
