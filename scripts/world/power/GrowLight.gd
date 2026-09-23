extends StaticBody3D
class_name GrowLight
## GrowLight.gd
## ─────────────────────────────────────────────────────────────────────────────
## Farming System plan §3.2/§4. Lives in scripts/world/power/ (NOT
## scripts/world/farming/) — structurally this is a PowerManager consumer
## device exactly like WallLight/HeavyConsumerTest, not a farming-specific
## object. One script, two tiers via `tier` export (mirrors
## PurifierFilterItem's "one script, state param" convention rather than two
## near-duplicate classes).
##
## Registration/interaction shape copied from HeavyConsumerTest.gd (a plain
## StaticBody3D consumer that opens PowerPriorityUI directly on E — no
## PowerPriorityInteractable proxy needed, that proxy only exists for
## Node3D-without-a-body hosts like WallLight).
##
## Grow lights are free-standing consumers and require an explicit player-drawn
## wire connection. Invisible proximity feeds are reserved for wall-mounted
## devices whose connection point is above the floor-level wire run.
##
## Growth contract read by FarmPlant.gd (plan §4, "pure XZ position match" —
## no parent/child relationship or registration handshake with any tray):
##   get_active_growth_speed() -> float   0.0 unpowered/shed, 0.5 normal, 1.0 pro
##
## Polish Plan Group 2 item 5 — real OmniLight3D child (WallLight's own
## pattern), budget-capped low energy/range from the start since a dense
## farm room can hold far more of these than a base has wall lights. See
## OMNI_* consts below. Item 6 (ghost-preview footprint decal) lives in
## GhostPreview.gd, not here — it only needs this class's placement Y, no
## GrowLight-side code.

# ─── Debug ────────────────────────────────────────────────────────────────────
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Tier config ──────────────────────────────────────────────────────────────
@export var tier: String = "normal"   ## "normal" or "pro"

const TIER_WATTS: Dictionary = {
	"normal": 75.0,
	"pro":    100.0,
}
const TIER_GROWTH_SPEED: Dictionary = {
	"normal": 0.5,
	"pro":    1.0,
}
const TIER_TYPE_TAG: Dictionary = {
	"normal": "grow_light_normal",
	"pro":    "grow_light_pro",
}

# ─── Model (hand-made Tinkercad OBJ swap, Sep 2026) ─────────────────────────
## Hand-made models (assets/models/grow_light/) replace the old procedural
## fixture. Per tier there are TWO OBJs: the *Unpowered* model is the full
## physical fixture (dark cover plate + translucent white tubes + two tall
## ceiling-mount support panels); the *Powered* model is ONLY the 3 glowing
## tubes, positioned at byte-identical coordinates to the tubes inside the
## Unpowered fixture so the glow overlays them exactly.
##
## MODEL_SCALE maps the fixture's 20-unit plate width to the 0.70m footprint
## used by the collision box / ghost box below (20 * 0.035 = 0.70). The
## model's 2-unit tube thickness lands on the old TUBE_RADIUS 0.035 exactly
## (2 * 0.035 / 2 = 0.035), confirming this is the intended scale.
const MODEL_PATHS_UNPOWERED: Dictionary = {
	"normal": "res://assets/models/grow_light/regular_unpowered/tinker.obj",
	"pro":    "res://assets/models/grow_light/pro_unpowered/tinker.obj",
}
const MODEL_PATHS_POWERED: Dictionary = {
	"normal": "res://assets/models/grow_light/regular_powered/tinker.obj",
	"pro":    "res://assets/models/grow_light/pro_powered/tinker.obj",
}
const MODEL_SCALE: float = 0.035

## Powered tube glow color — matches each tier's Powered MTL albedo exactly
## (regular: warm white; pro: cool cyan), so the lit state reads as the
## user's intended lamp color rather than forcing both tiers to white.
const TUBE_GLOW_COLOR: Dictionary = {
	"normal": Color(0.9725, 0.9020, 0.7176, 1.0),
	"pro":    Color(0.5216, 0.8039, 0.9020, 1.0),
}

