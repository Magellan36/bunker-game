extends Node
## WireDrawMode.gd
## Two-click wire placement tool. Integrated into BuildModeController as
## a sub-mode when TOOL_WIRE is selected.
##
## Flow:
##   Click 1 — snap-select a registered wire node near the cursor → set as source.
##             Ghost wire immediately anchors at source, tail follows mouse.
##   Move    — ghost wire stretches from source to cursor (or snaps to nearby node).
##   Click 2 — snap-select a second wire node → finalise: register edge in PM +
##              spawn WireSegment + charge $8/metre.
##   RMB     — cancel at any time.
##
## Wire nodes are positions registered with PowerManager.register_wire_node().
## We query PM.get_wire_nodes() (returns Array[Dictionary] with "pos" key)
## to find snappable nodes within SNAP_RADIUS of the cursor world hit.

## Emitted after a wire is successfully placed.
signal wire_placed(seg_node: Node3D, edge_id: String, cost: int, midpoint: Vector3)

## Emitted alongside wire_placed with the two wire node keys + their positions.
signal wire_nodes_connected(key_a: String, pos_a: Vector3, key_b: String, pos_b: Vector3)

## Emitted when the player presses E / Escape / RMB-in-phase-0 to fully exit
## the wire tool. BuildModeController listens and switches active tool back to 0.
signal wire_tool_exit_requested()

# ─── Debug ────────────────────────────────────────────────────────────────────
## Flip false to silence all [WireDrawMode] click/snap prints.
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Tuning ───────────────────────────────────────────────────────────────────
const SNAP_RADIUS:      float = 2.5    ## metres — auto-snap attraction radius; generous so generators/wires are always reachable
const FREE_JOINT_MIN:   float = 1.5    ## metres — only allow free joint creation when nearest node is farther than this
const COST_PER_M:       float = 8.0    ## dollars per metre
const WIRE_RADIUS:      float = 0.025  ## tube radius for ghost and real wire
const DOT_RADIUS:       float = 0.06   ## radius of the source / dest snap dot
const DOT_PULSE_SPEED:  float = 3.0    ## radians/sec for pulse animation

# ─── Ghost colours ────────────────────────────────────────────────────────────
const GHOST_COLOR:    Color = Color(0.35, 0.80, 1.0, 0.55)   ## free-drag wire
const SNAP_COLOR:     Color = Color(0.50, 1.00, 0.60, 0.75)  ## wire when snapped to dest
const DOT_SRC_COLOR:  Color = Color(0.50, 1.00, 0.60, 0.90)  ## source anchor dot
const DOT_DST_COLOR:  Color = Color(1.00, 0.90, 0.30, 0.90)  ## destination snap dot

# ─── External refs (set by BuildModeController before activating) ─────────────
var camera:      Camera3D    = null
var world_node:  Node        = null
var build_hud:   CanvasLayer = null
var ray_length:  float       = 50.0

# ─── State ────────────────────────────────────────────────────────────────────
var _phase:       int     = 0
var _source_key:  String  = ""
var _source_pos:  Vector3 = Vector3.ZERO

## Ghost visuals — NOT in the "wire_segment" group so group broadcasts
## (e.g. hide-on-exit-build-mode) never accidentally kill them mid-drag.
var _ghost_wire:   Node3D = null
var _dot_src:      MeshInstance3D = null
var _dot_dst:      MeshInstance3D = null
var _pulse_t:      float  = 0.0

## Hover prompt — Label3D shown above snappable nodes in phase 0 (idle) and phase 1 (source picked).
var _hover_label:  Label3D = null
var _hover_key:    String  = ""

## Live cost label — Label3D floating at wire midpoint during phase 1 drag.
## Shows the running dollar cost as the player moves the cursor.
var _cost_label:   Label3D = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_process(false)

# ─── Activation ──────────────────────────────────────────────────────────────
func activate() -> void:
	## Null all visual-state vars that deactivate() queue_freed.
	## Without this, on second entry the stale (freed) refs survive and
	## _update_ghost_wire / _update_hover_label skip their creation branches,
	## leaving the mode visually dead until a new node is hovered/clicked.
	_ghost_wire  = null
	_dot_src     = null
	_dot_dst     = null
	_hover_label = null
	_hover_key   = ""
	_cost_label  = null
	_phase       = 0
	_source_key  = ""
	_pulse_t     = 0.0
	set_process(true)

func deactivate() -> void:
	_cancel()
	set_process(false)

