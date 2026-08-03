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
var hold_point: Node3D = null       ## NPC's carry anchor (Part 3)
var held_item: RigidBody3D = null   ## what's in hand, via PickupableItem.pickup

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
const HUNGER_DRAIN_PER_GAME_HOUR: float = 1.39  ## matches PlayerStats.food_drain_per_game_hour (Part 12 fix — was 3.4, a wrong number, not a deliberate 2.4x-faster choice)
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

# ─── Skills (Part 4) — score multipliers for job selection; grow with use ──
var skills: Dictionary = {
	"farming": 1.0, "plumbing": 1.0, "electrical": 1.0, "construction": 1.0,
}

func randomize_skills() -> void:
	for k: String in skills.keys():
		skills[k] = randf_range(0.6, 1.4)

func gain_skill(key: String, amount: float = 0.01) -> void:
	if skills.has(key):
		skills[key] = minf(2.0, float(skills[key]) + amount)

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
## Part 13 — every stationary phase in the game (job work, eating, drinking,
## the idle pause between wander legs) already calls this every frame. It
## now also raises _movement_locked, so a late-arriving avoidance callback
## (see _on_velocity_computed below) can never overwrite the halt with a
## stale travel-direction velocity.
var _movement_locked: bool = false

func halt_movement(delta: float) -> void:
	_movement_locked = true
	velocity.x = lerp(velocity.x, 0.0, acceleration * delta)
	velocity.z = lerp(velocity.z, 0.0, acceleration * delta)

## One-time hard stop for the exact instant an NPC snaps into a seated/lying
## position (SitActivity, LieActivity) — those states return early every
## frame afterward and never call halt_movement() again, so they need an
## explicit lock at the moment of transition rather than relying on a
## per-frame call.
func lock_movement() -> void:
	_movement_locked = true
	velocity.x = 0.0
	velocity.z = 0.0

func _ready() -> void:
	add_to_group("npc")
	add_to_group("interactable")

	## Agent built in code (no scene edit needed; scene stays Pass-1 shape).
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	## Reached-checks are 3D. Path points sit on the floor (y≈0.5) while this
	## node's origin is the capsule CENTER (y≈1.4) — a constant ~0.9 vertical
	## offset. Desired distances must exceed it or no waypoint can ever
	## register as reached (the Part 1–8 wall-sticking root cause). 1.1
	## leaves ~0.63 of effective XZ arrival tolerance. (Part 9)
	nav_agent.path_desired_distance = 1.1
	nav_agent.target_desired_distance = 1.1
	nav_agent.path_max_distance = 3.0
	nav_agent.radius = 0.4               ## matches BunkerNavMesh.agent_radius (Part 8)
	## Real dynamic avoidance (Part 11) — routes around heavy items'
	## NavigationObstacle3D (PickupableItem.gd) AND every other NPC's own
	## agent continuously, replacing Part 10.1's reactive post-collision
	## steering hack entirely.
	nav_agent.avoidance_enabled = true
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(nav_agent)

	## Carry anchor — chest-height, slightly forward; items follow it with
	## the same PickupableItem physics the player's HoldPoint gets.
	hold_point = Node3D.new()
	hold_point.name = "HoldPoint"
	hold_point.position = Vector3(0.0, 0.9, -0.8)
	add_child(hold_point)

	_enter_idle()

	generation_seed = randi()   ## stub — future personality generation input
	randomize_skills()
	brain = NPCBrain.new()
	brain.setup(self)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

	_tick_needs(delta)
	_tick_stuck_recovery(delta)

	if current_task != null:
		perform_task(delta)
	elif brain != null:
		brain.tick(delta)
	else:
		_process_wander(delta)   ## fallback only — brain owns behavior now

	move_and_slide()
	_handle_physics_pushes(delta)
	_check_stuck(delta)

