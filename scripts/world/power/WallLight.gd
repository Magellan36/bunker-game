extends Node3D
## WallLight.gd
## Wall-mounted industrial lamp using the industrial_wall_lamp GLB model.
##
## Light: OmniLight3D radiating from the fixture centre.
## OmniLight fills the room in all directions — no tilt/direction tuning needed.
##
## NO COLLISION — purely visual + light-emitting Node3D.
## Called from BuildModeController._spawn_placed_object() for TILE_LIGHT = 5.
##
## POWER GRID
##   Registers with PowerManager on _ready() using power_watts.
##   PowerManager calls set_powered(bool) to toggle the light on/off.
##   PowerManager calls set_shed(true) when load-shedding — light dims to a
##   faint orange glow rather than going fully dark.

# ─── Debug ────────────────────────────────────────────────────────────────────
## Flip false to silence all [LIGHT] registration prints.
const WIRE_DEBUG: bool = true
func _wdbg(msg: String) -> void:
	if WIRE_DEBUG:
		print(msg)

# ─── Model path ───────────────────────────────────────────────────────────────
const MODEL_PATH: String = "res://assets/models/industrial_wall_lamp.glb"

# ─── Fixture geometry constants (match GLB bounds exactly) ───────────────────
const LAMP_W: float = 0.2735
const LAMP_H: float = 0.4300
const LAMP_D: float = 0.1404

## Vertical offset from node origin to lamp centre (~3/4 wall height).
const LAMP_Y_OFFSET: float = 1.5

# ─── OmniLight constants ──────────────────────────────────────────────────────
## Warm industrial amber — noticeably warm, not clinical white
const LIGHT_COLOR:  Color = Color(1.0, 0.82, 0.50, 1.0)
## Lowered from 4.5 (July 2026 lighting-blowout fix) — 4.5 was tuned before
## glow/SDFGI/volumetric fog existed in the project; once those post-process
## systems came online they amplified the same raw value well past what
## looked right originally. Let glow/bloom sell "bright at the source"
## instead of flooding the whole room via raw light energy.
const LIGHT_ENERGY: float = 2.0
const LIGHT_RANGE:  float = 10.0
## Per-light volumetric-fog contribution (July 2026 lighting-blowout fix).
## Godot's default is 1.0 (full contribution) — left at default, every wall
## light was scattering its full warm glow through the whole fog volume,
## turning "distinct pools of light with dark corners between" into
## "uniformly hazy room." Reserves the visible fog-shaft look specifically
## for the flashlight (the intended showcase per the graphics plan's design
## thesis), not ambient room lights.
const LIGHT_VOLUMETRIC_FOG_ENERGY: float = 0.2

## Shed (overloaded grid) state — faint orange glow, barely visible
const SHED_COLOR:   Color = Color(1.0, 0.45, 0.0, 1.0)
const SHED_ENERGY:  float = 0.15   ## very low — just enough to suggest the filament is warm

# ─── Power grid ───────────────────────────────────────────────────────────────
## Rated power draw in watts. Matches DeviceDatabase.WATT_RATINGS["wall_light"].
var power_watts: float = 40.0

## Internal reference to the OmniLight3D — needed for set_powered() / set_shed()
var _omni: OmniLight3D = null

## Priority tier: 1 (critical) … 5 (luxury). Wall lights default to 1
## (critical/never-shed) — both pregen level-start lights and player-placed
## lights use this same default since they're the same WallLight.gd scene
## either way. Player can still change it per-instance via the priority
## panel (E to interact) same as any other consumer.
var power_priority: int = 1

## Snap key returned by PowerManager.register_wire_node() — needed to
## unregister the wire node in _exit_tree(). Empty until registered.
var _pm_node_key: String = ""

## Track shed state so set_powered(true) knows to restore full brightness.
var _is_shed: bool = false

## Lazily-created shared priority panel (PowerPriorityUI). Reused across opens.
var _prio_ui: CanvasLayer = null
## Tracks whether the player is currently powered (for the interact prompt).
var _is_powered: bool = false

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_meta("tile_id", 5)
	add_to_group("wall_lights")
	_build_fixture()
	## Defer power registration so global_position is correct.
	## add_child() sets position AFTER _ready() runs, so calling
	## register_wire_node() here would snap to Vector3.ZERO.
	call_deferred("_register_wire_deferred")

