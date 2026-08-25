extends Node
## GraphicsSettings.gd
## Device-level rendering/quality preferences — deliberately SEPARATE from
## SaveManager's gameplay save-slot system (this is a hardware/device
## preference, not game state; see PROJECT_SUMMARY.md §7 for why those two
## are kept apart). Persists to user://graphics_settings.cfg, independent of
## save slots.
##
## Registered as an autoload ("GraphicsSettings") in project.godot's
## [autoload] section — other scripts reference it via the bare identifier
## `GraphicsSettings` (GraphicsSettingsPanel.gd, Flashlight.gd, GameCamera.gd,
## WallLight.gd, GrowLight.gd, CharacterPreviewViewport.gd, ...).

signal settings_changed

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }

const CFG_PATH: String = "user://graphics_settings.cfg"

## Aug 2026 — Rendering Driver switch (Vulkan/D3D12). See
## docs/systems/graphics/README.md "Rendering driver switch" for the full
## design — short version: the driver is locked in at engine startup and
## CANNOT change mid-session (Godot hard limitation, not something this
## code works around), so this is a restart-based setting: save the
## choice, relaunch to apply it. Windows-only (this project's stated
## target platform) — matches project.godot's `driver.windows` key.
const RENDERING_DRIVERS: Array[String] = ["vulkan", "d3d12"]

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
var volumetric_fog_enabled: bool = false
var flashlight_volumetrics: bool = false
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

var glow_enabled:          bool = true
var dof_enabled:           bool = false
var msaa:                  int  = Viewport.MSAA_2X

## Camera FOV (graphics plan Phase 7) — NOT part of any preset (a comfort/
## motion-sickness preference, not a quality tier), read directly by
## GameCamera.gd via its own settings_changed connection, same pattern as
## Flashlight.gd. Default lowered 75→60 (Aug 2026) so the iso camera sits
## meaningfully closer to the player out of the box; the slider range is
## 45–75 centered on it. Godot's raw Camera3D default is 75.0.
var camera_fov: float = 60.0

## Display settings (Phase 2) — device/display behavior, not quality tier
var vsync_enabled: bool = true
var window_mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN
var fps_cap: int = 0   ## 0 = uncapped

## Aug 2026 — the player's SAVED rendering driver preference. Deliberately
## NOT part of PRESETS and NOT wired into set_setting_live() — it can't
## apply live (see RENDERING_DRIVERS comment above), so lumping it in with
## the fields that call _apply_all() every change would be misleading. Use
## set_rendering_driver() below instead. Matches project.godot's committed
## default ("vulkan") — this var is what changes on disk, never the
## committed project file itself.
var rendering_driver: String = "vulkan"

## Captured ONCE, at the end of _load() below — the driver value that was
## on disk when THIS session booted, which by construction of the relaunch
## flow (see GraphicsSettingsPanel.gd's _relaunch_with_driver()) is what
## the engine is actually running under right now. Comparing a pending new
## choice against this (not against `rendering_driver`, which may already
## have been overwritten by the time the comparison happens) is how the
## panel decides whether to show "restart required."
var session_start_rendering_driver: String = "vulkan"

## Anti-aliasing overhaul (Phase 3)
var screen_space_aa: int = Viewport.SCREEN_SPACE_AA_DISABLED
var use_taa: bool = false

## Phase 4 — Anisotropic filtering, shadow quality, render scale
var anisotropic_filtering: int = 4
var shadow_quality: int = 2048
var render_scale: float = 1.0

