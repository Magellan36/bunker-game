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
## Auto-connects to the nearest wire node within AUTO_CONNECT_RADIUS, same
## exact mechanism WallLight._auto_connect_to_nearby_wires() uses — a grow
## light placed near an existing wire run just works with no separate
## wire-drawing step.
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

# ─── Model geometry (§4.1) ────────────────────────────────────────────────────
const TUBE_LENGTH: float  = 0.62
const TUBE_RADIUS: float  = 0.035
const TUBE_SPACING: float = 0.22   ## gap between the 3 parallel tubes (Z axis)
const COVER_COLOR: Color  = Color(0.15, 0.15, 0.16, 1.0)

## Unshaded/emissive white tube material — matches the connectable-dot
## material's unshaded convention already used elsewhere in this codebase.
const TUBE_COLOR_ON:  Color = Color(1.0, 1.0, 0.98, 1.0)

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
const SPOT_LIGHT_ENERGY: float = 1.1
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
## WIRE_LENGTH is derived, not hand-typed: since GROW_LIGHT_PLACEMENT_Y is
## exactly 7/8 wall height, the remaining 1/8 (0.375m) is exactly the gap
## from this node's local origin up to the ceiling.
const WALL_HEIGHT_M: float = 3.0
const WIRE_LENGTH: float = WALL_HEIGHT_M * (1.0 / 8.0)
const WIRE_RADIUS: float = 0.02
const WIRE_COLOR: Color = Color(0.05, 0.05, 0.06, 1.0)   ## unlit dark grey/black

# ─── Power grid ───────────────────────────────────────────────────────────────
var power_priority: int = 3   ## Both tiers default to priority 3 (plan §3.1)

var _pm_node_key: String = ""
var _is_powered:  bool   = false
var _is_shed:     bool   = false

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

## Tube materials — one per tube so all 3 update together in set_powered()/set_shed().
var _tube_mats: Array[StandardMaterial3D] = []

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

# ─── PowerManager registration (mirrors WallLight's auto-connect exactly) ────
func _register_deferred() -> void:
	_register_with_power_manager()
	call_deferred("_auto_connect_deferred")

func _auto_connect_deferred() -> void:
	if _pm_node_key == "":
		return
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		_auto_connect_to_nearby_wires(pm)

func _register_with_power_manager() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("GrowLight: PowerManager not found — will never receive power.")
		return

	_pm_node_key = pm.register_wire_node(
		global_position,
		"consumer",
		str(get_instance_id()))

	pm.register_consumer(
		str(get_instance_id()),
		TIER_WATTS.get(tier, 75.0),
		self,
		TIER_TYPE_TAG.get(tier, "grow_light_normal"),
		power_priority,
		true)

	_auto_connect_to_nearby_wires(pm)

## Scans existing PM wire nodes and connects to the nearest one within
## AUTO_CONNECT_RADIUS — copied verbatim from WallLight._auto_connect_to_nearby_wires().
func _auto_connect_to_nearby_wires(pm: PowerManager) -> void:
	if _pm_node_key == "":
		return
	const AUTO_CONNECT_RADIUS: float = 0.75
	var my_pos: Vector3 = global_position

	var edge_endpoint_keys: Dictionary = {}
	var edges: Array[Dictionary] = pm.get_wire_edges()
	for ed: Dictionary in edges:
		var na: String = ed.get("node_a", "")
		var nb: String = ed.get("node_b", "")
		if not na.is_empty(): edge_endpoint_keys[na] = true
		if not nb.is_empty(): edge_endpoint_keys[nb] = true

	var best_key:  String = ""
	var best_dist: float  = AUTO_CONNECT_RADIUS + 0.001

	for pass_idx: int in range(2):
		for wn: Dictionary in pm.get_wire_nodes():
			var wn_key: String = wn.get("key", "")
			if wn_key == _pm_node_key:
				continue
			if wn.get("role", "joint") != "joint":
				continue
			if pass_idx == 0 and not edge_endpoint_keys.has(wn_key):
				continue
			var wn_pos: Vector3 = wn.get("pos", Vector3.ZERO)
			var dx: float = wn_pos.x - my_pos.x
			var dz: float = wn_pos.z - my_pos.z
			var dist: float = sqrt(dx * dx + dz * dz)
			if dist < best_dist:
				best_dist = dist
				best_key  = wn_key
		if best_key != "":
			break

	if best_key != "":
		_wdbg("[GROWLIGHT] auto-connect id=%d -> key=%s dist=%.3f" % [get_instance_id(), best_key, best_dist])
		var ac_eid: String = pm.register_wire_edge(_pm_node_key, best_key, null, true)
		pm.set_wire_edge_no_visual(ac_eid)

