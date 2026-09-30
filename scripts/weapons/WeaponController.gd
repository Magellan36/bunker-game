extends Node
## Owns weapon input only. Runs after movement, before weapon pose/attacks.
const Weapon = preload("res://scripts/weapons/WeaponItem.gd")
const Reticle = preload("res://scripts/weapons/WeaponReticle.gd")
const FistsScript = preload("res://scripts/weapons/Fists.gd")
var _reticle: Reticle
var interaction: Node
## The held WeaponItem, or the player's Fists when the hands are empty.
var _weapon: Node
var _fists: Node3D
## Mouse aim = RMB physically held (tracked from raw events in _input) after a
## press that began in gameplay. A brief block (UI blip, animation lock, item
## swap) only suspends aiming; it never cancels a held RMB, so aim resumes.
var _mouse_aim: bool = false
var _rmb_down: bool = false
## Seconds a press stays queued, so a press during recovery lands the moment
## the weapon is ready (combos feel continuous instead of eating inputs).
const ATTACK_BUFFER: float = 0.18
## Gamepad aim assist: a stick direction within this cone of a valid target
## snaps to it (firearm narrower than melee). Mouse aim is never assisted.
const ASSIST_FIREARM_DEG: float = 10.0
const ASSIST_MELEE_DEG: float = 32.0
const ASSIST_FIREARM_RANGE: float = 12.0
const Melee = preload("res://scripts/weapons/MeleeStrike.gd")
var _buffer_left: float = 0.0
## Gameplay keeps the OS cursor CAPTURED (InputMode), pinned at screen centre,
## i.e. on the player. Mouse aim therefore uses its own virtual point: it
## starts ahead of the player on RMB and moves with raw mouse motion.
const MOUSE_AIM_START: float = 2.5
## The virtual point lives on a ring around the player's screen position, so
## the mouse steers a direction like the right stick does (reversing is one
## small flick, never a long drag back across the screen).
## Radius as a fraction of screen height (≈140 px at 1080p).
const MOUSE_RING_FRACTION: float = 0.13
var _mouse_offset: Vector2 = Vector2(0, -1)   ## from the player on screen, on the ring
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
		_mouse_aim = false
		_reset()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true

func _reset() -> void:
	_buffer_left = 0.0
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
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_rmb_down = event.pressed
		if not event.pressed:
			_mouse_aim = false
	elif event is InputEventMouseMotion and _mouse_aim:
		_steer_mouse_point(event.relative)

func _unhandled_input(event: InputEvent) -> void:
	if not _focused or not interaction.can_use_weapon() or not (interaction.held_item is Weapon or interaction.held_item == null):
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and not _mouse_aim:
				_start_mouse_point()
				_mouse_aim = true
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _mouse_aim:
			_buffer_left = ATTACK_BUFFER
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		if is_instance_valid(_weapon) and _weapon.is_firearm():
			_weapon.reload()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_TRIGGER_RIGHT:
		var pressed: bool = event.axis_value > 0.55
		if pressed and not _trigger_down:
			_buffer_left = ATTACK_BUFFER
		_trigger_down = pressed
		if pressed:
			get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	var held: Node = interaction.held_item as Weapon
	if interaction.held_item == null and is_instance_valid(interaction.player):
		if _fists == null:
			_fists = FistsScript.new()
			interaction.player.add_child(_fists)
		held = _fists
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
	if _mouse_aim and not _rmb_down:
		_mouse_aim = false
	var player: CharacterBody3D = interaction.player
	var stick: Vector2 = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var aim: bool = _mouse_aim or stick.length_squared() > 0.01
	var target_direction: Vector3 = Vector3.ZERO
	if _mouse_aim:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			var mouse: Vector2 = _player_screen() + _mouse_offset
			var plane := Plane(Vector3.UP, _weapon.get_aim_origin().y)
			var point: Variant = plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
			if point != null:
				target_direction = point - Vector3(player.global_position.x, plane.d, player.global_position.z)
	elif aim:
		target_direction = _assist(player, Vector3(stick.x, 0, stick.y).rotated(Vector3.UP, player.camera_yaw_rad))
	if aim:
		if not _was_aiming:
			_aim_yaw = player.rotation.y
		if target_direction.length_squared() > 0.01:
			_aim_yaw = lerp_angle(_aim_yaw, atan2(-target_direction.x, -target_direction.z), 1.0 - exp(-24.0 * delta))
		player.rotation.y = _aim_yaw
		_direction = -player.global_basis.z
	_weapon.set_aiming(aim)
	_weapon.sync_held_pose()
	if _buffer_left > 0.0 and aim:
		if _weapon.try_attack(_direction):
			_buffer_left = 0.0
		else:
			_buffer_left = maxf(0.0, _buffer_left - delta)
	elif not aim:
		_buffer_left = 0.0
	_was_aiming = aim
	_reticle.visible = aim
	if aim:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			## Mouse and pad share one placement: a tight ring in the aim direction.
			_reticle.aim_position = camera.unproject_position(_weapon.global_position + _direction * minf(_weapon.reach, 7.0))
		_reticle.empty = _weapon.is_firearm() and _weapon.ammo == 0

