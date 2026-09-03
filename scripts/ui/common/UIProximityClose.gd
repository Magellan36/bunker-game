extends Node
## UIProximityClose.gd (Aug 2026)
## Auto-closes a UI when the player moves beyond max_distance from an anchor
## world position — the object the UI was opened from. Follow-up to allowing
## the player to move while a world-anchored UI (storage, dispenser,
## terminal, NPC talk) is open: walking away dismisses it instead of forcing
## a manual close.
## ONE-WAY: this node only ever CLOSES the UI. Once auto-closed it stops
## checking, so walking back does NOT reopen it — a fresh explicit open()
## (player re-interacting) is required to use the UI again.
## Purely additive — only UIs that create this node and set `ui` + `anchor`
## get the behavior (pause/settings/confirm-style UIs simply don't opt in).

## The UI node to close (must have close()/hide()); typically the CanvasLayer.
var ui: Node = null
## World position the player must stay near to keep the UI open.
var anchor: Vector3 = Vector3.ZERO
## Distance past which the UI closes.
@export var max_distance: float = 3.0
## Cached player ref — lazy-resolved once (was a per-frame group scan).
var _player: Node3D = null
## Optional live anchor. A freed/removed host closes its inspector as well.
## Legacy callers may continue assigning `anchor` directly.
var _target: WeakRef = null

func bind_target(target: Node3D) -> void:
	_target = weakref(target) if is_instance_valid(target) else null
	if is_instance_valid(target):
		anchor = target.global_position

func bind_position(position: Vector3) -> void:
	_target = null
	anchor = position

func _process(_delta: float) -> void:
	if not is_instance_valid(ui) or not ui.is_inside_tree():
		return
	if not _ui_open(ui):
		return
	if _target != null:
		var target: Node3D = _target.get_ref() as Node3D
		if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
			_close_ui()
			return
		anchor = target.global_position
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(_player):
		return
	if _player.global_position.distance_to(anchor) > max_distance:
		_close_ui()

func _close_ui() -> void:
	if ui.has_method("close"):
		ui.call("close")
	elif ui.has_method("hide"):
		ui.call("hide")

func _ui_open(ui_node: Node) -> bool:
	if ui_node is Control:
		return (ui_node as Control).is_visible_in_tree()
	if "visible" in ui_node:
		return bool(ui_node.get("visible"))
	return false
