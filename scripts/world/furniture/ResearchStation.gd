extends StaticBody3D
class_name ResearchStation
## ResearchStation.gd
## Singleton, spawns at world start (see MainWorld._spawn_initial_research_station()),
## never purchasable, never deconstructable, movable only — identical treatment
## to BuildStation.gd. Opens ResearchStationUI on E; the UI itself is the
## substantial part of this feature and grows over future passes. This pass:
## object + UI shell + 3 selectable tabs with placeholder content only —
## no buttons, no timers, no feed logic. See HANDOVER for the full scope note.

var _research_ui: Node = null   ## Injected by MainWorld at spawn time, same pattern as BuildStation's _main_world

const MATERIAL_TYPES: Array[String] = ["metal", "plastic", "paper", "organic"]
const STORAGE_CAP: int = 10   ## Final-version cap, upgradeable later via this same menu — wired now per direction, not a placeholder.

var stored_materials: Dictionary = {"metal": 0, "plastic": 0, "paper": 0, "organic": 0}

## Exactly one research can be active at a time, globally, this pass — see
## the design note at the top of this plan for why multi-concurrent/pause
## isn't built yet and what it'll need when it is.
var active_upgrade: UpgradeDef   = null
var _elapsed: float              = 0.0
var _consumed: Dictionary        = {}   ## material -> amount already drained from stored_materials for the active research

## New. Active research + is_paused together fully describe the 3 states.
var is_paused: bool = false

## Persisted per-station, NOT on the UpgradeDef resource itself (Resources
## can be shared/reloaded refs — mutating a "completed" bool directly on one
## would be a correctness footgun). This is the real source of truth for
## "has this upgrade been done."
## chain id -> tiers completed so far (0 = not started). Replaces last
## pass's simple done/not-done set now that upgrades can have multiple
## completions.
var tier_progress: Dictionary = {}

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	add_to_group("research_station")
	_build_mesh()

func get_interact_prompt() -> String:
	return "[E] Open Research Station"

func on_interact() -> void:
	if _research_ui != null and _research_ui.has_method("open"):
		_research_ui.open(self)

func get_prompt_world_pos() -> Vector3:
	return global_position + Vector3(0.0, 1.1, 0.0)

## Adds amount of a material, clamped at STORAGE_CAP. Returns the actual
## amount added (may be less than requested if the cap was hit) — callers
## that care (e.g. a future toast for "storage full, X wasted") can use this;
## the F7 debug button (Part 5) doesn't need to.
func add_material(material: String, amount: int) -> int:
	if not stored_materials.has(material):
		return 0
	var before: int = stored_materials[material]
	stored_materials[material] = clampi(before + amount, 0, STORAGE_CAP)
	return stored_materials[material] - before

## Not built this pass — deliberately no "remove_material" or "deposit trash
## into reservoir" logic at all. Storage math above is self-contained and
## ready to be called from whatever the future reservoir/dump feature turns
## out to be; nothing here assumes how materials arrive.

## Attempts to begin researching an upgrade. Returns false (leaving state
## untouched) if another research is already running, the upgrade is already
## completed, or the station doesn't currently hold enough of each required
## material. Nothing is deducted at click-time — eligibility is just a check;
## the pool drains incrementally in _process() as elapsed time advances (see
## the design note at the top of the plan).
func start_research(upgrade: UpgradeDef) -> bool:
	if active_upgrade != null:
		return false   ## something else already running — see design note
	if tier_progress.get(upgrade.id, 0) >= upgrade.get_max_tier():
		return false   ## fully maxed
	for material: String in upgrade.material_costs.keys():
		if stored_materials.get(material, 0) < upgrade.material_costs[material]:
			return false   ## not enough — button should already be greyed out, this is the authoritative re-check
	active_upgrade = upgrade
	_elapsed   = 0.0
	_consumed  = {}
	is_paused  = false   ## reset a stale pause flag before starting fresh (polish-pass bug fix — flagged)
	for material: String in upgrade.material_costs.keys():
		_consumed[material] = 0
	return true

func pause_research() -> void:
	if active_upgrade != null:
		is_paused = true   ## _process() below stops advancing elapsed/consumption while true — no refund, nothing else changes