## Shed (overloaded grid) state — reused VERBATIM from WallLight's own
## SHED_COLOR/SHED_ENERGY so a shed grow light reads consistently with every
## other shed device in the game.
const SHED_COLOR:  Color = Color(1.0, 0.45, 0.0, 1.0)
const SHED_ENERGY: float = 0.15

const TUBE_ENERGY_ON: float = 2.0

## Polish Plan Group 2 item 5 — real OmniLight3D illumination, budget-capped
## from the start (not a follow-up pass). Deliberately NOT copying
## WallLight's LIGHT_ENERGY(2.0)/LIGHT_RANGE(10.0) — a dense farm room can
## plausibly hold far more grow lights in one space than a base has wall
## lights, so both values start well below WallLight's own tuned figures.
## Warm-white (matches TUBE_COLOR_ON) rather than WallLight's warm amber —
## a grow light should read as "bright grow-lamp white," not "cozy room
## light." Fog contribution reuses WallLight's same low-contribution fix
## (avoid ambient haze buildup with many lights in one room).
const SPOT_LIGHT_ENERGY: float = 1.65   ## 1.1 × 1.5 (raised Sep 2026 at Brannon's request)
const SPOT_LIGHT_RANGE:  float = 3.0
const SPOT_VOLUMETRIC_FOG_ENERGY: float = 0.15
## Cheap perf guard for large farm rooms (plan §5's "if FPS dips, cull the
## light node itself beyond some camera distance, keep the emissive
## mesh at all distances" — built proactively via Godot's own native
## distance-fade rather than a custom per-frame camera-distance check,
## since it costs nothing to include now. Begin distance is generous (well
## beyond SPOT_LIGHT_RANGE) so it never visibly pops during normal play —
## it only caps the worst case of dozens of lights rendering at once.
## (Renamed from OMNI_* Aug 2026 when this fixture's light was converted
## from OmniLight3D to a downward-facing SpotLight3D — see
## _build_spot_light() below.)
const SPOT_DISTANCE_FADE_BEGIN:  float = 18.0
const SPOT_DISTANCE_FADE_LENGTH: float = 4.0

## Polish Plan Group 0 item 20 — 4 thin corner support wires running from the
## cover plate up to the 3.0m ceiling directly above. WALL_HEIGHT_M mirrors
## BuildModeController.WALL_HEIGHT_M (both cite the same tile_set.tscn 3.0m
## figure — two independent constants, same value, same reasoning as
## WaterPipeDrawMode.WATER_CEILING_Y already documents for that pair).
## NOTE: these constants are historical. The hand-made OBJ swap (Sep 2026)
## bakes the fixture's own ceiling-mount support panels into the Unpowered
## model, so _build_support_wires() was removed — the model carries its
## supports. WALL_HEIGHT_M is retained only because GROW_LIGHT_PLACEMENT_Y
## derivation lives in BuildModeController (this file's copy is now unused).
const WALL_HEIGHT_M: float = 3.0

# ─── Power grid ───────────────────────────────────────────────────────────────
var power_priority: int = 3   ## Both tiers default to priority 3 (plan §3.1)

var _pm_node_key: String = ""
var _is_powered:  bool   = false
var _is_shed:     bool   = false

## Shadow LOD (Aug 2026, see GraphicsSettings.SHADOW_LOD_* header comment and
## WallLight.gd's identical mechanism) — this fixture's own hysteresis
## state; starts true so a freshly placed/loaded light isn't wrongly
## shadow-culled before the first scan.
var _shadow_lod_near: bool = true

## Full-fidelity preview mode (Jul 2026) — set TRUE by BuildModeHUD's
## construct-tab preview code BEFORE add_child(), so this instance builds
## its real visual exactly like a placed object but skips every
## side-effecting call (group membership, PowerManager/WaterManager
## registration). MUST be set before add_child() — _ready() fires
## synchronously during add_child() and reads this immediately. See
## docs/systems/build/README.md "Full-fidelity previews" for the full
## convention and why this exists (a previous version instantiated these
## same scripts with no guard and registered 3 real running generators
## into the live PowerManager the instant Build Mode opened).
var _is_preview_only: bool = false

