extends StaticBody3D
class_name Stove
## Stove.gd
## Cooking System Part A/B. 1x1 floor-placed power consumer. Manual on/off
## toggle via [E] — independent of whether a Cooking Pot is present. Only
## actually draws its 200W while powered_on AND a pot is present ("cooking").
## Indicator light reflects powered_on ONLY (pot or no pot).
##
## Placement/registration mirrors HeavyConsumerTest.gd / GrowLight.gd exactly
## — see those files for the established convention this follows.

# ─── Config ───────────────────────────────────────────────────────────────────
const WATTS: float = 200.0

## Real-model footprint/height, replacing the old procedural BOX_SIZE.
## Source: assets/models/stove.glb (Kitchen_Oven_Large), uniform scale
## 0.7257 applied to fit the existing 1×1 tile — see
## PLAN_stove_glb_swap.md for the full derivation, including why this is
## uniform (preserves the model's real proportions) rather than forced
## square like the old placeholder. NOT square — 0.85 × 0.7768 footprint,
## 1.1558 tall. Every other file that depended on the old square 0.85/0.55
## values (BuildModeController._tile_half_extents(), MoveDuplicateTool.gd)
## has been updated to match — see that plan's dependency list if this
## ever needs to change again.
const MODEL_PATH:  String  = "res://assets/models/stove.glb"
const MODEL_SCALE: Vector3 = Vector3(0.7257, 0.7257, 0.7257)
const FOOTPRINT_X: float = 0.85
const FOOTPRINT_Z: float = 0.7768
const MODEL_HEIGHT: float = 1.1558

const COLOR_LIGHT_ON:  Color = Color(0.30, 1.00, 0.40, 1.0)   ## green, matches HeavyConsumerTest's COLOR_ON
const COLOR_LIGHT_OFF: Color = Color(0.25, 0.05, 0.05, 1.0)   ## dark red / unlit

## Local position (relative to Stove root) where a placed Cooking Pot
## sits — the flat top of the real model (confirmed with Brannon; the
## source model reads as an oven-tower cabinet with no distinct
## "burner" geometry, so the very top surface is the intended cooking
## spot). Was 0.58 under the old procedural box.
const POT_LOCAL_POS: Vector3 = Vector3(0.0, 1.1558, 0.0)

# ─── State ────────────────────────────────────────────────────────────────────
var _pm_node_key: String = ""
var powered_on:   bool   = false   ## Manual toggle state — independent of pot presence
var _is_shed:     bool   = false   ## Grid load-shed state
var _grid_connected: bool = false  ## Cache only — see _is_grid_connected() below for the authoritative check
var pot_ref:      Node   = null    ## The CookingPot currently resting on this stove, or null

var _indicator_mi:  MeshInstance3D     = null
var _indicator_mat: StandardMaterial3D = null

## Full-fidelity preview mode — set TRUE by BuildModeHUD's construct-tab
## preview code BEFORE add_child(). Same convention as every other build
## object in this project (see HeavyConsumerTest.gd's own comment on this
## field for the full explanation). MUST be set before add_child().
var _is_preview_only: bool = false

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	if not _is_preview_only:
		add_to_group("interactable")
		add_to_group("stove")
	_build_collision()
	_build_fixture()
	set_powered(false)   ## Safety net — matches GrowLight's convention
	if _is_preview_only:
		return
	call_deferred("_register_deferred")


## Collision built once, independent of the visual model — matches every
## other model-swap in this codebase. Direct CollisionShape3D on this
## StaticBody3D (Stove already extends StaticBody3D — no nested-body
## trimesh-collision indirection needed). Box spans the full real
## footprint/height so it blocks movement the same way the tall real
## model visually reads (unlike thin furniture, this is a floor-to-top
## obstacle the player walks around, not over).
func _build_collision() -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(FOOTPRINT_X, MODEL_HEIGHT, FOOTPRINT_Z)
	shape.shape = box
	shape.position = Vector3(0.0, MODEL_HEIGHT * 0.5, 0.0)
	add_child(shape)


func _exit_tree() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if not _pm_node_key.is_empty():
		pm.unregister_wire_node(_pm_node_key)
	pm.unregister_consumer(str(get_instance_id()))


# ─── PowerManager registration (mirrors HeavyConsumerTest.gd exactly) ────────
func _register_deferred() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("Stove: PowerManager not found — will never receive power.")
		return

	_pm_node_key = pm.register_wire_node(
		global_position,
		"consumer",
		str(get_instance_id()))

	## Registered INACTIVE. The stove only actually draws power once
	## powered_on AND pot_ref are both true — see _refresh_cooking_state().
	pm.register_consumer(
		str(get_instance_id()),
		WATTS,
		self,
		"stove",
		1,        ## priority — appliance-tier, not life-support
		false)    ## NOT active from the start

	_auto_connect_to_nearby_wires(pm)