# ─── Navigation primitives (used by wander now; by every activity later) ──
## Point the agent at a world position. Y is flattened — paths are XZ-only.
func set_nav_target(world_pos: Vector3) -> void:
	if nav_agent != null:
		## Snap target to the real floor plane (0.5), not y=0 — keeps the
		## vertical offset to this node's origin at ~0.9, inside the 1.1
		## desired-distance budget above. (Part 9)
		nav_agent.target_position = Vector3(world_pos.x, 0.5, world_pos.z)

func nav_finished() -> bool:
	return nav_agent == null or nav_agent.is_navigation_finished()

## Steer toward the agent's next waypoint. Call once per physics frame while
## traveling; pairs with move_and_slide() in _physics_process. With real
## avoidance (Part 11) this no longer sets velocity directly — it submits
## the PREFERRED velocity to the NavigationAgent3D, which factors in every
## nearby NavigationObstacle3D (heavy items) and other NPC agents, then
## calls back into _on_velocity_computed() with the safe, adjusted velocity
## to actually apply. Every activity keeps calling this exact same function,
## so no activity code needs to know avoidance exists at all.
func nav_steer(delta: float) -> void:
	_movement_locked = false   ## actively requesting movement again (Part 13)
	_last_steer_delta = delta
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
	nav_agent.set_velocity(dir * move_speed)   ## -> _on_velocity_computed()

var _last_steer_delta: float = 0.0

## Godot calls this once avoidance has computed a safe velocity from the
## preferred one submitted in nav_steer(). Fires synchronously within the
## same physics frame under local (non-multithreaded) avoidance, which is
## what a single-region setup like this one uses.
func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if _movement_locked:
		return   ## a stationary phase (Part 13) started after this request was
		         ## submitted — the request is stale, ignore it
	velocity.x = lerp(velocity.x, safe_velocity.x, acceleration * _last_steer_delta)
	velocity.z = lerp(velocity.z, safe_velocity.z, acceleration * _last_steer_delta)
	if Vector2(safe_velocity.x, safe_velocity.z).length() > 0.05:
		rotation.y = atan2(-safe_velocity.x, -safe_velocity.z)

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
		_talk_menu.open(npc_name, self)


# ─── Overhead work banner (Part 4) — GeneratorObject fuel-banner style ─────
var _work_banner: Label3D = null

func show_work_banner() -> void:
	if _work_banner == null:
		_work_banner = Label3D.new()
		_work_banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_work_banner.fixed_size = true
		_work_banner.pixel_size = 0.0009
		_work_banner.font_size = 40
		_work_banner.outline_size = 8
		_work_banner.position = Vector3(0.0, 1.55, 0.0)
		_work_banner.modulate = Color(0.95, 0.85, 0.45, 1.0)
		add_child(_work_banner)
	_work_banner.visible = true

func update_work_banner(action: String, progress: float) -> void:
	if _work_banner == null:
		return
	var filled: int = clampi(int(round(progress * 5.0)), 0, 5)
	_work_banner.text = "%s %s%s" % [action,
		"▓".repeat(filled), "░".repeat(5 - filled)]

func hide_work_banner() -> void:
	if _work_banner != null:
		_work_banner.visible = false


# ─── Overhead name/activity label (Part 5) ─────────────────────────────────
## Always-on small billboard: "Name — Activity". Sits ABOVE the Part-4 work
## banner (which shows only during job work phases, below this).
var _overhead_label: Label3D = null
var _overhead_timer: float = 0.0

func _process(delta: float) -> void:
	_overhead_timer -= delta
	if _overhead_timer > 0.0:
		return
	_overhead_timer = 0.5
	if _overhead_label == null:
		_overhead_label = Label3D.new()
		_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_overhead_label.fixed_size = true
		_overhead_label.pixel_size = 0.0007
		_overhead_label.font_size = 34
		_overhead_label.outline_size = 8
		_overhead_label.position = Vector3(0.0, 1.85, 0.0)
		_overhead_label.modulate = Color(0.88, 0.90, 0.92, 0.95)
		add_child(_overhead_label)
	var activity: String = brain.current_label() if brain != null else "Idle"
	_overhead_label.text = "%s — %s" % [npc_name, activity]