## Farming Polish Plan Group 6 item 14 (perf) — spatial-hash bucket registry
## replacing FarmPlant's old per-hour, per-plant O(n) scan over every
## "grow_light" group member. Grow lights are placed on the 0.25m build grid
## (BuildModeController.grid_size), NOT a whole-meter grid, so a naive
## roundi()-per-axis key can put two positions within the old
## LIGHT_MATCH_RADIUS tolerance into different buckets. Fix: bucket size is
## deliberately >= LIGHT_MATCH_RADIUS, each bucket holds an Array (never a
## single ref, since more than one light could in theory land in one
## bucket), and the lookup scans the 3x3 neighborhood of buckets around the
## query position, then applies the SAME exact distance check the old O(n)
## scan used. This keeps behavior byte-for-byte identical to the original
## while cutting the search space from "every grow light in the game" to "a
## handful of nearby candidates". Registers on placement (_ready),
## unregisters on deconstruct (_exit_tree) — the two lifecycle hooks the
## plan calls "two signals". Static so every GrowLight instance shares one
## registry; also used by item 15's future double-stack guard (Group 7, not
## built yet — this shape is chosen to serve both consumers from the start,
## per the plan's own note).
const CELL_BUCKET_SIZE: float = 0.45   ## >= LIGHT_MATCH_RADIUS (0.40)
const LIGHT_MATCH_RADIUS: float = 0.40   ## Increased from 0.25 to 0.40 for more forgiving horizontal placement

static var _bucket_registry: Dictionary = {}   ## String bucket_key -> Array[GrowLight]
var _registered_bucket_key: String = ""

## Buckets a world XZ position into a bucket key. Y is ignored — same as the
## old distance check, which only ever compared X/Z (grow lights sit at a
## fixed height on walls, plants on the floor).
static func bucket_key_for(pos: Vector3) -> String:
	return "%d_%d" % [floori(pos.x / CELL_BUCKET_SIZE), floori(pos.z / CELL_BUCKET_SIZE)]

## O(a few candidates) replacement for the old
## get_tree().get_nodes_in_group("grow_light") scan. Scans the 3x3
## neighborhood of buckets around `pos` and returns the best (highest)
## get_active_growth_speed() among every registered light within
## LIGHT_MATCH_RADIUS of `pos` — identical semantics to the original O(n)
## scan's maxf() best-speed pick. Returns 0.0 if nothing is in range.
static func get_best_growth_speed_near(pos: Vector3) -> float:
	var best: float = 0.0
	var cx: int = floori(pos.x / CELL_BUCKET_SIZE)
	var cz: int = floori(pos.z / CELL_BUCKET_SIZE)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key: String = "%d_%d" % [cx + dx, cz + dz]
			var bucket: Array = _bucket_registry.get(key, []) as Array
			if bucket.is_empty():
				continue
			# Iterate backwards so erasing stale/invalid entries in-place is safe.
			for i in range(bucket.size() - 1, -1, -1):
				var light: GrowLight = bucket[i] as GrowLight
				if light == null or not is_instance_valid(light):
					bucket.remove_at(i)
					continue
				var light_xz: Vector2 = Vector2(light.global_position.x, light.global_position.z)
				var pos_xz: Vector2 = Vector2(pos.x, pos.z)
				if light_xz.distance_to(pos_xz) <= LIGHT_MATCH_RADIUS:
					best = maxf(best, light.get_active_growth_speed())
	return best

## Fixture visuals (Sep 2026 hand-made OBJ swap) — the Unpowered model is the
## full physical fixture (plate + tubes + support panels), always shown. The
## Powered model is the glowing-tube overlay, shown only when lit/shed and
## driven by _refresh_glow(). _base_mi/_glow_mi are the two MeshInstance3D.
var _base_mi: MeshInstance3D = null
var _glow_mi: MeshInstance3D = null
var _glow_mat: StandardMaterial3D = null

## Polish Plan Group 2 item 5 — the real light (WallLight pattern), later
## converted from OmniLight3D to a downward-facing SpotLight3D (Aug 2026 —
## see _build_spot_light() below for why).
var _spot: SpotLight3D = null