## Shadow LOD (Aug 2026) — distance-gated shadow casting for player-placed
## fixtures (WallLight/GrowLight). WallLight/GrowLight are Build-Mode
## devices with no cap on how many can exist in a base — at HIGH/ULTRA
## (shadow_casting_enabled = true) a large base can have far more
## simultaneous shadow-casting lights than the scene ever had before Build
## Mode existed. Godot has no per-light "render this shadow cheaper at
## distance" knob, so the practical version of "far shadows cost less" is a
## binary gate: a light beyond SHADOW_LOD_FAR_RADIUS of the player has its
## shadow_enabled forced off (skips the render pass entirely — the cheapest
## possible state); once shadow_enabled is back on within
## SHADOW_LOD_NEAR_RADIUS, Godot's own shadow-atlas allocator naturally
## favors it over anything else still in range. NEAR < FAR on purpose
## (hysteresis) so a light hovering right at the boundary can't flip on/off
## every scan as the player's distance jitters by a few cm. Scanned on a
## throttle (SHADOW_LOD_SCAN_INTERVAL), same reasoning as JobBoard's 2s
## rescan — this only needs to react to the player walking around, not to
## run every frame. Entirely skipped when shadow_casting_enabled is false
## (LOW/MEDIUM or Custom-off) — nothing to gate, zero cost.
const SHADOW_LOD_NEAR_RADIUS: float = 14.0
const SHADOW_LOD_FAR_RADIUS:  float = 18.0
const SHADOW_LOD_SCAN_INTERVAL: float = 0.5
var _shadow_lod_scan_timer: float = 0.0

## Dynamic Resolution (Aug 2026) — the LIVE render scale auto-adjusts
## between DR_SCALE_FLOOR and the user's `render_scale` (the quality
## ceiling) to hold the target frame budget (fps_cap if set, else the
## display refresh rate, else 60). Preset-INDEPENDENT comfort/performance
## setting like camera_fov — never routed through PRESETS. Disabled =
## the fixed `render_scale` is applied exactly as before (bilinear);
## enabled = the controller owns the scale (still BILINEAR upscaling —
## FSR 1.0 reads pixelated/soft here and degrades the full-res case).
##
## OFF by default (Aug 2026): this game is CPU-bound (physics/objects), and
## DR only buys back GPU time — on a CPU bottleneck it just sits at the
## lowered scale forever, making the whole screen hazy for zero gain. It's
## an opt-in safeguard for GPU-bound setups only.
var dynamic_resolution_enabled: bool = false

## DR tuning: steps of DR_STEP; needs DR_DOWN_FRAMES consecutive
## over-budget frames to lower (ramps down fast on a sustained drop) and
## DR_UP_FRAMES consecutive comfortable frames to raise (restores slowly);
## DR_COOLDOWN forces a gap between steps so one spike can't ratchet twice.
## DR_SCALE_FLOOR is deliberately HIGH (0.8) — DR is a subtle safeguard, and
## a deep floor downscales the whole screen into visible pixelation.
const DR_SCALE_FLOOR: float = 0.8
const DR_STEP: float = 0.05
const DR_DOWN_FRAMES: int = 5
const DR_UP_FRAMES: int = 30
const DR_COOLDOWN: float = 0.15
## Frame-time EMA blend (lower = smoother, slower response).
const DR_EMA_ALPHA: float = 0.15
## Only step down when the EMA exceeds the budget by this much, so an
## exactly-at-target frame can't trigger a needless drop.
const DR_DOWN_TOLERANCE: float = 1.02
## Below this fraction of the budget counts as "comfortable" (raise allowed).
const DR_UP_THRESHOLD: float = 0.8

## The LIVE scale currently applied (<= render_scale). Owned by the DR
## controller while enabled; tracks render_scale while disabled.
var _dr_scale: float = 1.0
var _dr_frame_avg: float = 0.0
var _dr_over_budget_frames: int = 0
var _dr_under_budget_frames: int = 0
var _dr_cooldown: float = 0.0

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
		"volumetric_fog_enabled": false, "flashlight_volumetrics": false,
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
	## The autoload boots before MainWorld exists, so _apply_to_environment()
	## finds no "world_environment" node yet and saved SDFGI/SSAO/volumetrics/
	## glow would sit at the scene's authored defaults until the first toggle.
	## Re-apply whenever a WorldEnvironment enters the tree (fires once per
	## world load) so saved settings take effect at startup.
	get_tree().node_added.connect(_on_node_added)


