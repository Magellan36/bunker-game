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

## Plain `int` rather than `Preset` — see apply_preset()'s header comment for
## why (avoids any int/enum ambiguity at the call boundary entirely).
var current_preset: int = Preset.MEDIUM

# ─── Individual toggles ────────────────────────────────────────────────────
## Mirrors the preset table from the graphics plan (Section 8). Defaults
## below match Preset.MEDIUM so a fresh install with no config file yet
## behaves the same as explicitly picking Medium.
var sdfgi_enabled:         bool = false
var ssao_enabled:          bool = true
var ssil_enabled:          bool = false
var volumetric_fog_enabled: bool = true
var flashlight_volumetrics: bool = true
## Aug 2026 — generalized from flashlight-only to all dynamic
## shadow-casting lights (Flashlight, WallLight, GrowLight — see
## docs/systems/graphics/README.md "Unified dynamic shadow casting").
## Preset-driven now (LOW/MEDIUM = false, HIGH/ULTRA = true, same as SDFGI/
## SSAO/etc.) rather than opt-in-only — still individually toggleable via
## the Settings panel's "Shadow Casting" checkbox, which now flips
## current_preset to CUSTOM like every other preset-tier toggle (see
## set_setting_live() below — camera_fov is now the only field still
## excluded from that).
var shadow_casting_enabled: bool = false

## Aug 2026 — shared render layer for every character (player + NPCs)
## whose light/shadow now comes from an aggregated CharacterShadowProxy
## instead of real per-light shadow maps (see
## docs/systems/graphics/README.md "Aggregated character shadows"). Every
## real light (Flashlight/WallLight/GrowLight) clears this bit from its
## own light_cull_mask; CharacterShadowProxy.gd is the only thing that
## includes it. Was Player.PLAYER_SELF_LIGHT_LAYER_BIT (flashlight-only)
## before this session generalized it — relocated here since it's now a
## cross-thread rendering convention (Player, NPC, Power, Furniture/Items
## all reference it), not something one thread should own. Layer 11 is
## already reserved by InteractionFocusGlow.gd's HIGHLIGHT_LAYER — this
## stays layer 12, the value it already had as Player's constant.
const CHARACTER_SHADOW_LAYER: int = 12
const CHARACTER_SHADOW_LAYER_BIT: int = 1 << (CHARACTER_SHADOW_LAYER - 1)
var glow_enabled:          bool = true
var dof_enabled:           bool = false
var msaa:                  int  = Viewport.MSAA_2X

## Camera FOV (graphics plan Phase 7) — NOT part of any preset (a comfort/
## motion-sickness preference, not a quality tier), read directly by
## GameCamera.gd via its own settings_changed connection, same pattern as
## Flashlight.gd. Godot's Camera3D default is 75.0.
var camera_fov: float = 75.0

## Display settings (Phase 2) — device/display behavior, not quality tier
var vsync_enabled: bool = true
var window_mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN
var fps_cap: int = 0   ## 0 = uncapped

## Anti-aliasing overhaul (Phase 3)
var screen_space_aa: int = Viewport.SCREEN_SPACE_AA_DISABLED
var use_taa: bool = false

## Phase 4 — Anisotropic filtering, shadow quality, render scale
var anisotropic_filtering: int = 4
var shadow_quality: int = 2048
var render_scale: float = 1.0