## Called by BuildModeController after a new wire node is placed (mirrors WallLight).
func notify_wire_placed(wn_key: String, wn_pos: Vector3) -> void:
	if _pm_node_key == "":
		return
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	const AUTO_CONNECT_RADIUS: float = 0.75
	var dx: float = wn_pos.x - global_position.x
	var dz: float = wn_pos.z - global_position.z
	if sqrt(dx * dx + dz * dz) <= AUTO_CONNECT_RADIUS:
		var nw_eid: String = pm.register_wire_edge(_pm_node_key, wn_key, null, true)
		pm.set_wire_edge_no_visual(nw_eid)

# ─── PowerManager callbacks ───────────────────────────────────────────────────
func set_powered(on: bool) -> void:
	_is_powered = on
	if on:
		_is_shed = false
	_refresh_tubes()

func set_shed(shed_on: bool) -> void:
	_is_shed = shed_on
	if shed_on:
		_is_powered = false
	_refresh_tubes()

func _refresh_tubes() -> void:
	var col: Color
	var energy: float
	if _is_powered:
		col    = TUBE_COLOR_ON
		energy = TUBE_ENERGY_ON
	elif _is_shed:
		col    = SHED_COLOR
		energy = SHED_ENERGY
	else:
		col    = SHED_COLOR
		energy = 0.0
	for mat: StandardMaterial3D in _tube_mats:
		mat.emission = col
		mat.emission_energy_multiplier = energy
		mat.albedo_color = col if energy > 0.0 else Color(0.25, 0.25, 0.26, 1.0)

	## Polish Plan Group 2 item 5 — real light mirrors the tube state
	## exactly: full white when powered, faint orange when shed, dark/off
	## otherwise (same 3-state shape as WallLight.set_powered()/set_shed()).
	if _spot == null:
		return
	if _is_powered:
		_spot.light_color  = TUBE_COLOR_ON
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
		_prio_ui.call("open", str(get_instance_id()), display_name, false)

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

# ─── Model (procedural — no GLB, matches GeneratorObject/WaterPurifier convention) ──
static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.70, 0.10, 0.70)
	return box

