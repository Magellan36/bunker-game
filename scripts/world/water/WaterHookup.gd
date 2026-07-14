extends StaticBody3D
class_name WaterHookup
## WaterHookup.gd
## ─────────────────────────────────────────────────────────────────────────────
## The wall-mounted water source — represents a pipe coming up through the
## rock from outside the bunker. TILE_WATER_HOOKUP in BuildModeController.
##
## PLACEMENT: wall-snapped only, reusing the same 4-cardinal-raycast wall-
## detection philosophy WallSnapHelpers._snap_light_to_wall()/
## _snap_breaker_to_wall() already use (see WallSnapHelpers._snap_to_nearest_wall(),
## the new generic helper added alongside this file) — NOT a literal call into
## build-mode internals, since this is a standalone system (see
## docs/systems/water/ — created once a real dashboard/terminal UI exists).
##
## AUTO-TRACKING THE OUTERMOST WALL: the hookup must always be mounted on
## whichever wall is currently the OUTERMOST wall in its recorded facing
## direction — not necessarily the wall it was originally placed on, since
## digging further out in that direction should pull it along. See
## reposition_to_outer_wall() below for the full approach.
##
## NEVER DELETABLE: no "return to inventory" flow. Can only be relocated via
## the Move tool. BuildModeController._try_deconstruct() explicitly excludes
## TILE_WATER_HOOKUP from its generic placed-object deletion path.

# ─── Config ───────────────────────────────────────────────────────────────────
## Placeholder visual dimensions — a grey pipe stub coming out of the wall.
## Confirmed placeholder (see plan) — built as its own clean function so a
## later re-texture pass is a material swap, not a geometry rewrite.
const STUB_RADIUS: float = 0.09
const STUB_LENGTH: float = 0.32
const VALVE_RADIUS: float = 0.14
const VALVE_LENGTH: float = 0.05

const COLOR_PIPE:  Color = Color(0.42, 0.44, 0.46, 1.0)   ## grey galvanized pipe
const COLOR_VALVE: Color = Color(0.25, 0.27, 0.29, 1.0)   ## darker valve wheel

## Pull-back offset from the raw wall-hit position so the stub's back face is
## flush with the wall, not buried inside it — matches
## WallSnapHelpers.LIGHT_WALL_HALF_THICKNESS/BREAKER_HALF_DEPTH's role.
const WALL_PULLBACK: float = 0.05

## How far to nudge the raycast origin off the wall before casting outward
## toward the rock, when re-tracking the outer wall (see
## reposition_to_outer_wall()) — must be enough to clear the wall's own
## collision skin, small enough to stay inside any realistically-sized room.
const REPOSITION_ORIGIN_NUDGE: float = 0.30

## Maximum ray length when searching for the new outer wall — generous enough
## to cover any realistic dig depth (RockSurround.dig_margin is world units of
## surrounding rock; this is intentionally much larger as a safety margin).
const MAX_REPOSITION_RANGE: float = 300.0

# ─── State ────────────────────────────────────────────────────────────────────
## Graph node key this hookup is registered under in WaterManager/WaterGraph.
var _node_key: String = ""

## Step 2 (July 2026) — tier/output/quality data model.
## Tier index → daily output in mL. Index 0 = starting/"low-grade" hookup.
## A future upgrade mechanic will raise `tier`, not replace this table.
const TIER_DAILY_ML: Array[float] = [3000.0, 6000.0, 12000.0, 24000.0]

## Plain tunable int for now — nothing sets this except a future upgrade
## mechanic (not this pass, no purchase/upgrade UI exists yet). Kept here now
## rather than introduced later so that future pass doesn't need a second
## data-model refactor.
var tier: int = 0

## 0-100. Static for this pass — a future pass will decay this over time.
## The sink's displayed quality is always THIS value (traced back via
## WaterManager.get_received_rate_mL()) — water doesn't gain/lose quality
## travelling through pipes in this pass.
var water_quality: float = 100.0

## Info panel (Step 2) — lazy-instantiated, reused across opens, same
## lifecycle pattern as PowerTerminal._terminal_ui.
var _info_ui: CanvasLayer = null

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	_build_mesh()
	call_deferred("_register_deferred")

func _exit_tree() -> void:
	if _info_ui != null and is_instance_valid(_info_ui):
		_info_ui.queue_free()
		_info_ui = null
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	if not _node_key.is_empty():
		wm.unregister_node(_node_key)
	wm.unregister_hookup(self)


# ─── Output getters (Step 2) ──────────────────────────────────────────────────
func get_daily_output_mL() -> float:
	return TIER_DAILY_ML[tier]

func get_per_minute_output_mL() -> float:
	return get_daily_output_mL() / 1440.0   ## 1440 minutes/day

## Public accessor for this hookup's WaterGraph node key — needed by
## WaterManager's flow-split methods and by WaterInfoUI (Step 2, July 2026).
## Every other WaterGraph-facing method on this class kept _node_key private;
## this is the one deliberate read-only exception.
func get_node_key() -> String:
	return _node_key


