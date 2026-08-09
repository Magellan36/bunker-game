extends PickupableItem
## TestCrate.gd
## Carriable crate. While held, stays in world tree and lerps to hold point
## every physics frame — no reparenting during carry.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var item_name: String = "Crate"

## Shelf stacking — 1 crate per slot (too large to stack)
var shelf_stack_limit: int   = 1
var shelf_item_type: String  = "test_crate"

var _mesh: MeshInstance3D = null

func _ready() -> void:
	super._ready()
	_mesh = get_node_or_null("Model/MeshInstance3D")
	if _mesh == null:
		_build_placeholder_mesh()

func get_prompt_text() -> String:
	return "[F] Pick up %s" % item_name

## Aug 2026 — was missing entirely, so every NPC-facing log/UI surface
## fell back to PickupableItem's generic "Item" default. NPCs need real
## per-object identity now (Cleaning logs, and every future job that
## touches specific objects), not just the player-facing F-prompt text.
func get_display_name() -> String:
	return item_name

## Procedural milk crate — dark blue/grey plastic with lattice-style
## reinforcement ribs on each face, corner pillars, and handle cutouts.
func _build_placeholder_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.position = Vector3(0.0, 0.019, 0.0)

	var crate_mat: StandardMaterial3D = StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.22, 0.25, 0.30, 1.0)
	crate_mat.roughness    = 0.75
	crate_mat.metallic     = 0.05

	var rib_mat: StandardMaterial3D = StandardMaterial3D.new()
	rib_mat.albedo_color = Color(0.18, 0.21, 0.26, 1.0)
	rib_mat.roughness    = 0.80
	rib_mat.metallic     = 0.05

	var handle_mat: StandardMaterial3D = StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.15, 0.18, 0.22, 1.0)
	handle_mat.roughness    = 0.70
	handle_mat.metallic     = 0.08

	## Crate dimensions.
	var W: float = 0.54
	var H: float = 0.48
	var D: float = 0.73
	var T: float = 0.018

	## Bottom plate.
	var bottom: MeshInstance3D = MeshInstance3D.new()
	bottom.mesh = BoxMesh.new()
	(bottom.mesh as BoxMesh).size = Vector3(W, T, D)
	bottom.position = Vector3(0.0, -H * 0.5 + T * 0.5, 0.0)
	bottom.set_surface_override_material(0, crate_mat)
	_mesh.add_child(bottom)

	## Front wall.
	var front: MeshInstance3D = MeshInstance3D.new()
	front.mesh = BoxMesh.new()
	(front.mesh as BoxMesh).size = Vector3(W, H, T)
	front.position = Vector3(0.0, 0.0, -D * 0.5 + T * 0.5)
	front.set_surface_override_material(0, crate_mat)
	_mesh.add_child(front)

	## Back wall.
	var back: MeshInstance3D = MeshInstance3D.new()
	back.mesh = BoxMesh.new()
	(back.mesh as BoxMesh).size = Vector3(W, H, T)
	back.position = Vector3(0.0, 0.0, D * 0.5 - T * 0.5)
	back.set_surface_override_material(0, crate_mat)
	_mesh.add_child(back)

	## Left wall.
	var left: MeshInstance3D = MeshInstance3D.new()
	left.mesh = BoxMesh.new()
	(left.mesh as BoxMesh).size = Vector3(T, H, D)
	left.position = Vector3(-W * 0.5 + T * 0.5, 0.0, 0.0)
	left.set_surface_override_material(0, crate_mat)
	_mesh.add_child(left)

	## Right wall.
	var right: MeshInstance3D = MeshInstance3D.new()
	right.mesh = BoxMesh.new()
	(right.mesh as BoxMesh).size = Vector3(T, H, D)
	right.position = Vector3(W * 0.5 - T * 0.5, 0.0, 0.0)
	right.set_surface_override_material(0, crate_mat)
	_mesh.add_child(right)

	## Lattice ribs on front face — horizontal bars.
	for i: int in 4:
		var y: float = -H * 0.35 + i * (H * 0.7 / 3.0)
		var rib: MeshInstance3D = MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(W * 0.92, 0.008, 0.006)
		rib.position = Vector3(0.0, y, -D * 0.5 + T + 0.003)
		rib.set_surface_override_material(0, rib_mat)
		_mesh.add_child(rib)

	## Lattice ribs on front face — vertical bars.
	for i: int in 5:
		var x: float = -W * 0.36 + i * (W * 0.72 / 4.0)
		var rib: MeshInstance3D = MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(0.008, H * 0.70, 0.006)
		rib.position = Vector3(x, 0.0, -D * 0.5 + T + 0.003)
		rib.set_surface_override_material(0, rib_mat)
		_mesh.add_child(rib)

	## Lattice ribs on back face — horizontal bars.
	for i: int in 4:
		var y: float = -H * 0.35 + i * (H * 0.7 / 3.0)
		var rib: MeshInstance3D = MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(W * 0.92, 0.008, 0.006)
		rib.position = Vector3(0.0, y, D * 0.5 - T - 0.003)
		rib.set_surface_override_material(0, rib_mat)
		_mesh.add_child(rib)

	## Lattice ribs on back face — vertical bars.
	for i: int in 5:
		var x: float = -W * 0.36 + i * (W * 0.72 / 4.0)
		var rib: MeshInstance3D = MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(0.008, H * 0.70, 0.006)
		rib.position = Vector3(x, 0.0, D * 0.5 - T - 0.003)
		rib.set_surface_override_material(0, rib_mat)
		_mesh.add_child(rib)

	## Lattice ribs on left face — horizontal bars.
	for i: int in 4:
		var y: float = -H * 0.35 + i * (H * 0.7 / 3.0)
		var rib: MeshInstance3D = MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(0.006, 0.008, D * 0.92)
		rib.position = Vector3(-W * 0.5 + T + 0.003, y, 0.0)
		rib.set_surface_override_material(0, rib_mat)
		_mesh.add_child(rib)

	## Lattice ribs on left face — vertical bars.
	for i: int in 6:
		var z: float = -D * 0.38 + i * (D * 0.76 / 5.0)
		var rib: MeshInstance3D = MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(0.006, H * 0.70, 0.008)
		rib.position = Vector3(-W * 0.5 + T + 0.003, 0.0, z)
		rib.set_surface_override_material(0, rib_mat)
		_mesh.add_child(rib)

	## Lattice ribs on right face — horizontal bars.
	for i: int in 4:
		var y: float = -H * 0.35 + i * (H * 0.7 / 3.0)
		var rib: MeshInstance3D = MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(0.006, 0.008, D * 0.92)
		rib.position = Vector3(W * 0.5 - T - 0.003, y, 0.0)
		rib.set_surface_override_material(0, rib_mat)
		_mesh.add_child(rib)

	## Lattice ribs on right face — vertical bars.
	for i: int in 6:
		var z: float = -D * 0.38 + i * (D * 0.76 / 5.0)
		var rib: MeshInstance3D = MeshInstance3D.new()
		rib.mesh = BoxMesh.new()
		(rib.mesh as BoxMesh).size = Vector3(0.006, H * 0.70, 0.008)
		rib.position = Vector3(W * 0.5 - T - 0.003, 0.0, z)
		rib.set_surface_override_material(0, rib_mat)
		_mesh.add_child(rib)

	## Corner pillars — thicker vertical bars at all 4 corners.
	for sign_x: int in [-1, 1]:
		for sign_z: int in [-1, 1]:
			var pillar: MeshInstance3D = MeshInstance3D.new()
			pillar.mesh = BoxMesh.new()
			(pillar.mesh as BoxMesh).size = Vector3(0.025, H, 0.025)
			pillar.position = Vector3(sign_x * (W * 0.5 - 0.012), 0.0, sign_z * (D * 0.5 - 0.012))
			pillar.set_surface_override_material(0, handle_mat)
			_mesh.add_child(pillar)

	## Handle frames on left and right — top bar + two side bars.
	for sign_x: int in [-1, 1]:
		## Top bar.
		var h_top: MeshInstance3D = MeshInstance3D.new()
		h_top.mesh = BoxMesh.new()
		(h_top.mesh as BoxMesh).size = Vector3(0.015, 0.015, 0.10)
		h_top.position = Vector3(sign_x * (W * 0.5 - 0.015), H * 0.30, 0.0)
		h_top.set_surface_override_material(0, handle_mat)
		_mesh.add_child(h_top)
		## Left bar.
		var h_left: MeshInstance3D = MeshInstance3D.new()
		h_left.mesh = BoxMesh.new()
		(h_left.mesh as BoxMesh).size = Vector3(0.015, 0.10, 0.015)
		h_left.position = Vector3(sign_x * (W * 0.5 - 0.015), H * 0.22, -0.042)
		h_left.set_surface_override_material(0, handle_mat)
		_mesh.add_child(h_left)
		## Right bar.
		var h_right: MeshInstance3D = MeshInstance3D.new()
		h_right.mesh = BoxMesh.new()
		(h_right.mesh as BoxMesh).size = Vector3(0.015, 0.10, 0.015)
		h_right.position = Vector3(sign_x * (W * 0.5 - 0.015), H * 0.22, 0.042)
		h_right.set_surface_override_material(0, handle_mat)
		_mesh.add_child(h_right)

	## Top rim — thin lip around the open top edge.
	for sign_x: int in [-1, 1]:
		var rim: MeshInstance3D = MeshInstance3D.new()
		rim.mesh = BoxMesh.new()
		(rim.mesh as BoxMesh).size = Vector3(0.015, 0.012, D)
		rim.position = Vector3(sign_x * (W * 0.5 - 0.007), H * 0.5 - 0.006, 0.0)
		rim.set_surface_override_material(0, handle_mat)
		_mesh.add_child(rim)
	for sign_z: int in [-1, 1]:
		var rim: MeshInstance3D = MeshInstance3D.new()
		rim.mesh = BoxMesh.new()
		(rim.mesh as BoxMesh).size = Vector3(W, 0.012, 0.015)
		rim.position = Vector3(0.0, H * 0.5 - 0.006, sign_z * (D * 0.5 - 0.007))
		rim.set_surface_override_material(0, handle_mat)
		_mesh.add_child(rim)

	add_child(_mesh)
