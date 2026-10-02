extends SubViewportContainer
## SurvivorPortrait.gd (Oct 2026)
## Live head-and-shoulders portrait for a survivor card: the NPC's real
## Adventurer body (gender read from the parent meta, exactly as a spawned
## resident resolves it) in a small private studio, framed from the model's
## own bounds. Warm key, cool rim — the same lighting language as the item
## previews. Focusing/selecting the card warms the key and turns the
## survivor a little towards you; reduced motion snaps instead of easing.

const MODEL_SCENE: String = "res://scenes/player/AdventurerModel.tscn"
const MODEL_SCALE: float = 1.25          ## NPC.tscn's CharacterModel scale
const REST_YAW_DEG: float = 162.0     ## the Adventurer faces -Z; 180 - 18
const LIVE_YAW_DEG: float = 174.0
const KEY_REST: float = 0.85
const KEY_LIVE: float = 1.3
const RESPONSE: float = 9.0
const FRAME_DISTANCE: float = 2.6      ## with fov 22: head and shoulders

var _viewport: SubViewport
var _camera: Camera3D
var _key: DirectionalLight3D
var _turn: Node3D
var _framed: bool = false
var _live: bool = false
var _yaw: float = REST_YAW_DEG
var _energy: float = KEY_REST


func setup(gender: String) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9d3dc")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	_key = DirectionalLight3D.new()
	_key.light_color = Color("f4e2c0")
	_key.light_energy = KEY_REST
	_key.rotation_degrees = Vector3(-30.0, -38.0, 0.0)
	_viewport.add_child(_key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("9cc3e0")
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-14.0, 150.0, 0.0)
	_viewport.add_child(rim)

	_camera = Camera3D.new()
	_camera.fov = 22.0
	_camera.near = 0.05
	_camera.far = 20.0
	_viewport.add_child(_camera)

	_turn = Node3D.new()
	_turn.name = "Turn"
	## The model controller reads its parent's gender meta when it has no
	## CharacterBody3D owner (same path a resident's model takes).
	_turn.set_meta("_adventurer_random_gender", gender)
	_turn.rotation_degrees.y = REST_YAW_DEG
	_viewport.add_child(_turn)
	var scene := load(MODEL_SCENE) as PackedScene
	if scene != null:
		var model: Node3D = scene.instantiate()
		if "randomize_gender" in model:
			model.set("randomize_gender", true)
		model.scale = Vector3.ONE * MODEL_SCALE
		_turn.add_child(model)


## Card focus/hover/selection drives this.
func set_live(on: bool) -> void:
	_live = on
	if UIMotion.reduced():
		_yaw = LIVE_YAW_DEG if on else REST_YAW_DEG
		_energy = KEY_LIVE if on else KEY_REST
		_apply()


func _process(delta: float) -> void:
	if not _framed:
		_frame()
	if UIMotion.reduced():
		return
	var k: float = 1.0 - exp(-RESPONSE * delta)
	_yaw = lerpf(_yaw, LIVE_YAW_DEG if _live else REST_YAW_DEG, k)
	_energy = lerpf(_energy, KEY_LIVE if _live else KEY_REST, k)
	_apply()


func _apply() -> void:
	if _turn != null:
		_turn.rotation_degrees.y = _yaw
	if _key != null:
		_key.light_energy = _energy


## Head-and-shoulders, aimed at the skeleton's Head bone (skinned meshes
## report bind-pose bounds at FBX scale, so their AABBs can't frame it).
## Waits until the controller has built the skeleton and posed it.
func _frame() -> void:
	var skeleton: Skeleton3D = null
	for node: Node in _turn.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null:
		return
	var head_bone: int = -1
	for b: int in skeleton.get_bone_count():
		var bone_name: String = skeleton.get_bone_name(b).to_lower()
		if bone_name == "head" or bone_name.ends_with(":head") or bone_name.ends_with("_head"):
			head_bone = b
			break
	var head: Vector3 = Vector3(0.0, 2.05, 0.0)   ## fallback: NPC head height at 1.25 scale
	if head_bone >= 0:
		head = skeleton.global_transform * skeleton.get_bone_global_pose(head_bone).origin
	if head.y < 0.5:
		return
	_framed = true
	var aim: Vector3 = head + Vector3(0.0, -0.14, 0.0)   ## head and shoulders in frame
	_camera.look_at_from_position(aim + Vector3(0.0, 0.04, FRAME_DISTANCE), aim, Vector3.UP)
