extends StaticBody3D
## Bed.gd
## Interactable bed. Player presses E nearby to sleep.
## Signals SleepOverlay to handle the fade + time-skip.
## Place on a StaticBody3D with a MeshInstance3D and CollisionShape3D child.

# ─── Signals ─────────────────────────────────────────────────────────────────
## Emitted when player initiates sleep
signal sleep_requested()
## Emitted when player presses E again to get up
signal wake_requested()

# ─── State ───────────────────────────────────────────────────────────────────
var _player_in_range: bool = false
var _player_sleeping: bool = false

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("bed")   ## Used by MainWorld._connect_bed() to wire all placed beds

# ─── Called by InteractionSystem on E press ──────────────────────────────────
func on_interact() -> void:
	if not _player_in_range:
		return
	if not _player_sleeping:
		sleep_requested.emit()
	else:
		wake_requested.emit()

func get_prompt_text() -> String:
	if _player_sleeping:
		return "[E] Wake up"
	return "[E] Sleep"

func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range

func set_sleeping(sleeping: bool) -> void:
	_player_sleeping = sleeping
