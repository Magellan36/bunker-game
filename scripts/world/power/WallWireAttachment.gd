class_name WallWireAttachment
extends Node
## Local wall feed with a device-owned visual drop. Topology events coalesce.
## Horizontal tolerance is independent of mounting height.
const RADIUS: float = 1.0
const MAX_DROP: float = 3.5
var manager: PowerManager
var host: Node3D
var device_key: String
var _edge_id: String = ""
var _target_key: String = ""
var _queued: bool = false
var _refreshing: bool = false
var _visual: WireSegment

static func connector_position(device: Node3D) -> Vector3:
	if device.has_method("get_wall_wire_connector"):
		return device.call("get_wall_wire_connector")
	return device.global_position

static func update_visual(device: Node3D, previous_visual: Variant,
		target: Vector3, source_edge: String) -> WireSegment:
	## A freed Object cannot cross a typed Object argument boundary in GDScript.
	## Validate before casting, and never reuse a node waiting for deletion.
	var visual: WireSegment = null
	if is_instance_valid(previous_visual) and not previous_visual.is_queued_for_deletion():
		visual = previous_visual as WireSegment
	if visual == null:
		visual = WireSegment.new()
		visual.set_meta("_wall_feed_visual", true)
		device.add_child(visual)
		## WireSegment inherits current build visibility on creation/rebuild.
	var start: Vector3 = connector_position(device)
	var toward_wall: Vector3 = device.global_basis.z.normalized()
	var inset: float = 0.07
	if device.has_method("get_wall_wire_inset"):
		inset = float(device.call("get_wall_wire_inset"))
	var elbow: Vector3 = start + toward_wall * inset
	var foot := Vector3(elbow.x, target.y, elbow.z)
	visual.edge_id = source_edge
	visual.set_path(PackedVector3Array([start, elbow, foot, target]))
	return visual

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

func request_refresh() -> void:
	_queue_refresh("")

## Shared beneath-wire query for wall lights, terminals and breakers. Returns
## an exact physical-wire sample so logical feeds and breaker cuts attach to
## the same graph position without moving the wall-mounted visual.
static func find_candidate(host_position: Vector3, pm: PowerManager,
		radius: float = RADIUS) -> Dictionary:
	var best := Vector3.INF
	var best_distance: float = radius
	var best_id: String = "~"
	for edge: Dictionary in pm.get_wire_edges():
		if bool(edge.get("no_visual", false)):
			continue
		var a: Vector3 = pm.get_wire_node_pos(edge["node_a"])
		var b: Vector3 = pm.get_wire_node_pos(edge["node_b"])
		if not is_equal_approx(a.y, b.y) or a.y > host_position.y or host_position.y - a.y > MAX_DROP:
			continue
		var ab := Vector2(b.x - a.x, b.z - a.z)
		if ab.length_squared() < 0.000001:
			continue
		var ap := Vector2(host_position.x - a.x, host_position.z - a.z)
		var t: float = clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
		var steps: int = maxi(1, roundi(a.distance_to(b) / PowerManager.SNAP_GRID))
		if a.distance_to(b) <= PowerManager.SNAP_GRID * 1.5:
			steps = 1
		t = roundf(t * steps) / steps
		var candidate: Vector3 = a.lerp(b, t)
		var distance: float = Vector2(candidate.x - host_position.x,
			candidate.z - host_position.z).length()
		if distance < best_distance or (is_equal_approx(distance, best_distance)
				and String(edge["id"]) < best_id):
			best = candidate
			best_distance = distance
			best_id = edge["id"]
	return {} if not best.is_finite() else {
		"pos": best, "edge_id": best_id, "distance": best_distance}

func _refresh() -> void:
	_queued = false
	if not is_instance_valid(host) or host.is_queued_for_deletion() or not is_instance_valid(manager):
		return
	if not manager._wire_nodes.has(device_key):
		return
	var candidate_data: Dictionary = find_candidate(connector_position(host), manager)
	_refreshing = true
	manager.begin_bulk()
	if not candidate_data.is_empty():
		var best: Vector3 = candidate_data["pos"]
		var key: String = manager._graph._snap_key(best)
		if key != _target_key or not manager.has_wire_edge(_edge_id):
			if manager.has_wire_edge(_edge_id):
				manager.unregister_wire_edge(_edge_id)
			_target_key = manager.register_wire_node(best, "joint", "", true)
			if _target_key != device_key:
				_edge_id = manager.register_wire_edge(device_key, _target_key, null, true)
				manager.set_wire_edge_no_visual(_edge_id)
		_visual = update_visual(host, _visual, best, _edge_id)
	elif manager.has_wire_edge(_edge_id):
		manager.unregister_wire_edge(_edge_id)
		_edge_id = ""
		_target_key = ""
	if candidate_data.is_empty() and is_instance_valid(_visual):
		_visual.queue_free()
		_visual = null
	manager.end_bulk()
	_refreshing = false
