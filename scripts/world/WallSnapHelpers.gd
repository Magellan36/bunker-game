extends RefCounted
class_name WallSnapHelpers
## WallSnapHelpers.gd  —  Stage 10 (BuildModeController slice) extraction
## ─────────────────────────────────────────────────────────────────────────────
## Wall/breaker-snap raycasting, extracted out of BuildModeController.gd: casts
## four cardinal rays to find the nearest interior wall surface for lights and
## breakers, plus the pregen-boundary interior-face correctness check both
## snap functions depend on.
##
## SCOPE: _snap_light_to_wall, _snap_breaker_to_wall, _is_pregen_interior_face.
## `_snap_light_to_wall`/`_snap_breaker_to_wall` ARE called externally — from
## `GhostPreview.gd`'s `_update_ghost()` via `_owner._snap_light_to_wall()`/
## `_owner._snap_breaker_to_wall()` (GhostPreview calls through the
## BuildModeController instance, so the forwarding wrappers below keep that
## working unchanged). `_is_pregen_interior_face` is internal-only, called
## from the other two functions within this same cluster.
##
## NOTE: a `static func _tile_half_extents()` sits physically between this
## cluster and the next function in the original file — it's unrelated tile
## footprint-size data (used by `_is_position_occupied`/
## `_is_position_occupied_for_tile`), not wall-snap logic, so it was
## deliberately left on BuildModeController rather than swept in.
##
## DESIGN — same `_owner` back-reference pattern as every prior extraction.
## Nothing moved: `LIGHT_WALL_SNAP_RANGE`, `LIGHT_WALL_HALF_THICKNESS`,
## `TILE_WALL`, `TILE_PILLAR`, `grid_size`, `rock_surround` all stay on
## BuildModeController. Also routes `_owner._is_inside_bunker()`,
## `_owner.get_world_3d()`, `_owner.get_parent()` (RefCounted has no
## scene-tree access of its own — `node.get_parent()`/`walk_node.get_parent()`
## calls on LOCAL collider-tree-walk variables inside the raycast loops stay
## bare, only the two `get_parent()` calls on `self` got prefixed).
##
## BuildModeController holds one instance (`_wall_snap`) and forwards
## `_snap_light_to_wall()`/`_snap_breaker_to_wall()` with identical signatures
## (both called from GhostPreview as described above). `_is_pregen_interior_face()`
## is only called from within this same cluster, so needs no wrapper.

var _owner: BuildModeController = null

func _init(owner: BuildModeController) -> void:
	_owner = owner