## Lazily-created shared priority panel (PowerPriorityUI). Reused across opens.
var _prio_ui: CanvasLayer = null

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	tier = tier if TIER_WATTS.has(tier) else "normal"
	collision_layer = 5
	collision_mask  = 0
	## Fixture mesh must build for EVERY instance, including previews —
	## the Construct-menu spinning preview and the placement ghost are
	## _is_preview_only instances and are invisible without it. The
	## preview guard goes AFTER this line, never before.
	_build_fixture()
	if _is_preview_only:
		return
	add_to_group("interactable")
	add_to_group("grow_light")
	add_to_group("shadow_lod_lights")   ## Aug 2026 — distance-gated shadows, see GraphicsSettings.gd
	## A7 safety net — guarantee fixture starts off before any PowerManager
	## solve can potentially set it powered.
	set_powered(false)
	## Bug fix (Jul 2026) — must be deferred, not called directly here.
	## add_child() fires _ready() synchronously BEFORE spawn_structure()'s
	## subsequent `global_position = pos` line runs, so a direct call here
	## registers the light's spatial bucket at (0,0,0) instead of its real
	## placed position — every grow light placed through the build menu was
	## silently un-findable by any plant, powered or not. Deferring this
	## (like _register_deferred below already does for power) waits until
	## after global_position has its real value.
	call_deferred("_register_bucket")
	call_deferred("_register_deferred")

## Registers into the static bucket registry (item 14) — global_position is
## already valid here, _ready() runs after the node enters the tree.
func _register_bucket() -> void:
	_registered_bucket_key = GrowLight.bucket_key_for(global_position)
	var bucket: Array = GrowLight._bucket_registry.get(_registered_bucket_key, []) as Array
	bucket.append(self)
	GrowLight._bucket_registry[_registered_bucket_key] = bucket

func _exit_tree() -> void:
	if not _registered_bucket_key.is_empty():
		var bucket: Array = GrowLight._bucket_registry.get(_registered_bucket_key, []) as Array
		bucket.erase(self)
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if not _pm_node_key.is_empty():
		pm.unregister_wire_node(_pm_node_key)
	pm.unregister_consumer(str(get_instance_id()))

# ─── PowerManager registration (manual elevated connector) ──────────────────
func _register_deferred() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("GrowLight: PowerManager not found — will never receive power.")
		return
	pm.begin_bulk()
	pm.register_consumer(
		str(get_instance_id()),
		TIER_WATTS.get(tier, 75.0),
		self,
		TIER_TYPE_TAG.get(tier, "grow_light_normal"),
		power_priority,
		true)
	_pm_node_key = pm.register_wire_node(
		global_position,
		"consumer",
		str(get_instance_id()),
		true)
	pm.end_bulk()

# ─── PowerManager callbacks ───────────────────────────────────────────────────
func set_powered(on: bool) -> void:
	_is_powered = on
	if on:
		_is_shed = false
	_refresh_glow()

func set_shed(shed_on: bool) -> void:
	_is_shed = shed_on
	if shed_on:
		_is_powered = false
	_refresh_glow()

## Drives the Powered glow-tube overlay (and the spot light) from the grid
## state — same 3-state shape as the old procedural _refresh_tubes(), but
## now the lit tube layer is the hand-made Powered OBJ instead of material
## emission on procedural cylinders. The base (Unpowered) fixture is always
## shown unchanged; only the overlay's material + visibility toggle.
func _refresh_glow() -> void:
	if _glow_mat == null:
		return
	var col: Color
	var energy: float
	if _is_powered:
		col    = TUBE_GLOW_COLOR.get(tier, TUBE_GLOW_COLOR["normal"])
		energy = TUBE_ENERGY_ON
	elif _is_shed:
		col    = SHED_COLOR
		energy = SHED_ENERGY
	else:
		col    = TUBE_GLOW_COLOR.get(tier, TUBE_GLOW_COLOR["normal"])
		energy = 0.0
	_glow_mi.visible = energy > 0.0
	_glow_mat.emission = col
	_glow_mat.emission_energy_multiplier = energy
	_glow_mat.albedo_color = col if energy > 0.0 else Color(0.25, 0.25, 0.26, 1.0)

	## Polish Plan Group 2 item 5 — real light mirrors the tube state
	## exactly: full white when powered, faint orange when shed, dark/off
	## otherwise (same 3-state shape as WallLight.set_powered()/set_shed()).
	if _spot == null:
		return
	if _is_powered:
		_spot.light_color  = TUBE_GLOW_COLOR.get(tier, TUBE_GLOW_COLOR["normal"])
		_spot.light_energy = SPOT_LIGHT_ENERGY
		_spot.visible      = true
	elif _is_shed:
		_spot.light_color  = SHED_COLOR
		_spot.light_energy = SHED_ENERGY
		_spot.visible      = true
	else:
		_spot.visible = false