# ─── Process — update ghost every frame ──────────────────────────────────────
func _process(delta: float) -> void:
	if camera == null:
		return

	var cursor_world: Vector3 = _get_cursor_world_pos()

	if _phase == 0:
		_clear_ghost()
		_clear_cost_label()
		if cursor_world != Vector3.ZERO:
			## Auto-snap cursor to nearest node for hover highlight — makes it
			## visually clear which node will be selected on click.
			var hover: Dictionary = _get_nearest_wire_node(cursor_world, "")
			_update_hover_label(hover)
		else:
			_update_hover_label({})
		return

	if cursor_world == Vector3.ZERO:
		return

	# Find nearest snappable destination node.
	# The cursor "effective position" is snapped to the nearest node when within
	# SNAP_RADIUS, so the ghost wire locks onto it before the player clicks.
	var nearest: Dictionary = _get_nearest_wire_node(cursor_world, _source_key)
	var snapped:  bool      = not nearest.is_empty()
	## Snap to existing node if within radius, otherwise use grid position.
	var dest_pos: Vector3   = nearest["pos"] if snapped else _grid_snap(cursor_world)

	# Update ghost wire
	_update_ghost_wire(_source_pos, dest_pos, snapped)

	# Pulse animation for dots
	_pulse_t += delta * DOT_PULSE_SPEED
	var pulse_scale: float = 1.0 + 0.18 * sin(_pulse_t)

	# Source dot — stays fixed at source
	if _dot_src == null:
		_dot_src = _make_dot(DOT_SRC_COLOR)
	_dot_src.global_position = _source_pos
	_dot_src.scale           = Vector3.ONE * pulse_scale

	# Destination dot — only show when snapped to a valid node
	if snapped:
		if _dot_dst == null:
			_dot_dst = _make_dot(DOT_DST_COLOR)
		_dot_dst.global_position = dest_pos
		_dot_dst.scale           = Vector3.ONE * (pulse_scale * 0.85)
		_dot_dst.visible         = true
		_update_hover_label(nearest)
	else:
		if _dot_dst != null:
			_dot_dst.visible = false
		_update_hover_label({})

	# Live cost label at wire midpoint
	var midpoint: Vector3 = (_source_pos + dest_pos) * 0.5
	var dist: float = _source_pos.distance_to(dest_pos)
	var cost: int   = int(ceil(dist * COST_PER_M))
	_update_cost_label(midpoint, cost)

# ─── Input (called by BuildModeController._unhandled_input) ──────────────────
func handle_input(event: InputEvent) -> bool:
	## ── Keyboard: E or Escape always exit the wire tool entirely ─────────────
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.keycode == KEY_ESCAPE:
			_cancel()
			wire_tool_exit_requested.emit()
			return true

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _phase == 0:
					return _try_pick_source()
				elif _phase == 1:
					return _try_pick_dest()
			MOUSE_BUTTON_RIGHT:
				if _phase > 0:
					## Mid-draw cancel — go back to phase 0 (ready for next wire)
					_cancel()
					return true
				else:
					## Phase 0 RMB — exit wire tool entirely, return cursor to player
					wire_tool_exit_requested.emit()
					return true
	return false

# ─── Phase 0: pick source node ───────────────────────────────────────────────
func _try_pick_source() -> bool:
	var cursor_world: Vector3 = _get_cursor_world_pos()
	if cursor_world == Vector3.ZERO:
		return false

	## Prefer snapping to an existing PM wire node within SNAP_RADIUS.
	## IMPORTANT: if ANY node exists within SNAP_RADIUS, always snap to it —
	## never create a free joint, which would form a new disconnected zone.
	var nearest: Dictionary = _get_nearest_wire_node(cursor_world, "")
	if not nearest.is_empty():
		_source_key = nearest["key"]
		_source_pos = nearest["pos"]
		_wdbg("[WireDrawMode] Phase0: snapped to existing node key=%s pos=%s" % [_source_key, _source_pos])
	else:
		## No existing node within SNAP_RADIUS — safe to create a free joint
		## only if we're genuinely far from everything (> FREE_JOINT_MIN).
		## This prevents accidentally starting a new isolated zone when clicking
		## just outside snap range of a generator or existing wire.
		var any_nearby: Dictionary = _get_nearest_wire_node_wide(cursor_world, "", FREE_JOINT_MIN)
		if not any_nearby.is_empty():
			## Too close to an existing node but outside SNAP_RADIUS — snap anyway
			## with a helpful hint so the player knows what happened.
			_source_key = any_nearby["key"]
			_source_pos = any_nearby["pos"]
			_wdbg("[WireDrawMode] Phase0: forced-snap to nearby node key=%s (within FREE_JOINT_MIN)" % _source_key)
		else:
			## Genuinely open space — create a free joint.
			## But first check for an existing node at the same XZ (different Y)
			## so we don't accidentally create a disconnected zone.
			var grid_pos: Vector3 = _grid_snap(cursor_world)
			var xz_match: Dictionary = _find_existing_node_at_xz(grid_pos)
			if not xz_match.is_empty():
				_source_key = xz_match["key"]
				_source_pos = xz_match["pos"]
				_wdbg("[WireDrawMode] Phase0: XZ-matched existing node key=%s (Y-diff absorbed)" % _source_key)
			else:
				_source_key = _make_free_key(grid_pos)
				_source_pos = grid_pos
				var pm: PowerManager = _get_pm()
				if pm != null:
					pm.register_wire_node(grid_pos, "joint", "")
				_wdbg("[WireDrawMode] Phase0: free joint at grid_pos=%s key=%s" % [grid_pos, _source_key])

	_phase   = 1
	_pulse_t = 0.0
	return true

