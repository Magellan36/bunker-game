extends StaticBody3D
class_name WaterPurifier
## WaterPurifier.gd
## ─────────────────────────────────────────────────────────────────────────────
## Construct-menu tile (TILE_WATER_PURIFIER = 20, $240, Water submenu — see
## BuildModeHUD.CATEGORIES) that attaches directly onto an existing pipe run,
## same "click near a placed pipe" candidate-search BuildModeController._spawn_
## placed_object() performs (see WaterPurifierAttach.gd) — NOT a floor/wall
## snap like every other construct tile.
##
## GRAPH ROLE: occupies a normal WaterGraph node (role "purifier") splitting
## one pipe edge into two (key_a <-> purifier <-> key_b), exactly like a
## WaterPipeElbow "corner" node splits an edge — see
## WaterPurifierAttach.insert_purifier_at(). Any water reaching a consumer
## ONLY via a path that passes through a "purifier" node reads as 100% pure
## — see WaterGraph.get_unpurified_reachable_keys() / WaterManager.
## get_received_rate_mL() for the algorithm.
##
## DELETION ORDER (explicit design decision): deconstructing a purifier does
## NOT delete either adjoining pipe edge — it reverts this node's role back
## to "corner" in place (same key, same edges, water_nodes.register_node()
## is idempotent on role), frees this device's visual, and refunds $240. The
## pipe stays fully intact/connected. Any edge-deletion path (hookup
## reposition, generalized WaterManager.delete_and_refund_edge()) separately
## REFUSES to delete an edge touching a node still marked role == "purifier"
## — that guard plus this "revert first" deconstruct is what enforces
## "purifier must be removed before the pipe beneath it," without any
## cascade-delete complexity.

const RADIUS: float = 0.135   ## WaterPipeSegment.PIPE_RADIUS * 1.5
const LENGTH: float = 0.34
const COLOR_BODY: Color = Color(0.30, 0.55, 0.42, 1.0)   ## green-teal, distinct from plain grey pipe
const COLOR_BAND: Color = Color(0.85, 0.90, 0.30, 1.0)   ## yellow warning band, reads as "treatment unit"

## This purifier's own WaterGraph node key — set by WaterPurifierAttach right
## after insertion.
var node_key: String = ""

## Info panel (read-only) — same lazy-instantiate/reuse pattern as
## WaterHookup._info_ui.
var _info_ui: CanvasLayer = null

func _ready() -> void:
	collision_layer = 5
	collision_mask  = 0
	add_to_group("interactable")
	## Jul 2026 (clean-pulse VFX) — purifier nodes are registered into
	## WaterGraph WITHOUT a consumer_ref (see WaterPurifierAttach
	## .insert_purifier_at()'s register_node() call — role-only, no back-
	## reference), so WaterManager can't find this instance via
	## get_consumer_ref(). This group + node_key match is the same
	## findability pattern find_pipe_visual() already uses for
	## "water_pipe_visual" — see WaterManager._find_purifier_by_key().
	add_to_group("water_purifier")
	_build_mesh()

func _exit_tree() -> void:
	if _info_ui != null and is_instance_valid(_info_ui):
		_info_ui.queue_free()
		_info_ui = null


# ─── Deconstruct — revert to a plain corner, keep the pipe intact ────────────
## Called by BuildModeController._try_deconstruct()'s TILE_WATER_PURIFIER
## branch BEFORE this node is queue_free()'d. Reverts the graph node's role
## from "purifier" back to "corner" at the SAME key/position — edges are
## keyed by node key, not role, so both adjoining pipe segments stay exactly
## as connected as they were. No pipe refund; only this device's own $240
## construct cost is refunded (handled by the generic deconstruct path, same
## as any other placed object).
func revert_to_corner() -> void:
	if node_key.is_empty():
		return
	var wm: WaterManager = get_tree().get_first_node_in_group("water_manager") as WaterManager
	if wm == null:
		return
	var pos: Vector3 = wm.get_node_data(node_key).get("pos", global_position)
	wm.register_node(pos, "corner")
	## Spawn a plain elbow visual in this purifier's place so the corner
	## still reads as a normal pipe bend, matching every other mid-run corner.
	var elbow_script: GDScript = load("res://scripts/world/water/WaterPipeElbow.gd")
	if elbow_script != null:
		var elbow: Node3D = Node3D.new()
		elbow.set_script(elbow_script)
		var parent: Node = get_parent()
		if parent != null:
			parent.add_child(elbow)
			elbow.global_position = pos
			elbow.set("node_key", node_key)
	wm.recompute_flow_directions()


# ─── Interaction — read-only info panel (extends WaterInfoUI, mode="purifier") ─
func get_interact_prompt() -> String:
	return "[E] Check Purifier"

func on_interact() -> void:
	if _info_ui == null or not is_instance_valid(_info_ui):
		var ui_script: GDScript = load("res://scripts/ui/water/WaterInfoUI.gd")
		if ui_script == null:
			push_warning("WaterPurifier: WaterInfoUI.gd not found")
			return
		_info_ui = CanvasLayer.new()
		_info_ui.set_script(ui_script)
		_info_ui.name = "WaterInfoUI"
		get_tree().get_root().add_child(_info_ui)
		if _info_ui.has_signal("closed"):
			_info_ui.closed.connect(_on_ui_closed)

	if _info_ui.has_method("open"):
		_info_ui.open("Water Purifier", "purifier", self)

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_ui_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Public accessor mirroring WaterHookup.get_node_key() — read by
## WaterInfoUI's purifier branch to trace the upstream hookup's raw quality.
func get_node_key() -> String:
	return node_key


