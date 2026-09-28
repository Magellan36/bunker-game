extends Node
## Owns weapon input only. Runs after movement, before weapon pose/attacks.
const Weapon = preload("res://scripts/weapons/WeaponItem.gd")
const Reticle = preload("res://scripts/weapons/WeaponReticle.gd")
var _reticle: Reticle
var interaction: Node
var _weapon: Weapon
var _mouse_aim: bool = false
var _attack_pending: bool = false
var _aim_yaw: float = 0.0
var _was_aiming: bool = false
var _trigger_down: bool = false
var _focused: bool = true
var _direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	interaction = get_parent()
	process_physics_priority = 10
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	_reticle = Reticle.new()
	canvas.add_child(_reticle)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_reset()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true

func _reset() -> void:
	_mouse_aim = false
	_attack_pending = false
	_was_aiming = false
	_trigger_down = false
	for device: int in Input.get_connected_joypads():
		if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.35:
			_trigger_down = true
	if is_instance_valid(_reticle):
		_reticle.hide()
	if is_instance_valid(_weapon):
		_weapon.cancel_action()

func _input(event: InputEvent) -> void:
	# Observe release even when a UI consumes the event later; never consume here.
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_TRIGGER_RIGHT and event.axis_value < 0.35:
		_trigger_down = false

func _unhandled_input(event: InputEvent) -> void:
	if not _focused or not interaction.can_use_weapon() or not interaction.held_item is Weapon:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_aim = event.pressed
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _mouse_aim:
			_attack_pending = true
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_TRIGGER_RIGHT:
		var pressed: bool = event.axis_value > 0.55
		if pressed and not _trigger_down:
			_attack_pending = true
		_trigger_down = pressed
		if pressed:
			get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	var held: Weapon = interaction.held_item as Weapon
	if held != _weapon:
		if is_instance_valid(_weapon) and _weapon.hit_resolved.is_connected(_on_hit):
			_weapon.hit_resolved.disconnect(_on_hit)
		_reset()
		_weapon = held
		if is_instance_valid(_weapon):
			_weapon.hit_resolved.connect(_on_hit)
	if not is_instance_valid(_weapon) or not interaction.can_use_weapon() or not _focused:
		_reset()
		return
	if _mouse_aim and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_mouse_aim = false
	var player: CharacterBody3D = interaction.player
	var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var aim: bool = _mouse_aim or stick.length_squared() > 0.01
	var target_direction: Vector3 = Vector3.ZERO
	if _mouse_aim:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			var mouse: Vector2 = get_viewport().get_mouse_position()
			var plane := Plane(Vector3.UP, _weapon.get_aim_origin().y)
			var point: Variant = plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
			if point != null:
				target_direction = point - Vector3(player.global_position.x, plane.d, player.global_position.z)
	elif aim:
		target_direction = Vector3(stick.x, 0, stick.y).rotated(Vector3.UP, player.camera_yaw_rad)
	if aim:
		if not _was_aiming:
			_aim_yaw = player.rotation.y
		if target_direction.length_squared() > 0.01:
			_aim_yaw = lerp_angle(_aim_yaw, atan2(-target_direction.x, -target_direction.z), 1.0 - exp(-24.0 * delta))
		player.rotation.y = _aim_yaw
		_direction = -player.global_basis.z
	_weapon.set_aiming(aim)
	_weapon.sync_held_pose()
	if _attack_pending and aim:
		_weapon.try_attack(_direction)
	_attack_pending = false
	_was_aiming = aim
	_reticle.visible = aim
	if aim:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			_reticle.aim_position = get_viewport().get_mouse_position() if _mouse_aim else camera.unproject_position(_weapon.global_position + _direction * minf(_weapon.reach, 7.0))
		_reticle.empty = _weapon.is_firearm() and _weapon.ammo == 0
		_reticle.rounds = ("Reloading…" if _weapon._reload_left > 0.0 else "%d / %d" % [_weapon.ammo, _weapon.reserve_ammo]) if _weapon.is_firearm() else ""

func _on_hit(hit: Dictionary) -> void:
	var receiver: Node = hit.collider as Node
	while receiver != null:
		if receiver.has_method("receive_weapon_hit"):
			_reticle.hit_time = 0.15
			return
		receiver = receiver.get_parent()