func resume_research() -> void:
	if active_upgrade != null:
		is_paused = false

func _process(delta: float) -> void:
	if active_upgrade == null or is_paused:
		return   ## paused: elapsed/consumption both frozen, no refund

	_elapsed += delta
	var progress: float = clampf(_elapsed / active_upgrade.duration_seconds, 0.0, 1.0)

	## Incremental drain — only the DELTA since last tick leaves storage,
	## matching the "60% done = 3/5 used" example exactly. floor() keeps
	## consumption monotonic and never overshoots before completion; the
	## final tick snaps to the exact full cost rather than trusting
	## floor(cost * 1.0) to land exactly on cost (it does, but this is
	## explicit and immune to float rounding at the boundary).
	for material: String in active_upgrade.material_costs.keys():
		var cost: int    = active_upgrade.material_costs[material]
		var target: int  = cost if progress >= 1.0 else int(floor(cost * progress))
		var step: int    = target - _consumed[material]
		if step > 0:
			stored_materials[material] = maxi(0, stored_materials[material] - step)
			_consumed[material] = target

	if progress >= 1.0:
		_complete_research()

func _complete_research() -> void:
	var finished: UpgradeDef = active_upgrade
	var next_tier: int = tier_progress.get(finished.id, 0) + 1
	tier_progress[finished.id] = next_tier
	active_upgrade = null
	_elapsed  = 0.0
	_consumed = {}
	is_paused = false   ## polish-pass bug fix — stale true would stall the next research (flagged)

	if finished.has_method("set_tree_ref"):
		finished.set_tree_ref(get_tree())
	finished.apply_effect(next_tier)

	## Toast per direction — established system, not the old warning label.
	NotificationManager.notify(
		UIKit.Domain.NEUTRAL,
		NotificationManager.Severity.INFO,
		"%s Tier %d research completed" % [finished.display_name, next_tier]
	)

# ─── Basic model — filled rectangle base + beakers/flasks, grey/steel to match Table/Chair ──
func _build_mesh() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.60, 0.62, 0.65, 1.0)   ## Table.gd/Chair.gd's COLOR_METAL, verified current value
	mat.metallic = 0.3
	mat.roughness = 0.55

	## Filled rectangle base — same 2×1 (1.90 × 0.90) footprint as Build
	## Station/Medium Table, but solid floor-to-top rather than four legs +
	## thin top, per design direction.
	const TOP_Y: float = 0.75
	var base_mi: MeshInstance3D = MeshInstance3D.new()
	var base_mesh: BoxMesh = BoxMesh.new()
	base_mesh.size = Vector3(1.90, TOP_Y, 0.90)
	base_mi.mesh = base_mesh
	base_mi.position = Vector3(0.0, TOP_Y * 0.5, 0.0)
	base_mi.set_surface_override_material(0, mat)
	add_child(base_mi)
	base_mi.create_trimesh_collision()
	for child in base_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Beakers/flasks — a few simple primitives, tinted "liquid" glass look.
	var mat_glass: StandardMaterial3D = StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.55, 0.85, 0.75, 0.55)
	mat_glass.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.roughness = 0.1

	var flask_specs: Array = [
		{"pos": Vector3(-0.55, TOP_Y + 0.08, -0.15), "r": 0.055, "h": 0.16},
		{"pos": Vector3(-0.35, TOP_Y + 0.06, 0.15),  "r": 0.045, "h": 0.12},
		{"pos": Vector3(0.40, TOP_Y + 0.09, -0.05),  "r": 0.06,  "h": 0.18},
		{"pos": Vector3(0.60, TOP_Y + 0.05, 0.20),   "r": 0.04,  "h": 0.10},
	]
	for spec: Dictionary in flask_specs:
		var flask_mi: MeshInstance3D = MeshInstance3D.new()
		var flask_mesh: CylinderMesh = CylinderMesh.new()
		flask_mesh.top_radius = spec["r"] * 0.7
		flask_mesh.bottom_radius = spec["r"]
		flask_mesh.height = spec["h"]
		flask_mi.mesh = flask_mesh
		flask_mi.position = spec["pos"]
		flask_mi.set_surface_override_material(0, mat_glass)
		add_child(flask_mi)

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.90, 0.95, 0.90)
	return box