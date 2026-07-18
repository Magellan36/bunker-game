extends RefCounted
class_name GhostPreview
## GhostPreview.gd  —  Stage 10 (BuildModeController slice) extraction
## ─────────────────────────────────────────────────────────────────────────────
## The build-mode ghost/preview system, extracted out of BuildModeController.gd:
## spawning/destroying the ghost mesh instance, rebuilding its shape per
## selected tile type (procedural boxes for most devices, GLB-sized meshes for
## lights/shelving, MeshLibrary lookups for walls/pillars), the direction-arrow
## indicator, and the per-frame ghost update (raycast → snap → wall-snap for
## breakers/lights → validity checks → material tint).
##
## SCOPE: _spawn_ghost, _destroy_ghost, _rebuild_ghost_mesh,
## _attach_ghost_direction_arrow, _update_ghost. Confirmed zero external
## callers anywhere else in the repo before extraction (same check as every
## prior slice).
##
## DESIGN — same `_owner` back-reference pattern as every prior extraction.
## Nothing moved: `_ghost`, `_selected_tile`, `_selected_tile_price`, `gridmap`,
## `camera`, `world_node`, `build_reach`, `_mat_valid`/`_mat_invalid`,
## `_current_angle_deg`, `_orient_index`, `_ghost_valid`,
## `_ghost_blocked_by_occupation`, `_ghost_world_pos`, `EIGHT_DIR_ANGLES`, all
## `TILE_*`/`*_PLACEMENT_Y` consts stay on BuildModeController. Also routes
## `_owner._raycast_to_grid()`, `_owner._snap_to_grid()`,
## `_owner._snap_breaker_to_wall()`, `_owner._snap_light_to_wall()`,
## `_owner._is_position_occupied_for_tile()`, `_owner._has_wall_surface_behind()`,
## `_owner._is_inside_bunker()`, `_owner.get_tree()`, `_owner.get_parent()`
## (RefCounted has no scene-tree access of its own).
##
## Caught and fixed one real transcription-risk bug during the read-back pass:
## a naive regex on `get_parent()`/`get_tree()` initially double-prefixed
## `gridmap.get_parent()` into `_owner.gridmap._owner.get_parent()` because the
## exclusion only checked for a preceding `_owner.`, not any other receiver.
## Fixed by excluding any preceding `.` at all before writing the final file.
##
## BuildModeController holds one instance (`_ghost_preview`) and forwards the
## 3 functions still called from elsewhere in that file with identical
## signatures: `_spawn_ghost()`/`_update_ghost()` (called from tool-select and
## `_process()`), `_destroy_ghost()` (called from `_cancel_ghost()` and from
## within `_spawn_ghost()` itself). `_rebuild_ghost_mesh()` and
## `_attach_ghost_direction_arrow()` are only called from within this same
## cluster, so need no wrapper.

var _owner: BuildModeController = null

func _init(owner: BuildModeController) -> void:
	_owner = owner


func _spawn_ghost() -> void:
	_destroy_ghost()
	_owner._ghost = MeshInstance3D.new()
	_owner._ghost.position = Vector3.ZERO   ## Reset local offset before mesh rebuild may override
	_rebuild_ghost_mesh()
	var parent: Node = _owner.gridmap.get_parent() if _owner.gridmap != null else _owner.get_tree().get_root()
	parent.add_child(_owner._ghost)
	_owner._ghost.visible = false

func _destroy_ghost() -> void:
	if _owner._ghost != null:
		_owner._ghost.queue_free()
		_owner._ghost = null