# ─── Phase 1: pick destination node and place wire ───────────────────────────
func _try_pick_dest() -> bool:
	var cursor_world: Vector3 = _get_cursor_world_pos()
	if cursor_world == Vector3.ZERO:
		return false

	var dest_key: String
	var dest_pos: Vector3

	var nearest: Dictionary = _get_nearest_wire_node(cursor_world, _source_key)
	if not nearest.is_empty():
		dest_key = nearest["key"]
		dest_pos = nearest["pos"]
		_wdbg("[WireDrawMode] Phase1: snapped dest to existing node key=%s pos=%s" % [dest_key, dest_pos])
	else:
		## Check for nodes within FREE_JOINT_MIN — force-snap rather than orphan.
		var any_nearby: Dictionary = _get_nearest_wire_node_wide(cursor_world, _source_key, FREE_JOINT_MIN)
		if not any_nearby.is_empty():
			dest_key = any_nearby["key"]
			dest_pos = any_nearby["pos"]
			_wdbg("[WireDrawMode] Phase1: forced-snap dest to nearby node key=%s" % dest_key)
		else:
			## Genuinely open space — create a free joint.
			## But first check for an existing node at the same XZ (different Y)
			## to avoid creating a disconnected zone.
			var grid_pos: Vector3 = _grid_snap(cursor_world)
			var xz_match: Dictionary = _find_existing_node_at_xz(grid_pos)
			if not xz_match.is_empty():
				dest_key = xz_match["key"]
				dest_pos = xz_match["pos"]
				_wdbg("[WireDrawMode] Phase1: XZ-matched existing dest node key=%s (Y-diff absorbed)" % dest_key)
			else:
				dest_key = _make_free_key(grid_pos)
				dest_pos = grid_pos
				var pm2: PowerManager = _get_pm()
				if pm2 != null:
					pm2.register_wire_node(grid_pos, "joint", "")
				_wdbg("[WireDrawMode] Phase1: free dest joint at grid_pos=%s key=%s" % [grid_pos, dest_key])

	if dest_key == _source_key:
		_show_warning("Select a different node")
		return true

	## ── Duplicate wire check ──────────────────────────────────────────────
	## Build the same canonical edge_id PM would produce and check if it exists.
	var pm_check: PowerManager = _get_pm()
	if pm_check != null:
		var parts_check: Array[String] = [_source_key, dest_key]
		parts_check.sort()
		var would_be_id: String = "e_%s__%s" % [parts_check[0], parts_check[1]]
		var existing_edges: Dictionary = pm_check.get("_wire_edges") if pm_check.get("_wire_edges") != null else {}
		if existing_edges.has(would_be_id):
			_show_warning("A wire is already placed there")
			_wdbg("[WireDrawMode] Blocked duplicate wire: %s" % would_be_id)
			return true

	# Cost check
	var dist: float = _source_pos.distance_to(dest_pos)
	var cost: int   = int(ceil(dist * COST_PER_M))

	if world_node != null and world_node.has_method("get_cash"):
		if world_node.get_cash() < cost:
			_show_warning("Not enough cash — need $%d (%dm × $%.0f/m)" % [cost, int(dist), COST_PER_M])
			return true

	# Spend cash
	if world_node != null and world_node.has_method("spend_cash"):
		world_node.spend_cash(cost)

	# Register edge in PowerManager — no capacity_w arg in v3.1
	var pm: PowerManager = _get_pm()
	var edge_id: String = ""
	if pm != null:
		edge_id = pm.register_wire_edge(_source_key, dest_key)

	# Spawn permanent WireSegment
	var seg: Node3D = _spawn_wire_segment(_source_pos, dest_pos, edge_id)

	# Notify BuildModeController
	var midpoint: Vector3 = (_source_pos + dest_pos) * 0.5
	wire_placed.emit(seg, edge_id, cost, midpoint)
	wire_nodes_connected.emit(_source_key, _source_pos, dest_key, dest_pos)

	# Reset to idle
	_clear_ghost()
	_clear_cost_label()
	_phase      = 0
	_source_key = ""
	return true

