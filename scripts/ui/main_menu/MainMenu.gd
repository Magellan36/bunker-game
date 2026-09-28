extends Node
## MainMenu.gd (Sep 2026)
## Boot scene orchestrator. Owns three things only:
##   1. The surface backdrop: loaded on threads so the menu appears at once,
##      then revealed with a short fade (the menu still works if it never is).
##      Load speed: with vsync on, every GPU texture upload waits for a shown
##      frame (~75 ms per texture here; ~140 textures = 8+ s). V-sync is
##      therefore off only while the backdrop loads (the screen is black
##      then) and the player's setting is restored the moment it is ready.
##      With parallel sub-thread loading that brings the load to under 1 s.
##   2. The curtain: sits *under* the UI for the opening (the wordmark reveals
##      over black), then moves *over* everything when leaving.
##   3. Hand-offs: New Game -> character creation, Continue/Load -> loading
##      screen with a pending slot, Settings overlay, Quit.
## Presentation lives in MainMenuScreen.gd; the 3D scene in MenuBackdrop.gd.

const NEW_GAME_SCENE: String = "res://scenes/ui/character_creation/CharacterCreation.tscn"
const LOADING_SCENE: String = "res://scenes/ui/LoadingScreen.tscn"
const SETTINGS_SCRIPT: String = "res://scripts/ui/menus/GraphicsSettingsPanel.gd"
const NAV_SCRIPT: GDScript = preload("res://scripts/ui/common/ControllerUINavigation.gd")
const CURTAIN_UNDER_UI: int = 5
const CURTAIN_OVER_ALL: int = 250

## The 3D scene behind the menu. Any scene exposing MenuBackdrop.gd's API works.
@export_file("*.tscn") var backdrop_scene_path: String = "res://scenes/world/menu_backdrop/MenuBackdrop.tscn"
## Give up waiting for the backdrop after this long and show the menu anyway.
@export var backdrop_timeout: float = 8.0
## Short reveal once the backdrop is in and its first frames have rendered.
@export var backdrop_fade_seconds: float = 0.5
@export var exit_seconds: float = 1.2
@export var music: AudioStream
@export var music_volume_db: float = -12.0

@onready var _backdrop_host: Node3D = $BackdropHost
@onready var _screen: Control = $Interface/Screen
@onready var _curtain_layer: CanvasLayer = $Curtain
@onready var _curtain: ColorRect = $Curtain/Black

var _backdrop: Node = null
var _settings: CanvasLayer = null
var _settings_open: bool = false
var _presented: bool = false
var _leaving: bool = false
var _waited: float = 0.0
var _music: AudioStreamPlayer = null
var _vsync_to_restore: int = -1


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_curtain_layer.layer = CURTAIN_UNDER_UI
	_curtain.color = Color.BLACK
	_curtain.modulate.a = 1.0
	_screen.connect("action_requested", _on_action)
	var nav: Node = NAV_SCRIPT.new()
	nav.set("ui_root", _screen)
	nav.set("close_on_cancel", false)
	add_child(nav)
	if music != null:
		_music = AudioStreamPlayer.new()
		_music.stream = music
		_music.volume_db = -60.0
		add_child(_music)
		_music.play()
		create_tween().tween_property(_music, "volume_db", music_volume_db, 3.0)
	_screen.call("play_intro")
	if backdrop_scene_path.is_empty():
		_present(null)
		return
	_vsync_to_restore = DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if ResourceLoader.load_threaded_request(backdrop_scene_path, "", true) != OK:
		_present(null)


func _exit_tree() -> void:
	_restore_vsync()


func _restore_vsync() -> void:
	if _vsync_to_restore >= 0:
		DisplayServer.window_set_vsync_mode(_vsync_to_restore as DisplayServer.VSyncMode)
		_vsync_to_restore = -1