# ─── Interaction (Step 2) ──────────────────────────────────────────────────────
## NOTE: does NOT toggle open/closed like PowerTerminal does — mirrors
## GeneratorObject.on_interact()'s simpler "always (re)open" pattern instead.
## WaterInfoUI closes itself on E/Escape via its own _unhandled_input (same
## as GeneratorInspectUI) — if the panel is already open, that consumes the
## E press first (set_input_as_handled()) before InteractionSystem ever
## calls on_interact() again, so there's no double-toggle race either way.
func get_interact_prompt() -> String:
	return "[E] Check Hookup"

func on_interact() -> void:
	if _info_ui == null or not is_instance_valid(_info_ui):
		var ui_script: GDScript = load("res://scripts/ui/water/WaterInfoUI.gd")
		if ui_script == null:
			push_warning("WaterHookup: WaterInfoUI.gd not found")
			return
		_info_ui = CanvasLayer.new()
		_info_ui.set_script(ui_script)
		_info_ui.name = "WaterInfoUI"
		get_tree().get_root().add_child(_info_ui)
		if _info_ui.has_signal("closed"):
			_info_ui.closed.connect(_on_ui_closed)

	if _info_ui.has_method("open"):
		_info_ui.open("Water Hookup", true, self)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_ui_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# ─── WaterManager registration ────────────────────────────────────────────────
func _register_deferred() -> void:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		push_warning("WaterHookup: WaterManager not found — will not register into the water graph.")
		return
	_node_key = wm.register_node(global_position, "hookup")
	wm.register_hookup(self)


# ─── Facing direction ─────────────────────────────────────────────────────────
## The cardinal direction FROM the room interior TOWARD the wall (i.e. where
## the rock is) — same convention as WallSnapHelpers' `dir` in its 4-direction
## raycast loop. Derived from rotation_degrees.y rather than stored/cached
## separately, so it's always correct even after the Move tool re-snaps this
## hookup to a different wall (see WallSnapHelpers._snap_to_nearest_wall()'s
## angle_deg convention — identical mapping to _snap_light_to_wall()'s):
##   angle 0°   → wall in +Z   → facing_dir = ( 0, 0,  1)
##   angle 90°  → wall in +X   → facing_dir = ( 1, 0,  0)
##   angle 180° → wall in -Z   → facing_dir = ( 0, 0, -1)
##   angle 270° → wall in -X   → facing_dir = (-1, 0,  0)
func get_facing_dir() -> Vector3:
	var rad: float = deg_to_rad(rotation_degrees.y)
	var fx: float = roundf(sin(rad))
	var fz: float = roundf(cos(rad))
	return Vector3(fx, 0.0, fz)


# ─── Auto-tracking the outermost wall ──────────────────────────────────────────
## Called by WaterManager whenever RockSurround reports a chunk dig/restore
## (the same boundary-change event WireGraphBuilder's incremental wire-graph
## rebuild already reacts to — see WaterManager._on_chunk_deconstructed/
## _on_chunk_restored). Since the bunker only ever expands (no contraction
## case to handle — confirmed in the plan), this is strictly "move outward
## when the boundary moves outward," never "handle floating over open air."
##
## APPROACH: cast a single straight ray, starting just inside the room from
## this hookup's current position, travelling along facing_dir (toward the
## rock) for a long distance. The first wall/pillar collider hit IS the
## current outer wall, whether it moved or not:
##   - If nothing was dug further in this direction, the ray immediately hits
##     the same wall this hookup is already mounted on (no visible change).
##   - If the player dug further out, the old wall was replaced by a new
##     autofill wall further away (see WireGraphBuilder's incremental rebuild)
##     — the space in between is now open/cleared, so the ray passes straight
##     through it and hits the NEW wall instead.
## A straight-line ray along a single cardinal axis cannot drift on the other
## two axes, which is what naturally preserves the along-wall coordinate
## exactly (the same outcome BreakerBox's wall-snap math achieves via manual
## axis-split arithmetic — see WallSnapHelpers.gd's own comments on that
## pattern) while only ever recomputing the perpendicular (into-the-wall)
## coordinate.
func reposition_to_outer_wall() -> void:
	var facing_dir: Vector3 = get_facing_dir()
	if facing_dir == Vector3.ZERO:
		return   ## Should never happen — rotation is always one of the 4 cardinal snaps.

	var origin: Vector3 = global_position - facing_dir * REPOSITION_ORIGIN_NUDGE
	var to_pt:  Vector3 = origin + facing_dir * MAX_REPOSITION_RANGE

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to_pt)
	## Mask 5 — same as WallSnapHelpers' wall-snap raycasts. Deliberately does
	## NOT include RockSurround's raw rock-chunk collision layer (16), so this
	## ray only ever stops at an actual wall/pillar collider, never at undug
	## rock — see file header for why that's the correct behavior here.
	query.collision_mask = 5

	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		push_warning("WaterHookup: no wall found while tracking the outer boundary — leaving position unchanged.")
		return

	var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if hit_normal.dot(facing_dir) >= 0.0:
		## Not an interior-facing surface (mirrors WallSnapHelpers' same check)
		## — reject rather than mount the hookup on the wrong face.
		return

	## Confirm the hit is actually wall/pillar/GridMap geometry (not, say, a
	## stray placed object that happens to sit on this line).
	var is_wall: bool = false
	var node: Node = hit.get("collider")
	while node != null:
		if node.has_meta("tile_id"):
			var tid: int = node.get_meta("tile_id")
			## TILE_WALL/TILE_PILLAR constants live on BuildModeController;
			## this file stays standalone (no build-mode dependency), so the
			## values are inlined here with a comment rather than referenced
			## directly — keep in sync if those constants ever change.
			if tid == 1 or tid == 2:   ## TILE_WALL, TILE_PILLAR
				is_wall = true
			break
		if node is GridMap:
			is_wall = true
			break
		node = node.get_parent()
	if not is_wall:
		return

	var new_pos: Vector3 = hit["position"] - facing_dir * WALL_PULLBACK
	new_pos.y = global_position.y
	global_position = new_pos

	update_graph_node_position()


