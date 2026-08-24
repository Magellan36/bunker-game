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

## Aug 2026 chute pass — station didn't need this before (on_interact() is
## parameterless). Same lazy-resolve pattern LightStorage.gd/TrashCan.gd use.
var _interaction_system: Node = null

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

func _resolve_interaction_system() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		_interaction_system = player.get_node_or_null("InteractionSystem")

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

## ── Chute feed (Aug 2026) ───────────────────────────────────────────────
## F, from the chute proxy only (ResearchStationChute.gd) — feeds the
## player's held item/bag into stored_materials via add_material() above.
## A held single item is fully consumed (destroyed) for 1 unit of its
## get_trash_material() result. A held Trash Bag drains ALL viable records
## at once: records that fit are consumed and removed; records whose
## material is already at cap (checked against a running tally as the
## drain proceeds, not just the station's state before the bag started)
## stay behind — the SAME bag stays in the player's hand, just shrunk to
## the leftover records, or is fully consumed if nothing's left over.
## Confirmed with the person (three separate rounds): key-press feed (not
## physics drop-in), whole-bag drain, reject-entirely at cap for a single
## item, partial-drain-with-leftover for a bag.
func get_chute_f_prompt() -> String:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null:
		return ""
	var held: Node = _interaction_system.held_item
	if held == null:
		return ""
	if "is_trash_bag" in held:
		return "[F] Feed Trash Bag into chute"
	if held.is_in_group("inventory_item") and held.has_method("get_trash_material"):
		return "[F] Feed item into chute"
	return ""

func on_chute_f_interact() -> bool:
	if _interaction_system == null:
		_resolve_interaction_system()
	if _interaction_system == null:
		return false
	var held: RigidBody3D = _interaction_system.held_item
	if held == null:
		return false

	if "is_trash_bag" in held:
		_feed_bag(held, _interaction_system)
		return true

	if held.is_in_group("inventory_item") and held.has_method("get_trash_material"):
		_feed_single_item(held, _interaction_system)
		return true

	return false

func _feed_single_item(item: RigidBody3D, isys: Node) -> void:
	var material: String = item.get_trash_material()
	if not stored_materials.has(material):
		return   ## defensive — get_trash_material() should always return a known type
	if stored_materials[material] >= STORAGE_CAP:
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, "%s storage is full" % material.capitalize())
		return   ## reject entirely — item stays in hand, nothing consumed (confirmed)

	## Release from InteractionSystem — identical sequence to
	## LightStorage._try_store_held() / TrashCan's store path, just
	## destroying the item afterward instead of absorbing it into storage.
	isys._is_holding_e = false
	if item.has_signal("knocked_out") and item.knocked_out.is_connected(isys._on_item_knocked_out):
		item.knocked_out.disconnect(isys._on_item_knocked_out)
	if isys._held_from_slot != -1 and isys.inventory != null:
		isys.inventory.retrieve_item(isys._held_from_slot)
	isys.held_item       = null
	isys._held_from_slot = -1

	add_material(material, 1)
	item.queue_free()
	NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO, "+1 %s" % material.capitalize())

func _feed_bag(bag: RigidBody3D, isys: Node) -> void:
	var records: Array = bag.contents if "contents" in bag else []
	if records.is_empty():
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, "Bag is empty")
		return

	## Running per-material tally — lets a bag with several of the same
	## material correctly stop partway through once THIS drain pass would
	## push that material over the cap, not just checked against the
	## station's state before the bag started.
	var running: Dictionary = {}
	for m: String in MATERIAL_TYPES:
		running[m] = stored_materials[m]

	var leftover: Array[Dictionary] = []
	var fed_counts: Dictionary = {}
	for record: Dictionary in records:
		var material: String = record.get("data", {}).get("material", "")
		if material == "" or not stored_materials.has(material):
			leftover.append(record)   ## untagged (e.g. a bagged Seed) — can't be recycled, kept
			continue
		if running[material] >= STORAGE_CAP:
			leftover.append(record)   ## this material's full — kept, per confirmed partial-drain behavior
			continue
		running[material] += 1
		fed_counts[material] = fed_counts.get(material, 0) + 1

	for material: String in fed_counts.keys():
		add_material(material, fed_counts[material])

	var fed_total: int = 0
	for material: String in fed_counts.keys():
		fed_total += fed_counts[material]

	if fed_total == 0:
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.WARNING, "Nothing in the bag could be fed right now")
		return

	if leftover.is_empty():
		## Fully drained — consume the bag entirely, same release sequence
		## TrashCan._merge_bag() uses for a bag leaving the player's hand.
		isys._is_holding_e = false
		if bag.has_signal("knocked_out") and bag.knocked_out.is_connected(isys._on_item_knocked_out):
			bag.knocked_out.disconnect(isys._on_item_knocked_out)
		if isys._held_from_slot != -1 and isys.inventory != null:
			isys.inventory.retrieve_item(isys._held_from_slot)
		isys.held_item       = null
		isys._held_from_slot = -1
		bag.queue_free()
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO, "Fed %d items into Research Station — bag emptied" % fed_total)
	else:
		## Partial drain — bag stays in the player's hand, shrunk to just
		## the leftover records. No new bag object needed: this is the
		## SAME live bag node, never released from the player's hand to
		## begin with, just with its contents array reduced — simpler
		## than TrashCan's from-scratch bag creation.
		for i: int in leftover.size():
			leftover[i]["disposed_index"] = i
		bag.contents = leftover
		NotificationManager.notify(UIKit.Domain.NEUTRAL, NotificationManager.Severity.INFO, "Fed %d items — %d stayed in the bag (storage full)" % [fed_total, leftover.size()])

