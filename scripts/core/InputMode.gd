extends Node
## InputMode.gd (Aug 2026) — tracks whether the player is currently using a
## gamepad (controller mode) or keyboard/mouse, LAST-INPUT-WINS. UI layers
## (e.g. InteractPrompt) read is_controller() to swap key-cap icons for Xbox
## button icons.

var _controller_mode: bool = false

func is_controller() -> bool:
	return _controller_mode

func is_keyboard() -> bool:
	return not _controller_mode

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_controller_mode = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_controller_mode = false