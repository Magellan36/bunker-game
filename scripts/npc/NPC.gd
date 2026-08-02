extends CharacterBody3D
class_name NPC
## NPC.gd  (rewritten in NPC Pass 2, Part 1 — navmesh locomotion)
## Wanders the dug-out bunker using real NavigationAgent3D pathfinding over
## BunkerNavMesh's runtime-baked navmesh, and can be talked to via [E].
##
## Collision note (unchanged from Pass 1): deliberately on Godot's DEFAULT
## collision_layer/collision_mask (1/1), like Player.gd. All placed solids
## use collision_layer = 5 (includes bit 1), so default collision already
## hits everything. Never set custom layers here.
##
## Locomotion split: the NavigationAgent3D provides the next XZ waypoint;
## _physics_process steers toward it and move_and_slide() + gravity own the
## actual motion and Y. Physics collision stays the hard guarantee — if the
## navmesh is momentarily stale (mid-rebake after a dig), the NPC bumps and
## re-targets instead of clipping.
##
## FUTURE WORK (unchanged contract from Pass 1):
##   - current_task / assign_task() / perform_task() — Part 4 fills these.

# ─── Tunables ─────────────────────────────────────────────────────────────
@export var move_speed: float = 2.2
@export var acceleration: float = 8.0
@export var npc_name: String = "Survivor"
@export var arrival_distance: float = 0.5
@export var idle_time_min: float = 1.5
@export var idle_time_max: float = 4.0

# ─── Node refs ────────────────────────────────────────────────────────────
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var nav_agent: NavigationAgent3D = null

# ─── State ────────────────────────────────────────────────────────────────
enum NPCState { IDLE, WANDERING }
var _state: NPCState = NPCState.IDLE
var _idle_timer: float = 0.0
var _stuck_check_timer: float = 0.0
var _stuck_check_last_pos: Vector3 = Vector3.ZERO

## FUTURE WORK: Part 4's task system. Do not wire anything into this yet.
var current_task: Node = null

# ─── Needs (Part 2) — 0..100, decay on the game clock ─────────────────────
var energy: float = 100.0
var hunger: float = 100.0   ## 100 = full, 0 = starving (matches PlayerStats' food convention)
var thirst: float = 100.0   ## 100 = hydrated

const ENERGY_DRAIN_PER_GAME_HOUR: float = 3.0
const HUNGER_DRAIN_PER_GAME_HOUR: float = 3.4   ## mirrors PlayerStats food_drain feel
const THIRST_DRAIN_PER_GAME_HOUR: float = 2.08  ## matches PlayerStats.water_drain_per_game_hour

## FUTURE WORK (crisis-response pass, per Brannon's standing note): when a
## need hits 0, consequences (refusing work, slowed movement, mood damage)
## hook in HERE. Deliberately no behavior yet.

# ─── Personality / mood / seed — INERT STUBS (Part 2) ─────────────────────
## FUTURE WORK: the personality-trait + mood + crisis-response system reads
## and populates these. Nothing may read or write them until that pass.
var generation_seed: int = 0
var personality: Dictionary = {}
var mood: float = 100.0

# ─── Brain ────────────────────────────────────────────────────────────────
var brain: NPCBrain = null

var _stats_ref: Node = null

## Real-seconds → game-hours for this frame, via the shared compressed clock.
func game_hours(delta: float) -> float:
	if _stats_ref == null or not is_instance_valid(_stats_ref):
		_stats_ref = get_tree().get_first_node_in_group("player_stats")
	if _stats_ref == null or _stats_ref._seconds_per_game_hour <= 0.0:
		return 0.0
	return delta / _stats_ref._seconds_per_game_hour

func _tick_needs(delta: float) -> void:
	var h: float = game_hours(delta)
	if h <= 0.0:
		return
	energy = maxf(0.0, energy - ENERGY_DRAIN_PER_GAME_HOUR * h)
	hunger = maxf(0.0, hunger - HUNGER_DRAIN_PER_GAME_HOUR * h)
	thirst = maxf(0.0, thirst - THIRST_DRAIN_PER_GAME_HOUR * h)