func _exit_tree() -> void:
	## Unregister from the power graph when removed from the scene.
	## Wire node FIRST — that triggers the network re-solve.
	## Consumer SECOND — graph no longer references this device.
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	if _pm_node_key != "":
		pm.unregister_wire_node(_pm_node_key)
	pm.unregister_consumer(str(get_instance_id()))

# ─── Power grid API ──────────────────────────────────────────────────────────

## Called by PowerManager when the grid trips or restores power.
## When turning off via this call it means a hard power-cut (not shedding),
## so the light goes fully dark.
func set_powered(on: bool) -> void:
	_is_powered = on
	if _omni == null:
		return
	if on:
		## Restore full brightness — clear shed state.
		_is_shed = false
		_omni.light_color  = LIGHT_COLOR
		_omni.light_energy = LIGHT_ENERGY
		_omni.visible      = true
	else:
		## Hard power-cut — always go fully dark regardless of shed state.
		## PowerManager clears shed before calling set_powered(false), but
		## this guard ensures correctness even if called out of order.
		_is_shed      = false
		_omni.visible = false


## Called by PowerManager._apply_shed_to_consumer() when this light is
## load-shed during an overloaded grid. Shows a faint orange glow instead of going dark.
## The player can see the light is "on" but starved for power.
func set_shed(shed_on: bool) -> void:
	if _omni == null:
		return
	_is_shed = shed_on
	if shed_on:
		_omni.light_color  = SHED_COLOR
		_omni.light_energy = SHED_ENERGY
		_omni.visible      = true   ## dimly visible — not off
	else:
		## Un-shed: restore full brightness if the grid is still live.
		## PowerManager will call set_powered(true) shortly after clearing shed,
		## so we just let that handle the full restore. Only clear the flag here.
		_is_shed = false


# ─── Priority interaction (forwarded by PowerPriorityInteractable proxy) ─────
## Opens the shared PowerPriorityUI for this light. No load toggle — lights are
## always "on" when wired; their visibility is driven by the grid/shed state.
func on_priority_interact() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = true

	if _prio_ui == null or not is_instance_valid(_prio_ui):
		var ui_script: GDScript = load("res://scripts/ui/power/PowerPriorityUI.gd")
		if ui_script == null:
			push_warning("WallLight: PowerPriorityUI.gd not found")
			return
		_prio_ui = CanvasLayer.new()
		_prio_ui.set_script(ui_script)
		_prio_ui.name = "PowerPriorityUI"
		get_tree().get_root().add_child(_prio_ui)
		if _prio_ui.has_signal("closed"):
			_prio_ui.closed.connect(_on_prio_closed)
		if _prio_ui.has_signal("priority_changed"):
			_prio_ui.priority_changed.connect(_on_prio_changed)

	if _prio_ui.has_method("open"):
		_prio_ui.call("open", str(get_instance_id()), "Wall Light", false)

func get_priority_prompt() -> String:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	var prio: int = power_priority
	if pm != null:
		prio = pm.get_consumer_priority(str(get_instance_id()))
	var state: String = "Powered" if _is_powered else ("Shed" if _is_shed else "No Power")
	return "[E] Wall Light  —  Priority %d  (%s)" % [prio, state]

func _on_prio_closed() -> void:
	var is_node: Node = _get_interaction_system()
	if is_node != null and "build_mode_active" in is_node:
		is_node.build_mode_active = false

func _on_prio_changed(_id: String, value: int) -> void:
	## Keep our local copy in sync (PowerManager is the source of truth, but this
	## keeps the interact prompt accurate without an extra query).
	power_priority = value

# ─── Interaction-system lookup (same pattern as GeneratorObject) ─────────────
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


## Called one frame after _ready() so global_position is fully resolved.
## After registration, schedule a second auto-connect attempt one more frame
## later — this guarantees the perimeter wire edges exist by the time we search,
## even if the perimeter build happened in the same frame as _ready().
func _register_wire_deferred() -> void:
	_register_with_power_manager()
	## Second-pass auto-connect: fires next frame after registration.
	## Handles the startup case where _compute_and_rebuild_wires() may not
	## have created all perimeter edges yet when _register_with_power_manager ran.
	call_deferred("_auto_connect_deferred")

## Deferred second-pass auto-connect — guaranteed to fire after all same-frame
## perimeter wire edges are registered.  Safe to call multiple times (PM dedupes).
func _auto_connect_deferred() -> void:
	if _pm_node_key == "":
		return  ## registration didn't complete — skip silently
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm != null:
		_auto_connect_to_nearby_wires(pm)

