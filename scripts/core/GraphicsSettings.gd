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
signal graphics_change_rejected(reason: String)

enum Preset { LOW, MEDIUM, HIGH, ULTRA, CUSTOM }

const CFG_PATH: String = "user://graphics_settings.cfg"

# Headroom below which raising memory-heavy settings is refused.
# Sep 2026 — was 2 GiB, which blocked almost every raise on a 12 GB system
# once the game + OS pushed available memory under it, even with memory to
# spare. Lowered to 512 MiB so the guard only trips when memory is genuinely
# about to run out (prevents OOM), not as a routine throttle. This is a
# pressure guard, not a promise that High fits every GPU or scene.
const GRAPHICS_MEMORY_HEADROOM: int = 512 * 1024 * 1024
## Settings whose raise can meaningfully inflate memory/VRAM and crash a low-
## memory machine. Sep 2026 — trimmed to the true allocators (SDFGI voxel
## GI, SSIL buffers, volumetric fog volume). Removed flashlight_volumetrics
## (light-scoped, tiny), shadow_casting_enabled (now only gates dynamic
## per-mesh shadows — small), dof_enabled (screen-space tilt-shift) and
## use_taa (modest temporal buffer) so a raise of those isn't refused.
const MEMORY_HEAVY_EFFECTS: Array[String] = [
	"sdfgi_enabled", "ssil_enabled", "volumetric_fog_enabled",
]

func _available_graphics_memory() -> int:
	# On Linux use reclaimable RAM, not MemFree (which omits caches) or swap.
	if OS.get_name() == "Linux" and FileAccess.file_exists("/proc/meminfo"):
		for line: String in FileAccess.get_file_as_string("/proc/meminfo").split("\n"):
			if line.begins_with("MemAvailable:"):
				var parts: PackedStringArray = line.split(" ", false)
				if parts.size() >= 2 and parts[1].is_valid_int():
					return int(parts[1]) * 1024
	return int(OS.get_memory_info().get("available", -1))

func _reject_memory_increase(changes: Dictionary) -> bool:
	var increases: bool = false
	for field: String in MEMORY_HEAVY_EFFECTS:
		if bool(changes.get(field, false)) and not bool(get(field)):
			increases = true
	for field: String in ["msaa", "shadow_quality", "render_scale"]:
		if changes.has(field) and float(changes[field]) > float(get(field)):
			increases = true
	if not increases:
		return false  # Always allow lowering settings, even under pressure.
	var available: int = _available_graphics_memory()
	if available < 0 or available >= GRAPHICS_MEMORY_HEADROOM:
		return false  # Unknown memory must not permanently lock out settings.
	var reason: String = "Graphics unchanged: only %.1f GiB of system memory is available. Close other apps before raising graphics quality." % (float(available) / 1073741824.0)
	graphics_change_rejected.emit(reason)
	return true


## Rendering drivers are selected at startup. Direct3D is Windows-only.
const RENDERING_DRIVERS: Array[String] = ["vulkan", "d3d12"]

func is_rendering_driver_supported(driver: String) -> bool:
	return driver == "vulkan" or (driver == "d3d12" and OS.get_name() == "Windows")

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
## Sep 2026 — now means "DYNAMIC shadow casting" specifically, within the
## "classic" two-layer split: lights ALWAYS cast (static walls/pillars always
## occlude them — the hard wall/corner shadow cutoff, present at every
## quality, independent of this setting). This field gates only the dynamic
## per-character/per-object shadows: when OFF (LOW/MEDIUM) those meshes'
## cast_shadow is forced OFF by _apply_dynamic_shadow_casting(); when ON
## (HIGH/ULTRA) their authored cast_shadow is restored. Preset-driven
## (LOW/MEDIUM = false, HIGH/ULTRA = true) — still individually toggleable
## via the Settings panel's "Dynamic shadows" checkbox, which flips
## current_preset to CUSTOM like every other preset-tier toggle (see
## set_setting_live() below — camera_fov is now the only field still
## excluded from that). See docs/systems/graphics/README.md "Structural
## shadow cutoff (Sep 2026)".
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
var shadow_quality: int = 4096   ## matches Preset.MEDIUM (the first-launch preset)
var render_scale: float = 1.0

## Sep 2026 — the distance-based shadow LOD (Aug 2026) was removed. Lights now
## ALWAYS cast shadows (the "classic" two-layer split: static geometry like
## walls/pillars always occludes the light, so the hard shadow cutoff at
## walls/corners is present at every quality preset — independent of
## shadow_casting_enabled). The old LOD force-disabled a far light's
## shadow_enabled, which would have silently removed the wall cutoff in the
## isometric view that sees the whole bunker. The cost of always-on casting is
## accepted by design (see _apply_dynamic_shadow_casting for the quality-
## scaled dynamic layer).

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