# ─── Stuck recovery (Part 7) ────────────────────────────────────────────────
## Fires only while the nav agent has an active, unfinished target — i.e.
## during any activity's travel phase. Idle/consume/work-in-place moments
## are correctly stationary and never flagged. If the NPC hasn't displaced
## STUCK_MIN_DISPLACEMENT in STUCK_CHECK_INTERVAL seconds while trying to
## travel, hard-abort the current activity so the brain re-scores fresh —
## every activity's exit() already releases jobs/chairs/items cleanly, so
## this is always a safe, non-destructive reset.
const STUCK_CHECK_INTERVAL: float = 1.0
const STUCK_MIN_DISPLACEMENT: float = 0.15

var _stuck_timer: float = 0.0
var _stuck_ref_pos: Vector3 = Vector3.ZERO
var _stuck_recoveries: int = 0   ## exposed for the Part 7 debug dump

func _tick_stuck_recovery(delta: float) -> void:
	if nav_agent == null or nav_finished():
		_stuck_timer = 0.0
		_stuck_ref_pos = global_position
		return
	## Part 10.1's avoidance-cooldown carve-out lived here and is removed
	## (Part 11) — real NavigationObstacle3D-based avoidance now prevents
	## most heavy-item collisions before they happen, so this general check
	## goes back to being the single, simple final-fallback safety net.
	_stuck_timer += delta
	if _stuck_timer < STUCK_CHECK_INTERVAL:
		return
	var moved: float = global_position.distance_to(_stuck_ref_pos)
	_stuck_timer = 0.0
	_stuck_ref_pos = global_position
	if moved < STUCK_MIN_DISPLACEMENT:
		_recover_from_stuck()

func _recover_from_stuck() -> void:
	_stuck_recoveries += 1
	NPCDebug.log_stuck(self)
	if brain != null:
		brain.stop_current()
	velocity.x = 0.0
	velocity.z = 0.0


# ─── Physics-clutter push-through (Part 10, simplified in Part 11) ─────────
## Only light items reach this now — heavy items have a real
## NavigationObstacle3D (PickupableItem.gd, Part 11) and NPCs route around
## their current position proactively via avoidance, so they rarely collide
## at all. This still shoves+corrects for light loose items (FoodCan,
## WaterBottle, produce, ...), which intentionally have no obstacle and are
## meant to be walked straight through rather than routed around.
const LIGHT_PUSH_IMPULSE: float = 1.5   ## shove strength on light items
const HEAVY_PUSH_MASS: float = 3.0      ## mirrors PickupableItem.HEAVY_OBSTACLE_MASS —
                                        ## anything at/above this got an obstacle and
                                        ## should rarely reach this code at all; if it
                                        ## still does (avoidance is a preference, not a
                                        ## guarantee), give it a small acknowledging
                                        ## shove but let normal collision resistance stand

func _handle_physics_pushes(delta: float) -> void:
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		var body: Object = col.get_collider()
		if not (body is RigidBody3D):
			continue
		if ("is_held" in body) and body.is_held:
			continue   ## someone's carrying it — not clutter, ignore
		var rb: RigidBody3D = body as RigidBody3D
		var away: Vector3 = -col.get_normal()
		away.y = 0.0
		if away.length() <= 0.01:
			continue

		if rb.mass < HEAVY_PUSH_MASS:
			rb.apply_central_impulse(away.normalized() * LIGHT_PUSH_IMPULSE)
			var blocked: Vector3 = velocity - get_real_velocity()
			blocked.y = 0.0
			if blocked.length() > 0.01:
				global_position += blocked * delta
		else:
			rb.apply_central_impulse(away.normalized() * LIGHT_PUSH_IMPULSE / rb.mass)