## Copied (pattern) from GrowLight._auto_connect_to_nearby_wires() — confirmed
## Aug 2026 that the Stove should auto-connect like every other consumer.
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
		var ac_eid: String = pm.register_wire_edge(_pm_node_key, best_key, null, true)
		pm.set_wire_edge_no_visual(ac_eid)


## Called by BuildModeController after a new wire node is placed nearby.
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


# ─── PowerManager callbacks (required interface) ──────────────────────────────
## The registered consumer is only EVER active while cooking (see
## _refresh_cooking_state), so `on` here is only ever true while
## powered_on AND pot_ref are both true. The indicator light is driven
## independently off `powered_on` directly — see _refresh_indicator().
func set_powered(on: bool) -> void:
	_grid_connected = on
	if on:
		_is_shed = false
	elif powered_on:
		## Lost our wire connection (or grid path) while switched on — force
		## off. This is the "auto-disconnect" behavior: powered_on cannot
		## be true while _grid_connected is false. _refresh_cooking_state()
		## already handles stopping the 200W draw, and CookingPot's existing
		## decay logic (Part 3/G) already handles ticking cook progress back
		## down since is_cooking() will go false the instant powered_on does.
		powered_on = false
		_refresh_cooking_state()
		_refresh_indicator()

func set_shed(shed_on: bool) -> void:
	_is_shed = shed_on


## Authoritative "am I actually wired to a live generator right now" check.
## Deliberately does NOT rely on set_powered() / _grid_connected alone —
## PowerManager only calls set_powered() on ACTIVE consumers (see
## PowerManager._apply_reachability()), and this stove registers itself
## inactive until it's already cooking, so a wired-but-not-yet-cooking stove
## would otherwise never be told it's connected. _is_consumer_reachable() is
## PowerManager's private raw-BFS-result check (not active-gated) — reaching
## into it directly is a pragmatic workaround, not a permanent API; ideally
## PowerManager would expose a public wrapper for this someday.
func _is_grid_connected() -> bool:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null or not pm.has_method("_is_consumer_reachable"):
		return false
	return pm._is_consumer_reachable(str(get_instance_id()))


# ─── Manual on/off toggle — [E] while NOT holding a Cooking Pot ──────────────
## Called generically by InteractionSystem._try_interact() (StaticBody3D +
## "interactable" group + on_interact() — zero InteractionSystem changes
## needed for this path). InteractionSystem's is_cookpot_container branch
## (see Part D) always intercepts E BEFORE this when the player is holding
## the pot and this stove is open, so by the time this runs it is always
## meant to simply toggle.
func on_interact() -> void:
	if not powered_on and not _is_grid_connected():
		## Can't switch on without a live wire connection.
		var hud: Node = get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_soft_warning"):
			hud.show_soft_warning("Stove not connected to power")
		return
	powered_on = not powered_on
	_refresh_cooking_state()
	_refresh_indicator()

## If our pot has a dish ready, show ITS prompt instead of the toggle text
## — so whichever of {Stove, Pot} the nearby-interactable scan happens to
## pick as "closest", the displayed text always matches what [E] will
## actually do (InteractionSystem's take-dish check runs before the
## generic fallback regardless of which one is displayed — see Part G4).
func get_interact_prompt() -> String:
	if pot_ref != null and pot_ref.has_method("is_dish_ready") and pot_ref.is_dish_ready():
		if pot_ref.has_method("get_dish_ready_text"):
			return pot_ref.get_dish_ready_text()
		return pot_ref.get_interact_prompt()   ## fallback if the method's ever missing
	if not powered_on and not _is_grid_connected():
		return "Stove Not Connected"
	return "[E] Turn Stove %s" % ("Off" if powered_on else "On")


# ─── Pot slot management (called by InteractionSystem, Part D) ──────────────
func has_open_slot() -> bool:
	return pot_ref == null

## Places `pot` on top of the burner. Caller is responsible for releasing it
## from the player's hand — this only handles the stove/pot side.
func try_place_pot(pot: Node) -> bool:
	if pot_ref != null:
		return false
	## Defensive (Aug 2026 crash fix): if this pot still thinks it belongs
	## to a DIFFERENT stove — a stale reference left over from some other
	## code path — clear that stove's pot_ref FIRST. Without this, the old
	## host keeps pointing at a pot that isn't its child anymore, and the
	## next time anything calls try_remove_pot() on IT, Godot throws an
	## engine-level "parent != this" error trying to remove_child() a node
	## it doesn't actually own. This was the confirmed root cause of a
	## reported crash.
	if "_host_stove" in pot:
		var old_host: Variant = pot.get("_host_stove")
		if old_host != null and old_host != self and old_host.has_method("clear_pot_ref"):
			old_host.clear_pot_ref()
	pot_ref = pot
	var old_parent: Node = pot.get_parent()
	if old_parent != null:
		old_parent.remove_child(pot)
	add_child(pot)
	pot.position = POT_LOCAL_POS
	pot.rotation = Vector3.ZERO
	if pot is RigidBody3D:
		var rb: RigidBody3D = pot as RigidBody3D
		rb.freeze           = true
		rb.freeze_mode      = RigidBody3D.FREEZE_MODE_STATIC
		rb.collision_layer  = 0
		rb.collision_mask   = 0
		rb.linear_velocity  = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		if pot.has_method("deactivate_dynamic_state"):
			pot.deactivate_dynamic_state()   ## resting pot = physics/contacts/obstacle off (Aug 2026)
	if "is_held" in pot:
		pot.is_held = false
	if pot.has_method("set_host_stove"):
		pot.set_host_stove(self)
	_refresh_cooking_state()
	return true

