extends Node3D
## MainWorld.gd
## Root script for the main game world scene.

# ─── Dev Tools ────────────────────────────────────────────────────────────────
## F12 — toggle x50 time warp (speeds up clock + all stat drain)
## F11 — spawn a TestCrate in front of the player
const DEV_TIME_SCALE: float  = 50.0
const CRATE_SCENE: String    = "res://scenes/world/TestCrate.tscn"
var _dev_warp_active: bool   = false

@onready var player: CharacterBody3D       = $Player
@onready var camera: Camera3D              = $GameCamera
@onready var world_env: WorldEnvironment   = $WorldEnvironment
@onready var dir_light: DirectionalLight3D = $DirectionalLight3D
@onready var hud: CanvasLayer              = $HUD
@onready var player_stats: Node            = $PlayerStats
@onready var sleep_overlay: CanvasLayer    = $SleepOverlay
@onready var interact_prompt: Node         = $InteractPrompt
@onready var interaction_system: Node3D    = $Player/InteractionSystem

## Reference to the bed in the scene — assign in _ready or via @export
@export var bed_path: NodePath = NodePath("")
var _bed: Node = null

func _ready() -> void:
	_setup_lighting()
	_connect_hud()
	_connect_bed()
	_connect_world_objects()

func _unhandled_input(event: InputEvent) -> void:
	# F12 — toggle time warp x50
	if event.is_action_pressed("ui_end") or \
			(event is InputEventKey and event.pressed and event.keycode == KEY_F12):
		_dev_toggle_warp()

	# F11 — spawn crate in front of player
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_dev_spawn_crate()

func _dev_toggle_warp() -> void:
	_dev_warp_active = not _dev_warp_active
	if _dev_warp_active:
		Engine.time_scale = DEV_TIME_SCALE
		print("[DEV] Time warp ON (x%.0f)" % DEV_TIME_SCALE)
	else:
		Engine.time_scale = 1.0
		print("[DEV] Time warp OFF")

func _dev_spawn_crate() -> void:
	var crate_res: Resource = load(CRATE_SCENE)
	if crate_res == null:
		push_error("[DEV] Could not load TestCrate.tscn — check path: %s" % CRATE_SCENE)
		return
	var crate: Node3D = crate_res.instantiate()
	add_child(crate)
	# Spawn 2m in front of player, slightly above ground
	crate.global_position = player.global_position \
		+ (-player.global_transform.basis.z * 2.0) \
		+ Vector3(0.0, 0.5, 0.0)
	print("[DEV] Spawned TestCrate")

func _setup_lighting() -> void:
	dir_light.rotation_degrees = Vector3(-50.0, 45.0, 0.0)
	dir_light.light_energy = 1.2
	dir_light.shadow_enabled = true

func _connect_hud() -> void:
	hud.set_health(100.0)
	hud.set_stamina(100.0)
	hud.set_food(100.0)
	hud.set_water(100.0)
	hud.set_sleep(100.0)
	hud.set_cash(12500)

	player.stamina_changed.connect(func(v: float) -> void: hud.set_stamina(v))

	player_stats.food_changed.connect(func(v: float)   -> void: hud.set_food(v))
	player_stats.water_changed.connect(func(v: float)  -> void: hud.set_water(v))
	player_stats.sleep_changed.connect(func(v: float)  -> void: hud.set_sleep(v))
	player_stats.health_changed.connect(func(v: float) -> void: hud.set_health(v))

	player_stats.time_changed.connect(
		func(_h: int, _m: int, _pm: bool, display: String) -> void:
			hud.set_clock(display)
	)

func _connect_bed() -> void:
	# Wire SleepOverlay to PlayerStats
	sleep_overlay.player_stats = player_stats

	# Find bed by path if set, otherwise search the scene
	if bed_path != NodePath(""):
		_bed = get_node(bed_path)
	else:
		_bed = get_tree().get_first_node_in_group("interactable")

	if _bed == null:
		return

	sleep_overlay.bed = _bed

	_bed.sleep_requested.connect(func() -> void:
		_bed.set_sleeping(true)
		# Lock player movement during sleep
		player.set_physics_process(false)
		sleep_overlay.begin_sleep()
	)

	_bed.wake_requested.connect(func() -> void:
		sleep_overlay.request_wake()
	)

	sleep_overlay.sleep_ended.connect(func() -> void:
		player.set_physics_process(true)
	)

func _connect_world_objects() -> void:
	# Wire prompt to interaction system
	interaction_system.prompt = interact_prompt

	# Inject player_stats into any world object that has a _player_stats property.
	# Scans both interactable and pickup groups to catch all cases.
	var all_world_nodes: Array = []
	all_world_nodes.append_array(get_tree().get_nodes_in_group("interactable"))
	all_world_nodes.append_array(get_tree().get_nodes_in_group("pickup"))
	for node in all_world_nodes:
		if "_player_stats" in node:
			node._player_stats = player_stats