const PRESETS: Dictionary = {
	Preset.LOW: {
		"sdfgi_enabled": false, "ssao_enabled": true, "ssil_enabled": false,
		"volumetric_fog_enabled": false, "flashlight_volumetrics": false,
		"glow_enabled": false, "dof_enabled": false, "msaa": Viewport.MSAA_DISABLED,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": false,
		"anisotropic_filtering": 2, "shadow_quality": 1024, "render_scale": 1.0,
		"shadow_casting_enabled": false,
	},
	Preset.MEDIUM: {
		"sdfgi_enabled": false, "ssao_enabled": true, "ssil_enabled": false,
		"volumetric_fog_enabled": true, "flashlight_volumetrics": true,
		"glow_enabled": true, "dof_enabled": false, "msaa": Viewport.MSAA_2X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": false,
		"anisotropic_filtering": 4, "shadow_quality": 2048, "render_scale": 1.0,
		"shadow_casting_enabled": false,
	},
	Preset.HIGH: {
		"sdfgi_enabled": true, "ssao_enabled": true, "ssil_enabled": false,
		"volumetric_fog_enabled": true, "flashlight_volumetrics": true,
		"glow_enabled": true, "dof_enabled": true, "msaa": Viewport.MSAA_2X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_FXAA, "use_taa": false,
		"anisotropic_filtering": 8, "shadow_quality": 4096, "render_scale": 1.0,
		"shadow_casting_enabled": true,
	},
	Preset.ULTRA: {
		"sdfgi_enabled": true, "ssao_enabled": true, "ssil_enabled": true,
		"volumetric_fog_enabled": true, "flashlight_volumetrics": true,
		"glow_enabled": true, "dof_enabled": true, "msaa": Viewport.MSAA_4X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": true,
		"anisotropic_filtering": 16, "shadow_quality": 4096, "render_scale": 1.0,
		"shadow_casting_enabled": true,
	},
}


func _ready() -> void:
	_load()
	_apply_all()


## Applies a named preset. Takes a plain `int` rather than `Preset` — the
## dropdown that calls this (`GraphicsSettingsPanel._on_preset_selected`)
## hands back a bare `int` from `OptionButton.item_selected`, and GDScript's
## `as` doesn't support enum casts (see `_apply_to_viewport()` below for the
## bug that already bit this file once from that exact class of mistake).
## Taking `int` here and comparing/indexing against the int-backed `Preset`
## enum values directly sidesteps the whole question instead of relying on
## implicit int→enum parameter passing. shadow_casting_enabled DOES reset
## with the preset now (Aug 2026 — LOW/MEDIUM off, HIGH/ULTRA on), unlike
## camera_fov, which remains untouched by every preset (see PRESETS above
## and set_setting_live() below).
func apply_preset(preset: int) -> void:
	if preset == Preset.CUSTOM or not PRESETS.has(preset):
		return
	var vals: Dictionary = PRESETS[preset]
	for key: String in vals:
		set(key, vals[key])
	current_preset = preset
	_apply_all()
	_save()


## Generic single-setting override, used by GraphicsSettingsPanel's individual
## checkboxes. Flips current_preset to CUSTOM (except for camera_fov, the
## only remaining field that doesn't participate in preset matching at all
## — shadow_casting_enabled joined the normal preset-driven fields Aug 2026).
func set_setting(field: String, value: Variant) -> void:
	set_setting_live(field, value)
	_save()


## Same as set_setting() but does NOT persist to disk — mutates + applies
## live only. For UI controls that fire continuously while being dragged
## (e.g. Slider.value_changed can fire ~40 times over one drag); pair with a
## call to save_now() once the interaction completes (e.g. Slider's
## drag_ended signal) so the settings file is only written once per
## interaction instead of on every intermediate tick.
func set_setting_live(field: String, value: Variant) -> void:
	match field:
		"sdfgi_enabled":            sdfgi_enabled = value
		"ssao_enabled":             ssao_enabled = value
		"ssil_enabled":             ssil_enabled = value
		"volumetric_fog_enabled":   volumetric_fog_enabled = value
		"flashlight_volumetrics":   flashlight_volumetrics = value
		"shadow_casting_enabled":   shadow_casting_enabled = value
		"glow_enabled":             glow_enabled = value
		"dof_enabled":              dof_enabled = value
		"msaa":                     msaa = value
		"screen_space_aa":          screen_space_aa = value
		"use_taa":                  use_taa = value
		"anisotropic_filtering":    anisotropic_filtering = value
		"shadow_quality":           shadow_quality = value
		"render_scale":             render_scale = value
		"camera_fov":               camera_fov = value
		"vsync_enabled":            vsync_enabled = value
		"window_mode":              window_mode = value
		"fps_cap":                  fps_cap = value
		_:	
			push_warning("[GraphicsSettings] Unknown field: %s" % field)
			return
	if field != "camera_fov":
		current_preset = Preset.CUSTOM
	_apply_all()