## Called by BuildModeController._try_deconstruct() before this node is
## freed, so a pot resting on the stove survives instead of being destroyed
## as an orphaned child. Confirmed Aug 2026 fix. Reuses try_remove_pot()'s
## existing reparent-to-world-root + unfreeze logic — the pot ends up sitting
## on the ground at the stove's position, fully interactable again.
func eject_all_items() -> void:
	if pot_ref == null:
		return
	var pot: Node = try_remove_pot()
	if pot != null and pot is RigidBody3D:
		(pot as RigidBody3D).linear_velocity = Vector3.ZERO


## ─── Save/Load (Part J) ───────────────────────────────────────────────────
## Read by BuildModeController._get_device_extra().
func get_pot_extra() -> Dictionary:
	if pot_ref != null and pot_ref.has_method("get_save_extra"):
		return pot_ref.get_save_extra()
	return {}

## Called by BuildModeController._apply_device_extra_deferred() on restore.
## Sets powered_on directly — bypassing the grid-connection gate inside
## on_interact(), since this is a system-level restore, not a player action
## — and re-creates the pot (a real CookingPot.tscn instance, not just a
## data blob) if one existed when the game was saved.
func restore_saved_state(saved_powered_on: bool, pot_extra: Dictionary) -> void:
	powered_on = saved_powered_on
	_refresh_indicator()
	if not pot_extra.is_empty():
		var packed: PackedScene = load("res://scenes/world/CookingPot.tscn") as PackedScene
		if packed != null:
			var pot: Node = packed.instantiate()
			if pot != null:
				try_place_pot(pot)
				if pot.has_method("restore_saved_state"):
					pot.restore_saved_state(pot_extra)
	_refresh_cooking_state()


## Detaches the current pot, restores its physics, and returns it — caller
## (InteractionSystem's F-handler, Part D) then calls pot.pickup(hold_point)
## on it exactly like a normal world pickup. Returns null if no pot present.
func try_remove_pot() -> Node:
	if pot_ref == null:
		return null
	var pot: Node = pot_ref
	pot_ref = null
	## Defensive (Aug 2026 crash fix): if this pot's actual parent isn't us
	## anymore — already moved elsewhere by some other path — there's
	## nothing to remove. Drop the stale reference instead of letting Godot
	## throw an engine-level "parent != this" error.
	if pot.get_parent() != self:
		_refresh_cooking_state()
		return null
	var world_root: Node = get_tree().get_root()
	remove_child(pot)
	world_root.add_child(pot)
	pot.global_position = global_position + Vector3(0.0, POT_LOCAL_POS.y + 0.05, 0.0)
	if pot is RigidBody3D:
		var rb: RigidBody3D = pot as RigidBody3D
		rb.freeze          = false
		rb.freeze_mode     = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.gravity_scale   = 0.0
		rb.collision_layer = 2
		rb.collision_mask  = 1
		if pot.has_method("restore_dynamic_state"):
			pot.restore_dynamic_state()   ## off the stove — live again (Aug 2026)
	if pot.has_method("set_host_stove"):
		pot.set_host_stove(null)
	_refresh_cooking_state()
	return pot


## Defensive escape hatch — clears our pot_ref WITHOUT touching the pot
## itself (the pot has already been claimed by something else by the time
## this runs; see try_place_pot()'s stale-reference guard above).
func clear_pot_ref() -> void:
	pot_ref = null
	_refresh_cooking_state()


# ─── Cooking-active / power-draw logic ────────────────────────────────────────
## Power draw (200W) = powered_on ALONE. Pot or no pot, items or no items —
## if it's switched on, it draws. is_cooking() (powered_on + pot present +
## pot has items) still exists and is unchanged, but is now used ONLY to
## gate the cook-progress timer inside CookingPot._process() and the pot's
## "COOKING" status text — a fully separate concern from the power draw.
func _refresh_cooking_state() -> void:
	## Confirmed Aug 2026 — the 200W draw is tied to `powered_on` ALONE, not
	## to is_cooking(). The stove draws power the instant it's switched on,
	## pot or no pot, items or no items. is_cooking() (powered_on + pot
	## present + pot has items) still exists and is unchanged, but is now
	## used ONLY to gate the cook-progress timer inside CookingPot._process()
	## and the pot's "COOKING" status text — a fully separate concern from
	## the power draw itself.
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		pm.set_consumer_active(str(get_instance_id()), powered_on)


