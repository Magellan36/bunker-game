extends SubViewportContainer
class_name NPCPortraitViewport
## Persistent visual-only resident preview. The real NPC never leaves the
## world: this viewport instantiates the same AdventurerModel scene using the
## gender already resolved on the NPC, then lets its existing idle animation
## run inside a small isolated 3D world.

const MODEL_SCENE: PackedScene = preload("res://scenes/player/AdventurerModel.tscn")
const VIEWPORT_SIZE: Vector2i = Vector2i(448, 512)
const MODEL_SCALE: Vector3 = Vector3(1.25, 1.25, 1.25)
## Portrait framing is resolved from the animated Head bone rather than from
## the model root. This keeps male/female bodies and future appearance variants
## centered consistently even when their proportions differ slightly.
const PORTRAIT_DISTANCE: float = 1.4
const PORTRAIT_FACE_TO_CHEST_OFFSET: float = 0.20
const FALLBACK_PORTRAIT_TARGET: Vector3 = Vector3(0.0, 1.42, 0.0)

var _viewport: SubViewport = null
var _stage: Node3D = null
var _resident_root: CharacterBody3D = null
var _camera: Camera3D = null


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_viewport()
	set_active(false)


func show_npc(npc: Node) -> void:
	_clear_resident()
	if npc == null or not is_instance_valid(npc):
		return
	var resolved_gender: String = "male"
	if npc.has_meta("_adventurer_random_gender"):
		resolved_gender = String(npc.get_meta("_adventurer_random_gender"))
	else:
		var live_model: Node = npc.get_node_or_null("CharacterModel")
		if live_model != null:
			var stored_gender: Variant = live_model.get("_gender")
			if stored_gender is String and String(stored_gender) != "":
				resolved_gender = String(stored_gender)

	_resident_root = CharacterBody3D.new()
	_resident_root.name = "PortraitResident"
	## The model controller already compensates for the capsule height. The old
	## additional +1 m offset raised the feet above the stage and pushed the
	## resident's face completely beyond the top of the portrait.
	_resident_root.position = Vector3.ZERO
	_resident_root.set_meta("_adventurer_random_gender", resolved_gender)
	_stage.add_child(_resident_root)

	var collision: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	_resident_root.add_child(collision)

	var model: AdventurerModelController = MODEL_SCENE.instantiate() as AdventurerModelController
	if model == null:
		return
	model.name = "CharacterModel"
	model.randomize_gender = true
	model.is_shadow_only = false
	model.scale = MODEL_SCALE
	_resident_root.add_child(model)
	set_active(true)
	## AdventurerModelController creates the gendered FBX and skeleton during its
	## own _ready(). Frame on the deferred call so that Head is available.
	call_deferred("_frame_resident_portrait")


func set_active(active: bool) -> void:
	if _viewport == null:
		return
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	)
	if _resident_root != null and is_instance_valid(_resident_root):
		_resident_root.process_mode = (
		Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		)


func clear_npc() -> void:
	set_active(false)
	_clear_resident()


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ResidentSubViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var graphics_settings: Node = get_node_or_null("/root/GraphicsSettings")
	if graphics_settings != null:
		var render_scale: Variant = graphics_settings.get("render_scale")
		if render_scale is float:
			_viewport.scaling_3d_scale = clampf(float(render_scale), 0.5, 1.0)
	add_child(_viewport)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0d2025")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8cbd0")
	environment.ambient_light_energy = 0.58
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	_viewport.add_child(environment_node)

	var warm_key: DirectionalLight3D = DirectionalLight3D.new()
	warm_key.name = "WarmKey"
	warm_key.rotation_degrees = Vector3(-35.0, -145.0, 0.0)
	warm_key.light_color = Color("ffe3ba")
	warm_key.light_energy = 1.05
	warm_key.shadow_enabled = false
	_viewport.add_child(warm_key)

	var cool_fill: DirectionalLight3D = DirectionalLight3D.new()
	cool_fill.name = "CoolRim"
	cool_fill.rotation_degrees = Vector3(-15.0, 40.0, 0.0)
	cool_fill.light_color = Color("8ec9f2")
	cool_fill.light_energy = 0.48
	cool_fill.shadow_enabled = false
	_viewport.add_child(cool_fill)

	_stage = Node3D.new()
	_stage.name = "PortraitStage"
	_viewport.add_child(_stage)
	_build_floor()

	_camera = Camera3D.new()
	_camera.name = "PortraitCamera"
	_camera.fov = 32.0
	_camera.near = 0.05
	_viewport.add_child(_camera)
	_camera.current = true
	_apply_portrait_frame(FALLBACK_PORTRAIT_TARGET)


## Centers the live portrait on the resident's actual face. The aim point is
## lowered slightly from the Head bone so the final composition includes the
## shoulders and upper chest, while everything below mid-chest is cropped.
func _frame_resident_portrait() -> void:
	if _camera == null or _resident_root == null or not is_instance_valid(_resident_root):
		return
	var skeleton: Skeleton3D = _find_skeleton(_resident_root)
	if skeleton == null:
		_apply_portrait_frame(FALLBACK_PORTRAIT_TARGET)
		return
	var head_bone: int = skeleton.find_bone("Head")
	if head_bone < 0:
		_apply_portrait_frame(FALLBACK_PORTRAIT_TARGET)
		return
	var head_pose: Transform3D = skeleton.get_bone_global_pose(head_bone)
	var head_position: Vector3 = skeleton.global_transform * head_pose.origin
	var portrait_target: Vector3 = head_position + Vector3(
		0.0, -PORTRAIT_FACE_TO_CHEST_OFFSET, 0.0
	)
	_apply_portrait_frame(portrait_target)


func _apply_portrait_frame(target: Vector3) -> void:
	if _camera == null:
		return
	_camera.position = target + Vector3(0.0, 0.02, -PORTRAIT_DISTANCE)
	_camera.look_at(target, Vector3.UP)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _build_floor() -> void:
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = 0.82
	cylinder.bottom_radius = 0.9
	cylinder.height = 0.025
	cylinder.radial_segments = 48
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("18343a")
	material.metallic = 0.15
	material.roughness = 0.82
	cylinder.material = material
	floor_mesh.mesh = cylinder
	floor_mesh.position.y = -0.02
	_stage.add_child(floor_mesh)


func _clear_resident() -> void:
	if _resident_root == null or not is_instance_valid(_resident_root):
		_resident_root = null
		return
	_resident_root.queue_free()
	_resident_root = null
