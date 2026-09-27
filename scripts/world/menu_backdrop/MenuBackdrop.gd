extends Node3D
## MenuBackdrop.gd (Sep 2026)
## Root of the main-menu surface scene: the ruined city above the bunker.
## Owns nothing gameplay-related. The menu talks to it through this small API
## only, so the whole scene can be swapped (MainMenu.backdrop_scene_path)
## without touching UI code.
##
##   set_pointer(v)      normalized pointer (-1..1) for camera parallax
##   skip_intro()        settle the opening dolly immediately
##   play_exit(seconds)  push-in + wind fade when leaving the menu
##   get_flash()         current lightning brightness (UI reacts to it)
##   get_gust()          current wind gust 0..1
##   signal struck(km)   a lightning strike just began
##
## Scene layout, asset slots and the art brief: docs/systems/main-menu/README.md

signal struck(distance_km: float)

@export var camera_rig: Node3D
@export var storm: Node
@export var wind: Node
@export var world_environment: WorldEnvironment
## Optional equirectangular cloud-sky texture (human-made/licensed). When set
## it replaces the procedural overcast gradient.
@export var sky_panorama: Texture2D
## Slow sky rotation so the cloud deck drifts; degrees per second.
@export var cloud_drift_deg_per_sec: float = 0.3
@export var sky_panorama_energy: float = 1.0

var _env: Environment


func _ready() -> void:
	if world_environment != null:
		_env = world_environment.environment
	if _env != null and sky_panorama != null and _env.sky != null:
		var panorama := PanoramaSkyMaterial.new()
		panorama.panorama = sky_panorama
		panorama.energy_multiplier = sky_panorama_energy
		_env.sky.sky_material = panorama
	if storm != null and storm.has_signal("struck"):
		storm.connect("struck", func(km: float) -> void: struck.emit(km))
	# Honour the player's graphics choices for the costly effects, live, but
	# never switch on SDFGI/SSIL here: an overcast exterior gains nothing.
	var graphics: Node = get_node_or_null("/root/GraphicsSettings")
	if graphics != null and graphics.has_signal("settings_changed"):
		graphics.connect("settings_changed", _apply_graphics_settings)
	_apply_graphics_settings()


func _process(delta: float) -> void:
	if _env != null and not UIMotion.reduced():
		_env.sky_rotation.y += deg_to_rad(cloud_drift_deg_per_sec) * delta


func set_pointer(normalized: Vector2) -> void:
	if camera_rig != null:
		camera_rig.call("set_pointer", normalized)


func skip_intro() -> void:
	if camera_rig != null:
		camera_rig.call("skip_intro")


func play_exit(seconds: float) -> void:
	if camera_rig != null:
		camera_rig.call("play_exit", seconds)
	if wind != null:
		wind.call("fade_to", 0.0, seconds)
	if storm != null:
		storm.set("enabled", false)


func get_flash() -> float:
	return float(storm.get("intensity")) if storm != null else 0.0


func get_gust() -> float:
	return float(wind.get("gust")) if wind != null else 0.0


func _apply_graphics_settings() -> void:
	var graphics: Node = get_node_or_null("/root/GraphicsSettings")
	if graphics == null or _env == null:
		return
	_env.volumetric_fog_enabled = bool(graphics.get("volumetric_fog_enabled"))
	_env.ssao_enabled = bool(graphics.get("ssao_enabled"))
	_env.glow_enabled = bool(graphics.get("glow_enabled"))