## Called by CookingPot (via _host_stove) whenever its contents change while
## already resting on this stove — an item added post-placement, or a dish
## finishing and clearing the pot's slots. This now only re-sets active =
## powered_on (which is already correct), kept for parity with the pattern.
func notify_pot_contents_changed() -> void:
	_refresh_cooking_state()


## "Cooking" = powered_on AND a pot is present AND that pot has ≥1 item in
## it. An empty pot on a powered-on stove draws nothing and never
## progresses — there's nothing to cook. (Once a dish finishes, the pot's
## slots are cleared — see CookingPot._finish_cooking() — so is_cooking()
## naturally goes false again the instant the dish is ready, and the stove
## stops drawing power until either the dish is taken and new items added,
## or the ready dish is served.)
func is_cooking() -> bool:
	if not powered_on or pot_ref == null:
		return false
	if not pot_ref.has_method("count_filled"):
		return false
	return pot_ref.count_filled() > 0


# ─── Indicator light — reflects powered_on ONLY ──────────────────────────────
func _refresh_indicator() -> void:
	if _indicator_mat == null:
		return
	var c: Color = COLOR_LIGHT_ON if powered_on else COLOR_LIGHT_OFF
	_indicator_mat.albedo_color = c
	_indicator_mat.emission     = c
	_indicator_mat.emission_energy_multiplier = 2.5 if powered_on else 0.0


# ─── Visual build ──────────────────────────────────────────────────────────
## Loads the real Kitchen_Oven_Large model. Every procedural body/feet/
## burner-ring/knob element the old placeholder built is now supplied by
## the real mesh — only the indicator light survives, since it's the one
## piece of functional (not decorative) geometry: it visually reports
## live powered_on state, which the imported static model can't do on
## its own. See PLAN_stove_glb_swap.md for the full source-asset
## breakdown and why this particular model has no distinct "burner"
## geometry (it reads as an oven-tower cabinet, not an open cooktop).
func _build_fixture() -> void:
	var packed: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null
	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position = Vector3.ZERO
			model.scale    = MODEL_SCALE
			_recenter_glb_mesh(model)
			_strip_model_collision(model)
			add_child(model)
	else:
		push_warning("Stove.gd: model missing at %s — falling back to no visual mesh" % MODEL_PATH)

	## Indicator light — small emissive sphere, repositioned onto the new
	## model's front-upper area (was BOX_SIZE-relative, now
	## MODEL_HEIGHT/FOOTPRINT_Z-relative, same 0.75-height / front-face
	## placement ratio as before).
	_indicator_mi = MeshInstance3D.new()
	var ind_mesh: SphereMesh = SphereMesh.new()
	ind_mesh.radius = 0.035
	ind_mesh.height = 0.07
	_indicator_mi.mesh = ind_mesh
	_indicator_mi.position = Vector3(0.0, MODEL_HEIGHT * 0.75, FOOTPRINT_Z * 0.5 + 0.02)
	_indicator_mat = StandardMaterial3D.new()
	_indicator_mat.albedo_color     = COLOR_LIGHT_OFF
	_indicator_mat.emission_enabled = true
	_indicator_mat.emission         = COLOR_LIGHT_OFF
	_indicator_mat.emission_energy_multiplier = 0.0
	_indicator_mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator_mi.set_surface_override_material(0, _indicator_mat)
	add_child(_indicator_mi)

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
## explanation. stove.glb's source node has an identity transform
## (confirmed via direct inspection), so this is inert here — kept for
## consistency.
func _recenter_glb_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		(node as MeshInstance3D).position = Vector3.ZERO
		return true
	for child: Node in node.get_children():
		if _recenter_glb_mesh(child):
			return true
	return false


## Side-effect-free ghost mesh for build-mode previews — same convention as
## HeavyConsumerTest.build_ghost_mesh(): no registration, no groups, no
## signals, just the plain mesh. Non-square now, matching the real
## model's footprint (was a uniform BOX_SIZE cube-ish box under the old
## placeholder) — this box IS the accurate size cue in the walking
## placement ghost; the full detailed model shows separately in the
## Construct-menu spinning preview via the existing GhostModelBuilder
## registration, unaffected by this change.
static func build_ghost_mesh() -> Mesh:
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(FOOTPRINT_X, MODEL_HEIGHT, FOOTPRINT_Z)
	return box
