extends RefCounted
## Short-lived feedback, deliberately excluded from item/save/pickup groups.
const MAX_CASES: int = 16

static func eject_case(weapon: Node3D, pose: Transform3D) -> void:
	var cases: Array[Node] = weapon.get_tree().get_nodes_in_group("weapon_cases")
	if cases.size() >= MAX_CASES:
		cases[0].queue_free()
	var body := RigidBody3D.new()
	body.mass = 0.015
	body.collision_layer = 0
	body.collision_mask = 1
	body.continuous_cd = true
	body.add_to_group("weapon_cases")
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.012
	cylinder.bottom_radius = 0.012
	cylinder.height = 0.045
	cylinder.radial_segments = 6
	mesh.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.73, 0.49, 0.14)
	material.metallic = 0.75
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.022
	collision.shape = shape
	body.add_child(collision)
	weapon.get_tree().current_scene.add_child(body)
	body.global_transform = pose
	body.global_position += pose.basis.x * 0.12
	body.linear_velocity = pose.basis.x * 1.4 + Vector3.UP * 1.8
	body.angular_velocity = Vector3(8, 3, 11)
	var timer := Timer.new()
	timer.wait_time = 4.0
	timer.one_shot = true
	timer.timeout.connect(body.queue_free)
	body.add_child(timer)
	timer.start()

static func impact(weapon: Node3D, position: Vector3, normal: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	mesh.mesh = sphere
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.82, 0.52)
	mesh.material_override = material
	weapon.get_tree().current_scene.add_child(mesh)
	mesh.global_position = position + normal * 0.025
	var tween: Tween = mesh.create_tween()
	tween.tween_property(mesh, "scale", Vector3.ONE * 0.01, 0.10)
	tween.tween_callback(mesh.queue_free)
