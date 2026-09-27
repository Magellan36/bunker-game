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

# ─── Scene Transition ─────────────────────────────────────────────────────────
func change_scene(path: String) -> void:
	current_scene_name = path.get_file().get_basename()
	get_tree().change_scene_to_file(path)
	scene_changed.emit(current_scene_name)