## Growth contract read by FarmPlant.gd — see file header.
func get_active_growth_speed() -> float:
	if not _is_powered:
		return 0.0
	return TIER_GROWTH_SPEED.get(tier, 0.5)

# ─── Priority interaction (direct — StaticBody3D host, no proxy needed) ──────
func on_interact() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = true

	if _prio_ui == null or not is_instance_valid(_prio_ui):
		var ui_script: GDScript = load("res://scripts/ui/power/PowerPriorityUI.gd")
		if ui_script == null:
			push_warning("GrowLight: PowerPriorityUI.gd not found")
			return
		_prio_ui = CanvasLayer.new()
		_prio_ui.set_script(ui_script)
		_prio_ui.name = "PowerPriorityUI"
		get_tree().get_root().add_child(_prio_ui)
		if _prio_ui.has_signal("closed"):
			_prio_ui.closed.connect(_on_prio_closed)
		if _prio_ui.has_signal("priority_changed"):
			_prio_ui.priority_changed.connect(_on_prio_changed)

	var display_name: String = "Grow Light" if tier == "normal" else "Grow Light (Pro)"
	if _prio_ui.has_method("open"):
		_prio_ui.call("open", str(get_instance_id()), display_name, false, global_position, self)

func get_interact_prompt() -> String:
	var label: String = "Grow Light" if tier == "normal" else "Grow Light (Pro)"
	return "[E] %s" % label

func _on_prio_closed() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = false

func _on_prio_changed(_id: String, value: int) -> void:
	power_priority = value

func _get_interaction_system() -> Node:
	var root: Node = get_tree().get_root()
	for child: Node in root.get_children():
		if child is Node3D:
			for sub: Node in (child as Node3D).get_children():
				if sub is CharacterBody3D:
					for s2: Node in sub.get_children():
						if s2.get_script() != null and str(s2.get_script().resource_path).contains("InteractionSystem"):
							return s2
	return null

# ─── Model (hand-made OBJ swap — replaces the procedural fixture) ───────────
static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.70, 0.10, 0.70)
	return box

func _build_fixture() -> void:
	_load_fixture_models()
	## No collision beyond the parent StaticBody3D itself needing a shape for
	## interaction proximity/raycast — add a slim invisible collider matching
	## the 1×1 footprint used by _tile_half_extents().
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.70, 0.20, 0.70)
	shape.shape = box
	add_child(shape)

	_build_spot_light()