## Persists current settings to disk. Call after a batch of set_setting_live()
## calls once the user's interaction is actually done (see set_setting_live()).
func save_now() -> void:
	_save()


func _apply_all() -> void:
	_apply_to_environment()
	_apply_to_viewport()
	_apply_to_display()
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
	tree.root.screen_space_aa = screen_space_aa
	tree.root.use_taa = use_taa
	get_viewport().scaling_3d_scale = render_scale
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

## Display settings (VSync, window mode, FPS cap, anisotropic filtering, shadow quality)
func _apply_to_display() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(window_mode)
	Engine.max_fps = fps_cap
	ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", anisotropic_filtering)
	get_viewport().positional_shadow_atlas_size = shadow_quality


func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "preset", current_preset)
	cfg.set_value("graphics", "sdfgi_enabled", sdfgi_enabled)
	cfg.set_value("graphics", "ssao_enabled", ssao_enabled)
	cfg.set_value("graphics", "ssil_enabled", ssil_enabled)
	cfg.set_value("graphics", "volumetric_fog_enabled", volumetric_fog_enabled)
	cfg.set_value("graphics", "flashlight_volumetrics", flashlight_volumetrics)
	cfg.set_value("graphics", "shadow_casting_enabled", shadow_casting_enabled)
	cfg.set_value("graphics", "glow_enabled", glow_enabled)
	cfg.set_value("graphics", "dof_enabled", dof_enabled)
	cfg.set_value("graphics", "msaa", msaa)
	cfg.set_value("graphics", "screen_space_aa", screen_space_aa)
	cfg.set_value("graphics", "use_taa", use_taa)
	cfg.set_value("graphics", "anisotropic_filtering", anisotropic_filtering)
	cfg.set_value("graphics", "shadow_quality", shadow_quality)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "camera_fov", camera_fov)
	cfg.set_value("graphics", "vsync_enabled", vsync_enabled)
	cfg.set_value("graphics", "window_mode", window_mode)
	cfg.set_value("graphics", "fps_cap", fps_cap)
	cfg.set_value("graphics", "anisotropic_filtering", anisotropic_filtering)
	cfg.set_value("graphics", "shadow_quality", shadow_quality)
	cfg.set_value("graphics", "render_scale", render_scale)
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
	shadow_casting_enabled   = cfg.get_value("graphics", "shadow_casting_enabled", shadow_casting_enabled)
	glow_enabled             = cfg.get_value("graphics", "glow_enabled", glow_enabled)
	dof_enabled              = cfg.get_value("graphics", "dof_enabled", dof_enabled)
	msaa                     = cfg.get_value("graphics", "msaa", msaa)
	screen_space_aa          = cfg.get_value("graphics", "screen_space_aa", screen_space_aa)
	use_taa                  = cfg.get_value("graphics", "use_taa", use_taa)
	anisotropic_filtering    = cfg.get_value("graphics", "anisotropic_filtering", anisotropic_filtering)
	shadow_quality           = cfg.get_value("graphics", "shadow_quality", shadow_quality)
	render_scale             = cfg.get_value("graphics", "render_scale", render_scale)
	camera_fov               = cfg.get_value("graphics", "camera_fov", camera_fov)
	vsync_enabled            = cfg.get_value("graphics", "vsync_enabled", vsync_enabled)
	window_mode              = cfg.get_value("graphics", "window_mode", window_mode)
	fps_cap                  = cfg.get_value("graphics", "fps_cap", fps_cap)
