extends Node3D
class_name Poster
## Poster.gd
## Basic wall-mounted poster — blank canvas with a visible frame border, the
## baseline decor object other wall art will build on later (swap the
## texture/material in, keep the mount/snap logic). Wall-snapped like
## WallLight, but via the generic _snap_to_nearest_wall() helper rather than
## the light-specific one (see BuildModeController wiring below).
##
## COLLISION NOTE: unlike WallLight (a genuinely zero-collision Node3D),
## Poster gets a thin flush-mounted collision box on layer 5 (player +
## build-hover, same convention Shelving/Bed/Table use). This is
## deliberate: BuildModeController._get_hovered_placed_body() (the function
## the Deconstruct tool uses to find what's under the cursor) raycasts
## against layer-3-only colliders — an object with zero collision can be
## placed but not deconstructed via mouse hover. Because the poster sits
## flush and is only 0.03m thick, this collision is imperceptible to player
## movement in practice.

const POSTER_WIDTH: float     = 0.90
const POSTER_HEIGHT: float    = 1.30
const POSTER_THICKNESS: float = 0.03

## Blank canvas — light neutral so it reads clearly against the darker
## concrete wall material regardless of lighting, with a darker frame
## border so the edges are always visible even under flat/no directional
## light (a pure flat fill could otherwise blend into shadowed walls).
const COLOR_CANVAS: Color = Color(0.93, 0.91, 0.85, 1.0)
const COLOR_FRAME:  Color = Color(0.22, 0.22, 0.22, 1.0)
const FRAME_BORDER: float = 0.05   ## Frame width visible around the canvas edge

## Full-fidelity preview mode — same convention as every other furniture
## script in this codebase (see Bed.gd's own comment for the full writeup).
## Poster has nothing to register (no power, no groups beyond "interactable"
## it doesn't even join), so this guard only matters for staying consistent
## with the pattern other scripts rely on.
var _is_preview_only: bool = false

func _ready() -> void:
	_build_mesh()
	if _is_preview_only:
		return
	collision_layer = 5   ## Player + build-hover raycast — see class comment
	collision_mask  = 0

func _build_mesh() -> void:
	## Frame — slightly larger box behind the canvas, reads as a border.
	var frame_mat: StandardMaterial3D = StandardMaterial3D.new()
	frame_mat.albedo_color = COLOR_FRAME
	frame_mat.metallic  = 0.0
	frame_mat.roughness = 0.9

	var frame_mi:   MeshInstance3D = MeshInstance3D.new()
	var frame_mesh: BoxMesh        = BoxMesh.new()
	frame_mesh.size = Vector3(POSTER_WIDTH, POSTER_HEIGHT, POSTER_THICKNESS)
	frame_mi.mesh   = frame_mesh
	frame_mi.set_surface_override_material(0, frame_mat)
	add_child(frame_mi)

	## Canvas — blank fill, inset from the frame edge by FRAME_BORDER,
	## pushed slightly forward (+Z local, toward the room) so it doesn't
	## z-fight with the frame box behind it.
	var canvas_mat: StandardMaterial3D = StandardMaterial3D.new()
	canvas_mat.albedo_color = COLOR_CANVAS
	canvas_mat.metallic  = 0.0
	canvas_mat.roughness = 0.95

	var canvas_mi:   MeshInstance3D = MeshInstance3D.new()
	var canvas_mesh: BoxMesh        = BoxMesh.new()
	canvas_mesh.size = Vector3(
		POSTER_WIDTH  - FRAME_BORDER * 2.0,
		POSTER_HEIGHT - FRAME_BORDER * 2.0,
		POSTER_THICKNESS * 0.4
	)
	canvas_mi.mesh = canvas_mesh
	canvas_mi.position = Vector3(0.0, 0.0, POSTER_THICKNESS * 0.35)
	canvas_mi.set_surface_override_material(0, canvas_mat)
	add_child(canvas_mi)

	if not _is_preview_only:
		frame_mi.create_trimesh_collision()
		for child in frame_mi.get_children():
			if child is StaticBody3D:
				(child as StaticBody3D).collision_layer = 5
				(child as StaticBody3D).collision_mask  = 0

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(POSTER_WIDTH, POSTER_HEIGHT, POSTER_THICKNESS)
	return box