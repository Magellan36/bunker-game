extends StaticBody3D
class_name Chair
## Chair.gd
## Interactable chair. Player presses E nearby to sit; E again to stand.
## No animation yet — player capsule is repositioned and partially sunk into
## the seat while seated (see get_seat_transform()). Movement is frozen while
## seated, same convention Bed/SleepOverlay uses (player.set_physics_process).
## Chair's local -Z axis is its "front" (open, seat-facing) side — same
## forward-axis convention used by Bed/Generator ghost-arrow indicators.

const SEAT_Y: float       = 0.5625  ## was 0.45 → ×1.25
const SEAT_THICKNESS: float = 0.0625 ## was 0.05 → ×1.25
const BACK_HEIGHT: float  = 0.5625  ## was 0.45 → ×1.25
const LEG_HEIGHT: float   = SEAT_Y - SEAT_THICKNESS * 0.5   ## unchanged formula — auto-scales
const FOOTPRINT: float    = 0.625   ## was 0.50 → ×1.25

const COLOR_BEIGE: Color = Color(0.82, 0.74, 0.60, 1.0)   ## Matches Table.gd for now

## How far the player sinks below the seat surface while "seated" (placeholder
## for a proper sit animation — see class comment).
const SIT_SINK: float     = 0.30
## How far in front of the chair (along local +Z, away from the backrest)
## the player is placed on standing up.
const STAND_DIST: float   = 0.65   ## was 0.55

var _is_preview_only: bool = false   ## Same convention as Bed.gd/Shelving.gd — see those files' comment for the full writeup.

signal seat_requested()
signal stand_requested()

var _player_in_range: bool = false
var _player_seated: bool   = false

func _ready() -> void:
	if _is_preview_only:
		return
	add_to_group("interactable")
	add_to_group("chair")   ## Used by MainWorld._connect_chair() to wire all placed chairs
	collision_layer = 5
	collision_mask  = 0
	_build_mesh()

func _build_mesh() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = COLOR_BEIGE
	mat.metallic  = 0.0
	mat.roughness = 0.85

	## 4 thin legs under the seat corners.
	var leg_positions: Array[Vector2] = [
		Vector2(-FOOTPRINT * 0.5 + 0.05, -FOOTPRINT * 0.5 + 0.05),
		Vector2( FOOTPRINT * 0.5 - 0.05, -FOOTPRINT * 0.5 + 0.05),
		Vector2(-FOOTPRINT * 0.5 + 0.05,  FOOTPRINT * 0.5 - 0.05),
		Vector2( FOOTPRINT * 0.5 - 0.05,  FOOTPRINT * 0.5 - 0.05),
	]
	for p: Vector2 in leg_positions:
		var leg_mi: MeshInstance3D = MeshInstance3D.new()
		var leg_mesh: CylinderMesh = CylinderMesh.new()
		leg_mesh.top_radius = 0.02
		leg_mesh.bottom_radius = 0.02
		leg_mesh.height = LEG_HEIGHT
		leg_mesh.radial_segments = 8
		leg_mi.mesh = leg_mesh
		leg_mi.position = Vector3(p.x, LEG_HEIGHT * 0.5, p.y)
		leg_mi.set_surface_override_material(0, mat)
		add_child(leg_mi)

	## Seat slab.
	var seat_mi:   MeshInstance3D = MeshInstance3D.new()
	var seat_mesh: BoxMesh        = BoxMesh.new()
	seat_mesh.size = Vector3(FOOTPRINT, SEAT_THICKNESS, FOOTPRINT)
	seat_mi.mesh   = seat_mesh
	seat_mi.position = Vector3(0.0, SEAT_Y, 0.0)
	seat_mi.set_surface_override_material(0, mat)
	add_child(seat_mi)
	seat_mi.create_trimesh_collision()
	for child in seat_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Backrest — thin vertical slab at the -Z edge (back of chair; +Z is "front"/open side).
	var back_mi:   MeshInstance3D = MeshInstance3D.new()
	var back_mesh: BoxMesh        = BoxMesh.new()
	back_mesh.size = Vector3(FOOTPRINT, BACK_HEIGHT, 0.05)
	back_mi.mesh   = back_mesh
	back_mi.position = Vector3(0.0, SEAT_Y + BACK_HEIGHT * 0.5, -FOOTPRINT * 0.5 + 0.025)
	back_mi.set_surface_override_material(0, mat)
	add_child(back_mi)

# ─── Interaction ────────────────────────────────────────────────────────────
func on_interact() -> void:
	if not _player_in_range:
		return
	if not _player_seated:
		seat_requested.emit()
	else:
		stand_requested.emit()

func get_prompt_text() -> String:
	if _player_seated:
		return "[E] Stand"
	return "[E] Sit"

func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range

func set_seated(seated: bool) -> void:
	_player_seated = seated

# ─── Positioning API (consumed by MainWorld — see Part 3) ──────────────────
## World transform the player should be moved to while seated. Y is sunk
## below the seat surface by SIT_SINK (placeholder for a real sit animation).
func get_seat_transform() -> Transform3D:
	var local_pos: Vector3 = Vector3(0.0, SEAT_Y - SIT_SINK, 0.0)
	var world_pos: Vector3 = global_transform * local_pos
	var t: Transform3D = Transform3D(global_transform.basis, world_pos)
	return t

## World position the player should be moved to on standing — in front of the
## chair (local +Z, the open/non-backrest side), at floor height.
func get_stand_position() -> Vector3:
	var local_pos: Vector3 = Vector3(0.0, 0.0, STAND_DIST)
	return global_transform * local_pos

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(FOOTPRINT, SEAT_Y + BACK_HEIGHT, FOOTPRINT)
	return box