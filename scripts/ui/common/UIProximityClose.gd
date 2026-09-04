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
var _anchor_node: WeakRef = null
## Distance past which the UI closes.
@export var max_distance: float = 3.0
## Cached player ref — lazy-resolved once (was a per-frame group scan).
var _player: Node3D = null

func _process(_delta: float) -> void:
	if ui == null or not ui.is_inside_tree():
		return
	if not _ui_open(ui):
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		return
	if _anchor_node != null:
		var live_anchor: Node3D = _anchor_node.get_ref() as Node3D
		if live_anchor == null:
			if ui.has_method("close"):
				ui.call("close")
			return
		anchor = live_anchor.global_position
	if _player.global_position.distance_to(anchor) > max_distance:
		if ui.has_method("close"):
			ui.call("close")
		elif ui.has_method("hide"):
			ui.call("hide")

## Prefer binding the actual host node over copying one position.  Moving
## storage/devices therefore keep the correct proximity origin, and freeing
## the host safely closes the inspector instead of leaving an orphaned UI.
func bind(host: Node3D) -> void:
	_anchor_node = weakref(host) if host != null else null
	anchor = host.global_position if host != null else Vector3.ZERO
	set_process(host != null)

func unbind() -> void:
	_anchor_node = null
	set_process(false)

func _ui_open(ui_node: Node) -> bool:
	if ui_node is Control:
		return (ui_node as Control).is_visible_in_tree()
	if "visible" in ui_node:
		return bool(ui_node.get("visible"))
	return false
