extends Node
## WorldManager.gd
## Autoload singleton. Manages global game state, scene transitions, and
## any data that needs to persist between rooms/scenes.
## Register as Autoload: Project > Project Settings > Autoload
## Name it exactly: WorldManager

# ─── Signals ──────────────────────────────────────────────────────────────────
signal scene_changed(scene_name: String)

# ─── State ────────────────────────────────────────────────────────────────────
var current_scene_name: String = ""
var player_data: Dictionary = {}  # Expand this as you add inventory, stats, etc.
## Save slot the next MainWorld should restore once it reports startup_ready
## (set by the main menu's Continue/Load, consumed by LoadingScreen). 0 = none.
var pending_load_slot: int = 0
## Set by character creation's Begin, consumed by LoadingScreen: a brand-new
## game shows the survivor selection (SurvivorSelectScreen) before the world
## is revealed. Continue/Load and every other route leave it false.
var pending_new_game: bool = false

# ─── Scene Transition ─────────────────────────────────────────────────────────
## Sep 2026 — leave the running MainWorld for another scene (game over →
## reload via LoadingScreen, future "exit to main menu"). Clears autoload
## state that references nodes of the world being freed, then swaps scene.
## Set pending_load_slot / CharacterCreationData first when reloading a save.
func leave_world(scene_path: String) -> Error:
	Engine.time_scale = 1.0
	var job_board: Node = get_node_or_null("/root/JobBoard")
	if job_board != null and job_board.has_method("reset_world_state"):
		job_board.call("reset_world_state")
	var notifications: Node = get_node_or_null("/root/NotificationManager")
	if notifications != null and notifications.has_method("clear_transient_queue"):
		notifications.call("clear_transient_queue")
	current_scene_name = scene_path.get_file().get_basename()
	var error := get_tree().change_scene_to_file(scene_path)
	if error == OK:
		scene_changed.emit(current_scene_name)
	return error

func change_scene(path: String) -> void:
	current_scene_name = path.get_file().get_basename()
	get_tree().change_scene_to_file(path)
	scene_changed.emit(current_scene_name)