func _rebuild_ghost_mesh() -> void:
	if _owner._ghost == null:
		return

	# ── Bed: procedural box ghost (2m wide × 0.5m tall × 1m deep) ───────────────
	if _owner._selected_tile == _owner.TILE_BED:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var W: float = 2.0; var H: float = 0.5; var D: float = 1.0
		# Build a simple box centred at (0, H/2, 0)
		var hx: float = W*0.5; var hy: float = H*0.5; var hz: float = D*0.5
		var verts: Array[Array] = [
			[Vector3(-hx,-hy,-hz),Vector3(-hx,hy,-hz),Vector3(hx,hy,-hz),Vector3(-hx,-hy,-hz),Vector3(hx,hy,-hz),Vector3(hx,-hy,-hz)],
			[Vector3(hx,-hy,hz),Vector3(hx,hy,hz),Vector3(-hx,hy,hz),Vector3(hx,-hy,hz),Vector3(-hx,hy,hz),Vector3(-hx,-hy,hz)],
			[Vector3(-hx,hy,-hz),Vector3(-hx,hy,hz),Vector3(hx,hy,hz),Vector3(-hx,hy,-hz),Vector3(hx,hy,hz),Vector3(hx,hy,-hz)],
			[Vector3(-hx,-hy,hz),Vector3(-hx,-hy,-hz),Vector3(hx,-hy,-hz),Vector3(-hx,-hy,hz),Vector3(hx,-hy,-hz),Vector3(hx,-hy,hz)],
			[Vector3(-hx,-hy,hz),Vector3(hx,-hy,hz),Vector3(hx,hy,hz),Vector3(-hx,-hy,hz),Vector3(hx,hy,hz),Vector3(-hx,hy,hz)],  # back
			[Vector3(hx,-hy,-hz),Vector3(-hx,-hy,-hz),Vector3(-hx,hy,-hz),Vector3(hx,-hy,-hz),Vector3(-hx,hy,-hz),Vector3(hx,hy,-hz)],
		]
		for face: Array in verts:
			for v: Vector3 in face:
				st.add_vertex(v + Vector3(0.0, hy, 0.0))
		st.generate_normals()
		var bed_mesh: ArrayMesh = st.commit()
		_owner._ghost.mesh = bed_mesh
		for s: int in bed_mesh.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		_attach_ghost_direction_arrow(0.75, 90.0)  ## half-depth offset for bed; +90° so arrow faces true front
		return

	# ── Wall light: ghost sized to GLB model bounds ───────────────────────────
	if _owner._selected_tile == _owner.TILE_LIGHT:
		var light_script: GDScript = load("res://scripts/world/power/WallLight.gd")
		if light_script != null and light_script.has_method("build_ghost_mesh"):
			var ghost_mesh: Mesh = light_script.build_ghost_mesh()
			if ghost_mesh != null:
				_owner._ghost.mesh = ghost_mesh
				# GLB origin is at the model's vertical centre; LAMP_Y_OFFSET = 1.5
				# places that centre at world Y = snap_pos.y + 1.5 = 2.5.
				# Ghost local position matches so the box aligns with the real model.
				_owner._ghost.position = Vector3(0.0, 1.5, 0.0)
				for s: int in ghost_mesh.get_surface_count():
					_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── Water hookup (July 2026 groundwork pass): ghost from static helper ────
	if _owner._selected_tile == _owner.TILE_WATER_HOOKUP:
		var hookup_script: GDScript = load("res://scripts/world/water/WaterHookup.gd")
		if hookup_script != null and hookup_script.has_method("build_ghost_mesh"):
			var wh_mesh: Mesh = hookup_script.build_ghost_mesh()
			if wh_mesh != null:
				_owner._ghost.mesh = wh_mesh
				for s: int in wh_mesh.get_surface_count():
					_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── Water test sink (July 2026 groundwork pass): grey box, mirrors TILE_HEAVY ──
	if _owner._selected_tile == _owner.TILE_WATER_SINK:
		var ws_box: BoxMesh = BoxMesh.new()
		ws_box.size = Vector3(0.35, 0.30, 0.35)
		_owner._ghost.mesh     = ws_box
		_owner._ghost.position = Vector3(0.0, 0.15, 0.0)
		for s: int in ws_box.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── Water dispenser (Jul 2026, demand/priority pass): ghost from its own
	## static helper, same convention WallLight/Shelving/WaterHookup use ──────
	if _owner._selected_tile == _owner.TILE_WATER_DISPENSER:
		var wd_script: GDScript = load("res://scripts/world/water/WaterDispenser.gd")
		if wd_script != null and wd_script.has_method("build_ghost_mesh"):
			var wd_mesh: Mesh = wd_script.build_ghost_mesh()
			if wd_mesh != null:
				_owner._ghost.mesh     = wd_mesh
				_owner._ghost.position = Vector3(0.0, 0.275, 0.0)   ## BOX_SIZE.y * 0.5
				for s: int in wd_mesh.get_surface_count():
					_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── Water purifier (Jul 2026): ghost from static helper, attaches onto a
	## pipe rather than floor/wall — position is resolved in _update_ghost() ──
	if _owner._selected_tile == _owner.TILE_WATER_PURIFIER:
		var wp_mesh: Mesh = WaterPurifier.build_ghost_mesh()
		_owner._ghost.mesh = wp_mesh
		for s: int in wp_mesh.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── Shelving: procedural ghost from static helper ──────────────────────────
	if _owner._selected_tile == _owner.TILE_SHELVING:
		var shelving_script: GDScript = load("res://scripts/world/furniture/Shelving.gd")
		if shelving_script != null and shelving_script.has_method("build_ghost_mesh"):
			var ghost_mesh: Mesh = shelving_script.build_ghost_mesh()
			if ghost_mesh != null:
				_owner._ghost.mesh = ghost_mesh
				for s: int in ghost_mesh.get_surface_count():
					_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		_attach_ghost_direction_arrow(0.6)
		return

	# ── Heavy consumer ghost: grey box matching HeavyConsumerTest BOX_SIZE ─────
	if _owner._selected_tile == _owner.TILE_HEAVY:
		var hc_box: BoxMesh = BoxMesh.new()
		hc_box.size = Vector3(0.60, 0.60, 0.60)
		_owner._ghost.mesh   = hc_box
		_owner._ghost.position = Vector3(0.0, 0.30, 0.0)
		for s: int in hc_box.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── Circuit breaker ghost: small wall box (standard + upgraded/smart) ─────
	if _owner._selected_tile == _owner.TILE_BREAKER or _owner._selected_tile == _owner.TILE_BREAKER_SMART:
		var brk_box: BoxMesh = BoxMesh.new()
		brk_box.size = Vector3(0.36, 0.44, 0.14)
		_owner._ghost.mesh     = brk_box
		_owner._ghost.position = Vector3(0.0, 0.22, 0.0)
		for s: int in brk_box.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── Battery bank ghosts: box scaled by tier ────────────────────────────────
	if _owner._selected_tile == _owner.TILE_BATTERY_S or _owner._selected_tile == _owner.TILE_BATTERY_M \
			or _owner._selected_tile == _owner.TILE_BATTERY_L:
		const BAT_SIZES: Array = [
			Vector3(0.40, 0.70, 0.22),   ## Small
			Vector3(0.50, 0.90, 0.26),   ## Medium
			Vector3(0.60, 1.10, 0.28),   ## Large
		]
		var b_tier: int = 0
		if _owner._selected_tile == _owner.TILE_BATTERY_M: b_tier = 1
		elif _owner._selected_tile == _owner.TILE_BATTERY_L: b_tier = 2
		var bat_box: BoxMesh = BoxMesh.new()
		bat_box.size = BAT_SIZES[b_tier]
		_owner._ghost.mesh     = bat_box
		_owner._ghost.position = Vector3(0.0, BAT_SIZES[b_tier].y * 0.5, 0.0)
		for s: int in bat_box.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── Power terminal ghost: thin box panel ──────────────────────────────────
	if _owner._selected_tile == _owner.TILE_TERMINAL:
		var term_box: BoxMesh = BoxMesh.new()
		term_box.size = Vector3(0.70, 0.90, 0.08)
		_owner._ghost.mesh   = term_box
		_owner._ghost.position = Vector3(0.0, 0.45, 0.0)
		for s: int in term_box.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		_attach_ghost_direction_arrow(0.25)
		return

	# ── Generator ghost: box sized to tier footprint ──────────────────────────
	if _owner._selected_tile == _owner.TILE_GEN_S or _owner._selected_tile == _owner.TILE_GEN_M \
			or _owner._selected_tile == _owner.TILE_GEN_L:
		const GEN_SIZES: Array = [
			Vector3(0.85, 0.85, 0.85),
			Vector3(0.85, 0.85, 1.85),
			Vector3(1.85, 0.85, 1.85),
		]
		var tier: int = 0
		if _owner._selected_tile == _owner.TILE_GEN_M: tier = 1
		elif _owner._selected_tile == _owner.TILE_GEN_L: tier = 2
		var box: BoxMesh = BoxMesh.new()
		box.size = GEN_SIZES[tier]
		_owner._ghost.mesh = box
		_owner._ghost.position = Vector3(0.0, GEN_SIZES[tier].y * 0.5, 0.0)
		for s: int in box.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		_attach_ghost_direction_arrow(GEN_SIZES[tier].z * 0.5 + 0.15, 180.0)  ## +180° so arrow faces generator front panel
		return

	# ── Wire ghost: thin flat box ──────────────────────────────────────────────
	if _owner._selected_tile == _owner.TILE_WIRE:
		var wire_box: BoxMesh = BoxMesh.new()
		wire_box.size = Vector3(0.90, 0.06, 0.08)
		_owner._ghost.mesh   = wire_box
		_owner._ghost.position = Vector3(0.0, 0.03, 0.0)
		for s: int in wire_box.get_surface_count():
			_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
		return

	# ── MeshLibrary tiles (wall / pillar) ──────────────────────────────────────
	if _owner.gridmap == null:
		return
	var lib: MeshLibrary = _owner.gridmap.mesh_library
	if lib == null:
		return
	var mesh: Mesh = lib.get_item_mesh(_owner._selected_tile)
	if mesh == null:
		_owner._ghost.visible = false
		return
	_owner._ghost.mesh = mesh
	for s: int in mesh.get_surface_count():
		_owner._ghost.set_surface_override_material(s, _owner._mat_valid)
	## Walls/pillars have no meaningful "front" in a rotation context — skip arrow.
	## (They're handled by the MeshLibrary branch; _owner.TILE_LIGHT and _owner.TILE_WIRE also excluded.)

