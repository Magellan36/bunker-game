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
## to find snappable nodes within SNAP_PIXELS of the cursor on screen.

## Emitted after a wire is successfully placed.
signal wire_placed(seg_node: Node3D, edge_id: String, cost: int, midpoint: Vector3)

## Emitted alongside wire_placed with the two wire node keys + their positions.
signal wire_nodes_connected(key_a: String, pos_a: Vector3, key_b: String, pos_b: Vector3)

## Emitted when the player presses E / Escape / RMB-in-phase-0 to fully exit
## the wire tool. BuildModeController listens and switches active tool back to 0.
signal wire_tool_exit_requested()

# ─── Debug ────────────────────────────────────────────────────────────────────
## Flip false to silence all [WireDrawMode] click/snap prints.
const WIRE_DEBUG: bool = false
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Tuning ───────────────────────────────────────────────────────────────────
const SNAP_PIXELS: float = 18.0  ## includes elevated connectors in screen space
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
var _source_existing: bool = false

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
		if cursor_world.is_finite():
			## Auto-snap cursor to nearest node for hover highlight — makes it
			## visually clear which node will be selected on click.
			var hover: Dictionary = _get_nearest_wire_node(cursor_world, "")
			_update_hover_label(hover)
		else:
			_update_hover_label({})
		return

	if not cursor_world.is_finite():
		return

	# Find nearest snappable destination node.
	# The cursor "effective position" is snapped to the nearest node when within
	# SNAP_PIXELS, so the ghost wire locks onto it before the player clicks.
	var nearest: Dictionary = _get_nearest_wire_node(cursor_world, _source_key)
	var snapped:  bool      = not nearest.is_empty()
	## Snap to existing node if within radius, otherwise use grid position.
	var dest_pos: Vector3   = nearest["pos"] if snapped else _grid_snap(cursor_world)

	# Update ghost wire
	_update_ghost_wire(_source_pos, dest_pos, snapped)

	# Pulse animation for dots
	_pulse_t += delta * DOT_PULSE_SPEED
	var pulse_scale: float = 1.0 if UIMotion.reduced() else 1.0 + 0.06 * sin(_pulse_t)

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
	var dist: float = WireRoute.length(WireRoute.points(_source_pos, dest_pos))
	var cost: int   = int(ceil(dist * COST_PER_M))
	_update_cost_label(midpoint, cost)

# ─── Input (called by BuildModeController._unhandled_input) ──────────────────
func handle_input(event: InputEvent) -> bool:
	## ── Keyboard: E or Escape always exit the wire tool entirely ─────────────
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.keycode == KEY_ESCAPE:
			## Cancels the in-progress placement and stays IN the wire tool
			## (July 2026 correction — a prior pass wrongly made this exit
			## all the way back to Construct tool; Brannon flagged that E
			## "isn't working" because it was really just leaving wire mode
			## entirely, which was never the ask). Does NOT emit
			## wire_tool_exit_requested — that signal now only fires from
			## an actual tool-switch elsewhere (toolbar button).
			_cancel()
			return true

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if _phase == 0:
					return _try_pick_source()
				elif _phase == 1:
					return _try_pick_dest()
			MOUSE_BUTTON_RIGHT:
				## Same correction as E/Escape above — cancels the current
				## drag/placement, stays in the wire tool. No tool-exit.
				_cancel()
				return true
	return false

# ─── Phase 0: pick source node ───────────────────────────────────────────────
func _try_pick_source() -> bool:
	var cursor: Vector3 = _get_cursor_world_pos()
	if not cursor.is_finite():
		return false
	var nearest: Dictionary = _get_nearest_wire_node(cursor, "")
	_source_existing = not nearest.is_empty()
	_source_pos = nearest["pos"] if _source_existing else _grid_snap(cursor)
	_source_key = nearest["key"] if _source_existing else _make_free_key(_source_pos)
	_phase = 1
	_pulse_t = 0.0
	return true