func _register_with_power_manager() -> void:
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		push_warning("WallLight id=%d: PowerManager not found in group 'power_manager' — skipping registration. global_pos=%s" % [
			get_instance_id(), str(global_position)])
		return
	var pm_status: Dictionary = pm.get_status()
	_wdbg("[LIGHT] _register_with_power_manager — id=%d pos=%s pm_wire_nodes=%d pm_edges=%d" % [
		get_instance_id(), str(global_position),
		pm_status.get("wire_nodes", -1), pm_status.get("wire_edges", -1)])

	## 1. Register a wire node at this light's world position.
	_pm_node_key = pm.register_wire_node(
		global_position,
		"consumer",
		str(get_instance_id()))

	## 2. Register as a consumer. No zone parameter in v3.x.
	pm.register_consumer(
		str(get_instance_id()),
		power_watts,
		self,
		"wall_light",
		power_priority,
		true)

	## 3. Auto-connect: scan all existing wire nodes for any within 0.75 m XZ.
	_auto_connect_to_nearby_wires(pm)

## Scans existing PM wire nodes and connects this light to the nearest one within
## AUTO_CONNECT_RADIUS that is already an edge endpoint (a live graph node).
## Falls back to any nearby node if no edge-endpoint is found.
## Safe to call multiple times — PM deduplicates edges internally.
func _auto_connect_to_nearby_wires(pm: PowerManager) -> void:
	if _pm_node_key == "":
		return
	const AUTO_CONNECT_RADIUS: float = 0.75
	## Use the wire-node's registered position (Y-normalised to 1.0) for XZ comparison,
	## not global_position directly, so snap-key math stays consistent.
	var my_pos: Vector3 = global_position   ## Y already 1.0 (LIGHT_PLACEMENT_Y)

	## Build the set of nodes that are already endpoints in at least one edge.
	## Orphan intermediate joints exist in _wire_nodes but have no edges yet;
	## connecting to them without the edge-split guarantee can leave the light
	## in an isolated 2-node zone.
	var edge_endpoint_keys: Dictionary = {}
	var edges: Array[Dictionary] = pm.get_wire_edges()
	for ed: Dictionary in edges:
		var na: String = ed.get("node_a", "")
		var nb: String = ed.get("node_b", "")
		if not na.is_empty(): edge_endpoint_keys[na] = true
		if not nb.is_empty(): edge_endpoint_keys[nb] = true

	## Two-pass search: pass 1 = connected endpoint nodes, pass 2 = any node.
	## We prefer the nearest endpoint node; only fall back to orphans if the
	## ring has no live node within radius (e.g. very first wire placed).
	var best_key:  String = ""
	var best_dist: float  = AUTO_CONNECT_RADIUS + 0.001

	for pass_idx: int in range(2):
		for wn: Dictionary in pm.get_wire_nodes():
			var wn_key: String = wn.get("key", "")
			if wn_key == _pm_node_key:
				continue
			## Only snap to ring joints — never to generator/battery/consumer/breaker nodes.
			## Generators must be manually wired by the player; auto-snapping a light to
			## a gen node would give it a private 2-node zone with no ring connection.
			if wn.get("role", "joint") != "joint":
				continue
			## Pass 0: only consider nodes with live edges.
			## Pass 1: consider any node (fallback).
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
			break   ## Found a good candidate in this pass — stop.

	if best_key != "":
		_wdbg("[LIGHT] auto-connect id=%d -> key=%s dist=%.3f" % [
			get_instance_id(), best_key, best_dist])
		var ac_eid: String = pm.register_wire_edge(_pm_node_key, best_key, null, true)
		## Stamp no_visual even if the edge already existed (pre-flag sessions).
		pm.set_wire_edge_no_visual(ac_eid)
	else:
		push_warning("[LIGHT] auto-connect id=%d: no node within %.2fm (wire_nodes=%d)" % [
			get_instance_id(), AUTO_CONNECT_RADIUS, pm.get_wire_nodes().size()])