# ─── Ghost wire ──────────────────────────────────────────────────────────────
func _update_ghost_wire(from: Vector3, to: Vector3, snapped: bool) -> void:
	if _ghost_wire == null:
		_ghost_wire = WireSegment.make_ghost_wire(_get_scene_root(), from, to)
	else:
		if _ghost_wire.has_method("set_endpoints"):
			_ghost_wire.set_endpoints(from, to)

	_ghost_wire.visible = true

	var mat: StandardMaterial3D = _ghost_wire.get("_material")
	if mat != null:
		mat.albedo_color = SNAP_COLOR if snapped else GHOST_COLOR

func _clear_ghost() -> void:
	if _ghost_wire != null:
		_ghost_wire.queue_free()
		_ghost_wire = null
	if _dot_src != null:
		_dot_src.queue_free()
		_dot_src = null
	if _dot_dst != null:
		_dot_dst.queue_free()
		_dot_dst = null
	## NOTE: hover label is NOT cleared here — _process manages it directly.
	## Calling _update_hover_label({}) here resets _hover_key every frame,
	## causing a new Label3D to be created and destroyed each frame →
	## GPU resource churn → RID=0 free → D3D12 DEVICE_REMOVED crash.

# ─── Hover label ──────────────────────────────────────────────────────────────
## Show/hide a billboard Label3D above a snappable node.
## Pass empty dict to hide.
func _update_hover_label(node_data: Dictionary) -> void:
	## Guard: _process may fire one final frame after deactivate/queue_free.
	if not is_inside_tree():
		return
	var key: String = node_data.get("key", "")

	if key.is_empty():
		if _hover_label != null:
			_hover_label.queue_free()
			_hover_label = null
		_hover_key = ""
		return

	if key == _hover_key and _hover_label != null:
		return

	if _hover_label != null:
		_hover_label.queue_free()
		_hover_label = null

	var pos: Vector3    = node_data.get("pos", Vector3.ZERO)
	var text: String    = _get_hover_text(node_data)

	var label: Label3D = Label3D.new()
	label.text             = text
	label.font_size        = 28
	label.modulate         = Color(1.0, 1.0, 1.0, 0.92)
	label.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test    = true
	label.render_priority  = 3
	label.double_sided     = true
	label.fixed_size       = false
	label.pixel_size       = 0.005
	label.outline_size     = 6
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	## add_child BEFORE setting global_position — node must be in the tree
	## so get_global_transform() is valid; setting position before add_child
	## triggers a "!is_inside_tree()" error and returns identity transform.
	_get_scene_root().add_child(label)
	label.global_position  = pos + Vector3(0.0, 0.85, 0.0)
	_hover_label = label
	_hover_key   = key

## Returns a human-readable label for a wire node based on role + scene node.
## Now includes watt draw for consumer nodes so player knows the device cost.
func _get_hover_text(node_data: Dictionary) -> String:
	var role:      String = node_data.get("role", "joint")
	var device_id: String = node_data.get("device_id", "")

	if not device_id.is_empty():
		## Query PowerManager for watt draw if this is a consumer node.
		var watts_str: String = ""
		if role == "consumer":
			var pm: PowerManager = _get_pm()
			if pm != null:
				var w: float = pm.get_consumer_watts(device_id)
				if w > 0.0:
					watts_str = "  (%dW)" % int(w)

		## Generators
		for gen: Node in get_tree().get_nodes_in_group("generator"):
			if str(gen.get_instance_id()) == device_id:
				if gen.has_method("get_interact_prompt"):
					return gen.get_interact_prompt()
				return "Generator"
		## Wall lights
		for lt: Node in get_tree().get_nodes_in_group("wall_lights"):
			if str(lt.get_instance_id()) == device_id:
				if lt.has_method("get_interact_prompt"):
					return lt.get_interact_prompt() + watts_str
				return "Wall Light" + watts_str
		## Generic interactable
		for obj: Node in get_tree().get_nodes_in_group("interactable"):
			if str(obj.get_instance_id()) == device_id:
				if obj.has_method("get_interact_prompt"):
					return obj.get_interact_prompt() + watts_str
				return obj.name + watts_str

		## Consumer with no matched group node — show watts alone if available
		if not watts_str.is_empty():
			return _role_fallback(role) + watts_str

	## Role-based fallbacks
	return _role_fallback(role)