## Attaches a small forward-direction arrow to _owner._ghost so the player can see
## which way the object faces before placing it.
##
## The arrow sits at ground level (Y = 0.05), pointing along local -Z (the
## object's "front"). It's built as a flat elongated prism (shaft) + a
## CylinderMesh cone-tip for the arrowhead, all white-cyan, semi-transparent.
##
## z_offset  — how far from ghost centre to start the arrow (half object depth + gap)
func _attach_ghost_direction_arrow(z_offset: float, y_rotation_offset_deg: float = 0.0) -> void:
	if _owner._ghost == null:
		return

	## Remove any old arrow child first (mesh rebuilds call this each time)
	for child: Node in _owner._ghost.get_children():
		if child.name == "_GhostArrow":
			child.queue_free()

	var arrow_root: Node3D = Node3D.new()
	arrow_root.name = "_GhostArrow"

	## Shared arrow material — bright cyan, no depth test so it's always visible
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color              = Color(0.30, 0.90, 1.0, 0.85)
	mat.emission_enabled          = true
	mat.emission                  = Color(0.30, 0.90, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.6
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test             = true
	mat.render_priority           = 2

	## Shaft — thin flat box along -Z (pointing away from object front)
	const SHAFT_LEN:   float = 0.28
	const SHAFT_W:     float = 0.055
	const SHAFT_H:     float = 0.04
	var shaft_mi: MeshInstance3D = MeshInstance3D.new()
	var shaft_box: BoxMesh = BoxMesh.new()
	shaft_box.size = Vector3(SHAFT_W, SHAFT_H, SHAFT_LEN)
	shaft_mi.mesh  = shaft_box
	## Centre of shaft is half its length in front of z_offset
	shaft_mi.position = Vector3(0.0, 0.05, -(z_offset + SHAFT_LEN * 0.5))
	shaft_mi.set_surface_override_material(0, mat)
	arrow_root.add_child(shaft_mi)

	## Arrowhead — flat cone-ish triangle prism using a short wide CylinderMesh
	## (top_radius=0 makes it a cone)
	const HEAD_R: float  = 0.10
	const HEAD_H: float  = 0.06
	var head_mi: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius      = 0.0
	cone.bottom_radius   = HEAD_R
	cone.height          = HEAD_H
	cone.radial_segments = 4    ## diamond shape — simple and clear
	cone.rings           = 1
	head_mi.mesh = cone
	## Cone sits at tip of shaft; rotate 90°X to lie flat, then face -Z
	head_mi.rotation_degrees = Vector3(0.0, 45.0, 0.0)   ## 45° so diamond points along Z
	head_mi.position = Vector3(0.0, 0.05, -(z_offset + SHAFT_LEN + HEAD_H * 0.5))
	head_mi.set_surface_override_material(0, mat)
	arrow_root.add_child(head_mi)

	## Apply optional Y rotation offset (e.g. +180° for generators, +90° for beds)
	## so the arrow points at the true visual front of the object.
	if y_rotation_offset_deg != 0.0:
		arrow_root.rotation_degrees = Vector3(0.0, y_rotation_offset_deg, 0.0)

	_owner._ghost.add_child(arrow_root)

func _update_ghost() -> void:
	if _owner._ghost == null or _owner.gridmap == null or _owner.camera == null:
		return

	var result: Dictionary = _owner._raycast_to_grid()
	if result.is_empty():
		_owner._ghost.visible = false
		_owner._ghost_valid   = false
		return

	var world_pos: Vector3 = result["position"]
	var snap_pos: Vector3  = _owner._snap_to_grid(world_pos)
	# Use shelf-specific Y for shelving, standard for everything else
	if _owner._selected_tile == _owner.TILE_SHELVING or _owner._selected_tile == _owner.TILE_BED:
		snap_pos.y = _owner.SHELF_PLACEMENT_Y
	elif _owner._selected_tile == _owner.TILE_LIGHT:
		snap_pos.y = _owner.LIGHT_PLACEMENT_Y
	elif _owner._selected_tile == _owner.TILE_GEN_S or _owner._selected_tile == _owner.TILE_GEN_M \
			or _owner._selected_tile == _owner.TILE_GEN_L:
		snap_pos.y = _owner.GEN_PLACEMENT_Y
	elif _owner._selected_tile == _owner.TILE_WIRE or _owner._selected_tile == _owner.TILE_TERMINAL \
			or _owner._selected_tile == _owner.TILE_HEAVY:
		snap_pos.y = _owner.PLACEMENT_Y
	elif _owner._selected_tile == _owner.TILE_BREAKER or _owner._selected_tile == _owner.TILE_BREAKER_SMART:
		snap_pos.y = _owner.PLACEMENT_Y
		## Wall-snap: attempt to stick the breaker to the nearest interior wall.
		## Shared by both breaker variants — identical snap geometry.
		var brk_snapped: Dictionary = _owner._snap_breaker_to_wall(snap_pos)
		if not brk_snapped.is_empty():
			snap_pos           = brk_snapped["pos"]
			_owner._current_angle_deg = brk_snapped["angle_deg"]
			for i: int in _owner.EIGHT_DIR_ANGLES.size():
				if absf(_owner.EIGHT_DIR_ANGLES[i] - _owner._current_angle_deg) < 1.0:
					_owner._orient_index = i
					break
		else:
			## No wall nearby — hide ghost so there is no misleading indicator.
			_owner._ghost.visible = false
			_owner._ghost_valid   = false
			return
	elif _owner._selected_tile == _owner.TILE_WATER_HOOKUP:
		## Water hookup (July 2026 groundwork pass) — mandatory wall-snap,
		## same "hide ghost if no wall found" strictness as the breaker above.
		## Raised near-ceiling per playtest feedback (see WATER_HOOKUP_PLACEMENT_Y).
		snap_pos.y = _owner.WATER_HOOKUP_PLACEMENT_Y
		var wh_snapped: Dictionary = _owner._snap_to_nearest_wall(snap_pos, 0.0, 0.05, 1.5)
		if not wh_snapped.is_empty():
			snap_pos = wh_snapped["pos"]
			_owner._current_angle_deg = wh_snapped["angle_deg"]
			for i: int in _owner.EIGHT_DIR_ANGLES.size():
				if absf(_owner.EIGHT_DIR_ANGLES[i] - _owner._current_angle_deg) < 1.0:
					_owner._orient_index = i
					break
		else:
			_owner._ghost.visible = false
			_owner._ghost_valid   = false
			return
	elif _owner._selected_tile == _owner.TILE_WATER_SINK:
		snap_pos.y = _owner.PLACEMENT_Y
	elif _owner._selected_tile == _owner.TILE_WATER_DISPENSER:
		snap_pos.y = _owner.PLACEMENT_Y
	elif _owner._selected_tile == _owner.TILE_WATER_PURIFIER:
		## Attaches directly onto an existing pipe run — NO grid/wall snap.
		## Uses the cursor's raw world hit position (not the floor-grid-
		## snapped `snap_pos`) so it can land anywhere along the pipe's line,
		## per the explicit "placed freely, no snap grid" requirement.
		var wm_pf: WaterManager = _owner.get_tree().get_first_node_in_group("water_manager") as WaterManager
		var candidate: Dictionary = WaterPurifierAttach.find_purifier_candidate(_owner.get_tree(), wm_pf, world_pos)
		if candidate.is_empty():
			## No pipe nearby — hide the ghost entirely, same strictness as
			## the breaker/hookup wall-snap "no wall found" case.
			_owner._ghost.visible = false
			_owner._ghost_valid   = false
			return
		snap_pos = candidate["pos"]
		_owner._ghost_purifier_candidate = candidate
	elif _owner._selected_tile == _owner.TILE_BATTERY_S or _owner._selected_tile == _owner.TILE_BATTERY_M \
			or _owner._selected_tile == _owner.TILE_BATTERY_L:
		snap_pos.y = _owner.PLACEMENT_Y
	else:
		snap_pos.y = _owner.PLACEMENT_Y

	# ── Wall light: auto-snap to nearest wall surface within range ──────────
	# Instead of relying on the player to manually rotate the ghost to face a
	# wall, we cast four short rays (N/S/E/W) from the cursor XZ position at
	# lamp height and snap the ghost to the nearest wall hit, auto-setting the
	# orientation so the fixture back always touches the wall.
	if _owner._selected_tile == _owner.TILE_LIGHT:
		var snapped: Dictionary = _owner._snap_light_to_wall(snap_pos)
		if not snapped.is_empty():
			snap_pos           = snapped["pos"]
			_owner._current_angle_deg = snapped["angle_deg"]
			# Keep orient_index in sync so scroll-wheel rotation still works from here
			for i: int in _owner.EIGHT_DIR_ANGLES.size():
				if absf(_owner.EIGHT_DIR_ANGLES[i] - _owner._current_angle_deg) < 1.0:
					_owner._orient_index = i
					break
		else:
			## No wall found within snap range — cursor is over rock, open floor,
			## or outside the bunker.  Hide the ghost entirely so there is no
			## misleading red indicator.  Placement is blocked silently.
			_owner._ghost.visible = false
			_owner._ghost_valid   = false
			return

	# Distance check
	var player: Node3D = _owner.get_parent()
	var dist: float    = player.global_position.distance_to(snap_pos)
	_owner._ghost_valid = (dist <= _owner.build_reach)

	# Also invalid if insufficient cash
	if _owner._ghost_valid and _owner.world_node != null:
		if _owner.world_node.get_cash() < _owner._selected_tile_price:
			_owner._ghost_valid = false

	# Also invalid if another object already occupies this snap position.
	# Lights use a tighter overlap radius so multiple can sit along a wall.
	_owner._ghost_blocked_by_occupation = false
	if _owner._ghost_valid and _owner._is_position_occupied_for_tile(snap_pos, _owner._selected_tile):
		_owner._ghost_valid = false
		_owner._ghost_blocked_by_occupation = true

	# Wall lights must be placed against a wall or pillar surface
	if _owner._ghost_valid and _owner._selected_tile == _owner.TILE_LIGHT:
		if not _owner._has_wall_surface_behind(snap_pos, _owner._current_angle_deg):
			_owner._ghost_valid = false

	# Outside-bunker check — mirrors the gate in _try_construct() so the ghost
	# turns red immediately instead of staying green until the player clicks.
	if _owner._ghost_valid and not _owner._is_inside_bunker(snap_pos):
		_owner._ghost_valid = false

	_owner._ghost_world_pos       = snap_pos
	_owner._ghost.global_position = snap_pos

	# Purifier ghost: lie flat along the pipe run it's attaching to, exactly
	# like WaterPurifier.orient_along() does on the real placed node — a
	# plain Y-only rotation_degrees (below) can't express that since pipes
	# can run along either X or Z. Mirrors orient_along()'s own look_at()+
	# rotate_object_local(RIGHT, 90°) sequence so the ghost always matches
	# what gets placed (was previously stuck at whatever angle the last
	# floor/wall-snapped tile left _current_angle_deg at).
	if _owner._selected_tile == _owner.TILE_WATER_PURIFIER and not _owner._ghost_purifier_candidate.is_empty():
		var seg_node: WaterPipeSegment = _owner._ghost_purifier_candidate.get("seg_node", null)
		if seg_node != null and is_instance_valid(seg_node):
			var dir: Vector3 = (seg_node.point_b - seg_node.point_a).normalized()
			if dir != Vector3.ZERO:
				var up: Vector3 = Vector3.UP
				if absf(dir.dot(up)) > 0.999:
					up = Vector3.RIGHT
				_owner._ghost.look_at(_owner._ghost.global_position + dir, up)
				_owner._ghost.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	else:
		_owner._ghost.rotation_degrees = Vector3(0.0, _owner._current_angle_deg, 0.0)
	_owner._ghost.visible         = true

	var mat: StandardMaterial3D = _owner._mat_valid if _owner._ghost_valid else _owner._mat_invalid
	if _owner._ghost.mesh != null:
		for s: int in _owner._ghost.mesh.get_surface_count():
			_owner._ghost.set_surface_override_material(s, mat)