## Loads the per-tier Unpowered (full fixture) + Powered (glow-tube overlay)
## OBJ models and adds them as sibling MeshInstance3D children. Both use the
## identical local transform — the Powered tubes were authored at the same
## coordinates as the tubes baked into the Unpowered fixture, so one scale +
## rotation + position places both. The glow material is a fresh
## StandardMaterial3D (emission-driven), applied via material_override so the
## OBJ's own MTL colors don't fight the glow tint.
func _load_fixture_models() -> void:
	var base_path: String = MODEL_PATHS_UNPOWERED.get(tier, MODEL_PATHS_UNPOWERED["normal"])
	var glow_path: String = MODEL_PATHS_POWERED.get(tier, MODEL_PATHS_POWERED["normal"])

	var base_mesh: ArrayMesh = load(base_path) as ArrayMesh
	var glow_mesh: ArrayMesh = load(glow_path) as ArrayMesh
	if base_mesh == null:
		push_warning("GrowLight: base model missing at %s" % base_path)
		return
	if glow_mesh == null:
		push_warning("GrowLight: glow model missing at %s" % glow_path)

	## Angle-based normal rebuild (Sep 2026) — the OBJ carries no normals, so
	## Godot's importer smooth-averages them and smears the boxy fixture's flat
	## faces (the visible "needles to center" shading on the top plate). 45°
	## auto-smooth splits the hard box edges flat while keeping the rounded
	## tube surfaces smooth. See BuildMaterials.build_auto_smooth_mesh().
	base_mesh = BuildMaterials.build_auto_smooth_mesh(base_mesh)
	glow_mesh = BuildMaterials.build_auto_smooth_mesh(glow_mesh)

	_base_mi = MeshInstance3D.new()
	_base_mi.mesh = base_mesh
	_base_mi.name = "Fixture"
	_apply_mood_override_to_base(_base_mi)
	add_child(_base_mi)

	_glow_mi = MeshInstance3D.new()
	_glow_mi.mesh = glow_mesh
	_glow_mi.name = "GlowTubes"
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.emission_enabled = true
	_glow_mat.albedo_color = Color(0.25, 0.25, 0.26, 1.0)
	_glow_mi.material_override = _glow_mat
	add_child(_glow_mi)

	## Tinkercad OBJ convention — height runs along OBJ Z; rotate -90° about X
	## so the fixture's "up" (support panels toward the ceiling) maps to Godot
	## +Y. Matches every other hand-made OBJ load site (Splint/FarmProduce/Bed).
	var t := Transform3D()
	t = t.rotated(Vector3.RIGHT, -PI / 2.0)
	t = t.scaled(Vector3.ONE * MODEL_SCALE)
	_base_mi.transform = t
	_glow_mi.transform = t