func _try_pick_dest() -> bool:
	var cursor: Vector3 = _get_cursor_world_pos()
	var pm: PowerManager = _get_pm()
	if not cursor.is_finite() or pm == null:
		return false
	if _source_existing and not pm._wire_nodes.has(_source_key):
		_show_warning("The starting connection was removed")
		_cancel()
		return true
	var nearest: Dictionary = _get_nearest_wire_node(cursor, _source_key)
	var destination: Vector3 = nearest["pos"] if not nearest.is_empty() else _grid_snap(cursor)
	var path: PackedVector3Array = WireRoute.points(_source_pos, destination)
	if path.size() < 2:
		_show_warning("Select a different connection")
		return true
	var keys: Array[String] = []
	for point: Vector3 in path:
		keys.append(_make_free_key(point))
	keys[0] = _source_key
	if not nearest.is_empty():
		keys[-1] = nearest["key"]
	for i: int in range(1, keys.size()):
		if keys[i - 1] == keys[i] or pm.has_wire_edge(WireRoute.edge_id(keys[i - 1], keys[i])):
			_show_warning("A wire already occupies part of this route")
			return true
	for edge: Dictionary in pm.get_wire_edges():
		if bool(edge.get("no_visual", false)):
			continue
		for i: int in range(1, path.size()):
			if WireRoute.overlaps(path[i - 1], path[i], pm.get_wire_node_pos(edge["node_a"]), pm.get_wire_node_pos(edge["node_b"])):
				_show_warning("A wire already occupies part of this route")
				return true
	var cost: int = ceili(WireRoute.length(path) * COST_PER_M)
	if world_node == null or not world_node.spend_cash(cost):
		_show_warning("Not enough cash for this wire")
		return true
	var color_snapshot: Dictionary = pm.snapshot_zone_colors()
	var run: String = "wire_%d" % Time.get_ticks_usec()
	pm.begin_bulk()
	for i: int in path.size():
		if not pm._wire_nodes.has(keys[i]):
			keys[i] = pm.register_wire_node(path[i], "joint", "", true)
	for i: int in range(1, path.size()):
		var id: String = WireRoute.edge_id(keys[i - 1], keys[i])
		var seg := _spawn_wire_segment(path[i - 1], path[i], id) as WireSegment
		seg.player_placed = true
		seg.run_id = run
		seg.set_meta("zone_color_snap", color_snapshot)
		pm.register_wire_edge(keys[i - 1], keys[i], seg)
		seg.play_placement()
		var midpoint: Vector3 = (path[i - 1] + path[i]) * 0.5
		wire_placed.emit(seg, id, cost if i == 1 else 0, midpoint)
		wire_nodes_connected.emit(keys[i - 1], path[i - 1], keys[i], path[i])
	pm.end_bulk()
	_spawn_float_label((_source_pos + destination) * 0.5, cost, false)
	_cancel()
	return true

func _update_ghost_wire(from: Vector3, to: Vector3, snapped: bool) -> void:
	if _ghost_wire == null:
		_ghost_wire = WireSegment.make_ghost_wire(_get_scene_root(), from, to)
	else:
		_ghost_wire.set_endpoints(from, to)
	_ghost_wire.visible = true
	(_ghost_wire as WireSegment).set_preview_color(SNAP_COLOR if snapped else GHOST_COLOR)

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
		lbl.font_size        = 56   ## 2x (was 28) — per Brannon's "a bit small" feedback, July 2026
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

	_cost_label.text            = UIFormat.money(cost)
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
		return Vector3.INF
	var mouse: Vector2 = camera.get_viewport().get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse)
	var direction: Vector3 = camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.0001:
		return Vector3.INF
	var t: float = (_WIRE_Y - origin.y) / direction.y
	return origin + direction * t if t >= 0.0 else Vector3.INF

func _get_nearest_wire_node(_world_pos: Vector3, exclude_key: String) -> Dictionary:
	var pm: PowerManager = _get_pm()
	if pm == null or camera == null:
		return {}
	var mouse: Vector2 = camera.get_viewport().get_mouse_position()
	var best_distance: float = SNAP_PIXELS
	var best: Dictionary = {}
	for data: Dictionary in pm.get_wire_nodes():
		var key: String = data.get("key", "")
		var position: Vector3 = data.get("pos", Vector3.ZERO)
		if key == exclude_key or bool(pm._wire_nodes[key].get("wall_feed", false)) or camera.is_position_behind(position):
			continue
		var distance: float = camera.unproject_position(position).distance_to(mouse)
		if distance < best_distance or (is_equal_approx(distance, best_distance) and key < String(best.get("key", "~"))):
			best_distance = distance
			best = data
	return best



func _get_pm() -> PowerManager:
	return get_tree().get_first_node_in_group("power_manager") as PowerManager

func _get_scene_root() -> Node3D:
	var root: Node = get_tree().get_root()
	for child: Node in root.get_children():
		if child is Node3D:
			return child as Node3D
	return root as Node3D

func _show_warning(msg: String) -> void:
	NotificationManager.notify(UIKit.Domain.POWER,
		NotificationManager.Severity.WARNING, msg)

## Floating "+$X"/"-$X" screen-space label — same HUD.spawn_float_label()
## call BuildModeController._spawn_float_label_at_pos() uses for tile
## place/remove. positive=true → green refund, false → red spend.
func _spawn_float_label(world_pos: Vector3, amount: int, positive: bool) -> void:
	if camera == null or amount == 0 or world_node == null:
		return
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	var main_hud: Node = world_node.get_node_or_null("HUD")
	if main_hud != null and main_hud.has_method("spawn_float_label"):
		main_hud.spawn_float_label(screen_pos, amount, positive)

func _cancel() -> void:
	_clear_ghost()
	_clear_cost_label()
	## Clear any floating hover label too — without this, exiting wire mode
	## (or build mode entirely) while the cursor is still hovering a wire
	## node/generator/wall light left its Label3D permanently orphaned in
	## the scene (nothing ever calls _update_hover_label() again once
	## deactivated, so it never got the chance to free itself). Reusing the
	## same "empty dict clears" path _process() already uses every frame.
	_update_hover_label({})
	_phase      = 0
	_source_key = ""

## Cancels the in-progress wire placement but STAYS in the wire tool (Aug
## 2026 — controller B; mirrors the pipe tool's RMB/E cancel semantics).
## The mode keeps processing so the player can immediately start a new wire.
func cancel_placement() -> void:
	_cancel()

# ─── Grid snap helpers ────────────────────────────────────────────────────────
const _WIRE_GRID: float = 0.25   ## must match PowerManager.SNAP_GRID
## Canonical free-floor-joint height. Selected device nodes keep their actual Y.
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