func _role_fallback(role: String) -> String:
	match role:
		"generator": return "Generator"
		"consumer":  return "Consumer"
		"battery":   return "Battery"
		"breaker":   return "Breaker"
		_:           return "Wire Node"


# ─── Live cost label ──────────────────────────────────────────────────────────
## Shows a floating "$X" label at the wire midpoint during phase 1 drag.
## Updated every frame to reflect the current drag distance.
func _update_cost_label(midpoint: Vector3, cost: int) -> void:
	if _cost_label == null:
		var lbl: Label3D = Label3D.new()
		lbl.font_size        = 28
		lbl.billboard        = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test    = true
		lbl.render_priority  = 5
		lbl.double_sided     = true
		lbl.fixed_size       = false
		lbl.pixel_size       = 0.005
		lbl.outline_size     = 6
		lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.90)
		lbl.modulate         = Color(1.0, 0.88, 0.15, 1.0)   ## bright yellow
		## Parent to world_node (MainWorld) so it lives in the 3D scene graph.
		## Fallback to scene root if world_node is not set yet.
		var parent: Node = world_node if world_node != null else _get_scene_root()
		parent.add_child(lbl)
		_cost_label = lbl

	_cost_label.text            = "$%d" % cost
	## Raise 0.7 m above midpoint so it clears the wire and any floor geometry.
	_cost_label.global_position = midpoint + Vector3(0.0, 0.70, 0.0)
	_cost_label.visible         = true


func _clear_cost_label() -> void:
	if _cost_label != null:
		_cost_label.queue_free()
		_cost_label = null


# ─── Snap dot factory ─────────────────────────────────────────────────────────
func _make_dot(color: Color) -> MeshInstance3D:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = DOT_RADIUS
	sphere.height = DOT_RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color    = color
	mat.no_depth_test   = true
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 2

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = sphere
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_get_scene_root().add_child(mi)
	mi.visible = true
	return mi

# ─── Permanent wire segment ───────────────────────────────────────────────────
func _spawn_wire_segment(from: Vector3, to: Vector3, edge_id: String) -> Node3D:
	var wire_script: GDScript = load("res://scripts/world/power/WireSegment.gd")
	var seg: Node3D = Node3D.new()
	if wire_script != null:
		seg.set_script(wire_script)
	seg.name = "WireSegment"

	_get_scene_root().add_child(seg)

	if seg.has_method("set_endpoints"):
		seg.set_endpoints(from, to)
	if "edge_id" in seg:
		seg.edge_id = edge_id

	seg.visible = true
	return seg

# ─── Raycasting ──────────────────────────────────────────────────────────────
func _get_cursor_world_pos() -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var vp: Viewport = camera.get_viewport()
	if vp == null:
		return Vector3.ZERO
	var mouse: Vector2 = vp.get_mouse_position()
	var from: Vector3  = camera.project_ray_origin(mouse)
	var dir: Vector3   = camera.project_ray_normal(mouse)
	var to: Vector3    = from + dir * ray_length

	var space: PhysicsDirectSpaceState3D   = camera.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	var result: Dictionary = space.intersect_ray(query)
	if result.is_empty():
		var t: float = (1.0 - from.y) / max(abs(dir.y), 0.0001)
		if t > 0.0:
			return from + dir * t
		return Vector3.ZERO
	return result["position"]

# ─── Wire node query ─────────────────────────────────────────────────────────
func _get_nearest_wire_node(world_pos: Vector3, exclude_key: String) -> Dictionary:
	var pm: PowerManager = _get_pm()
	if pm == null:
		return {}

	var nodes: Array = pm.get_wire_nodes()
	var best_dist: float = SNAP_RADIUS
	var best: Dictionary = {}

	for node_data: Dictionary in nodes:
		var k: String  = node_data.get("key", "")
		var p: Vector3 = node_data.get("pos", Vector3.ZERO)
		if k == exclude_key:
			continue
		var d: float = Vector2(world_pos.x, world_pos.z).distance_to(Vector2(p.x, p.z))
		if d < best_dist:
			best_dist = d
			best = node_data

	return best