## Called by BuildModeController after a new wire node is placed in the scene.
func notify_wire_placed(wn_key: String, wn_pos: Vector3) -> void:
	if _pm_node_key == "":
		return
	var pm: PowerManager = get_tree().get_first_node_in_group("power_manager") as PowerManager
	if pm == null:
		return
	const AUTO_CONNECT_RADIUS: float = 0.75
	var my_pos: Vector3 = global_position
	var dx: float = wn_pos.x - my_pos.x
	var dz: float = wn_pos.z - my_pos.z
	if sqrt(dx * dx + dz * dz) <= AUTO_CONNECT_RADIUS:
		var nw_eid: String = pm.register_wire_edge(_pm_node_key, wn_key, null, true)
		pm.set_wire_edge_no_visual(nw_eid)

# ─────────────────────────────────────────────────────────────────────────────
func _build_fixture() -> void:
	# ── Load GLB model ────────────────────────────────────────────────────────
	var packed: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null

	if packed != null:
		var model: Node3D = packed.instantiate() as Node3D
		if model != null:
			model.position        = Vector3(0.0, LAMP_Y_OFFSET, 0.0)
			model.rotation_degrees = Vector3(0.0, 180.0, 0.0)
			_remove_collision_recursive(model)
			add_child(model)
			_apply_matte_override(model)
	else:
		# Fallback box if model missing
		var mi: MeshInstance3D = MeshInstance3D.new()
		var bm: BoxMesh = BoxMesh.new()
		bm.size = Vector3(LAMP_W, LAMP_H, LAMP_D)
		mi.mesh = bm
		mi.position = Vector3(0.0, LAMP_Y_OFFSET, 0.0)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.18, 0.20, 1.0)
		mat.metallic     = 0.0
		mat.roughness    = 1.0
		mi.set_surface_override_material(0, mat)
		add_child(mi)

	# ── OmniLight3D — sits at lamp centre, radiates in all directions ─────────
	var omni: OmniLight3D = OmniLight3D.new()
	omni.light_color           = LIGHT_COLOR
	omni.light_energy          = LIGHT_ENERGY
	omni.omni_range            = LIGHT_RANGE
	omni.omni_attenuation      = 0.6
	omni.light_indirect_energy = 1.0
	omni.light_volumetric_fog_energy = LIGHT_VOLUMETRIC_FOG_ENERGY
	omni.shadow_enabled        = false
	omni.position              = Vector3(0.0, LAMP_Y_OFFSET, -LAMP_D * 0.5)
	## START DARK — light only turns on when PowerManager calls set_powered(true).
	omni.visible = false
	add_child(omni)
	_omni = omni

	# ── Interaction proxy — lets the player press E to set power priority ──────
	## WallLight is a plain Node3D (no body), so we attach a small StaticBody3D
	## proxy that the InteractionSystem can pick up. It forwards on_interact()
	## back to this light's on_priority_interact().
	var proxy_script: GDScript = load("res://scripts/world/power/PowerPriorityInteractable.gd")
	if proxy_script != null:
		var proxy: StaticBody3D = StaticBody3D.new()
		proxy.set_script(proxy_script)
		proxy.position = Vector3(0.0, LAMP_Y_OFFSET, 0.0)
		add_child(proxy)
		proxy.set("host", self)


# ─── Override all GLB mesh materials to be fully matte, no shadows ───────────
func _apply_matte_override(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode     = GeometryInstance3D.GI_MODE_DISABLED
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for s: int in range(mesh.get_surface_count()):
				var orig: Material = mesh.surface_get_material(s)
				var base_color: Color = Color(0.15, 0.15, 0.18, 1.0)
				if orig is StandardMaterial3D:
					base_color = (orig as StandardMaterial3D).albedo_color
				var mat: StandardMaterial3D = StandardMaterial3D.new()
				mat.albedo_color = base_color
				mat.metallic     = 0.0
				mat.roughness    = 1.0
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat.shading_mode  = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				mi.set_surface_override_material(s, mat)
	for child: Node in node.get_children():
		_apply_matte_override(child)


# ─── Strip collision nodes from GLB import ───────────────────────────────────
func _remove_collision_recursive(node: Node) -> void:
	var children: Array = []
	for child in node.get_children():
		children.append(child)
	for child in children:
		if child is CollisionShape3D or child is CollisionPolygon3D:
			child.queue_free()
		elif child is StaticBody3D or child is RigidBody3D or child is Area3D:
			child.queue_free()
		else:
			_remove_collision_recursive(child)


# ─── Static helper: ghost mesh for BuildModeController ───────────────────────
static func build_ghost_mesh() -> Mesh:
	var bm: BoxMesh = BoxMesh.new()
	bm.size = Vector3(0.2735, 0.4300, 0.1404)
	return bm