## Re-registers this hookup's graph node at its (possibly new) position.
## WaterGraph nodes are keyed by position, so a reposition needs a fresh
## register — any pipe edges attached to the OLD node key would be orphaned
## by this in Phase 1 (no pipes exist yet to attach to a hookup — pipes are
## always placed starting FROM the hookup's current position, so this is a
## non-issue for this pass; flagged here for whoever builds pipe-to-hookup
## reconnection logic once pipes exist across a reposition event).
func update_graph_node_position() -> void:
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	if not _node_key.is_empty():
		wm.unregister_node(_node_key)
	_node_key = wm.register_node(global_position, "hookup")


# ─── Visual build ─────────────────────────────────────────────────────────────
## Placeholder mesh — a short grey pipe stub with a valve wheel disc at the
## wall face, built the same procedural way BreakerBox/WallLight/
## GeneratorObject build their placeholder geometry.
func _build_mesh() -> void:
	var pipe_mat: StandardMaterial3D = StandardMaterial3D.new()
	pipe_mat.albedo_color = COLOR_PIPE
	pipe_mat.roughness    = 0.55
	pipe_mat.metallic     = 0.60

	var valve_mat: StandardMaterial3D = StandardMaterial3D.new()
	valve_mat.albedo_color = COLOR_VALVE
	valve_mat.roughness    = 0.70
	valve_mat.metallic     = 0.40

	## Pipe stub — cylinder along local Z, protruding from the wall into the room.
	## Local -Z is "into the room" (matches the light/breaker convention where
	## rotation_degrees.y = 0 means the wall is at +Z, room is at -Z).
	var stub_mi: MeshInstance3D = MeshInstance3D.new()
	var stub_cyl: CylinderMesh  = CylinderMesh.new()
	stub_cyl.top_radius    = STUB_RADIUS
	stub_cyl.bottom_radius = STUB_RADIUS
	stub_cyl.height        = STUB_LENGTH
	stub_cyl.radial_segments = 12
	stub_mi.mesh = stub_cyl
	stub_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)   ## CylinderMesh is Y-aligned; rotate to lie along Z
	stub_mi.position = Vector3(0.0, 0.0, -STUB_LENGTH * 0.5)
	stub_mi.set_surface_override_material(0, pipe_mat)
	add_child(stub_mi)

	## Valve wheel — flat disc at the wall face end of the stub.
	var valve_mi: MeshInstance3D = MeshInstance3D.new()
	var valve_cyl: CylinderMesh  = CylinderMesh.new()
	valve_cyl.top_radius    = VALVE_RADIUS
	valve_cyl.bottom_radius = VALVE_RADIUS
	valve_cyl.height        = VALVE_LENGTH
	valve_cyl.radial_segments = 16
	valve_mi.mesh = valve_cyl
	valve_mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	valve_mi.position = Vector3(0.0, 0.0, -STUB_LENGTH - VALVE_LENGTH * 0.5)
	valve_mi.set_surface_override_material(0, valve_mat)
	add_child(valve_mi)

	## Collision — simple trimesh on the stub is enough for wall-snap
	## raycasts / hover detection; matches HeavyConsumerTest's approach.
	stub_mi.create_trimesh_collision()
	for child in stub_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0


## Returns a standalone ghost-preview mesh (no collision) — same
## `build_ghost_mesh()` static-function convention WallLight.gd/Shelving.gd
## use, so GhostPreview.gd/MoveDuplicateTool.gd can build a preview without
## instantiating a real WaterHookup.
static func build_ghost_mesh() -> Mesh:
	var stub_cyl: CylinderMesh = CylinderMesh.new()
	stub_cyl.top_radius    = STUB_RADIUS
	stub_cyl.bottom_radius = STUB_RADIUS
	stub_cyl.height        = STUB_LENGTH
	stub_cyl.radial_segments = 12
	return stub_cyl