## ── Dynamic shadow layer (Sep 2026, "classic" two-layer split) ──────────────
## Lights ALWAYS cast (static walls/pillars always occlude them — the hard
## wall/corner cutoff at every quality). `shadow_casting_enabled` now means
## "cast DYNAMIC (character/object) shadows" specifically: when OFF (LOW/
## MEDIUM), characters and placed objects are forced OFF so the only shadows
## in the scene are the structural wall/geometry ones; when ON (HIGH/ULTRA)
## they cast again. Layer 1 (structural) is therefore walls/corners ONLY —
## never the player or objects; those are Layer 2's domain. Resolution scales
## via `shadow_quality` (positional shadow atlas) at every tier. Gating is
## owned where the data lives: characters in AdventurerModelController
## (deterministic, can never render the shadow silhouette), placed objects in
## GraphicsSettings.register_dynamic_shadow_root(). Registration is event-
## driven at spawn time (BuildModeController and PickupableItem), so changing
## quality only revisits known caster roots. This replaces the old periodic
## whole-world walk, which produced a visible hitch in expanded bunkers.
## The instance-id dictionary makes registration O(1); WeakRef values keep the
## registry from owning/freezing deconstructed objects.
const DYNAMIC_SHADOW_META: StringName = &"_dynamic_shadow_authored_cast"
var _dynamic_shadow_roots: Dictionary = {}   ## instance_id -> WeakRef

## ── Positional shadow atlas layout (Sep 2026 lighting review) ───────────────
## Godot sizes each light's atlas slot from its on-screen coverage and moves a
## light to a different-sized slot when that changes — every move is a full
## shadow re-render (six faces for a cube omni) and a visible resolution pop
## while walking. Three equal quadrants remove that churn for every light that
## fits in them; the fourth, finer quadrant only catches overflow in very
## large bases so no light ever loses its structural shadow. Slot size is
## atlas/8 (e.g. 4096 -> 512 px); 48 + 64 = 112 slots (an omni uses two).
const SHADOW_ATLAS_QUADRANTS: Array[int] = [
	Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16,
	Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_64,
]

