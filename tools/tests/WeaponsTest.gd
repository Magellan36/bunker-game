extends Node3D
## F6 this scene. Uses the real player, pickup system, inventory, and camera.
var _player: Player
var _status: Label

func _ready() -> void:
	add_to_group("world")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.035, 0.045, 0.065)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.7, 0.85)
	env.environment.ambient_light_energy = 0.45
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 0.6
	light.shadow_enabled = true
	add_child(light)
	_box(Vector3(24, 0.3, 24), Vector3(0, -0.15, 0), Color(0.14, 0.17, 0.2))
	_box(Vector3(2, 2.4, 0.2), Vector3(3, 1.2, -4), Color(0.23, 0.29, 0.32))
	_player = preload("res://scenes/player/Player.tscn").instantiate()
	_player.position = Vector3(0, 1, 2)
	add_child(_player)
	var inventory: Node = preload("res://scripts/ui/inventory/InventoryManager.gd").new()
	add_child(inventory)
	_player.interaction_system.inventory = inventory
	var camera := Camera3D.new()
	camera.set_script(preload("res://scripts/core/GameCamera.gd"))
	camera.target_path = camera.get_path_to(_player) if camera.is_inside_tree() else NodePath("../" + str(_player.name))
	camera.current = true
	add_child(camera)
	for i: int in 6:
		var item: RigidBody3D = load("res://scenes/weapons/%s.tscn" % ["Webley", "Knife", "Hatchet", "Pipe", "Bat", "Crowbar"][i]).instantiate()
		item.position = Vector3(-1.8 + i * 1.0, 0.4, 0.5)
		add_child(item)
	for x: float in [-3.0, 0.0, 3.0]:
		var target := StaticBody3D.new()
		target.set_script(preload("res://scripts/weapons/WeaponTestTarget.gd"))
		target.position = Vector3(x, 1, -6)
		add_child(target)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_status = Label.new()
	_status.position = Vector2(24, 24)
	canvas.add_child(_status)

func _process(_delta: float) -> void:
	var held: Node = _player.get_held_item()
	_status.text = "WEAPONS TEST ROOM\nWASD / Left stick: Move   F / X: Pick up or drop   G: Store   Wheel: Inventory\nHold RMB / Right stick: Aim   LMB / RT: Attack   E / A: Reload\nTargets count hits. The right target is behind a wall."
	if is_instance_valid(held):
		_status.text += "\nHolding: " + held.get_display_name() + "\n" + held.get_use_prompt()
	else:
		_status.text += "\nWalk up to a weapon on the floor and press F / X."

func _box(size: Vector3, position_: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = position_
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
