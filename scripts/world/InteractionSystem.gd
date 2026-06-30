extends Node3D
## InteractionSystem.gd
## Handles pickup, drop, placement, world interaction, and interact prompts.

# ─── Exports ──────────────────────────────────────────────────────────────────
@export var place_radius: float = 2.5
@export var hold_height: float  = 0.8

# ─── Node refs ────────────────────────────────────────────────────────────────
@onready var hold_point: Node3D         = $HoldPoint
@onready var placement_indicator: Node3D = $PlacementIndicator
@onready var detect_area: Area3D        = $DetectArea
@onready var player: CharacterBody3D    = get_parent()

## Set by MainWorld after ready
var prompt: Node = null

# ─── State ────────────────────────────────────────────────────────────────────
var held_item: RigidBody3D = null
var _is_placing: bool      = false
var _world_root: Node3D    = null

func _ready() -> void:
	hold_point.position = Vector3(0.0, hold_height, -1.0)
	placement_indicator.visible = false
	_world_root = get_tree().get_first_node_in_group("world")
	detect_area.body_entered.connect(_on_body_entered)
	detect_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("interactable") and body.has_method("set_player_in_range"):
		body.set_player_in_range(true)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("interactable") and body.has_method("set_player_in_range"):
		body.set_player_in_range(false)

func _process(_delta: float) -> void:
	_handle_placement_mode()
	_update_prompt()

func _unhandled_input(event: InputEvent) -> void:
	# F — pickup / drop / use held item
	if event.is_action_pressed("pickup"):
		if held_item == null:
			_try_pickup()
		elif not _is_placing:
			_quick_drop()

	# E — placement confirm OR world interact OR use held consumable
	if event.is_action_pressed("interact"):
		if _is_placing:
			_confirm_place()
		elif held_item != null and held_item.has_method("on_use"):
			held_item.on_use()
		elif held_item == null:
			_try_interact()

# ─── Prompt ───────────────────────────────────────────────────────────────────
func _update_prompt() -> void:
	if prompt == null:
		print("IS: prompt is null")
		return

	# Priority 1: held item — show use prompt or nothing
	if held_item != null:
		var use_text: String = _get_use_prompt(held_item)
		if use_text != "":
			prompt.show_prompt(use_text, held_item.global_position)
			return
		prompt.hide_prompt()
		return

	# Priority 2: nearest world object — combine pickup + interact prompts if both exist
	var best_node: Node3D = null
	var best_dist: float  = INF

	var bodies: Array = detect_area.get_overlapping_bodies()
	print("IS bodies in detect_area: ", bodies.size(), " -> ", bodies)
	for body in bodies:
		var d: float = body.global_position.distance_to(player.global_position)
		if d >= best_dist:
			continue
		if body.is_in_group("interactable") or body.is_in_group("pickup"):
			best_dist = d
			best_node = body

	if best_node == null:
		prompt.hide_prompt()
		return

	print("IS best_node: ", best_node.name, " groups: interactable=", best_node.is_in_group("interactable"), " pickup=", best_node.is_in_group("pickup"))

	var lines: Array[String] = []

	if best_node.is_in_group("pickup"):
		if best_node.has_method("get_prompt_text"):
			var pt: String = best_node.get_prompt_text()
			print("IS pickup prompt: '", pt, "'")
			if pt != "":
				lines.append(pt)
		else:
			lines.append("[F] Pick up")

	if best_node.is_in_group("interactable") and best_node.has_method("get_interact_prompt"):
		var ip: String = best_node.get_interact_prompt()
		print("IS interact prompt: '", ip, "'")
		if ip != "":
			lines.append(ip)
	elif best_node.is_in_group("interactable") and best_node.has_method("get_prompt_text") \
			and not best_node.is_in_group("pickup"):
		var pt: String = best_node.get_prompt_text()
		if pt != "":
			lines.append(pt)

	print("IS lines: ", lines)
	if lines.is_empty():
		prompt.hide_prompt()
	else:
		prompt.show_prompt("\n".join(lines), best_node.global_position)

func _get_use_prompt(item: RigidBody3D) -> String:
	if item.has_method("get_use_prompt"):
		return item.get_use_prompt()
	return ""

# ─── World Interaction ────────────────────────────────────────────────────────
func _try_interact() -> void:
	var bodies: Array = detect_area.get_overlapping_bodies()
	var closest: Node3D  = null
	var closest_dist: float = INF

	for body in bodies:
		if body.is_in_group("interactable"):
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	if closest != null and closest.has_method("on_interact"):
		closest.on_interact()

# ─── Pickup ───────────────────────────────────────────────────────────────────
func _try_pickup() -> void:
	var bodies: Array = detect_area.get_overlapping_bodies()
	var closest: RigidBody3D = null
	var closest_dist: float  = INF

	for body in bodies:
		if body.is_in_group("pickup"):
			var d: float = body.global_position.distance_to(player.global_position)
			if d < closest_dist:
				closest_dist = d
				closest = body

	if closest == null:
		return

	held_item = closest
	if not held_item.knocked_out.is_connected(_on_item_knocked_out):
		held_item.knocked_out.connect(_on_item_knocked_out)
	held_item.pickup(hold_point)

# ─── Knocked out ──────────────────────────────────────────────────────────────
func _on_item_knocked_out() -> void:
	held_item = null
	_is_placing = false
	placement_indicator.visible = false

# ─── Quick Drop ───────────────────────────────────────────────────────────────
func _quick_drop() -> void:
	if held_item == null:
		return
	var drop_pos: Vector3 = player.global_position + \
		player.global_transform.basis.z * -1.5 + Vector3(0.0, 0.2, 0.0)
	held_item.drop(_world_root, drop_pos)
	held_item = null
	_is_placing = false
	placement_indicator.visible = false

# ─── Placement Mode ───────────────────────────────────────────────────────────
func _handle_placement_mode() -> void:
	if held_item == null:
		_is_placing = false
		placement_indicator.visible = false
		return

	_is_placing = Input.is_action_pressed("interact") and held_item != null \
		and not held_item.has_method("on_use")
	placement_indicator.visible = _is_placing

	if not _is_placing:
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse_pos: Vector2  = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3    = camera.project_ray_normal(mouse_pos)

	var ground_y: float = 0.05
	if abs(ray_dir.y) < 0.001:
		return
	var t: float = (ground_y - ray_origin.y) / ray_dir.y
	var world_point: Vector3 = ray_origin + ray_dir * t

	var to_point: Vector3 = world_point - player.global_position
	if to_point.length() > place_radius:
		to_point = to_point.normalized() * place_radius
		world_point = player.global_position + to_point

	placement_indicator.global_position = world_point

# ─── Confirm Placement ────────────────────────────────────────────────────────
func _confirm_place() -> void:
	if held_item == null:
		return
	var place_pos: Vector3 = placement_indicator.global_position
	held_item.place(_world_root, place_pos)
	held_item = null
	_is_placing = false
	placement_indicator.visible = false
