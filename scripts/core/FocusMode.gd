extends Node
## FocusMode.gd (Aug 2026) — global "focus mode" state.
## Keyboard holds Ctrl; a controller right-stick click toggles it on/off
## (Player.gd flips `toggled`). is_active() returns true when EITHER source
## is active, so every interaction/highlight code path that used to read
## `Input.is_key_pressed(KEY_CTRL)` works identically for both input styles.

var toggled: bool = false

func is_active() -> bool:
	return Input.is_key_pressed(KEY_CTRL) or toggled

func toggle() -> void:
	toggled = not toggled