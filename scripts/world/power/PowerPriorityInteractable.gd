extends StaticBody3D
## PowerPriorityInteractable.gd
## A tiny invisible interaction proxy that makes a Node3D-based powered device
## (e.g. WallLight, which is a plain Node3D) selectable by the InteractionSystem
## so the player can press E to open the shared PowerPriorityUI.
##
## WHY THIS EXISTS
##   InteractionSystem's StaticBody3D proximity scan only picks up nodes that
##   are themselves StaticBody3D AND in the "interactable" group. Devices that
##   are Node3D (no body) can add one of these as a child to gain a clean
##   interaction hit-box without changing their own base class.
##
## HOW IT WORKS
##   • On _ready it joins "interactable" and builds a small box collider.
##   • InteractionSystem finds it by proximity and calls on_interact() / reads
##     get_interact_prompt(); both forward to the owning device.
##   • The device must implement:
##       func on_priority_interact() -> void
##       func get_priority_prompt() -> String
##
## The device sets `host` (the script/node to forward to) before/after adding
## this as a child.

## The device this proxy represents. Must implement on_priority_interact() and
## get_priority_prompt(). Assigned by the host right after add_child().
var host: Node = null

## Half-extents of the interaction box (metres). Small, centred on the device.
const HITBOX_SIZE: Vector3 = Vector3(0.6, 0.6, 0.6)

func _ready() -> void:
	add_to_group("interactable")
	## Layer 1 matches PowerTerminal so the proximity scan and any raycasts
	## treat it identically. Mask 0 — it never needs to detect others.
	collision_layer = 1
	collision_mask  = 0
	_build_collider()

func _build_collider() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box:   BoxShape3D       = BoxShape3D.new()
	box.size  = HITBOX_SIZE
	shape.shape = box
	add_child(shape)

# ─── Interaction forwarding ──────────────────────────────────────────────────
func on_interact() -> void:
	if host != null and is_instance_valid(host) and host.has_method("on_priority_interact"):
		host.on_priority_interact()

func get_interact_prompt() -> String:
	if host != null and is_instance_valid(host) and host.has_method("get_priority_prompt"):
		return host.get_priority_prompt()
	return "[E] Set Power Priority"
