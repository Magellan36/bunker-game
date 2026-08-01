extends CharacterBody3D
class_name NPC
## NPC.gd
## Basic NPC: wanders the currently dug-out bunker area with proper
## collision, and can be talked to via [E] when the player is nearby.
##
## Collision note: this node is deliberately left on Godot's DEFAULT
## collision_layer/collision_mask (both = 1), exactly like Player.gd's
## CharacterBody3D. Every solid structure in this project (pregen walls/
## pillars, player-placed walls/pillars, furniture, appliances, etc.) is
## spawned with collision_layer = 5 (bits for layer 1 + layer 3 combined —
## see BuildModeController._spawn_placed_object and the various furniture
## scripts under scripts/world/furniture/ and scripts/world/cooking/),
## which INCLUDES layer 1. That means the default player-style collision
## already collides correctly with all of it. Do not add custom
## collision_layer/collision_mask values here — it is not needed and will
## only cause inconsistent behavior.
##
## FUTURE WORK (not wired up yet — kept easy to add later):
##   - Replace the IDLE/WANDERING state machine below with a task-driven
##     one. Add new states to NPCState (e.g. WORKING) and use
##     `current_task` (already stubbed below) to hold a reference to
##     whatever describes the job (filter swap, crop harvest, water
##     collection, generator repair, etc).
##   - `perform_task()` is a deliberate no-op stub. When a real task system
##     exists, have it call `assign_task(task)` — this already interrupts
##     wandering (see _physics_process) and defers to perform_task() every
##     frame instead.

# ─── Tunables ─────────────────────────────────────────────────────────────
@export var move_speed: float = 2.2          ## slower than player (4.0) so NPCs read as distinct
@export var acceleration: float = 8.0
@export var npc_name: String = "Survivor"

## How close (world units) counts as "arrived" at a wander target.
@export var arrival_distance: float = 0.5
## Min/max seconds an NPC stands still between wander legs.
@export var idle_time_min: float = 1.5
@export var idle_time_max: float = 4.0
## Margin (world units) kept clear from the edge of the dug-out bounding
## box when picking wander targets, so NPCs don't hug/clip walls constantly.
@export var wander_margin: float = 0.8

# ─── Node refs ────────────────────────────────────────────────────────────
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

# ─── State ────────────────────────────────────────────────────────────────
enum NPCState { IDLE, WANDERING }
var _state: NPCState = NPCState.IDLE
var _idle_timer: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _stuck_check_timer: float = 0.0
var _stuck_check_last_pos: Vector3 = Vector3.ZERO

## FUTURE WORK: set by a future task system via assign_task(). Left null/
## unused deliberately for now — do not wire anything into this.
var current_task: Node = null

func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")
	_wander_target = global_position
	_enter_idle()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	## FUTURE WORK: once a task system exists, this branch already routes
	## to perform_task() — do not change this branch, only fill in
	## perform_task() itself when that system is built.
	if current_task != null:
		perform_task(delta)
	else:
		_process_wander(delta)

	move_and_slide()
	_check_stuck(delta)

# ─── Wander state machine ──────────────────────────────────────────────────
func _enter_idle() -> void:
	_state = NPCState.IDLE
	_idle_timer = randf_range(idle_time_min, idle_time_max)
	velocity.x = 0.0
	velocity.z = 0.0

func _enter_wandering() -> void:
	_state = NPCState.WANDERING
	_wander_target = _pick_wander_target()
	_stuck_check_timer = 0.0
	_stuck_check_last_pos = global_position

func _process_wander(delta: float) -> void:
	match _state:
		NPCState.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_enter_wandering()
		NPCState.WANDERING:
			_move_toward_target(delta)

func _move_toward_target(delta: float) -> void:
	var to_target: Vector3 = _wander_target - global_position
	to_target.y = 0.0

	if to_target.length() <= arrival_distance:
		_enter_idle()
		return

	var direction: Vector3 = to_target.normalized()
	velocity.x = lerp(velocity.x, direction.x * move_speed, acceleration * delta)
	velocity.z = lerp(velocity.z, direction.z * move_speed, acceleration * delta)

	## Face movement direction — same convention as Player._handle_movement().
	var angle: float = atan2(-direction.x, -direction.z)
	rotation.y = angle

## Picks a random point inside the LIVE dug-out bunker bounding box (grows
## as the player digs — see MainWorld.get_cleared_cell_bounds_world()),
## inset by wander_margin. This is an axis-aligned bounding box, not the
## exact dug shape — good enough for basic wandering; collision handles the
## rest (see _check_stuck). Falls back to standing still if bounds aren't
## available yet.
func _pick_wander_target() -> Vector3:
	var world_node: Node = get_tree().get_first_node_in_group("main_world")
	if world_node == null or not world_node.has_method("get_cleared_cell_bounds_world"):
		return global_position

	var bounds: Rect2 = world_node.get_cleared_cell_bounds_world()
	var min_x: float = bounds.position.x + wander_margin
	var max_x: float = bounds.position.x + bounds.size.x - wander_margin
	var min_z: float = bounds.position.y + wander_margin
	var max_z: float = bounds.position.y + bounds.size.y - wander_margin

	if min_x >= max_x or min_z >= max_z:
		return global_position

	return Vector3(randf_range(min_x, max_x), global_position.y, randf_range(min_z, max_z))

## If a wander leg collides with something (wall/pillar/furniture/object)
## or the NPC hasn't moved meaningfully in a while, abandon the current
## target and pick a new one on the next idle→wander transition, rather
## than pushing into the obstacle forever.
func _check_stuck(delta: float) -> void:
	if _state != NPCState.WANDERING:
		return

	if get_slide_collision_count() > 0:
		_enter_idle()
		return

	_stuck_check_timer += delta
	if _stuck_check_timer >= 1.0:
		if global_position.distance_to(_stuck_check_last_pos) < 0.15:
			_enter_idle()
		else:
			_stuck_check_timer = 0.0
			_stuck_check_last_pos = global_position

# ─── Future task hook (stub — not wired up) ────────────────────────────────
func assign_task(task: Node) -> void:
	current_task = task

func perform_task(_delta: float) -> void:
	pass  ## FUTURE WORK: move toward the task's target, run its behavior.

# ─── Interaction (called by player/InteractionSystem.gd, same contract as
# every other "interactable" — see PowerTerminal.gd for the reference
# pattern this mirrors) ─────────────────────────────────────────────────────
func get_interact_prompt() -> String:
	return "[E] Talk to %s" % npc_name

func on_interact() -> void:
	_open_talk_menu()

var _talk_menu: CanvasLayer = null

func _open_talk_menu() -> void:
	if _talk_menu == null or not is_instance_valid(_talk_menu):
		var ui_script: GDScript = load("res://scripts/ui/npc/NPCTalkMenuUI.gd")
		if ui_script == null:
			push_warning("[NPC] NPCTalkMenuUI.gd not found")
			return
		_talk_menu = CanvasLayer.new()
		_talk_menu.set_script(ui_script)
		_talk_menu.name = "NPCTalkMenuUI"
		get_tree().get_root().add_child(_talk_menu)

	if _talk_menu.has_method("open"):
		_talk_menu.open(npc_name)