## Cast four short rays (N/S/E/W) from the cursor XZ at lamp height.
## Returns { "pos": Vector3, "angle_deg": float } for the closest wall hit
## within _owner.LIGHT_WALL_SNAP_RANGE, or an empty dict if none found.
## "angle_deg" is set so the light faces AWAY from the wall (into the room).
func _snap_light_to_wall(base_pos: Vector3) -> Dictionary:
	var lamp_y: float = base_pos.y + 1.5   ## lamp-centre world Y
	var origin: Vector3 = Vector3(base_pos.x, lamp_y, base_pos.z)

	# Cardinal directions: +X, -X, +Z, -Z
	# angle_deg is the Y-rotation given to the WallLight node so its local +Z
	# points TOWARD the wall (light/spot aims -Z = away from wall into room).
	# WallLight local +Z rotated by angle_deg:
	#   0°   → +Z direction  (wall is in +Z)
	#   180° → -Z direction  (wall is in -Z)
	#   90°  → +X direction  (wall is in +X)
	#   270° → -X direction  (wall is in -X)
	var directions: Array[Dictionary] = [
		{ "dir": Vector3( 0, 0,  1), "angle_deg":   0.0 },   ## wall north (+Z)
		{ "dir": Vector3( 0, 0, -1), "angle_deg": 180.0 },   ## wall south (-Z)
		{ "dir": Vector3( 1, 0,  0), "angle_deg":  90.0 },   ## wall east  (+X)
		{ "dir": Vector3(-1, 0,  0), "angle_deg": 270.0 },   ## wall west  (-X)
	]

	var space: PhysicsDirectSpaceState3D = _owner.get_world_3d().direct_space_state
	var player: Node3D = _owner.get_parent()
	var best_dist: float       = _owner.LIGHT_WALL_SNAP_RANGE
	var best_result: Dictionary = {}
	var best_is_player_wall: bool = false   ## true = player _owner.TILE_WALL/_owner.TILE_PILLAR hit

	for d: Dictionary in directions:
		var dir: Vector3 = d["dir"] as Vector3
		var to_pt: Vector3 = origin + dir * _owner.LIGHT_WALL_SNAP_RANGE

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to_pt)
		query.collision_mask = 5
		## hit_back_faces intentionally NOT set to false here.
		## Player-placed walls use create_trimesh_collision() — their interior
		## face normals point outward (away from the room), so they are "back
		## faces" from the ray's perspective and would be silently skipped if
		## hit_back_faces = false. We do the interior-face test manually below.
		if player.has_method("get_rid"):
			query.exclude = [player.get_rid()]

		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue

		# Confirm the hit normal opposes the ray direction — interior face only.
		# A side or back face of a wall would have a normal that doesn't oppose
		# the outbound ray, so we reject it here.
		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
		if hit_normal.dot(dir) >= 0.0:
			continue  ## Not an interior-facing surface — skip

		# Confirm the hit is actually a wall/pillar or GridMap geometry.
		# Also track whether it's a player-placed interior wall vs GridMap perimeter.
		var is_wall: bool = false
		var is_player_wall: bool = false
		var node: Node = hit.get("collider")
		while node != null:
			if node.has_meta("tile_id"):
				var tid: int = node.get_meta("tile_id")
				if tid == _owner.TILE_WALL or tid == _owner.TILE_PILLAR:
					is_wall = true
					## Only treat as player wall if it is NOT a pregen/autofill structure.
					## Pregen walls have _is_pregen meta and must pass the interior-face
					## check — they are NOT freely placeable by the player.
					is_player_wall = not node.has_meta("_is_pregen")
				break
			if node is GridMap:
				is_wall = true
				break
			node = node.get_parent()
		if not is_wall:
			continue

		## For pregen/autofill walls and GridMap: reject side faces and exterior faces.
		## Only the interior-facing surface of each boundary wall is valid.
		if not is_player_wall and _owner.rock_surround != null:
			if not _is_pregen_interior_face(hit["position"], hit_normal):
				continue

		var hit_dist: float = origin.distance_to(hit["position"])
		if hit_dist < best_dist:
			best_dist = hit_dist
			# Snap position: pull back from wall surface by half wall thickness
			# so the light back face is flush, not buried inside the wall.
			var snapped_xz: Vector3 = hit["position"] - dir * _owner.LIGHT_WALL_HALF_THICKNESS
			best_result = {
				"pos":       Vector3(snapped_xz.x, base_pos.y, snapped_xz.z),
				"angle_deg": d["angle_deg"],
			}
			best_is_player_wall = is_player_wall

	# Discard the result if the snap position is invalid.
	# For GridMap perimeter walls we apply strict interior-boundary filtering so lights
	# can't be placed on outer rock faces or exterior wall surfaces.
	if not best_result.is_empty() and _owner.rock_surround != null and not best_is_player_wall:
		if not _owner._is_inside_bunker(best_result["pos"]):
			return {}

	## Wall snap is the final word — NO wire-node XZ override here.
	## Wire connection is handled by BreakerBox/_auto_connect_to_nearby_wires()
	## at registration time, not by position-matching during ghost placement.

	return best_result