## Wider search — same as _get_nearest_wire_node but uses a custom radius
## instead of SNAP_RADIUS. Used for forced-snap / anti-orphan checks.
func _get_nearest_wire_node_wide(world_pos: Vector3, exclude_key: String, radius: float) -> Dictionary:
	var pm: PowerManager = _get_pm()
	if pm == null:
		return {}

	var nodes: Array = pm.get_wire_nodes()
	var best_dist: float = radius
	var best: Dictionary = {}

	for node_data: Dictionary in nodes:
		var k: String  = node_data.get("key", "")
		var p: Vector3 = node_data.get("pos", Vector3.ZERO)
		if k == exclude_key:
			continue
		var d: float = Vector2(world_pos.x, world_pos.z).distance_to(Vector2(p.x, p.z))
		if d < best_dist:
			best_dist = d
			best = node_data

	return best

# ─── Helpers ─────────────────────────────────────────────────────────────────
func _get_pm() -> PowerManager:
	return get_tree().get_first_node_in_group("power_manager") as PowerManager

func _get_scene_root() -> Node3D:
	var root: Node = get_tree().get_root()
	for child: Node in root.get_children():
		if child is Node3D:
			return child as Node3D
	return root as Node3D

func _show_warning(msg: String) -> void:
	if world_node != null:
		var main_hud: Node = world_node.get_node_or_null("HUD")
		if main_hud != null and main_hud.has_method("show_soft_warning"):
			main_hud.show_soft_warning(msg)
			return
	push_warning("[WireDrawMode] " + msg)

func _cancel() -> void:
	_clear_ghost()
	_clear_cost_label()
	_phase      = 0
	_source_key = ""

# ─── Grid snap helpers ────────────────────────────────────────────────────────
const _WIRE_GRID: float = 0.25   ## must match PowerManager.SNAP_GRID
## Canonical wire height — must match MainWorld._rebuild_auto_wires WIRE_Y.
## All free joints and player wire endpoints are clamped to this Y so their
## snap keys match the auto-wire nodes (which are always at Y=1.0).
## Without this, a cursor raycast hitting the floor (Y≈0) produces a key like
## "X,0,Z" that never merges with an existing "X,4,Z" auto-wire node, causing
## spurious new zones every time the player places a wire mid-run.
const _WIRE_Y: float = 1.0

## Snap a world position to the 0.25 m grid.
## Y is ALWAYS clamped to _WIRE_Y (canonical wire height) so that free joints
## created here share the same snap key as auto-wire nodes registered by
## MainWorld at Y=1.0.  Keeping the raw raycast Y was the root cause of the
## "new zone on every wire placement" bug.
func _grid_snap(pos: Vector3) -> Vector3:
	return Vector3(
		roundf(pos.x / _WIRE_GRID) * _WIRE_GRID,
		_WIRE_Y,
		roundf(pos.z / _WIRE_GRID) * _WIRE_GRID
	)

## Build the same canonical snap key PM uses, without needing PM itself.
## Matches PowerManager._snap_key() — "%d,%d,%d" with rounded grid indices.
func _make_free_key(pos: Vector3) -> String:
	var ix: int = roundi(pos.x / _WIRE_GRID)
	var iy: int = roundi(pos.y / _WIRE_GRID)
	var iz: int = roundi(pos.z / _WIRE_GRID)
	return "%d,%d,%d" % [ix, iy, iz]

## Look for an existing PM wire node at the same XZ position as `pos`,
## regardless of Y.  If found, return that node's key and position so that
## the new wire connects to the existing grid rather than creating a
## disconnected free joint at a different Y level.
## Returns {} if no match found.
func _find_existing_node_at_xz(pos: Vector3) -> Dictionary:
	var pm: PowerManager = _get_pm()
	if pm == null:
		return {}
	var snap_x: float = roundf(pos.x / _WIRE_GRID) * _WIRE_GRID
	var snap_z: float = roundf(pos.z / _WIRE_GRID) * _WIRE_GRID
	for node_data: Dictionary in (pm.get_wire_nodes() as Array):
		var np: Vector3 = node_data.get("pos", Vector3.ZERO)
		if absf(np.x - snap_x) < _WIRE_GRID * 0.5 and absf(np.z - snap_z) < _WIRE_GRID * 0.5:
			return node_data
	return {}