func _player_screen() -> Vector2:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var player: CharacterBody3D = interaction.player
	if camera == null or not is_instance_valid(player):
		return get_viewport().get_visible_rect().size * 0.5
	var at: Vector3 = player.global_position
	if is_instance_valid(_weapon):
		at.y = _weapon.get_aim_origin().y
	return camera.unproject_position(at)

func ring_radius() -> float:
	return get_viewport().get_visible_rect().size.y * MOUSE_RING_FRACTION

func _steer_mouse_point(relative: Vector2) -> void:
	var offset: Vector2 = _mouse_offset + relative
	if offset.length() > 1.0:
		_mouse_offset = offset.normalized() * ring_radius()

func _start_mouse_point() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var player: CharacterBody3D = interaction.player
	if camera == null or not is_instance_valid(player):
		return
	var ahead: Vector3 = player.global_position - player.global_basis.z * MOUSE_AIM_START
	if is_instance_valid(_weapon):
		ahead.y = _weapon.get_aim_origin().y
	_mouse_offset = camera.unproject_position(ahead) - _player_screen()
	_steer_mouse_point(Vector2.ZERO)

## Closest valid target to the stick direction inside the assist cone, with a
## clear line; otherwise the raw direction.
func _assist(player: CharacterBody3D, raw: Vector3) -> Vector3:
	if raw.length_squared() < 0.01:
		return raw
	var firearm: bool = _weapon.is_firearm()
	var range_: float = ASSIST_FIREARM_RANGE if firearm else float(_weapon.reach) + 0.6
	var cone: float = ASSIST_FIREARM_DEG if firearm else ASSIST_MELEE_DEG
	var origin: Vector3 = _weapon.get_aim_origin()
	var exclude: Array[RID] = [player.get_rid()]
	if _weapon is CollisionObject3D:
		exclude.append((_weapon as CollisionObject3D).get_rid())
	var best: Vector3 = raw
	var best_angle: float = deg_to_rad(cone)
	for hit: Dictionary in Melee.find(player.get_world_3d(), origin, raw.normalized(), range_, cone, exclude, 1):
		if not _is_receiver(hit.collider as Node):
			continue
		var to: Vector3 = (hit.collider as Node3D).global_position - origin
		to.y = 0.0
		var angle: float = raw.angle_to(to)
		if angle < best_angle:
			best_angle = angle
			best = to
	return best

func _is_receiver(node: Node) -> bool:
	while node != null:
		if node.has_method("receive_weapon_hit"):
			return true
		node = node.get_parent()
	return false

func _on_hit(hit: Dictionary) -> void:
	if not _is_receiver(hit.collider as Node):
		return
	_reticle.hit_time = 0.15