# ─── Clean-pulse VFX (Jul 2026) ───────────────────────────────────────────────
## Tweened expanding flat ring (Brannon's confirmed pick over a particle
## burst or particle+ring combo — reads clearly at this game's top-down
## camera angle; a TorusMesh already lies flat in the XZ plane with no
## rotation needed, same reasoning DustMotes.gd's factory functions use for
## picking the cheapest primitive that reads correctly from this camera).
## Called by WaterManager._process_purity_and_dual_arrows() — ONE call per
## purifier per recompute pass (deduped there, regardless of how many
## consumers' purity-flip attributed to this specific purifier), matching
## Brannon's "one pulse total per recompute pass" answer. WaterManager only
## decides WHEN to call this; how it looks lives entirely here, matching the
## project's existing manager/node-script separation.
const PULSE_COLOR:       Color = Color(0.55, 0.90, 1.00, 0.85)   ## light cyan-blue "clean" tint
const PULSE_DURATION:    float = 0.4
const PULSE_START_SCALE: float = 0.3
const PULSE_END_SCALE:   float = 2.5

func play_clean_pulse() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return

	var ring_mi: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = RADIUS * 1.5
	torus.outer_radius = RADIUS * 2.2
	ring_mi.mesh = torus

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color     = PULSE_COLOR
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test    = true   ## reads clearly even if it expands past nearby pipes/walls — same convention WireSegment's ghost material uses
	ring_mi.set_surface_override_material(0, mat)

	parent.add_child(ring_mi)
	ring_mi.global_position = global_position
	ring_mi.scale = Vector3.ONE * PULSE_START_SCALE

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ring_mi, "scale", Vector3.ONE * PULSE_END_SCALE, PULSE_DURATION)
	tween.tween_property(mat, "albedo_color:a", 0.0, PULSE_DURATION)
	tween.chain().tween_callback(ring_mi.queue_free)


# ─── Orientation + mesh ───────────────────────────────────────────────────────
## Rotates this purifier's body to match whichever axis (X or Z) the pipe run
## it's attached to travels along — called once, right after insertion, by
## WaterPurifierAttach.insert_purifier_at().
func orient_along(pos_a: Vector3, pos_b: Vector3) -> void:
	var dir: Vector3 = (pos_b - pos_a).normalized()
	if dir == Vector3.ZERO:
		return
	var up: Vector3 = Vector3.UP
	if absf(dir.dot(up)) > 0.999:
		up = Vector3.RIGHT
	look_at(global_position + dir, up)
	rotate_object_local(Vector3.RIGHT, PI * 0.5)

static func build_ghost_mesh() -> Mesh:
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius    = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height        = LENGTH
	cyl.radial_segments = 12
	return cyl

func _build_mesh() -> void:
	var body_mat: StandardMaterial3D = StandardMaterial3D.new()
	body_mat.albedo_color = COLOR_BODY
	body_mat.roughness    = 0.45
	body_mat.metallic     = 0.55

	var band_mat: StandardMaterial3D = StandardMaterial3D.new()
	band_mat.albedo_color = COLOR_BAND
	band_mat.roughness    = 0.60
	band_mat.metallic     = 0.20

	## NO extra local rotation on these mesh instances (Jul 2026 fix — was
	## previously rotation_degrees = Vector3(90,0,0) on both, "CylinderMesh
	## is Y-aligned; lie along local Z"). That comment's premise was wrong
	## for this node specifically: orient_along() (called once at spawn,
	## right after _build_mesh()) already rotates the WHOLE WaterPurifier
	## body via look_at()+rotate_object_local(RIGHT, 90°) — the exact same
	## sequence WaterPipeSegment.gd uses to align ITS OWN mesh instance's
	## local Y-axis along the pipe direction. Since orient_along rotates
	## this node's root (not a child mesh), the root's own local Y-axis
	## already lies along the pipe run by the time _build_mesh() runs its
	## course — a CylinderMesh child needs NO further rotation to inherit
	## that alignment. The old extra 90°-around-X on the child re-tipped the
	## already-aligned cylinder onto local Z, landing it perpendicular to
	## the pipe — exactly the reported bug.
	var body_mi: MeshInstance3D = MeshInstance3D.new()
	var body_cyl: CylinderMesh  = CylinderMesh.new()
	body_cyl.top_radius    = RADIUS
	body_cyl.bottom_radius = RADIUS
	body_cyl.height        = LENGTH
	body_cyl.radial_segments = 12
	body_mi.mesh = body_cyl
	body_mi.set_surface_override_material(0, body_mat)
	add_child(body_mi)

	var band_mi: MeshInstance3D = MeshInstance3D.new()
	var band_cyl: CylinderMesh  = CylinderMesh.new()
	band_cyl.top_radius    = RADIUS * 1.08
	band_cyl.bottom_radius = RADIUS * 1.08
	band_cyl.height        = LENGTH * 0.22
	band_cyl.radial_segments = 12
	band_mi.mesh = band_cyl
	band_mi.set_surface_override_material(0, band_mat)
	add_child(band_mi)

	body_mi.create_trimesh_collision()
	for child in body_mi.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 5
			(child as StaticBody3D).collision_mask  = 0