## Re-applies the environment settings when the world scene's WorldEnvironment
## node enters the tree. Idempotent — safe to fire on every world load.
func _on_node_added(node: Node) -> void:
	if node.is_in_group("world_environment"):
		_apply_to_environment()


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
		"render_scale":             render_scale = value; _dr_scale = value
		"dynamic_resolution_enabled": dynamic_resolution_enabled = value
		"camera_fov":               camera_fov = value
		"vsync_enabled":            vsync_enabled = value
		"window_mode":              window_mode = value
		"fps_cap":                  fps_cap = value
		_:	
			push_warning("[GraphicsSettings] Unknown field: %s" % field)
			return
	if field != "camera_fov" and field != "dynamic_resolution_enabled":
		current_preset = Preset.CUSTOM
	_apply_all()


## Persists current settings to disk. Call after a batch of set_setting_live()
## calls once the user's interaction is actually done (see set_setting_live()).
func save_now() -> void:
	_save()


## Aug 2026 — dedicated setter for rendering_driver, deliberately separate
## from set_setting_live(). That function assumes every field it touches
## can be applied live via _apply_all() and flips current_preset to
## CUSTOM — neither is true here (see RENDERING_DRIVERS comment). This
## just updates the value and saves immediately; GraphicsSettingsPanel.gd
## is responsible for deciding whether to show the restart prompt and for
## actually relaunching.
func set_rendering_driver(value: String) -> void:
	if not RENDERING_DRIVERS.has(value):
		push_warning("[GraphicsSettings] Unknown rendering driver: %s" % value)
		return
	rendering_driver = value
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
	if dynamic_resolution_enabled:
		## BILINEAR upscaling throughout — the same mode the render-scale
		## slider used before DR existed, so a given scale looks exactly as
		## crisp as it always did (FSR 1.0 reads pixelated on this art and
		## even softens the 1.0 case). The controller owns
		## scaling_3d_scale between DR_SCALE_FLOOR and the user's ceiling.
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = _dr_scale
	else:
		_dr_scale = render_scale
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = render_scale

## Dynamic Resolution controller (Aug 2026). Runs every frame while DR is
## enabled: smooths the frame time, compares against the target budget, and
## only moves the live scale after enough consecutive slow/fast frames
## (hysteresis) plus a cooldown gap — so it reacts to sustained drops
## without oscillating on a single spike. Preview SubViewports are
## unaffected (register_preview_viewport only mirrors MSAA, not scale).
func _process(delta: float) -> void:
	_update_shadow_lod(delta)
	if not dynamic_resolution_enabled:
		return
	_dr_frame_avg = lerpf(_dr_frame_avg, delta, DR_EMA_ALPHA)
	if _dr_cooldown > 0.0:
		_dr_cooldown -= delta
		return
	var budget: float = _target_frame_budget()
	if _dr_frame_avg > budget * DR_DOWN_TOLERANCE:
		_dr_over_budget_frames += 1
		_dr_under_budget_frames = 0
		if _dr_over_budget_frames >= DR_DOWN_FRAMES:
			_dr_scale = maxf(DR_SCALE_FLOOR, _dr_scale - DR_STEP)
			_dr_over_budget_frames = 0
			_dr_cooldown = DR_COOLDOWN
			get_viewport().scaling_3d_scale = _dr_scale
	elif _dr_frame_avg < budget * DR_UP_THRESHOLD:
		_dr_under_budget_frames += 1
		_dr_over_budget_frames = 0
		if _dr_under_budget_frames >= DR_UP_FRAMES:
			_dr_scale = minf(render_scale, _dr_scale + DR_STEP)
			_dr_under_budget_frames = 0
			_dr_cooldown = DR_COOLDOWN
			get_viewport().scaling_3d_scale = _dr_scale
	else:
		_dr_over_budget_frames = 0
		_dr_under_budget_frames = 0

