extends StaticBody3D
class_name ResearchStationChute
## ResearchStationChute.gd
## Small interaction proxy for the Research Station's material-feed chute
## (Aug 2026, widened-station pass). Positioned at the chute's mouth by
## ResearchStation._build_mesh() so InteractionSystem's proximity scan
## treats "near the chute" and "near the rest of the station" as distinct
## interactables — same host-forwarding pattern PowerPriorityInteractable.gd
## already uses for WallLight's E-prompt proxy.
##
## E still forwards to the main station (opens ResearchStationUI) so the
## player never loses that ability just by standing at the chute end. F is
## the new feed action — this proxy has no feed logic of its own, it's
## purely a forwarding hitbox; get_chute_f_prompt()/on_chute_f_interact()
## on ResearchStation.gd do the actual work.

var host: Node = null

const HITBOX_SIZE: Vector3 = Vector3(0.5, 0.7, 0.5)

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 5   ## matches ResearchStation's own body / general furniture convention
	collision_mask  = 0
	_build_collider()

func _build_collider() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = HITBOX_SIZE
	shape.shape = box
	add_child(shape)

func on_interact() -> void:
	if host != null and is_instance_valid(host) and host.has_method("on_interact"):
		host.on_interact()

## Sep 2026 fix (quiet UI audit #13): the chute used to repeat the station's
## "[E] Open Research Station", so two identical prompts floated side by
## side. It now defers to the station whenever the station itself is within
## prompt range (E still forwards from here, so behaviour is unchanged) and
## only speaks for the station when the player is out of the station's range.
func get_interact_prompt() -> String:
	if host == null or not is_instance_valid(host) or not host.has_method("get_interact_prompt"):
		return ""
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null and (host as Node3D).global_position.distance_to(player.global_position) \
			<= InteractionSystem.MAX_PROMPT_DIST:
		return ""
	return host.get_interact_prompt()

func on_f_interact() -> bool:
	if host != null and is_instance_valid(host) and host.has_method("on_chute_f_interact"):
		return host.on_chute_f_interact()
	return false

func get_f_prompt() -> String:
	if host != null and is_instance_valid(host) and host.has_method("get_chute_f_prompt"):
		return host.get_chute_f_prompt()
	return ""