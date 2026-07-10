extends Node
## GraphicsSettings.gd
## Device-level rendering/quality preferences — deliberately SEPARATE from
## SaveManager's gameplay save-slot system (this is a hardware/device
## preference, not game state; see PROJECT_SUMMARY.md §7 for why those two
## are kept apart). Persists to user://graphics_settings.cfg, independent of
## save slots.
##
## NOT YET REGISTERED AS AN AUTOLOAD — per the known Godot class-cache /
## project.godot-autoload-ownership gotcha, Brannon adds this manually via
## Project Settings > Autoload (name it exactly "GraphicsSettings") after
## pulling, rather than us hand-editing project.godot's [autoload] section.
## Every other script referencing the bare identifier `GraphicsSettings`
## (GraphicsSettingsPanel.gd, later Flashlight.gd/GameCamera.gd wiring) will
## show "Could not find type" errors until that registration is done.

signal settings_changed

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }

const CFG_PATH: String = "user://graphics_settings.cfg"

var current_preset: Preset = Preset.MEDIUM

# ─── Individual toggles ────────────────────────────────────────────────────
## Mirrors the preset table from the graphics plan (Section 8). Defaults
## below match Preset.MEDIUM so a fresh install with no config file yet
## behaves the same as explicitly picking Medium.
var sdfgi_enabled:         bool = false
var ssao_enabled:          bool = true
var ssil_enabled:          bool = false
var volumetric_fog_enabled: bool = true
var flashlight_volumetrics: bool = true
## Opt-in ONLY, default OFF, and deliberately NOT part of any preset —
## Flashlight.gd's no-shadow default is a documented gameplay choice
## (handheld shadow would block the center of the beam cone), not a
## performance fallback. See LightingDirector.gd / graphics plan Section 2.
var flashlight_shadows:    bool = false
var glow_enabled:          bool = true
var dof_enabled:           bool = false
var msaa:                  int  = Viewport.MSAA_2X

const PRESETS: Dictionary = {
	Preset.LOW: {
		"sdfgi_enabled": false, "ssao_enabled": true, "ssil_enabled": false,
		"volumetric_fog_enabled": false, "flashlight_volumetrics": false,
		"glow_enabled": false, "dof_enabled": false, "msaa": Viewport.MSAA_DISABLED,
	},
	Preset.MEDIUM: {
		"sdfgi_enabled": false, "ssao_enabled": true, "ssil_enabled": false,
		"volumetric_fog_enabled": true, "flashlight_volumetrics": true,
		"glow_enabled": true, "dof_enabled": false, "msaa": Viewport.MSAA_2X,
	},
	Preset.HIGH: {
		"sdfgi_enabled": true, "ssao_enabled": true, "ssil_enabled": false,
		"volumetric_fog_enabled": true, "flashlight_volumetrics": true,
		"glow_enabled": true, "dof_enabled": true, "msaa": Viewport.MSAA_2X,
	},
	Preset.ULTRA: {
		"sdfgi_enabled": true, "ssao_enabled": true, "ssil_enabled": true,
		"volumetric_fog_enabled": true, "flashlight_volumetrics": true,
		"glow_enabled": true, "dof_enabled": true, "msaa": Viewport.MSAA_4X,
	},
}


func _ready() -> void:
	_load()
	_apply_all()


## Applies a named preset. flashlight_shadows is intentionally untouched here
## — it never resets when switching presets, per the "opt-in only, never
## preset-driven" decision.
func apply_preset(preset: Preset) -> void:
	if preset == Preset.CUSTOM or not PRESETS.has(preset):
		return
	var vals: Dictionary = PRESETS[preset]
	for key: String in vals:
		set(key, vals[key])
	current_preset = preset
	_apply_all()
	_save()