## Dims/desaturates/mattens the fixture's dark-grey plate + light-grey
## support panels so they read in-theme with the dark bunker (same reason
## every other hand-made OBJ swap applies BuildMaterials mood overrides).
## The translucent white tube surfaces are left untouched — they are the
## "unlit tube" look and are tinted by the glow overlay instead.
func _apply_mood_override_to_base(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null:
		return
	for s: int in mi.mesh.get_surface_count():
		var base: Material = mi.mesh.surface_get_material(s)
		var is_tube: bool = false
		if base is StandardMaterial3D:
			is_tube = (base as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if is_tube:
			continue
		BuildMaterials.apply_surface_override(mi, s, 0.6, 0.12, 0.8, 0.0)

## Aug 2026 — converted from OmniLight3D to a downward-facing SpotLight3D
## (was Polish Plan Group 2 item 5's OmniLight3D). Two independent reasons:
## (1) physical correctness — a grow light fixture only ever shines down
## onto the tray below it; an all-directions Omni was lighting the ceiling/
## walls/sideways too, which never made sense for this fixture. (2) cost —
## SpotLight3D shadows use a single shadow map vs. Omni's 6-face cubemap,
## which matters concretely here because SPOT_LIGHT_ENERGY/RANGE's own
## doc-comments above already flag that a dense farm room can hold far more
## of these than a base has wall lights.
##
## rotation_degrees.x = -90 points the default -Z forward direction
## straight down — same sign convention as Flashlight.gd's BEAM_PITCH_DEG
## (negative X pitches down; verified against that file before writing
## this). spot_angle = 35.0 is a first-pass eyeballed value sized to cover
## roughly a 1-2 tile tray footprint from this fixture's mounting height
## near the ceiling (see GROW_LIGHT_PLACEMENT_Y above for the
## mount height) — tune in the Inspector if it reads too narrow/wide once
## seen over a real placed tray in-editor; this wasn't measured against
## FarmingTray.gd's actual footprint dimensions.
##
## Sits at fixture centre (same as the 3 tubes it's meant to represent).
## Starts dark/invisible — only turns on via _refresh_glow() once
## PowerManager calls set_powered().
func _build_spot_light() -> void:
	var spot: SpotLight3D = SpotLight3D.new()
	spot.light_color                 = TUBE_GLOW_COLOR.get(tier, TUBE_GLOW_COLOR["normal"])
	spot.light_energy                = SPOT_LIGHT_ENERGY
	spot.spot_range                  = SPOT_LIGHT_RANGE
	spot.spot_angle                  = 35.0
	spot.spot_angle_attenuation      = 0.6
	spot.light_indirect_energy       = 1.0
	spot.light_volumetric_fog_energy = SPOT_VOLUMETRIC_FOG_ENERGY
	spot.distance_fade_enabled       = true
	spot.distance_fade_begin         = SPOT_DISTANCE_FADE_BEGIN
	spot.distance_fade_length        = SPOT_DISTANCE_FADE_LENGTH
	spot.position                    = Vector3.ZERO
	spot.rotation_degrees            = Vector3(-90.0, 0.0, 0.0)
	## Aug 2026 — this fixture briefly excluded characters from its
	## light_cull_mask (Aggregated Character Shadows plan), reverted (see
	## docs/systems/graphics/README.md "Aggregated character shadows" for
	## the postmortem). Back to default cull mask — lights and shadows the
	## player/NPCs completely normally. get_shadow_weight() below is
	## retained as dead code — its only consumer was the fake-shadow decal
	## system, replaced by the stand-in system (see
	## docs/systems/graphics/README.md "Character shadow stand-in");
	## kept, not scheduled for removal.
	spot.visible                     = false
	add_child(spot)
	_spot = spot
	_apply_graphics_settings()
	GraphicsSettings.settings_changed.connect(_apply_graphics_settings)

## Applies GraphicsSettings.shadow_casting_enabled to this fixture's
## SpotLight3D. Called once at build time and again on every
## GraphicsSettings.settings_changed (preset switch or individual toggle) —
## same live-update pattern Flashlight.gd/WallLight.gd use.
func _apply_graphics_settings() -> void:
	if _spot == null:
		return
	## Global switch always wins outright: OFF forces this fixture dark
	## regardless of distance; ON re-arms distance gating rather than
	## forcing shadows on for a possibly-far fixture — the next
	## GraphicsSettings shadow-LOD scan corrects it down again if the
	## player isn't actually nearby. Mirrors WallLight.gd exactly.
	_spot.shadow_enabled = GraphicsSettings.shadow_casting_enabled and _shadow_lod_near


## Shadow LOD (Aug 2026) — called by GraphicsSettings' periodic scan.
## Mirrors WallLight.gd's identical method; see that file's comment for the
## hysteresis rationale.
func update_shadow_lod(player_pos: Vector3) -> void:
	if _spot == null:
		return
	var dist: float = global_position.distance_to(player_pos)
	if _shadow_lod_near and dist > GraphicsSettings.SHADOW_LOD_FAR_RADIUS:
		_shadow_lod_near = false
		_spot.shadow_enabled = false
	elif not _shadow_lod_near and dist < GraphicsSettings.SHADOW_LOD_NEAR_RADIUS:
		_shadow_lod_near = true
		_spot.shadow_enabled = GraphicsSettings.shadow_casting_enabled

## Aug 2026 — returns this fixture's current contribution weight for the
## removed fake-shadow decal system's aggregate shadow-direction
## calculation, or 0.0 if currently off/out of range. Dead code since that
## system was replaced by the stand-in approach (see
## docs/systems/graphics/README.md "Character shadow stand-in"); kept, not
## scheduled for removal. Same simple-falloff approach as WallLight.gd's
## version — only needs to rank/blend lights relative to each other, not
## match the GPU's real attenuation curve exactly.
func get_shadow_weight(from_pos: Vector3) -> float:
	if _spot == null or not _spot.visible:
		return 0.0
	var dist: float = global_position.distance_to(from_pos)
	if dist >= SPOT_LIGHT_RANGE:
		return 0.0
	var t: float = 1.0 - (dist / SPOT_LIGHT_RANGE)
	return SPOT_LIGHT_ENERGY * t * t