## Snap a circuit breaker to the nearest interior wall surface.
## Identical logic to _snap_light_to_wall but uses the breaker's half-depth
## (0.07 m = BoxMesh Z/2) as the pull-back offset instead of _owner.LIGHT_WALL_HALF_THICKNESS.
## Breaker centre Y = placement_y (it self-offsets its mesh like a wall panel).
## Returns {} if no wall found within _owner.LIGHT_WALL_SNAP_RANGE.
func _snap_breaker_to_wall(base_pos: Vector3) -> Dictionary:
	const BREAKER_HALF_DEPTH: float = 0.07
	var cast_y: float   = base_pos.y + 0.22
	var origin: Vector3 = Vector3(base_pos.x, cast_y, base_pos.z)

	var directions: Array[Dictionary] = [
		{ "dir": Vector3( 0, 0,  1), "angle_deg":   0.0 },
		{ "dir": Vector3( 0, 0, -1), "angle_deg": 180.0 },
		{ "dir": Vector3( 1, 0,  0), "angle_deg":  90.0 },
		{ "dir": Vector3(-1, 0,  0), "angle_deg": 270.0 },
	]

	var space: PhysicsDirectSpaceState3D = _owner.get_world_3d().direct_space_state
	var player: Node3D = _owner.get_parent()
	var best_dist: float        = _owner.LIGHT_WALL_SNAP_RANGE
	var best_result: Dictionary = {}
	var best_is_player_wall: bool = false

	for d: Dictionary in directions:
		var dir: Vector3   = d["dir"] as Vector3
		var to_pt: Vector3 = origin + dir * _owner.LIGHT_WALL_SNAP_RANGE

		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to_pt)
		query.collision_mask = 5
		if player.has_method("get_rid"):
			query.exclude = [player.get_rid()]

		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue

		var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
		var normal_dot: float   = hit_normal.dot(dir)
		if normal_dot >= 0.0:
			continue

		## Walk up collider tree to classify the hit surface.
		var is_wall: bool        = false
		var is_player_wall: bool = false
		var is_pregen: bool      = false
		var hit_tile_id: int     = -1
		var node: Node = hit.get("collider")
		var walk_node: Node = node
		while walk_node != null:
			if walk_node.has_meta("_is_pregen"):
				is_pregen = true
			if walk_node.has_meta("tile_id"):
				hit_tile_id = walk_node.get_meta("tile_id") as int
				if hit_tile_id == _owner.TILE_WALL or hit_tile_id == _owner.TILE_PILLAR:
					is_wall = true
					## Player wall = has tile_id but NOT pregen tag
					is_player_wall = not is_pregen
				break
			if walk_node is GridMap:
				is_wall = true
				break
			walk_node = walk_node.get_parent()

		if not is_wall:
			continue

		## Pregen walls (and raw GridMap) must pass the interior-face check.
		if not is_player_wall and _owner.rock_surround != null:
			if not _is_pregen_interior_face(hit["position"], hit_normal):
				continue

		var hit_dist: float = origin.distance_to(hit["position"])
		if hit_dist < best_dist:
			best_dist = hit_dist
			var snapped_xz: Vector3 = hit["position"] - dir * BREAKER_HALF_DEPTH
			## ── Snap BOTH axes to the 0.25 m wire grid ───────────────────────
			## The wire runs at exact 0.25 m grid coordinates (e.g. Z=4.5).
			## The physical wall face sits slightly proud of that (e.g. Z=4.72).
			##
			## Problem: the breaker visual lands at Z=4.72 (wall face minus half-
			## depth), but the wire/PM split is at Z=4.5.  The colour boundary
			## therefore appears 0.22 m away from the breaker centre.
			##
			## Fix: snap the wall-perpendicular axis (the one pointing INTO the
			## wall, i.e. dir's dominant axis) toward the bunker interior using
			## floor/ceil instead of round.  "Interior" is OPPOSITE to the wall
			## normal (dir), so:
			##   dir.z > 0  → interior is −Z → snap with floor
			##   dir.z < 0  → interior is +Z → snap with ceil
			##   dir.x > 0  → interior is −X → snap with floor
			##   dir.x < 0  → interior is +X → snap with ceil
			## The along-wall axis (the other one) simply uses round — it is
			## already close enough to the grid since the player aimed there.
			var final_x: float = snapped_xz.x
			var final_z: float = snapped_xz.z
			if absf(dir.z) > 0.5:
				## Z-facing wall: perp axis = Z, along-wall axis = X
				final_x = roundf(snapped_xz.x / _owner.grid_size) * _owner.grid_size
				if dir.z > 0.0:
					final_z = floorf(snapped_xz.z / _owner.grid_size) * _owner.grid_size  ## interior = −Z
				else:
					final_z = ceilf(snapped_xz.z / _owner.grid_size) * _owner.grid_size   ## interior = +Z
			else:
				## X-facing wall: perp axis = X, along-wall axis = Z
				final_z = roundf(snapped_xz.z / _owner.grid_size) * _owner.grid_size
				if dir.x > 0.0:
					final_x = floorf(snapped_xz.x / _owner.grid_size) * _owner.grid_size  ## interior = −X
				else:
					final_x = ceilf(snapped_xz.x / _owner.grid_size) * _owner.grid_size   ## interior = +X
			best_result = {
				"pos":       Vector3(final_x, base_pos.y, final_z),
				"angle_deg": d["angle_deg"],
			}
			best_is_player_wall = is_player_wall

	if not best_result.is_empty() and _owner.rock_surround != null and not best_is_player_wall:
		var inside: bool = _owner._is_inside_bunker(best_result["pos"])
		if not inside:
			return {}

	return best_result