## Decelerate to a stop — used by activities when standing still.
func halt_movement(delta: float) -> void:
	velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
	velocity.z = lerp(velocity.z, 0.0, acceleration * delta)

func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")

	## Agent built in code (no scene edit needed; scene stays Pass-1 shape).
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	nav_agent.path_desired_distance = 0.4
	nav_agent.target_desired_distance = arrival_distance
	nav_agent.path_max_distance = 3.0
	nav_agent.radius = 0.35              ## matches BunkerNavMesh.agent_radius
	nav_agent.avoidance_enabled = false  ## physics handles NPC-vs-NPC shoving fine at 2-3 NPCs
	add_child(nav_agent)

	_enter_idle()

	generation_seed = randi()   ## stub — future personality generation input
	brain = NPCBrain.new()
	brain.setup(self)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	_tick_needs(delta)

	if current_task != null:
		perform_task(delta)
	elif brain != null:
		brain.tick(delta)
	else:
		_process_wander(delta)   ## fallback only — brain owns behavior now

	move_and_slide()
	_check_stuck(delta)

# ─── Navigation primitives (used by wander now; by every activity later) ──
## Point the agent at a world position. Y is flattened — paths are XZ-only.
func set_nav_target(world_pos: Vector3) -> void:
	if nav_agent != null:
		nav_agent.target_position = Vector3(world_pos.x, 0.0, world_pos.z)

func nav_finished() -> bool:
	return nav_agent == null or nav_agent.is_navigation_finished()

## Steer toward the agent's next waypoint. Call once per physics frame while
## traveling; pairs with move_and_slide() in _physics_process.
func nav_steer(delta: float) -> void:
	if nav_agent == null or nav_agent.is_navigation_finished():
		velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
		velocity.z = lerp(velocity.z, 0.0, acceleration * delta)
		return
	var next: Vector3 = nav_agent.get_next_path_position()
	var dir: Vector3 = next - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	velocity.x = lerp(velocity.x, dir.x * move_speed, acceleration * delta)
	velocity.z = lerp(velocity.z, dir.z * move_speed, acceleration * delta)
	rotation.y = atan2(-dir.x, -dir.z)

# ─── Wander state machine ─────────────────────────────────────────────────
func _enter_idle() -> void:
	_state = NPCState.IDLE
	_idle_timer = randf_range(idle_time_min, idle_time_max)
	velocity.x = 0.0
	velocity.z = 0.0

func _enter_wandering() -> void:
	_state = NPCState.WANDERING
	var world: Node = get_tree().get_first_node_in_group("main_world")
	if world != null and world.has_method("get_random_cleared_cell_center"):
		set_nav_target(world.get_random_cleared_cell_center())
	_stuck_check_timer = 0.0
	_stuck_check_last_pos = global_position

func _process_wander(delta: float) -> void:
	match _state:
		NPCState.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_enter_wandering()
		NPCState.WANDERING:
			if nav_finished():
				_enter_idle()
			else:
				nav_steer(delta)

## Safety net for stale-navmesh moments (mid-rebake) or physics shoves:
## if wandering but not actually moving, give up this leg and re-idle.
func _check_stuck(delta: float) -> void:
	if _state != NPCState.WANDERING or current_task != null:
		return
	_stuck_check_timer += delta
	if _stuck_check_timer >= 1.5:
		if global_position.distance_to(_stuck_check_last_pos) < 0.15:
			_enter_idle()
		else:
			_stuck_check_timer = 0.0
			_stuck_check_last_pos = global_position

# ─── Future task hook (stub — Part 4 fills this) ──────────────────────────
func assign_task(task: Node) -> void:
	current_task = task

func perform_task(_delta: float) -> void:
	pass  ## FUTURE WORK

# ─── Interaction (contract unchanged from Pass 1) ─────────────────────────
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