## Generic single-setting override, used by GraphicsSettingsPanel's individual
## checkboxes. Flips current_preset to CUSTOM (except for flashlight_shadows,
## which doesn't participate in preset matching at all).
func set_setting(field: String, value: Variant) -> void:
	match field:
		"sdfgi_enabled":            sdfgi_enabled = value
		"ssao_enabled":             ssao_enabled = value
		"ssil_enabled":             ssil_enabled = value
		"volumetric_fog_enabled":   volumetric_fog_enabled = value
		"flashlight_volumetrics":   flashlight_volumetrics = value
		"flashlight_shadows":       flashlight_shadows = value
		"glow_enabled":             glow_enabled = value
		"dof_enabled":              dof_enabled = value
		"msaa":                     msaa = value
		_:
			push_warning("[GraphicsSettings] Unknown field: %s" % field)
			return
	if field != "flashlight_shadows":
		current_preset = Preset.CUSTOM
	_apply_all()
	_save()


func _apply_all() -> void:
	_apply_to_environment()
	_apply_to_viewport()
	settings_changed.emit()


## Finds the world's WorldEnvironment via the "world_environment" group
## (added to the node in MainWorld.tscn) rather than a direct scene path —
## keeps this autoload decoupled from any single scene's node tree.
func _apply_to_environment() -> void:
	var world_env: WorldEnvironment = get_tree().get_first_node_in_group("world_environment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	env.sdfgi_enabled          = sdfgi_enabled
	env.ssao_enabled           = ssao_enabled
	env.ssil_enabled           = ssil_enabled
	env.volumetric_fog_enabled = volumetric_fog_enabled
	env.glow_enabled           = glow_enabled
	## DOF in Godot 4 lives on CameraAttributes (per-Camera3D), not
	## Environment — dof_enabled is wired into GameCamera.gd in Phase 7,
	## this is just the storage/persistence half for now.


func _apply_to_viewport() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	## `msaa` is already stored using the raw Viewport.MSAA_* enum ints — enums
	## are plain ints in GDScript, and `as` does NOT support enum casts (only
	## Object/class casts). Direct assignment is correct and avoids a parse
	## error here (this was the actual root cause of the autoload silently
	## failing to load — see HANDOVER note).
	tree.root.msaa_3d = msaa


func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "preset", current_preset)
	cfg.set_value("graphics", "sdfgi_enabled", sdfgi_enabled)
	cfg.set_value("graphics", "ssao_enabled", ssao_enabled)
	cfg.set_value("graphics", "ssil_enabled", ssil_enabled)
	cfg.set_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled)
	cfg.set_value("graphics", "flashlight_volumetrics", flashlight_volumetrics)
	cfg.set_value("graphics", "flashlight_shadows", flashlight_shadows)
	cfg.set_value("graphics", "glow_enabled", glow_enabled)
	cfg.set_value("graphics", "dof_enabled", dof_enabled)
	cfg.set_value("graphics", "msaa", msaa)
	cfg.save(CFG_PATH)


func _load() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return   ## No file yet — Medium-equivalent defaults above stand.
	current_preset          = cfg.get_value("graphics", "preset", current_preset)
	sdfgi_enabled            = cfg.get_value("graphics", "sdfgi_enabled", sdfgi_enabled)
	ssao_enabled             = cfg.get_value("graphics", "ssao_enabled", ssao_enabled)
	ssil_enabled             = cfg.get_value("graphics", "ssil_enabled", ssil_enabled)
	volumetric_fog_enabled   = cfg.get_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled)
	flashlight_volumetrics   = cfg.get_value("graphics", "flashlight_volumetrics", flashlight_volumetrics)
	flashlight_shadows       = cfg.get_value("graphics", "flashlight_shadows", flashlight_shadows)
	glow_enabled             = cfg.get_value("graphics", "glow_enabled", glow_enabled)
	dof_enabled              = cfg.get_value("graphics", "dof_enabled", dof_enabled)
	msaa                     = cfg.get_value("graphics", "msaa", msaa)