## Returns true if the hit point + hit normal represent a valid interior-facing
## surface of a pregen bunker boundary wall.
##
## The pregen bunker is a rectangle defined by:
##   X ∈ [OFFSET_X,  OFFSET_X + bunker_depth]
##   Z ∈ [OFFSET_Z,  OFFSET_Z + bunker_width]
##
## Each of the four boundary edges has exactly one valid inward-pointing normal:
##   Left wall   (x ≈ OFFSET_X):             normal must be ≈ +X
##   Right wall  (x ≈ OFFSET_X + depth):     normal must be ≈ -X
##   Front wall  (z ≈ OFFSET_Z):             normal must be ≈ +Z
##   Back wall   (z ≈ OFFSET_Z + width):     normal must be ≈ -Z
##
## A side face (end of a wall cell) or exterior face has a normal that won't
## match the expected inward normal for the nearest boundary — so it's rejected.
## This prevents breakers from snapping to the sides or exterior of pregen walls.
##
## _is_pregen_interior_face — only accept hits on the inward-facing face of a
## pregen boundary wall.  Corner geometry used to bleed through because a hit
## near a corner is within tolerance of TWO boundary edges simultaneously; the
## old code accepted it for whichever edge's normal matched first, which could
## be the wrong axis (e.g. Z-face of the right wall's corner pillar passing the
## back-wall Z-boundary check).
##
## Fix: find the SINGLE closest boundary, then only test that boundary's normal.
## This means a corner pillar Z-face will only be accepted if the Z-boundary is
## closer than the X-boundary — which it isn't for a right-wall corner hit.
func _is_pregen_interior_face(hit_pos: Vector3, hit_normal: Vector3) -> bool:
	if _owner.rock_surround == null:
		return true   ## No bounds data — allow

	## Tightened from 0.75 → 0.55 to reduce tolerance to just the wall thickness.
	## Must be > 0 (physics skin) but small enough that the corner pillar face on
	## one axis doesn't bleed into the adjacent boundary's tolerance zone.
	const WALL_FACE_TOL: float  = 0.55
	const NORMAL_DOT_MIN: float = 0.85   ## cos(≈32°) — must be nearly axis-aligned

	var ox: float    = _owner.rock_surround.OFFSET_X
	var oz: float    = _owner.rock_surround.OFFSET_Z
	var depth: float = float(_owner.rock_surround.bunker_depth)
	var width: float = float(_owner.rock_surround.bunker_width)

	## ── Pass 1: original four perimeter faces ─────────────────────────────
	## Compute distance from hit to each of the four boundary edge planes.
	var dist_left:  float = absf(hit_pos.x - ox)
	var dist_right: float = absf(hit_pos.x - (ox + depth))
	var dist_front: float = absf(hit_pos.z - oz)
	var dist_back:  float = absf(hit_pos.z - (oz + width))

	## Build a candidate list: only boundaries within tolerance.
	## We then pick the CLOSEST one and test only its expected inward normal.
	## This prevents a corner hit from matching the wrong axis's boundary.
	var best_dist:   float   = WALL_FACE_TOL + 1.0   ## sentinel > TOL
	var best_normal: Vector3 = Vector3.ZERO

	if dist_left <= WALL_FACE_TOL and dist_left < best_dist:
		best_dist   = dist_left
		best_normal = Vector3(1, 0, 0)   ## interior faces +X

	if dist_right <= WALL_FACE_TOL and dist_right < best_dist:
		best_dist   = dist_right
		best_normal = Vector3(-1, 0, 0)  ## interior faces -X

	if dist_front <= WALL_FACE_TOL and dist_front < best_dist:
		best_dist   = dist_front
		best_normal = Vector3(0, 0, 1)   ## interior faces +Z

	if dist_back <= WALL_FACE_TOL and dist_back < best_dist:
		best_dist   = dist_back
		best_normal = Vector3(0, 0, -1)  ## interior faces -Z

	if best_normal != Vector3.ZERO:
		## Accept only if the hit normal aligns with the inward direction.
		return hit_normal.dot(best_normal) >= NORMAL_DOT_MIN

	## ── Pass 2: exposed faces of deconstructed rock chunks ────────────────
	## When a chunk is dug out, its 4 axis-aligned faces become valid snap
	## surfaces.  A face is valid when it borders a SOLID (non-deconstructed)
	## chunk or lies on the original bunker rectangle boundary.
	##
	## Strategy: find which chunk the hit point sits in, confirm it is
	## deconstructed, then check whether the hit normal points AWAY from a
	## solid neighbour (i.e. the solid side is in the direction -hit_normal).
	if _owner.rock_surround.has_method("get_chunk_at_world_pos") and \
	   _owner.rock_surround.has_method("is_chunk_active"):

		var chunk_id: Vector2i = _owner.rock_surround.get_chunk_at_world_pos(hit_pos)
		if chunk_id == Vector2i(-9999, -9999):
			return false   ## Hit not within any known chunk

		## The hit must be inside a deconstructed (dug) chunk — the rock face
		## we're hitting is the exposed wall of that excavation.
		if _owner.rock_surround.is_chunk_active(chunk_id):
			return false   ## Chunk still has rock — don't allow snap here

		## The normal must be nearly axis-aligned.
		if absf(hit_normal.x) < NORMAL_DOT_MIN and absf(hit_normal.z) < NORMAL_DOT_MIN:
			return false

		## The face is valid only if the chunk in the direction of the hit normal
		## is SOLID (active) — meaning this face borders rock or original wall.
		## Direction toward the solid side = hit_normal (the normal points INTO
		## the dug space, i.e. away from the solid rock).
		var cs: int = _owner.rock_surround.chunk_size

		## Dominant axis of hit_normal determines which neighbour to check.
		var nx: int = 0
		var nz: int = 0
		if absf(hit_normal.x) >= NORMAL_DOT_MIN:
			nx = 1 if hit_normal.x > 0.0 else -1
		else:
			nz = 1 if hit_normal.z > 0.0 else -1

		var neighbour_id: Vector2i = Vector2i(chunk_id.x + nx, chunk_id.y + nz)

		## Neighbour is solid if it is an active chunk, or if it doesn't exist at
		## all (means it's outside the rock ring entirely — i.e. original perimeter).
		var neighbour_solid: bool = false
		if not _owner.rock_surround.has_method("get_chunk_at_world_pos"):
			neighbour_solid = true   ## Fallback — allow
		else:
			## Build world pos of neighbour centre to look it up.
			var nb_world_x: float = ox + float(neighbour_id.x * cs) + float(cs) * 0.5
			var nb_world_z: float = oz + float(neighbour_id.y * cs) + float(cs) * 0.5
			var nb_id: Vector2i = _owner.rock_surround.get_chunk_at_world_pos(
				Vector3(nb_world_x, hit_pos.y, nb_world_z))
			if nb_id == Vector2i(-9999, -9999):
				## No chunk there — original perimeter wall or outside ring.
				neighbour_solid = true
			elif _owner.rock_surround.is_chunk_active(nb_id):
				neighbour_solid = true   ## Active rock chunk = solid neighbour

		return neighbour_solid

	return false