## Not built this pass — deliberately no "remove_material" logic beyond the
## chute above. Storage math (add_material()) is self-contained and was
## already ready for exactly this before the chute existed; nothing here
## assumed how materials would arrive.

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
## Aug 2026 chute pass: total footprint widened 1.5x (1.90 → 2.85 local X)
## to make room for a chute on the left. The ORIGINAL 1.90-wide research
## slab + beakers below is completely unchanged internally — it's now
## parented under `main_block`, a Node3D shifted +MAIN_BLOCK_CENTER_X so
## the whole assembly's local origin (0,0,0) sits at the CENTER of the new
## combined 2.85-wide footprint (required for _tile_half_extents()'s
## symmetric-about-origin bounds check to stay accurate). The chute itself
## occupies the remaining left portion, centered at CHUTE_CENTER_X.
## Reuses the same real model Table.gd's Medium (2×1) table loads — see
## PLAN_researchstation_table_base_swap.md for why the scale differs
## slightly from Table.gd's own constant (targets this station's TOP_Y =
## 0.75, not Table.gd's 0.77).
const BASE_MODEL_PATH:  String  = "res://assets/models/wooden_table.glb"
const BASE_MODEL_SCALE: Vector3 = Vector3(0.6333, 0.5792, 0.4638)

func _build_mesh() -> void:
	const CHUTE_WIDTH: float          = 0.95    ## 2.85 total - 1.90 original = 0.95 added
	const MAIN_BLOCK_WIDTH: float     = 1.90    ## unchanged original slab width
	const HALF_WIDTH_NEW: float       = 1.425   ## matches BuildModeController._tile_half_extents() Section 1.1
	const MAIN_BLOCK_CENTER_X: float  = HALF_WIDTH_NEW - MAIN_BLOCK_WIDTH * 0.5   ## 0.475
	const CHUTE_CENTER_X: float       = -HALF_WIDTH_NEW + CHUTE_WIDTH * 0.5        ## -0.95

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.60, 0.62, 0.65, 1.0)   ## Table.gd/Chair.gd's COLOR_METAL, verified current value
	mat.metallic = 0.3
	mat.roughness = 0.55

	## Original research slab + beakers, unchanged internally, now parented
	## under this shifted container instead of directly under self.
	var main_block: Node3D = Node3D.new()
	main_block.position = Vector3(MAIN_BLOCK_CENTER_X, 0.0, 0.0)
	add_child(main_block)

	## Real model base (Aug 2026) — same wooden_table.glb Table.gd's
	## Medium table uses, scaled to this station's own TOP_Y instead of
	## Table.gd's. Collision stays a solid full-height box matching the
	## OLD procedural box's exact extents/position — decoupled from the
	## now-open-legged visual on purpose (see plan header: default choice
	## was to keep this a fully solid obstacle, not let players walk
	## between the legs).
	const TOP_Y: float = 0.75
	var packed: PackedScene = load(BASE_MODEL_PATH) if ResourceLoader.exists(BASE_MODEL_PATH) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position = Vector3.ZERO
			model.scale    = BASE_MODEL_SCALE
			_recenter_glb_mesh(model)
			_strip_model_collision(model)
			main_block.add_child(model)
	else:
		push_warning("ResearchStation.gd: wooden_table.glb missing at %s — falling back to no base visual" % BASE_MODEL_PATH)

	## Main-block collision. MUST be a direct child of THIS StaticBody3D
	## (not of main_block, which is a plain Node3D) — a CollisionShape3D
	## nested under a non-CollisionObject3D does not register with the
	## physics server, so the table body would be walk-through. Position is
	## main_block's X offset + the old box's own offset to land identically.
	var base_col: CollisionShape3D = CollisionShape3D.new()
	var base_box: BoxShape3D = BoxShape3D.new()
	base_box.size = Vector3(1.90, TOP_Y, 0.90)
	base_col.shape = base_box
	base_col.position = Vector3(MAIN_BLOCK_CENTER_X, TOP_Y * 0.5, 0.0)
	add_child(base_col)

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
		main_block.add_child(flask_mi)

	## ── Chute (Aug 2026, wedge pass) — material input on the left side,
	## feeds stored_materials (the "bottom half" of the station, i.e. its
	## storage rather than the research/tier system). PrismMesh wedge —
	## tall at the outer/left mouth, sloping down to a near-zero point
	## right where it meets the main block — reads as an actual funnel
	## feeding into the box's side, not a second flat tower. Per the
	## person's own reference diagram.
	##
	## left_to_right = 0.0 puts the top edge directly above the LEFT
	## bottom edge, which collapses the RIGHT side to ~zero height (tall
	## left, pointed right — mouth away from the box, taper feeding into
	## it). Unverified visually — if it renders mirrored, flip this single
	## value to 1.0.
	const CHUTE_HOUSING_HEIGHT: float = 1.05

	## Riser — the wedge no longer tapers all the way to the floor. This
	## short box is the vertical wall at the box-side end: floor to
	## TOP_Y/3 (≈0.25, "about 1/3rd up the side" of the research station
	## per direction), spanning the full chute footprint. The ramp below
	## sits on top of this instead of on the floor directly.
	const RISER_HEIGHT: float = TOP_Y / 3.0
	var riser_mi: MeshInstance3D = MeshInstance3D.new()
	var riser_mesh: BoxMesh = BoxMesh.new()
	riser_mesh.size = Vector3(CHUTE_WIDTH - 0.10, RISER_HEIGHT, 0.80)
	riser_mi.mesh = riser_mesh
	riser_mi.position = Vector3(CHUTE_CENTER_X, RISER_HEIGHT * 0.5, 0.0)
	riser_mi.set_surface_override_material(0, mat)
	add_child(riser_mi)
	riser_mi.create_trimesh_collision()
	for child in riser_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Ramp — same wedge as before, just shortened by RISER_HEIGHT and
	## raised to sit on top of the riser. Tall end stays at the same
	## absolute height as before (RISER_HEIGHT + RAMP_HEIGHT = 1.05,
	## unchanged), so the mouth/opening marker below needs no repositioning.
	const RAMP_HEIGHT: float = CHUTE_HOUSING_HEIGHT - RISER_HEIGHT
	var chute_mi: MeshInstance3D = MeshInstance3D.new()
	var chute_mesh: PrismMesh = PrismMesh.new()
	chute_mesh.size = Vector3(CHUTE_WIDTH - 0.10, RAMP_HEIGHT, 0.80)
	chute_mesh.left_to_right = 0.0
	chute_mi.mesh = chute_mesh
	chute_mi.position = Vector3(CHUTE_CENTER_X, RISER_HEIGHT + RAMP_HEIGHT * 0.5, 0.0)
	chute_mi.set_surface_override_material(0, mat)
	add_child(chute_mi)
	chute_mi.create_trimesh_collision()
	for child in chute_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0

	## Opening marker — sits at the tall (left) mouth now, not centered
	## across what used to be a flat top. CHUTE_MOUTH_X is the wedge's
	## own left edge (tall side) + a small inset so the marker reads as
	## just inside the opening rather than hanging off it.
	const CHUTE_MOUTH_X: float = CHUTE_CENTER_X - (CHUTE_WIDTH - 0.10) * 0.5 + 0.20
	var mat_slot: StandardMaterial3D = StandardMaterial3D.new()
	mat_slot.albedo_color = Color(0.08, 0.08, 0.09, 1.0)
	mat_slot.roughness = 0.9
	var slot_mi: MeshInstance3D = MeshInstance3D.new()
	var slot_mesh: BoxMesh = BoxMesh.new()
	slot_mesh.size = Vector3(0.35, 0.08, 0.55)
	slot_mi.mesh = slot_mesh
	slot_mi.position = Vector3(CHUTE_MOUTH_X, CHUTE_HOUSING_HEIGHT - 0.10, 0.0)
	slot_mi.set_surface_override_material(0, mat_slot)
	add_child(slot_mi)

	## Feed interaction proxy — repositioned to the tall mouth (was
	## centered across the old flat top). See ResearchStationChute.gd's
	## own doc comment for why this is a separate StaticBody3D rather than
	## F handling living on the main station body.
	var chute_proxy_script: GDScript = load("res://scripts/world/furniture/ResearchStationChute.gd")
	var chute_proxy: StaticBody3D = StaticBody3D.new()
	chute_proxy.set_script(chute_proxy_script)
	chute_proxy.position = Vector3(CHUTE_MOUTH_X, CHUTE_HOUSING_HEIGHT - 0.10, 0.45)
	add_child(chute_proxy)
	chute_proxy.set("host", self)

## Recursively disables collision on every CollisionObject3D descendant of
## an instanced model. Duplicated per-file, matching the established
## convention across every prior model-swap in this codebase.
func _strip_model_collision(node: Node) -> void:
	if node is CollisionObject3D:
		var co: CollisionObject3D = node as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask  = 0
	for child: Node in node.get_children():
		_strip_model_collision(child)

## Godot's glTF importer always wraps an imported scene in an extra
## generated root node — see Table.gd's identical helper for the full
## explanation. wooden_table.glb's source node has an identity transform
## (already confirmed clean in the original Table.gd plan), so this is
## inert here — kept for consistency.
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false

static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(2.85, 0.95, 0.90)   ## Aug 2026 chute pass — widened 1.5x (was 1.90). Unaffected by the base-model swap — same overall footprint.
	return box