## The frame budget DR holds against: the player's fps_cap if one is set,
## else the current display's refresh rate, else a 60 fps fallback.
func _target_frame_budget() -> float:
	if fps_cap > 0:
		return 1.0 / float(fps_cap)
	var refresh: int = DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	if refresh > 0:
		return 1.0 / float(refresh)
	return 1.0 / 60.0

## Shadow LOD scan (Aug 2026, see SHADOW_LOD_* header comment above) —
## throttled to SHADOW_LOD_SCAN_INTERVAL, skipped entirely when shadows are
## globally off. Every "shadow_lod_lights" member gets a fresh distance
## check against the player each time this fires; each light owns its own
## hysteresis state (update_shadow_lod()) so this scan doesn't need to
## track per-light state itself.
func _update_shadow_lod(delta: float) -> void:
	if not shadow_casting_enabled:
		return
	_shadow_lod_scan_timer -= delta
	if _shadow_lod_scan_timer > 0.0:
		return
	_shadow_lod_scan_timer = SHADOW_LOD_SCAN_INTERVAL
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var player: Node3D = tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var player_pos: Vector3 = player.global_position
	for light: Node in tree.get_nodes_in_group("shadow_lod_lights"):
		if is_instance_valid(light) and light.has_method("update_shadow_lod"):
			light.update_shadow_lod(player_pos)

## 3D item-preview SubViewports (Aug 2026) — apply MSAA so the models in
## inventory/storage/build/prompt previews aren't jagged (SubViewports
## default to MSAA_DISABLED and do NOT inherit the main viewport's setting).
## Registers a viewport to follow the current msaa and settings changes;
## auto-disconnects when the viewport leaves the tree.
##
## Preview MSAA is CAPPED at 2X: these viewports are small (40-96px) and
## displayed downscaled, so 4X/8X there allocates a per-viewport
## multisampled resolve for essentially invisible benefit — a build submenu
## holding ~20 previews would otherwise multiply the heaviest AA cost. The
## main viewport still follows the player's full choice.
func register_preview_viewport(vp: SubViewport) -> void:
	if vp == null:
		return
	var capped_msaa: int = mini(msaa, Viewport.MSAA_2X)
	vp.msaa_3d = capped_msaa
	var apply := func() -> void:
		if is_instance_valid(vp):
			vp.msaa_3d = mini(msaa, Viewport.MSAA_2X)
	settings_changed.connect(apply)
	vp.tree_exited.connect(func() -> void:
		settings_changed.disconnect(apply))

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
	cfg.set_value("graphics", "dynamic_resolution_enabled", dynamic_resolution_enabled)
	cfg.set_value("graphics", "camera_fov", camera_fov)
	cfg.set_value("graphics", "vsync_enabled", vsync_enabled)
	cfg.set_value("graphics", "window_mode", window_mode)
	cfg.set_value("graphics", "fps_cap", fps_cap)
	cfg.set_value("graphics", "rendering_driver", rendering_driver)
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
	dynamic_resolution_enabled = cfg.get_value("graphics", "dynamic_resolution_enabled", dynamic_resolution_enabled)
	camera_fov               = cfg.get_value("graphics", "camera_fov", camera_fov)
	vsync_enabled            = cfg.get_value("graphics", "vsync_enabled", vsync_enabled)
	window_mode              = cfg.get_value("graphics", "window_mode", window_mode)
	fps_cap                  = cfg.get_value("graphics", "fps_cap", fps_cap)
	rendering_driver         = cfg.get_value("graphics", "rendering_driver", rendering_driver)
	## Snapshot AFTER the load above — see session_start_rendering_driver's
	## declaration comment for why this must be captured here, once, and
	## never reassigned afterward.
	session_start_rendering_driver = rendering_driver
