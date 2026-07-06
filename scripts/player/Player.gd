class_name Player
extends CharacterBody3D
## Player.gd
## Handles WASD movement, animation state, and basic interaction input.
## Attach to: res://scenes/player/Player.tscn (CharacterBody3D root)

# ─── Exports (tweak in Inspector) ────────────────────────────────────────────
@export var move_speed: float = 4.0        ## Base walk speed (20% slower than original 5.0)
@export var sprint_speed: float = 7.5      ## Sprint speed (1.5× walk — feels punchy but not insane)
@export var acceleration: float = 12.0
@export var friction: float = 16.0

## Stamina drained per second while sprinting (0–100 scale)
@export var sprint_stamina_drain: float = 18.0
## Stamina recovered per second while not sprinting
@export var stamina_regen: float = 8.0

# ─── Node refs ────────────────────────────────────────────────────────────────
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var interaction_area: Area3D = $InteractionArea

## Stamina must recover to this before sprinting is allowed again (prevents flicker)
@export var sprint_recover_threshold: float = 20.0

## Set each frame by MainWorld to match the camera's current yaw.
## Movement input is rotated by this so controls always feel camera-relative.
var camera_yaw_rad: float = 0.0
var _is_moving: bool = false
var _is_sprinting: bool = false
var _sprint_locked: bool = false  ## true when exhausted, blocks sprint until threshold met

## Current stamina 0–100. Drive this from PlayerStats if you have one,
## or use it standalone — HUD reads it via set_stamina().
var stamina: float = 100.0

## Set true while the pause menu (or any other full-screen modal) is open —
## blocks movement/interaction input without pausing the SceneTree, so the
## rest of the game (power grid, generators, etc.) keeps running per the
## "game continues while paused" decision. Velocity is zeroed on lock so the
## player doesn't keep sliding on residual momentum while the menu is open.
var _movement_locked: bool = false
func set_movement_locked(locked: bool) -> void:
	_movement_locked = locked
	if locked:
		velocity = Vector3.ZERO

# ─── Signals ──────────────────────────────────────────────────────────────────
signal interacted()
signal stamina_changed(new_value: float)   ## Emit so HUD / PlayerStats can react

func _ready() -> void:
	## Register in "player" group so items (e.g. Flashlight) can resolve the
	## player ref via get_first_node_in_group("player") without needing a direct reference.
	add_to_group("player")

func _physics_process(delta: float) -> void:
	if _movement_locked:
		## Still apply gravity/move_and_slide so the player doesn't float or
		## clip through the floor while the menu is open — just skip WASD/
		## sprint/interact input handling.
		if not is_on_floor():
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return
	_handle_movement(delta)
	_handle_interaction_input()

func _handle_movement(delta: float) -> void:
	# Apply gravity so the player falls when not on the floor
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	## Rotate raw input by camera yaw so W always means "away from camera"
	## regardless of which direction the camera is currently facing.
	var raw: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
	var direction: Vector3 = raw.rotated(Vector3.UP, camera_yaw_rad)

	# Unlock sprint once stamina recovers past threshold
	if _sprint_locked and stamina >= sprint_recover_threshold:
		_sprint_locked = false

	# Sprint only while moving, shift held, not locked out
	var wants_sprint: bool = Input.is_action_pressed("sprint") and direction.length_squared() > 0.0
	_is_sprinting = wants_sprint and not _sprint_locked

	# Drain / regen stamina
	if _is_sprinting:
		stamina = maxf(0.0, stamina - sprint_stamina_drain * delta)
		if stamina == 0.0:
			_sprint_locked = true  ## exhausted — force walk until recovered
	else:
		stamina = minf(100.0, stamina + stamina_regen * delta)
	stamina_changed.emit(stamina)

	var target_speed: float = sprint_speed if _is_sprinting else move_speed

	if direction.length_squared() > 0.0:
		velocity = velocity.lerp(direction * target_speed, acceleration * delta)
		_is_moving = true

		# Face movement direction
		var angle: float = atan2(-direction.x, -direction.z)
		rotation.y = angle
	else:
		velocity = velocity.lerp(Vector3.ZERO, friction * delta)
		_is_moving = false

	move_and_slide()

func _handle_interaction_input() -> void:
	if Input.is_action_just_pressed("interact"):
		interacted.emit()