## ── Dynamic-shadow budget (Sep 2026 lighting review) ────────────────────────
## Godot caches every positional shadow map and re-renders it only when a
## shadow caster inside the light's range moves. Static structure/furniture
## is therefore almost free after the first frame, but an animated character
## inside a lamp's range forces that lamp's full re-render EVERY frame. With
## Dynamic Shadows on, only the lights nearest the player keep character
## casters in their shadow_caster_mask; the rest drop just the character
## layers and stay cached. Structural shadows are never affected.
## Character render layers: 12 = the player (Player.PLAYER_SELF_LIGHT_LAYER_BIT,
## kept as a literal to avoid an autoload -> Player class dependency) and
## 13 = NPCs (set by AdventurerModelController).
const PLAYER_SHADOW_LAYER_BIT: int = 1 << 11
const NPC_SHADOW_LAYER_BIT: int = 1 << 12
const CHARACTER_SHADOW_LAYERS: int = PLAYER_SHADOW_LAYER_BIT | NPC_SHADOW_LAYER_BIT
const ALL_SHADOW_CASTERS: int = 0xFFFFFFFF
const SHADOW_BUDGET_INTERVAL: float = 0.25
## A light already holding a budget slot ranks this many metres closer, so
## two lamps at similar distance don't swap back and forth (each swap costs a
## re-render of both).
const SHADOW_BUDGET_HYSTERESIS_M: float = 1.5
var _shadow_lights: Dictionary = {}   ## instance_id -> WeakRef(Light3D)
var _shadow_budget_timer: float = 0.0

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
		"anisotropic_filtering": 2, "shadow_quality": 2048, "render_scale": 1.0,
		"shadow_casting_enabled": false,
	},
	Preset.MEDIUM: {
		"sdfgi_enabled": false, "ssao_enabled": true, "ssil_enabled": false,
		"volumetric_fog_enabled": false, "flashlight_volumetrics": false,
		"glow_enabled": true, "dof_enabled": false, "msaa": Viewport.MSAA_2X,
		"screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, "use_taa": false,
		"anisotropic_filtering": 4, "shadow_quality": 4096, "render_scale": 1.0,
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
		"anisotropic_filtering": 16, "shadow_quality": 8192, "render_scale": 1.0,
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
## node enters the tree, and the dynamic-shadow gate when the world itself
## does. Idempotent — safe to fire on every world load.
func _on_node_added(node: Node) -> void:
	if node.is_in_group("world_environment"):
		_apply_to_environment()
	if node.is_in_group("main_world"):
		_apply_dynamic_shadow_casting()


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
func apply_preset(preset: int) -> bool:
	if preset == Preset.CUSTOM or not PRESETS.has(preset):
		return false
	var vals: Dictionary = PRESETS[preset]
	if _reject_memory_increase(vals):
		return false
	for key: String in vals:
		set(key, vals[key])
	current_preset = preset
	_apply_all()
	_save()
	return true


## Generic single-setting override, used by GraphicsSettingsPanel's individual
## checkboxes. Flips current_preset to CUSTOM (except for camera_fov, the
## only remaining field that doesn't participate in preset matching at all
## — shadow_casting_enabled joined the normal preset-driven fields Aug 2026).
func set_setting(field: String, value: Variant) -> void:
	if set_setting_live(field, value):
		_save()


## Same as set_setting() but does NOT persist to disk — mutates + applies
## live only. For UI controls that fire continuously while being dragged
## (e.g. Slider.value_changed can fire ~40 times over one drag); pair with a
## call to save_now() once the interaction completes (e.g. Slider's
## drag_ended signal) so the settings file is only written once per
## interaction instead of on every intermediate tick.
func set_setting_live(field: String, value: Variant) -> bool:
	if _reject_memory_increase({field: value}):
		return false
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
			return false
	if field != "camera_fov" and field != "dynamic_resolution_enabled":
		current_preset = Preset.CUSTOM
	_apply_all()
	return true


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
	if not is_rendering_driver_supported(value):
		push_warning("[GraphicsSettings] Unknown rendering driver: %s" % value)
		return
	rendering_driver = value
	_save()


func _apply_all() -> void:
	_apply_to_environment()
	_apply_to_viewport()
	_apply_to_display()
	_reapply_registered_dynamic_shadow_roots()
	_update_shadow_budget()
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
	_shadow_budget_timer -= delta
	if _shadow_budget_timer <= 0.0:
		_shadow_budget_timer = SHADOW_BUDGET_INTERVAL
		_update_shadow_budget()
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

## Re-applies the dynamic (character/object) shadow gate. Characters remain
## self-gating in AdventurerModelController; object roots register here once
## when spawned. The BuildModeController call is a load/startup safety net for
## objects restored before they had a chance to register themselves.
func _apply_dynamic_shadow_casting() -> void:
	_reapply_registered_dynamic_shadow_roots()
	var bc: Node = _find_build_controller()
	if bc != null and bc.has_method("_apply_dynamic_shadow_gate"):
		bc.call("_apply_dynamic_shadow_gate")

func _reapply_registered_dynamic_shadow_roots() -> void:
	for root_id: int in _dynamic_shadow_roots.keys():
		var root_ref: WeakRef = _dynamic_shadow_roots[root_id] as WeakRef
		var root: Node = root_ref.get_ref() as Node
		if root == null or not is_instance_valid(root):
			_dynamic_shadow_roots.erase(root_id)
			continue
		_apply_dynamic_shadow_to_root(root)

## Registers a non-structural object as one dynamic shadow unit and applies the
## current setting immediately. Safe to call repeatedly (pickup/drop/reparent):
## roots are de-duplicated and each mesh remembers its authored cast mode in
## metadata, so authored-OFF glass/fixture surfaces remain OFF when enabled.
func register_dynamic_shadow_root(root: Node) -> void:
	if root == null or not is_instance_valid(root):
		return
	_dynamic_shadow_roots[root.get_instance_id()] = weakref(root)
	_apply_dynamic_shadow_to_root(root)

func _apply_dynamic_shadow_to_root(root: Node) -> void:
	_apply_dynamic_shadow_to_branch(root, shadow_casting_enabled)

func _apply_dynamic_shadow_to_branch(node: Node, enabled: bool) -> void:
	## GeometryInstance3D includes ordinary meshes and MultiMesh renderers.
	## Treating both alike keeps instanced shelf geometry in the same dynamic
	## shadow tier as its former individual MeshInstance3D children.
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		if not geometry.has_meta(DYNAMIC_SHADOW_META):
			geometry.set_meta(DYNAMIC_SHADOW_META, int(geometry.cast_shadow))
		geometry.cast_shadow = (
			int(geometry.get_meta(DYNAMIC_SHADOW_META))
			if enabled
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for child: Node in node.get_children():
		_apply_dynamic_shadow_to_branch(child, enabled)

func _soft_shadow_filter_for_quality() -> RenderingServer.ShadowQuality:
	if shadow_quality >= 8192:
		return RenderingServer.SHADOW_QUALITY_SOFT_HIGH
	if shadow_quality >= 4096:
		return RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM
	return RenderingServer.SHADOW_QUALITY_SOFT_LOW

## How many lights may keep character casters in their shadow maps.
func dynamic_shadow_light_budget() -> int:
	if not shadow_casting_enabled:
		return 0
	return 8 if shadow_quality >= 8192 else 5

## Registers a world light (WallLight/GrowLight) with the dynamic-shadow
## budget. The player-held flashlight is deliberately not registered: it is
## always beside the player and always keeps character casters.
func register_shadow_light(light: Light3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	_shadow_lights[light.get_instance_id()] = weakref(light)
	## Start without characters; the next budget pass (<= 0.25 s) promotes it.
	_set_shadow_caster_mask(light, ALL_SHADOW_CASTERS & ~CHARACTER_SHADOW_LAYERS)

func _update_shadow_budget() -> void:
	if _shadow_lights.is_empty():
		return
	var budget: int = dynamic_shadow_light_budget()
	var focus: Node3D = null
	if budget > 0:
		focus = get_tree().get_first_node_in_group("Player") as Node3D
	var ranked: Array = []   ## [score, light]
	for id: int in _shadow_lights.keys():
		var light: Light3D = (_shadow_lights[id] as WeakRef).get_ref() as Light3D
		if light == null or not is_instance_valid(light):
			_shadow_lights.erase(id)
			continue
		if budget == 0 or focus == null or not light.is_visible_in_tree():
			_set_shadow_caster_mask(light, ALL_SHADOW_CASTERS & ~CHARACTER_SHADOW_LAYERS)
			continue
		var score: float = light.global_position.distance_to(focus.global_position)
		if light.shadow_caster_mask == ALL_SHADOW_CASTERS:
			score -= SHADOW_BUDGET_HYSTERESIS_M
		ranked.append([score, light])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i: int in ranked.size():
		_set_shadow_caster_mask(ranked[i][1] as Light3D,
			ALL_SHADOW_CASTERS if i < budget else ALL_SHADOW_CASTERS & ~CHARACTER_SHADOW_LAYERS)

## Only writes on change — every write marks the light's shadow map dirty.
func _set_shadow_caster_mask(light: Light3D, mask: int) -> void:
	if light.shadow_caster_mask != mask:
		light.shadow_caster_mask = mask

func _find_build_controller() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var mw: Node = tree.get_first_node_in_group("main_world")
	if mw == null:
		return null
	return mw.get("_build_controller") as Node

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
	var vp: Viewport = get_viewport()
	vp.positional_shadow_atlas_size = shadow_quality
	vp.positional_shadow_atlas_quad_0 = SHADOW_ATLAS_QUADRANTS[0]
	vp.positional_shadow_atlas_quad_1 = SHADOW_ATLAS_QUADRANTS[1]
	vp.positional_shadow_atlas_quad_2 = SHADOW_ATLAS_QUADRANTS[2]
	vp.positional_shadow_atlas_quad_3 = SHADOW_ATLAS_QUADRANTS[3]
	## Shadow-edge filtering follows the same quality knob, so "Shadow
	## quality" really changes every shadow. The filter is the only shadow
	## cost paid every frame (cached maps aside), so the lower tiers keep
	## Godot's default. Very Low was rejected: visibly dithered contact lines.
	RenderingServer.positional_soft_shadow_filter_set_quality(_soft_shadow_filter_for_quality())
	## Directional shadows use a separate atlas. Keeping it in lockstep fixes
	## the old mismatch where the UI only changed local-light shadow quality.
	## Directional atlases are owned by RenderingServer rather than Viewport.
	## The second argument keeps the standard 24-bit depth format.
	RenderingServer.directional_shadow_atlas_set_size(shadow_quality, false)
	for node: Node in get_tree().get_nodes_in_group("quality_directional_light"):
		var light := node as DirectionalLight3D
		if light == null:
			continue
		if shadow_quality <= 1024:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		elif shadow_quality <= 2048:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		else:
			light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


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
	# A settings file copied from Windows must not select Direct3D on Linux.
	if not is_rendering_driver_supported(rendering_driver):
		rendering_driver = "vulkan"
	## Snapshot AFTER the load above — see session_start_rendering_driver's
	## declaration comment for why this must be captured here, once, and
	## never reassigned afterward.
	session_start_rendering_driver = rendering_driver
