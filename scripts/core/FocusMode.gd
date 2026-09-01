extends Node
## FocusMode.gd (Aug 2026) — global "focus mode" state.
## Keyboard holds Ctrl; a controller right-stick click toggles it on/off
## (Player.gd flips `toggled`). is_active() returns true when EITHER source
## is active, so every interaction/highlight code path that used to read
## `Input.is_key_pressed(KEY_CTRL)` works identically for both input styles.

var toggled: bool = false

func is_active() -> bool:
	var ctrl: bool = Input.is_key_pressed(KEY_CTRL)
	## Aug 2026 — during build mode the keyboard CTRL source is BLANKED so CTRL
	## is free for build-mode actions (e.g. CTRL+wheel grid size while
	## placing). The controller right-stick toggle still works either way.
	if ctrl and _build_mode_active():
		ctrl = false
	return ctrl or toggled

func _build_mode_active() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var bm: Node = tree.get_first_node_in_group("build_mode_controller")
	return bm != null and bool(bm.get("is_active"))

func toggle() -> void:
	toggled = not toggled