func _process(delta: float) -> void:
	if not _presented:
		_waited += delta
		var status := ResourceLoader.load_threaded_get_status(backdrop_scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_present(ResourceLoader.load_threaded_get(backdrop_scene_path) as PackedScene)
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			# Parallel sub-thread loading can race on a dependency (seen
			# headless on the terrain's normal map); a plain load of the same
			# file then succeeds, so fall back rather than lose the backdrop.
			push_warning("[MainMenu] Threaded backdrop load failed; loading it directly.")
			_present(ResourceLoader.load(backdrop_scene_path) as PackedScene)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS or _waited > backdrop_timeout:
			push_warning("[MainMenu] Backdrop unavailable; showing the menu without it.")
			_present(null)
		return
	if _backdrop == null:
		return
	_screen.call("set_flash", float(_backdrop.call("get_flash")))
	_screen.call("set_gust", float(_backdrop.call("get_gust")))
	if not _leaving:
		_backdrop.call("set_pointer", _pointer())
	if _settings_open and _settings != null and not bool(_settings.call("is_open")):
		_settings_open = false
		_screen.call("set_overlay_active", false)


func _present(scene: PackedScene) -> void:
	_presented = true
	_restore_vsync()
	if scene != null:
		_backdrop = scene.instantiate()
		_backdrop_host.add_child(_backdrop)
		# The first two frames compile pipelines (~70-95 ms each); let them
		# happen behind the curtain so the fade itself is smooth.
		await get_tree().process_frame
		await get_tree().process_frame
	var fade := UIMotion.duration(backdrop_fade_seconds if _backdrop != null else 0.6)
	var tween := create_tween()
	tween.tween_property(_curtain, "modulate:a", 0.0, fade) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _input(event: InputEvent) -> void:
	# The first deliberate input also settles the camera's opening dolly.
	if _backdrop != null and bool(_screen.call("is_intro_running")):
		var deliberate: bool = (event is InputEventKey and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed)
		if deliberate:
			_backdrop.call("skip_intro")


func _pointer() -> Vector2:
	if InputMode.is_controller():
		return Vector2.ZERO
	var viewport := get_viewport().get_visible_rect().size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return Vector2.ZERO
	var mouse := get_viewport().get_mouse_position()
	return Vector2(mouse.x / viewport.x - 0.5, mouse.y / viewport.y - 0.5) * 2.0


func _on_action(action: StringName, slot: int) -> void:
	match action:
		&"new_game":
			_leave(NEW_GAME_SCENE)
		&"continue", &"load_slot":
			_start_load(slot)
		&"settings":
			_open_settings()
		&"quit":
			_leave("")
		_:
			push_warning("[MainMenu] Unknown action: %s" % action)
			_screen.call("release")


func _start_load(slot: int) -> void:
	var info: Dictionary = SaveManager.get_slot_info(slot)
	if not info.get("exists", false):
		_screen.call("release")
		return
	# The player model reads the body choice when the world instantiates, so
	# restore it before the loading screen builds MainWorld.
	var gender := str(info.get("gender", ""))
	if gender == "male" or gender == "female":
		CharacterCreationData.gender = gender
	WorldManager.pending_load_slot = slot
	_leave(LOADING_SCENE)


func _open_settings() -> void:
	if _settings == null:
		var script := load(SETTINGS_SCRIPT) as GDScript
		if script == null:
			push_warning("[MainMenu] GraphicsSettingsPanel.gd not found")
			return
		_settings = CanvasLayer.new()
		_settings.set_script(script)
		_settings.name = "GraphicsSettingsPanel"
		_settings.set("back_button_text", "Back")
		add_child(_settings)
	_settings_open = true
	_screen.call("set_overlay_active", true)
	_settings.call("open")


## Fade everything out and change scene; an empty path quits the game.
func _leave(scene_path: String) -> void:
	if _leaving:
		return
	_leaving = true
	var seconds := UIMotion.duration(exit_seconds)
	_screen.call("play_outro", exit_seconds)
	if _backdrop != null:
		_backdrop.call("play_exit", exit_seconds)
	_curtain_layer.layer = CURTAIN_OVER_ALL
	var tween := create_tween()
	tween.tween_property(_curtain, "modulate:a", 1.0, maxf(seconds, 0.01)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if _music != null:
		create_tween().tween_property(_music, "volume_db", -60.0, maxf(seconds, 0.01))
	tween.tween_callback(func() -> void:
		if scene_path.is_empty():
			get_tree().quit()
			return
		var error := get_tree().change_scene_to_file(scene_path)
		if error != OK:
			push_error("[MainMenu] Could not open %s (error %d)" % [scene_path, error])
			WorldManager.pending_load_slot = 0
			_leaving = false
			_curtain.modulate.a = 0.0
			_screen.call("release"))