func _build_fixture() -> void:
	_tube_mats.clear()

	## 3 glowing tubes, lying on their sides (long axis horizontal along X),
	## equally spaced across the 1×1 footprint on the Z axis.
	for i: int in range(3):
		var tube_mi: MeshInstance3D = MeshInstance3D.new()
		var tube_mesh: CylinderMesh = CylinderMesh.new()
		tube_mesh.top_radius    = TUBE_RADIUS
		tube_mesh.bottom_radius = TUBE_RADIUS
		tube_mesh.height        = TUBE_LENGTH
		tube_mesh.radial_segments = 10
		tube_mi.mesh = tube_mesh
		## CylinderMesh's long axis is local Y by default — rotate 90° so it lies horizontal.
		tube_mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		tube_mi.position = Vector3(0.0, 0.0, (i - 1) * TUBE_SPACING)

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.albedo_color     = Color(0.25, 0.25, 0.26, 1.0)
		mat.emission         = SHED_COLOR
		mat.emission_energy_multiplier = 0.0
		tube_mi.set_surface_override_material(0, mat)
		add_child(tube_mi)
		_tube_mats.append(mat)

	## Dark grey cover — flat top plate + two thin side-wall panels dropping
	## down partway along the tubes' height, wrapping 2 of the 4 sides only
	## (leave the short ends open, matching a real shop-light reflector).
	var cover_mat: StandardMaterial3D = StandardMaterial3D.new()
	cover_mat.albedo_color = COVER_COLOR
	cover_mat.metallic     = 0.10
	cover_mat.roughness    = 0.80

	var top_mi:   MeshInstance3D = MeshInstance3D.new()
	var top_mesh: BoxMesh        = BoxMesh.new()
	top_mesh.size = Vector3(0.66, 0.03, 0.66)
	top_mi.mesh   = top_mesh
	top_mi.position = Vector3(0.0, TUBE_RADIUS + 0.05, 0.0)
	top_mi.set_surface_override_material(0, cover_mat)
	add_child(top_mi)

	for side: int in [-1, 1]:
		var side_mi:   MeshInstance3D = MeshInstance3D.new()
		var side_mesh: BoxMesh        = BoxMesh.new()
		side_mesh.size = Vector3(0.66, 0.10, 0.03)
		side_mi.mesh   = side_mesh
		side_mi.position = Vector3(0.0, 0.0, side * 0.33)
		side_mi.set_surface_override_material(0, cover_mat)
		add_child(side_mi)

	## No collision beyond the parent StaticBody3D itself needing a shape for
	## interaction proximity/raycast — add a slim invisible collider matching
	## the 1×1 footprint used by _tile_half_extents().
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.70, 0.20, 0.70)
	shape.shape = box
	add_child(shape)

	_build_support_wires()
	_build_spot_light()

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
## near the ceiling (see WIRE_LENGTH/GROW_LIGHT_PLACEMENT_Y above for the
## mount height) — tune in the Inspector if it reads too narrow/wide once
## seen over a real placed tray in-editor; this wasn't measured against
## FarmingTray.gd's actual footprint dimensions.
##
## Sits at fixture centre (same as the 3 tubes it's meant to represent).
## Starts dark/invisible — only turns on via _refresh_tubes() once
## PowerManager calls set_powered().
func _build_spot_light() -> void:
	var spot: SpotLight3D = SpotLight3D.new()
	spot.light_color                 = TUBE_COLOR_ON
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
	_spot.shadow_enabled = GraphicsSettings.shadow_casting_enabled

## 4 thin corner support wires (Polish Plan Group 0 item 20) — one per
## fixture footprint corner (matches the cover plate's 0.66×0.66 footprint,
## corner inset mirrors FarmingTray's own leg-corner convention), running
## straight up from this node's local origin to the ceiling above.
func _build_support_wires() -> void:
	var wire_mat: StandardMaterial3D = StandardMaterial3D.new()
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire_mat.albedo_color = WIRE_COLOR

	var corner_positions: Array[Vector2] = [
		Vector2(-0.28, -0.28),
		Vector2( 0.28, -0.28),
		Vector2(-0.28,  0.28),
		Vector2( 0.28,  0.28),
	]
	for p: Vector2 in corner_positions:
		var wire_mi:   MeshInstance3D = MeshInstance3D.new()
		var wire_mesh: CylinderMesh   = CylinderMesh.new()
		wire_mesh.top_radius    = WIRE_RADIUS
		wire_mesh.bottom_radius = WIRE_RADIUS
		wire_mesh.height        = WIRE_LENGTH
		wire_mesh.radial_segments = 6
		wire_mi.mesh = wire_mesh
		wire_mi.position = Vector3(p.x, WIRE_LENGTH * 0.5, p.y)
		wire_mi.set_surface_override_material(0, wire_mat)
		add_child(wire_mi)
